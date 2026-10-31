# package.sh -- CPython 3.11.18 (P-31 sec 10.9); assignments only.
NAME=python3
PKG=python3
VERSION=3.11.18
PKGREV=1
SUMMARY="Python 3.11.18"
DESC="CPython 3.11.18 for Amix, statically linked, threads through GNU Pth, with its standard library (no test suite, IDLE or Tk) under /opt/amix/lib/python3.11. /opt/amix/bin/python3 seeds hash randomisation with PYTHONHASHSEED=0 while /dev/urandom cannot be read; os.urandom and secrets need the random driver. Needs a UFS file system."
CATEGORY=language
SET=extra
LICENSE=PSF-2.0
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/python3-3.11.18/Python-3.11.18.tar.xz
URL=https://www.python.org/ftp/python/3.11.18/Python-3.11.18.tar.xz
SHA256=9120e0a653868f6e3698d36cdd99e5a58903ec9469e448f21d98f7b16d8fa290
SRCDIR=Python-3.11.18
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS="pth zlib"
