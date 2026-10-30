#!/bin/sh
#
# run.sh - host regression suite for the get_mntinfo() sparse-mnttab
# robustness fix (AMIX PORT, libinst/mntinfo.c) and the fail-closed
# exit behaviour of the datastream install path.
#
# Prereq: ./build-host.sh has been run (produces the host libinst/libpkg/
# libgendb/libadm archives and build-host/bin/pkgadd).
#
# Two groups:
#   A. get_mntinfo() robustness+fail-closed, exercised directly through a
#      tiny linked-against-libinst driver (test-mntinfo) with $PKG_MNTTAB
#      pointed at controlled fixtures.
#   B. pkgadd fails CLOSED (non-zero exit) when the datastream cannot be
#      processed -- the "processes nothing, exits 0" fail-open guard.
#
# Exit 0 = all pass, 1 = a failure, 2 = could not run (build first).
#
set -u

D="$(cd "$(dirname "$0")" && pwd)"
TOP="$(cd "$D/../.." && pwd)"
OUT="${OUTDIR:-/tmp/mntinfo-robustness}"
CC="${CC:-gcc}"

for lib in libinst/libinst.a libpkg/libpkg.a libgendb/libgendb.a \
	   libadm/libadm.a version/version.o; do
	[ -f "$TOP/$lib" ] || {
		echo "SKIP: $TOP/$lib missing - run ./build-host.sh first"
		exit 2
	}
done

rm -rf "$OUT"; mkdir -p "$OUT"
fail=0

# ------------------------------------------------------------------
# A. get_mntinfo() directly
# ------------------------------------------------------------------
echo "== compiling test-mntinfo against the host libinst =="
$CC -O -std=gnu89 -fcommon -D_GNU_SOURCE -I"$TOP/sslstub" \
	-I"$TOP/hdrs" -I"$TOP/libpkg" -I"$TOP/libgendb" -I"$TOP/libinst" \
	-I"$TOP/libspmizones" -I"$TOP/libadm" \
	"$D/test-mntinfo.c" "$TOP/version/version.o" \
	-L"$TOP/libinst" -linst -L"$TOP/libpkg" -lpkg \
	-L"$TOP/libgendb" -lgendb -L"$TOP/libadm" -ladm \
	-o "$OUT/test-mntinfo" || { echo "FAIL: could not compile test-mntinfo"; exit 2; }

# Fixtures in the standard /etc/mtab shape (fsname dir type opts freq passno);
# the HOST _getmntent is glibc getmntent(3).
printf '/dev/cdrom /cdrom cdfs ro 0 0\n' > "$OUT/sparse"        # NO "/"  (miniroot shape)
printf '/dev/root / s5 rw 0 0\n/dev/cdrom /cdrom cdfs ro 0 0\n' > "$OUT/normal"  # has "/"

# The two open-failure fixtures are DELIBERATELY DISTINCT (METAL-FIX.1) -- the
# split IS the point:
#   * MISSING file (open -> ENOENT) is the fresh-install-media case: the Amix
#     miniroot ships no /etc/mnttab.  get_mntinfo() must treat it as an empty
#     table and synthesize "/" -> rc 0.  "$MISSING" is guaranteed absent (OUT
#     was just wiped and we never create it).
#   * UNREADABLE file (open -> EACCES) is a genuine fault: get_mntinfo() must
#     still fail CLOSED -> rc 1.  chmod 000 yields EACCES for the (non-root)
#     tester.  The pre-METAL-FIX.1 suite used a *missing* file for this case,
#     but a missing file now legitimately synthesizes, so the fail-closed
#     assertion must use a PERMISSION failure to keep exercising fail-closed.
MISSING="$OUT/missing"                                   # never created -> ENOENT
NOPERM="$OUT/noperm"; : > "$NOPERM"; chmod 000 "$NOPERM" # exists, unreadable -> EACCES

chk_mntinfo() {			# desc  PKG_MNTTAB-value  expected-rc
	_desc="$1"; _tab="$2"; _want="$3"
	PKG_MNTTAB="$_tab" "$OUT/test-mntinfo" >>"$OUT/log" 2>&1
	_got=$?
	if [ "$_got" = "$_want" ]; then
		echo "PASS: $_desc (rc=$_got)"
	else
		echo "FAIL: $_desc (rc=$_got, want $_want)"; fail=1
	fi
}

: > "$OUT/log"
chk_mntinfo "sparse mnttab (no root) -> root synthesized -> success"      "$OUT/sparse" 0
chk_mntinfo "normal mnttab (has root) -> success, unchanged"              "$OUT/normal" 0
chk_mntinfo "missing mnttab file (ENOENT) -> root synthesized -> success" "$MISSING"    0
if [ "$(id -u)" = 0 ]; then
	# root bypasses DAC, so chmod 000 is readable and this case can't test
	# the EACCES fail-closed path; skip rather than false-pass/false-fail.
	echo "SKIP: unreadable mnttab (EACCES) fail-closed - run as non-root to exercise"
else
	chk_mntinfo "unreadable mnttab (EACCES) -> fail closed"           "$NOPERM"     1
fi

# ------------------------------------------------------------------
# B. pkgadd fails closed on a datastream it cannot process
# ------------------------------------------------------------------
PKGADD="$TOP/build-host/bin/pkgadd"
if [ -x "$PKGADD" ]; then
	# missing datastream: pkgadd must NOT exit 0 (fail-open) -- it must
	# report and exit non-zero.  This mirrors the on-box MISSRC=99.
	"$PKGADD" -n -d "$OUT/no-such-stream.pkg" somepkg >>"$OUT/log" 2>&1
	rc=$?
	if [ "$rc" != 0 ]; then
		echo "PASS: pkgadd on a missing datastream exits non-zero (rc=$rc)"
	else
		echo "FAIL: pkgadd on a missing datastream exited 0 (fail-open)"; fail=1
	fi
else
	echo "SKIP: $PKGADD not built - B (pkgadd fail-closed) not run"
fi

echo
if [ "$fail" = 0 ]; then
	echo "== mntinfo-robustness: ALL PASS =="
else
	echo "== mntinfo-robustness: FAILURES (see $OUT/log) =="
fi
exit $fail
