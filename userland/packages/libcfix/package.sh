# package.sh -- libcfix: the stock libc.so.1 with two malloc fixes; assignments only.
NAME=libcfix
PKG=libcfix
VERSION=2.1c
PKGREV=1
SUMMARY="libc.so.1 with its realloc and huge-size malloc faults fixed"
DESC="/usr/lib/libc.so.1, Amix 2.1c's own C library, with 64 bytes changed: a realloc that sbrk refuses at the top of the heap no longer leaves the caller's block marked free, and malloc or realloc of 2 Gbyte or more returns NULL instead of shrinking the heap. Everything else is the stock file, byte for byte. Built from amix-system at its pin; replaces core's copy, which stays recorded under core."
CATEGORY=library
SET=base
LICENSE="LicenseRef-Amix-System"
STYLE=hooks
TOOLCHAIN=period
ESSENTIAL=yes
SYSTEM_PATHS="/usr/lib/libc.so.1"
# the stock file and the bytes it must have after the stage hook patches it
STOCK_PATCHED="/usr/lib/libc.so.1=f57f624ba2d325dee8839adb5c7fcf1559f7a11ecdc21d870dcd78f75831cf52"
# a fixed time stamp, so the installer can lay its copy with the pkgmap's time
SOURCE_EPOCH=1793836800
DEPENDS=""
BUILD_DEPENDS=""
