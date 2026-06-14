# VM test harness

Provisions a throwaway **Debian 12** VM with libvirt + cloud-init and runs
`bootstrap.yml` + `config.yml` against it, then asserts the results. Raspberry Pi
OS is Debian-bookworm based, so this exercises almost everything except the parts
that need real hardware.

## Requirements

Already present on the dev box: `libvirt` (the `default` NAT network active and
your user in the `libvirt` group), `virt-install`, `qemu-img`, `ansible`, plus
KVM (`/dev/kvm`). No Vagrant needed.

## Run

```
bash test/run.sh           # download image (first run), boot VM, provision, verify
bash test/run.sh destroy   # tear the VM down
```

The VM is left running on success so you can poke at it:

```
ssh -i test/.ssh/id_ed25519 pi@<ip>
```

## What it covers

- apt package installs (hostapd, dnsmasq, openvpn, wireguard, …)
- the **OpenVPN 2.6.20 XOR build** from source (`vpn/vpn-xor.sh`)
- the **AmneziaWG DKMS module** build + `amneziawg-tools`
- `/etc` config deploys and helper-script deploys
- hostapd unmasked + enabled

## What it can't cover (needs a real Pi)

- hostapd actually serving an AP (no wireless interface in the VM — it's enabled
  but not started)
- the dhcpcd wpa_supplicant hook (skipped where dhcpcd isn't present)
- a live OpenVPN / AmneziaWG tunnel end-to-end

## Notes

- It's an **amd64** VM, so the OpenVPN/DKMS builds prove the code compiles, not
  that the arm64 Pi packages resolve. The `amnezia` PPA `arm64` availability and
  the `raspberrypi-kernel-headers` package are only validated on the Pi.
- VM-specific overrides live in `vm-vars.yml`; the deb822 deb-src enablement is
  done in `cloud-init.user-data` (the playbook handles the Pi's legacy
  `sources.list`).
- `.cache/` (base image) and `.ssh/` (test keypair) are git-ignored.
