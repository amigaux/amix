#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# run.sh - regression for a datastream that fails to unpack.  ds_init's
# error returns freed the header and kept the pointer, and the command's
# cleanup (ds_close) freed it again: pkgtrans, pkgtrans -i and pkginfo -d
# aborted with a double free (glibc: "double free detected", rc 134)
# instead of reporting the failure.  Cuts the smoke test's jutoy.pkg
# inside its first cpio archive, so cpio exits non-zero, and checks that
# each command reports the failure and exits 1 with no abort.  Called
# from build-host.sh after the smoke test that makes jutoy.pkg.
set -u
TOP="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$TOP/build-host/bin"
SRC="$TOP/build-host/smoke/out/jutoy.pkg"
W="$TOP/build-host/badstream"

fail() { echo "bad stream: FAIL - $*"; exit 1; }
[ -f "$SRC" ] || fail "no $SRC (the smoke test makes it)"
rm -rf "${W:?}"
mkdir -p "$W"
# the header block plus 188 bytes of the first cpio member
head -c 700 "$SRC" > "$W/cut.pkg"

n=0
check() {	# check NAME CMD...: rc 1, the unpack error, no abort
	local name=$1 rc
	shift
	"$@" > "$W/$name.out" 2>&1
	rc=$?
	grep -q 'double free\|Aborted\|corrupted' "$W/$name.out" &&
		fail "$name: the heap check fired: $(tr '\n' ' ' < "$W/$name.out")"
	[ "$rc" = 1 ] || fail "$name: rc $rc, want 1: $(tr '\n' ' ' < "$W/$name.out")"
	grep -q 'attempt to process datastream failed' "$W/$name.out" ||
		fail "$name: no unpack error: $(tr '\n' ' ' < "$W/$name.out")"
	n=$((n + 1))
}
mkdir -p "$W/o1" "$W/o2"
check pkgtrans-i "$BIN/pkgtrans" -i "$W/cut.pkg" "$W/o1" all
check pkgtrans "$BIN/pkgtrans" "$W/cut.pkg" "$W/o2" all
check pkginfo-d "$BIN/pkginfo" -d "$W/cut.pkg"
[ -z "$(find "$W/o1" "$W/o2" -mindepth 1)" ] || fail "a cut stream left files in the spool"
echo "bad stream:        OK ($n commands report a cut datastream, rc 1, no double free)"
