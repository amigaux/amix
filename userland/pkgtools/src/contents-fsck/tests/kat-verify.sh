#!/bin/sh
# kat-verify.sh -- build + verify the known-answer branch/switch battery
# for the Amix cross pipeline (gcc.real -S -> asmfix.pl -> as -> static ld).
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Host side: builds kat-branch.c with the host gcc and RUNS it (C-level
# ground truth -- all cases must pass).
#
# Cross side (cannot execute m68k here): builds tests/kat-branch.amix with
# the exact contents-fsck pipeline and mechanically verifies the switch
# jump-table dispatch invariant on the disassembly:
#     for every "movew %pc@(A,...)" table fetch, the following
#     "jmp %pc@(B,...)" must satisfy A == B
# (fetch base = table label, jump base = hard-coded ext+6; they are equal
# only when the 4-byte .swbeg filler is present -- without the asmfix.pl
# .swbeg fix, B == A + 4 and every case is entered 4 bytes late).
# It also greps the two canonical comparison encodings validated by hand.
#
# Run the cross binary ON THE GUEST for machine ground truth:
#     /tmp/kat-branch ; echo rc=$?      (rc 0 = all pass)

DIR=`cd \`dirname "$0"\` && pwd`
OUT=$DIR/out
mkdir -p "$OUT"
fails=0

ok()  { echo "PASS: $1"; }
bad() { echo "FAIL: $1"; fails=`expr $fails + 1`; }

# ---------------- host ground truth ----------------
if gcc -std=c89 -pedantic -Wall -O2 -o "$OUT/kat-host" "$DIR/kat-branch.c" \
   && "$OUT/kat-host" > "$OUT/kat-host.log" 2>&1; then
    ok "host: kat-branch all cases pass"
else
    bad "host: kat-branch (see $OUT/kat-host.log)"
fi

# ---------------- cross build ----------------
# gcc-cross-amix at amix's toolchain/gcc-cross-amix.pin: CROSS_ENV, else
# $GCA/env.sh (GCA = its build/ directory)
CROSS_ENV=${CROSS_ENV:-${GCA:+$GCA/env.sh}}
SYSROOT=${AMIX_SYSROOT:-$HOME/opt/amix-cross/m68k-cbm-sysv4/sysroot}
CRT=$SYSROOT/usr/ccs/lib

command -v m68k-cbm-sysv4-gcc.real >/dev/null 2>&1 || \
    { [ -n "$CROSS_ENV" ] && [ -r "$CROSS_ENV" ] && . "$CROSS_ENV"; }
if ! command -v m68k-cbm-sysv4-gcc.real >/dev/null 2>&1; then
    echo "SKIP: cross toolchain not available (set GCA, see toolchain/gcc-cross-amix.pin)"
    exit `expr $fails + 0`
fi

if m68k-cbm-sysv4-gcc.real -S -O -I"$SYSROOT/usr/include" \
        -o "$OUT/kat.s" "$DIR/kat-branch.c" \
   && perl "$DIR/../tools/asmfix.pl" "$OUT/kat.s" \
   && m68k-cbm-sysv4-as -m68020 -o "$OUT/kat.o" "$OUT/kat.s" \
   && m68k-cbm-sysv4-ld -o "$DIR/kat-branch.amix" \
        "$CRT/crt1.o" "$CRT/crti.o" "$OUT/kat.o" "$CRT/libc.a" "$CRT/crtn.o"; then
    ok "cross: pipeline builds kat-branch.amix (static)"
else
    bad "cross: pipeline build"
    exit `expr $fails + 0`
fi

m68k-cbm-sysv4-objdump -d "$DIR/kat-branch.amix" > "$OUT/kat.dis"

# ---------------- switch dispatch invariant ----------------
awk '
function norm(a) {
    # objdump may print sign-extended addresses (ffffffff80000d96);
    # compare the low 8 hex digits
    while (length(a) > 8)
        a = substr(a, 2)
    return a
}
/movew %pc@\(/ {
    if (match($0, /%pc@\([0-9a-f]+/)) {
        fetch = norm(substr($0, RSTART + 5, RLENGTH - 5))
        want = 1
        next
    }
}
want == 1 && /jmp %pc@\(/ {
    if (match($0, /%pc@\([0-9a-f]+/)) {
        jmpb = norm(substr($0, RSTART + 5, RLENGTH - 5))
        pairs++
        if (jmpb != fetch) {
            printf("MISMATCH: fetch base %s jmp base %s\n", fetch, jmpb)
            badpairs++
        }
    }
    want = 0
}
END {
    printf("%d switch dispatch pair(s), %d mismatched\n", pairs, badpairs + 0)
    exit (pairs == 0 || badpairs > 0) ? 1 : 0
}' "$OUT/kat.dis" > "$OUT/kat-switch.log" 2>&1
if [ $? -eq 0 ]; then
    ok "cross: switch jump-table dispatch invariant (fetch base == jmp base)"
    cat "$OUT/kat-switch.log"
else
    bad "cross: switch dispatch invariant (see $OUT/kat-switch.log)"
    cat "$OUT/kat-switch.log"
fi

# ---------------- canonical comparison encodings ----------------
# lt8: gcc emits "mov.l &7,%d1; cmp.l %d1,<n>" (flags = 7 - n) + sge;
# after the operand swap gas encodes  D1 - <ea>  = 7 - n  -> sge == (n<8).
if grep -q 'sge %d0' "$OUT/kat.dis"; then
    ok "cross: signed-immediate compare uses sge (7-n >= 0) encoding"
else
    bad "cross: expected sge encoding not found"
fi
# unsigned compares must use carry-based conditions (scs/scc/shi/sls)
if grep -qE 's(cs|cc|hi|ls) %d0' "$OUT/kat.dis"; then
    ok "cross: unsigned compares use carry-based scc encodings"
else
    bad "cross: expected unsigned scc encodings not found"
fi

echo "----"
echo "kat-verify: $fails failure(s)"
echo "on-guest ground truth: push tests/kat-branch.amix and run it; rc 0 = all pass"
exit `expr $fails + 0`
