# pin.sh -- which zlib tarball this recipe builds from, and nothing else.
# Sourced, never executed.
#
# THE PIN LIVES HERE AND NOWHERE ELSE (recipes/common/fetch.sh's rule, and the
# 040-060 lane's before it): this file holds one URL and one sha256, and every
# gate reads the digest from here rather than carrying its own copy.
#
# ---------------------------------------------------------------------------
# WHY 1.2.13 AND NOT SOMETHING NEWER
#
# registry/zlib.yaml picks it and BATCH-1.md restates why:
#
#   - zlib >= 1.3.2 SILENTLY STUBS gzprintf() unless built -DZLIB_INSECURE.
#     A compression library that quietly writes nothing is exactly the failure
#     class this campaign exists to avoid, so the version boundary is drawn
#     just below it.  1.2.13 predates the change entirely.
#   - 1.2.13 is integer-only, ships its own hand-written ./configure (no
#     autotools, no gnulib wall, no config.sub), and its only assembler
#     (contrib/gcc_gvmat64/gvmat64.S) is x86-64 and never referenced by the
#     default Makefile.  build.sh removes contrib/ after extraction so the
#     no-imported-assembly gate reads a tree with no .S in it at all.
#   - It is the last release that still carries no outstanding core CVE while
#     remaining this portable.
#
# ---------------------------------------------------------------------------
# WHY THIS URL
#
# zlib.net/fossils is upstream's own permanent archive of past releases (the
# front page only carries the current one).  As with every pin here the sha256
# is what makes the bytes trustworthy -- it does so whether they arrived over
# TLS, plain HTTP or a USB stick -- so the scheme is not a security decision.
#
# Verified 2026-08-30: the tarball below is 1497445 bytes and its sha256 is the
# digest upstream publishes for zlib-1.2.13.tar.gz.

ZLIB_VERSION=1.2.13
ZLIB_URL=https://zlib.net/fossils/zlib-1.2.13.tar.gz
ZLIB_SHA256=b3a24de97a8fdbc835b9833169501030b8977031bcb54b3b3ac13740f846ab30
ZLIB_SIZE=1497445
