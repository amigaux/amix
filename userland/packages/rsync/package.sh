# package.sh -- rsync 3.1.3; assignments only.
NAME=rsync
PKG=rsync
VERSION=3.1.3
PKGREV=5   # -5: gcc14-cross-amix 9d13dcd (release-1.1): fold-mem-offsets off
SOURCE_EPOCH=1795177562   # -5's published build (2026-11-20 12:26:02 UTC), kept when only docs change
SUMMARY="rsync 3.1.3"
DESC="rsync 3.1.3, the incremental file-transfer tool, speaking protocol 31 to modern peers: client over a remote shell (-e) or to an rsync daemon (rsync://), and the daemon itself (--daemon). Installs /opt/amix/bin/rsync; add /opt/amix/bin to PATH."
CATEGORY=network
SET=extra
LICENSE=GPL-3.0-or-later
URL=https://download.samba.org/pub/rsync/src/rsync-3.1.3.tar.gz
SHA256=55cc554efec5fdaad70de921cd5a5eeb6c29a95524c715f3bbf849235b0800c0
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
