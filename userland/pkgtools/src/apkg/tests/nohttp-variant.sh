#!/bin/sh
# nohttp-variant.sh - host-side test for the FILE+RAW-only (-DAPKG_NO_HTTP)
# apkg variant that the static/install build ships.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# This is a SEPARATE vehicle from run-tests.sh on purpose: run-tests.sh
# exercises the DEFAULT (HTTP-capable) apkg and must stay at its own
# count.  Here we build a second host binary with the HTTP backend
# COMPILED OUT (http.c and dns.c dropped, -DAPKG_NO_HTTP) - exactly the
# source set and define that heirloom/build-amix-static.sh gives the m68k
# static apkg - and prove three things host-side:
#
#   1. an http:// repo FAILS CLOSED with a clear message (never
#      misclassified, never falls through to another backend);
#   2. FILE (file:// and bare /path) behaviour is byte-for-byte the
#      shared build's - same pkgadd argv, same staged bytes;
#   3. RAW (raw:<device>) behaviour is byte-for-byte the shared build's.
#
# 2 and 3 run the IDENTICAL scenario through both the shared apkg and the
# nohttp apkg and compare, so "byte-for-byte the shared build" is a
# measured fact, not an assertion.
#
# Usage: sh tests/nohttp-variant.sh   (does NOT need any network server)

set -u

SRC=$(cd "$(dirname "$0")/.." && pwd)
TESTS=$SRC/tests
WORK=$TESTS/work/nohttp          # under the gitignored tests/work/

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; [ -n "${2:-}" ] && { \
        echo "----- output -----"; echo "$2"; echo "------------------"; }; }

# run <expected-rc> <desc> <cmd...>; combined output in $OUT
run() {
    want=$1; desc=$2; shift 2
    OUT=$("$@" 2>&1); rc=$?
    if [ "$rc" -eq "$want" ]; then ok "$desc"
    else bad "$desc (rc=$rc, wanted $want)" "$OUT"; fi
}

command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
command -v md5sum  >/dev/null || { echo "md5sum required"; exit 1; }

# ---------------------------------------------------------------- build
echo "== building shared apkg (HTTP-capable, reference) =="
make -C "$SRC" host >/dev/null || { echo "shared host build failed"; exit 1; }
APKG=$SRC/apkg

echo "== building nohttp apkg (-DAPKG_NO_HTTP, http.c excluded) =="
rm -rf "$WORK"; mkdir -p "$WORK/bin" "$WORK/repo/pkgs" \
    "$WORK/root/etc" "$WORK/root/var/apkg" "$WORK/root/var/sadm/pkg"
APKGNH=$WORK/apkg-nohttp
# The source set is SRCS-minus-http.c: exactly what build-amix-static.sh
# compiles.  gnu89/-O2 without -Wall (the shared build already carries the
# -Wall coverage; the #ifdef'd-out HTTP arms leave a few unused locals).
( cd "$SRC" && gcc -std=gnu89 -O2 -DAPKG_NO_HTTP -o "$APKGNH" \
    main.c util.c conf.c vercmp.c catalog.c md5.c install.c source.c \
    kspace.c txn.c sha256.c fsreq.c conffile.c ) \
    || { echo "nohttp build failed"; exit 1; }
ok "nohttp apkg builds with http.c excluded (-DAPKG_NO_HTTP)"

# proof the object set carries no HTTP client symbol at all
if nm "$APKGNH" | grep -qw http_get; then
    bad "nohttp binary still references http_get"
else
    ok "nohttp binary has no http_get symbol (backend truly excluded)"
fi
# and no resolver either: dns.c goes with http.c, because it is the other
# half of the socket/netconfig closure the static build exists to avoid
if nm "$APKGNH" | grep -qE '\b(apkg_resolve|apkg_dns_query|gethostbyname)\b'; then
    bad "nohttp binary still references the resolver"
else
    ok "nohttp binary has no resolver symbol (no sockets, no gethostbyname)"
fi
# dns.c must also be SAFE to compile under -DAPKG_NO_HTTP (build-amix-static.sh
# derives its file list from the Makefile's SRCS): the whole file is #ifdef'd
# out, so it must build clean and define no socket-using symbol
( cd "$SRC" && gcc -std=gnu89 -O2 -Wall -Wextra -DAPKG_NO_HTTP \
    -c dns.c -o "$WORK/dns-nohttp.o" ) 2>"$WORK/dns-nohttp.err" \
    && [ ! -s "$WORK/dns-nohttp.err" ] \
    && ok "dns.c compiles clean and empty under -DAPKG_NO_HTTP" \
    || bad "dns.c does not compile cleanly under -DAPKG_NO_HTTP" \
           "$(cat "$WORK/dns-nohttp.err")"
