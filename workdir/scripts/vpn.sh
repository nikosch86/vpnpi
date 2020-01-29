#!/bin/bash
echo "choose: nordvpn pia nordvpn_xor"
read VPN_PROVIDER
if [ "${VPN_PROVIDER}" == "nordvpn" ]; then
  VPN_ZIPFILE=~/vpn/nordvpn-ovpn.zip
elif [ "${VPN_PROVIDER}" == "nordvpn_xor" ]; then
  VPN_ZIPFILE=~/vpn/nordvpn-ovpn_xor.zip
elif [ "${VPN_PROVIDER}" == "pia" ]; then
  VPN_ZIPFILE=~/vpn/pia-ovpn.zip
else
  echo "invalid choice ${VPN_PROVIDER}"
  exit
fi
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
echo "removing US and CA servers"
if [ "${VPN_PROVIDER}" == "pia" ]; then
  mkdir ovpn_udp && mv *ovpn ovpn_udp/
  rm ovpn_udp/{US,CA}*ovpn
else
  rm ovpn_udp/{us,ca}*ovpn
fi
sed -i 's,auth-user-pass,auth-user-pass auth.txt,g' */*ovpn
echo -en "${vpn_user}\n${vpn_pass}" > auth.txt
chmod 600 auth.txt
cp /etc/resolv.conf /etc/resolv.conf.bak
echo "setting 8.8.8.8 nameserver"
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "Flushing OUTPUT chain? (y/n) default: n"
read ANSW
if [ " ${ANSW}" == "y" ]; then
	iptables -F OUTPUT
fi
echo "VPN killswitch for UDP 1194/1198/1216/2231 connection and 192.168.0.0/16 LAN"
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -d 172.16.0.0/16 -j ACCEPT
iptables -A OUTPUT -d 13.37.10.0/24 -j ACCEPT
iptables -A OUTPUT -d 8.8.8.8 -j ACCEPT
iptables -A OUTPUT -m multiport -p udp -m udp --dports 1194,1198,1214,1215,1216,2231 -j ACCEPT
# iptables -A OUTPUT -p udp -m udp --dport 1198 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT
iptables -P OUTPUT DROP
echo "reading vpn server list, randomize, pick one"
find ovpn_udp -iname "*ovpn"  | sort -R | while read vpn; do if [ -f stop ]; then break; fi; echo; echo; echo $vpn; echo; echo; openvpn --config "$vpn"; done
# for vpn in $(ls ovpn_udp/*ovpn | sort -R); do if [ -f stop ]; then break; fi; echo; echo; echo $vpn; echo; echo; openvpn --config "$vpn"; done
# while true; do sleeptime=$(for i in {10..30}; do echo $i; done | sort -R | head -n1); curl ifconfig.co/city; sleep $sleeptime; done
popd
rm -r $TMP_DIR
echo "setting original nameserver config"
mv /etc/resolv.conf.bak /etc/resolv.conf

