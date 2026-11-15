# package.sh -- X11R6.3; assignments only.
NAME=x11r6.3
PKG=x11r63
VERSION=6.3
PKGREV=9   # -9: the RTG layer card-neutral: a card record in rtg.h, the ZZ9000 driver behind it, -card, the server as Xrtg
SUMMARY="X11R6.3 - the X Window System, with the Xrtg server"
DESC="X11R6.3 under /opt/amix/X11R6 (/usr/X11R6 links to it): the Xrtg server for RTG cards, the ZZ9000 and the Z3660 RTG (isoriano's Amiga DDX; also installed as Xzz9000 and X), the Xlib/Xt/Xaw/Xmu/Xext/SM/ICE libraries (static) and headers, xinit, xdm, twm, xterm and the standard clients, fonts, rgb, XKB data. MIT-SHM is not built (the server runs as root and could not check a client's right to a segment). X needs an FPU or the kernel's FP emulation (68LC040/68LC060: emulated and slow; on a 68LC060 the server starts in about 25 s; the 68LC040 is untested): a 68030 with a 68881/68882, or a full 68040 or 68060, runs it at full speed. Coexists with the stock X11R4/R5 in /usr/X."
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
