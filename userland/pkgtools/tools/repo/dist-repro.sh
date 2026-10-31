#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# dist-repro.sh -- `make repro-check`: APKG and APKGENG are the same bytes
# however they are built (P-38 S4.2, "in out/ and reproducible").  Runs
# `make dist` twice: in this checkout, and in a `git archive` of HEAD's
# userland/pkgtools unpacked at another path, built under umask 077 with
# another SOURCE_DATE_EPOCH in the environment (which the roll must
# ignore).  Every binary is compiled afresh in the copy.  The datastreams
# must be identical.  Uncommitted changes in this checkout make the two
# differ; commit first.
#
# Work: $DIST_REPRO_WORK (default <amix>/tmp/dist-repro), kept for a look.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TOP="$(cd "$HERE/../.." && pwd)"
W="${DIST_REPRO_WORK:-$TOP/tmp/dist-repro}"

if [ -n "$(git -C "$HERE" status --porcelain -- . 2>/dev/null)" ]; then
	echo "dist-repro: warning: userland/pkgtools has uncommitted changes; the copy is HEAD's" >&2
fi
rm -rf "$W"; mkdir -p "$W/copy"
git -C "$TOP" archive HEAD userland/pkgtools | tar -x -C "$W/copy"

echo "== dist A: this checkout"
make -C "$HERE" dist OUT="$W/outA" STAGE="$W/stA" > "$W/A.log" 2>&1 ||
	{ echo "dist-repro: make dist failed here (see $W/A.log)" >&2; exit 1; }
echo "== dist B: $W/copy, umask 077, SOURCE_DATE_EPOCH=1"
( umask 077; SOURCE_DATE_EPOCH=1 make -C "$W/copy/userland/pkgtools" dist \
	OUT="$W/outB" STAGE="$W/stB" ) > "$W/B.log" 2>&1 ||
	{ echo "dist-repro: make dist failed in the copy (see $W/B.log)" >&2; exit 1; }

rc=0
n=0
for a in "$W"/outA/*.pkg; do
	f=$(basename "$a")
	n=$((n + 1))
	if cmp -s "$a" "$W/outB/$f"; then
		echo "  same  $f $(md5sum < "$a" | cut -d' ' -f1)"
	else
		echo "  DIFF  $f"
		rc=1
	fi
done
[ "$n" -eq 2 ] || { echo "dist-repro: expected 2 packages, found $n" >&2; rc=1; }
[ $rc -eq 0 ] && echo "dist-repro: OK, both rolls are the same bytes" ||
	echo "dist-repro: FAIL (work: $W)"
exit $rc
