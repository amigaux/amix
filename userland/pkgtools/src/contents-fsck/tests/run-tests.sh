#!/bin/sh
# run-tests.sh -- test suite for contents-fsck (host build).
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Usage:  sh tests/run-tests.sh [path-to-binary]
#         (default binary: ./contents-fsck next to the Makefile)
#
# The factory-DB validation (28,646-line real Amix contents file) runs only
# when CONTENTS_FACTORY points at a readable copy of it; otherwise those
# cases are reported as SKIP.  The synthetic cases are self-contained.

DIR=`cd \`dirname "$0"\` && pwd`
BIN=${1:-$DIR/../contents-fsck}
OUT=$DIR/out

if [ ! -x "$BIN" ]; then
    echo "run-tests.sh: binary $BIN not found -- run 'make host' first" >&2
    exit 2
fi

rm -rf "$OUT"
mkdir -p "$OUT"

pass=0
fail=0

ok() {
    echo "PASS: $1"
    pass=`expr $pass + 1`
}

bad() {
    echo "FAIL: $1 -- $2"
    fail=`expr $fail + 1`
}

# run <logname> <expected-exit> [args...] ; sets $rc, log in $OUT/<logname>.log
run() {
    _log=$1; _want=$2; shift 2
    "$BIN" "$@" > "$OUT/$_log.log" 2>&1
    rc=$?
    if [ "$rc" -ne "$_want" ]; then
        _runfail="exit $rc (wanted $_want)"
        return 1
    fi
    _runfail=""
    return 0
}

# grepc <logname> <count> <pattern>
grepc() {
    _n=`grep -c "$3" "$OUT/$1.log"`
    [ "$_n" -eq "$2" ]
}

# ---------------------------------------------------------------- clean
cp "$DIR/clean.contents" "$OUT/clean"
if run clean-report 0 "$OUT/clean" && grepc clean-report 1 "findings: 0 total"; then
    ok "clean: report exits 0, no findings"
else
    bad "clean: report" "$_runfail"
fi
if run clean-repair 0 -r "$OUT/clean" && cmp -s "$OUT/clean" "$OUT/clean.fixed"; then
    ok "clean: repair output byte-identical (comments/directives preserved)"
else
    bad "clean: repair" "output differs or $_runfail"
fi

# ---------------------------------------------------------------- spaced
cp "$DIR/spaced.contents" "$OUT/spaced"
if run spaced-report 1 "$OUT/spaced" \
   && grepc spaced-report 1 '"/opt/app/My Cool File"' \
   && grepc spaced-report 1 '"/opt/app/New Folder Of Stuff"' \
   && grepc spaced-report 1 "spaced-path 2,"; then
    ok "spaced: both spaced pathnames recovered via tolerant re-join"
else
    bad "spaced: report" "$_runfail"
fi
if run spaced-keep 1 -r "$OUT/spaced" && cmp -s "$OUT/spaced" "$OUT/spaced.fixed"; then
    ok "spaced: repair default keeps records (byte-identical)"
else
    bad "spaced: repair keep" "output differs or $_runfail"
fi
if run spaced-strip 1 -r -s -o "$OUT/spaced.stripped" "$OUT/spaced" \
   && grepc spaced-strip 2 "DROPPED" \
   && grepc spaced-strip 1 ">>>     /opt/app/My Cool File" \
   && [ `wc -l < "$OUT/spaced.stripped"` -eq 2 ] \
   && run spaced-recheck 0 "$OUT/spaced.stripped"; then
    ok "spaced: -s drops records, prints on-disk paths, result rechecks clean"
else
    bad "spaced: -s strip" "$_runfail"
fi

# ---------------------------------------------------------------- dup-pkg
cp "$DIR/duppkg.contents" "$OUT/duppkg"
if run duppkg-report 1 "$OUT/duppkg" \
   && grepc duppkg-report 3 "dup-pkg\]" \
   && grepc duppkg-report 0 "^line 1:"; then
    ok "duppkg: 3 duplicated pkg fields found; 'lp lp lp' owner/group trap not flagged"
