# package.sh -- less 704 (P-31 sec 10.9); assignments only.
NAME=less
PKG=less
VERSION=704
PKGREV=8   # -8: man pages in /opt/amix/man/<sect>/<name> + whatis.d (docs/man-pages.md)
SUMMARY="less 704 - the backward-scrolling pager"
DESC="less 704, the pager with backward scroll and incremental search -- stock Amix has only more/pg/page. Installs /opt/amix/bin/{less,lesskey,lessecho}. Uses the SVR4 regcmp regex (libgen) and the termcap API via libcurses; links nothing outside the stock system libraries. Add /opt/amix/bin to PATH to use it."
CATEGORY=utility
SET=extra
LICENSE="GPL-3.0-or-later OR BSD-2-Clause"
URL=https://www.greenwoodsoftware.com/less/less-704.tar.gz
SHA256=20a0b0a2bb2525fa53c7eee9beb854b4c9cf172eabb209af7020743547bfe9fb
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
PATCH_STRIP=0
