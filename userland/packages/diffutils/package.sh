# package.sh -- GNU diffutils 2.8.1; assignments only.
NAME=diffutils
PKG=diffutil
VERSION=2.8.1
PKGREV=4   # -4: gcc14-cross-amix 3446533, every program gains the library-constructor runner
SUMMARY="GNU diffutils 2.8.1"
DESC="GNU diffutils 2.8.1 beside the stock SVR4 diff tools, which it does NOT replace: diff with unified (-u) and recursive (-r) output, diff3, sdiff and cmp. Installs /opt/amix/bin/{diff,diff3,sdiff,cmp}; add /opt/amix/bin to PATH."
CATEGORY=utility
SET=extra
LICENSE=GPL-2.0-or-later
URL=https://ftp.gnu.org/gnu/diffutils/diffutils-2.8.1.tar.gz
SHA256=c5001748b069224dd98bf1bb9ee877321c7de8b332c8aad5af3e2a7372d23f5a
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
