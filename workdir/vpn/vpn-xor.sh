#!/bin/bash
unzip openvpn*zip
cd openvpn-*/
mv ../openvpn-*-xorpatch.tar.gz .

for i in *diff; do patch -p1 -i $i; done

./configure --prefix=/usr
make
make install
