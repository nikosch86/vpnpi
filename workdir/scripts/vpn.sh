#!/bin/bash -euf
echo "choose: nordvpn pia nordvpn_xor vpn.ac"
read VPN_PROVIDER
echo "Enter VPN Username"
read vpn_user
echo "Enter VPN Password"
read -s vpn_pass
if [ "${VPN_PROVIDER}" == "vpn.ac" ]; then
  echo "  vpn.ac works differently, only one config with multiple servers in it"
  echo "  circumventing all the magic"
  pushd vpn
  echo -en "${vpn_user}\n${vpn_pass}" > auth.txt
  chmod 600 auth.txt
  popd
else
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

  TMP_DIR=$(mktemp -d)
  pushd $TMP_DIR
  cp ${VPN_ZIPFILE} . && unzip ${VPN_ZIPFILE} > /dev/null
  echo "  removing US and CA servers"
  if [ "${VPN_PROVIDER}" == "pia" ]; then
    mkdir ovpn_udp && mv *ovpn ovpn_udp/
    rm ovpn_udp/{US,CA}*ovpn
  else
    rm ovpn_udp/{us,ca}*ovpn
  fi
  sed -i 's,auth-user-pass,auth-user-pass auth.txt,g' */*ovpn
  echo -en "${vpn_user}\n${vpn_pass}" > auth.txt
  chmod 600 auth.txt
  popd
fi
sudo cp /etc/resolv.conf /etc/resolv.conf.bak
echo "  setting 8.8.8.8 nameserver"
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "  Flushing OUTPUT chain? (y/n) default: n"
read ANSW
if [ " ${ANSW}" == "y" ]; then
	sudo iptables -F OUTPUT
fi
echo "  VPN killswitch for UDP 1194/1198/1216/2231 connection and LAN"
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
sudo iptables -A OUTPUT -d 172.16.0.0/16 -j ACCEPT
sudo iptables -A OUTPUT -d 13.37.10.0/24 -j ACCEPT
sudo iptables -A OUTPUT -d 8.8.8.8 -j ACCEPT
sudo iptables -A OUTPUT -m multiport -p udp -m udp --dports 1194,1198,1214,1215,1216,2231 -j ACCEPT
# sudo iptables -A OUTPUT -p udp -m udp --dport 1198 -j ACCEPT
sudo iptables -A OUTPUT -o tun0 -j ACCEPT
sudo iptables -P OUTPUT DROP
if [ "${VPN_PROVIDER}" == "vpn.ac" ]; then
  pushd vpn
  sudo iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
  sudo openvpn --config vpn.ac-xor-tcp.ovpn
  popd
else
  pushd $TMP_DIR
  echo "reading vpn server list, randomize, pick one"
  find ovpn_udp -iname "*ovpn"  | sort -R | while read vpn; do if [ -f stop ]; then break; fi; echo; echo; echo $vpn; echo; echo; sudo openvpn --config "$vpn"; done
  # for vpn in $(ls ovpn_udp/*ovpn | sort -R); do if [ -f stop ]; then break; fi; echo; echo; echo $vpn; echo; echo; openvpn --config "$vpn"; done
  # while true; do sleeptime=$(for i in {10..30}; do echo $i; done | sort -R | head -n1); curl ifconfig.co/city; sleep $sleeptime; done
  popd
  rm -r $TMP_DIR
fi
echo "  setting original nameserver config"
sudo  mv /etc/resolv.conf.bak /etc/resolv.conf
