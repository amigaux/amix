# pin.sh -- which GNU patch tarball this recipe builds from, and nothing else.
# Sourced, never executed.
#
# THE PIN LIVES HERE AND NOWHERE ELSE.  build.sh reads these three values; no
# gate carries its own copy of the digest.  The 040-060 lane learned this the
# expensive way -- a check whose expected value exists in several places is a
# check that will eventually disagree with itself -- and the rule it wrote down
# is the rule here: bumping the version is an edit to this file, plus prose
# wherever prose quotes it.
#
# ---------------------------------------------------------------------------
# WHY 2.5.9 AND NOT SOMETHING NEWER
#
# ROADMAP.md picks it, and building it confirmed the reasoning:
#
#   - It ships NO config.sub and NO config.guess, so there is no triplet table
#     to be out of date about m68k-cbm-sysv4.  --host is used only to pick the
#     tool prefix and to set cross_compiling.
#   - Its configure is autoconf 2.57 with SEVEN AC_TRY_RUN sites, every one of
#     which already carries a cross-compilation fallback.  Nothing had to be
#     seeded except one that was actively wrong (see build.sh).
#   - It is entirely C89, and -- measured, not assumed -- it is SELF-CONTAINED:
#     it bundles its own strncasecmp and uses mktemp(3) plus its own O_EXCL
#     create rather than mkstemp.  It needs nothing from libacompat.
#   - Everything past 2.7.6 is behind the gnulib wall (D5), and autoreconf is
#     banned outright: regenerating configure with autoconf >= 2.70 switches to
#     a C11-probing AC_PROG_CC and loses the port.  Ship the shipped configure.
#
# ---------------------------------------------------------------------------
# WHY PLAIN HTTP
#
# ftp.gnu.org over http:// is the fetch path, not https://.  It is not a
# security decision -- the sha256 below is what makes the bytes trustworthy,
# and it does so whether they arrived over TLS, FTP or a USB stick.  It is a
# consistency decision: this repo's own on-box client speaks plain HTTP/1.0
# because the target has no usable TLS, and a recipe that can only be fetched
# by a modern host is a recipe with an undeclared dependency on one.
#
# Verified reachable 2026-08-28: http://ftp.gnu.org/gnu/patch/patch-2.5.9.tar.gz
# returns 200, Content-Length 201926, Last-Modified Tue 01 Jun 2004.

PATCH_VERSION=2.5.9
PATCH_URL=http://ftp.gnu.org/gnu/patch/patch-2.5.9.tar.gz
PATCH_SHA256=ecb5c6469d732bcf01d6ec1afe9e64f1668caba5bfdb103c28d7f537ba3cdb8a
PATCH_SIZE=201926
