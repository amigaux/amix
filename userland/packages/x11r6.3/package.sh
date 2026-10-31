# package.sh -- X11R6.3; assignments only.
NAME=x11r6.3
PKG=x11r63
VERSION=6.3
PKGREV=1
SUMMARY="X11R6.3 - the X Window System, with the Xzz9000 server"
DESC="X11R6.3 under /opt/amix/X11R6 (/usr/X11R6 links to it): the Xzz9000 server for the ZZ9000 and the Z3660 RTG (isoriano's Amiga DDX), the Xlib/Xt/Xaw/Xmu/Xext/SM/ICE libraries (static) and headers, xinit, xdm, twm, xterm and the standard clients, fonts, rgb, XKB data. MIT-SHM is built in: use it only on a kernel with the shared-memory fixes. Needs an FPU: a 68030 with a 68881/68882, or a full 68040 or 68060; LC040/LC060 cannot run it until FP emulation on LC parts exists. Coexists with the stock X11R4/R5 in /usr/X."
CATEGORY=x11
SET=extra
LICENSE="X11 AND MIT"
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/x11r6.3-6.3/xc-1.tar.gz
URL=https://www.x.org/archive/X11R6.3/tars/xc-1.tar.gz
SHA256=a1324ca19ea7a46abacb5a1a72e14e944140e73449dc524403829a694ba370b8
SRCDIR=xc
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix/X11R6
SYSTEM_PATHS=/usr/X11R6
DEPENDS=""
BUILD_DEPENDS=""
