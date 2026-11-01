# amixrt: libamixrt.so.1, the runtime a shared library built with GCC 14
# needs, as the pinned toolchain built it.
NAME=amixrt
PKG=amixrt
VERSION=1.0
PKGREV=1
SUMMARY="libamixrt.so.1: the runtime GCC 14 shared libraries need"
DESC="/usr/lib/libamixrt.so.1, the runtime a shared library built with gcc -shared NEEDs: libamixc99 built position-independent, and gettimeofday, select, truncate, realpath, interval timers and message tables, which libc.so.1 does not export. One copy serves every program that loads such a library."
CATEGORY=library
SET=base
LICENSE="MIT AND GPL-3.0-or-later WITH GCC-exception-3.1"
STYLE=hooks
TOOLCHAIN=gcc14
ESSENTIAL=yes
SYSTEM_PATHS="/usr/lib/libamixrt.so.1"
# the pinned gcc14 prefix's own bytes (gcc14-pin.sh checks its sha256)
PREBUILT="/usr/lib/libamixrt.so.1"
