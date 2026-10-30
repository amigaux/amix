# package.sh -- GNU patch 2.5.9 (P-31 sec 10.9); assignments only.
NAME=patch
PKG=patch
VERSION=2.5.9
PKGREV=6   # -6: relinked on gcc14-cross-amix b51ff39 (runtime only)
SUMMARY="GNU patch 2.5.9 - apply a diff to an original"
DESC="GNU patch 2.5.9 applies unified, context and ed-format diffs. Supersedes the 1990 Larry Wall patch 12u4 in /usr/public/bin. Installs /usr/local/bin/patch plus a /usr/bin/patch symlink."
CATEGORY=development
SET=extra
LICENSE=GPL-2.0-or-later
URL=http://ftp.gnu.org/gnu/patch/patch-2.5.9.tar.gz
SHA256=ecb5c6469d732bcf01d6ec1afe9e64f1668caba5bfdb103c28d7f537ba3cdb8a
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/usr/local
DEPENDS=""
BUILD_DEPENDS=""
