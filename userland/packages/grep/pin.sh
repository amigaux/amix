# pin.sh -- which GNU grep tarball this recipe builds from, and nothing else.
# Sourced, never executed.  One URL, one sha256 (recipes/common/fetch.sh's rule).
#
# ---------------------------------------------------------------------------
# WHY 2.5.1a
#
# registry/grep.yaml: the last GPLv2 grep, and -- the deciding factor -- it
# carries its OWN regex (src/regex.c via the GNU re_compile_pattern/re_search
# API).  The box has NO POSIX regcomp/regexec at all (D8, REGEX-NONE), so a grep
# that expects the system to provide them is unbuildable no matter how portable
# the rest of it is.  >= 2.6 crosses the gnulib wall and moves regex to gnulib's
# C99-assuming copy.
#
# The blocker note's warning is real and this recipe answers it structurally:
# `--with-included-regex` FORCES src/regex.c into LIBOBJS rather than letting
# configure "find" a partial system regex -- a compile test succeeds under gcc
# 2.7's implicit declarations even when the symbol is absent (PORTING.md 4).
# build.sh then asserts regex.o is actually in the link.
#
# Measured extras (see build.sh + patches/): grep needs strcasecmp, which lives
# in libacompat (absent from libc, declared by no SVR4 header); S_ISSOCK, which
# SVR4 leaves undefined though S_IFSOCK exists; and one missing isdir()
# declaration in gnulib's savedir.c.  Two small source patches and -lacompat.
#
# ---------------------------------------------------------------------------
# WHY THIS URL / SCHEME  (ftp.gnu.org over http; the sha256 is the trust anchor)
#
# Verified reachable 2026-08-30: http://ftp.gnu.org/gnu/grep/grep-2.5.1a.tar.gz
# is 630975 bytes with the sha256 below.

GREP_VERSION=2.5.1a
GREP_URL=http://ftp.gnu.org/gnu/grep/grep-2.5.1a.tar.gz
GREP_SHA256=65f48c187932cd7984af4f2b6cd23e1a9b7d82c7778c1e9bc54c932a28d1bdff
GREP_SIZE=630975
