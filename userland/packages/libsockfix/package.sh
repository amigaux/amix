# package.sh -- libsockfix: the stock socket libraries without their per-socket heap leak; assignments only.
NAME=libsockfix
PKG=libsockfx
VERSION=1.0
PKGREV=1
SUMMARY="libsocket.so without the heap it lost on every socket and accept"
DESC="/usr/lib/libsockhost.so and /usr/lib/libsockdns.so, Amix 2.1's socket libraries (libsocket.so is a link to one of them), with 55 bytes changed in each so that a socket(), accept() or DNS lookup on a reused descriptor number frees the buffer the library kept for the last socket of that number. The stock library lost about 200 bytes each time, 4.4 Kbyte for a UNIX-domain socket, until the program exited: an X server kept by dtlogin grew by about 1 Mbyte a day. Everything else is the stock file, byte for byte. Removing the package puts the stock files and the stock link back."
CATEGORY=library
SET=base
LICENSE="LicenseRef-Amix-System"
STYLE=hooks
TOOLCHAIN=period
ESSENTIAL=no
PREFIX=/opt/amix
SYSTEM_PATHS="/usr/lib/libsockhost.so /usr/lib/libsockdns.so"
# the stock files and the bytes each must have after the stage hook patches it
STOCK_PATCHED="/usr/lib/libsockhost.so=f37c4fac4081ae3fda44e2ba02dcd3f7b1fc8945254c94d22e7085bf1453fba9 /usr/lib/libsockdns.so=798b1ae661d9288a66e913d7873df6c0cc9c55eea72170c416c65e1e8bd74832"
# a fixed time stamp: the time of this version
SOURCE_EPOCH=1795824000   # 2026-11-28 00:00 UTC
# postinstall links libsocket.so to the fixed file of its variant; preremove puts the stock files back
INSTALL_SCRIPTS="postinstall preremove"
# the scripts' installf and removef are apkg's (the stock installf faults)
DEPENDS="apkgeng"
BUILD_DEPENDS=""
