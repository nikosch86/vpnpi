#!/usr/bin/env bash
# Boot a throwaway Debian 12 VM with qemu (KVM) + a NoCloud cloud-init seed and
# run the vpnpi playbooks against it, then verify everything checkable without Pi
# hardware: package installs, the OpenVPN 2.6.20 XOR build, the AmneziaWG DKMS
# module, the /etc config deploys and the helper scripts. The WiFi access point
# and live VPN tunnels still need a real Pi.
#
#   bash test/run.sh           # create the VM, provision it, verify
#   bash test/run.sh destroy   # tear the VM down again
#
# Runs qemu directly as your user. Tunables via env: SSH_PORT, RAM_MB, VCPUS, DISK_GB.
set -euo pipefail

VM_NAME="${VM_NAME:-vpnpi-test}"
SSH_PORT="${SSH_PORT:-2222}"
RAM_MB="${RAM_MB:-2048}"
VCPUS="${VCPUS:-2}"
DISK_GB="${DISK_GB:-16}"
MAC="${MAC:-52:54:00:be:ef:01}"
IMG_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
CACHE="${HERE}/.cache"
KEYDIR="${HERE}/.ssh"
KEY="${KEYDIR}/id_ed25519"
BASE="${CACHE}/debian-12-genericcloud-amd64.qcow2"
DISK="${CACHE}/${VM_NAME}.qcow2"
SEED="${CACHE}/${VM_NAME}-seed.iso"
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

if [ "${1:-}" = "destroy" ]; then
  echo "destroying ${VM_NAME}..."
  stop_vm
  rm -f "${DISK}" "${SEED}" "${CONSOLE}"
  echo "done."
  exit 0
fi

mkdir -p "${CACHE}" "${KEYDIR}"

# test SSH keypair
if [ ! -f "${KEY}" ]; then
  ssh-keygen -t ed25519 -N "" -f "${KEY}" -C vpnpi-test >/dev/null
fi
PUBKEY="$(cat "${KEY}.pub")"

# base cloud image (cached)
if [ ! -f "${BASE}" ]; then
  echo "downloading Debian 12 genericcloud image..."
  curl -fSL -o "${BASE}" "${IMG_URL}"
fi

# fresh disk from a per-run copy of the base image
echo "preparing a fresh ${VM_NAME}..."
stop_vm
cp "${BASE}" "${DISK}"
qemu-img resize "${DISK}" "${DISK_GB}G" >/dev/null

# NoCloud seed ISO (label cidata): user creation + DHCP-by-MAC network config
SEEDDIR="${CACHE}/seed"
rm -rf "${SEEDDIR}"
mkdir -p "${SEEDDIR}"
sed "s|__SSH_PUBKEY__|${PUBKEY}|" "${HERE}/cloud-init.user-data" > "${SEEDDIR}/user-data"
# fail loudly if the rendered user-data is not valid YAML
python3 -c "import yaml; yaml.safe_load(open('${SEEDDIR}/user-data'))" \
  || { echo "ERROR: rendered user-data is not valid YAML" >&2; exit 1; }
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
( cd "${SEEDDIR}" && xorriso -as mkisofs -output "${SEED}" -volid cidata \
    -joliet -rock user-data meta-data network-config >/dev/null 2>&1 )

echo "booting VM (qemu/kvm)..."
qemu-system-x86_64 \
  -name "${VM_NAME}" \
  -enable-kvm -cpu host -m "${RAM_MB}" -smp "${VCPUS}" \
  -drive "file=${DISK},format=qcow2,if=virtio" \
  -cdrom "${SEED}" \
  -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
  -device "virtio-net-pci,netdev=net0,mac=${MAC}" \
  -serial "file:${CONSOLE}" \
  -display none \
  -daemonize -pidfile "${PIDFILE}"

# wait for cloud-init to create pi + sshd to accept the key
echo "waiting for SSH on 127.0.0.1:${SSH_PORT} (cloud-init runs on first boot)..."
ok=""
for _ in $(seq 1 90); do
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
echo "ALL DONE — VM '${VM_NAME}' left running (pid $(cat "${PIDFILE}"))"
echo "  ssh -p ${SSH_PORT} -i ${KEY} pi@127.0.0.1"
echo "  bash test/run.sh destroy   # tear it down"
