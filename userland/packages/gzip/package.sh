# package.sh -- GNU gzip 1.3.12 (P-31 sec 10.9); assignments only.
NAME=gzip
PKG=gzip
VERSION=1.3.12
PKGREV=8   # -8: man pages in /opt/amix/man/<sect>/<name> + whatis.d (docs/man-pages.md)
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
