# package.sh -- acompat 0.1, the libamixcompat library; assignments only.
# Our own source (src/, include/), BSD-2-Clause; no upstream tarball.
NAME=acompat
PKG=acompat
VERSION=0.1
PKGREV=10   # -10: gcc14-cross-amix c806d49 (release-1.1): library names first in .dynstr
SOURCE_EPOCH=1795097888   # -10's published build (2026-11-19 14:18:08 UTC), kept when only docs change
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
