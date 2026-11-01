# package.sh -- libzz9k 2.9.1, the ZZ9000 SDK v2 host library for Amix; assignments only.
# The SDK's host API (src/, verbatim) with the Amix branch (patches/0001) and the pool and
# fallback calls (src/zz9k_amix.c); GPL-3.0-or-later.  The reasons are in README.md.
NAME=libzz9k
PKG=libzz9k
VERSION=2.9.1
PKGREV=2   # -2: AUTO takes only a board's OK (zlib decides the rest); ZZ9K_INFLATE_BOARD_MIN
SUMMARY="libzz9k - ZZ9000-family board services for programs, with a software fallback"
DESC="libzz9k.a and its headers: the ZZ9000 SDK v2 host API over the kernel's /dev/zz9ksvcN channels (zz9ksvc), a pool of the boards with their capability catalogues, and zz9k_inflate, which decompresses raw deflate, zlib and gzip on a board that offers it and with zlib otherwise, the same bytes either way. Link -lzz9k -lz. GPL-3.0-or-later: a program that links it is GPL-3.0-or-later as a whole. Ships /opt/amix/bin/zz9k-test, the on-box check."
CATEGORY=library
SET=extra
LICENSE=GPL-3.0-or-later
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS="zlib"
