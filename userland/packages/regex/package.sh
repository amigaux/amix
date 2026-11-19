# package.sh -- Henry Spencer's regex library, alpha3.8; assignments only.
NAME=regex
PKG=regex
VERSION=3.8
PKGREV=1
SOURCE_EPOCH=1795046400   # 2026-11-19 00:00 UTC
SUMMARY="regex 3.8 - Henry Spencer's POSIX regular expression library"
DESC="Henry Spencer's regular expression library (release alpha3.8, the 4.4BSD regex), unaltered, under /opt/amix: libregex.a and regex.h, the POSIX regcomp, regexec, regerror and regfree calls that Amix's libc lacks (it has regcmp and regex in libgen), with the manual pages regex(3) and regex(7). CDE links it."
CATEGORY=library
SET=extra
LICENSE=Spencer-94
# the repository that keeps Spencer's release (garyhouston/regex), pinned by commit
URL=https://github.com/garyhouston/regex/archive/70bc2965604b6b8aaf260049e64c708dddf85334.tar.gz
SHA256=ecc140607fc2fa4b291b182e8b482411a1dfcc13de56f016aec253e3f9009b1f
# fallback: our archive copy, https://github.com/amigaux/amix-distfiles/releases/download/regex-3.8/70bc2965604b6b8aaf260049e64c708dddf85334.tar.gz
SRCDIR=regex-70bc2965604b6b8aaf260049e64c708dddf85334
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