if nm "$WORK/dns-nohttp.o" 2>/dev/null | grep -qE ' T | U '; then
    bad "dns.c under -DAPKG_NO_HTTP still defines or references symbols" \
        "$(nm "$WORK/dns-nohttp.o")"
else
    ok "the -DAPKG_NO_HTTP dns.o is empty (no symbols at all)"
fi

# ---------------------------------------------------------------- fixtures
ROOT=$WORK/root
SHIMLOG=$WORK/shim.log; : > "$SHIMLOG"
P=$WORK/repo/pkgs

printf 'fake SVR4 datastream for foo-1.0.pkg\n' > "$P/foo-1.0.pkg"
dd if=/dev/urandom bs=256 count=1 2>/dev/null >> "$P/foo-1.0.pkg"

md5of()  { md5sum "$1" | cut -d' ' -f1; }
sizeof() { wc -c < "$1" | tr -d ' '; }
DATA_OFF=65536
cat > "$WORK/repo/catalog" <<EOF
#apkg-catalog 1
foo|1.0|FOO|foo-1.0.pkg|$(md5of "$P/foo-1.0.pkg")|$(sizeof "$P/foo-1.0.pkg")|none|system|Foo base package|$DATA_OFF
EOF
md5sum "$WORK/repo/catalog" > "$WORK/repo/catalog.md5"

# a self-describing raw slice built to the exact source.c layout constants
python3 - "$WORK" "$P" <<'PY'
import hashlib, os, sys
work, P = sys.argv[1], sys.argv[2]
CAT_OFF, MD5_OFF, DATA_OFF = 0, 32768, 65536
data = open(os.path.join(P, "foo-1.0.pkg"), "rb").read()
fields = ["foo", "1.0", "FOO", "foo-1.0.pkg",
          hashlib.md5(data).hexdigest(), str(len(data)),
          "none", "system", "Foo base package", str(DATA_OFF)]
