# pin.sh -- which GNU tar tarball this recipe builds from, and nothing else.
# Sourced, never executed.  One URL, one sha256 (recipes/common/fetch.sh's rule).
#
# ---------------------------------------------------------------------------
# WHY 1.14
#
# registry/tar.yaml: 1.13 is the hard floor for base-256 READ compatibility --
# below it, an archive a modern tar made with a large uid/gid/size field is
# unreadable -- and 1.14 is the release the Amix archive already proved
# ([PROVEN-AMIX], Michael Parson's build), one step above the floor.  Above it
# the gnulib content climbs steeply for nothing this box needs.
#
# What it took (measured 2026-09-26; see build.sh + patches/): four small
# source patches, three justified configure seeds, the D3 passwd/group parsers
# linked into the executable, and gettimeofday from libacompat.
#
# ---------------------------------------------------------------------------
# WHY THIS URL / SCHEME  (ftp.gnu.org over http; the sha256 is the trust anchor)
#
# Verified 2026-09-26: http://ftp.gnu.org/gnu/tar/tar-1.14.tar.gz is 1485633
# bytes with the sha256 below; byte-identical from mirrors.kernel.org; and its
# detached .sig verifies ("Good signature") against gnu-keyring.gpg, DSA key
# 325F 650C 4C2B 6AD5 8807 327A 3602 B07F 55D0 C732 (Sergey Poznyakoff, the
# tar maintainer).  The signature was checked once, when the pin was taken;
# the build trusts the pin.

TAR_VERSION=1.14
TAR_URL=http://ftp.gnu.org/gnu/tar/tar-1.14.tar.gz
TAR_SHA256=c1730ca923c12b8ed87e8577ae940b0f4d84d5f2f449667a73ab83242bd787c7
TAR_SIZE=1485633
