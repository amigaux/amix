#!/usr/bin/env bash
# run-tests.sh -- host-side tests for gen-catalog.py and publish.sh.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Fixtures: real Heirloom-pkgtools-produced SVR4 datastreams --
#   TESTpkg.pkg  odc  (070707) cpio, BASEDIR=/, reloc payload
#   TSTpkg.pkg   odc  (070707) cpio, variant field order
#   toy.pkg      newc (070701) cpio, VERSION with spaces, root payload
# plus a synthetic datastream built here with GNU cpio (independent
# producer) to exercise APKG_DEPS / APKG_DESC.
#
# Never contacts the network: publish.sh is only exercised with --dry-run
# against a scratch PUBLISH_DEST, which exits before the HTTP verify.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GEN="$HERE/../gen-catalog.py"
PUB="$HERE/../publish.sh"
FIX="$HERE/fixtures"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/apkg-repo-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL- $1"; }
check() { # check <description> <command...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

field() { # field <catalog> <name> <n>  -> print field n of entry <name>
    awk -F'|' -v n="$2" -v f="$3" '$1 == n { print $f }' "$1"
}

# ---------------------------------------------------------------- T1 ----
echo "T1: basic catalog generation (odc + newc fixtures)"
S1="$WORK/t1"; mkdir -p "$S1"
cp "$FIX/TESTpkg.pkg" "$FIX/TSTpkg.pkg" "$FIX/toy.pkg" "$S1/"
python3 "$GEN" "$S1" >"$WORK/t1.out" 2>"$WORK/t1.err"
check "exit status 0" test $? -eq 0
check "catalog written" test -f "$S1/catalog"
check "catalog.md5 written" test -f "$S1/catalog.md5"
check "header line" grep -qx '#apkg-catalog 1' "$S1/catalog"
check "three entries" test "$(grep -vc '^#' "$S1/catalog")" = 3

check "PKG extraction: testpkg pkginst" \
    test "$(field "$S1/catalog" testpkg 3)" = "TESTpkg"
check "PKG extraction: jutoy (newc) pkginst" \
    test "$(field "$S1/catalog" jutoy 3)" = "JUTOY"
check "NAME extraction -> description" \
    test "$(field "$S1/catalog" testpkg 9)" = "Test Package"
check "VERSION extraction" \
    test "$(field "$S1/catalog" testpkg 2)" = "1.0"
check "CATEGORY extraction" \
    test "$(field "$S1/catalog" jutoy 8)" = "system"
check "deps default none" \
    test "$(field "$S1/catalog" testpkg 7)" = "none"
check "filename field" \
    test "$(field "$S1/catalog" testpkg 4)" = "TESTpkg.pkg"

# line shape: 9 pipe-separated fields on every entry
check "every entry has 9 fields" \
    test -z "$(grep -v '^#' "$S1/catalog" | awk -F'|' 'NF != 9')"
# sorted by name
SORTED="$(grep -v '^#' "$S1/catalog" | cut -d'|' -f1)"
check "entries sorted by name" \
    test "$SORTED" = "$(printf '%s\n' "$SORTED" | sort)"

MD5="$(md5sum "$S1/TESTpkg.pkg" | cut -d' ' -f1)"
SIZE="$(stat -c %s "$S1/TESTpkg.pkg")"
check "md5 of served file" test "$(field "$S1/catalog" testpkg 5)" = "$MD5"
check "size of served file" test "$(field "$S1/catalog" testpkg 6)" = "$SIZE"
check "catalog.md5 is md5sum-compatible" \
    bash -c "cd '$S1' && md5sum -c catalog.md5"

# deterministic re-run: identical bytes
cp "$S1/catalog" "$WORK/t1.catalog.first"
python3 "$GEN" "$S1" >/dev/null 2>&1
check "re-run is byte-identical" cmp -s "$S1/catalog" "$WORK/t1.catalog.first"

# ---------------------------------------------------------------- T2 ----
echo "T2: deps.conf override"
S2="$WORK/t2"; mkdir -p "$S2"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S2/"
printf '# test override\ntestpkg: jutoy, extra\n' > "$S2/deps.conf"
python3 "$GEN" "$S2" >/dev/null 2>&1
check "deps.conf wins" \
    test "$(field "$S2/catalog" testpkg 7)" = "jutoy,extra"
check "other entries untouched" \
    test "$(field "$S2/catalog" jutoy 7)" = "none"

# ---------------------------------------------------------------- T3 ----
echo "T3: names.conf mapping"
S3="$WORK/t3"; mkdir -p "$S3"
cp "$FIX/TESTpkg.pkg" "$S3/"
printf 'TESTpkg: amixtest\n' > "$S3/names.conf"
printf 'amixtest: jutoy\n' > "$S3/deps.conf"
python3 "$GEN" "$S3" >/dev/null 2>&1
check "mapped name used" test -n "$(field "$S3/catalog" amixtest 3)"
check "pkginst stays PKG" \
    test "$(field "$S3/catalog" amixtest 3)" = "TESTpkg"
check "deps.conf keyed by mapped name" \
    test "$(field "$S3/catalog" amixtest 7)" = "jutoy"

# ---------------------------------------------------------------- T4 ----
echo "T4: .Z handling"
S4="$WORK/t4"; mkdir -p "$S4"
if command -v compress >/dev/null 2>&1; then
    compress -c "$FIX/TESTpkg.pkg" > "$S4/TESTpkg.pkg.Z"
    echo "  (using real LZW compress)"
else
    # gzip output under a .Z name still exercises the .Z code path, since
    # the decompressor chain (uncompress -c / zcat / gzip -dc) reads both.
    gzip -c "$FIX/TESTpkg.pkg" > "$S4/TESTpkg.pkg.Z"
    echo "  (compress(1) not on host; substituting gzip stream)"
fi
python3 "$GEN" "$S4" >/dev/null 2>&1
check "exit 0 on .Z staging" test $? -eq 0
check ".Z entry present" test -n "$(field "$S4/catalog" testpkg 2)"
check ".Z filename served as-is" \
    test "$(field "$S4/catalog" testpkg 4)" = "TESTpkg.pkg.Z"
ZMD5="$(md5sum "$S4/TESTpkg.pkg.Z" | cut -d' ' -f1)"
ZSIZE="$(stat -c %s "$S4/TESTpkg.pkg.Z")"
check ".Z md5 is of the compressed file" \
    test "$(field "$S4/catalog" testpkg 5)" = "$ZMD5"
check ".Z size is of the compressed file" \
    test "$(field "$S4/catalog" testpkg 6)" = "$ZSIZE"
check ".Z pkginfo parsed from decompressed stream" \
    test "$(field "$S4/catalog" testpkg 2)" = "1.0"

# ---------------------------------------------------------------- T5 ----
echo "T5: malformed files reported and skipped, not fatal"
S5="$WORK/t5"; mkdir -p "$S5"
cp "$FIX/toy.pkg" "$S5/"
head -c 1000 /dev/urandom > "$S5/garbage.pkg"
head -c 300 "$FIX/TESTpkg.pkg" > "$S5/truncated.pkg"
python3 "$GEN" "$S5" >"$WORK/t5.out" 2>"$WORK/t5.err"
check "exit 0 despite malformed files" test $? -eq 0
check "good package still cataloged" \
    test "$(field "$S5/catalog" jutoy 3)" = "JUTOY"
check "only the good entry emitted" \
    test "$(grep -vc '^#' "$S5/catalog")" = 1
check "garbage.pkg reported on stderr" \
    grep -q 'SKIP garbage.pkg' "$WORK/t5.err"
check "truncated.pkg reported on stderr" \
    grep -q 'SKIP truncated.pkg' "$WORK/t5.err"

# all-malformed staging refuses to write a catalog
S5b="$WORK/t5b"; mkdir -p "$S5b"
head -c 700 /dev/urandom > "$S5b/junk.pkg"
python3 "$GEN" "$S5b" >/dev/null 2>&1
check "all-malformed staging exits nonzero" test $? -ne 0
check "all-malformed staging writes no catalog" test ! -f "$S5b/catalog"

# ---------------------------------------------------------------- T6 ----
echo "T6: APKG_DEPS / APKG_DESC from pkginfo (GNU-cpio-built datastream)"
S6="$WORK/t6"; mkdir -p "$S6/build/SYNpkg"
cat > "$S6/build/SYNpkg/pkginfo" <<'EOF'
PKG=SYNpkg
NAME=Synthetic package
ARCH=Amiga
VERSION=2.3-1
CATEGORY=application
APKG_DEPS=jutoy,testpkg
APKG_DESC=A synthetic test package with authored deps
CLASSES=none
EOF
printf ': 1 1\n1 i pkginfo 200 12345 1234567890\n' > "$S6/build/SYNpkg/pkgmap"
{
    printf '# PaCkAgE DaTaStReAm\nSYNpkg 1 1\n# end of header\n'
    head -c 512 /dev/zero
} | head -c 512 > "$S6/build/hdr"
( cd "$S6/build" && printf 'SYNpkg/pkginfo\nSYNpkg/pkgmap\n' \
    | cpio -o -H odc --quiet > arch1 )
cat "$S6/build/hdr" "$S6/build/arch1" > "$S6/SYNpkg.pkg"
rm -rf "$S6/build"
python3 "$GEN" "$S6" >/dev/null 2>&1
check "synthetic datastream parses" \
    test "$(field "$S6/catalog" synpkg 3)" = "SYNpkg"
check "APKG_DEPS honored" \
    test "$(field "$S6/catalog" synpkg 7)" = "jutoy,testpkg"
check "APKG_DESC honored" \
    test "$(field "$S6/catalog" synpkg 9)" = "A synthetic test package with authored deps"

# ---------------------------------------------------------------- T7 ----
echo "T7: duplicate catalog name skipped with report"
S7="$WORK/t7"; mkdir -p "$S7"
cp "$FIX/TESTpkg.pkg" "$S7/"
cp "$FIX/TESTpkg.pkg" "$S7/TESTpkg-copy.pkg"
python3 "$GEN" "$S7" >/dev/null 2>"$WORK/t7.err"
check "one entry survives" test "$(grep -vc '^#' "$S7/catalog")" = 1
check "duplicate reported" grep -q 'duplicate catalog name' "$WORK/t7.err"

# ---------------------------------------------------------------- T8 ----
echo "T8: publish.sh --dry-run against scratch PUBLISH_DEST"
S8="$WORK/t8"; mkdir -p "$S8"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S8/"
python3 "$GEN" "$S8" >/dev/null 2>&1
DEST8="$WORK/t8-dest"; mkdir -p "$DEST8"
PUBLISH_DEST="$DEST8" bash "$PUB" --dry-run "$S8" >"$WORK/t8.out" 2>&1
check "dry-run exit 0" test $? -eq 0
check "dry-run announces itself" grep -q 'DRY RUN' "$WORK/t8.out"
check "dry-run lists packages" grep -q 'TESTpkg.pkg' "$WORK/t8.out"
check "dry-run lists catalog" grep -q 'catalog' "$WORK/t8.out"
check "dry-run skips HTTP verify" \
    grep -q 'skipping HTTP verify' "$WORK/t8.out"
check "destination untouched" \
    test -z "$(find "$DEST8" -mindepth 1 -print -quit)"

# ---------------------------------------------------------------- T9 ----
echo "T9: publish.sh refuses bad staging"
S9="$WORK/t9"; mkdir -p "$S9"
PUBLISH_DEST="$WORK/t9-dest" bash "$PUB" --dry-run "$S9" >/dev/null 2>&1
check "missing catalog -> nonzero exit" test $? -ne 0
cp "$FIX/TESTpkg.pkg" "$S9/"
python3 "$GEN" "$S9" >/dev/null 2>&1
echo "tampered" >> "$S9/catalog"
PUBLISH_DEST="$WORK/t9-dest" bash "$PUB" --dry-run "$S9" >/dev/null 2>&1
check "catalog/catalog.md5 mismatch -> nonzero exit" test $? -ne 0
python3 "$GEN" "$S9" >/dev/null 2>&1
env -u PUBLISH_DEST bash "$PUB" --dry-run "$S9" >"$WORK/t9-nodest.out" 2>&1
check "no PUBLISH_DEST -> nonzero exit (no default host)" test $? -ne 0
check "no PUBLISH_DEST -> says to set it" grep -q 'PUBLISH_DEST' "$WORK/t9-nodest.out"

# --------------------------------------------------------------- T10 ----
echo "T10: recursive scan of categorized subdirectories"
S10="$WORK/t10"; mkdir -p "$S10/stock" "$S10/base/deep"
cp "$FIX/TESTpkg.pkg" "$S10/stock/"
cp "$FIX/toy.pkg" "$S10/base/deep/"
cp "$FIX/TSTpkg.pkg" "$S10/"                    # root-level still works
printf 'testpkg: jutoy\n' > "$S10/deps.conf"    # root-level conf applies
python3 "$GEN" "$S10" >"$WORK/t10.out" 2>"$WORK/t10.err"
check "exit status 0" test $? -eq 0
check "three entries found recursively" \
    test "$(grep -vc '^#' "$S10/catalog")" = 3
check "subdir filename is relative path" \
    test "$(field "$S10/catalog" testpkg 4)" = "stock/TESTpkg.pkg"
check "nested subdir filename is relative path" \
    test "$(field "$S10/catalog" jutoy 4)" = "base/deep/toy.pkg"
check "root-level filename has no slash" \
    test "$(field "$S10/catalog" tstpkg 4)" = "TSTpkg.pkg"
M10="$(md5sum "$S10/stock/TESTpkg.pkg" | cut -d' ' -f1)"
check "md5 of subdir file" test "$(field "$S10/catalog" testpkg 5)" = "$M10"
check "root deps.conf applies to subdir package" \
    test "$(field "$S10/catalog" testpkg 7)" = "jutoy"
# duplicate catalog names are detected across subdirectories too
S10b="$WORK/t10b"; mkdir -p "$S10b/stock" "$S10b/base"
cp "$FIX/TESTpkg.pkg" "$S10b/stock/"
cp "$FIX/TESTpkg.pkg" "$S10b/base/"
python3 "$GEN" "$S10b" >/dev/null 2>"$WORK/t10b.err"
check "cross-subdir duplicate: one entry survives" \
    test "$(grep -vc '^#' "$S10b/catalog")" = 1
check "cross-subdir duplicate reported" \
    grep -q 'duplicate catalog name' "$WORK/t10b.err"

# --------------------------------------------------------------- T11 ----
echo "T11: publish.sh --dry-run preserves subdirectory structure"
DEST11="$WORK/t11-dest"; mkdir -p "$DEST11"
PUBLISH_DEST="$DEST11" bash "$PUB" --dry-run "$S10" >"$WORK/t11.out" 2>&1
check "dry-run exit 0" test $? -eq 0
check "dry-run lists subdir package with its path" \
    grep -q 'stock/TESTpkg.pkg' "$WORK/t11.out"
check "dry-run lists nested subdir package with its path" \
    grep -q 'base/deep/toy.pkg' "$WORK/t11.out"
check "dry-run lists root-level package" \
    grep -q 'TSTpkg.pkg' "$WORK/t11.out"
check "dry-run does not sync deps.conf" \
    bash -c "! grep -q 'deps.conf' <(grep -v '^publish:' '$WORK/t11.out')"
check "destination untouched" \
    test -z "$(find "$DEST11" -mindepth 1 -print -quit)"

# --------------------------------------------------------------- T12 ----
echo "T12: --raw offset catalog + raw.img (self-describing slice)"
S12="$WORK/t12"; mkdir -p "$S12/stock"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S12/stock/"
python3 "$GEN" --raw "$S12" >"$WORK/t12.out" 2>"$WORK/t12.err"
check "exit status 0" test $? -eq 0
check "raw catalog written" test -f "$S12/catalog"
check "raw.img written" test -f "$S12/raw.img"
check "every raw entry has 10 fields (offset column present)" \
    test -z "$(grep -v '^#' "$S12/catalog" | awk -F'|' 'NF != 10')"
check "first package offset is RAW_DATA_OFF (65536)" \
    test "$(grep -v '^#' "$S12/catalog" | head -1 | cut -d'|' -f10)" = 65536
check "raw catalog.md5 matches raw catalog" \
    bash -c "cd '$S12' && md5sum -c catalog.md5"
# a plain (non-raw) run of the same staging stays 9-field and writes no image
S12b="$WORK/t12b"; mkdir -p "$S12b/stock"
cp "$FIX/TESTpkg.pkg" "$S12b/stock/"
python3 "$GEN" "$S12b" >/dev/null 2>&1
check "plain mode stays 9-field" \
    test -z "$(grep -v '^#' "$S12b/catalog" | awk -F'|' 'NF != 9')"
check "plain mode writes no raw.img" test ! -f "$S12b/raw.img"
# image layout: catalog@0, catalog.md5@32768, each package's served bytes
# at its 512-aligned offset, md5-consistent with the catalog
python3 - "$S12" >"$WORK/t12.img.out" 2>&1 <<'PY'
import sys, os, hashlib
s = sys.argv[1]
img = open(os.path.join(s, "raw.img"), "rb").read()
cat = open(os.path.join(s, "catalog"), "rb").read()
md5 = open(os.path.join(s, "catalog.md5"), "rb").read()
assert img[:len(cat)] == cat, "catalog not at image offset 0"
assert img[32768:32768 + len(md5)] == md5, "catalog.md5 not at offset 32768"
for line in cat.decode().splitlines():
    if line.startswith("#"):
        continue
    f = line.split("|")
    fn, want, size, off = f[3], f[4], int(f[5]), int(f[9])
    assert off % 512 == 0 and off >= 65536, "bad offset for " + fn
    seg = img[off:off + size]
    assert hashlib.md5(seg).hexdigest() == want, "image md5 != catalog for " + fn
    assert seg == open(os.path.join(s, fn), "rb").read(), "image != source " + fn
print("RAWIMG-OK")
PY
check "raw.img layout verified (catalog@0, md5@32768, pkgs at offsets)" \
    grep -q RAWIMG-OK "$WORK/t12.img.out"

# --------------------------------------------------------------- T13 ----
# Licensing gate (W6-K section 3), RE-KEYED to OUR kernel packages: a package
# is PRIVATE-only when its pkginfo carries the kernel-package markers
# (KSUM_R / BOOT2_SHA) that build-packages.sh mints onto KERNBENCH/KERNZ3660 --
# NOT when its pkgmap merely installs /stand/unix or /stand/boot2.boot.  That
# re-key is the whole point: STOCK `core` ships those /stand members as ORIGINAL
# Amix content and must catalog + publish normally.  We synthesize two tiny
# datastreams -- one carrying the markers (a mock kernel package, refused) and
# one that installs the very same /stand paths in its pkgmap but carries NO
# markers (a mock stock-core package, passed) -- so the gate is proven to key
# on the marker, not the pathname.  Both use a valid <=9-char PKG so the
# refusal is unmistakably about private CONTENT, not the name-length gate.
echo "T13: kernel-marker packages refused; stock /stand content passes (re-key)"

mk_kernel_pkg() { # mk_kernel_pkg <destdir>  -> writes KERNMOCK.pkg (marked)
    local dest="$1" b="$1/.build/KERNMOCK"
    mkdir -p "$b"
    # pkginfo carries the kernel-package markers KSUM_R + BOOT2_SHA (plus the
    # ROOTDEV/CONFIG/KMIX a real mint adds) -- this is what the gate keys on.
    cat > "$b/pkginfo" <<'EOF'
PKG=KERNMOCK
NAME=Mock private kernel package
ARCH=Amiga
VERSION=45473-2026.07.23
CATEGORY=system
CLASSES=none
ROOTDEV=0x00480016
CONFIG=c6s1unix
KMIX=a4091,cdfs
KSUM_R=45473
BOOT2_SHA=f287ff3a759d6f80304fa35bb53e1479fc98056836b44a16824bd3e3f8fdba78
EOF
    # pkgmap installs the same /stand payload a real kernel package does; the
    # gate no longer reads it, so keeping it faithful proves the gate ignores
    # the pathname in favor of the pkginfo markers.
    printf ': 1 1\n1 d none /stand 0755 root root\n1 f none /stand/unix 0644 root root 100 1 1\n1 f none /stand/boot2.boot 0644 root root 8192 1 1\n1 i pkginfo 200 1 1\n' > "$b/pkgmap"
    { printf '# PaCkAgE DaTaStReAm\nKERNMOCK 1 1\n# end of header\n'
      head -c 512 /dev/zero; } | head -c 512 > "$1/.build/hdr"
    ( cd "$1/.build" && printf 'KERNMOCK/pkginfo\nKERNMOCK/pkgmap\n' \
        | cpio -o -H odc --quiet > arch1 )
    cat "$1/.build/hdr" "$1/.build/arch1" > "$dest/KERNMOCK.pkg"
    rm -rf "$1/.build"
}

mk_stock_stand_pkg() { # mk_stock_stand_pkg <destdir> -> writes COREMOCK.pkg
    # Mimics stock `core`: installs /stand/unix + /stand/boot2.boot as original
    # content, but carries NO kernel markers -- must catalog + publish normally.
    local dest="$1" b="$1/.build/COREMOCK"
    mkdir -p "$b"
    cat > "$b/pkginfo" <<'EOF'
PKG=COREMOCK
NAME=Mock stock core (ships /stand, no markers)
ARCH=Amiga
VERSION=2.1
CATEGORY=system
CLASSES=none
EOF
    printf ': 1 1\n1 d none /stand 0755 root root\n1 f none /stand/unix 0644 root root 100 1 1\n1 f none /stand/boot2.boot 0644 root root 8192 1 1\n1 i pkginfo 200 1 1\n' > "$b/pkgmap"
    { printf '# PaCkAgE DaTaStReAm\nCOREMOCK 1 1\n# end of header\n'
      head -c 512 /dev/zero; } | head -c 512 > "$1/.build/hdr"
    ( cd "$1/.build" && printf 'COREMOCK/pkginfo\nCOREMOCK/pkgmap\n' \
        | cpio -o -H odc --quiet > arch1 )
    cat "$1/.build/hdr" "$1/.build/arch1" > "$dest/COREMOCK.pkg"
    rm -rf "$1/.build"
}

# T13a: gen-catalog NORMAL mode refuses a kernel-marker package (rc 3), no catalog
S13="$WORK/t13"; mkdir -p "$S13"
mk_kernel_pkg "$S13"
python3 "$GEN" "$S13" >"$WORK/t13.out" 2>"$WORK/t13.err"; RC=$?
check "normal catalog build exits rc 3 on kernel-marker package" test "$RC" -eq 3
check "no catalog written for kernel-marker package" test ! -f "$S13/catalog"
check "refusal names a kernel marker (KSUM_R/BOOT2_SHA)" \
    grep -Eq 'KSUM_R|BOOT2_SHA' "$WORK/t13.err"
check "refusal cites the licensing gate / PRIVATE" \
    grep -qi 'PRIVATE\|licensing gate' "$WORK/t13.err"

# T13b: --scan-private reports the offender and exits rc 3
python3 "$GEN" --scan-private "$S13" >/dev/null 2>"$WORK/t13b.err"; RC=$?
check "scan-private exits rc 3 on kernel-marker package" test "$RC" -eq 3
check "scan-private names the offending package" \
    grep -q 'PRIVATE CONTENT KERNMOCK.pkg' "$WORK/t13b.err"
check "scan-private reports it as a kernel package" \
    grep -q 'kernel package' "$WORK/t13b.err"
check "scan-private states no --force" grep -q 'no --force' "$WORK/t13b.err"

# T13c: --scan-private passes clean (redistributable) staging
S13c="$WORK/t13c"; mkdir -p "$S13c"
cp "$FIX/toy.pkg" "$FIX/TESTpkg.pkg" "$S13c/"
python3 "$GEN" --scan-private "$S13c" >"$WORK/t13c.out" 2>&1; RC=$?
check "scan-private exits 0 on clean staging" test "$RC" -eq 0
check "scan-private announces OK on clean staging" \
    grep -q 'scan-private: OK' "$WORK/t13c.out"

# T13d: RE-KEY PROOF -- a stock-core-like package that installs /stand/unix +
# /stand/boot2.boot but carries NO markers CATALOGS normally (this is exactly
# the false-positive the pathname gate caused; the marker re-key removes it).
S13d="$WORK/t13d"; mkdir -p "$S13d"
mk_stock_stand_pkg "$S13d"
python3 "$GEN" "$S13d" >"$WORK/t13d.out" 2>"$WORK/t13d.err"; RC=$?
check "stock /stand package catalogs (rc 0)" test "$RC" -eq 0
check "stock /stand package catalog written" test -f "$S13d/catalog"
check "stock /stand package present in catalog" \
    test "$(field "$S13d/catalog" coremock 3)" = "COREMOCK"
python3 "$GEN" --scan-private "$S13d" >"$WORK/t13d.scan" 2>&1; RC=$?
check "scan-private passes stock /stand package (rc 0)" test "$RC" -eq 0

# T13e: a MIXED staging (stock-clean + kernel-marker) still refuses (no partial
# catalog that blesses the clean package while omitting the kernel one)
S13e="$WORK/t13e"; mkdir -p "$S13e"
cp "$FIX/toy.pkg" "$S13e/"
mk_stock_stand_pkg "$S13e"          # a legit /stand package present too
mk_kernel_pkg "$S13e"
python3 "$GEN" "$S13e" >/dev/null 2>&1
check "mixed staging (clean+kernel) writes no catalog" test ! -f "$S13e/catalog"

# T13f: publish.sh REFUSES a staging carrying a kernel-marker package even when
# a valid catalog is present (the load-bearing gate: publish rsyncs every
# *.pkg, so a stale-catalog/hand-added kernel package must be caught).
S13f="$WORK/t13f"; mkdir -p "$S13f"
cp "$FIX/toy.pkg" "$S13f/"
python3 "$GEN" "$S13f" >/dev/null 2>&1            # valid catalog for the toy
mk_kernel_pkg "$S13f"                             # add kernel pkg AFTER
DEST13="$WORK/t13f-dest"; mkdir -p "$DEST13"
PUBLISH_DEST="$DEST13" bash "$PUB" --dry-run "$S13f" >"$WORK/t13f.out" 2>&1; RC=$?
check "publish refuses staging with a kernel-marker package (rc 4)" test "$RC" -eq 4
check "publish refusal names private/proprietary content" \
    grep -qi 'proprietary\|PRIVATE' "$WORK/t13f.out"
check "publish refusal offers no --force escape" \
    grep -q 'no --force' "$WORK/t13f.out"
check "publish wrote nothing to the destination" \
    test -z "$(find "$DEST13" -mindepth 1 -print -quit)"

# T13g: publish.sh PASSES a staging whose only /stand-shipping package is the
# stock-core-like one (no markers) -- the NAS-publish path must NOT refuse
# stock content.  (dry-run, so it exits before the HTTP verify.)
S13g="$WORK/t13g"; mkdir -p "$S13g"
cp "$FIX/toy.pkg" "$S13g/"
mk_stock_stand_pkg "$S13g"
python3 "$GEN" "$S13g" >/dev/null 2>&1            # valid catalog incl. the stock pkg
DEST13g="$WORK/t13g-dest"; mkdir -p "$DEST13g"
PUBLISH_DEST="$DEST13g" bash "$PUB" --dry-run "$S13g" >"$WORK/t13g.out" 2>&1; RC=$?
check "publish passes stock /stand staging (dry-run rc 0)" test "$RC" -eq 0
check "publish scan announces OK on stock /stand staging" \
    grep -q 'scan-private: OK' "$WORK/t13g.out"

# --------------------------------------------------------------- T14 ----
# Installed-size extension block (--isize).  The load-bearing property is
# NON-BREAKAGE: apkg's C parser accepts 9 fields (or 10 with the RAW offset)
# and rejects anything else, so the sizes ride as catalog COMMENT lines and
# the flag is opt-in.  Every check below is about proving that the entry
# lines -- what every existing consumer reads -- do not move.
echo "T14: installed-size block (--isize)"

# T14a: exact arithmetic against a hand-built pkgmap (independent oracle:
# the expected total is known by construction, not recomputed by the tool).
# Sized ftypes are f/v/e/i; d/s/l/c/b/p carry no size and must contribute 0.
S14="$WORK/t14"; mkdir -p "$S14/build/SZpkg"
cat > "$S14/build/SZpkg/pkginfo" <<'EOF'
PKG=SZpkg
NAME=Sized package
ARCH=Amiga
VERSION=1.0
CATEGORY=system
CLASSES=none
EOF
# 1000 + 2000 + 30 (v) + 7 (e) + 200 (i, pkginfo) = 3237; the directory,
# symlink, hard link, char/block devices and pipe must add nothing.
cat > "$S14/build/SZpkg/pkgmap" <<'EOF'
: 1 4
1 d none /usr 0755 bin bin
1 f none /usr/bin/one 0555 bin bin 1000 111 690829200
1 f none /usr/bin/two 0555 bin bin 2000 222 690829200
1 v none /var/log/vol 0644 root sys 30 333 690829200
1 e none /etc/edit 0644 root sys 7 444 690829200
1 s none /usr/bin/link=/usr/bin/one
1 l none /usr/bin/hard=/usr/bin/two
1 c none /dev/tty0 22 0 0666 root sys
1 b none /dev/dsk0 12 1 0640 root sys
1 p none /usr/pipe 0666 root sys
1 i pkginfo 200 555 690829200
EOF
{ printf '# PaCkAgE DaTaStReAm\nSZpkg 1 1\n# end of header\n'
  head -c 512 /dev/zero; } | head -c 512 > "$S14/build/hdr"
( cd "$S14/build" && printf 'SZpkg/pkginfo\nSZpkg/pkgmap\n' \
    | cpio -o -H odc --quiet > arch1 )
cat "$S14/build/hdr" "$S14/build/arch1" > "$S14/SZpkg.pkg"
rm -rf "$S14/build"
python3 "$GEN" --isize "$S14" >/dev/null 2>&1
check "sized ftypes summed exactly (f+v+e+i, no d/s/l/c/b/p)" \
    grep -qx '#isize szpkg 3237' "$S14/catalog"

# T14b: opt-in.  Without --isize nothing is appended at all.
python3 "$GEN" "$S14" >/dev/null 2>&1
check "no --isize => no #ext line" \
    bash -c "! grep -q '^#ext ' '$S14/catalog'"
check "no --isize => no #isize line" \
    bash -c "! grep -q '^#isize ' '$S14/catalog'"

# T14c: the entry lines are byte-identical with and without the flag --
# this is the whole no-breakage claim, checked on bytes rather than asserted.
S14b="$WORK/t14b"; mkdir -p "$S14b/stock"
cp "$FIX/TESTpkg.pkg" "$FIX/TSTpkg.pkg" "$S14b/stock/"
cp "$FIX/toy.pkg" "$S14b/"
python3 "$GEN" "$S14b" >/dev/null 2>&1
grep -v '^#' "$S14b/catalog" > "$WORK/t14.plain"
python3 "$GEN" --isize "$S14b" >/dev/null 2>&1
grep -v '^#' "$S14b/catalog" > "$WORK/t14.isize"
check "entry lines byte-identical with and without --isize" \
    cmp -s "$WORK/t14.plain" "$WORK/t14.isize"
check "--isize catalog still 9-field on every entry" \
    test -z "$(grep -v '^#' "$S14b/catalog" | awk -F'|' 'NF != 9')"
check "--isize catalog.md5 still matches its catalog" \
    bash -c "cd '$S14b' && md5sum -c catalog.md5"
check "one #ext isize line, version 1" \
    test "$(grep -c '^#ext isize 1$' "$S14b/catalog")" = 1
check "one #isize line per catalog entry" \
    test "$(grep -c '^#isize ' "$S14b/catalog")" = \
         "$(grep -vc '^#' "$S14b/catalog")"
check "#isize block follows the entries (block is a trailer)" \
    bash -c "test \$(grep -n '^#ext isize 1\$' '$S14b/catalog' | cut -d: -f1) \
             -gt \$(grep -vn '^#' '$S14b/catalog' | tail -1 | cut -d: -f1)"
# names in the block match the entry names, in the same order
check "#isize names match the entry names, in order" \
    bash -c "diff <(grep -v '^#' '$S14b/catalog' | cut -d'|' -f1) \
                  <(sed -n 's/^#isize \([^ ]*\) .*/\1/p' '$S14b/catalog')"
check "#isize values are decimal and positive" \
    test -z "$(sed -n 's/^#isize [^ ]* //p' "$S14b/catalog" \
               | grep -v '^[1-9][0-9]*$')"

# T14d: independent recomputation.  Pull the pkgmap out of the datastream
# with cpio and sum it with awk -- a different extractor and a different
# language from the generator's own python.
mkdir -p "$WORK/t14x"
dd if="$FIX/TESTpkg.pkg" bs=512 skip=1 2>/dev/null \
    | ( cd "$WORK/t14x" && cpio -idu --quiet 2>/dev/null )
AWKSUM="$(awk '$2=="f"||$2=="v"||$2=="e"||$2=="i" { s += $(NF-2) } \
               END { print s+0 }' "$WORK/t14x/TESTpkg/pkgmap")"
check "awk re-sum of the extracted pkgmap agrees with the catalog block" \
    test "$(sed -n 's/^#isize testpkg //p' "$S14b/catalog")" = "$AWKSUM"
check "the independent sum is non-trivial (> 0)" test "$AWKSUM" -gt 0

# T14e: a package with no pkgmap still catalogs; it just gets no #isize
# line (absence, not a fabricated 0 -- a free-space gate must see the gap).
S14c="$WORK/t14c"; mkdir -p "$S14c/build/NOMAP"
cat > "$S14c/build/NOMAP/pkginfo" <<'EOF'
PKG=NOMAP
NAME=Package without a pkgmap
ARCH=Amiga
VERSION=1.0
CATEGORY=system
CLASSES=none
EOF
{ printf '# PaCkAgE DaTaStReAm\nNOMAP 1 1\n# end of header\n'
  head -c 512 /dev/zero; } | head -c 512 > "$S14c/build/hdr"
( cd "$S14c/build" && printf 'NOMAP/pkginfo\n' | cpio -o -H odc --quiet > a1 )
cat "$S14c/build/hdr" "$S14c/build/a1" > "$S14c/NOMAP.pkg"
rm -rf "$S14c/build"
cp "$FIX/toy.pkg" "$S14c/"
python3 "$GEN" --isize "$S14c" >/dev/null 2>"$WORK/t14c.err"
check "pkgmap-less package still catalogs" \
    test "$(field "$S14c/catalog" nomap 3)" = "NOMAP"
check "pkgmap-less package gets no #isize line" \
    bash -c "! grep -q '^#isize nomap ' '$S14c/catalog'"
check "pkgmap-less package warned about on stderr" \
    grep -q 'no usable pkgmap' "$WORK/t14c.err"
check "its neighbour still gets one" grep -q '^#isize jutoy ' "$S14c/catalog"

# T14f: --raw and --isize compose (10-field entries + the trailing block),
# and the combined catalog still fits the RAW metadata region.
S14d="$WORK/t14d"; mkdir -p "$S14d/stock"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S14d/stock/"
python3 "$GEN" --raw --isize "$S14d" >/dev/null 2>&1
check "--raw --isize: entries keep the 10th offset field" \
    test -z "$(grep -v '^#' "$S14d/catalog" | awk -F'|' 'NF != 10')"
check "--raw --isize: block present" grep -q '^#isize testpkg ' "$S14d/catalog"
check "--raw --isize: raw.img still written" test -f "$S14d/raw.img"
check "--raw --isize: catalog fits the 32768-byte RAW metadata region" \
    test "$(stat -c %s "$S14d/catalog")" -lt 32768
check "--raw --isize: catalog.md5 matches" \
    bash -c "cd '$S14d' && md5sum -c catalog.md5"

# --------------------------------------------------------------- T15 ----
# cats.conf -- catalog-level taxonomy override.  The point is re-categorising
# WITHOUT re-minting: the served bytes (and therefore every .pkg md5 the
# digest gates depend on) must not move, only the catalog's category field.
echo "T15: cats.conf category override"
S15="$WORK/t15"; mkdir -p "$S15"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S15/"
python3 "$GEN" "$S15" >/dev/null 2>&1
PRE_CAT="$(field "$S15/catalog" jutoy 8)"
PRE_MD5="$(md5sum "$S15/toy.pkg" | cut -d' ' -f1)"
PRE_LINE="$(grep '^jutoy|' "$S15/catalog")"
printf '# taxonomy\njutoy: games\n' > "$S15/cats.conf"
python3 "$GEN" "$S15" >/dev/null 2>&1
check "cats.conf wins over pkginfo CATEGORY" \
    test "$(field "$S15/catalog" jutoy 8)" = "games"
check "the pkginfo CATEGORY it replaced was different" \
    test "$PRE_CAT" != "games"
check "package absent from cats.conf keeps its pkginfo CATEGORY" \
    test "$(field "$S15/catalog" testpkg 8)" = "application"
check "the .pkg file itself is untouched (md5 unmoved)" \
    test "$(md5sum "$S15/toy.pkg" | cut -d' ' -f1)" = "$PRE_MD5"
check "only the category field moved on the entry line" \
    test "$(grep '^jutoy|' "$S15/catalog" | awk -F'|' '{$8="X"; print}')" = \
         "$(printf '%s' "$PRE_LINE" | awk -F'|' '{$8="X"; print}')"

# keyed by the catalog name post names.conf mapping, with pkginst fallback
S15b="$WORK/t15b"; mkdir -p "$S15b"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S15b/"
printf 'TESTpkg: amixtest\n' > "$S15b/names.conf"
printf 'amixtest: development\nJUTOY: x11\n' > "$S15b/cats.conf"
python3 "$GEN" "$S15b" >/dev/null 2>&1
check "cats.conf keyed by the mapped catalog name" \
    test "$(field "$S15b/catalog" amixtest 8)" = "development"
check "cats.conf pkginst key works as a fallback" \
    test "$(field "$S15b/catalog" jutoy 8)" = "x11"

# an override apkg could not parse is refused per-package, never emitted:
# a category holding a space makes apkg reject the WHOLE catalog.
S15c="$WORK/t15c"; mkdir -p "$S15c"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S15c/"
printf 'jutoy: open look\n' > "$S15c/cats.conf"
python3 "$GEN" "$S15c" >/dev/null 2>"$WORK/t15c.err"
check "spacey category is refused, not emitted" \
    bash -c "! grep -q 'open look' '$S15c/catalog'"
check "spacey category reported as a SKIP" \
    grep -q 'SKIP toy.pkg' "$WORK/t15c.err"
check "spacey category names cats.conf in the message" \
    grep -q 'cats.conf: bad category' "$WORK/t15c.err"
check "the other package still catalogs" \
    test "$(field "$S15c/catalog" testpkg 3)" = "TESTpkg"

# a DECLARED vocabulary is a CLOSED set.  '@group' lines say which categories
# the repo is willing to emit; an override outside them is a typo or an
# unagreed group, and either way it lands in the installer as a heading
# nobody chose -- so it is refused per-package, exactly like a spacey one.
S15d="$WORK/t15d"; mkdir -p "$S15d"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S15d/"
printf '@group games: games\n@group x11: the X stack\njutoy: games\n' \
    > "$S15d/cats.conf"
python3 "$GEN" "$S15d" >/dev/null 2>"$WORK/t15d.err"
check "an override naming a DECLARED group is applied" \
    test "$(field "$S15d/catalog" jutoy 8)" = "games"
printf '@group games: games\njutoy: utility\n' > "$S15d/cats.conf"
python3 "$GEN" "$S15d" >/dev/null 2>"$WORK/t15d2.err"
check "an override naming an UNDECLARED group is refused" \
    bash -c "! grep -q '^jutoy|' '$S15d/catalog'"
check "the refusal names the undeclared category" \
    grep -q 'undeclared category' "$WORK/t15d2.err"
check "a package outside the vocabulary still catalogs" \
    test "$(field "$S15d/catalog" testpkg 3)" = "TESTpkg"
# the pkginfo fallback stays permissive (it is upstream metadata, not
# hand-authored here) but says so, because that is the path by which a
# sibling repo's un-agreed CATEGORY would reach the catalog unnoticed
check "a pkginfo CATEGORY outside a declared vocabulary warns" \
    grep -q 'not a declared cats.conf group' "$WORK/t15d2.err"

# '@group' grammar errors are fatal, not silently-ignored lines
G15="$WORK/t15g"; mkdir -p "$G15"
cp "$FIX/toy.pkg" "$G15/"
printf '@group games: a\n@group games: b\n' > "$G15/cats.conf"
python3 "$GEN" "$G15" >/dev/null 2>"$WORK/t15g1.err"
check "a duplicate @group declaration is an error" test $? -ne 0
check "the duplicate group is named" grep -q 'declared twice' "$WORK/t15g1.err"
printf '@group open look: the toolkit\n' > "$G15/cats.conf"
python3 "$GEN" "$G15" >/dev/null 2>"$WORK/t15g2.err"
check "a spacey @group token is an error" test $? -ne 0
check "the bad group token is reported" \
    grep -q 'bad group token' "$WORK/t15g2.err"
printf '@nosuch thing: value\n' > "$G15/cats.conf"
python3 "$GEN" "$G15" >/dev/null 2>"$WORK/t15g3.err"
check "an unknown @ statement is an error" test $? -ne 0
check "the unknown statement is reported" \
    grep -q 'unknown statement' "$WORK/t15g3.err"

# the REPO's authored taxonomy: well-formed, one token per category, every
# assigned category declared, and covering exactly the packages the install
# sets name (drift guard vs sets.conf).
CATS="$HERE/../cats.conf"
check "tools/repo/cats.conf exists" test -f "$CATS"
# cats.conf carries TWO statement types, so split them once and assert over
# each rather than grepping ':' and hoping.
grep -v '^[[:space:]]*#' "$CATS" | grep ':' | grep -v '^[[:space:]]*@' \
    > "$WORK/cats.assign"
sed 's/^[^:]*:[[:space:]]*//' "$WORK/cats.assign" > "$WORK/cats.values"
sed 's/:.*//; s/[[:space:]]//g' "$WORK/cats.assign" | sort > "$WORK/cats.keys"
grep '^[[:space:]]*@group[[:space:]]' "$CATS" \
    | sed 's/^[[:space:]]*@group[[:space:]]*//; s/[[:space:]]*:.*//' \
    | sort > "$WORK/cats.groups"
check "every cats.conf value is a single token" \
    bash -c "test -z \"\$(grep -v '^[A-Za-z0-9][A-Za-z0-9+.-]*\$' \
                          '$WORK/cats.values')\""
check "every @group token is a single token" \
    bash -c "test -z \"\$(grep -v '^[A-Za-z0-9][A-Za-z0-9+.-]*\$' \
                          '$WORK/cats.groups')\""
# The vocabulary is LOCKED, the way the set memberships are: it is the
# contract the sibling amix-packages registry validates its per-package
# `category:` against (its roadmap item X3).  `editor` still carries no
# package in THIS repo (BATCH-1 populated `utility`/`development` instead)
# and must not be pruned as unused.  `archive` added 2026-10-30 (owner).
check "cats.conf declares exactly the thirteen agreed groups" \
    bash -c "diff '$WORK/cats.groups' <(printf '%s\n' archive development \
        documentation editor emacs games network openlook source system \
        text utility x11)"
check "every assigned category is a declared group" \
    bash -c "test -z \"\$(comm -23 <(sort -u '$WORK/cats.values') \
                                   '$WORK/cats.groups')\""
check "cats.conf covers exactly the packages the install sets name" \
    bash -c "diff '$WORK/cats.keys' \
                  <(python3 '$HERE/../sets.py' --all | awk '{print \$2}' \
                    | sort -u)"

# --------------------------------------------------------------- T20 ----
# names.conf -- the catalog-name override.  Its failure mode is SILENT: with
# no mapping a package whose name cannot be its pkginst (the 9-char SVR4
# ceiling) comes out under the short instance name, no error, no warning, a
# well-formed but WRONG catalog.  So the checks below are about the file
# existing, being staged, and actually doing the work.
echo "T20: names.conf catalog-name override"
NAMES="$HERE/../names.conf"
check "tools/repo/names.conf exists" test -f "$NAMES"
grep -v '^[[:space:]]*#' "$NAMES" | grep ':' > "$WORK/names.assign"
sed 's/:.*//; s/[[:space:]]//g' "$WORK/names.assign" | sort > "$WORK/names.keys"
sed 's/^[^:]*:[[:space:]]*//' "$WORK/names.assign" > "$WORK/names.values"
check "every names.conf key is a valid PKG instance" \
    bash -c "test -z \"\$(grep -vE '^[A-Za-z0-9][A-Za-z0-9+.-]*\$' \
                          '$WORK/names.keys')\""
# the whole point of the file: the KEY is the thing that must fit in 9 chars
check "every names.conf key obeys the 9-char SVR4 PKG limit" \
    bash -c "test -z \"\$(awk 'length(\$0) > 9' '$WORK/names.keys')\""
check "every names.conf value is a valid catalog name" \
    bash -c "test -z \"\$(grep -vE '^[A-Za-z0-9][A-Za-z0-9+.-]*\$' \
                          '$WORK/names.values')\""
check "no names.conf value contains the field separator" \
    bash -c "! grep -q '|' '$WORK/names.values'"

# PINNED membership.  A catalog-name mapping is a RENAME as far as every
# deployed box is concerned -- `apkg install <name>` stops resolving under the
# old one -- so adding a second mapping must be a deliberate edit of this
# test, never drift.  Today: amixbench -> amix-benchmark (published 09-16);
# gtar -> tar (amix-packages batch-2, staged 2026-09-26); diffutil ->
# diffutils and coreutil -> coreutils (GCC 14 batch, mapped 2026-10-30).
check "names.conf maps exactly the packages that need it" \
    bash -c "diff '$WORK/names.keys' <(printf '%s\n' amixbench gtar \
                                       diffutil coreutil | sort)"
check "amixbench maps to the published catalog name" \
    grep -q '^amixbench:[[:space:]]*amix-benchmark$' "$NAMES"
check "gtar maps to the batch-2 catalog name" \
    grep -q '^gtar:[[:space:]]*tar$' "$NAMES"
check "diffutil maps to the catalog name diffutils" \
    grep -q '^diffutil:[[:space:]]*diffutils$' "$NAMES"
check "coreutil maps to the catalog name coreutils" \
    grep -q '^coreutil:[[:space:]]*coreutils$' "$NAMES"

# drift guard: staged on every mint, or the authored file is one nobody reads
check "build-packages.sh stages names.conf into the staging root" \
    grep -q 'cp "\$REPO/tools/repo/names.conf" "\$STAGING/names.conf"' \
        "$HERE/../build-packages.sh"

# ★ NON-VACUOUS PAIR: the same fixture, generated with and without the file.
# Without this pair, every check above could pass while names.conf did
# nothing at all.  toy.pkg has PKG=JUTOY, so its default catalog name is
# `jutoy`; a mapping must move it, and removing the mapping must move it back.
S20="$WORK/t20"; mkdir -p "$S20"
cp "$FIX/toy.pkg" "$S20/"
python3 "$GEN" "$S20" >/dev/null 2>&1
check "without names.conf the name defaults to the lowercased pkginst" \
    test "$(field "$S20/catalog" jutoy 1)" = jutoy
printf 'JUTOY: toy-with-a-long-name\n' > "$S20/names.conf"
python3 "$GEN" "$S20" >/dev/null 2>&1
check "with names.conf the mapped name is what lands in the catalog" \
    test "$(field "$S20/catalog" toy-with-a-long-name 1)" = toy-with-a-long-name
check "the pkginst column still carries the SVR4 instance" \
    test "$(field "$S20/catalog" toy-with-a-long-name 3)" = JUTOY
check "the old default name is gone from the catalog" \
    bash -c "! grep -q '^jutoy|' '$S20/catalog'"
# the key is the pkginst EXACTLY as pkginfo spells it -- a lowercased key is
# a silent no-op, which is the trap this file is most likely to be edited into
printf 'jutoy: wrong-case-key\n' > "$S20/names.conf"
python3 "$GEN" "$S20" >/dev/null 2>&1
check "a wrong-case key does NOT match (keys are the literal PKG)" \
    test "$(field "$S20/catalog" jutoy 1)" = jutoy

# and the real authored file must survive the real generator
S20B="$WORK/t20b"; mkdir -p "$S20B"
cp "$FIX/toy.pkg" "$S20B/"
cp "$NAMES" "$S20B/names.conf"
python3 "$GEN" "$S20B" >/dev/null 2>"$WORK/t20b.err"
check "the authored names.conf parses without error" test $? -eq 0
check "it leaves an unlisted package alone" \
    test "$(field "$S20B/catalog" jutoy 1)" = jutoy

# --------------------------------------------------------------- T19 ----
# payload-licence-gate.py -- "no foreign object code leaves in OUR builds".
# A gate that inspects nothing prints the same thing as a gate that inspects
# everything and finds nothing, so every check here is paired: it must FIRE on
# the known positive as well as pass the negatives.
echo "T19: payload licence gate"
PLG="$HERE/../payload-licence-gate.py"
check "tools/repo/payload-licence-gate.py exists" test -f "$PLG"
check "its own self-test passes" python3 "$PLG" --self-test

# the detector, exercised directly on signatures (no package needed)
plg_verdict() {
    python3 - "$PLG" "$@" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
hits = sorted(set(sys.argv[2:]) & m.LIBM_OBJECTS)
dist = sorted(set(hits) & m.LIBM_DISTINCTIVE)
print("REFUSE" if (dist or len(hits) >= m.LIBM_COOCCURRENCE)
      else ("look" if hits else "clean"))
PY
}
check "FIRES on the real whet signature" \
    test "$(plg_verdict atan.c exp.c log.c matherr.c reduce.c sin.c sqrt.c)" \
       = REFUSE
check "a distinctive marker alone is enough" \
    test "$(plg_verdict matherr.c)" = REFUSE
check "three co-occurring libm names are enough" \
    test "$(plg_verdict sin.c sqrt.c exp.c)" = REFUSE
# the false positive that would have made this gate unusable
check "an honest project's own log.c does NOT refuse" \
    test "$(plg_verdict log.c main.c util.c)" = look
check "a clean binary is clean" test "$(plg_verdict dhry.c main.c)" = clean

# anti-vacuity: an empty path must not pass, a binary-free package must
T19W="$WORK/t19"; mkdir -p "$T19W/empty" "$T19W/nobin"
cp "$HERE/fixtures/toy.pkg" "$T19W/nobin/"
python3 "$PLG" "$T19W/empty" >/dev/null 2>&1
check "an empty path is NOT a pass" test $? -ne 0
python3 "$PLG" "$T19W/nobin" >/dev/null 2>&1
check "a binary-free package IS a pass" test $? -eq 0
check "it says nothing was inspected rather than OK" \
    bash -c "python3 '$PLG' '$T19W/empty' 2>&1 | grep -q 'NOTHING INSPECTED'"

# scope: vendor content is skipped, and the skip is announced, not silent
mkdir -p "$T19W/scoped/stock"
cp "$HERE/fixtures/toy.pkg" "$T19W/scoped/stock/"
check "vendor stock/ is skipped by provenance path" \
    bash -c "python3 '$PLG' '$T19W/scoped' 2>&1 | grep -q 'skipping 1 vendor package'"
check "the skip is visible in the output, never silent" \
    bash -c "python3 '$PLG' '$T19W/scoped' 2>&1 | grep -q 'include-stock'"

# a Kickstart ROM image refuses, loose or inside a real datastream.  The image
# is synthetic: the reset header of a 512K Kickstart and zeros, no ROM bytes.
mkdir -p "$T19W/rom" "$T19W/rompkg/spool" "$T19W/romswap"
python3 -c 'import sys; open(sys.argv[1],"wb").write(b"\x11\x14\x4e\xf9\x00\xf8\x00\xd2"+bytes(524280))' \
    "$T19W/rom/kick.bin"
python3 -c 'import sys; open(sys.argv[1],"wb").write(b"\x14\x11\xf9\x4e"+bytes(262140))' \
    "$T19W/romswap/kick.bin"
python3 "$PLG" "$T19W/rom" >"$WORK/t19rom.out" 2>&1
check "a loose Kickstart ROM image refuses (rc 2)" test $? -eq 2
check "... and says why" grep -q 'Kickstart ROM image' "$WORK/t19rom.out"
python3 "$PLG" "$T19W/romswap" >/dev/null 2>&1
check "a byte-swapped Kickstart ROM image refuses (rc 2)" test $? -eq 2
T19HB="$HERE/../../../heirloom/build-host/bin"
if [ -x "$T19HB/pkgmk" ] && [ -x "$T19HB/pkgtrans" ]; then
    printf 'PKG=ROMTEST\nNAME=rom fixture\nVERSION=1.0\nARCH=m68k\nCATEGORY=application\nCLASSES=none\nBASEDIR=/\n' \
        > "$T19W/rompkg/pkginfo"
    printf 'i pkginfo=%s\nd none /opt/romtest 0755 root sys\nf none /opt/romtest/kick.rom=%s 0644 root sys\n' \
        "$T19W/rompkg/pkginfo" "$T19W/rom/kick.bin" > "$T19W/rompkg/prototype"
    mkdir -p "$T19W/romstg"
    ( cd "$T19W/rompkg" && "$T19HB/pkgmk" -o -d "$T19W/rompkg/spool" -f prototype && \
      "$T19HB/pkgtrans" -s "$T19W/rompkg/spool" "$T19W/romstg/ROMTEST-1.0.pkg" ROMTEST ) \
        >"$WORK/t19rom.mk" 2>&1
    python3 "$PLG" "$T19W/romstg" >"$WORK/t19rompkg.out" 2>&1
    check "a Kickstart ROM inside a .pkg payload refuses (rc 2)" test $? -eq 2
    check "... named by its path inside the package" \
        grep -q 'ROMTEST-1.0.pkg!.*kick.rom.*Kickstart ROM image' "$WORK/t19rompkg.out"
else
    echo "  skip- Kickstart ROM in a datastream (host pkgmk/pkgtrans missing)"
fi

# publish.sh must actually call it -- a gate nobody runs is not a gate
check "publish.sh invokes the payload licence gate" \
    grep -q 'payload-licence-gate.py' "$HERE/../publish.sh"
check "publish.sh treats a payload refusal as fatal" \
    grep -q 'exit 5' "$HERE/../publish.sh"
check "publish.sh offers no --force for it" \
    bash -c "! grep -A6 'payload licence gate' '$HERE/../publish.sh' | grep -q ' --force'"

# --------------------------------------------------------------- T16 ----
# sets.conf -- the five named install sets.  These memberships are LOCKED
# (installer-UX rework plan section 8.4); the assertions below are the lock.
echo "T16: sets.conf named install sets"
SETS="$HERE/../sets.py"
SETSCONF="$HERE/../sets.conf"
check "tools/repo/sets.conf exists" test -f "$SETSCONF"
check "tools/repo/sets.py resolves it without error" \
    python3 "$SETS" --all

setis() { # setis <set> <space-separated expected membership>
    check "$1 resolves to exactly its locked membership" \
        test "$(python3 "$SETS" "$1" | tr '\n' ' ')" = "$2 "
}
setis minimal "apkg apkgeng bsd cdfs core net sysadm text"
setis standard "apkg apkgeng bsd cdev cdfs core lp man net olcore public \
sysadm terminfo text uucp xbasic xcore"
setis full "amigasrc apkg apkgeng bsd cdev cdfs conf core emacs emacsrc \
games gnusrc gnusrc2 lp man net olcore oldev public pubsrc sysadm terminfo \
text uucp x11r5src xbasic xcore xdev xsource xtras"
setis developer "apkg apkgeng bsd cdev cdfs core lp man net olcore oldev \
public sysadm terminfo text uucp xbasic xcore xdev"
setis x11 "apkg apkgeng bsd cdev cdfs core lp man net olcore public sysadm \
terminfo text uucp xbasic xcore xtras"

check "minimal is the proven base-8 (8 packages)" \
    test "$(python3 "$SETS" minimal | wc -l)" = 8
check "full is the 30 packages we ship" \
    test "$(python3 "$SETS" full | wc -l)" = 30
check "standard is the 14 non-opt stock packages + our 3" \
    test "$(python3 "$SETS" standard | wc -l)" = 17
check "conf is in full" \
    bash -c "python3 '$SETS' full | grep -qx conf"
check "conf is EXCLUDED from developer (locked user decision)" \
    bash -c "! python3 '$SETS' developer | grep -qx conf"
check "developer = standard + xdev + oldev, nothing else" \
    bash -c "diff <(python3 '$SETS' developer) \
                  <( { python3 '$SETS' standard; echo xdev; echo oldev; } | sort)"
check "x11 = standard + xtras, nothing else" \
    bash -c "diff <(python3 '$SETS' x11) \
                  <( { python3 '$SETS' standard; echo xtras; } | sort)"
check "minimal is a subset of standard" \
    bash -c "test -z \"\$(comm -23 <(python3 '$SETS' minimal) \
                                   <(python3 '$SETS' standard))\""
check "standard is a subset of full" \
    bash -c "test -z \"\$(comm -23 <(python3 '$SETS' standard) \
                                   <(python3 '$SETS' full))\""
# The PRIVATE kernel packages are off-catalog by the KSUM_R/BOOT2_SHA marker
# gates (T13).  A set naming one would invite pressure to weaken those gates,
# so no set may ever name one.
check "no set names a KERN* private kernel package" \
    bash -c "! python3 '$SETS' --all | grep -qi 'kern'"
check "no set names a test fixture (amixdemo/demolib)" \
    bash -c "! python3 '$SETS' --all | grep -Eq ' (amixdemo|demolib)\$'"

# `extra` -- the add-on userland from the sibling amix-packages repo.  It is
# OFF the composition chain, and it must never leak into the five locked
# memberships: `full` is "the Amix 2.1 distribution + our three", not "every
# package in the catalog", and the metal installer's regression identity is
# built on that.  Populated 2026-09-16 with BATCH-1 (published 2026-09-15,
# catalog 32 -> 38), amix-benchmark (published 2026-09-16, catalog 38 -> 39)
# and batch-2's make + tar (staged 2026-09-26, catalog -> 41), then the GCC 14
# batch's bzip2, coreutils and diffutils (assigned 2026-10-30, unpublished);
# pinned to the measured membership so a future batch must touch this test
# deliberately, not by drift.
check "the add-on set 'extra' is declared" bash -c "python3 '$SETS' extra"
check "extra is the twelve add-on packages" \
    test "$(python3 "$SETS" extra | tr '\n' ' ')" = \
         "acompat amix-benchmark bzip2 coreutils diffutils grep gzip less make patch tar zlib "
check "extra and full are disjoint" \
    bash -c "test -z \"\$(comm -12 <(python3 '$SETS' extra) \
                                   <(python3 '$SETS' full))\""
check "no locked installer set includes +extra" \
    bash -c "! grep -Eq '^(minimal|standard|full|developer|x11):.*\+extra' \
             '$SETSCONF'"

# grammar: multi-line accumulation, '+' includes, cycles, unknown sets
G16="$WORK/t16"; mkdir -p "$G16"
printf 'a: one,two\na: three\nb: +a,four\n' > "$G16/sets.conf"
check "a set declared on several lines accumulates" \
    test "$(python3 "$SETS" -f "$G16/sets.conf" a | tr '\n' ' ')" = "one three two "
check "'+set' includes are expanded" \
    test "$(python3 "$SETS" -f "$G16/sets.conf" b | tr '\n' ' ')" = "four one three two "
printf 'a: +b\nb: +a\n' > "$G16/cycle.conf"
python3 "$SETS" -f "$G16/cycle.conf" a >/dev/null 2>"$WORK/t16.cyc"
check "an include cycle is an error, not a hang" test $? -ne 0
check "the cycle is named in the message" grep -q 'include cycle' "$WORK/t16.cyc"
python3 "$SETS" -f "$G16/sets.conf" nosuchset >/dev/null 2>"$WORK/t16.uns"
check "an unknown set exits nonzero" test $? -ne 0
check "an unknown set says so" grep -q 'no such set' "$WORK/t16.uns"
printf 'a one two\n' > "$G16/bad.conf"
python3 "$SETS" -f "$G16/bad.conf" >/dev/null 2>&1
check "a line without ':' is a parse error" test $? -ne 0
printf '# only a comment\n\n' > "$G16/empty.conf"
check "comments and blank lines are ignored" \
    python3 "$SETS" -f "$G16/empty.conf"

# The miniroot resolves sets in 1991 pre-POSIX Bourne sh, not python, so the
# grammar's real claim is "two independent implementations agree".  This is
# that second implementation: sed + tr + while-read, no arrays, no
# functions-with-local, no $( ) -- and it must reproduce sets.py exactly.
cat > "$WORK/shsets.sh" <<'SHEOF'
# usage: sh shsets.sh <sets.conf> <setname>   -- prints members, one per line
conf=$1
pending=$2
seen=
out=
while [ -n "$pending" ]; do
    set -- $pending
    cur=$1
    shift
    pending="$*"
    case " $seen " in *" $cur "*) continue ;; esac
    seen="$seen $cur"
    members=`sed -n "s/^$cur:[ 	]*//p" "$conf" | tr ',' ' '`
    for m in $members; do
        case "$m" in
            +*) pending="$pending `echo $m | cut -c2-`" ;;
            *)  out="$out $m" ;;
        esac
    done