cat = ("#apkg-catalog 1\n" + "|".join(fields) + "\n").encode()
md5 = (hashlib.md5(cat).hexdigest() + "  catalog\n").encode()
end = DATA_OFF + ((len(data) + 511) // 512) * 512
img = bytearray(end)
img[CAT_OFF:CAT_OFF + len(cat)] = cat
img[MD5_OFF:MD5_OFF + len(md5)] = md5
img[DATA_OFF:DATA_OFF + len(data)] = data
open(os.path.join(work, "raw.img"), "wb").write(img)
PY

# pkgadd/pkgrm shims (log argv only)
cat > "$WORK/bin/pkgadd-shim" <<EOF
#!/bin/sh
echo "pkgadd \$*" >> $SHIMLOG
exit 0
EOF
cat > "$WORK/bin/pkgrm-shim" <<EOF
#!/bin/sh
echo "pkgrm \$*" >> $SHIMLOG
exit 0
EOF
chmod +x "$WORK/bin/pkgadd-shim" "$WORK/bin/pkgrm-shim"

cat > "$ROOT/var/apkg/admin" <<EOF
instance=quit
action=nocheck
mail=
EOF

mkconf() {
    cat > "$1" <<EOF
repo=$2
cachedir=$ROOT/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
timeout=10
EOF
}
mkconf "$WORK/conf-http" "http://127.0.0.1:1/repo"
mkconf "$WORK/conf-file" "file://$WORK/repo"
mkconf "$WORK/conf-fabs" "$WORK/repo"
mkconf "$WORK/conf-raw"  "raw:$WORK/raw.img"

APKG_ROOT=$ROOT; export APKG_ROOT
CACHE=$ROOT/var/apkg/cache
CATFILE=$ROOT/var/apkg/catalog
FAILMSG="http: not available in the static/install build"

echo "== running tests =="

# ---------------------------------------------- (1) http:// FAILS CLOSED
rm -f "$CATFILE"
run 1 "nohttp: http:// repo is refused (exit 1, fail closed)" \
    "$APKGNH" -c "$WORK/conf-http" update
echo "$OUT" | grep -qF "$FAILMSG" \
    && ok "nohttp: refusal message is the documented one" \
    || bad "nohttp: refusal message wrong" "$OUT"
[ ! -f "$CATFILE" ] \
    && ok "nohttp: http:// wrote no catalog (never fell through to a backend)" \
    || bad "nohttp: http:// produced a catalog - it was misclassified"
# and it is refused at EVERY verb that opens a source, not just update
run 1 "nohttp: http:// refused on install too (fail closed everywhere)" \
    "$APKGNH" -c "$WORK/conf-http" install foo

# the shared (HTTP-capable) build, by contrast, ACCEPTS http:// as HTTP -
# it gets past classification and fails only later at the dead socket
# (exit 2 = network).  This proves the ONLY behavioural difference is the
# deliberate http:// cut.
run 2 "shared build accepts http:// (classifies as HTTP; exit 2 at dead net)" \
    "$APKG" -c "$WORK/conf-http" update

# ---------------------------------------------- (2) FILE parity
# file:// update + install, run through BOTH binaries; compare.
run_file_scenario() {   # $1 = binary  $2 = shimlog  $3 = cache
    : > "$2"; rm -rf "$3"; rm -f "$CATFILE"
    "$1" -c "$WORK/conf-file" update    >/dev/null 2>&1 || return 1
    "$1" -c "$WORK/conf-file" install foo >/dev/null 2>&1 || return 1
    return 0
}
SLOG_SH=$WORK/shim-shared.log; SLOG_NH=$WORK/shim-nohttp.log
# shared build writes to $SHIMLOG via the shim; capture per-run by moving it
: > "$SHIMLOG"; rm -rf "$CACHE"; rm -f "$CATFILE"
run 0 "nohttp: file:// update"      "$APKGNH" -c "$WORK/conf-file" update
cmp -s "$CATFILE" "$WORK/repo/catalog" \
    && ok "nohttp: file:// stored the catalog verbatim" \
    || bad "nohttp: file:// catalog bytes wrong"
: > "$SHIMLOG"
run 0 "nohttp: file:// install foo" "$APKGNH" -c "$WORK/conf-file" install foo
cp "$SHIMLOG" "$SLOG_NH"
grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $WORK/repo/pkgs/foo-1.0.pkg FOO" "$SLOG_NH" \
    && ok "nohttp: file:// plain .pkg handed to pkgadd IN PLACE (no cache copy)" \
    || bad "nohttp: file:// in-place staging wrong" "$(cat "$SLOG_NH")"
# same scenario through the shared build
: > "$SHIMLOG"; rm -rf "$CACHE"; rm -f "$CATFILE"
"$APKG" -c "$WORK/conf-file" update >/dev/null 2>&1
: > "$SHIMLOG"
"$APKG" -c "$WORK/conf-file" install foo >/dev/null 2>&1
cp "$SHIMLOG" "$SLOG_SH"
cmp -s "$SLOG_NH" "$SLOG_SH" \
    && ok "FILE parity: nohttp pkgadd argv byte-identical to the shared build" \
    || bad "FILE parity: pkgadd argv differs" "nohttp:$(cat "$SLOG_NH") shared:$(cat "$SLOG_SH")"

# bare absolute /path (what an installer passes) also works
rm -f "$CATFILE"
run 0 "nohttp: bare /path source (installer /cdrom form)" \
    "$APKGNH" -c "$WORK/conf-fabs" update

# ---------------------------------------------- (3) RAW parity
: > "$SHIMLOG"; rm -rf "$CACHE"; rm -f "$CATFILE"
run 0 "nohttp: raw: update reads the offset catalog at offset 0" \
    "$APKGNH" -c "$WORK/conf-raw" update
: > "$SHIMLOG"
run 0 "nohttp: raw: install foo dd's by catalog offset" \
    "$APKGNH" -c "$WORK/conf-raw" install foo
cmp -s "$CACHE/foo-1.0.pkg" "$P/foo-1.0.pkg" \
    && ok "nohttp: raw-extracted bytes match the original package" \
    || bad "nohttp: raw-extracted bytes differ"
NH_RAW=$WORK/nh-raw-foo.pkg; cp "$CACHE/foo-1.0.pkg" "$NH_RAW" 2>/dev/null
# same through the shared build, compare staged bytes
: > "$SHIMLOG"; rm -rf "$CACHE"; rm -f "$CATFILE"
"$APKG" -c "$WORK/conf-raw" update >/dev/null 2>&1
: > "$SHIMLOG"
"$APKG" -c "$WORK/conf-raw" install foo >/dev/null 2>&1
cmp -s "$NH_RAW" "$CACHE/foo-1.0.pkg" \
    && ok "RAW parity: nohttp staged bytes byte-identical to the shared build" \
    || bad "RAW parity: staged bytes differ"

# ---------------------------------------------- (4) kernel-space parity
# 40 section 6 / C3-5 v8 section 1.2 through kspace.c: a module's device
# nodes, c under /dev/ and b under /dev/dsk/ (the ramdisk's ram0-2 b 20),
# pass; a b node elsewhere, a short or classed b line, a p, s or l entry and
# a b node in a kernel package are refused.  Dry-run installs (-n) of each
# with its kernel, through both binaries: same rc, same output.
KW=$WORK/kspace; KP=$KW/repo/pkgs/kernel
mkdir -p "$KP" "$KW/root/var/apkg" "$KW/root/var/sadm/pkg"
cp "$ROOT/var/apkg/admin" "$KW/root/var/apkg/admin"
KPIN=gcc-2.7.2.3-8949028
kds() {     # kds <file> <pkginst> <directives...>  (a module package)
    f=$1; i=$2; shift 2
    { printf 'DIR /etc\nDIR /etc/conf\nDIR /etc/conf/mod.d\nFILE /etc/conf/mod.d/%s o\nDIR /dev\n' "$i"
      printf '%s\n' "$@"; } | python3 "$TESTS/mkds.py" "$KP/$f" "$i" 1.0
}
printf 'DIR /stand\nDIR /stand/k46\nFILE /stand/k46/unix u\n' \
    | python3 "$TESTS/mkds.py" "$KP/k46.pkg" KERNK46 1.1.0
printf 'DIR /stand\nDIR /stand/k46\nFILE /stand/k46/unix u\nDIR /dev\nDIR /dev/dsk\nBDEV /dev/dsk/ram0 20 0\n' \
    | python3 "$TESTS/mkds.py" "$KP/kbdev.pkg" KBDEV 1.0
kds ram46.pkg ram46 "DIR /dev/dsk" "BDEV /dev/dsk/ram0 20 0" \
    "BDEV /dev/dsk/ram1 20 1" "BDEV /dev/dsk/ram2 20 2"
kds zeth46.pkg zeth46 "CDEV /dev/zen0 51 0"
kds zdevb.pkg zdevb "PKGMAP 1 b none /dev/zbd0 52 0 0644 root root"
kds zdevbm.pkg zdevbm "PKGMAP 1 b none /dev/dsk/ram0 20 0600 root root"
kds zdevbk.pkg zdevbk "PKGMAP 1 b kcls /dev/dsk/ram0 20 0 0600 root root"
kds zdevp.pkg zdevp "PKGMAP 1 p none /dev/zpipe 0644 root root"
kds zdevs.pkg zdevs "PKGMAP 1 s none /dev/zsl=/dev/zen0"
kds zdevl.pkg zdevl "PKGMAP 1 l none /dev/zln=/dev/zen0"
kl() {      # kl <name> <role> <file>
    printf '#kpkg %s 1.0 role=%s line=k46 kabi=k46.1.0 pin=%s size=%s sha256=%s file=kernel/%s\n' \
        "$1" "$2" "$KPIN" "$(sizeof "$KP/$3")" "$(sha256sum "$KP/$3" | cut -c1-64)" "$3"
}
{ echo "#apkg-catalog 1"; echo "#ext kpkg 1"
  kl kernel-k46 kernel k46.pkg; kl kbdev kernel kbdev.pkg
  for i in ram46 zeth46 zdevb zdevbm zdevbk zdevp zdevs zdevl; do kl $i module $i.pkg; done
  echo "#end kpkg"; } > "$KW/repo/catalog"
md5sum "$KW/repo/catalog" > "$KW/repo/catalog.md5"
cat > "$KW/conf" <<EOF
repo=file://$KW/repo
cachedir=$KW/root/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$KW/root/var/apkg/admin
kbootset=/bin/true
EOF
APKG_ROOT=$KW/root "$APKG" -c "$KW/conf" update >/dev/null 2>&1
for i in ram46 zeth46 kbdev zdevb zdevbm zdevbk zdevp zdevs zdevl; do
    case $i in
    ram46|zeth46) want=0; why= ;;
    kbdev)  want=3; why="an object of type b at /dev/dsk/ram0" ;;
    zdevb)  want=3; why="a block device node outside /dev/dsk/: /dev/zbd0" ;;
    zdevbm) want=3; why="a device entry not of the form <major> <minor> <mode> <owner> <group>: /dev/dsk/ram0" ;;
    zdevbk) want=3; why="an object in class kcls" ;;
    zdevp)  want=3; why="an object of type p at /dev/zpipe" ;;
    zdevs)  want=3; why="an object of type s at /dev/zsl=/dev/zen0" ;;
    zdevl)  want=3; why="an object of type l at /dev/zln=/dev/zen0" ;;
    esac
    names="kernel-k46 $i"; [ $i = kbdev ] && names=kbdev
    run $want "nohttp: -n install $i: rc $want${why:+ ($why)}" \
        env APKG_ROOT="$KW/root" "$APKGNH" -n -c "$KW/conf" install $names
    NHOUT=$OUT
    [ -z "$why" ] || echo "$OUT" | grep -qF "$i: not a pure-file kernel-space package: $why" \
        || bad "nohttp: $i refusal message" "$OUT"
    SHOUT=$(APKG_ROOT="$KW/root" "$APKG" -n -c "$KW/conf" install $names 2>&1)
    [ "$SHOUT" = "$NHOUT" ] \
        && ok "KSPACE parity: $i byte-identical through the shared build" \
        || bad "KSPACE parity: $i differs" "nohttp:$NHOUT shared:$SHOUT"
done

# ---------------------------------------------------------------- summary
echo
echo "== nohttp variant: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
