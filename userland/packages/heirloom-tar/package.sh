# package.sh -- Heirloom Toolchest tar (070715); assignments only.
NAME=heirloom-tar
PKG=heirtar
VERSION=070715
PKGREV=1
SOURCE_EPOCH=1793491200   # 2026-11-01 00:00 UTC, the time stamp of this version
SUMMARY="Heirloom tar: the system tar, replacing the 1992 /usr/sbin/tar"
DESC="Heirloom Toolchest tar (070715), Gunnar Ritter's SVR4-style tar from Unix 32V, installed as /usr/sbin/tar in place of the stock tar, with the stock keys and /etc/default/tar. Root extracts ustar and GNU archives whose owner or group the box lacks (the stock tar crashed on them): names that exist here give their local ids, as stock does, others the archive's numeric ids. Reads GNU long names, large uids and sizes, pax headers, and gzip or bzip2 compressed archives (with gzip or bzip2 on PATH). Not removable: there is no stock copy to put back."
CATEGORY=archive
SET=base
LICENSE="LicenseRef-Caldera AND Zlib AND MIT"
URL=https://downloads.sourceforge.net/project/heirloom/heirloom/070715/heirloom-070715.tar.bz2
SHA256=eb33f70bcc019b1d0e0a41f1d7552d45c57a16272e4e1c48634ec3e44496a30f
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/heirloom-070715/heirloom-070715.tar.bz2
SRCDIR=heirloom-070715
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
SYSTEM_PATHS="/usr/sbin/tar"
MAN_REPLACES="/usr/sbin/tar 1 heirloom-tar"
ESSENTIAL=yes
DEPENDS=""
BUILD_DEPENDS=""
