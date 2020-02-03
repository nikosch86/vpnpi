#!/bin/bash -eu
unzip -u openvpn*zip
cd openvpn-*/
cp ../openvpn-*-xorpatch.tar.gz .
tar xf openvpn-*-xorpatch.tar.gz

for i in *diff; do patch -t -p1 -i $i; done

./configure --prefix=/usr
make
sudo make install