done
echo $out | tr ' ' '\n' | grep -v '^$' | sort -u
SHEOF
for s in minimal standard full developer x11 extra; do
    check "pre-POSIX sh filter loop agrees with sets.py on '$s'" \
        bash -c "diff <(sh '$WORK/shsets.sh' '$SETSCONF' $s) \
                      <(python3 '$SETS' $s)"
done

# --------------------------------------------------------------- T17 ----
# s5-collision-scan.py -- the 14-character (s5) name-collision scanner.
#
# The fixtures below are synthetic datastreams whose pkgmaps are hand-written
# to contain, in one small set, every shape that decides the answer:
#
#   * the same aliasing pair in TWO directories (WORK/ and ZAPHOD/) -- the
#     shape W6's basename-only key MERGED into one row;
#   * two DIFFERENT over-long basenames sharing a 14-character prefix but
#     living in different directories -- the shape that same key INVENTS a
#     collision for;
#   * an exactly-14 basename aliased by a longer one -- a real collision that
#     a key restricted to over-long names cannot see at all;
#   * a symlink (ftype s) colliding with a regular file, so the group is not
#     even type-homogeneous;
#   * a device node and a pipe (excluded from the truncation universe), an
#     `i` line (never an installed object) and a directory declared by BOTH
#     packages (de-duplicated to one object).
#
# Expected, by hand: 16 objects, 14 in the truncation universe, 9 basenames
# over 14 characters and 10 at 14 or over, 3 real collision groups -- and 2
# by the W6 key, which is wrong in three separate ways at once.
echo "T17: s5-collision-scan.py (14-character name collisions)"
SCAN="$HERE/../s5-collision-scan.py"
S17="$WORK/t17"; mkdir -p "$S17"

