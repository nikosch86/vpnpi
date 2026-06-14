#!/usr/bin/env bash
# Boot a throwaway Debian 12 VM with qemu + a NoCloud cloud-init seed and run the
# vpnpi playbooks against it, then verify everything checkable without Pi
# hardware: package installs, the OpenVPN 2.6.20 XOR build, the AmneziaWG DKMS
# module, the /etc config deploys and the helper scripts. The WiFi access point
# and live VPN tunnels still need a real Pi.
#
#   bash test/run.sh                # VM matching the host arch (hardware-accelerated)
#   ARCH=arm64 bash test/run.sh     # force an arm64 VM (native on arm hosts, else emulated)
#   bash test/run.sh destroy        # tear the VM down again
#
# ARCH defaults to the host architecture, so the run is hardware-accelerated and
# the right arch wherever it runs:
#   * x86_64 Linux        -> amd64 guest, KVM
#   * Apple Silicon macOS -> arm64 guest, HVF  (native, fast -- mirrors a Pi)
#   * arm64 Linux         -> arm64 guest, KVM
# Forcing the non-host arch (e.g. ARCH=arm64 on an x86 box) runs under qemu's TCG
# software emulation instead: it boots and provisions correctly but the
# from-source builds take tens of minutes. The arm64 guest is what proves the
# arm64 apt packages resolve (notably the amnezia PPA arm64 builds) and that the
# OpenVPN/DKMS sources compile on arm64 -- the gaps an amd64 run can't cover.
#
# Runs qemu directly as your user. Tunables via env: ARCH, ACCEL, CPU, SSH_PORT,
# RAM_MB, VCPUS, DISK_GB.
#
# Requirements:
#   * Linux: qemu (qemu-system-x86_64 / qemu-system-aarch64), qemu-utils, xorriso
#     (or genisoimage), ansible; KVM for native speed; qemu-efi-aarch64 for arm64.
#   * macOS: `brew install qemu xorriso ansible` (qemu ships the edk2 firmware and
#     is signed for HVF; hdiutil is used for the seed if xorriso is absent).
set -euo pipefail

# --- host detection & guest/accel selection -------------------------------
HOST_OS="$(uname -s)"
case "$(uname -m)" in
  x86_64|amd64)  HOST_ARCH=amd64 ;;
  aarch64|arm64) HOST_ARCH=arm64 ;;
  *)             HOST_ARCH="$(uname -m)" ;;
esac

ARCH="${ARCH:-${HOST_ARCH}}"
case "${ARCH}" in
  amd64|arm64) ;;
  *) echo "ERROR: unsupported ARCH='${ARCH}' (use amd64 or arm64)" >&2; exit 1 ;;
esac

# Native when the guest arch matches the host: use hardware virtualisation (KVM
# on Linux, HVF on macOS). Otherwise fall back to TCG software emulation.
if [ "${ARCH}" = "${HOST_ARCH}" ]; then
  if [ "${HOST_OS}" = "Darwin" ]; then ACCEL_DEFAULT=hvf; else ACCEL_DEFAULT=kvm; fi
  CPU_DEFAULT=host
  BOOT_TRIES_DEFAULT=90
else
  ACCEL_DEFAULT=tcg
  # a concrete model for emulation; cortex-a72 mirrors the Pi 4 (the Pi 5 is a76)
  if [ "${ARCH}" = arm64 ]; then CPU_DEFAULT=cortex-a72; else CPU_DEFAULT=max; fi
  BOOT_TRIES_DEFAULT=180
fi

ACCEL="${ACCEL:-${ACCEL_DEFAULT}}"
CPU="${CPU:-${CPU_DEFAULT}}"
BOOT_TRIES="${BOOT_TRIES:-${BOOT_TRIES_DEFAULT}}"

# arm64 guests carry the heavy from-source builds, so default them more headroom
if [ "${ARCH}" = arm64 ]; then
  RAM_MB="${RAM_MB:-4096}"; VCPUS="${VCPUS:-4}"
else
  RAM_MB="${RAM_MB:-2048}"; VCPUS="${VCPUS:-2}"
fi

VM_NAME="${VM_NAME:-vpnpi-test}"
SSH_PORT="${SSH_PORT:-2222}"
DISK_GB="${DISK_GB:-16}"
MAC="${MAC:-52:54:00:be:ef:01}"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-${ARCH}.qcow2"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
CACHE="${HERE}/.cache"
KEYDIR="${HERE}/.ssh"
KEY="${KEYDIR}/id_ed25519"
BASE="${CACHE}/debian-12-genericcloud-${ARCH}.qcow2"
DISK="${CACHE}/${VM_NAME}.qcow2"
SEED="${CACHE}/${VM_NAME}-seed.iso"
EFIVARS="${CACHE}/${VM_NAME}-efivars.fd"
CONSOLE="${CACHE}/${VM_NAME}-console.log"
PIDFILE="${CACHE}/${VM_NAME}.pid"
INVENTORY="${CACHE}/inventory"

