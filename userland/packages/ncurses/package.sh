# package.sh -- ncurses 6.6 (P-31 sec 10.9); assignments only.
NAME=ncurses
PKG=ncurses
VERSION=6.6
PKGREV=1
SUMMARY="ncurses 6.6 - the terminal library, static"
DESC="ncurses 6.6 as static libraries (libncurses.a, libform.a, libmenu.a, libpanel.a) with their headers in /opt/amix/include/ncurses, narrow characters, reading the stock terminfo database in /usr/share/lib/terminfo. For building programs (vim links it); the stock curses and tic/tput are untouched and no programs are installed."
CATEGORY=library
SET=extra
LICENSE=X11
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/ncurses-6.6/ncurses-6.6.tar.gz
URL=https://ftp.gnu.org/gnu/ncurses/ncurses-6.6.tar.gz
SHA256=355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