mkpkg() { # mkpkg <staging-dir> <PKG> <pkgmap-file>
    _d="$1"; _p="$2"; _m="$3"
    mkdir -p "$_d/build/$_p"
    cat > "$_d/build/$_p/pkginfo" <<EOF
PKG=$_p
NAME=$_p s5 collision fixture
ARCH=m68k
VERSION=1.0
CATEGORY=application
EOF
    cp "$_m" "$_d/build/$_p/pkgmap"
    {   printf '# PaCkAgE DaTaStReAm\n%s 1 1\n# end of header\n' "$_p"
        head -c 512 /dev/zero
    } | head -c 512 > "$_d/build/hdr"
    ( cd "$_d/build" && printf '%s/pkginfo\n%s/pkgmap\n' "$_p" "$_p" \
        | cpio -o -H odc --quiet > arch1 )
    cat "$_d/build/hdr" "$_d/build/arch1" > "$_d/$_p.pkg"
    rm -rf "$_d/build"
}

cat > "$WORK/t17-a.pkgmap" <<'EOF'
: 1 100
1 i pkginfo 200 12345 1234567890
1 d none /opt/coll 0755 root sys
1 d none /opt/coll/WORK 0755 root sys
1 d none /opt/coll/ZAPHOD 0755 root sys
1 f none /opt/coll/WORK/amixInitExtDMI.c 0644 root sys 100 1 1
1 f none /opt/coll/WORK/amixInitExtDMI.o 0644 root sys 100 1 1
1 s none /opt/coll/ZAPHOD/amixInitExtDMI.c=../mi/miinitext.c
1 f none /opt/coll/ZAPHOD/amixInitExtDMI.o 0644 root sys 100 1 1
1 f none /opt/coll/uniquelongname1.c 0644 root sys 100 1 1
1 c none /dev/collzero 47 0 0644 root sys
1 p none /opt/coll/fifo 0644 root sys
EOF
cat > "$WORK/t17-b.pkgmap" <<'EOF'
: 1 100
1 i pkginfo 200 12345 1234567890
1 d none /opt/coll 0755 root sys
1 d none /opt/other 0755 root sys
1 f none /opt/other/uniquelongname1.c 0644 root sys 100 1 1
1 f none /opt/coll/exactly14chars 0644 root sys 100 1 1
1 f none /opt/coll/exactly14charsPLUS 0644 root sys 100 1 1
1 f none /opt/coll/verylongfilename.a 0644 root sys 100 1 1
1 f none /opt/other/verylongfilename.b 0644 root sys 100 1 1
EOF
mkpkg "$S17" COLLA "$WORK/t17-a.pkgmap"
mkpkg "$S17" COLLB "$WORK/t17-b.pkgmap"

