#!/bin/bash -eu
# Build OpenVPN with the Tunnelblick/clayface XOR "scramble" obfuscation patch.
# The patch was never merged upstream, so an obfuscated client must be built from
# source. We use the pre-patched release tarballs from luzrain/openvpn-xorpatch,
# which track current OpenVPN (the old bundled 2.4.7 no longer builds against the
# OpenSSL 3.0 shipped on current Raspberry Pi OS).
#   https://github.com/luzrain/openvpn-xorpatch

OPENVPN_VERSION="2.6.20"
TARBALL="openvpn-${OPENVPN_VERSION}.tar.gz"
URL="https://github.com/luzrain/openvpn-xorpatch/releases/download/v${OPENVPN_VERSION}/${TARBALL}"
SHA256="0d8e93a08eb89b752accaa7d9a398c1a63f7aabb8e8f54e03adcd8d73b2c8690"

if [ ! -f "${TARBALL}" ]; then
  curl -fsSL -o "${TARBALL}" "${URL}"
fi
echo "${SHA256}  ${TARBALL}" | sha256sum -c -

tar xzf "${TARBALL}"
cd "openvpn-${OPENVPN_VERSION}"
./configure --prefix=/usr
make
sudo make install
