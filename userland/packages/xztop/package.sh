# package.sh -- xztop 1.1.1; assignments only.
# From amix-z3660rtg at kernel/drivers/z3660rtg/z3660rtg.pin (x11/xztop).
NAME=xztop
PKG=xztop
VERSION=1.1.1
PKGREV=1
SOURCE_EPOCH=1793491200   # 2026-11-01 00:00 UTC
SUMMARY="xztop 1.1.1 - the Z3660/ZZ9000 board's sensors in an X window"
DESC="xztop shows the Z3660/ZZ9000 board's temperatures, voltages and CPU clock in an X window, read from /dev/zz9000i, the sensors node of the z3660rtg driver package (z3660rtg-k30 or z3660rtg-k46, which must be installed and loaded). Installs /opt/amix/bin/xztop and its manual page; ztop, the same readings on a terminal, comes with the driver package. Built with GCC 14 from amix-z3660rtg and statically linked with X11R6.3's libraries (Xaw, Xmu, Xt, SM, ICE, Xext, X11), so it needs the x11r63 package's server and nothing more of it at run time; it uses floating point, so it needs an FPU."
CATEGORY=x11
SET=extra
LICENSE="MIT AND X11"
FORKPIN=kernel/drivers/z3660rtg/z3660rtg.pin
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS="x11r6.3"
BUILD_DEPENDS="x11r6.3"
