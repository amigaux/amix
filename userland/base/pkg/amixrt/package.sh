# amixrt: libamixrt.so.1, the runtime a shared library built with GCC 14
# needs, as the pinned toolchain built it.
NAME=amixrt
PKG=amixrt
VERSION=1.0
PKGREV=5   # -5: gcc14-cross-amix 276ef49 (release-1.1): libc's second wave, errno through the GOT (30948 bytes)
SOURCE_EPOCH=1795373622   # -5's published build (2026-11-22 18:53:42 UTC), kept when only docs change
SUMMARY="libamixrt.so.1: the runtime GCC 14 shared libraries need"
DESC="/usr/lib/libamixrt.so.1, the runtime a shared library built with gcc -shared (or the C++ runtime, cxxrt) NEEDs: libamixc99 built position-independent, and what libc.so.1 does not export: gettimeofday, select, truncate, realpath, interval timers, message tables, fpsetround and fpsetsticky, getmntent and getmntany, the getutx* utmpx functions, siglongjmp, sysinfo, syslog (openlog, vsyslog, setlogmask, closelog) and vfork. A failing call stores errno itself, through the GOT (before 1.0-5 the first one left a wrong errno, _cerror's address). One copy serves every program that loads such a library."
CATEGORY=library
SET=base
LICENSE="MIT AND GPL-3.0-or-later WITH GCC-exception-3.1"
STYLE=hooks
TOOLCHAIN=gcc14
ESSENTIAL=yes
SYSTEM_PATHS="/usr/lib/libamixrt.so.1"
# the pinned gcc14 prefix's own bytes (gcc14-pin.sh checks its sha256)
PREBUILT="/usr/lib/libamixrt.so.1"
