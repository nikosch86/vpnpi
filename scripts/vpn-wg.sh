#!/bin/bash -euf
# Bring up an obfuscated WireGuard (AmneziaWG) tunnel with a simple kill-switch,
# mirroring the OpenVPN flow in vpn.sh. Drop AmneziaWG client configs (the ones
# carrying the Jc/Jmin/Jmax/S1/S2/H1-H4 obfuscation params) into ~/vpn/wg/*.conf.
#
# Usage:
#   ./vpn-wg.sh            interactively pick a config and connect
#   ./vpn-wg.sh UNLOCK     drop the kill-switch (flush the OUTPUT chain)

WG_DIR=~/vpn/wg

if [ "${1:-}" == "UNLOCK" ]; then
  echo "!! DISABLING KILLSWITCH !!"
  echo "are you sure? (y/n)"
  read -r answ
  if [ "${answ}" == "y" ]; then
    sudo iptables -P OUTPUT ACCEPT
    sudo iptables -F OUTPUT
  fi
  exit
fi

if ! ls "${WG_DIR}"/*.conf >/dev/null 2>&1; then
  echo "no AmneziaWG configs found in ${WG_DIR} (expected *.conf), exiting!"
  exit 1
fi

echo "available AmneziaWG configs:"
for c in "${WG_DIR}"/*.conf; do
  echo "  $(basename "${c}" .conf)"
done
echo "enter config name (without .conf):"
read -r WG_NAME
WG_CONF="${WG_DIR}/${WG_NAME}.conf"
if [ ! -f "${WG_CONF}" ]; then
  echo "config ${WG_CONF} not found, exiting!"
  exit 1
fi

# resolve the peer Endpoint (host:port) so the kill-switch can let it through
WG_ENDPOINT=$(grep -iE '^[[:space:]]*Endpoint' "${WG_CONF}" | head -n1 | sed -E 's/.*=[[:space:]]*//; s/[[:space:]]//g')
WG_HOST=${WG_ENDPOINT%:*}
WG_PORT=${WG_ENDPOINT##*:}
WG_HOST_IP=$(getent hosts "${WG_HOST}" | awk '{print $1; exit}')
WG_HOST_IP=${WG_HOST_IP:-${WG_HOST}}

echo "  kill-switch: allow LAN + AmneziaWG endpoint ${WG_HOST_IP}:${WG_PORT}, drop the rest"
sudo iptables -F OUTPUT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
sudo iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
sudo iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
sudo iptables -A OUTPUT -d "${WG_HOST_IP}" -p udp --dport "${WG_PORT}" -j ACCEPT
sudo iptables -A OUTPUT -o "${WG_NAME}" -j ACCEPT
sudo iptables -P OUTPUT DROP

cleanup() {
  echo
  echo "  tearing down tunnel '${WG_NAME}'"
  sudo awg-quick down "${WG_CONF}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sudo awg-quick up "${WG_CONF}"
echo "  AmneziaWG tunnel '${WG_NAME}' up — press Ctrl-C to disconnect"
# awg-quick returns immediately; hold the tunnel (and kill-switch) until interrupted
while true; do sleep 3600; done
