# pin.sh -- which GNU make tarball this recipe builds from, and nothing else.
# Sourced, never executed.  One URL, one sha256 (recipes/common/fetch.sh's rule).
#
# ---------------------------------------------------------------------------
# WHY 3.81
#
# registry/make.yaml: the gnulib/C99 wall for GNU make is 4.3 (D5), so 4.2.1 is
# the true ceiling; 3.81 is one release above the [PROVEN-AMIX] 3.80 build and
# already has what modern Makefiles use (order-only prerequisites, $(eval)).
#
# ---------------------------------------------------------------------------
# WHY THIS URL / SCHEME  (ftp.gnu.org over http; the sha256 is the trust anchor)
#
# Verified 2026-09-26: http://ftp.gnu.org/gnu/make/make-3.81.tar.gz is 1564560
# bytes with the sha256 below; byte-identical from mirrors.kernel.org; and its
# detached .sig verifies ("Good signature") against gnu-keyring.gpg, DSA key
# 3D25 54F0 A153 38AB 9AF1 BB9D 96B0 4715 6338 B6D4 (Paul Smith, the make
# maintainer).  Checked once, when the pin was taken; the build trusts the pin.

MAKE_VERSION=3.81
MAKE_URL=http://ftp.gnu.org/gnu/make/make-3.81.tar.gz
MAKE_SHA256=16b77de9f013bcd536b7bc1efbe314223aedfe250f9063e33cbb4dfd347215a2
MAKE_SIZE=1564560
