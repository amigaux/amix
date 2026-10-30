# package.sh -- GNU grep 2.5.1a (P-31 sec 10.9); assignments only.
NAME=grep
PKG=grep
VERSION=2.5.1a
PKGREV=8   # -8: man pages in /opt/amix/man/<sect>/<name> + whatis.d (docs/man-pages.md)
SUMMARY="GNU grep 2.5.1a - recursive/color grep"
DESC="GNU grep 2.5.1a with recursive -r, -o, --color and reliable -E over stock SVR4 grep, which it does NOT replace (stock /usr/bin/grep is untouched; ours wins by PATH). Installs /opt/amix/bin/{grep,egrep,fgrep}. Carries its own GNU regex; strcasecmp comes from the toolchain runtime libamixc99 (GCC 14 build). Add /opt/amix/bin to PATH to use it."
CATEGORY=utility
SET=extra
LICENSE=GPL-2.0-or-later
URL=http://ftp.gnu.org/gnu/grep/grep-2.5.1a.tar.gz
SHA256=65f48c187932cd7984af4f2b6cd23e1a9b7d82c7778c1e9bc54c932a28d1bdff
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
PATCH_STRIP=0
