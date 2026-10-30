# package.sh -- GNU coreutils 5.2.1 (P-31 sec 10.9); assignments only.
NAME=coreutils
PKG=coreutil
VERSION=5.2.1
PKGREV=4   # -4: man pages in /opt/amix/man/<sect>/<name> + whatis.d (docs/man-pages.md)
SUMMARY="GNU coreutils 5.2.1"
DESC="GNU coreutils 5.2.1 beside the stock SVR4 tools, which it does NOT replace: GNU ls, cp, mv, rm, sort, date, df, du, install, stat and the rest, plus md5sum and sha1sum (the box has no content checksum otherwise). Installs /opt/amix/bin; add /opt/amix/bin to PATH."
CATEGORY=utility
SET=extra
LICENSE=GPL-2.0-or-later
URL=https://ftp.gnu.org/gnu/coreutils/coreutils-5.2.1.tar.gz
SHA256=9f7662c4dff1c9cb957588830ca4ab83dede538c113283723b8190bddcc85bf9
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