python3 "$SCAN" "$S17" >"$WORK/t17.out" 2>"$WORK/t17.err"
check "scan exits 0" test $? -eq 0

count() { # count <label prefix> -> the trailing number of that report line
    awk -v k="$1" 'index($0, k) == 1 { print $NF }' "$WORK/t17.out"
}
is() { # is <description> <label prefix> <expected>
    check "$1" test "$(count "$2")" = "$3"
}
is "object universe de-duplicates the shared directory (16)" \
    "object universe" 16
is "truncation universe excludes the device node and the pipe (14)" \
    "truncation universe" 14
is "basenames over 14 characters (9)" "basenames > 14" 9
is "basenames at 14 or over (10)" "basenames >= 14" 10
is "3 real collision groups, keyed per directory" \
    "collision groups (dir," 3
is "the W6 basename-only key would say 2" \
    "collision groups, basename-only" 2

# WORK/ and ZAPHOD/ must be reported SEPARATELY -- this is the W6 defect.
check "WORK and ZAPHOD are two distinct groups, not one" \
    test "$(grep -c 'amixInitExtDMI$' "$WORK/t17.out")" = 2
check "the ZAPHOD group is reported" \
    grep -q '/opt/coll/ZAPHOD/  ->  amixInitExtDMI' "$WORK/t17.out"
check "the symlink member is reported with ftype s" \
    grep -qE 'amixInitExtDMI\.c +s +COLLA' "$WORK/t17.out"
check "the exactly-14 basename collides with the longer one" \
    grep -q '/opt/coll/  ->  exactly14chars' "$WORK/t17.out"
check "same over-long name in two directories is NOT a collision" \
    bash -c "! grep -q 'uniquelongname' '$WORK/t17.out'"
