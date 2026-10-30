# package.sh -- GNU make 3.81 (P-31 sec 10.9); assignments only.
NAME=make
PKG=make
VERSION=3.81
PKGREV=7   # -7: relinked on gcc14-cross-amix b51ff39 (runtime only)
SUMMARY="GNU make 3.81"
DESC="GNU make 3.81 beside the stock SVR4 make, which it does NOT replace (stock /usr/ccs/bin/make is untouched; ours wins by PATH). Pattern rules, VPATH, \$(shell), \$(eval), order-only prerequisites, -j with the jobserver. make -l only warns (no load average on Amix). Installs /opt/amix/bin/make; add /opt/amix/bin to PATH."
CATEGORY=development
SET=extra
LICENSE=GPL-2.0-or-later
URL=http://ftp.gnu.org/gnu/make/make-3.81.tar.gz
SHA256=16b77de9f013bcd536b7bc1efbe314223aedfe250f9063e33cbb4dfd347215a2
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
PATCH_STRIP=0
