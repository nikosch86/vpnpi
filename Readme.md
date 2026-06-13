# bootstrap a RaspberryPi to become a WiFi Hotspot prepared for VPN

Standalone Ansible deployment that prepares a RaspberryPi to act as a WiFi
hotspot routed through an obfuscated VPN. Runs straight from this directory —
no Docker required.

## Requirements

- Ansible on the control machine (`pipx install ansible`, or your distro package)
- SSH access to the Pi as the `pi` user with passwordless `sudo`

## Usage

Bootstrap the host (installs the python3 prerequisites the apt tasks need):

```
ansible-playbook -i <IP>, bootstrap.yml
```

Run the configuration:

```
ansible-playbook -i <IP>, config.yml
```

The trailing comma in `-i <IP>,` makes Ansible treat the argument as an inline
inventory list rather than a path to an inventory file.

## VPN options

Two obfuscated VPN clients are provisioned; both apply a simple iptables
kill-switch so traffic only leaves through the tunnel.

### OpenVPN with XOR scramble

`config.yml` builds OpenVPN from source with the Tunnelblick/clayface XOR
"scramble" patch (`vpn/vpn-xor.sh`), pinned to a current patched release
(2.6.x) — the old 2.4.7 no longer compiles against the OpenSSL 3.0 on current
Raspberry Pi OS. Provider `.ovpn` configs live in `vpn/`; connect with:

```
~/scripts/vpn.sh
```

### AmneziaWG (obfuscated WireGuard)

`config.yml` installs [AmneziaWG](https://docs.amnezia.org/documentation/amnezia-wg/),
a WireGuard fork that keeps the crypto but masks the transport to defeat DPI.
Drop AmneziaWG client `.conf` files (with the `Jc/Jmin/Jmax/S1/S2/H1-H4`
obfuscation parameters) into `~/vpn/wg/`, then connect with:

```
~/scripts/vpn-wg.sh
```

> AmneziaWG only talks to a matching AmneziaWG peer, so you need an AmneziaWG
> endpoint (typically self-hosted) — a plain WireGuard provider config will not
> obfuscate.
>
> The kernel module is built via DKMS and needs matching kernel headers
> (`raspberrypi-kernel-headers`). If DKMS can't build it for your running
> kernel, use the userspace implementation
> [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go) instead.

Run `~/scripts/vpn.sh UNLOCK` (or `vpn-wg.sh UNLOCK`) to drop the kill-switch.
