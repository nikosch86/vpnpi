# VM test harness

Provisions a throwaway **Debian 12** VM with qemu + cloud-init and runs
`bootstrap.yml` + `config.yml` against it, then asserts the results. Raspberry Pi
OS is Debian-bookworm based, so this exercises almost everything except the parts
that need real hardware.

`run.sh` defaults the guest architecture to the **host's**, so it runs
hardware-accelerated and on the right arch wherever you are — including an
**arm64 guest natively on an Apple Silicon Mac** (or an arm64 Linux box), which
mirrors a Raspberry Pi closely *and* runs fast.

## Requirements

**Linux**

- `qemu` (`qemu-system-x86_64` and/or `qemu-system-aarch64`), `qemu-utils`
  (`qemu-img`), `xorriso` (or `genisoimage`), `curl`, `ansible`
- KVM (`/dev/kvm`) for native speed
- the `qemu-efi-aarch64` firmware package for any arm64 guest
  (`sudo apt install qemu-efi-aarch64`)

**macOS (Apple Silicon)**

- `brew install qemu xorriso ansible` — Homebrew's qemu ships the edk2 firmware
  and is signed for HVF, so arm64 guests run natively with no extra setup.
  (If `xorriso` is absent the built-in `hdiutil` is used to build the seed.)

No libvirt or Vagrant needed — `run.sh` invokes qemu directly as your user.

## Run

```
bash test/run.sh                # guest = host arch, hardware-accelerated
ARCH=arm64 bash test/run.sh     # force an arm64 guest
bash test/run.sh destroy        # tear the VM down
```

The first run downloads the base cloud image (cached per-arch under `.cache/`).
The VM is left running on success so you can poke at it:

```
ssh -p 2222 -i test/.ssh/id_ed25519 pi@127.0.0.1
```

Tunables via env: `ARCH`, `ACCEL` (`kvm`/`hvf`/`tcg`), `CPU`, `SSH_PORT`,
`RAM_MB`, `VCPUS`, `DISK_GB`.

## Native vs. emulated

`run.sh` picks acceleration automatically from host vs. guest arch:

| Host | Default guest | Accel | Speed |
|------|---------------|-------|-------|
| x86_64 Linux | amd64 | KVM | fast |
| Apple Silicon macOS | arm64 | HVF | fast, **Pi-like arch** |
| arm64 Linux | arm64 | KVM | fast, **Pi-like arch** |
| x86_64 Linux + `ARCH=arm64` | arm64 | TCG | slow (emulated) |

An **arm64 guest** (`cortex-a72`, i.e. a Pi 4; the Pi 5 is `cortex-a76`) mirrors a
Raspberry Pi and additionally validates what an amd64 run can't:

- the **arm64** apt packages resolve — notably that the **amnezia PPA** has
  `arm64` builds for `amneziawg`/`amneziawg-tools`
- the **OpenVPN 2.6.20 XOR** source and the **AmneziaWG DKMS** module compile on
  arm64

On a native arm host this is fast. Forcing an arm64 guest on an x86 box has no
hardware virtualisation available, so it runs under qemu's **TCG** software
emulation: it boots and provisions correctly but the CPU-heavy from-source builds
take **tens of minutes** rather than seconds — a worthwhile pre-Pi smoke test,
not something for every change.

## What it covers

- apt package installs (hostapd, dnsmasq, openvpn, wireguard, amneziawg-tools, …)
- the **OpenVPN 2.6.20 XOR build** from source (`vpn/vpn-xor.sh`)
- the **AmneziaWG DKMS module** build + `amneziawg-tools`
- `/etc` config deploys and helper-script deploys
- hostapd unmasked + enabled

## What it can't cover (needs a real Pi)

- hostapd actually serving an AP (no wireless interface in the VM — it's enabled
  but not started)
- the dhcpcd wpa_supplicant hook (skipped where dhcpcd isn't present)
- a live OpenVPN / AmneziaWG tunnel end-to-end
- the `raspberrypi-kernel-headers` package and the running Pi kernel (the VM
  builds DKMS against the cloud kernel; see `vm-vars.yml`)

## Notes

- VM-specific overrides live in `vm-vars.yml` (it pins the DKMS kernel headers to
  the VM's running kernel instead of the Pi's `raspberrypi-kernel-headers`). The
  deb822 deb-src enablement is done in `cloud-init.user-data`; the playbook
  handles the Pi's legacy `sources.list`.
- `.cache/` (base images, per-run disk, EFI varstore) and `.ssh/` (test keypair)
  are git-ignored.
