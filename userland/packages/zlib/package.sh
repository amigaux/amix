# package.sh -- zlib 1.2.13 (P-31 sec 10.9); assignments only.
NAME=zlib
PKG=zlib
VERSION=1.2.13
PKGREV=6   # -6: relinked on gcc14-cross-amix b51ff39 (runtime only)
SUMMARY="zlib 1.2.13 - the deflate/inflate compression library"
DESC="zlib 1.2.13 static compression library (libz.a) plus headers, under /opt/amix. The first zlib on Amix; rsync, wget and git link it. Ships /opt/amix/bin/zlib-test, an on-box acceptance check (crc32/adler32 canaries, a multi-MB deflate/inflate round trip, and inflate of a host-produced stream)."
CATEGORY=development
SET=extra
LICENSE=Zlib
URL=https://zlib.net/fossils/zlib-1.2.13.tar.gz
SHA256=b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
