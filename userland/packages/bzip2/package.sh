# package.sh -- bzip2 1.0.8 (P-31 sec 10.9); assignments only.
NAME=bzip2
PKG=bzip2
VERSION=1.0.8
PKGREV=2   # -2: relinked on gcc14-cross-amix b51ff39 (runtime only)
SUMMARY="bzip2 1.0.8"
DESC="bzip2 1.0.8 block-sorting compressor: bzip2, bunzip2, bzcat, bzip2recover, the bzgrep/bzmore/bzdiff wrappers, and libbz2.a with bzlib.h. Installs under /opt/amix; add /opt/amix/bin to PATH."
CATEGORY=archive
SET=extra
LICENSE=bzip2-1.0.6
URL=https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
SHA256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269
STYLE=make
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