check "two over-long names in DIFFERENT directories are NOT a collision" \
    bash -c "! grep -q 'verylongfilename' '$WORK/t17.out'"
check "the i (pkginfo) line is not an installed object" \
    bash -c "! grep -q ' pkginfo' '$WORK/t17.out'"
check "--fail-on-collision exits non-zero when a group exists" \
    bash -c "! python3 '$SCAN' --fail-on-collision '$S17' >/dev/null 2>&1"

# A clean set must scan clean and gate green.
S17C="$WORK/t17c"; mkdir -p "$S17C"
sed -i -e '/verylongfilename/d' -e '/exactly14charsPLUS/d' \
    "$WORK/t17-b.pkgmap"
mkpkg "$S17C" COLLB "$WORK/t17-b.pkgmap"
check "a set with no aliasing pair passes --fail-on-collision" \
    python3 "$SCAN" --fail-on-collision "$S17C"

# The pinned regression constants, against a local mirror of the published
# tree when one is present.  These are the numbers docs/s5-14char-collisions.md
# is written from; --check re-derives all seven from the .pkg files themselves.
# The published tree lives at http://pkg.amigaux.org/ since 2026-09-15, so this
# needs a local copy: set PUBLISHED to a mirror of it (e.g. the frozen mirror
# the first publish was made from).  Unset, the check is skipped.
PUBLISHED="${PUBLISHED:-}"
if [ -n "$PUBLISHED" ] && [ -f "$PUBLISHED/catalog" ]; then
    check "pinned constants for the published 'full' set all match" \
        python3 "$SCAN" --check -s full -q "$PUBLISHED"
else
    echo "  skip- pinned constants (no published tree at '${PUBLISHED:-<PUBLISHED unset>}')"
fi

# --------------------------------------------------------------- T18 ----
# descs.conf -- catalog-level DESCRIPTION override.  Same contract as
# cats.conf one field over: the ninth column is rewritten WITHOUT
# re-minting, so the served bytes and every .pkg md5 the digest gates
# depend on must not move.
echo "T18: descs.conf description override"
S18="$WORK/t18"; mkdir -p "$S18"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S18/"
python3 "$GEN" "$S18" >/dev/null 2>&1
PRE_DESC="$(field "$S18/catalog" jutoy 9)"
PRE_MD5="$(md5sum "$S18/toy.pkg" | cut -d' ' -f1)"
PRE_LINE="$(grep '^jutoy|' "$S18/catalog")"
# a colon in the TEXT must survive: only the first colon separates
printf '# prose\njutoy: A toy: do NOT run it (see NOTES)\n' > "$S18/descs.conf"
python3 "$GEN" "$S18" >/dev/null 2>&1
check "descs.conf wins over the pkginfo description" \
    test "$(field "$S18/catalog" jutoy 9)" = "A toy: do NOT run it (see NOTES)"
check "the pkginfo description it replaced was different" \
    test "$PRE_DESC" != "A toy: do NOT run it (see NOTES)"
check "package absent from descs.conf keeps its pkginfo description" \
    test "$(field "$S18/catalog" testpkg 9)" = "Test Package"
check "the .pkg file itself is untouched (md5 unmoved)" \
    test "$(md5sum "$S18/toy.pkg" | cut -d' ' -f1)" = "$PRE_MD5"
check "only the description field moved on the entry line" \
    test "$(grep '^jutoy|' "$S18/catalog" | awk -F'|' '{$9="X"; print}')" = \
         "$(printf '%s' "$PRE_LINE" | awk -F'|' '{$9="X"; print}')"

# keyed by the catalog name post names.conf mapping, with pkginst fallback
S18B="$WORK/t18b"; mkdir -p "$S18B"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S18B/"
printf 'TESTpkg: amixtest\n' > "$S18B/names.conf"
printf 'amixtest: Mapped by catalog name\nJUTOY: Mapped by pkginst\n' \
    > "$S18B/descs.conf"
python3 "$GEN" "$S18B" >/dev/null 2>&1
check "descs.conf keyed by the mapped catalog name" \
    test "$(field "$S18B/catalog" amixtest 9)" = "Mapped by catalog name"
check "descs.conf pkginst key works as a fallback" \
    test "$(field "$S18B/catalog" jutoy 9)" = "Mapped by pkginst"

# a '|' would be the FIELD SEPARATOR.  clean_field() would silently rewrite
# it to '/', which quietly rewrites an operator's authored sentence -- so
# the line is refused per-package instead, exactly like a spacey category.
S18C="$WORK/t18c"; mkdir -p "$S18C"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S18C/"
printf 'jutoy: pipe | inside\n' > "$S18C/descs.conf"
python3 "$GEN" "$S18C" >/dev/null 2>"$WORK/t18c.err"
check "a description holding '|' is refused, not silently rewritten" \
    bash -c "! grep -q '^jutoy|' '$S18C/catalog'"
check "the refusal names descs.conf" \
    grep -q "descs.conf: description for jutoy contains" "$WORK/t18c.err"
check "the refusal never emitted the rewritten form" \
    bash -c "! grep -q 'pipe / inside' '$S18C/catalog'"
check "the other package still catalogs" \
    test "$(field "$S18C/catalog" testpkg 3)" = "TESTpkg"

# an EMPTY override is a truncated line, not an instruction to blank a
# description the pkginfo did supply
printf 'jutoy:\n' > "$S18C/descs.conf"
python3 "$GEN" "$S18C" >/dev/null 2>"$WORK/t18c2.err"
check "an empty description override is refused" \
    bash -c "! grep -q '^jutoy|' '$S18C/catalog'"
check "the empty-override refusal says how to fall back" \
    grep -q "descs.conf: empty description for jutoy" "$WORK/t18c2.err"

# Gate 8: a line apkg's fgets() buffer cannot read rejects the WHOLE
# catalog in the CLIENT, so the generator fails closed rather than writing
# one -- the Gate 7 posture, for the one free-text column.
S18D="$WORK/t18d"; mkdir -p "$S18D"
cp "$FIX/TESTpkg.pkg" "$FIX/toy.pkg" "$S18D/"
python3 "$GEN" "$S18D" >/dev/null 2>&1
check "baseline catalog written before the long-line case" \
    test -f "$S18D/catalog"
BASE_MD5="$(md5sum "$S18D/catalog" | cut -d' ' -f1)"
python3 -c "print('jutoy: ' + 'x' * 2100)" > "$S18D/descs.conf"
python3 "$GEN" "$S18D" >/dev/null 2>"$WORK/t18d.err"
check "an over-long entry line is FATAL (rc=2)" test $? -eq 2
check "the over-long line names Gate 8" \
    grep -q 'Gate 8: entry line too long' "$WORK/t18d.err"
check "the message points at the description as the cause" \
    grep -q 'shorten the description' "$WORK/t18d.err"
check "no catalog was written over the good one" \
    test "$(md5sum "$S18D/catalog" | cut -d' ' -f1)" = "$BASE_MD5"
# and the largest line that DOES fit is still written: the bound is a real
# edge, not a round-down
python3 - "$S18D" "$GEN" <<'PYEOF'
import subprocess, sys
staging, gen = sys.argv[1], sys.argv[2]
# no search needed: measure the line the generator writes for a 1-char
# description, then pad the description out to land exactly on the limit
open(staging + "/descs.conf", "w").write("jutoy: x\n")
subprocess.run(["python3", gen, staging], capture_output=True)
line = [l for l in open(staging + "/catalog") if l.startswith("jutoy|")][0]
fixed = len(line.rstrip("\n")) - 1          # everything but the 1-char desc
open(staging + "/descs.conf", "w").write("jutoy: " + "x" * (2046 - fixed) + "\n")
PYEOF
python3 "$GEN" "$S18D" >/dev/null 2>"$WORK/t18d2.err"
check "a line exactly at the 2046-byte limit is accepted" test $? -eq 0
check "that limit line really is 2046 bytes" \
    test "$(grep '^jutoy|' "$S18D/catalog" | wc -c)" = 2047

# the REPO's authored descriptions: well-formed, ours only, and readable
# by the client that has to parse them.
DESCS="$HERE/../descs.conf"
check "tools/repo/descs.conf exists" test -f "$DESCS"
grep -v '^[[:space:]]*#' "$DESCS" | grep ':' > "$WORK/descs.assign"
sed 's/:.*//; s/[[:space:]]//g' "$WORK/descs.assign" | sort \
    > "$WORK/descs.keys"
check "every descs.conf line is 'name: text'" \
    bash -c "test -z \"\$(grep -v '^[A-Za-z0-9][A-Za-z0-9+.-]*:' \
                          '$WORK/descs.assign')\""
check "no descs.conf description contains the field separator" \
    bash -c "! grep -q '|' '$WORK/descs.assign'"
# OURS ONLY.  descs.conf is staged on every mint (build-packages.sh copies
# it beside deps.conf), and that is only safe while it names packages WE
# mint: a key naming a stock package would move a published stock line the
# moment anyone re-generates the catalog.
check "descs.conf names only packages this repo mints" \
    bash -c "test -z \"\$(comm -23 '$WORK/descs.keys' \
        <(printf '%s\n' apkg apkgeng cdfs amixdemo demolib | sort))\""
check "the apkg entry carries the 0.1 upgrade warning" \
    grep -q "^apkg:.*do NOT run 'apkg upgrade apkg'" "$DESCS"
check "the apkg entry keeps the plain one-liner in front of it" \
    grep -q '^apkg: Remote package client: update/list/search/install over HTTP\.' \
        "$DESCS"
# drift guard: build-packages.sh must actually stage it, or the authored
# file is a file nobody reads
check "build-packages.sh stages descs.conf into the staging root" \
    grep -q 'cp "\$REPO/tools/repo/descs.conf" "\$STAGING/descs.conf"' \
        "$HERE/../build-packages.sh"
# and the real file must survive the real generator, on a real package
S18E="$WORK/t18e"; mkdir -p "$S18E"
cp "$FIX/toy.pkg" "$S18E/"
cp "$DESCS" "$S18E/descs.conf"
python3 "$GEN" "$S18E" >/dev/null 2>"$WORK/t18e.err"
check "the authored descs.conf parses without error" test $? -eq 0
check "it leaves an unlisted package alone" \
    test "$(field "$S18E/catalog" jutoy 9)" = "$PRE_DESC"

# --------------------------------------------------------------- T21 ----
# cats.conf is STAGED (consolidation review decision, 2026-09-26): the taxonomy goes live
# at the next publish.  Until then build-packages.sh deliberately left it out,
# so a catalog generated from its staging kept every stock line at the
# factory CATEGORY=system.  The checks run the REAL build-packages.sh into a
# scratch staging root (--demo: two tiny packages, host pkgmk/pkgtrans only),
# drop in stock-shaped packages beside them, and assert on the CATALOG that
# staging produces -- not on the conf file, whose own shape T15 already pins.
echo "T21: cats.conf is staged, and the staged catalog carries the taxonomy"
BP="$HERE/../build-packages.sh"
check "build-packages.sh stages cats.conf into the staging root" \
    grep -q 'cp "\$REPO/tools/repo/cats.conf" "\$STAGING/cats.conf"' "$BP"

# mkstock <dir> <PKG> <CATEGORY> <NAME>: a minimal GNU-cpio datastream with
# the factory pkginfo shape (independent producer, as in T6).
mkstock() {
    local d="$1" p="$2" c="$3" n="$4" b="$1/build.$2"
    mkdir -p "$b/$p"
    printf 'PKG=%s\nNAME=%s\nARCH=Amiga\nVERSION=2.1\nCATEGORY=%s\nCLASSES=none\n' \
        "$p" "$n" "$c" > "$b/$p/pkginfo"
    printf ': 1 1\n1 i pkginfo 90 1234 1234567890\n' > "$b/$p/pkgmap"
    { printf '# PaCkAgE DaTaStReAm\n%s 1 1\n# end of header\n' "$p"
      head -c 512 /dev/zero; } | head -c 512 > "$b/hdr"
    ( cd "$b" && printf '%s/pkginfo\n%s/pkgmap\n' "$p" "$p" \
        | cpio -o -H odc --quiet > arch1 )
    cat "$b/hdr" "$b/arch1" > "$d/$p-2.1.pkg"
    rm -rf "$b"
}

S21="$WORK/t21"
if [ -x "$HERE/../../../heirloom/build-host/bin/pkgmk" ]; then
    bash "$BP" --demo "$S21" >"$WORK/t21.build" 2>&1
    check "build-packages.sh --demo mints into a scratch staging root" \
        test $? -eq 0
    check "the staged cats.conf is the authored file, byte for byte" \
        cmp -s "$HERE/../cats.conf" "$S21/cats.conf"
    mkdir -p "$S21/stock"
    mkstock "$S21/stock" net      system "Networking commands and daemons"
    mkstock "$S21/stock" Xcore    system "X Window System essential components"
    mkstock "$S21/stock" gnusrc2  system "Other GNU source code, part 2"
    mkstock "$S21/stock" core     system "Amiga Unix essential components"
    python3 "$GEN" "$S21" >/dev/null 2>"$WORK/t21.err"
    check "the staged catalog generates cleanly" test $? -eq 0
    check "no cats.conf refusal on the staged catalog" \
        bash -c "! grep -q 'SKIP' '$WORK/t21.err'"
    check "stock net (factory CATEGORY=system) is cataloged as network" \
        test "$(field "$S21/catalog" net 8)" = network
    check "stock Xcore is cataloged as x11 (key = lowercased catalog name)" \
        test "$(field "$S21/catalog" xcore 8)" = x11
    check "stock gnusrc2 is cataloged as source" \
        test "$(field "$S21/catalog" gnusrc2 8)" = source
    check "stock core stays system (the base OS is system on purpose)" \
        test "$(field "$S21/catalog" core 8)" = system
    check "the demo fixtures keep their pkginfo CATEGORY=test" \
        test "$(field "$S21/catalog" demolib 8)" = test
    # ★ NON-VACUOUS: the same staging WITHOUT the staged file must fall back
    # to the factory category -- otherwise every check above could pass with
    # cats.conf doing nothing (e.g. a fixture that already said network).
    mv "$S21/cats.conf" "$WORK/t21.cats"
    python3 "$GEN" "$S21" >/dev/null 2>&1
    check "without the staged cats.conf, stock net falls back to system" \
        test "$(field "$S21/catalog" net 8)" = system
    mv "$WORK/t21.cats" "$S21/cats.conf"
else
    echo "  skip- staged-catalog checks (host pkgmk missing: heirloom/build-host.sh)"
fi

# --------------------------------------------------------------- T22 ----
echo "T22: scan060.py (68060-unimplemented integer instructions)"
SCAN060="$HERE/../scan060.py"
if command -v m68k-linux-gnu-objdump >/dev/null 2>&1 &&
   command -v m68k-linux-gnu-as >/dev/null 2>&1; then
    check "self-test fires on the installf trap encoding and not on the 32-bit forms" \
        python3 "$SCAN060" --self-test
    S22="$WORK/t22"; mkdir -p "$S22"
    # the exact faulting instruction from installf HASH(), 2026-10-05
    printf '\t.text\nf:\t.short 0x4c6e,0x1c02,0x0010\n\trts\n' > "$S22/hit.s"
    printf '\t.text\nf:\tdivsll %%fp@(16),%%d2:%%d1\n\tmulsl #10,%%d0\n\trts\n' > "$S22/ok.s"
    # a gcc switch table whose entries decode as movep when read as code
    printf '\t.text\nf:\tjmp %%pc@(2,%%d0:w)\n\t.short 6,0x010a,0x0108\n\tnop\n\trts\n' > "$S22/tab.s"
    for s in hit ok tab; do m68k-linux-gnu-as -m68020 -o "$S22/$s.o" "$S22/$s.s"; done
    python3 "$SCAN060" "$S22/hit.o" >"$WORK/t22.hit" 2>&1
    check "64-bit DIVS.L (4c6e 1c02) is a hit, rc 2" test $? -eq 2
    check "  ... and is named as a 64-bit dividend" grep -q '64-bit dividend' "$WORK/t22.hit"
    python3 "$SCAN060" "$S22/ok.o" >/dev/null 2>&1
    check "32-bit remainder divide and 32-bit multiply are clean, rc 0" test $? -eq 0
    python3 "$SCAN060" "$S22/tab.o" >"$WORK/t22.tab" 2>&1
    check "a switch table that decodes as movep is skipped, rc 0" test $? -eq 0
    check "  ... and the skip is reported" grep -q '1 switch tables skipped' "$WORK/t22.tab"
    mkdir -p "$S22/tree/sub"; cp "$S22/hit.o" "$S22/tree/sub/"
    python3 "$SCAN060" "$S22/tree" >/dev/null 2>&1
    check "a directory walk finds the hit too, rc 2" test $? -eq 2
    : > "$S22/empty"
    python3 "$SCAN060" "$S22/empty" >/dev/null 2>&1
    check "inspecting nothing is not a pass, rc 2" test $? -eq 2
else
    echo "  skip- scan060 checks (no m68k-linux-gnu-objdump/as on PATH)"
