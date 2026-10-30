# package.sh -- GNU tar 1.14 (P-31 sec 10.9); assignments only.
NAME=tar
PKG=gtar
VERSION=1.14
PKGREV=7   # -7: gnulib's F_FREESP ftruncate cuts block-aligned (quirk 90)
SUMMARY="GNU tar 1.14 - base-256 aware tar"
DESC="GNU tar 1.14 beside stock SVR4 tar, which it does NOT replace (stock /usr/sbin/tar is untouched; ours wins by PATH). Reads base-256 headers from modern tars, long names, -z via gzip on PATH (install gzip). Owner names are looked up by its own /etc/passwd and /etc/group parsers, not the stock libc (D3). Installs /opt/amix/bin/tar; add /opt/amix/bin to PATH."
CATEGORY=utility
SET=extra
LICENSE=GPL-2.0-or-later
URL=http://ftp.gnu.org/gnu/tar/tar-1.14.tar.gz
SHA256=c1730ca923c12b8ed87e8577ae940b0f4d84d5f2f449667a73ab83242bd787c7
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
PATCH_STRIP=0
