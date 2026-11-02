# package.sh -- Dropbear SSH 2026.94; assignments only.
NAME=dropbear
PKG=dropbear
VERSION=2026.94
PKGREV=1
SOURCE_EPOCH=1793520000   # this version's epoch, kept when only the build scripts change
SUMMARY="Dropbear SSH 2026.94"
DESC="Dropbear 2026.94, a small SSH server and client: dropbear, dbclient, dropbearkey and scp in one binary, with curve25519 and ML-KEM key exchange, ed25519 and RSA keys, chacha20-poly1305 and aes128-ctr. Needs /dev/urandom (the random module)."
CATEGORY=network
SET=extra
LICENSE=MIT
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/dropbear-2026.94/dropbear-2026.94.tar.bz2
URL=https://matt.ucc.asn.au/dropbear/releases/dropbear-2026.94.tar.bz2
SHA256=e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS="amix-base"
BUILD_DEPENDS=""
