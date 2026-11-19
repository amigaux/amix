# package.sh -- X11R6.3; assignments only.
NAME=x11r6.3
PKG=x11r63
VERSION=6.3
PKGREV=12  # -12: gcc14-cross-amix c806d49 (release-1.1): library names first in .dynstr; -11: xinit catches SIGTERM (patch 34); -10: the VA2000 card driver (xrtg-amix at its pin, FORKDIRS) under the RTG layer; the X configuration files are conffiles
SUMMARY="X11R6.3 - the X Window System, with the Xrtg server"
DESC="X11R6.3 under /opt/amix/X11R6 (/usr/X11R6 links to it): the Xrtg server for RTG cards, the ZZ9000, the Z3660 RTG and the VA2000 (isoriano's Amiga DDX, Antti Sokero's VA2000 driver; also installed as Xzz9000 and X), the Xlib/Xt/Xaw/Xmu/Xext/SM/ICE libraries (static) and headers, xinit, xdm, twm, xterm and the standard clients, fonts, rgb, XKB data. MIT-SHM is not built (the server runs as root and could not check a client's right to a segment). X needs an FPU or the kernel's FP emulation (68LC040/68LC060: emulated and slow; on a 68LC060 the server starts in about 25 s; the 68LC040 is untested): a 68030 with a 68881/68882, or a full 68040 or 68060, runs it at full speed. Coexists with the stock X11R4/R5 in /usr/X."
CATEGORY=x11
SET=extra
LICENSE="X11 AND MIT"
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/x11r6.3-6.3/xc-1.tar.gz
URL=https://www.x.org/archive/X11R6.3/tars/xc-1.tar.gz
SHA256=a1324ca19ea7a46abacb5a1a72e14e944140e73449dc524403829a694ba370b8
SRCDIR=xc
# the VA2000 card directory, from the xrtg-amix fork at the pin (patch 32 builds it)
FORKDIRS="userland/packages/x11r6.3/xrtg-amix.pin x11r6.3/hw/amix/rtg/va2000 programs/Xserver/hw/amix/rtg/va2000"
# the configuration an admin edits: an upgrade keeps an edited one and puts the new default
# beside it as .new (README, Configuration files).  Their defaults are byte-identical to 6.3-8's.
CONFFILES="/etc/profile.d/x11r63.sh \
    /opt/amix/X11R6/lib/X11/xdm/Xaccess \
    /opt/amix/X11R6/lib/X11/xdm/Xresources \
    /opt/amix/X11R6/lib/X11/xdm/Xservers \
    /opt/amix/X11R6/lib/X11/xdm/Xsession \
    /opt/amix/X11R6/lib/X11/xdm/Xsetup_0 \
    /opt/amix/X11R6/lib/X11/xdm/xdm-config \
    /opt/amix/X11R6/lib/X11/xdm/GiveConsole \
    /opt/amix/X11R6/lib/X11/xdm/TakeConsole \
    /opt/amix/X11R6/lib/X11/xinit/xinitrc \
    /opt/amix/X11R6/lib/X11/twm/system.twmrc \
    /opt/amix/X11R6/lib/X11/app-defaults/Chooser \
    /opt/amix/X11R6/lib/X11/app-defaults/XClock \
    /opt/amix/X11R6/lib/X11/app-defaults/XTerm \
    /opt/amix/X11R6/lib/X11/fonts/misc/fonts.alias \
    /opt/amix/X11R6/lib/X11/fonts/75dpi/fonts.alias \
    /opt/amix/X11R6/lib/X11/fonts/100dpi/fonts.alias \
    /opt/amix/X11R6/lib/X11/rstart/config \
    /opt/amix/X11R6/lib/X11/rstart/contexts/default \
    /opt/amix/X11R6/lib/X11/rstart/contexts/x11r6 \
    /opt/amix/X11R6/lib/X11/xserver/SecurityPolicy"
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix/X11R6
SYSTEM_PATHS=/usr/X11R6
DEPENDS=""
BUILD_DEPENDS=""
