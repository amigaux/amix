# package.sh -- X11R6 contrib clients (xeyes, xedit); assignments only.
NAME=x11contrib
PKG=x11contrb
VERSION=6.0
PKGREV=1
SOURCE_EPOCH=1795305600   # 2026-11-22 00:00 UTC
SUMMARY="X11R6 contrib clients - xeyes and xedit"
DESC="Clients from the X11R6 contrib distribution, which X11R6.3 left out of its core tree: xeyes (the eyes that follow the pointer) and xedit (the Athena-widget text editor), under /opt/amix/X11R6 with their manual pages and xedit's app-defaults. Built with GCC 14 and statically linked with X11R6.3's libraries (Xaw, Xmu, Xt, SM, ICE, Xext, X11), so they need the x11r63 package's server and nothing more of it at run time; xeyes uses floating point, so it needs an FPU. xload is not built: Amix cannot give it a true load average (README)."
CATEGORY=x11
SET=extra
LICENSE="X11 AND HPND-DEC"
URL=https://www.x.org/archive/X11R6/contrib-2.tar.gz
SHA256=b9cfa1b7d94d124556a6af217e4a0eeece049f4026550cdf5ac93cdef196d1a0
SRCDIR=contrib
# xedit's resources, which an admin edits (as x11r6.3's app-defaults)
CONFFILES="/opt/amix/X11R6/lib/X11/app-defaults/Xedit"
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix/X11R6
DEPENDS="x11r6.3"
BUILD_DEPENDS="x11r6.3"