ssh_vm() { ssh -p "${SSH_PORT}" -i "${KEY}" -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o BatchMode=yes -o ConnectTimeout=5 "pi@127.0.0.1" "$@"; }

stop_vm() {
  if [ -f "${PIDFILE}" ]; then
    kill "$(cat "${PIDFILE}")" 2>/dev/null || true
    rm -f "${PIDFILE}"
  fi
}

# Build the NoCloud seed ISO (volume label cidata) with whatever tool is present.
make_seed_iso() {
  local out="$1" dir="$2"
  if command -v xorriso >/dev/null 2>&1; then
    ( cd "${dir}" && xorriso -as mkisofs -output "${out}" -volid cidata -joliet -rock \
        user-data meta-data network-config >/dev/null 2>&1 )
  elif command -v genisoimage >/dev/null 2>&1; then
    ( cd "${dir}" && genisoimage -output "${out}" -volid cidata -joliet -rock \
        user-data meta-data network-config >/dev/null 2>&1 )
  elif command -v mkisofs >/dev/null 2>&1; then
    ( cd "${dir}" && mkisofs -output "${out}" -volid cidata -joliet -rock \
        user-data meta-data network-config >/dev/null 2>&1 )
  elif command -v hdiutil >/dev/null 2>&1; then
    # macOS without xorriso: the volume name becomes the cidata label the
    # NoCloud datasource looks for.
    hdiutil makehybrid -quiet -iso -joliet -default-volume-name cidata -o "${out}" "${dir}"
  else
    echo "ERROR: need an ISO builder for the cloud-init seed." >&2
    echo "  Linux: apt install xorriso   (or genisoimage)" >&2
    echo "  macOS: brew install xorriso   (or rely on the built-in hdiutil)" >&2
    exit 1
  fi
}

if [ "${1:-}" = "destroy" ]; then
  echo "destroying ${VM_NAME}..."
  stop_vm
  rm -f "${DISK}" "${SEED}" "${EFIVARS}" "${CONSOLE}"
  echo "done."
  exit 0
fi

mkdir -p "${CACHE}" "${KEYDIR}"

# test SSH keypair
if [ ! -f "${KEY}" ]; then
  ssh-keygen -t ed25519 -N "" -f "${KEY}" -C vpnpi-test >/dev/null
fi
PUBKEY="$(cat "${KEY}.pub")"

# base cloud image (cached, per-arch)
if [ ! -f "${BASE}" ]; then
  echo "downloading Debian 12 genericcloud ${ARCH} image..."
  curl -fSL -o "${BASE}" "${IMG_URL}"
fi

# fresh disk from a per-run copy of the base image
echo "preparing a fresh ${VM_NAME} (${ARCH})..."
stop_vm
cp "${BASE}" "${DISK}"
qemu-img resize "${DISK}" "${DISK_GB}G" >/dev/null

# NoCloud seed ISO (label cidata): user creation + DHCP-by-MAC network config
SEEDDIR="${CACHE}/seed"
rm -rf "${SEEDDIR}"
mkdir -p "${SEEDDIR}"
sed "s|__SSH_PUBKEY__|${PUBKEY}|" "${HERE}/cloud-init.user-data" > "${SEEDDIR}/user-data"
# fail loudly if the rendered user-data is not valid YAML (best-effort: only when
# python3 + PyYAML are available, e.g. not on a bare macOS without the module)
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  python3 -c "import yaml; yaml.safe_load(open('${SEEDDIR}/user-data'))" \
    || { echo "ERROR: rendered user-data is not valid YAML" >&2; exit 1; }
fi
cat > "${SEEDDIR}/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF
cat > "${SEEDDIR}/network-config" <<EOF
version: 2
ethernets:
  primary:
    match:
      macaddress: "${MAC}"
    dhcp4: true
EOF
make_seed_iso "${SEED}" "${SEEDDIR}"

# --- assemble the qemu command --------------------------------------------
# The cloud-init seed is a plain virtio disk (cloud-init's NoCloud datasource
# finds it by the cidata label), so the same handling works on the arm64 'virt'
# machine, which has no IDE cdrom bus.
case "${ACCEL}" in
  kvm) QEMU_ACCEL=(-enable-kvm) ;;
  hvf) QEMU_ACCEL=(-accel hvf) ;;
  tcg) QEMU_ACCEL=(-accel "tcg,thread=multi") ;;
  *)   echo "ERROR: unknown ACCEL='${ACCEL}' (use kvm, hvf or tcg)" >&2; exit 1 ;;
esac

QEMU_ARGS=(
  "${QEMU_ACCEL[@]}"
  -name "${VM_NAME}"
  -m "${RAM_MB}" -smp "${VCPUS}" -cpu "${CPU}"
  -drive "file=${DISK},format=qcow2,if=virtio"
  -drive "file=${SEED},format=raw,if=virtio"
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22"
  -device "virtio-net-pci,netdev=net0,mac=${MAC}"
  -serial "file:${CONSOLE}"
  -display none
  -daemonize -pidfile "${PIDFILE}"
)

