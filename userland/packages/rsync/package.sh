# package.sh -- rsync 3.1.3 (P-31 sec 10.9); assignments only.
NAME=rsync
PKG=rsync
VERSION=3.1.3
PKGREV=2   # -2: man pages in /opt/amix/man/<sect>/<name> + whatis.d (docs/man-pages.md)
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