fi

# --------------------------------------------------------------- T23 ----
# /etc/apkg.conf survives an install or upgrade of APKG (2026-10-06), and a
# plain pkgchk agrees with what the class action script left (APKGENG 1.12.3:
# pkginstall records the on-disk size/cksum/mtime for an e/v object a class
# action script installed).  The REAL build-packages.sh --apkg mints into a
# scratch root; the host heirloom pkgadd/pkgchk install it with -R under
# fakeroot.  The host pkgchk's stat() is not faked, so each root's
# /etc/passwd and /etc/group name root and sys as the invoking user: pkgadd
# then owns the objects as that user and a PLAIN pkgchk (attributes and
# contents) can run unprivileged.  One fakeroot state per root: a state
# shared across roots can hold a stale entry for a reused inode and report a
# regular file as a directory.  The host engine keeps its DB under
# <root>/<repo>/heirloom/build-host/var/sadm (VSADMDIR is relocated under
# -R), which is why the DB is found, not named.
echo "T23: /etc/apkg.conf is kept by install and upgrade (class apkgconf)"
HB="$HERE/../../../heirloom/build-host/bin"
A22="$HERE/../../../build/repo-staging-apkg022/base/APKG-0.2.2.pkg"
if [ -x "$HB/pkgmk" ] && command -v fakeroot >/dev/null 2>&1 &&
   [ -f "$HERE/../../../src/apkg/apkg.amix" ] &&
   [ -f "$HERE/../../../src/contents-fsck/contents-fsck.amix" ]; then
    S23="$WORK/t23"; mkdir -p "$S23"
    bash "$BP" --apkg "$S23/stg" >"$WORK/t23.build" 2>&1
    check "build-packages.sh --apkg mints into a scratch staging root" test $? -eq 0
    P23="$(ls "$S23"/stg/base/APKG-*.pkg 2>/dev/null | head -1)"
    printf 'mail=\ninstance=overwrite\npartial=nocheck\nrunlevel=nocheck\nidepend=nocheck\nrdepend=nocheck\nspace=nocheck\nsetuid=nocheck\nconflict=nocheck\naction=nocheck\nbasedir=default\n' \
        > "$S23/admin"
    fr() { local fs="$S23/fakeroot.$CUR"; touch "$fs"; fakeroot -i "$fs" -s "$fs" "$@"; }
    newroot() { CUR="$(basename "$1")"; rm -rf "$1"
        mkdir -p "$1/usr/bin" "$1/etc" "$1/var/sadm/install"
        printf 'root:x:%s:%s::/:/bin/sh\n' "$(id -u)" "$(id -g)" > "$1/etc/passwd"
        printf 'root::%s:\nsys::%s:\n' "$(id -g)" "$(id -g)" > "$1/etc/group"; }
    add() { fr "$HB/pkgadd" -R "$1" -n -a "$S23/admin" -d "$2" APKG >>"$WORK/t23.add" 2>&1; }
    # plain pkgchk: attributes, and contents of every f/e/v object
    chk() { fr "$HB/pkgchk" -R "$1" APKG >"$WORK/t23.chk" 2>&1; }
    # the SVR4 post-install check: -n skips editable (e) and volatile files
    chkn() { fr "$HB/pkgchk" -R "$1" -n APKG >"$WORK/t23.chkn" 2>&1; }
    # a plain pkgchk flags the conf and NOTHING else
    onlyconf() { chk "$1"; test $? -ne 0 &&
        test "$(grep -c '^ERROR' "$WORK/t23.chk")" = 1 &&
        grep -q "^ERROR: $1/etc/apkg.conf\$" "$WORK/t23.chk"; }
    mode644() { test "$(stat -c %a "$1")" = 644; }
    cdb() { find "$1" -path '*/var/sadm/install/contents' -newer "$S23/admin" | head -1; }
    # the DB record carries the bytes on disk: size and sum(1) checksum
    ondisk() { grep -q "^/etc/apkg.conf e apkgconf 0644 root sys $(stat -c %s "$1/etc/apkg.conf") $(sum -s "$1/etc/apkg.conf" | cut -d' ' -f1) " "$(cdb "$1")"; }
    EDIT='repo=http://example.invalid/edited-by-hand'

    check "the minted pkgmap delivers /etc/apkg.conf as e apkgconf" \
        grep -aq '^1 e apkgconf /etc/apkg.conf 0644 root sys' "$P23"
    check "  ... with the class action script in install/" \
        grep -aq '^1 i i.apkgconf ' "$P23"
    check "  ... and pkginfo CLASSES names the class" \
        grep -aq '^CLASSES=none apkgconf$' "$P23"

    # 1. fresh install: the default lands, and equals the reference copy
    R1="$S23/r1"; newroot "$R1"
    add "$R1" "$P23"
    check "fresh install: pkgadd rc 0" test $? -eq 0
    check "fresh install: /etc/apkg.conf is the shipped default" \
        cmp -s "$R1/etc/apkg.conf" "$R1/usr/apkg/lib/apkg.conf"
    check "fresh install: the default is 0.2.2's bytes (md5 8dada8d9...)" \
        test "$(md5sum < "$R1/usr/apkg/lib/apkg.conf" | cut -c1-32)" = 8dada8d9fd5da9cced27ac3bf18e85a9
    chk "$R1"; check "fresh install: plain pkgchk APKG clean" test $? -eq 0
    check "fresh install: conf is mode 0644" mode644 "$R1/etc/apkg.conf"

    # 2. edit, then re-add over the installed instance: the edit stays and
    #    the DB follows it
    printf '%s\n' "$EDIT" > "$R1/etc/apkg.conf"
    chkn "$R1"; check "an edit after install: pkgchk -n APKG clean" test $? -eq 0
    check "  ... a plain pkgchk flags the edited conf and nothing else" onlyconf "$R1"
    add "$R1" "$P23"
    check "re-add over an edited conf: pkgadd rc 0" test $? -eq 0
    check "re-add over an edited conf: the edit is kept" \
        test "$(cat "$R1/etc/apkg.conf")" = "$EDIT"
    chk "$R1"; check "re-add over an edited conf: plain pkgchk APKG clean" test $? -eq 0
    chkn "$R1"; check "re-add over an edited conf: pkgchk -n APKG clean" test $? -eq 0
    check "re-add over an edited conf: conf is mode 0644" mode644 "$R1/etc/apkg.conf"
    check "  ... the contents DB records the kept file's size and cksum" ondisk "$R1"

    # 3. a conf written BEFORE the first install (installer shape) is kept
    R2="$S23/r2"; newroot "$R2"
    fr sh -c "umask 022; printf '# installer\nrepo=http://pkg.amigaux.org\ncachedir=/var/apkg/cache\nadmin=/var/apkg/admin\n' > '$R2/etc/apkg.conf'"
    cp "$R2/etc/apkg.conf" "$S23/pre.conf"
    add "$R2" "$P23"
    check "pre-written conf: pkgadd rc 0" test $? -eq 0
    check "pre-written conf: kept byte for byte" cmp -s "$R2/etc/apkg.conf" "$S23/pre.conf"
    chk "$R2"; check "pre-written conf: plain pkgchk APKG clean" test $? -eq 0
    chkn "$R2"; check "pre-written conf: pkgchk -n APKG clean" test $? -eq 0
    check "  ... the contents DB records the kept file's size and cksum" ondisk "$R2"
    # non-vacuous: a corrupted plain `f` object is still reported
    printf 'X' >> "$R2/usr/apkg/man/man1/apkg.1"
    chk "$R2"; check "a corrupted f object: plain pkgchk fails" test $? -ne 0
    check "  ... and names that file and nothing else" \
        bash -c "test \"\$(grep -c '^ERROR' '$WORK/t23.chk')\" = 1 && grep -q '^ERROR: $R2/usr/apkg/man/man1/apkg.1\$' '$WORK/t23.chk'"

    # 4. the published 0.2.2 (`e none`) -> this mint, when the artefact is here
    if [ -f "$A22" ]; then
        # an UNEDITED 0.2.2 conf upgrades with a clean plain pkgchk: the
        # default's bytes did not move (only its class did)
        R4="$S23/r4"; newroot "$R4"
        add "$R4" "$A22"; add "$R4" "$P23"
        check "unedited 0.2.2 -> this mint: the conf is the new default" \
            cmp -s "$R4/etc/apkg.conf" "$R4/usr/apkg/lib/apkg.conf"
        chk "$R4"; check "unedited 0.2.2 -> this mint: plain pkgchk APKG clean" test $? -eq 0
        R3="$S23/r3"; newroot "$R3"
        add "$R3" "$A22"
        printf '%s\n' "$EDIT" > "$R3/etc/apkg.conf"
        # non-vacuous: 0.2.2 over itself LOSES the edit -- the defect
        add "$R3" "$A22"
        check "0.2.2 over an edited conf resets it (the defect this fixes)" \
            bash -c "! grep -q 'edited-by-hand' '$R3/etc/apkg.conf'"
        printf '%s\n' "$EDIT" > "$R3/etc/apkg.conf"
        add "$R3" "$P23"
        check "0.2.2 -> this mint: pkgadd rc 0" test $? -eq 0
        check "0.2.2 -> this mint: the edit is kept" \
            test "$(cat "$R3/etc/apkg.conf")" = "$EDIT"
        chk "$R3"; check "0.2.2 -> this mint: plain pkgchk APKG clean" test $? -eq 0
        chkn "$R3"; check "0.2.2 -> this mint: pkgchk -n APKG clean" test $? -eq 0
        check "0.2.2 -> this mint: conf is mode 0644" mode644 "$R3/etc/apkg.conf"
        check "  ... the contents DB records the kept file's size and cksum" ondisk "$R3"
    else
        echo "  skip- 0.2.2 upgrade checks (build/repo-staging-apkg022 not here)"
    fi
else
    echo "  skip- apkg.conf class checks (host pkgmk, fakeroot or the .amix binaries missing)"
fi

# --------------------------------------------------------------- T24 ----
# installf refuses a pathname with white space (APKGENG 1.12.3): contents(4)
# has no quoting, so such a record is unreadable to every stock tool (the
# factory ".../MacFS/TrueType Fonts" line).  Before 1.12.3 installf wrote it
# and its own `installf -f` then failed on the DB.  Reuses T23's root r1.
echo "T24: installf refuses a pathname with white space"
if [ -n "${R1:-}" ] && [ -d "$R1/usr/apkg" ]; then
    mkdir -p "$R1/opt"; echo hi > "$R1/opt/a b"; echo hi > "$R1/opt/ab"
    CUR=r1
    fr "$HB/installf" -R "$R1" APKG "/opt/a b" f 0644 root sys >"$WORK/t24.out" 2>&1
    check "installf of a spaced pathname fails" test $? -ne 0
    check "  ... with the white-space message" grep -q 'contains white space' "$WORK/t24.out"
    fr "$HB/installf" -R "$R1" APKG /opt/ab f 0644 root sys >>"$WORK/t24.out" 2>&1
    check "installf of a plain pathname still works" test $? -eq 0
    fr "$HB/installf" -R "$R1" -f APKG >>"$WORK/t24.out" 2>&1
    check "  ... and installf -f completes" test $? -eq 0
    check "the DB carries no record with a space in its pathname" \
        bash -c "! grep -q '^/opt/a b ' '$(cdb "$R1")'"
    chk "$R1"; check "plain pkgchk APKG clean after installf" test $? -eq 0
else
    echo "  skip- installf white-space checks (T23 did not run)"
fi

# T25: the kernel-space block (amix-dlm C2-2 v2, C2-3).  A kernel package
# never becomes an ordinary entry; its #kpkg line takes line=, kabi= and pin=
# from the package's OWN sidecar /stand/<line>/kabi, byte for byte, because
# kbootset gate 2 compares apkg's record (the catalog's values) with that
# sidecar.  The sidecar below has the shape of amix-dlm tests/host/kbuild.sh.
echo "T25: kernel-space block from the package's own sidecar"
MKDS="$HERE/../../../src/apkg/tests/mkds.py"
S25="$WORK/t25"; mkdir -p "$S25/src/stand/k46" "$S25/stg/kernel"
head -c 70000 /dev/urandom > "$S25/src/stand/k46/unix"
sidecar25() {   # sidecar25 <out> [line] [sha256] [pin-line]
    cat > "$1" <<EOF
kabi=static
family=KD060-A
line=${2:-k46}
${4-pin=gcc-2.7.2.3-8949028}
build=68060-260928-52
size=$(wc -c < "$S25/src/stand/k46/unix" | tr -d ' ')
sha256=${3:-$(sha256sum "$S25/src/stand/k46/unix" | cut -c1-64)}
loader-min=1
root=zorro:0202:54,zorro:144b:01
rootfs=ufs
EOF
}
sidecar25 "$S25/src/stand/k46/kabi"
HB="$HERE/../../../heirloom/build-host/bin"
K25="$S25/stg/kernel/KERNKD60-1.1.0.pkg"
if [ -x "$HB/pkgmk" ] && [ -x "$HB/pkgtrans" ]; then
    # a real datastream, minted by the host heirloom engine
    mkdir -p "$S25/spool"
    printf 'PKG=KERNKD60\nNAME=KD060-A kernel\nVERSION=1.1.0\nARCH=m68k\nCATEGORY=system\nCLASSES=none\nBASEDIR=/\n' > "$S25/pkginfo"
    printf 'i pkginfo=%s\nd none /stand/k46 0755 root sys\nf none /stand/k46/unix=%s 0644 root sys\nf none /stand/k46/kabi=%s 0644 root sys\n' \
        "$S25/pkginfo" "$S25/src/stand/k46/unix" "$S25/src/stand/k46/kabi" > "$S25/prototype"
    ( cd "$S25" && "$HB/pkgmk" -o -d "$S25/spool" -f prototype && \
      "$HB/pkgtrans" -s "$S25/spool" "$K25" KERNKD60 ) >"$WORK/t25.mk" 2>&1
    check "a real kernel datastream minted by the host pkgmk/pkgtrans" test -s "$K25"
else
    printf 'DIR /stand\nDIR /stand/k46\nCOPY /stand/k46/unix %s\nCOPY /stand/k46/kabi %s\n' \
        "$S25/src/stand/k46/unix" "$S25/src/stand/k46/kabi" | python3 "$MKDS" "$K25" KERNKD60 1.1.0
    echo "  skip- host pkgmk absent: the kernel datastream comes from mkds.py"
fi
# the loader package (C2-3 v2 section 3): boot1, boot2, and ldrinfo with one
# key=value per line; its entry takes line=any and loader= from ldrinfo
mkdir -p "$S25/src/stand/loader"
head -c 1024 /dev/urandom > "$S25/src/stand/loader/boot1"
head -c 30000 /dev/urandom > "$S25/src/stand/loader/boot2"
ldrinfo25() {   # ldrinfo25 <out> [line] [boot2-sha256] [version-line]
    cat > "$1" <<EOF
${4-version=3}
line=${2:-any}
boot1-sha256=$(sha256sum "$S25/src/stand/loader/boot1" | cut -c1-64)
boot2-size=$(wc -c < "$S25/src/stand/loader/boot2" | tr -d ' ')
boot2-sha256=${3:-$(sha256sum "$S25/src/stand/loader/boot2" | cut -c1-64)}
EOF
}
ldrinfo25 "$S25/src/stand/loader/ldrinfo"
L25="$S25/stg/kernel/LOADER-3.pkg"
if [ -x "$HB/pkgmk" ] && [ -x "$HB/pkgtrans" ]; then
    mkdir -p "$S25/lspool"
    printf 'PKG=LOADER\nNAME=amix-dlm boot loader\nVERSION=3\nARCH=m68k\nCATEGORY=system\nCLASSES=none\nBASEDIR=/\n' > "$S25/lpkginfo"
    printf 'i pkginfo=%s\nd none /stand/loader 0755 root sys\nf none /stand/loader/boot1=%s 0644 root sys\nf none /stand/loader/boot2=%s 0644 root sys\nf none /stand/loader/ldrinfo=%s 0644 root sys\n' \
        "$S25/lpkginfo" "$S25/src/stand/loader/boot1" "$S25/src/stand/loader/boot2" "$S25/src/stand/loader/ldrinfo" > "$S25/lprototype"
    ( cd "$S25" && "$HB/pkgmk" -o -d "$S25/lspool" -f lprototype && \
      "$HB/pkgtrans" -s "$S25/lspool" "$L25" LOADER ) >"$WORK/t25.lmk" 2>&1
    check "a real loader datastream (boot1, boot2, ldrinfo) minted by pkgmk/pkgtrans" test -s "$L25"
else
    printf 'DIR /stand\nDIR /stand/loader\nCOPY /stand/loader/boot1 %s\nCOPY /stand/loader/boot2 %s\nCOPY /stand/loader/ldrinfo %s\n' \
        "$S25/src/stand/loader/boot1" "$S25/src/stand/loader/boot2" "$S25/src/stand/loader/ldrinfo" \
        | python3 "$MKDS" "$L25" LOADER 3
