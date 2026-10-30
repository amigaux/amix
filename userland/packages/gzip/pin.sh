# pin.sh -- which GNU gzip tarball this recipe builds from, and nothing else.
# Sourced, never executed.  One URL, one sha256; every gate reads the digest
# from here (recipes/common/fetch.sh's rule).
#
# ---------------------------------------------------------------------------
# WHY 1.3.12
#
# registry/gzip.yaml and ROADMAP D5: the gnulib WALL for gzip is 1.4, not the
# naive 1.3.6.  1.3.12 (2007) is the last release below that wall, so it is the
# newest gzip that still cross-builds against a 1992 SVR4 libc -- free headroom
# of 20 fixes over the archived 1.3.5 [PROVEN-AMIX] build, at no portability
# cost.  >= 1.4 pulls gnulib modules that assume C99.
#
# WHAT MADE IT ACTUALLY BUILD (see build.sh + patches/):
#   - gzip's OWN deflate is pure C.  match.S (the optional hand-written inner
#     loop) is DISABLED by seeding gzip_cv_assembler=no -- the SGS '#'-as-comment
#     trap makes a mis-assembled .s a valid instruction with exit 0.
#   - gzip 1.3.12 ships gnulib helper headers (fcntl.h, time.h wrappers) meant
#     to shadow the system ones, but the cross wrapper forces its own
#     -I<sysroot>/usr/include to the FRONT, so those wrappers never win and gzip
#     sees a pure 1992 SVR4 libc.  Two small source patches fill the resulting
#     gaps (struct timespec, O_BINARY/O_NOFOLLOW/S_IRWXUGO, fileno/fchmod decls).
#
# ---------------------------------------------------------------------------
# WHY THIS URL / SCHEME
#
# ftp.gnu.org over http:// -- the same choice the patch recipe argues: the
# sha256 is what makes the bytes trustworthy, not the transport, and this repo's
# own on-box client speaks plain HTTP.
#
# Verified reachable 2026-08-30: http://ftp.gnu.org/gnu/gzip/gzip-1.3.12.tar.gz
# is 462169 bytes with the sha256 below.

GZIP_VERSION=1.3.12
GZIP_URL=http://ftp.gnu.org/gnu/gzip/gzip-1.3.12.tar.gz
GZIP_SHA256=3f565be05f7f3d1aff117c030eb7c738300510b7d098cedea796ca8e4cd587af
GZIP_SIZE=462169
