# cxxrt: libstdc++.so.6, the shared C++ runtime, as the pinned toolchain
# built it.
NAME=cxxrt
PKG=cxxrt
VERSION=1.0
PKGREV=1   # -1: gcc14-cross-amix 276ef49 (release-1.1), 1796012 bytes
SUMMARY="libstdc++.so.6: the shared C++ runtime for GCC 14 programs"
DESC="/usr/lib/libstdc++.so.6, GCC 14's C++ standard library built as a shared object: the runtime of a program linked with g++ -shared-libgcc or against a library built with g++ -shared, so that such a library and the program share one copy of the C++ runtime and exceptions thrown in one are caught in the other. It needs libamixrt.so.1 (amixrt) and the system's libc.so.1."
CATEGORY=library
SET=base
LICENSE="GPL-3.0-or-later WITH GCC-exception-3.1"
STYLE=hooks
TOOLCHAIN=gcc14
DEPENDS="amixrt"
SYSTEM_PATHS="/usr/lib/libstdc++.so.6"
# the pinned gcc14 prefix's own bytes (gcc14-pin.sh checks its sha256)
PREBUILT="/usr/lib/libstdc++.so.6"
