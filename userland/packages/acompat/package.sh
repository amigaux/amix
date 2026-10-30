# package.sh -- acompat 0.1, the libamixcompat library (P-31 sec 10.9); assignments only.
# Our own source (src/, include/), BSD-2-Clause; no upstream tarball.
NAME=acompat
PKG=acompat
VERSION=0.1
PKGREV=8   # -8: man pages in /opt/amix/man/<sect>/<name> + whatis.d (docs/man-pages.md)
SUMMARY="libacompat - missing-libc shim for Amix ports"
DESC="libamixcompat, the static library and headers for the libc surface Amix lacks: long-long snprintf/vsnprintf, setenv/unsetenv, strcasecmp/strncasecmp, mkstemp, usleep, gettimeofday. Link -lacompat."
CATEGORY=library
SET=extra
LICENSE=BSD-2-Clause
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/usr/local
DEPENDS=""
BUILD_DEPENDS=""