fi
# the kbootset package is userland (C2-3 v2 section 4): an ordinary entry
printf 'DIR /sbin\nFILE /sbin/kbootset static-binary\n' | python3 "$MKDS" "$S25/stg/KBOOTSET-1.0.pkg" KBOOTSET 1.0
cp "$FIX/TESTpkg.pkg" "$S25/stg/"
printf 'KERNKD60: kernel-kd060a\nLOADER: loader\n' > "$S25/stg/names.conf"
mkdir -p "$S25/plain"; cp "$FIX/TESTpkg.pkg" "$S25/stg/KBOOTSET-1.0.pkg" "$S25/stg/names.conf" "$S25/plain/"
python3 "$GEN" "$S25/plain" >/dev/null 2>&1
python3 "$GEN" "$S25/stg" >"$WORK/t25.out" 2>"$WORK/t25.err"
check "gen-catalog takes a staging root with a kernel package (rc 0)" test $? -eq 0
KL="#kpkg kernel-kd060a 1.1.0 role=kernel line=k46 kabi=static pin=gcc-2.7.2.3-8949028 size=$(wc -c < "$K25" | tr -d ' ') sha256=$(sha256sum "$K25" | cut -c1-64) file=kernel/KERNKD60-1.1.0.pkg pkginst=KERNKD60"
LL="#kpkg loader 3 role=loader line=any loader=3 size=$(wc -c < "$L25" | tr -d ' ') sha256=$(sha256sum "$L25" | cut -c1-64) file=kernel/LOADER-3.pkg pkginst=LOADER"
check "the block is exactly: #ext kpkg 1, the kernel's and the loader's #kpkg lines, #end kpkg" \
    test "$(sed -n '/^#ext kpkg 1$/,/^#end kpkg$/p' "$S25/stg/catalog")" = "#ext kpkg 1
$KL
$LL
#end kpkg"
check "the loader's line has line=any and loader= from ldrinfo, no kabi= or pin= (C2-2 v3)" \
    bash -c "grep '^#kpkg loader ' '$S25/stg/catalog' | grep -q ' line=any loader=3 ' && ! grep '^#kpkg loader ' '$S25/stg/catalog' | grep -q 'kabi=\\|pin='"
check "the kbootset package is an ordinary entry, not kernel space (C2-3 v2 section 4)" \
    bash -c "grep -q '^kbootset|1.0|KBOOTSET|KBOOTSET-1.0.pkg|' '$S25/stg/catalog' && ! grep -q '^#kpkg kbootset' '$S25/stg/catalog'"
SKABI=$(sed -n 's/^kabi=//p' "$S25/src/stand/k46/kabi")
SPIN=$(sed -n 's/^pin=//p' "$S25/src/stand/k46/kabi")
check "kabi= and pin= are the sidecar's bytes" \
    grep -q " kabi=$SKABI pin=$SPIN " "$S25/stg/catalog"
check "the kernel package is no ordinary entry (a 0.2.x client never sees it)" \
    bash -c "! grep -v '^#' '$S25/stg/catalog' | grep -q KERNKD60"
check "without the block the catalog is byte-for-byte the plain one" \
    test "$(grep -v -e '^#ext kpkg' -e '^#kpkg ' -e '^#end kpkg' "$S25/stg/catalog")" = "$(cat "$S25/plain/catalog")"
check "every block line is under 2048 bytes" \
    test "$(awk 'length($0) >= 2047' "$S25/stg/catalog" | wc -l)" = 0
mkdir -p "$S25/rawout"; python3 "$GEN" --raw -o "$S25/rawout" "$S25/stg" >/dev/null 2>&1
ROFF=$(sed -n 's/^#kpkg kernel-kd060a .* offset=\([0-9]*\)$/\1/p' "$S25/rawout/catalog")
check "--raw gives the #kpkg line an offset= and packs the bytes there" \
    bash -c "[ -n '$ROFF' ] && cmp -s '$K25' <(tail -c +\$(($ROFF + 1)) '$S25/rawout/raw.img' | head -c $(wc -c < "$K25"))"

# refusals: a SKIP naming why, never a #kpkg line
t25bad() {   # t25bad <desc> <stderr text> <directives...>  (mkds.py fixture)
    local d="$S25/bad"; rm -rf "$d"; mkdir -p "$d"
    desc=$1; want=$2; shift 2
    printf '%s\n' "$@" | python3 "$MKDS" "$d/KBAD-1.0.pkg" KBAD 1.0
    python3 "$GEN" "$d" >"$WORK/t25b.out" 2>"$WORK/t25b.err"
    check "$desc" bash -c "grep -q 'SKIP KBAD-1.0.pkg: .*$want' '$WORK/t25b.err' && ! grep -q '^#kpkg' '$d/catalog' 2>/dev/null"
}
sidecar25 "$S25/sc-line" k30
t25bad "a sidecar whose line= is not its path's is refused" "sidecar says line=k30" \
    "COPY /stand/k46/unix $S25/src/stand/k46/unix" "COPY /stand/k46/kabi $S25/sc-line"
sidecar25 "$S25/sc-sha" k46 0000000000000000000000000000000000000000000000000000000000000000
t25bad "a sidecar whose sha256= is not the packaged unix's is refused" "sidecar sha256= is not" \
    "COPY /stand/k46/unix $S25/src/stand/k46/unix" "COPY /stand/k46/kabi $S25/sc-sha"
sidecar25 "$S25/sc-nopin" k46 "" ""
t25bad "a sidecar without pin= is refused" "no usable pin=" \
    "COPY /stand/k46/unix $S25/src/stand/k46/unix" "COPY /stand/k46/kabi $S25/sc-nopin"
t25bad "a kernel package that is not pure files is refused (40 section 6)" "not pure files.*type e" \
    "COPY /stand/k46/unix $S25/src/stand/k46/unix" "COPY /stand/k46/kabi $S25/src/stand/k46/kabi" \
    "PKGMAP 1 e none /etc/kmod.conf 0644 root sys 1 1 1"
ldrinfo25 "$S25/li-line" k46
t25bad "an ldrinfo whose line= is not any is refused" "ldrinfo says line=k46" \
    "COPY /stand/loader/boot2 $S25/src/stand/loader/boot2" "COPY /stand/loader/ldrinfo $S25/li-line"
ldrinfo25 "$S25/li-sha" any 0000000000000000000000000000000000000000000000000000000000000000
t25bad "an ldrinfo whose boot2-sha256= is not the packaged boot2's is refused" "boot2-sha256= is not" \
    "COPY /stand/loader/boot2 $S25/src/stand/loader/boot2" "COPY /stand/loader/ldrinfo $S25/li-sha"
ldrinfo25 "$S25/li-nov" any "" ""
t25bad "an ldrinfo without version= is refused" "no numeric version=" \
    "COPY /stand/loader/boot2 $S25/src/stand/loader/boot2" "COPY /stand/loader/ldrinfo $S25/li-nov"

# the round trip through the client: update, info, download (sha256), and an
# install plan that runs apkg's own pure-files check on this datastream
APKG25="$HERE/../../../src/apkg/apkg"
if make -C "$HERE/../../../src/apkg" host >/dev/null 2>&1 && [ -x "$APKG25" ]; then
    mkdir -p "$S25/repo" "$S25/root"; cp "$S25/stg/catalog" "$S25/repo/"
    ln -s "$S25/stg" "$S25/repo/pkgs"
    printf 'repo=file://%s/repo\ncachedir=%s/root/var/apkg/cache\nadmin=%s/admin\npkgadd=/bin/true\nkbootset=/bin/true\n' \
        "$S25" "$S25" "$S25" > "$S25/apkg.conf"
    A25() { APKG_ROOT="$S25/root" "$APKG25" -c "$S25/apkg.conf" "$@"; }
    check "apkg update reads the generated block (2 kernel-space)" \
        bash -c "APKG_ROOT='$S25/root' '$APKG25' -c '$S25/apkg.conf' update | grep -q '2 packages, 2 kernel-space'"
    OUT25=$(A25 info loader 2>&1)
    check "apkg info loader: line any, loader 3, no kabi/pin, not refused" \
        bash -c "echo \"\$0\" | grep -qx 'Kernel-space: loader, line any' && echo \"\$0\" | grep -qx 'Loader:      3' && ! echo \"\$0\" | grep -q '^Kabi\\|^Pin\\|^Refused'" "$OUT25"
    OUT25=$(A25 -n install loader 2>&1); rc25=$?
    check "apkg -n install loader: the real loader datastream passes sha256 and pure files (rc 0)" \
        bash -c "[ $rc25 -eq 0 ] && ! echo \"\$0\" | grep -q 'not a pure-file'" "$OUT25"
    OUT25=$(A25 info kernel-kd060a 2>&1)
    check "apkg info: kabi and pin are the sidecar's" \
        bash -c "echo \"\$0\" | grep -qx 'Kabi:        $SKABI' && echo \"\$0\" | grep -qx 'Pin:         $SPIN'" "$OUT25"
    A25 download kernel-kd060a >/dev/null 2>&1
    check "apkg download verifies the datastream by sha256 (rc 0)" test $? -eq 0
    OUT25=$(A25 -n install kernel-kd060a 2>&1); rc25=$?
    check "apkg -n install: the datastream passes the pure-files check (rc 0)" \
        bash -c "[ $rc25 -eq 0 ] && ! echo \"\$0\" | grep -q 'not a pure-file'" "$OUT25"
else
    bad "T25: the host apkg did not build for the round trip"
fi

# --------------------------------------------------------------- T26 ----
# T26: module packages (stage 3; C3-5 section 1.2, C2-2 section 1.1).  The
# row is role=module with line=/kabi=/pin= from the module object's own
# .moddata (C3-1: the one section of type 13, word 0, "MD2\0", key=value
# strings; keys kabi= and cc=), catalog name and version as for any package
# (names.conf, pkginfo VERSION), and no depend= key (kbootset gate 3).
echo "T26: module packages, kabi= and pin= from the object's .moddata"
MKOBJ="$HERE/mkmodobj.py"
S26="$WORK/t26"; mkdir -p "$S26/src" "$S26/stg/base"
MPIN=gcc-2.7.2.3-8949028
python3 "$MKOBJ" "$S26/src/zeth" name=zeth kabi=k46.1.0 cc=$MPIN cpu=68030 \
    class=boot match=zorro:144b:01 majors=c:51 depend=zbus \
    param=mtu:int:1500 param=promisc:bool:0 "desc=test module"
printf '# defaults\n' > "$S26/src/zeth.reg"
M26="$S26/stg/base/zeth46-1.0.0-1.pkg"
if [ -x "$HB/pkgmk" ] && [ -x "$HB/pkgtrans" ]; then
    mkdir -p "$S26/spool"
    printf 'PKG=zeth46\nNAME=z3660eth-k46 test module\nVERSION=1.0.0-1\nARCH=Amiga\nCATEGORY=system\nCLASSES=none\nBASEDIR=/\n' > "$S26/pkginfo"
    printf 'i pkginfo=%s\nd none /etc 0755 root root\nd none /etc/conf 0755 root sys\nd none /etc/conf/mod.d 0755 root sys\nf none /etc/conf/mod.d/zeth=%s 0644 root sys\nd none /etc/conf/modreg.d 0755 root sys\nf none /etc/conf/modreg.d/zeth=%s 0644 root sys\nd none /dev 0755 bin bin\nc none /dev/zen0 51 0 0644 root root\n' \
        "$S26/pkginfo" "$S26/src/zeth" "$S26/src/zeth.reg" > "$S26/prototype"
    ( cd "$S26" && "$HB/pkgmk" -o -d "$S26/spool" -f prototype && \
      "$HB/pkgtrans" -s "$S26/spool" "$M26" zeth46 ) >"$WORK/t26.mk" 2>&1
    check "a real module datastream (C3-5 section 1.2 layout) minted by pkgmk/pkgtrans" test -s "$M26"
else
    printf 'DIR /etc\nDIR /etc/conf\nDIR /etc/conf/mod.d\nCOPY /etc/conf/mod.d/zeth %s\nDIR /etc/conf/modreg.d\nCOPY /etc/conf/modreg.d/zeth %s\nDIR /dev\nCDEV /dev/zen0 51 0\n' \
        "$S26/src/zeth" "$S26/src/zeth.reg" | python3 "$MKDS" "$M26" zeth46 1.0.0-1
    echo "  skip- host pkgmk absent: the module datastream comes from mkds.py"
fi
# C3-5 v4 section 1.2: the driver's device node rides in the pkgmap
check "the module datastream carries /dev/zen0 as a pkgmap c entry (C3-5 v4 section 1.2)" \
    grep -aq '^1 c none /dev/zen0 51 0 0644 root root$' "$M26"
cp "$FIX/TESTpkg.pkg" "$S26/stg/"
printf 'zeth46: z3660eth-k46\n' > "$S26/stg/names.conf"
printf 'z3660eth-k46: TESTpkg\n' > "$S26/stg/deps.conf"     # must not reach the row
python3 "$GEN" "$S26/stg" >"$WORK/t26.out" 2>"$WORK/t26.err"
check "gen-catalog takes a staging root with a module package (rc 0, nothing skipped)" \
    bash -c "[ $? -eq 0 ] && ! grep -q SKIP '$WORK/t26.err'"
ML="#kpkg z3660eth-k46 1.0.0-1 role=module line=k46 kabi=k46.1.0 pin=$MPIN size=$(wc -c < "$M26" | tr -d ' ') sha256=$(sha256sum "$M26" | cut -c1-64) file=base/zeth46-1.0.0-1.pkg pkginst=zeth46"
check "the block is exactly the module's C2-2 row (name from names.conf, version from pkginfo)" \
    test "$(sed -n '/^#ext kpkg 1$/,/^#end kpkg$/p' "$S26/stg/catalog")" = "#ext kpkg 1
$ML
#end kpkg"
check "no depend= key on the row, though the object and deps.conf name dependencies" \
    bash -c "! grep '^#kpkg z3660eth-k46 ' '$S26/stg/catalog' | grep -q 'depend'"
check "the module package is no ordinary entry" \
    bash -c "! grep -v '^#' '$S26/stg/catalog' | grep -q zeth46"

# refusals: a SKIP naming why, never a #kpkg line
t26bad() {   # t26bad <desc> <stderr text> <directives...>  (mkds.py fixture)
    local d="$S26/bad"; rm -rf "$d"; mkdir -p "$d"
    desc=$1; want=$2; shift 2
    printf '%s\n' "$@" | python3 "$MKDS" "$d/zbad46-1.0.pkg" zbad46 1.0
    python3 "$GEN" "$d" >"$WORK/t26b.out" 2>"$WORK/t26b.err"
    check "$desc" bash -c "grep -q 'SKIP zbad46-1.0.pkg: .*$want' '$WORK/t26b.err' && ! grep -q '^#kpkg' '$d/catalog' 2>/dev/null"
}
mo() { python3 "$MKOBJ" "$S26/src/$1" "${@:2}"; }
mo noelf.o; echo "not an object" > "$S26/src/noelf.o"
t26bad "an object that is not ELF is refused" "not an ELF32 big-endian object" \
    "COPY /etc/conf/mod.d/zbad $S26/src/noelf.o"
mo exec.o --type 2 name=zbad kabi=k46.1.0 cc=$MPIN
t26bad "an object that is not ET_REL is refused" "is not ET_REL EM_68K" \
    "COPY /etc/conf/mod.d/zbad $S26/src/exec.o"
mo nosec.o --nsec 0 name=zbad kabi=k46.1.0 cc=$MPIN
t26bad "an object without a type-13 section is refused" "has 0 sections of type 13" \
    "COPY /etc/conf/mod.d/zbad $S26/src/nosec.o"
mo twosec.o --nsec 2 name=zbad kabi=k46.1.0 cc=$MPIN
t26bad "an object with two type-13 sections is refused" "has 2 sections of type 13" \
    "COPY /etc/conf/mod.d/zbad $S26/src/twosec.o"
mo md1.o --magic MD1 name=zbad kabi=k46.1.0 cc=$MPIN
t26bad "a .moddata without MD2 is refused (a version-1 object)" "has no MD2 marker" \
    "COPY /etc/conf/mod.d/zbad $S26/src/md1.o"
mo nocc.o name=zbad kabi=k46.1.0
t26bad "a .moddata without cc= is refused" "has no usable cc=" \
    "COPY /etc/conf/mod.d/zbad $S26/src/nocc.o"
mo badkabi.o name=zbad kabi=k46.1 cc=$MPIN
t26bad "a kabi= that is not k30|k46.<major>.<minor> is refused" "kabi=k46.1 is not" \
    "COPY /etc/conf/mod.d/zbad $S26/src/badkabi.o"
mo twokabi.o name=zbad kabi=k46.1.0 kabi=k46.1.1 cc=$MPIN
t26bad "a key twice (param aside) is refused" "has kabi= twice" \
    "COPY /etc/conf/mod.d/zbad $S26/src/twokabi.o"