if [ "${ARCH}" = arm64 ]; then
  QEMU_BIN=qemu-system-aarch64
  # arm64 'virt' boots via UEFI. HVF on Apple Silicon needs the high memory map
  # disabled for a clean boot.
  machine=virt
  [ "${ACCEL}" = hvf ] && machine="virt,highmem=off"
  QEMU_ARGS+=(-machine "${machine}")

  # Find UEFI firmware. Prefer a CODE+VARS pflash pair (persistent vars); search
  # the common Linux package locations and the macOS Homebrew prefix.
  brew_share=""
  command -v brew >/dev/null 2>&1 && brew_share="$(brew --prefix 2>/dev/null)/share/qemu"
  efi_code=""; efi_vars_tpl=""
  for pair in \
    "/usr/share/AAVMF/AAVMF_CODE.fd|/usr/share/AAVMF/AAVMF_VARS.fd" \
    "/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw|/usr/share/edk2/aarch64/vars-template-pflash.raw" \
    "${brew_share:-/nonexistent}/edk2-aarch64-code.fd|${brew_share:-/nonexistent}/edk2-arm-vars.fd" \
    "/opt/homebrew/share/qemu/edk2-aarch64-code.fd|/opt/homebrew/share/qemu/edk2-arm-vars.fd" \
    "/usr/local/share/qemu/edk2-aarch64-code.fd|/usr/local/share/qemu/edk2-arm-vars.fd"; do
    c="${pair%%|*}"; v="${pair##*|}"
    if [ -f "${c}" ] && [ -f "${v}" ]; then efi_code="${c}"; efi_vars_tpl="${v}"; break; fi
  done
  if [ -n "${efi_code}" ]; then
    rm -f "${EFIVARS}"; cp "${efi_vars_tpl}" "${EFIVARS}"
    QEMU_ARGS+=(-drive "if=pflash,format=raw,readonly=on,file=${efi_code}")
    QEMU_ARGS+=(-drive "if=pflash,format=raw,file=${EFIVARS}")
  else
    # fall back to a single code-only firmware image via -bios
    qemu_efi=""
    for f in /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/edk2/aarch64/QEMU_EFI.fd \
             "${brew_share:-/nonexistent}/edk2-aarch64-code.fd" \
             /opt/homebrew/share/qemu/edk2-aarch64-code.fd; do
      if [ -f "${f}" ]; then qemu_efi="${f}"; break; fi
    done
    if [ -z "${qemu_efi}" ]; then
      echo "ERROR: arm64 UEFI firmware not found. Install it with:" >&2
      echo "  Linux: sudo apt install qemu-efi-aarch64" >&2
      echo "  macOS: brew install qemu   (ships the edk2 firmware)" >&2
      exit 1
    fi
    QEMU_ARGS+=(-bios "${qemu_efi}")
  fi
else
  QEMU_BIN=qemu-system-x86_64
fi

echo "booting VM (qemu: ${ARCH} guest on ${HOST_ARCH} ${HOST_OS}, accel=${ACCEL}, cpu=${CPU})..."
"${QEMU_BIN}" "${QEMU_ARGS[@]}"

# wait for cloud-init to create pi + sshd to accept the key
echo "waiting for SSH on 127.0.0.1:${SSH_PORT} (cloud-init runs on first boot)..."
ok=""
for _ in $(seq 1 "${BOOT_TRIES}"); do
  if ssh_vm true 2>/dev/null; then ok=1; break; fi
  sleep 5
done
if [ -z "${ok}" ]; then
  echo "ERROR: SSH never came up. Last console output:" >&2
  tail -n 60 "${CONSOLE}" 2>/dev/null || true
  exit 1
fi

cat > "${INVENTORY}" <<EOF
vpnpi-test ansible_host=127.0.0.1 ansible_port=${SSH_PORT} ansible_user=pi ansible_connection=ssh ansible_ssh_private_key_file=${KEY}
EOF

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_SSH_ARGS="-o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
cd "${REPO}"

echo "=== bootstrap.yml ==="
ansible-playbook -i "${INVENTORY}" bootstrap.yml

echo "=== config.yml ==="
ansible-playbook -i "${INVENTORY}" -e @test/vm-vars.yml config.yml

echo "=== verify.yml ==="
ansible-playbook -i "${INVENTORY}" test/verify.yml

echo
echo "ALL DONE (${ARCH}, accel=${ACCEL}) — VM '${VM_NAME}' left running (pid $(cat "${PIDFILE}"))"
echo "  ssh -p ${SSH_PORT} -i ${KEY} pi@127.0.0.1"
echo "  bash test/run.sh destroy   # tear it down"
