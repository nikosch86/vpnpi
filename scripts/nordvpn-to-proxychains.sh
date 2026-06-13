#!/bin/bash -euf
VPN_ZIPFILE=~/vpn/nordvpn-ovpn.zip
if [ ! -f ${VPN_ZIPFILE} ]; then
  echo "zip file holding VPN configs not found, exiting!"
  exit
fi
echo "Enter VPN Username"
read vpn_user
echo "Enter VPN Password"
read -s vpn_pass
TMP_DIR=$(mktemp -d)
pushd $TMP_DIR

cp ${VPN_ZIPFILE} . && unzip ${VPN_ZIPFILE} > /dev/null
find ovpn_udp -iname "*ovpn"  | sort -R | while read vpn; do
  VPN_HOST_IP=$(grep 'remote ' ${vpn} | sed -r 's/remote ([0-9\.]+) [0-9]+/\1/g')
  echo "socks5 ${VPN_HOST_IP} 1080 ${vpn_user} ${vpn_pass}"
done

popd
rm -r ${TMP_DIR}