mo wrongname.o name=other kabi=k46.1.0 cc=$MPIN
t26bad "a name= other than the file name is refused" "name=other, the object is /etc/conf/mod.d/zbad" \
    "COPY /etc/conf/mod.d/zbad $S26/src/wrongname.o"
mo good.o name=zbad kabi=k46.1.0 cc=$MPIN
t26bad "two module objects in one package are refused" "2 objects under /etc/conf/mod.d/" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "COPY /etc/conf/mod.d/zbad2 $S26/src/good.o"
t26bad "a module package that is not pure files is refused (40 section 6)" "not pure files.*postinstall" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 i postinstall 20 1 1"
# device entries (C3-5 v4 section 1.2): a module's c none /dev/<node> passes
# (above), and (C3-5 v8 section 1.2) a block driver's b none /dev/dsk/<node>
# (the ramdisk: /dev/dsk/ram0-2 b 20 0-2, 0600 root root); a b node outside
# /dev/dsk/, a p, s or l entry, a c node outside /dev/, a c or b line short
# of its fields or in another class does not, and a kernel package takes none
t26good() {  # t26good <desc> <directives...>  (mkds.py fixture)
    local d="$S26/good"; rm -rf "$d"; mkdir -p "$d"
    desc=$1; shift
    printf '%s\n' "$@" | python3 "$MKDS" "$d/zbad46-1.0.pkg" zbad46 1.0
    python3 "$GEN" "$d" >"$WORK/t26g.out" 2>"$WORK/t26g.err"
    check "$desc" bash -c "[ $? -eq 0 ] && ! grep -q SKIP '$WORK/t26g.err' && grep -q '^#kpkg zbad46 1.0 role=module ' '$d/catalog'"
}
t26good "a module package with block nodes in /dev/dsk/ is accepted (C3-5 v8 section 1.2)" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "DIR /dev" "DIR /dev/dsk" \
    "PKGMAP 1 b none /dev/dsk/ram0 20 0 0600 root root" \
    "PKGMAP 1 b none /dev/dsk/ram1 20 1 0600 root root" \
    "PKGMAP 1 b none /dev/dsk/ram2 20 2 0600 root root"
t26good "a module package with a c node in /dev/rdsk/ and a b node in /dev/dsk/ is accepted" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "DIR /dev" \
    "PKGMAP 1 b none /dev/dsk/zb0 52 0 0600 root root" \
    "PKGMAP 1 c none /dev/rdsk/zb0 52 0 0600 root root"
t26bad "a module's block node outside /dev/dsk/ is refused" "not pure files.*a block device node outside /dev/dsk/: /dev/zbd0" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 b none /dev/zbd0 52 0 0644 root root"
t26bad "a module's block node in /dev/rdsk/ is refused" "not pure files.*a block device node outside /dev/dsk/: /dev/rdsk/ram0" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 b none /dev/rdsk/ram0 20 0 0600 root root"
t26bad "a module's b entry without a minor is refused" "not pure files.*a device entry not of the form .*: /dev/dsk/ram0" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 b none /dev/dsk/ram0 20 0600 root root"
t26bad "a module's b entry in another class is refused" "not pure files.*an object in class kcls" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 b kcls /dev/dsk/ram0 20 0 0600 root root"
t26bad "a named-pipe entry in a module package is refused" "not pure files.*an object of type p at /dev/zp" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 p none /dev/zp 0644 root root"
t26bad "a symlink entry in a module package is refused" "not pure files.*an object of type s at /dev/zs=/dev/dsk/ram0" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 s none /dev/zs=/dev/dsk/ram0"
t26bad "a hard-link entry in a module package is refused" "not pure files.*an object of type l at /dev/zl=/dev/dsk/ram0" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 l none /dev/zl=/dev/dsk/ram0"
t26bad "a module's device node outside /dev/ is refused" "not pure files.*a device node outside /dev/: /etc/zen0" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 c none /etc/zen0 51 0 0644 root root"
t26bad "a module's c entry without a minor is refused" "not pure files.*a device entry not of the form .*: /dev/zen0" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 c none /dev/zen0 51 0644 root root"
t26bad "a module's c entry in another class is refused" "not pure files.*an object in class kcls" \
    "COPY /etc/conf/mod.d/zbad $S26/src/good.o" "PKGMAP 1 c kcls /dev/zen0 51 0 0644 root root"
t26bad "the same /dev/zen0 entry in a kernel package is refused" "not pure files.*an object of type c at /dev/zen0" \
    "DIR /stand" "DIR /stand/k46" "FILE /stand/k46/unix u" "FILE /stand/k46/kabi k" \
    "DIR /dev" "CDEV /dev/zen0 51 0"
t26bad "a /dev/dsk/ram0 b entry in a kernel package is refused" "not pure files.*an object of type b at /dev/dsk/ram0" \
    "DIR /stand" "DIR /stand/k46" "FILE /stand/k46/unix u" "FILE /stand/k46/kabi k" \
    "DIR /dev" "DIR /dev/dsk" "BDEV /dev/dsk/ram0 20 0"

# the round trip through the client: update counts it, info shows the
# .moddata's kabi and pin, download verifies its sha256
if [ -x "$APKG25" ]; then
    mkdir -p "$S26/repo" "$S26/root"; cp "$S26/stg/catalog" "$S26/repo/"
    ln -s "$S26/stg" "$S26/repo/pkgs"
    printf 'repo=file://%s/repo\ncachedir=%s/root/var/apkg/cache\nadmin=%s/admin\npkgadd=/bin/true\nkbootset=/bin/true\n' \
        "$S26" "$S26" "$S26" > "$S26/apkg.conf"
    A26() { APKG_ROOT="$S26/root" "$APKG25" -c "$S26/apkg.conf" "$@"; }
    check "apkg update reads the module row (1 kernel-space)" \
        bash -c "APKG_ROOT='$S26/root' '$APKG25' -c '$S26/apkg.conf' update | grep -q '1 package, 1 kernel-space'"
    OUT26=$(A26 info z3660eth-k46 2>&1)
    check "apkg info z3660eth-k46: a module, kabi and pin from .moddata, not refused" \
        bash -c "echo \"\$0\" | grep -qx 'Kernel-space: module, line k46' && echo \"\$0\" | grep -qx 'Kabi:        k46.1.0' && echo \"\$0\" | grep -qx 'Pin:         $MPIN' && ! echo \"\$0\" | grep -q '^Refused'" "$OUT26"
    A26 download z3660eth-k46 >/dev/null 2>&1
    check "apkg download verifies the module datastream by sha256 (rc 0)" test $? -eq 0
else
    bad "T26: no host apkg for the round trip"
fi

# against amix-packages' stage-3 mint, when that sibling tree is there (read
# only, copied): every #kpkg row, the four module rows among them, must be
# the one its round trip wrote (build/kspace/repo/catalog)
REF26="$HERE/../../../../amix-packages/build/kspace"
if [ -f "$REF26/repo/catalog" ] && [ -d "$REF26/rt/repo/pkgs" ]; then
    cp -r "$REF26/rt/repo/pkgs" "$S26/ref"; mkdir -p "$S26/refout"
    python3 "$GEN" -o "$S26/refout" "$S26/ref" >/dev/null 2>&1
    check "amix-packages' stage-3 mint: the generated #kpkg rows equal its catalog's ($(grep -c '^#kpkg .* role=module ' "$REF26/repo/catalog") module rows)" \
        test "$(grep '^#kpkg ' "$S26/refout/catalog" 2>/dev/null)" = "$(grep '^#kpkg ' "$REF26/repo/catalog")"
else
    echo "  skip- amix-packages build/kspace absent: no comparison with its mint"
fi

# --------------------------------------------------------------- T27 ----
# m4: the stock /usr/ccs/bin/m4 alone, carved out of the factory Cdev package
# (build-packages.sh --m4), so syslogd works without the C development set.
# Both packages deliver /usr/ccs/bin/m4.  The claim is that an IDENTICAL
# pkgmap row is a shared file, not a conflict: either install order is clean
# even with conflict=quit, plain pkgchk passes for both, and removing one
# leaves the file to the other.  A variant with a different mode must be
# refused under the same admin, or the "clean" result proves nothing.
echo "T27: m4 package shares /usr/ccs/bin/m4 with Cdev"
TAPE27="$HERE/../../../hdf/tape21"
CDEV27="$HERE/../../../build/repo-staging/stock/Cdev-2.1.pkg"
if [ -x "$HB/pkgmk" ] && command -v fakeroot >/dev/null 2>&1 &&
   [ -f "$TAPE27/x00/List" ] && [ -f "$TAPE27/04" ] && [ -f "$CDEV27" ]; then
    S27="$WORK/t27"; mkdir -p "$S27"
    ROW27='1 f none /usr/ccs/bin/m4 0755 bin bin 23004 51597 690829200'
    python3 "$HERE/../repackage-stock.py" --member Cdev:usr/ccs/bin/nosuch \
        --out "$S27/nosuch" >/dev/null 2>&1
    check "--member: a member the tape lacks fails, and leaves no file" \
        bash -c "test $? -ne 0 && test ! -e '$S27/nosuch'"
    bash "$BP" --m4 "$S27/stg" >"$WORK/t27.build" 2>&1
    check "build-packages.sh --m4 mints into a scratch staging root" test $? -eq 0
    P27="$S27/stg/stock/m4-2.1.pkg"
    check "  ... as stock/m4-2.1.pkg, beside the stock set" test -f "$P27"
    check "  ... and stages deps.conf with it" test -f "$S27/stg/deps.conf"
    check "the m4 pkgmap row is the factory one" grep -aqx "$ROW27" "$P27"
    check "  ... field for field the row Cdev carries" grep -aqx "$ROW27" "$CDEV27"
    mkdir -p "$S27/x"; "$HB/pkgtrans" "$P27" "$S27/x" m4 >/dev/null 2>&1
    X27="$S27/x/m4"
    check "pkginfo: PKG=m4 VERSION=2.1 CATEGORY=system" \
        bash -c "grep -qx 'PKG=m4' '$X27/pkginfo' && grep -qx 'VERSION=2.1' '$X27/pkginfo' && grep -qx 'CATEGORY=system' '$X27/pkginfo'"
    check "pkginfo: provenance in APKG_DESC" \
        grep -q '^APKG_DESC=.*(Amix 2.1 stock, Cdev tape member)$' "$X27/pkginfo"
    check "exactly four objects: /usr, /usr/ccs, /usr/ccs/bin and m4" \
        test "$(grep -v -e '^:' -e '^1 i ' "$X27/pkgmap" | tr '\n' ';')" = \
             "1 d none /usr 0755 bin bin;1 d none /usr/ccs 0755 bin bin;1 d none /usr/ccs/bin 0755 bin bin;$ROW27;"
    check "the payload is the tape's bytes (md5 93945b5c...)" \
        test "$(md5sum < "$S27/x/m4/root/usr/ccs/bin/m4" | cut -c1-32)" = 93945b5c306cf5286204a003b330df50

    printf 'mail=\ninstance=quit\npartial=nocheck\nrunlevel=nocheck\nidepend=nocheck\nrdepend=nocheck\nspace=nocheck\nsetuid=nocheck\nconflict=quit\naction=nocheck\nbasedir=default\n' \
        > "$S27/strict"
    fr27() { local fs="$S27/fakeroot.$CUR"; touch "$fs"; fakeroot -i "$fs" -s "$fs" "$@"; }
    newroot27() { CUR="$(basename "$1")"; rm -rf "$1"
        mkdir -p "$1/etc" "$1/var/sadm/install"
        printf 'root:x:%s:%s::/:/bin/sh\nbin:x:%s:%s::/:\namiga:x:%s:%s::/:\n' \
            "$(id -u)" "$(id -g)" "$(id -u)" "$(id -g)" "$(id -u)" "$(id -g)" > "$1/etc/passwd"
        printf 'root::%s:\nsys::%s:\nbin::%s:\namiga::%s:\n' \
            "$(id -g)" "$(id -g)" "$(id -g)" "$(id -g)" > "$1/etc/group"; }
    add27() { fr27 "$HB/pkgadd" -R "$1" -n -a "$S27/strict" -d "$2" "$3" >"$WORK/t27.add" 2>&1; }
    rm27()  { fr27 "$HB/pkgrm" -R "$1" -n -a "$S27/strict" "$2" >"$WORK/t27.rm" 2>&1; }
    chk27() { fr27 "$HB/pkgchk" -R "$1" "$2" >"$WORK/t27.chk" 2>&1; }
    cdb27() { find "$1" -path '*/var/sadm/install/contents' | head -1; }
    rowis() { grep -qx "/usr/ccs/bin/m4 f none 0755 bin bin 23004 51597 690829200 $2" "$(cdb27 "$1")"; }
    ondisk27() { test "$(md5sum < "$1/usr/ccs/bin/m4" | cut -c1-32)" = 93945b5c306cf5286204a003b330df50; }

    # order A: m4, then Cdev
    A27="$S27/a"; newroot27 "$A27"
    add27 "$A27" "$P27" m4;      check "A: m4 into an empty root, conflict=quit: rc 0" test $? -eq 0
    add27 "$A27" "$CDEV27" Cdev; check "A: then Cdev, conflict=quit: rc 0" test $? -eq 0
    check "A: no conflict was listed" bash -c "! grep -q 'already installed on the system' '$WORK/t27.add'"
    check "A: one contents row, both packages on it" rowis "$A27" "m4 Cdev"
    chk27 "$A27" m4;   check "A: plain pkgchk m4 clean" test $? -eq 0
    chk27 "$A27" Cdev; check "A: plain pkgchk Cdev clean" test $? -eq 0
    rm27 "$A27" Cdev;  check "A: pkgrm Cdev rc 0" test $? -eq 0
    check "A: the file stays, the tape's bytes" ondisk27 "$A27"
    check "A: the row now names m4 alone" rowis "$A27" "m4"
    chk27 "$A27" m4;   check "A: plain pkgchk m4 still clean" test $? -eq 0
    rm27 "$A27" m4
    check "A: pkgrm of the last owner removes the file" test ! -e "$A27/usr/ccs/bin/m4"

    # order B: Cdev, then m4
    B27="$S27/b"; newroot27 "$B27"
    add27 "$B27" "$CDEV27" Cdev; check "B: Cdev into an empty root: rc 0" test $? -eq 0
    add27 "$B27" "$P27" m4;      check "B: then m4, conflict=quit: rc 0" test $? -eq 0
    check "B: no conflict was listed" bash -c "! grep -q 'already installed on the system' '$WORK/t27.add'"
    check "B: one contents row, both packages on it" rowis "$B27" "Cdev m4"
    chk27 "$B27" Cdev; check "B: plain pkgchk Cdev clean" test $? -eq 0
    chk27 "$B27" m4;   check "B: plain pkgchk m4 clean" test $? -eq 0
    rm27 "$B27" m4;    check "B: pkgrm m4 rc 0" test $? -eq 0
    check "B: the file stays, the tape's bytes" ondisk27 "$B27"
    check "B: the row now names Cdev alone" rowis "$B27" "Cdev"
    chk27 "$B27" Cdev; check "B: plain pkgchk Cdev still clean" test $? -eq 0

    # negative control: the same file at mode 0775 IS a conflict
    N27="$S27/neg"; mkdir -p "$N27/spool"
    cp "$S27/x/m4/root/usr/ccs/bin/m4" "$N27/m4"
    printf 'PKG=m4\nNAME=m4 variant\nARCH=Amiga\nVERSION=2.1\nCATEGORY=system\nCLASSES=none\n' > "$N27/pkginfo"
    printf 'i pkginfo\nd none /usr/ccs 0755 bin bin\nd none /usr/ccs/bin 0755 bin bin\nf none /usr/ccs/bin/m4=%s 0775 bin bin\n' \
        "$N27/m4" > "$N27/prototype"
    ( cd "$N27" && "$HB/pkgmk" -o -d "$N27/spool" -f prototype ) >/dev/null 2>&1
    "$HB/pkgtrans" -s "$N27/spool" "$N27/m4-var.pkg" m4 >/dev/null 2>&1
    C27="$S27/c"; newroot27 "$C27"
    add27 "$C27" "$CDEV27" Cdev
    add27 "$C27" "$N27/m4-var.pkg" m4
    check "control: a different mode under conflict=quit is refused (rc 4)" test $? -eq 4
    check "control: ... and listed as a conflict" \
        grep -q 'already installed on the system' "$WORK/t27.add"

    # the catalog row: deps core (deps.conf), category system (pkginfo)
    python3 "$GEN" "$S27/stg" >/dev/null 2>&1
    check "catalog: m4|2.1|m4|stock/m4-2.1.pkg, deps core, category system" \
        test "$(cut -d'|' -f1-4,7,8 "$S27/stg/catalog" | grep '^m4|')" = "m4|2.1|m4|stock/m4-2.1.pkg|core|system"
else
    echo "  skip- m4 checks (host engine, fakeroot, hdf/tape21 or the staged Cdev-2.1.pkg missing)"
fi

# -------------------------------------------------------------- done ----
echo
echo "repo tools: $PASS passed, $FAIL failed"
test "$FAIL" -eq 0
