# package.sh -- GNU Pth 2.0.7 (P-31 sec 10.9); assignments only.
NAME=pth
PKG=pth
VERSION=2.0.7
PKGREV=1
SUMMARY="GNU Pth 2.0.7 - user-space threads and a pthread library"
DESC="GNU Pth 2.0.7, cooperative user-space threads for Amix (which has no kernel threads): libpth.a with pth.h, and libpthread.a with a pthread.h emulation for porting POSIX-threads programs. Static, under /opt/amix. Python and SDL2 link it."
CATEGORY=library
SET=extra
LICENSE=LGPL-2.1-or-later
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/pth-2.0.7/pth-2.0.7.tar.gz
URL=https://ftp.gnu.org/gnu/pth/pth-2.0.7.tar.gz
SHA256=72353660c5a2caafd601b20e12e75d865fd88f6cf1a088b306a3963f0bc77232
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
PATCH_STRIP=1