else
    bad "duppkg: report" "$_runfail"
fi
if run duppkg-repair 1 -r "$OUT/duppkg" \
   && cmp -s "$OUT/duppkg.fixed" "$DIR/duppkg.expected" \
   && run duppkg-recheck 0 "$OUT/duppkg.fixed"; then
    ok "duppkg: repair dedupes exactly; result rechecks clean"
else
    bad "duppkg: repair" "$_runfail"
fi

# ---------------------------------------------------------------- links (s/l with '=')
cp "$DIR/links.contents" "$OUT/links"
if run links 1 "$OUT/links" \
   && grepc links 1 "eq-hazard 0," \
   && grepc links 1 '"/opt/spaced link=/opt/real target"' \
   && grepc links 1 "spaced-path 1,"; then
    ok "links: s/l '=' pathnames clean; spaced symlink recovered, no eq-hazard"
else
    bad "links" "$_runfail"
fi

# ---------------------------------------------------------------- eq-hazard
cp "$DIR/eqhaz.contents" "$OUT/eqhaz"
if run eqhaz 1 "$OUT/eqhaz" \
   && grepc eqhaz 1 "eq-hazard\]" \
   && grepc eqhaz 1 "eq-hazard 1,"; then
    ok "eqhaz: '=' in non-s/l pathname flagged as silent-mis-split hazard"
else
    bad "eqhaz" "$_runfail"
fi

# ---------------------------------------------------------------- devices
cp "$DIR/devices.contents" "$OUT/devices"
if run devices 0 "$OUT/devices" && grepc devices 1 "findings: 0 total"; then
    ok "devices: c/b records incl. '?' major/minor parse clean"
else
    bad "devices" "$_runfail"
fi

# ---------------------------------------------------------------- status prefixes
cp "$DIR/status.contents" "$OUT/status"
if run status 0 "$OUT/status" && grepc status 1 "findings: 0 total"; then
    ok "status: -+*~!% pkg prefixes and pkg:class suffix tolerated"
else
    bad "status" "$_runfail"
fi

# ---------------------------------------------------------------- sort order
cp "$DIR/sortviol.contents" "$OUT/sortviol"
if run sortviol 1 "$OUT/sortviol" \
   && grepc sortviol 1 "sort-order\]" \
   && run sortviol-repair 1 -r "$OUT/sortviol" \
   && cmp -s "$OUT/sortviol" "$OUT/sortviol.fixed"; then
    ok "sortviol: disorder reported; repair keeps record order"
else
    bad "sortviol" "$_runfail"
fi

# ---------------------------------------------------------------- malformed
cp "$DIR/malformed.contents" "$OUT/malformed"
if run malformed 1 "$OUT/malformed" \
   && grepc malformed 1 "unparseable 5," \
   && grepc malformed 1 "mode is not octal" \
   && grepc malformed 1 "old-style entry" \
   && run malformed-repair 1 -r "$OUT/malformed" \
   && cmp -s "$OUT/malformed" "$OUT/malformed.fixed"; then
    ok "malformed: 5 unparseable records diagnosed; repair preserves them verbatim"
else
    bad "malformed" "$_runfail"
fi

# ---------------------------------------------------------------- long line
awk 'BEGIN {
    printf "/opt/a d none 0755 bin bin PKGA\n";
    printf "/opt/long/";
    for (i = 0; i < 600; i++) printf "0123456789";
    printf " f none 0444 bin bin 10 20 690829200 PKGA\n";
    printf "/opt/z d none 0755 bin bin PKGA\n";
}' > "$OUT/longline"
if run longline 1 "$OUT/longline" \
   && grepc longline 1 "long-line\]" \
   && run longline-repair 1 -r "$OUT/longline" \
   && cmp -s "$OUT/longline" "$OUT/longline.fixed"; then
    ok "longline: >4096-byte line reported; repair passes it through verbatim"
else
    bad "longline" "$_runfail"
fi

