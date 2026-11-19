# package.sh -- GNU gzip 1.3.12; assignments only.
NAME=gzip
PKG=gzip
VERSION=1.3.12
PKGREV=10   # -10: gcc14-cross-amix c806d49 (release-1.1): library names first in .dynstr
SUMMARY="GNU gzip 1.3.12 - the .gz compressor"
DESC="GNU gzip 1.3.12 reads and writes the universal .gz (deflate) format, which stock Amix cannot -- stock ships only 1985 LZW compress/.Z. Installs /opt/amix/bin/{gzip,gunzip,zcat}. Integer-only; links nothing outside the stock libc. Add /opt/amix/bin to PATH to use it."
CATEGORY=archive
SET=extra
LICENSE=GPL-2.0-or-later
URL=http://ftp.gnu.org/gnu/gzip/gzip-1.3.12.tar.gz
SHA256=3f565be05f7f3d1aff117c030eb7c738300510b7d098cedea796ca8e4cd587af
STYLE=configure
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
PATCH_STRIP=0
