#!/bin/sh
# cuts-selftest.sh -- the kernel make dist builds and the kernel package it
# rolls agree: cuts/CURRENT names a cut of record (cut.sh and seven sums),
# and pkg/kernel-k30-m/pin.sh pins that build id and every one of its sums.
# Reads files only; builds nothing.
#
# MIT licence, see LICENSE in kernel/k30.
set -eu

K=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "cuts-selftest: FAIL: $*" >&2; exit 1; }

read -r KB < "$K/cuts/CURRENT"
R=$K/cuts/$KB
[ -f "$R/cut.sh" ] || fail "cuts/CURRENT names $KB, which has no cut.sh"
S=$R/SHA256SUMS-$KB
[ -f "$S" ] || fail "cuts/$KB has no SHA256SUMS-$KB"
[ "$(grep -c . "$S")" = 7 ] || fail "SHA256SUMS-$KB does not hold seven sums"
grep -Eq "(^|[ ;])KB=$KB( |$)" "$R/cut.sh" || fail "cuts/$KB/cut.sh does not cut $KB"

P=$K/pkg/kernel-k30-m/pin.sh
bid=$(sed -n 's/^K30M_BUILDID=//p' "$P")
[ "$bid" = "$KB" ] || fail "kern30m pins build $bid, cuts/CURRENT is $KB"
for v in ETREL BREL SYM KABI AUDIO; do
	h=$(sed -n "s/^K30M_${v}_SHA=//p" "$P")
	[ -n "$h" ] && grep -q "^$h  " "$S" || fail "kern30m's K30M_${v}_SHA is not in SHA256SUMS-$KB"
done
for h in $(sed -n '/^K30M_FSMODS=/,/"$/p' "$P" | awk 'NF == 3 {print $2}' | tr -d '"'); do
	grep -q "^$h  mod.d/" "$S" || fail "a K30M_FSMODS sum is not in SHA256SUMS-$KB"
done
echo "cuts-selftest: PASS (cuts/CURRENT $KB, kern30m pins its seven sums)"