# ---------------------------------------------------------------- whitespace normalization
cp "$DIR/whitespace.contents" "$OUT/whitespace"
if run ws-report 0 "$OUT/whitespace" \
   && run ws-repair 0 -r "$OUT/whitespace" \
   && cmp -s "$OUT/whitespace.fixed" "$DIR/whitespace.expected" \
   && grepc ws-repair 1 "2 records re-spaced"; then
    ok "whitespace: tabs/runs normalized to single spaces on repair"
else
    bad "whitespace" "$_runfail"
fi

# ---------------------------------------------------------------- -b backup
cp "$DIR/duppkg.contents" "$OUT/bak"
if run bak 1 -r -b "$OUT/bak" \
   && cmp -s "$OUT/bak" "$OUT/bak.bak" \
   && cmp -s "$OUT/bak.fixed" "$DIR/duppkg.expected"; then
    ok "backup: -b writes byte-identical .bak before repair"
else
    bad "backup" "$_runfail"
fi

# ---------------------------------------------------------------- usage errors
if run usage-nofile 2; then
    ok "usage: no input file exits 2"
else
    bad "usage: no input file" "$_runfail"
fi
if run usage-s-without-r 2 -s "$OUT/clean"; then
    ok "usage: -s without -r exits 2"
else
    bad "usage: -s without -r" "$_runfail"
fi
if run usage-missing 2 "$OUT/no-such-file"; then
    ok "usage: unreadable input exits 2"
else
    bad "usage: unreadable input" "$_runfail"
fi

# ---------------------------------------------------------------- factory DB
if [ -n "$CONTENTS_FACTORY" ] && [ -r "$CONTENTS_FACTORY" ]; then
    cp "$CONTENTS_FACTORY" "$OUT/factory"

    if run fact-report 1 "$OUT/factory" \
       && grepc fact-report 1 "findings: 2 total" \
       && grepc fact-report 1 '"/usr/x11r5/fonts/server/MacFS/TrueType Fonts"' \
       && grepc fact-report 1 "^line 26964: .spaced-path" \
       && grepc fact-report 1 "^line 26964: .dup-pkg. duplicated trailing pkg field .X11R5" \
       && grepc fact-report 1 "28646 lines: 28644 records, 2 comment" \
       && grepc fact-report 1 "f=25819  s=253  p=3  c=557  b=273  d=1739"; then
        ok "factory: report finds exactly the spaced record + its dup pkg field"
    else
        bad "factory: report" "$_runfail"
    fi

    if run fact-repair 1 -r "$OUT/factory" \
       && [ `wc -l < "$OUT/factory.fixed"` -eq 28646 ] \
       && [ `diff "$OUT/factory" "$OUT/factory.fixed" | wc -l` -eq 4 ] \
       && diff "$OUT/factory" "$OUT/factory.fixed" | grep -q "^> .*TrueType Fonts f none 0444 x sys 525157 64049 679609720 X11R5\$"; then
        ok "factory: repair diff is exactly the one-line pkg-field dedupe"
    else
        bad "factory: repair" "$_runfail"
    fi

    if run fact-recheck 1 "$OUT/factory.fixed" \
       && grepc fact-recheck 1 "findings: 1 total" \
       && grepc fact-recheck 1 "spaced-path 1, dup-pkg 0, sort-order 0, eq-hazard 0, long-line 0"; then
        ok "factory: repaired DB rechecks clean except spaced-path informational"
    else
        bad "factory: recheck" "$_runfail"
    fi

    if run fact-strip 1 -r -s -o "$OUT/factory.stripped" "$OUT/factory" \
       && grepc fact-strip 1 "DROPPED" \
       && [ `wc -l < "$OUT/factory.stripped"` -eq 28645 ] \
       && run fact-strip-recheck 0 "$OUT/factory.stripped" \
       && grepc fact-strip-recheck 1 "findings: 0 total"; then
        ok "factory: -s drops the corrupt record; result fully clean (exit 0)"
    else
        bad "factory: strip" "$_runfail"
    fi
else
    echo "SKIP: factory DB cases (set CONTENTS_FACTORY=/path/to/contents.factory)"
fi

# ----------------------------------------------------------------
echo "----"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
