#!/bin/sh
# run-tests.sh - host-side functional tests for apkg.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# Strictly localhost: a fixture repo served by python3 -m http.server
# on 127.0.0.1, pkgadd/pkgrm replaced by shim scripts that log their
# argv, and the /var/sadm + /var/apkg + /etc/apkg.conf tree faked
# under a scratch root selected with the APKG_ROOT environment
# variable (a compiled-in prefix override, added precisely for this).
#
# Usage: sh tests/run-tests.sh   (or: make test)

set -u

SRC=$(cd "$(dirname "$0")/.." && pwd)
TESTS=$SRC/tests
WORK=$TESTS/work
APKG=$SRC/apkg

PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    echo "PASS: $1"
}

bad() {
    FAIL=$((FAIL + 1))
    echo "FAIL: $1"
    if [ -n "${2:-}" ]; then
        echo "----- output -----"
        echo "$2"
        echo "------------------"
    fi
}

# run <expected-rc> <desc> <cmd...>; captures combined output in $OUT
run() {
    want=$1; desc=$2; shift 2
    OUT=$("$@" 2>&1)
    rc=$?
    if [ "$rc" -eq "$want" ]; then
        ok "$desc"
    else
        bad "$desc (rc=$rc, wanted $want)" "$OUT"
    fi
}

# ---------------------------------------------------------------- setup

command -v python3 >/dev/null || { echo "python3 required"; exit 1; }
command -v md5sum  >/dev/null || { echo "md5sum required"; exit 1; }

echo "== building host apkg =="
make -C "$SRC" host >/dev/null || { echo "host build failed"; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK/repo/pkgs" "$WORK/badrepo" "$WORK/badmd5repo" \
         "$WORK/bin" "$WORK/root/etc" "$WORK/root/var/apkg" \
         "$WORK/root/var/sadm/install" \
         "$WORK/root/var/sadm/pkg/SAMEPKG" \
         "$WORK/root/var/sadm/pkg/OLDPKG" \
         "$WORK/root/var/sadm/pkg/UNVER" \
         "$WORK/root/var/sadm/pkg/FDEP" \
         "$WORK/root/var/sadm/pkg/FTOP"

ROOT=$WORK/root
SHIMLOG=$WORK/shim.log
: > "$SHIMLOG"

# --- fake packages (content only needs to be stable bytes) ---
mkpkg() {
    printf 'fake SVR4 datastream for %s\n' "$1" > "$WORK/repo/pkgs/$1"
    dd if=/dev/urandom of="$WORK/repo/pkgs/$1.pad" bs=256 count=1 2>/dev/null
    cat "$WORK/repo/pkgs/$1.pad" >> "$WORK/repo/pkgs/$1"
    rm -f "$WORK/repo/pkgs/$1.pad"
}
for f in foo-1.0.pkg bar-2.0.pkg baz-1.1.pkg oldpkg-2.0.pkg \
         samepkg-1.0.pkg unver-1.5.pkg corrupt-1.0.pkg \
         fdep-1.0.pkg ftop-1.0.pkg dtop-1.0.pkg; do
    mkpkg "$f"
done
# categorized-subdirectory package: the catalog filename carries a '/'
# (repo layout pkgs/stock/, pkgs/base/, ...); the cache uses the basename
mkdir -p "$WORK/repo/pkgs/stock"
mkpkg "stock/net-2.1.pkg"
# compressed package: gzip's zcat reads it regardless of suffix
printf 'fake SVR4 datastream for zpkg-1.0.pkg\n' > "$WORK/zpkg-plain"
gzip -c "$WORK/zpkg-plain" > "$WORK/repo/pkgs/zpkg-1.0.pkg.Z"

md5of() { md5sum "$1" | cut -d' ' -f1; }
sizeof() { wc -c < "$1" | tr -d ' '; }

P=$WORK/repo/pkgs
cat > "$WORK/repo/catalog" <<EOF
#apkg-catalog 1
# fixture catalog for apkg tests
foo|1.0|FOO|foo-1.0.pkg|$(md5of $P/foo-1.0.pkg)|$(sizeof $P/foo-1.0.pkg)|none|system|Foo base library
bar|2.0|BAR|bar-2.0.pkg|$(md5of $P/bar-2.0.pkg)|$(sizeof $P/bar-2.0.pkg)|foo|system|Bar tool that depends on foo
baz|1.1|BAZ|baz-1.1.pkg|$(md5of $P/baz-1.1.pkg)|$(sizeof $P/baz-1.1.pkg)|bar|system|Baz application that depends on bar
oldpkg|2.0|OLDPKG|oldpkg-2.0.pkg|$(md5of $P/oldpkg-2.0.pkg)|$(sizeof $P/oldpkg-2.0.pkg)|none|system|Upgradable package fixture
samepkg|1.0|SAMEPKG|samepkg-1.0.pkg|$(md5of $P/samepkg-1.0.pkg)|$(sizeof $P/samepkg-1.0.pkg)|none|system|Already installed package
unver|1.5|UNVER|unver-1.5.pkg|$(md5of $P/unver-1.5.pkg)|$(sizeof $P/unver-1.5.pkg)|none|system|Installed but VERSION-less package
misdep|1.0|MISDEP|misdep-1.0.pkg|00000000000000000000000000000000|1|nosuchpkg|system|Package with a missing dependency
cyca|1.0|CYCA|cyca-1.0.pkg|00000000000000000000000000000000|1|cycb|system|Dependency cycle half A
cycb|1.0|CYCB|cycb-1.0.pkg|00000000000000000000000000000000|1|cyca|system|Dependency cycle half B
corrupt|1.0|CORRUPT|corrupt-1.0.pkg|ffffffffffffffffffffffffffffffff|$(sizeof $P/corrupt-1.0.pkg)|none|system|Catalog md5 never matches this file
zpkg|1.0|ZPKG|zpkg-1.0.pkg.Z|$(md5of $P/zpkg-1.0.pkg.Z)|$(sizeof $P/zpkg-1.0.pkg.Z)|none|system|Compressed dot-Z package
net|2.1|NETPKG|stock/net-2.1.pkg|$(md5of $P/stock/net-2.1.pkg)|$(sizeof $P/stock/net-2.1.pkg)|none|system|Package living in a repo subdirectory
fdep|1.0|FDEP|fdep-1.0.pkg|$(md5of $P/fdep-1.0.pkg)|$(sizeof $P/fdep-1.0.pkg)|none|system|Installed dependency, same version as the catalog
ftop|1.0|FTOP|ftop-1.0.pkg|$(md5of $P/ftop-1.0.pkg)|$(sizeof $P/ftop-1.0.pkg)|fdep|system|Installed package whose dep fdep is also installed
dtop|1.0|DTOP|dtop-1.0.pkg|$(md5of $P/dtop-1.0.pkg)|$(sizeof $P/dtop-1.0.pkg)|oldpkg|system|Not installed; depends on the upgradable oldpkg
EOF
md5sum "$WORK/repo/catalog" > "$WORK/repo/catalog.md5"

# bad-header repo: valid-looking lines, no magic first line
cat > "$WORK/badrepo/catalog" <<EOF
foo|1.0|FOO|foo-1.0.pkg|00000000000000000000000000000000|1|none|system|No header here
EOF

# bad-md5 repo: fine catalog, lying catalog.md5
cp "$WORK/repo/catalog" "$WORK/badmd5repo/catalog"
echo "deadbeefdeadbeefdeadbeefdeadbeef  catalog" > "$WORK/badmd5repo/catalog.md5"

# --- pkgadd/pkgrm shims (log argv; the real engine's lock is fixed, so
#     apkg no longer clears any lock and the shims model none) ---
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
cat > "$WORK/bin/pkgadd-fail" <<EOF
#!/bin/sh
echo "pkgadd-fail \$*" >> $SHIMLOG
exit 1
EOF
# pkgadd-prompt: models the stock 1991 pkgadd that PROMPTS (conflict /
# "Do you want to continue") even under -n on some error paths -- it reads a
# line from stdin.  A batch/installer run feeds no stdin, so on EOF (apkg
# redirects the child to /dev/null -- METAL-FIX.3) it ABORTS non-zero, like
# the real engine.  On a NEVER-EOF stdin (the pre-fix inherited-console
# case) the read would BLOCK FOREVER -- which is exactly the metal wedge.
cat > "$WORK/bin/pkgadd-prompt" <<EOF
#!/bin/sh
echo "pkgadd-prompt \$*" >> $SHIMLOG
printf 'Do you want to continue with the installation [y,n,?] '
if read answer; then
    [ "\$answer" = y ] && exit 0
    echo "aborted at user request"; exit 3
else
    echo; echo "No changes were made to the system."; exit 3
fi
EOF
chmod +x "$WORK/bin/pkgadd-shim" "$WORK/bin/pkgrm-shim" \
         "$WORK/bin/pkgadd-fail" "$WORK/bin/pkgadd-prompt"

# --- fake installed state (/var/sadm/pkg/<PKGINST>/pkginfo) ---
cat > "$ROOT/var/sadm/pkg/SAMEPKG/pkginfo" <<EOF
PKG=SAMEPKG
NAME=Already installed package
VERSION=1.0
CATEGORY=system
EOF
cat > "$ROOT/var/sadm/pkg/OLDPKG/pkginfo" <<EOF
PKG=OLDPKG
NAME=Upgradable package fixture
VERSION=1.0
CATEGORY=system
EOF
cat > "$ROOT/var/sadm/pkg/UNVER/pkginfo" <<EOF
PKG=UNVER
NAME=Installed but VERSION-less package
CATEGORY=system
EOF
# force-scope fixtures: a named package AND its dependency both installed
# at exactly the catalog version, so -f has something to over-reach into
cat > "$ROOT/var/sadm/pkg/FDEP/pkginfo" <<EOF
PKG=FDEP
NAME=Installed dependency
VERSION=1.0
CATEGORY=system
EOF
cat > "$ROOT/var/sadm/pkg/FTOP/pkginfo" <<EOF
PKG=FTOP
NAME=Installed package with an installed dep
VERSION=1.0
CATEGORY=system
EOF

# admin file (content irrelevant to the shims; presence mirrors reality).
# The comment line is a MARKER: conf_adminfile() derives <admin>.overwrite
# from this file, so seeing the marker there proves the operator's own keys
# were carried across rather than a stock body being dropped on top.
mkadmin() {
    cat > "$ROOT/var/apkg/admin" <<EOF
# apkg-test-admin-marker
instance=quit
action=nocheck
mail=
EOF
}
mkadmin

# --- servers ---
freeport() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}
wait_port() {
    n=0
    while [ $n -lt 50 ]; do
        if python3 -c "import socket
s=socket.socket(); s.settimeout(0.2)
s.connect(('127.0.0.1', $1)); s.close()" 2>/dev/null; then
            return 0
        fi
        n=$((n + 1))
        sleep 0.1
    done
    return 1
}

PORT=$(freeport)
( cd "$WORK" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 ) \
    >/dev/null 2>&1 &
SRV_PID=$!

RPORT=$(freeport)
python3 "$TESTS/redirect-server.py" "$RPORT" "$WORK" >/dev/null 2>&1 &
RSRV_PID=$!

# slow/stall server for the inactivity-timeout tests: 64 KB per write,
# 0.5 s between writes, and a 256-byte prefix before going silent.
SPORT=$(freeport)
python3 "$TESTS/slow-server.py" "$SPORT" "$WORK" 65536 0.5 256 \
    >/dev/null 2>&1 &
SSRV_PID=$!

DEADPORT=$(freeport)   # nothing listens here: the network-down case

cleanup() {
    kill "$SRV_PID" "$RSRV_PID" "$SSRV_PID" 2>/dev/null
    wait "$SRV_PID" "$RSRV_PID" "$SSRV_PID" 2>/dev/null
}
trap cleanup EXIT INT TERM

wait_port "$PORT"  || { echo "http.server did not come up"; exit 1; }
wait_port "$RPORT" || { echo "redirect server did not come up"; exit 1; }
wait_port "$SPORT" || { echo "slow server did not come up"; exit 1; }

# --- config files ---
mkconf() {
    cat > "$1" <<EOF
# apkg test configuration
repo=$2
cachedir=$ROOT/var/apkg/cache
pkgadd=$3
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
timeout=${4:-10}
retries=0
retry_delay=0
EOF
}
CONF=$ROOT/etc/apkg.conf     # default location under APKG_ROOT
mkconf "$CONF"                "http://127.0.0.1:$PORT/repo"      "$WORK/bin/pkgadd-shim"
mkconf "$WORK/conf-fail"      "http://127.0.0.1:$PORT/repo"      "$WORK/bin/pkgadd-fail"
mkconf "$WORK/conf-prompt"    "http://127.0.0.1:$PORT/repo"      "$WORK/bin/pkgadd-prompt"
mkconf "$WORK/conf-badhdr"    "http://127.0.0.1:$PORT/badrepo"   "$WORK/bin/pkgadd-shim"
mkconf "$WORK/conf-badmd5"    "http://127.0.0.1:$PORT/badmd5repo" "$WORK/bin/pkgadd-shim"
mkconf "$WORK/conf-redirect"  "http://127.0.0.1:$RPORT/r"        "$WORK/bin/pkgadd-shim"
mkconf "$WORK/conf-down"      "http://127.0.0.1:$DEADPORT/repo"  "$WORK/bin/pkgadd-shim"

APKG_ROOT=$ROOT
export APKG_ROOT

CACHE=$ROOT/var/apkg/cache
CATFILE=$ROOT/var/apkg/catalog

echo "== running tests =="

# ------------------------------------------------ update
# (uses the default $APKG_ROOT/etc/apkg.conf - also covers APKG_ROOT
#  config discovery)
run 0 "update fetches and installs the catalog" "$APKG" update
[ -f "$CATFILE" ] && ok "catalog file exists at \$APKG_ROOT/var/apkg/catalog" \
                  || bad "catalog file missing at $CATFILE"
if cmp -s "$CATFILE" "$WORK/repo/catalog"; then
    ok "catalog content matches the repo copy"
else
    bad "catalog content differs from repo copy"
fi
echo "$OUT" | grep -q "catalog updated: 15 packages" \
    && ok "update reports 15 packages" \
    || bad "update output unexpected" "$OUT"
# catalog.md5 was present, so verbose update must verify it
OUT=$("$APKG" -v update 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "catalog md5 verified"; then
    ok "update verifies catalog.md5 when present"
else
    bad "update did not verify catalog.md5 (rc=$rc)" "$OUT"
fi

# ------------------------------------------------ update failure modes
run 3 "update rejects catalog without header (exit 3)" \
    "$APKG" -c "$WORK/conf-badhdr" update
run 3 "update rejects catalog.md5 mismatch (exit 3)" \
    "$APKG" -c "$WORK/conf-badmd5" update
run 2 "update with server down fails with exit 2" \
    "$APKG" -c "$WORK/conf-down" update

# ------------------------------------------------ 302 redirect
rm -f "$CATFILE"
run 0 "update follows one 302 redirect" "$APKG" -c "$WORK/conf-redirect" update
cmp -s "$CATFILE" "$WORK/repo/catalog" \
    && ok "redirected update stored the right catalog" \
    || bad "redirected update stored wrong catalog bytes"

# ------------------------------------------------ list
OUT=$("$APKG" list 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "^foo " && \
   echo "$OUT" | grep "^samepkg" | grep -q "installed 1.0"; then
    ok "list shows catalog with installed markers"
else
    bad "list output unexpected (rc=$rc)" "$OUT"
fi
echo "$OUT" | grep "^unver" | grep -q "installed (none)" \
    && ok "list shows (none) for VERSION-less installed package" \
    || bad "list marker for VERSION-less package wrong" "$OUT"
OUT=$("$APKG" list installed 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "^samepkg" && \
   ! echo "$OUT" | grep -q "^foo "; then
    ok "list installed filters to installed packages"
else
    bad "list installed output unexpected (rc=$rc)" "$OUT"
fi
run 0 "list all works" "$APKG" list all
run 1 "list rejects unknown filter word" "$APKG" list bananas

# ------------------------------------------------ search
OUT=$("$APKG" search upgradable 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "^oldpkg"; then
    ok "search matches description case-insensitively"
else
    bad "search output unexpected (rc=$rc)" "$OUT"
fi
OUT=$("$APKG" search zzz-no-such 2>&1); rc=$?
[ $rc -eq 0 ] && [ -z "$OUT" ] && ok "search with no hits prints nothing, exit 0" \
    || bad "search no-hit behaviour wrong (rc=$rc)" "$OUT"

# ------------------------------------------------ info
OUT=$("$APKG" info bar 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "Depends:     foo" && \
   echo "$OUT" | grep -q "Installed:   no"; then
    ok "info shows full entry and installed state"
else
    bad "info output unexpected (rc=$rc)" "$OUT"
fi
run 1 "info on unknown package fails with exit 1" "$APKG" info nosuch

# ------------------------------------------------ download
run 0 "download fetches and verifies foo" "$APKG" download foo
cmp -s "$CACHE/foo-1.0.pkg" "$P/foo-1.0.pkg" \
    && ok "downloaded file matches repo bytes" \
    || bad "downloaded foo differs from repo copy"
run 3 "download with corrupted md5 fails with exit 3" "$APKG" download corrupt
[ ! -f "$CACHE/corrupt-1.0.pkg" ] \
    && ok "corrupt download was removed from cache" \
    || bad "corrupt file left in cache"

# ------------------------------------------------ install with dep chain
: > "$SHIMLOG"
run 0 "install baz resolves dep chain" "$APKG" install baz
CHAIN=$(grep '^pkgadd ' "$SHIMLOG" | sed 's/.* //')
if [ "$CHAIN" = "FOO
BAR
BAZ" ]; then
    ok "pkgadd ran in dependency order (FOO BAR BAZ)"
else
    bad "pkgadd order wrong" "$(cat $SHIMLOG)"
fi
grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $CACHE/foo-1.0.pkg FOO" "$SHIMLOG" \
    && ok "pkgadd argv is -n -a <admin> -d <cachefile> <pkginst>" \
    || bad "pkgadd argv unexpected" "$(cat $SHIMLOG)"

# ------------------------------------------------ already-installed skip + -f
: > "$SHIMLOG"
OUT=$("$APKG" install samepkg 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "already installed" && \
   ! grep -q SAMEPKG "$SHIMLOG"; then
    ok "install skips already-installed same version"
else
    bad "already-installed skip broken (rc=$rc)" "$OUT"
fi
: > "$SHIMLOG"
OUT=$("$APKG" -f install samepkg 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "pkgadd .* SAMEPKG" "$SHIMLOG"; then
    ok "-f forces reinstall of same version"
else
    bad "-f reinstall broken (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi

# ------------------------------------------------ dry run
: > "$SHIMLOG"
OUT=$("$APKG" -n -f install samepkg 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "would run:" && \
   [ ! -s "$SHIMLOG" ]; then
    ok "-n dry-run prints plan and touches nothing"
else
    bad "dry-run behaviour wrong (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi

# ------------------------------------------------ -f scope: NAMED packages only
# METAL 2026-09-16: `apkg -f install apkg` re-pkgadd'ed the whole dependency
# closure, including the 2.3 MB APKGENG engine -- >4 minutes on a 68LC060
# before it reached the package the operator had actually named.  -f means
# "reinstall what I asked for", not "reinstall everything it rests on".
: > "$SHIMLOG"
OUT=$("$APKG" -f install ftop 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "pkgadd .* FTOP" "$SHIMLOG" && \
   ! grep -q "pkgadd .* FDEP" "$SHIMLOG"; then
    ok "-f re-installs the NAMED package only, not its installed deps"
else
    bad "-f scope wrong (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
# ... but a MISSING dependency is still installed under -f: the closure is
# what makes install work at all.
mv "$ROOT/var/sadm/pkg/FDEP" "$ROOT/var/sadm/pkg/FDEP.off"
: > "$SHIMLOG"
OUT=$("$APKG" -f install ftop 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "pkgadd .* FDEP" "$SHIMLOG" && \
   grep -q "pkgadd .* FTOP" "$SHIMLOG"; then
    ok "-f still installs a MISSING dependency"
else
    bad "-f missing-dep handling wrong (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
mv "$ROOT/var/sadm/pkg/FDEP.off" "$ROOT/var/sadm/pkg/FDEP"

# ------------------------------------------------ installed, catalog is NEWER
# METAL 2026-09-16: `apkg install apkg` said "already installed" and skipped,
# even though the catalog held a newer version -- so the operator had no way
# to discover that an upgrade existed.  Worse, letting it fall through to
# pkgadd hits instance=quit and stops with "Unable to determine whether to
# overwrite an existing package instance".  Named -> refuse, name the version
# gap, and point at the upgrade verb.
: > "$SHIMLOG"
OUT=$("$APKG" install oldpkg 2>&1); rc=$?
if [ $rc -eq 1 ] && echo "$OUT" | grep -q "apkg upgrade oldpkg" && \
   echo "$OUT" | grep -q "catalog has 2.0" && [ ! -s "$SHIMLOG" ]; then
    ok "install of an out-of-date package points at 'apkg upgrade' (exit 1)"
else
    bad "out-of-date install handling wrong (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
# as a DEPENDENCY the same situation is not an error: the dep is satisfied,
# it is reported, and it is NOT silently upgraded behind the operator's back
: > "$SHIMLOG"
OUT=$("$APKG" install dtop 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "pkgadd .* DTOP" "$SHIMLOG" && \
   ! grep -q "pkgadd .* OLDPKG" "$SHIMLOG" && \
   echo "$OUT" | grep -q "apkg upgrade oldpkg"; then
    ok "an out-of-date DEPENDENCY is reported, satisfied, and not upgraded"
else
    bad "out-of-date dependency handling wrong (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi

# ------------------------------------------------ missing dep / cycle / unknown
run 5 "install with missing dep fails with exit 5" "$APKG" install misdep
run 5 "install with dependency cycle fails with exit 5" "$APKG" install cyca
run 5 "install of name not in catalog fails with exit 5" "$APKG" install nosuch

# ------------------------------------------------ pkgadd failure -> exit 4
: > "$SHIMLOG"
rm -f "$CACHE/foo-1.0.pkg"
run 4 "pkgadd failure stops install with exit 4" \
    "$APKG" -c "$WORK/conf-fail" install foo

# ------------------------------------------------ no-hang: a PROMPTING pkgadd
# METAL-FIX.3.  A pkgadd that prompts (conflict/continue) with no stdin used
# to HANG apkg forever: the child inherited apkg's stdin, blocked on the
# prompt, and waitpid() never returned -> apkg never propagated a failure and
# the console wedged (M-RUN1, "No changes were made to the system." for 60s+).
# Fixed by redirecting the child's stdin to /dev/null, so the prompt reads EOF
# and pkgadd aborts non-zero.  This test would HANG (time out) against the old
# code and fast-fails with exit 4 against the fix.  We give apkg a never-EOF
# stdin (a FIFO held open by a non-writing sleeper) precisely so the old bug
# would manifest -- proving the child's stdin, not apkg's, is what got closed.
if command -v timeout >/dev/null 2>&1 && command -v mkfifo >/dev/null 2>&1; then
    : > "$SHIMLOG"
    rm -f "$CACHE/foo-1.0.pkg"
    FIFO=$WORK/hangstdin.fifo
    rm -f "$FIFO"; mkfifo "$FIFO"
    sleep 30 > "$FIFO" &          # hold the write end open, never write
    HOLDER=$!
    OUT=$(timeout 10 "$APKG" -c "$WORK/conf-prompt" install foo < "$FIFO" 2>&1)
    rc=$?
    kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
    rm -f "$FIFO"
    if [ "$rc" -eq 124 ]; then
        bad "prompting pkgadd HUNG the install (timed out; child stdin not redirected)" "$OUT"
    elif [ "$rc" -eq 4 ]; then
        ok "prompting pkgadd fast-fails with exit 4 (prompt got EOF, no hang)"
    else
        bad "prompting pkgadd: unexpected rc=$rc (wanted 4)" "$OUT"
    fi
    echo "$OUT" | grep -q "pkgadd failed for foo" \
        && ok "fast-fail names the failed package (foo)" \
        || bad "fast-fail did not name the failed package" "$OUT"
else
    echo "SKIP: timeout(1)/mkfifo(1) unavailable - skipping the no-hang test"
fi

# ------------------------------------------------ upgrade
#
# THE BRICK, AND ITS TWO FIXES (metal, A4000D/68LC060,
# 2026-09-16).  `apkg upgrade apkg` used to be pkgrm-then-pkgadd.  On the
# box the pkgrm SUCCEEDED -- and took /var/apkg/admin with it, because the
# APKG package OWNS that file as an `e` entry -- so the follow-on pkgadd
# died with "unable to open admin file </var/apkg/admin>" and the box was
# left with NO apkg and no way to fetch one.  Reproduced host-side with
# the real heirloom engine: after `pkgrm -R <root> APKG`, /var/apkg/admin
# and the whole /var/apkg directory were gone.
#
# Fix 1: there is no pkgrm in the upgrade path any more -- one pkgadd over
#        the installed instance, so no failure path can uninstall anything.
# Fix 2: the admin file is materialised before every engine call (below).
rm -f "$ROOT/var/apkg/admin.overwrite"
: > "$SHIMLOG"
OUT=$("$APKG" upgrade oldpkg 2>&1); rc=$?
if [ $rc -eq 0 ] && \
   grep -q "pkgadd -n -a $ROOT/var/apkg/admin.overwrite -d $CACHE/oldpkg-2.0.pkg OLDPKG" "$SHIMLOG"; then
    ok "upgrade argv is exactly: pkgadd -n -a <admin.overwrite> -d <file> <pkginst>"
else
    bad "upgrade pkgadd argv wrong (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
if ! grep -q '^pkgrm ' "$SHIMLOG"; then
    ok "upgrade never runs pkgrm (nothing is removed before its replacement)"
else
    bad "upgrade still runs pkgrm -- the brick path is back" "$(cat $SHIMLOG)"
fi
# the derived admin file: instance=overwrite, exactly once, and the
# operator's own keys carried across verbatim
AOW=$ROOT/var/apkg/admin.overwrite
NINST=$(grep -c '^instance=' "$AOW" 2>/dev/null || echo 0)
if [ -f "$AOW" ] && grep -q '^instance=overwrite$' "$AOW" && \
   [ "$NINST" = 1 ] && grep -q 'apkg-test-admin-marker' "$AOW" && \
   grep -q '^action=nocheck$' "$AOW"; then
    ok "admin.overwrite has one instance=overwrite and keeps the operator's keys"
else
    bad "derived admin file wrong" "$(cat "$AOW" 2>&1)"
fi

# A pkgadd that FAILS must leave the installed package alone -- and, with
# no pkgrm in the path, it now provably does: nothing ran but the pkgadd.
: > "$SHIMLOG"
rm -f "$CACHE/oldpkg-2.0.pkg"
OUT=$("$APKG" -c "$WORK/conf-fail" upgrade oldpkg 2>&1); rc=$?
if [ $rc -eq 4 ] && ! grep -q '^pkgrm ' "$SHIMLOG" && \
   echo "$OUT" | grep -q "is untouched"; then
    ok "a failed upgrade removes nothing and says the old package is untouched"
else
    bad "failed-upgrade behaviour wrong (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi

# THE ADMIN FILE IS MATERIALISED, NEVER ASSUMED.  This is the exact metal
# failure generalised: with /var/apkg/admin absent, the old client handed
# pkgadd a -a path that did not exist and pkgadd refused to run.
rm -f "$ROOT/var/apkg/admin" "$ROOT/var/apkg/admin.overwrite"
: > "$SHIMLOG"
rm -f "$CACHE/oldpkg-2.0.pkg"
OUT=$("$APKG" upgrade oldpkg 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -f "$ROOT/var/apkg/admin.overwrite" ] && \
   grep -q '^instance=overwrite$' "$ROOT/var/apkg/admin.overwrite" && \
   grep -q "pkgadd .* OLDPKG" "$SHIMLOG"; then
    ok "upgrade re-creates a MISSING admin file instead of failing on it"
else
    bad "missing-admin recovery broken (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
rm -f "$ROOT/var/apkg/admin"
: > "$SHIMLOG"
rm -f "$CACHE/foo-1.0.pkg"
OUT=$("$APKG" install foo 2>&1); rc=$?
if [ $rc -eq 0 ] && [ -f "$ROOT/var/apkg/admin" ] && \
   grep -q '^instance=quit$' "$ROOT/var/apkg/admin" && \
   grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $CACHE/foo-1.0.pkg FOO" "$SHIMLOG"; then
    ok "install re-creates a MISSING admin file (instance=quit) and uses it"
else
    bad "missing-admin recovery on install broken (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
mkadmin   # restore the marker-carrying fixture for the tests below

: > "$SHIMLOG"
OUT=$("$APKG" upgrade samepkg 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "up to date" && [ ! -s "$SHIMLOG" ]; then
    ok "upgrade equal version: says so, exit 0, nothing run"
else
    bad "upgrade equal-version behaviour wrong (rc=$rc)" "$OUT"
fi
: > "$SHIMLOG"
OUT=$("$APKG" upgrade unver 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "pkgadd .* UNVER" "$SHIMLOG"; then
    ok "upgrade treats VERSION-less installed package as older"
else
    bad "upgrade of VERSION-less package broken (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
run 1 "upgrade of not-installed package fails with exit 1" "$APKG" upgrade foo

# ------------------------------------------------ remove
: > "$SHIMLOG"
OUT=$("$APKG" remove samepkg 2>&1); rc=$?
if [ $rc -eq 0 ] && grep -q "pkgrm -n -a $ROOT/var/apkg/admin SAMEPKG" "$SHIMLOG"; then
    ok "remove maps name to pkginst and runs pkgrm"
else
    bad "remove broken (rc=$rc)" "$OUT $(cat $SHIMLOG)"
fi
run 1 "remove of not-installed package fails with exit 1" "$APKG" remove foo

# ------------------------------------------------ .Z transparency
: > "$SHIMLOG"
run 0 ".Z package is zcat-decompressed before pkgadd" "$APKG" install zpkg
if grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $CACHE/zpkg-1.0.pkg ZPKG" "$SHIMLOG" && \
   cmp -s "$CACHE/zpkg-1.0.pkg" "$WORK/zpkg-plain"; then
    ok "pkgadd got the decompressed datastream"
else
    bad ".Z handling wrong" "$(cat $SHIMLOG)"
fi

# ------------------------------------------------ subdirectory filenames
# catalog filename with a '/': URL keeps the relative path, cache file
# is the basename
: > "$SHIMLOG"
run 0 "install of subdir-filename package works" "$APKG" install net
if grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $CACHE/net-2.1.pkg NETPKG" "$SHIMLOG"; then
    ok "subdir package cached and passed to pkgadd by basename"
else
    bad "subdir cache/pkgadd path wrong" "$(cat $SHIMLOG)"
fi
cmp -s "$CACHE/net-2.1.pkg" "$P/stock/net-2.1.pkg" \
    && ok "subdir package bytes match repo copy" \
    || bad "subdir package bytes differ from repo copy"
OUT=$("$APKG" info net 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "Filename:    stock/net-2.1.pkg"; then
    ok "info shows the relative filename verbatim"
else
    bad "info filename field wrong (rc=$rc)" "$OUT"
fi

# rejection cases: a catalog whose filename field could escape pkgs/
# or the cache must be rejected whole (exit 3)
mkbadcat() {
    cat > "$CATFILE" <<EOF
#apkg-catalog 1
bad|1.0|BAD|$1|00000000000000000000000000000000|1|none|system|Bad filename fixture
EOF
}
mkbadcat "/etc/absolute.pkg"
run 3 "catalog filename with leading / rejected (exit 3)" "$APKG" list
mkbadcat "stock/../../evil.pkg"
run 3 "catalog filename with .. component rejected (exit 3)" "$APKG" list
mkbadcat "stock//net-2.1.pkg"
run 3 "catalog filename with // rejected (exit 3)" "$APKG" list
mkbadcat "stock/net-2.1.pkg/"
run 3 "catalog filename with trailing / rejected (exit 3)" "$APKG" list
mkbadcat "stock/.."
run 3 "catalog filename ending in .. component rejected (exit 3)" "$APKG" list
run 0 "catalog restored after rejection fixtures" "$APKG" update

# ------------------------------------------------ FILE source (mounted media)
# a mounted tree (e.g. /cdrom): file:// scheme, or a bare absolute /path.
mkconf "$WORK/conf-file"    "file://$WORK/repo" "$WORK/bin/pkgadd-shim"
mkconf "$WORK/conf-fileabs" "$WORK/repo"        "$WORK/bin/pkgadd-shim"
rm -f "$CATFILE"
run 0 "update from a file:// source copies the catalog" \
    "$APKG" -c "$WORK/conf-file" update
cmp -s "$CATFILE" "$WORK/repo/catalog" \
    && ok "file:// update stored the catalog" \
    || bad "file:// catalog content wrong"
run 0 "update from a bare absolute /path source (installer /cdrom)" \
    "$APKG" -c "$WORK/conf-fileabs" update
: > "$SHIMLOG"
run 0 "install foo from file:// source" "$APKG" -c "$WORK/conf-file" install foo
grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $WORK/repo/pkgs/foo-1.0.pkg FOO" "$SHIMLOG" \
    && ok "file:// plain .pkg handed to pkgadd IN PLACE (no cache copy)" \
    || bad "file:// in-place staging wrong" "$(cat $SHIMLOG)"
: > "$SHIMLOG"
run 0 "install .Z from file:// source decompresses to cache" \
    "$APKG" -c "$WORK/conf-file" install zpkg
if grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $CACHE/zpkg-1.0.pkg ZPKG" "$SHIMLOG" && \
   cmp -s "$CACHE/zpkg-1.0.pkg" "$WORK/zpkg-plain"; then
    ok "file:// .Z verified in place, decompressed to cache"
else
    bad "file:// .Z handling wrong" "$(cat $SHIMLOG)"
fi
# a pkgadd failure on the FILE arm propagates too (shared install loop)
mkconf "$WORK/conf-file-fail" "file://$WORK/repo" "$WORK/bin/pkgadd-fail"
: > "$SHIMLOG"
run 4 "file:// pkgadd failure propagates (exit 4)" \
    "$APKG" -c "$WORK/conf-file-fail" install foo

# ------------------------------------------------ RAW source (byte-offset slice)
# a self-describing raw slice: catalog at offset 0, catalog.md5 at 32768,
# packages at the offsets the catalog's 10th column records - built here
# to exactly the source.c layout constants.
python3 - "$WORK" "$P" <<'PY'
import hashlib, os, sys
work, P = sys.argv[1], sys.argv[2]
CAT_OFF, MD5_OFF, DATA_OFF = 0, 32768, 65536
def build(img_path, with_offset):
    data = open(os.path.join(P, "foo-1.0.pkg"), "rb").read()
    fields = ["foo", "1.0", "FOO", "stock/foo-1.0.pkg",
              hashlib.md5(data).hexdigest(), str(len(data)),
              "none", "system", "Foo via RAW"]
    if with_offset:
        fields.append(str(DATA_OFF))
    cat = ("#apkg-catalog 1\n" + "|".join(fields) + "\n").encode()
    md5 = (hashlib.md5(cat).hexdigest() + "  catalog\n").encode()
    end = DATA_OFF + ((len(data) + 511) // 512) * 512
    img = bytearray(end)
    img[CAT_OFF:CAT_OFF + len(cat)] = cat
    img[MD5_OFF:MD5_OFF + len(md5)] = md5
    img[DATA_OFF:DATA_OFF + len(data)] = data
    open(img_path, "wb").write(img)
build(os.path.join(work, "raw.img"), True)
build(os.path.join(work, "raw-noff.img"), False)
PY
mkconf "$WORK/conf-raw"     "raw:$WORK/raw.img"      "$WORK/bin/pkgadd-shim"
mkconf "$WORK/conf-rawnoff" "raw:$WORK/raw-noff.img" "$WORK/bin/pkgadd-shim"
rm -f "$CATFILE"
OUT=$("$APKG" -c "$WORK/conf-raw" update 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$OUT" | grep -q "catalog updated: 1 package"; then
    ok "update from raw: reads + parses the offset catalog at offset 0"
else
    bad "raw update wrong (rc=$rc)" "$OUT"
fi
: > "$SHIMLOG"
run 0 "install from raw: dd's the package by its catalog offset" \
    "$APKG" -c "$WORK/conf-raw" install foo
grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $CACHE/foo-1.0.pkg FOO" "$SHIMLOG" \
    && ok "raw package extracted to cache and pkgadd'd by basename" \
    || bad "raw staging wrong" "$(cat $SHIMLOG)"
cmp -s "$CACHE/foo-1.0.pkg" "$P/foo-1.0.pkg" \
    && ok "raw-extracted bytes match the original package" \
    || bad "raw-extracted bytes differ from original"
# a pkgadd failure on the RAW arm propagates too (the metal path was RAW)
mkconf "$WORK/conf-raw-fail" "raw:$WORK/raw.img" "$WORK/bin/pkgadd-fail"
"$APKG" -c "$WORK/conf-raw-fail" update >/dev/null 2>&1
: > "$SHIMLOG"
rm -f "$CACHE/foo-1.0.pkg"
run 4 "raw: pkgadd failure propagates (exit 4)" \
    "$APKG" -c "$WORK/conf-raw-fail" install foo
rm -f "$CATFILE"
run 0 "update from a raw: source whose catalog has no offset column" \
    "$APKG" -c "$WORK/conf-rawnoff" update
run 3 "raw install refuses an entry with no offset (fail closed, exit 3)" \
    "$APKG" -c "$WORK/conf-rawnoff" install foo

# multi-chunk raw_extract: the foo package above is tiny (ONE read), so it
# never exercises the read loop's iteration or its over-read-to-512 tail
# discard.  This fixture is > 3x the 65536 read buffer with a size that is
# deliberately NOT a 512 multiple, and the image is padded PAST the package
# with a 0xAA sentinel so the final read returns a full over-read the loop
# must discard down to the exact size.  verify_file (md5) + cmp (exact bytes,
# exact length) together catch a mis-sized write, a dropped tail, or spill.
python3 - "$WORK" <<'PY'
import hashlib, os, sys
work = sys.argv[1]
CAT_OFF, MD5_OFF, DATA_OFF = 0, 32768, 65536
n = 200000                                    # 3*65536 + 3392 (tail not /512)
data = bytes((i * 2654435761) & 0xff for i in range(n))
open(os.path.join(work, "big-1.0.pkg"), "wb").write(data)
fields = ["big", "1.0", "BIG", "big-1.0.pkg",
          hashlib.md5(data).hexdigest(), str(n),
          "none", "system", "Big multi-chunk package", str(DATA_OFF)]
cat = ("#apkg-catalog 1\n" + "|".join(fields) + "\n").encode()
md5 = (hashlib.md5(cat).hexdigest() + "  catalog\n").encode()
end = DATA_OFF + n + 4096
img = bytearray(end)                           # NUL: catalog/md5 stay NUL-padded
img[CAT_OFF:CAT_OFF + len(cat)] = cat
img[MD5_OFF:MD5_OFF + len(md5)] = md5
img[DATA_OFF:DATA_OFF + n] = data
# 0xAA sentinel ONLY in the over-read zone right after the package, so a
# tail that is wrongly written spills a detectable byte (cmp catches it)
img[DATA_OFF + n:end] = b"\xaa" * (end - (DATA_OFF + n))
open(os.path.join(work, "raw-big.img"), "wb").write(img)
PY
mkconf "$WORK/conf-rawbig" "raw:$WORK/raw-big.img" "$WORK/bin/pkgadd-shim"
rm -f "$CATFILE"
run 0 "update from raw: big multi-chunk offset catalog" \
    "$APKG" -c "$WORK/conf-rawbig" update
: > "$SHIMLOG"
run 0 "install from raw: multi-chunk package staged + md5-verified" \
    "$APKG" -c "$WORK/conf-rawbig" install big
cmp -s "$CACHE/big-1.0.pkg" "$WORK/big-1.0.pkg" \
    && ok "multi-chunk raw_extract: staged bytes exact (loop + tail discard)" \
    || bad "multi-chunk raw staging corrupt or wrong length"

# ------------------------------------------------ unclassifiable source
mkconf "$WORK/conf-badsrc" "ftp://nope/x" "$WORK/bin/pkgadd-shim"
run 1 "an unclassifiable source (ftp://) is a hard error (exit 1)" \
    "$APKG" -c "$WORK/conf-badsrc" update

# ------------------------------------------------ -R target root (pkgadd -R)
# -R adds "-R <root>" to the engine argv but does NOT move the engine,
# admin, config or cache (the compiled-in defaults still answer to
# APKG_ROOT only); the two are independent and composable.
"$APKG" -c "$CONF" update >/dev/null 2>&1   # restore the full catalog
TGT=$WORK/target
mkdir -p "$TGT/var/sadm/pkg"
: > "$SHIMLOG"
run 0 "install -R passes -R <root> to pkgadd" \
    "$APKG" -c "$CONF" -R "$TGT" install foo
grep -q "pkgadd -R $TGT -n -a $ROOT/var/apkg/admin -d $CACHE/foo-1.0.pkg FOO" "$SHIMLOG" \
    && ok "pkgadd argv grows -R <target>; engine + admin unmoved" \
    || bad "-R argv wrong" "$(cat $SHIMLOG)"
: > "$SHIMLOG"
run 0 "install without -R stays byte-identical (no -R in argv)" \
    "$APKG" -c "$CONF" -f install foo
grep -q "pkgadd -n -a $ROOT/var/apkg/admin -d $CACHE/foo-1.0.pkg FOO" "$SHIMLOG" \
    && ok "no -R: argv is exactly the pre-Wave-3 form" \
    || bad "non-R argv drifted" "$(cat $SHIMLOG)"

# ------------------------------------------------ verbose install smoke
OUT=$("$APKG" -c "$CONF" -v -f install samepkg 2>&1); rc=$?
[ $rc -eq 0 ] && ok "verbose forced reinstall works (rc 0)" \
    || bad "verbose reinstall broken (rc=$rc)" "$OUT"

# ------------------------------------ catalog installed-size block (--isize)
# gen-catalog.py --isize appends an extension block of catalog v1 COMMENT
# lines after the entries:
#     #ext isize 1
#     #isize <name> <bytes>
# The block exists because this parser's field grammar is full (9 fields, or
# 10 with the RAW offset, and NOTHING else -- see catalog.c NFIELDS_MIN/MAX),
# so an extra column would brick every already-deployed apkg on every box.
# This test is the proof that the chosen encoding is inert HERE: the same
# catalog, plus the block, must parse identically -- same package count, and
# byte-for-byte the same `list` output.
ISREPO=$WORK/isizerepo
mkdir -p "$ISREPO"
cp "$WORK/repo/catalog" "$ISREPO/catalog"
{
    echo "#ext isize 1"
    grep -v '^#' "$WORK/repo/catalog" | cut -d'|' -f1 | \
    while read n; do echo "#isize $n 123456"; done
} >> "$ISREPO/catalog"
md5sum "$ISREPO/catalog" > "$ISREPO/catalog.md5"
mkdir -p "$ISREPO/pkgs"
cp -r "$WORK/repo/pkgs/." "$ISREPO/pkgs/"
mkconf "$WORK/conf-isize" "file://$ISREPO" "$WORK/bin/pkgadd-shim"

OUT=$("$APKG" list 2>&1)            # baseline: catalog without the block
echo "$OUT" > "$WORK/list.noisize"
run 0 "update accepts a catalog carrying the #isize block" \
    "$APKG" -c "$WORK/conf-isize" update
echo "$OUT" | grep -q "catalog updated: 15 packages" \
    && ok "the block is not counted as a package (still 15)" \
    || bad "isize block perturbed the package count" "$OUT"
OUT=$("$APKG" -c "$WORK/conf-isize" list 2>&1); rc=$?
echo "$OUT" > "$WORK/list.isize"
[ $rc -eq 0 ] && ok "list works against a catalog with the block" \
    || bad "list failed on a catalog with the block (rc=$rc)" "$OUT"
cmp -s "$WORK/list.noisize" "$WORK/list.isize" \
    && ok "list output byte-identical with and without the block" \
    || bad "the isize block changed apkg's view of the catalog" \
           "$(diff "$WORK/list.noisize" "$WORK/list.isize")"
run 0 "install still resolves through a block-carrying catalog" \
    "$APKG" -c "$WORK/conf-isize" -n install baz
# and an unknown future extension block is equally inert (forward compat)
printf '#ext somethingnew 7\n#somethingnew foo whatever\n' >> "$ISREPO/catalog"
md5sum "$ISREPO/catalog" > "$ISREPO/catalog.md5"
run 0 "an UNKNOWN extension block is ignored too (forward compatible)" \
    "$APKG" -c "$WORK/conf-isize" update

# restore the plain catalog for anything downstream
"$APKG" update >/dev/null 2>&1

# ======================================= the fetch path: every knob, from apkg.conf
#
# 2026-09-16, real A4000D: `apkg install Xcore` died with "timeout after
# 60 s" on an 8.2 MB package over Z3660 ethernet while 118 KB and 2.2 MB
# packages fetched fine.  That path runs ~37 KB/s, so the package needs
# ~220 s of continuous, perfectly healthy transfer -- the 60 s WHOLE-
# transfer cap was the defect, not the link.  The fix makes the timer
# measure SILENCE, and makes every other constant on the fetch path a
# config key too (user, 2026-09-16: "all relevant things need to be
# configurable").  Three things therefore need testing: the keys parse,
# the defaults are what we say they are, and the inactivity semantics
# are real -- the last of which a merely-passing fetch cannot prove,
# hence the trickling server.

# --- the compiled-in DEFAULT repo ---
#
# A box whose /etc/apkg.conf names no repo= talks to DEF_REPO (conf.c) and
# nothing else, so that one string decides whether a fresh install reaches a
# live repository or a dead host.  It has been wrong once already: until
# 2026-09-14 (dcece20) it named the retired LAN-only NAS, and nothing in the
# suite would have noticed -- every other test supplies its own repo= pointing
# at the fixture server, which is exactly why the default was invisible here.
#
# The assertion is behavioural, not a grep of conf.c: it reads the repo the
# BINARY resolved off the -v config line.  No packet leaves the machine --
# `list` reads the cached catalog and the repo URL is only ever used by fetch.
CANON_REPO=http://pkg.amigaux.org
cat > "$WORK/conf-norepo" <<EOF
cachedir=$ROOT/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
EOF
OUT=$("$APKG" -v -c "$WORK/conf-norepo" list 2>&1)
echo "$OUT" | grep -qF "config: repo=$CANON_REPO cachedir=" \
    && ok "a config naming no repo gets the canonical repository as its default" \
    || bad "the compiled-in default repo is not $CANON_REPO" "$OUT"
DEFREPO=$(echo "$OUT" | sed -n 's/^.*config: repo=\([^ ]*\) cachedir=.*$/\1/p' | head -1)

# --- the defaults, on one grep-able -v line ---
cat > "$WORK/conf-nofetch" <<EOF
repo=http://127.0.0.1:$PORT/repo
cachedir=$ROOT/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
EOF
DEFLINE="timeout=300s connect_timeout=30s retries=2 retry_delay=5s progress=262144 bufsize=8192 redirects=1 rcvbuf=0 sndbuf=0"
OUT=$("$APKG" -v -c "$WORK/conf-nofetch" list 2>&1)
echo "$OUT" | grep -q "fetch: $DEFLINE" \
    && ok "a config naming no fetch key gets every documented default" \
    || bad "the built-in fetch defaults are not what apkg.1 documents" "$OUT"

# --- drift guard: the /etc/apkg.conf template SHIPPED in the APKG package
#     (minted by tools/repo/build-packages.sh) must name every fetch key
#     and must agree with the binary about what each one defaults to.  A
#     template that quietly disagrees would hand every fresh install a
#     different fetch path from the documented one. ---
TMPL=$WORK/shipped-apkg.conf
sed -n '/apkg.conf" <<EOF/,/^EOF$/p' \
    "$SRC/../../tools/repo/build-packages.sh" | sed '1d;$d' > "$TMPL"
if [ -s "$TMPL" ]; then
    # The template's repo= is what a fresh install actually reads; DEF_REPO is
    # the fallback under it.  Both must name the canonical host, and they must
    # name the SAME one -- a template that drifts from the binary hands the two
    # halves of one box two different repositories.
    TMPLREPO=$(sed -n 's/^repo=//p' "$TMPL" | head -1)
    [ "$TMPLREPO" = "$CANON_REPO" ] \
        && ok "the shipped apkg.conf template names the canonical repository" \
        || bad "shipped apkg.conf template repo=$TMPLREPO, wanted $CANON_REPO"
    [ -n "$DEFREPO" ] && [ "$TMPLREPO" = "$DEFREPO" ] \
        && ok "the shipped template's repo is the binary's own default" \
        || bad "template repo=$TMPLREPO but the binary defaults to ${DEFREPO:-<unread>}"
    MISSING=
    for k in timeout connect_timeout retries retry_delay progress \
             bufsize redirects rcvbuf sndbuf; do
        grep -q "^$k=" "$TMPL" || MISSING="$MISSING $k"
    done
    [ -z "$MISSING" ] \
        && ok "the shipped apkg.conf template names every fetch key" \
        || bad "shipped apkg.conf template is missing:$MISSING"
    OUT=$("$APKG" -v -c "$TMPL" list 2>&1)
    echo "$OUT" | grep -q "fetch: $DEFLINE" \
        && ok "the shipped template's values are the binary's own defaults" \
        || bad "shipped apkg.conf template has drifted from the defaults" "$OUT"
    # The template lives inside an UNQUOTED bash heredoc, so a backtick or
    # a '$' in it is command/variable substitution AT MINT TIME -- it runs
    # the text and silently swallows the result into the shipped file.
    # This actually happened once while writing the fetch-key comments.
    if grep -q '[`$]' "$TMPL"; then
        bad "shipped template contains a backtick or \$ (heredoc expands it at mint time)" \
            "$(grep -n '[`$]' "$TMPL")"
    else
        ok "shipped template is free of heredoc-expanding characters"
    fi
else
    bad "could not extract the apkg.conf template from build-packages.sh"
fi

# --- each key overrides, and each is reported back ---
setfetch() {
    cat > "$WORK/conf-fetch" <<EOF
repo=http://127.0.0.1:$PORT/repo
cachedir=$ROOT/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
$1
EOF
    "$APKG" -v -c "$WORK/conf-fetch" list 2>&1
}
for pair in "timeout=7:timeout=7s" \
            "connect_timeout=3:connect_timeout=3s" \
            "retries=5:retries=5" \
            "retry_delay=0:retry_delay=0s" \
            "progress=0:progress=0" \
            "bufsize=4096:bufsize=4096" \
            "redirects=0:redirects=0" \
            "rcvbuf=32768:rcvbuf=32768" \
            "rcvbuf=4096:rcvbuf=4096" \
            "sndbuf=8192:sndbuf=8192"; do
    line=${pair%%:*}
    want=${pair#*:}
    OUT=$(setfetch "$line")
    echo "$OUT" | grep -q "fetch: .*$want" \
        && ok "apkg.conf '$line' is honoured" \
        || bad "apkg.conf '$line' was not honoured" "$OUT"
done

# --- a nonsense value is REFUSED and the default kept (never silently 0) ---
for pair in "timeout=abc:timeout=300s" \
            "timeout=0:timeout=300s" \
            "timeout=-5:timeout=300s" \
            "connect_timeout=x:connect_timeout=30s" \
            "retries=abc:retries=2" \
            "retries=-1:retries=2" \
            "retry_delay=zz:retry_delay=5s" \
            "progress=-9:progress=262144" \
            "bufsize=0:bufsize=8192" \
            "redirects=nope:redirects=1" \
            "rcvbuf=huge:rcvbuf=0" \
            "rcvbuf=-1:rcvbuf=0" \
            "sndbuf=99999999:sndbuf=0"; do
    line=${pair%%:*}
    want=${pair#*:}
    key=${line%%=*}
    bogus=${line#*=}
    OUT=$(setfetch "$line")
    if echo "$OUT" | grep -q "bad $key '$bogus'" &&
       echo "$OUT" | grep -q "fetch: .*$want"; then
        ok "apkg.conf '$line' is refused and the default kept"
    else
        bad "apkg.conf '$line' was not refused cleanly" "$OUT"
    fi
done

# --- bufsize is clamped, loudly, rather than trusted ---
OUT=$(setfetch "bufsize=16")
if echo "$OUT" | grep -q "bufsize 16 clamped to 512" &&
   echo "$OUT" | grep -q "fetch: .*bufsize=512"; then
    ok "an absurdly small bufsize is clamped to 512 and says so"
else
    bad "bufsize=16 was not clamped" "$OUT"
fi
OUT=$(setfetch "bufsize=99999999")
if echo "$OUT" | grep -q "clamped to 262144" &&
   echo "$OUT" | grep -q "fetch: .*bufsize=262144"; then
    ok "an absurdly large bufsize is clamped to 262144 and says so"
else
    bad "bufsize=99999999 was not clamped" "$OUT"
fi

# --- an unknown key still warns (the vocabulary stays closed) ---
OUT=$(setfetch "tiemout=9")
echo "$OUT" | grep -q "unknown key 'tiemout'" \
    && ok "a misspelled fetch key is reported, not silently ignored" \
    || bad "unknown key not reported" "$OUT"

# --- rcvbuf reaches the SOCKET LAYER: apkg asks, then reads back with
#     getsockopt and reports both.  Note the wording the test pins: on
#     the stock Amix stack sockmod may answer from its own cached value
#     while the tcp module keeps its 4096 hiwat, so this proves the
#     request is issued and reported -- NOT that TCP honoured it.  Only
#     a wire capture settles that, and it is still pending. ---
mkconf "$WORK/conf-rcv" "http://127.0.0.1:$PORT/repo" "$WORK/bin/pkgadd-shim"
echo "rcvbuf=65536" >> "$WORK/conf-rcv"
echo "sndbuf=32768" >> "$WORK/conf-rcv"
OUT=$("$APKG" -v -c "$WORK/conf-rcv" update 2>&1)
echo "$OUT" | grep -qE "SO_RCVBUF: asked 65536, socket layer reports [1-9][0-9]*" \
    && ok "SO_RCVBUF is requested before connect and the readback reported" \
    || bad "SO_RCVBUF was not requested/reported" "$OUT"
echo "$OUT" | grep -q "not proof TCP honoured it" \
    && ok "the readback is labelled as not proof TCP honoured it" \
    || bad "the readback overclaims what it proves" "$OUT"
echo "$OUT" | grep -qE "SO_SNDBUF: asked 32768, socket layer reports [1-9][0-9]*" \
    && ok "SO_SNDBUF is requested before connect and the readback reported" \
    || bad "SO_SNDBUF was not requested/reported" "$OUT"
# rcvbuf=0 must leave the stack alone but still report its default, so
# an operator can see what raising it would be raising FROM
mkconf "$WORK/conf-rcv0" "http://127.0.0.1:$PORT/repo" "$WORK/bin/pkgadd-shim"
echo "rcvbuf=0" >> "$WORK/conf-rcv0"
OUT=$("$APKG" -v -c "$WORK/conf-rcv0" update 2>&1)
echo "$OUT" | grep -qE "SO_RCVBUF: asked 0, socket layer reports [1-9][0-9]*" \
    && ok "rcvbuf=0 leaves the default alone and still reports it" \
    || bad "rcvbuf=0 did not report the stack default" "$OUT"

# --- rcvbuf's SECOND mechanism: the STREAMS INITQPARMS ioctl ----------
#
# The wire capture of 2026-09-14 settled that SO_RCVBUF alone never
# reaches the stock Amix tcp module (the box advertised win 4096 after
# asking for 64 KB), so rcvbuf ALSO drives INITQPARMS (IQP_RQ|IQP_HIWAT)
# on the tcp module.  The round-2 capture of 2026-09-15 then settled
# that raising the window makes this driver SLOWER (RX loss past ~8
# segments in flight), so the DEFAULT IS 0 and the ioctl is an explicit
# operator knob.  The tests below therefore split in two: "off unless
# asked" is the contract that protects every ordinary run, and the
# argument/ordering checks cover the knob when it IS asked for.
#
# The HOST BUILD CANNOT ISSUE THE IOCTL -- there is no STREAMS here,
# and the suite does not run as root -- so what these prove is exactly:
# the path is compiled in, it is off by default, it is reached at the
# right two moments when enabled, it is given the right arguments, and
# it NEVER fails silently.  The behaviour on the wire is a box result,
# and it is already in; see NOTES.md.

OUT=$("$APKG" -v -c "$WORK/conf-rcv" update 2>&1)

# both attempts happen, and each names the queue+parameter it asks for
echo "$OUT" | grep -q "INITQPARMS(template): IQP_RQ|IQP_HIWAT <- 65535" \
    && ok "INITQPARMS is attempted on the module template, with IQP_RQ|IQP_HIWAT" \
    || bad "no INITQPARMS template attempt" "$OUT"
echo "$OUT" | grep -q "INITQPARMS(stream): IQP_RQ|IQP_HIWAT <- 65535" \
    && ok "INITQPARMS is also attempted on the fetch stream (belt)" \
    || bad "no INITQPARMS stream attempt" "$OUT"

# ORDERING IS THE LOAD-BEARING PART: initqparms() rewrites the tcp
# module's module_info template, and STREAMS copies that template into
# q_hiwat when a stream is OPENED -- so the template attempt must come
# before the fetch socket exists.  SO_RCVBUF is set on that socket, so
# its first line is a proxy for "the socket now exists".
T_LINE=$(echo "$OUT" | grep -n "INITQPARMS(template)" | head -1 | cut -d: -f1)
S_LINE=$(echo "$OUT" | grep -n "SO_RCVBUF: asked" | head -1 | cut -d: -f1)
if [ -n "$T_LINE" ] && [ -n "$S_LINE" ] && [ "$T_LINE" -lt "$S_LINE" ]; then
    ok "the template INITQPARMS precedes the fetch socket (open-time semantics)"
else
    bad "INITQPARMS template attempt did not precede the fetch socket" "$OUT"
fi

# it is issued once per process, not once per fetch: 'update' fetches
# one URL, but the template line must never appear twice in a run
N=$(echo "$OUT" | grep -c "INITQPARMS(template)")
[ "$N" = 1 ] \
    && ok "the template INITQPARMS is issued once per process" \
    || bad "template INITQPARMS appeared $N times, expected 1" "$OUT"

# never silent: when it is not attempted (no STREAMS on the host, or
# not root) the -v line says WHICH gate stopped it.  A build that
# quietly skipped the ioctl would look identical to one that worked.
echo "$OUT" | grep -qE "INITQPARMS\(template\): .* (accepted by the tcp module|refused \(.+\)|not attempted \(.+\))" \
    && ok "the INITQPARMS outcome is always stated (accepted/refused/why not)" \
    || bad "INITQPARMS outcome was not stated" "$OUT"

# 65535 is not a style choice: iqp_value is an unsigned short.  The
# conf above asks for 65536, so the clamp must fire, and say so once.
echo "$OUT" | grep -q "INITQPARMS: rcvbuf 65536 clamped to 65535 (iqp_value is 16-bit)" \
    && ok "rcvbuf above 65535 is clamped for the ioctl, and says so" \
    || bad "the 16-bit iqp_value clamp did not fire" "$OUT"
N=$(echo "$OUT" | grep -c "clamped to 65535")
[ "$N" = 1 ] \
    && ok "the clamp is reported once, not once per attempt" \
    || bad "clamp reported $N times, expected 1" "$OUT"

# rcvbuf=0 means "leave the stack alone" -- and that has to include the
# ioctl, which is box-wide, outlives the process and cannot be undone
# by apkg.  No INITQPARMS at all.
OUT=$("$APKG" -v -c "$WORK/conf-rcv0" update 2>&1)
echo "$OUT" | grep -q "INITQPARMS" \
    && bad "rcvbuf=0 still issued INITQPARMS (it is box-wide, until reboot)" "$OUT" \
    || ok "rcvbuf=0 issues no INITQPARMS at all"

# --- OFF BY DEFAULT.  This is the load-bearing one.  The round-2 metal
#     capture showed a raised window is SLOWER on z3660eth (4096 ~54
#     KB/s, 8192 ~32, 16384 ~36-40; RX loss past ~8 segments in
#     flight), and the ioctl changes the whole box until reboot.  A
#     config that names no rcvbuf must therefore touch nothing. ---
mkconf "$WORK/conf-iqp" "http://127.0.0.1:$PORT/repo" "$WORK/bin/pkgadd-shim"
OUT=$("$APKG" -v -c "$WORK/conf-iqp" update 2>&1)
echo "$OUT" | grep -q "INITQPARMS" \
    && bad "a config naming no rcvbuf still touched the box-wide tcp window" "$OUT" \
    || ok "the default (rcvbuf=0) issues no INITQPARMS -- the window is left alone"
echo "$OUT" | grep -q "SO_RCVBUF: asked 0" \
    && ok "the default asks the socket layer for nothing either" \
    || bad "the default did not leave SO_RCVBUF alone" "$OUT"

# an explicitly configured window IS honoured, unclamped, and is what
# the ioctl asks for -- the knob still works when an operator wants it
mkconf "$WORK/conf-iqp16" "http://127.0.0.1:$PORT/repo" "$WORK/bin/pkgadd-shim"
echo "rcvbuf=16384" >> "$WORK/conf-iqp16"
OUT=$("$APKG" -v -c "$WORK/conf-iqp16" update 2>&1)
echo "$OUT" | grep -q "INITQPARMS(template): IQP_RQ|IQP_HIWAT <- 16384" \
    && ok "an explicit rcvbuf=16384 is what INITQPARMS asks for" \
    || bad "INITQPARMS did not use the configured rcvbuf" "$OUT"
echo "$OUT" | grep -q "clamped" \
    && bad "rcvbuf=16384 was clamped; it is well under the 16-bit cap" "$OUT" \
    || ok "a 16384 window needs no clamping"

# --- drift guard on the restated <net/strioc.h> constants.  They are
#     retyped in http.c rather than included (the header is proprietary
#     and not in this repo), so a typo here would produce an ioctl the
#     tcp module silently ignores -- the worst possible failure mode.
#     Build with -DAPKG_CHECK_STRIOC against a real Amix sysroot to have
#     the compiler check them; this grep is the host-side backstop. ---
for pair in "APKG_IQP_RQ       0x00" \
            "APKG_IQP_HIWAT    0x20" \
            "APKG_INITQPARMS   (('Q' << 8) | 0x01)" \
            "APKG_IQP_MAX      65535L"; do
    grep -qF "#define $pair" "$SRC/http.c" \
        && ok "http.c restates $(echo "$pair" | awk '{print $1}') as <net/strioc.h> has it" \
        || bad "http.c's $(echo "$pair" | awk '{print $1}') has drifted from <net/strioc.h>"
done

# --- the box-wide change must be announced at WARNING level, not only
#     under -v.  The host build can never reach that branch (the ioctl
#     cannot succeed here), so this is a source guard: if someone
#     demotes it to note(), an operator could silently leave a box with
#     a changed tcp window and no way to know.  It must also name the
#     way back, because apkg cannot undo it. ---
if grep -q 'warnx2("tcp receive window set to %ld box-wide until reboot' "$SRC/http.c"; then
    ok "a successful INITQPARMS warns at warning level, not merely under -v"
else
    bad "the box-wide INITQPARMS warning is missing or demoted below warnx2"
fi
grep -q 'restore with "$' "$SRC/http.c" && grep -q 'rcvbuf=4096 as root, or reboot' "$SRC/http.c" \
    && ok "the warning names how to put the window back (apkg cannot)" \
    || bad "the box-wide warning does not name the revert path"
grep -q 'a window above 4096 is SLOWER' "$SRC/http.c" \
    && ok "the warning states the measured slowdown, so nobody reads it as a speed fix" \
    || bad "the warning does not carry the measured slowdown"
#
# Source guards, and deliberately not `strings "$APKG"`: in a build
# without STREAMS tcp_hiwat() can only return 0, so gcc proves the
# rc > 0 branch unreachable and deletes it -- literals and all.  A
# binary grep here would fail on a perfectly correct host build, which
# is a broken detector, not a finding.  The compiled-in check that DOES
# mean something is the cross build (-DAPKG_CHECK_STRIOC), which is not
# runnable from this suite.

# --- bufsize actually reaches the socket loop: a 512-byte buffer must
#     still fetch byte-exact (many more recv() rounds, same bytes) ---
mkconf "$WORK/conf-buf" "http://127.0.0.1:$PORT/repo" "$WORK/bin/pkgadd-shim"
echo "bufsize=512" >> "$WORK/conf-buf"
rm -f "$CACHE/foo-1.0.pkg"
run 0 "install with bufsize=512 (tiny reads) still works" \
    "$APKG" -c "$WORK/conf-buf" -f install foo
cmp -s "$CACHE/foo-1.0.pkg" "$WORK/repo/pkgs/foo-1.0.pkg" \
    && ok "a 512-byte read buffer delivers byte-exact bytes" \
    || bad "bufsize=512 corrupted the transfer"

# --- redirects=0 must refuse the hop the default follows ---
mkconf "$WORK/conf-noredir" "http://127.0.0.1:$RPORT/r" "$WORK/bin/pkgadd-shim"
echo "redirects=0" >> "$WORK/conf-noredir"
run 0 "baseline: redirects=1 (default) follows the hop" \
    "$APKG" -c "$WORK/conf-redirect" update
run 2 "redirects=0 refuses to follow the hop" \
    "$APKG" -c "$WORK/conf-noredir" update

# --- retries: a dead port must be re-attempted exactly as configured ---
cat > "$WORK/conf-retry" <<EOF
repo=http://127.0.0.1:$DEADPORT/repo
cachedir=$ROOT/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
timeout=5
connect_timeout=3
retries=2
retry_delay=0
EOF
OUT=$("$APKG" -c "$WORK/conf-retry" update 2>&1); rc=$?
NRETRY=$(echo "$OUT" | grep -c "^apkg: retrying ")
[ $rc -eq 2 ] && ok "a dead repo still fails with exit 2 after its retries" \
    || bad "dead repo did not fail with exit 2 (rc=$rc)" "$OUT"
[ "$NRETRY" -eq 2 ] \
    && ok "retries=2 produced exactly 2 retry attempts" \
    || bad "retries=2 produced $NRETRY retry lines" "$OUT"
echo "$OUT" | grep -q "attempt 2 of 3" \
    && ok "the retry line counts attempts against the configured total" \
    || bad "retry line does not report attempt N of M" "$OUT"
sed 's/^retries=2$/retries=0/' "$WORK/conf-retry" > "$WORK/conf-noretry"
OUT=$("$APKG" -c "$WORK/conf-noretry" update 2>&1)
echo "$OUT" | grep -q "^apkg: retrying " \
    && bad "retries=0 still retried" "$OUT" \
    || ok "retries=0 makes exactly one attempt"

# --- a non-200 is an ANSWER, not a network failure: never retried ---
cat > "$WORK/conf-404" <<EOF
repo=http://127.0.0.1:$PORT/nosuchrepo
cachedir=$ROOT/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
retries=3
retry_delay=0
EOF
OUT=$("$APKG" -c "$WORK/conf-404" update 2>&1)
echo "$OUT" | grep -q "^apkg: retrying " \
    && bad "a 404 was retried (it is an answer, not a failure)" "$OUT" \
    || ok "a 404 is not retried however high retries= is set"

# --- the fixture repo the slow server hands out ---
SLOWREPO=$WORK/slowrepo
mkdir -p "$SLOWREPO/pkgs"
# 586 KB: ten 64 KB writes from the server => nine 0.5 s gaps => ~4.5 s on
# the wire, comfortably MORE than the 2 s timeout configured below in total
# and comfortably LESS than it per gap.  It is also >2x the default
# progress interval, so the progress output has something to say.
dd if=/dev/urandom of="$SLOWREPO/pkgs/slow-1.0.pkg" bs=1024 count=586 2>/dev/null
dd if=/dev/urandom of="$SLOWREPO/pkgs/stall-1.0.pkg" bs=1024 count=64 2>/dev/null
cat > "$SLOWREPO/catalog" <<EOF
#apkg-catalog 1
slow|1.0|SLOWPKG|slow-1.0.pkg|$(md5of $SLOWREPO/pkgs/slow-1.0.pkg)|$(sizeof $SLOWREPO/pkgs/slow-1.0.pkg)|none|system|Package the server trickles out
stall|1.0|STALLPKG|stall-1.0.pkg|$(md5of $SLOWREPO/pkgs/stall-1.0.pkg)|$(sizeof $SLOWREPO/pkgs/stall-1.0.pkg)|none|system|Package the server abandons mid-body
EOF
md5sum "$SLOWREPO/catalog" > "$SLOWREPO/catalog.md5"

mkconf "$WORK/conf-slow"  "http://127.0.0.1:$SPORT/trickle/slowrepo" \
       "$WORK/bin/pkgadd-shim" 2
mkconf "$WORK/conf-stall" "http://127.0.0.1:$SPORT/stall/slowrepo" \
       "$WORK/bin/pkgadd-shim" 2

run 0 "update against the trickling server" "$APKG" -c "$WORK/conf-slow" update

# --- THE regression test: a slow but FLOWING transfer must survive a
#     timeout far shorter than the transfer itself.  This is the A4000D
#     failure; it fails against a whole-transfer cap and passes against
#     an inactivity timer. ---
rm -f "$CACHE/slow-1.0.pkg"
T0=$(date +%s)
OUT=$("$APKG" -c "$WORK/conf-slow" install slow 2>&1); rc=$?
T1=$(date +%s)
ELAPSED=$((T1 - T0))
if [ $rc -eq 0 ]; then
    ok "a slow but flowing 586 KB fetch completes under timeout=2"
else
    bad "trickled fetch failed (rc=$rc) - timeout is still a whole-transfer cap" "$OUT"
fi
if [ "$ELAPSED" -gt 2 ]; then
    ok "...and it really did outlive the 2 s timeout (${ELAPSED}s on the wire)"
else
    bad "the transfer took only ${ELAPSED}s - too fast to prove inactivity semantics" "$OUT"
fi
cmp -s "$CACHE/slow-1.0.pkg" "$SLOWREPO/pkgs/slow-1.0.pkg" \
    && ok "the trickled package arrived byte-exact" \
    || bad "trickled package differs from the origin"

# --- progress output: visible without -v, finer with it, off when asked ---
NPROG=$(echo "$OUT" | grep -c '^apkg: \.\.\. [0-9/]* bytes$')
[ "$NPROG" -eq 2 ] \
    && ok "progress prints at the 256 KB default step (2 lines for 586 KB)" \
    || bad "expected 2 progress lines for 586 KB, got $NPROG" "$OUT"
rm -f "$CACHE/slow-1.0.pkg"
OUT=$("$APKG" -v -c "$WORK/conf-slow" install slow 2>&1)
NPROGV=$(echo "$OUT" | grep -c '^apkg: \.\.\. [0-9/]* bytes$')
[ "$NPROGV" -gt "$NPROG" ] \
    && ok "-v quarters the progress interval ($NPROGV lines vs $NPROG)" \
    || bad "-v did not tighten the progress interval ($NPROGV vs $NPROG)" "$OUT"
cp "$WORK/conf-slow" "$WORK/conf-slowquiet"
echo "progress=0" >> "$WORK/conf-slowquiet"
rm -f "$CACHE/slow-1.0.pkg"
OUT=$("$APKG" -c "$WORK/conf-slowquiet" install slow 2>&1)
echo "$OUT" | grep -q '^apkg: \.\.\. [0-9/]* bytes$' \
    && bad "progress=0 still printed progress" "$OUT" \
    || ok "progress=0 silences the progress lines"

# --- a connection that goes SILENT must still be killed, promptly ---
rm -f "$CACHE/stall-1.0.pkg" "$CACHE/stall-1.0.pkg.part"
T0=$(date +%s)
OUT=$("$APKG" -c "$WORK/conf-stall" install stall 2>&1); rc=$?
T1=$(date +%s)
ELAPSED=$((T1 - T0))
[ $rc -eq 2 ] \
    && ok "a silent connection still fails, with exit 2" \
    || bad "stalled fetch did not fail with exit 2 (rc=$rc)" "$OUT"
[ "$ELAPSED" -lt 30 ] \
    && ok "the inactivity timeout fired promptly (${ELAPSED}s; server silent for 120)" \
    || bad "stalled fetch took ${ELAPSED}s - the timer did not fire" "$OUT"
echo "$OUT" | grep -q "no data for 2 s" \
    && ok "the timeout message names the inactivity window, not a duration" \
    || bad "timeout message does not report an inactivity window" "$OUT"
echo "$OUT" | grep -q "(256 bytes received)" \
    && ok "the timeout message reports the bytes that did arrive" \
    || bad "timeout message does not report bytes received" "$OUT"
[ -f "$CACHE/stall-1.0.pkg.part" ] \
    && bad "the aborted transfer left a .part file behind" \
    || ok "the aborted transfer left no .part file"

# --- the SECOND timeout, i.e. the retry path.  Everything above runs at
#     retries=0 and therefore only ever takes the FIRST timeout -- which
#     is exactly how a real defect stayed invisible until 2026-09-16: a
#     longjmp out of the SIGALRM handler never performs the return that
#     unblocks SIGALRM, so the retry armed alarm() again and nothing
#     could deliver it.  First stall: timed out correctly.  Second:
#     hung forever, with the shipped default retries=2.  The client's
#     own stall message is the oracle -- it must appear TWICE, and the
#     run must end. ---
cp "$WORK/conf-stall" "$WORK/conf-stall-retry"
sed -i 's/^retries=0$/retries=1/' "$WORK/conf-stall-retry"
sed -i 's/^retry_delay=0$/retry_delay=0/' "$WORK/conf-stall-retry"
rm -f "$CACHE/stall-1.0.pkg" "$CACHE/stall-1.0.pkg.part"
T0=$(date +%s)
OUT=$("$APKG" -c "$WORK/conf-stall-retry" install stall 2>&1); rc=$?
T1=$(date +%s)
ELAPSED=$((T1 - T0))
[ $rc -eq 2 ] \
    && ok "a stall that is RETRIED still ends, with exit 2" \
    || bad "retried stall did not fail with exit 2 (rc=$rc)" "$OUT"
[ "$ELAPSED" -lt 30 ] \
    && ok "the SECOND inactivity timeout fired too (${ELAPSED}s for 2 stalls)" \
    || bad "the second stall hung: ${ELAPSED}s - SIGALRM stayed blocked" "$OUT"
[ "$(echo "$OUT" | grep -c 'timeout: no data for 2 s')" = 2 ] \
    && ok "both attempts timed out (2 timeout messages, retries=1)" \
    || bad "only one attempt timed out - the retry's alarm never fired" "$OUT"

# restore the plain catalog for anything downstream
"$APKG" update >/dev/null 2>&1

# ------------------------------------------------ the stub resolver (dns.c)
#
# Stock Amix has no resolver: gethostbyname() reads /etc/inet/hosts and
# nothing else, so a box that has not been hand-edited cannot turn
# pkg.amigaux.org into an address at all.  dns.c closes that for apkg's
# own lookups.  Order is literal -> host database -> nameservers.
#
# TWO VEHICLES, and the split is not cosmetic.  Step (b) is reached only
# when the HOST DATABASE said nothing, and on a test machine that is
# whatever NSS says -- unscriptable from here.  The bench host this was
# written on has a WILDCARD upstream that answers every name, reserved
# .invalid ones included, so a test assuming "an invalid name does not
# resolve" would have exercised nothing while passing.  So the resolver
# itself is driven by tests/dns-driver.c (-D: nameservers only, no host
# database in the way), and the ORDERING is proved end-to-end through
# apkg with names every machine agrees about (127.0.0.1, localhost).
echo "== building the dns driver =="
DNSDRV=$WORK/dns-driver
gcc -std=gnu89 -O2 -Wall -Wextra -o "$DNSDRV" \
    "$TESTS/dns-driver.c" "$SRC/dns.c" "$SRC/util.c" 2>"$WORK/dnsdrv.err" \
    && ok "the dns driver builds clean (-Wall -Wextra)" \
    || bad "dns driver build failed" "$(cat "$WORK/dnsdrv.err")"
[ -s "$WORK/dnsdrv.err" ] \
    && bad "dns.c compiled with warnings" "$(cat "$WORK/dnsdrv.err")" \
    || ok "dns.c compiles without a single warning"

freeudp() {
    python3 -c 'import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}
# a UDP listener cannot be connect()ed to, so probe by trying to BIND its
# port: while the server holds it, our bind fails
wait_udp() {
    n=0
    while [ $n -lt 50 ]; do
        python3 -c "import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.bind(('127.0.0.1', $1)); s.close(); sys.exit(1)
except OSError:
    sys.exit(0)" 2>/dev/null && return 0
        n=$((n + 1))
        sleep 0.1
    done
    return 1
}

DNSPIDS=
DNSPORT=
# startdns <mode>: starts a server and leaves its port in $DNSPORT.
# It must NOT hand the port back by echoing it: $(startdns ...) would run
# the whole function in a SUBSHELL, so the "$!" appended to DNSPIDS would
# die with that subshell and every run would leak seven python processes
# straight past the cleanup trap.  (It did, until this was turned round.)
startdns() {
    DNSPORT=$(freeudp)
    python3 "$TESTS/fake-dns.py" "$DNSPORT" "$1" >/dev/null 2>&1 &
    DNSPIDS="$DNSPIDS $!"
    wait_udp "$DNSPORT" || { echo "fake-dns $1 did not come up" >&2; exit 1; }
}

startdns ok;      D_OK=$DNSPORT
startdns cname;   D_CNAME=$DNSPORT
startdns garbage; D_GARBAGE=$DNSPORT
startdns short;   D_SHORT=$DNSPORT
startdns wrongid; D_WRONGID=$DNSPORT
startdns nx;      D_NX=$DNSPORT
startdns quiet;   D_QUIET=$DNSPORT

# replace the server cleanup so the nameservers go down too (the trap
# names the function, so a later definition is the one that runs)
cleanup() {
    kill "$SRV_PID" "$RSRV_PID" "$SSRV_PID" $DNSPIDS 2>/dev/null
    wait "$SRV_PID" "$RSRV_PID" "$SSRV_PID" $DNSPIDS 2>/dev/null
}

# --- a correct answer ---
OUT=$("$DNSDRV" -v -D -t 2 -r 0 -s "127.0.0.1:$D_OK" dnsok.apkg.invalid 2>&1)
rc=$?
[ $rc -eq 0 ] && echo "$OUT" | grep -q '^resolved dnsok.apkg.invalid 127.0.0.1$' \
    && ok "a correct A answer resolves" \
    || bad "a correct A answer did not resolve (rc=$rc)" "$OUT"
echo "$OUT" | grep -q "resolve: dnsok.apkg.invalid -> 127.0.0.1 (dns 127.0.0.1:$D_OK)" \
    && ok "-v reports what was resolved and by which nameserver" \
    || bad "-v does not report the resolution and its source" "$OUT"
echo "$OUT" | grep -q "dns: asked 127.0.0.1:$D_OK for A dnsok.apkg.invalid" \
    && ok "-v reports the query that was sent" \
    || bad "-v does not report the query" "$OUT"

# --- a CNAME chain, with compression pointers, A record emitted FIRST ---
OUT=$("$DNSDRV" -v -D -t 2 -r 0 -s "127.0.0.1:$D_CNAME" dnsc.apkg.invalid 2>&1)
rc=$?
[ $rc -eq 0 ] && echo "$OUT" | grep -q '^resolved dnsc.apkg.invalid 127.0.0.1$' \
    && ok "a CNAME chain is followed to its A record" \
    || bad "the CNAME chain did not resolve (rc=$rc)" "$OUT"
echo "$OUT" | grep -q 'dns: dnsc.apkg.invalid is a CNAME for alias.apkg.invalid' \
    && ok "-v names the CNAME it followed (and the pointer decoded)" \
    || bad "-v does not report the CNAME hop" "$OUT"

# --- malformed replies are discarded, never half-believed ---
for pair in "$D_GARBAGE garbage" "$D_SHORT truncated" "$D_WRONGID wrong-id"; do
    set -- $pair
    OUT=$("$DNSDRV" -v -D -t 2 -r 0 -s "127.0.0.1:$1" dnsx.apkg.invalid 2>&1)
    rc=$?
    [ $rc -ne 0 ] \
        && ok "a $2 reply does not resolve" \
        || bad "a $2 reply was accepted" "$OUT"
    echo "$OUT" | grep -q 'is malformed or answers a different question' \
        && ok "a $2 reply is reported as malformed and discarded" \
        || bad "a $2 reply was not reported as malformed" "$OUT"
    echo "$OUT" | grep -q '^resolved ' \
        && bad "a $2 reply produced an address anyway" "$OUT" \
        || ok "a $2 reply produced no address at all"
done

# --- a well-formed "no such name" is an ANSWER: not retried ---
OUT=$("$DNSDRV" -v -D -t 2 -r 2 -s "127.0.0.1:$D_NX" dnsn.apkg.invalid 2>&1)
rc=$?
[ $rc -ne 0 ] \
    && ok "rcode 3 does not resolve" \
    || bad "rcode 3 produced an address" "$OUT"
echo "$OUT" | grep -q 'dns: server answered rcode 3' \
    && ok "the rcode is reported" \
    || bad "the rcode is not reported" "$OUT"
[ "$(echo "$OUT" | grep -c 'dns: asked ')" = 1 ] \
    && ok "an answered query is not retried (1 query, retries=2)" \
    || bad "rcode 3 was retried -- it is an answer, not a failure" "$OUT"

# --- a silent nameserver: the per-attempt timeout is the only way out ---
T0=$(date +%s)
OUT=$("$DNSDRV" -v -D -t 1 -r 0 -s "127.0.0.1:$D_QUIET" dnsq.apkg.invalid 2>&1)
rc=$?
T1=$(date +%s)
ELAPSED=$((T1 - T0))
[ $rc -ne 0 ] \
    && ok "a silent nameserver fails rather than hanging" \
    || bad "a silent nameserver produced an address" "$OUT"
[ "$ELAPSED" -lt 10 ] \
    && ok "the DNS timeout fired promptly (${ELAPSED}s at dns_timeout=1)" \
    || bad "the DNS timeout did not fire (${ELAPSED}s)" "$OUT"
echo "$OUT" | grep -q 'dns: no reply from .* within 1 s' \
    && ok "the timeout message names the window it waited" \
    || bad "the timeout message does not name the window" "$OUT"
OUT=$("$DNSDRV" -v -D -t 1 -r 2 -s "127.0.0.1:$D_QUIET" dnsq.apkg.invalid 2>&1)
[ "$(echo "$OUT" | grep -c 'dns: asked ')" = 3 ] \
    && ok "dns_retries=2 sends three queries to the same nameserver" \
    || bad "dns_retries did not produce 3 attempts" "$OUT"

# --- fall back to the NEXT nameserver, in configured order ---
OUT=$("$DNSDRV" -v -D -t 1 -r 0 -s "127.0.0.1:$D_GARBAGE" \
      -s "127.0.0.1:$D_OK" dnsf.apkg.invalid 2>&1)
rc=$?
[ $rc -eq 0 ] && echo "$OUT" | grep -q "(dns 127.0.0.1:$D_OK)" \
    && ok "a broken first nameserver falls through to the second" \
    || bad "no fallback to the second nameserver (rc=$rc)" "$OUT"
OUT=$("$DNSDRV" -v -D -t 1 -r 0 -s "127.0.0.1:$D_QUIET" \
      -s "127.0.0.1:$D_OK" dnsf.apkg.invalid 2>&1)
[ $? -eq 0 ] \
    && ok "a SILENT first nameserver falls through to the second" \
    || bad "no fallback past a silent nameserver" "$OUT"
# order matters: the first one that answers wins
OUT=$("$DNSDRV" -v -D -t 1 -r 0 -s "127.0.0.1:$D_OK" \
      -s "127.0.0.1:$D_GARBAGE" dnsf.apkg.invalid 2>&1)
echo "$OUT" | grep -q "127.0.0.1:$D_GARBAGE" \
    && bad "the second nameserver was asked even though the first answered" "$OUT" \
    || ok "nameservers are tried in order and stop at the first answer"

# --- a nameserver spec that is not an address is skipped, not fatal ---
OUT=$("$DNSDRV" -v -D -t 1 -r 0 -s "not-an-ip" -s "127.0.0.1:$D_OK" \
      dnsb.apkg.invalid 2>&1)
rc=$?
[ $rc -eq 0 ] \
    && ok "an unparseable nameserver is skipped, the next one is used" \
    || bad "an unparseable nameserver was fatal (rc=$rc)" "$OUT"
echo "$OUT" | grep -q "nameserver 'not-an-ip' is not an IPv4 address" \
    && ok "the unparseable nameserver is named in a warning" \
    || bad "no warning for the unparseable nameserver" "$OUT"
OUT=$("$DNSDRV" -D -t 1 -r 0 -s "127.0.0.1:99999" dnsb.apkg.invalid 2>&1)
echo "$OUT" | grep -q "is not an IPv4 address" \
    && ok "an out-of-range port in a nameserver spec is refused" \
    || bad "a bad port was not refused" "$OUT"

# --- ORDER, end to end through apkg, with names every machine agrees on ---
# (1) an address literal never reaches the resolver
mkconf "$WORK/conf-lit" "http://127.0.0.1:$PORT/repo" "$WORK/bin/pkgadd-shim"
echo "nameserver=127.0.0.1:$D_GARBAGE" >> "$WORK/conf-lit"
OUT=$("$APKG" -v -c "$WORK/conf-lit" update 2>&1)
rc=$?
[ $rc -eq 0 ] \
    && ok "an IP-literal repo works with a broken nameserver configured" \
    || bad "an IP-literal repo failed (rc=$rc)" "$OUT"
echo "$OUT" | grep -q 'resolve: 127.0.0.1 is an address literal' \
    && ok "-v says the literal was used as-is" \
    || bad "-v does not report the literal path" "$OUT"
# (2) the HOST DATABASE wins over DNS: localhost is in every hosts file,
#     and the only nameserver configured is a broken one
mkconf "$WORK/conf-hosts" "http://localhost:$PORT/repo" "$WORK/bin/pkgadd-shim"
echo "nameserver=127.0.0.1:$D_GARBAGE" >> "$WORK/conf-hosts"
OUT=$("$APKG" -v -c "$WORK/conf-hosts" update 2>&1)
rc=$?
[ $rc -eq 0 ] \
    && ok "a hosts-file name resolves even with a broken nameserver" \
    || bad "the hosts file did not win over DNS (rc=$rc)" "$OUT"
echo "$OUT" | grep -q 'resolve: localhost -> 127.0.0.1 (hosts file)' \
    && ok "-v says the hosts file answered" \
    || bad "-v does not report the hosts-file path" "$OUT"
echo "$OUT" | grep -q 'dns: asked ' \
    && bad "DNS was consulted although the hosts file answered" "$OUT" \
    || ok "DNS is not consulted when the hosts file answers"
# (3)+(4) the full path: a repo host the HOST DATABASE does not know and
#     only the nameserver does.  Staging that needs a name this machine's
#     gethostbyname() genuinely fails on -- and that cannot be assumed.
#     The bench host here has a WILDCARD upstream that answers every name,
#     .invalid included, but refuses the same name written ABSOLUTE (with
#     a trailing dot); another machine will be the other way round.  So
#     probe the candidates with the very call apkg's step (a) makes, and
#     use the first one that really does fail.  If none fails, the case
#     cannot be staged here at all and is reported as a SKIP rather than
#     quietly passing on a name the resolver never saw.
E2EHOST=
for cand in dnse2e.apkg.invalid dnse2e.apkg.invalid. ; do
    python3 -c "import socket, sys
try:
    socket.gethostbyname('$cand'); sys.exit(0)
except Exception:
    sys.exit(1)" 2>/dev/null || { E2EHOST=$cand; break; }
done
if [ -n "$E2EHOST" ]; then
    # (3) no nameserver configured: the old behaviour, and a message that
    #     says which of the two things is missing
    OUT=$("$DNSDRV" -v "$E2EHOST" 2>&1)
    echo "$OUT" | grep -q 'not in the hosts file and no nameserver= is configured' \
        && ok "with no nameserver configured the message says what is missing" \
        || bad "the no-nameserver message does not say what is missing" "$OUT"
    # (4) with one configured, the same name resolves and the fetch runs
    mkconf "$WORK/conf-dns" "http://$E2EHOST:$PORT/repo" "$WORK/bin/pkgadd-shim"
    echo "nameserver=127.0.0.1:$D_OK" >> "$WORK/conf-dns"
    OUT=$("$APKG" -v -c "$WORK/conf-dns" update 2>&1)
    rc=$?
    [ $rc -eq 0 ] \
        && ok "a repo host only DNS knows is fetched end to end ($E2EHOST)" \
        || bad "the DNS-only repo host did not fetch (rc=$rc)" "$OUT"
    echo "$OUT" | grep -q "resolve: $E2EHOST -> 127.0.0.1 (dns " \
        && ok "-v says DNS answered for the repo host" \
        || bad "-v does not report the DNS path for the repo host" "$OUT"
    echo "$OUT" | grep -q "is not in the hosts file; asking 1 nameserver" \
        && ok "-v says the hosts file was tried first and said nothing" \
        || bad "-v does not show the hosts-then-dns order" "$OUT"
    [ -s "$CATFILE" ] \
        && ok "the catalog fetched over the DNS-resolved host is on disk" \
        || bad "no catalog after the DNS-resolved fetch" "$OUT"
else
    echo "SKIP: end-to-end DNS fetch - this host's resolver answers EVERY"
    echo "SKIP: candidate name, so a DNS-only host name cannot be staged."
    echo "SKIP: The resolver itself is covered by the driver above; the"
    echo "SKIP: literal and hosts-file orderings are covered by (1) and (2)."
fi
"$APKG" update >/dev/null 2>&1   # restore the plain catalog (default conf)

# --- the config keys ---
DNSDEF="dns: nameserver=(none, hosts file only) dns_timeout=5s dns_retries=2"
OUT=$("$APKG" -v -c "$WORK/conf-nofetch" list 2>&1)
echo "$OUT" | grep -q "$DNSDEF" \
    && ok "a config naming no resolver key gets the documented defaults" \
    || bad "the built-in resolver defaults are not what apkg.1 documents" "$OUT"

dnsconf() {
    cat > "$WORK/conf-dnskeys" <<EOF
repo=http://127.0.0.1:$PORT/repo
cachedir=$ROOT/var/apkg/cache
pkgadd=$WORK/bin/pkgadd-shim
pkgrm=$WORK/bin/pkgrm-shim
admin=$ROOT/var/apkg/admin
$1
EOF
    "$APKG" -v -c "$WORK/conf-dnskeys" list 2>&1
}
OUT=$(dnsconf "nameserver=10.0.0.1
nameserver=10.0.0.2:5353
dns_timeout=9
dns_retries=0")
echo "$OUT" | grep -q "dns: nameserver=10.0.0.1,10.0.0.2:5353 dns_timeout=9s dns_retries=0" \
    && ok "nameserver is repeatable and order-preserving; both knobs apply" \
    || bad "the resolver keys did not parse as documented" "$OUT"
OUT=$(dnsconf "nameserver=10.0.0.1
nameserver=")
echo "$OUT" | grep -q "dns: nameserver=(none, hosts file only)" \
    && ok "an empty nameserver= clears the list" \
    || bad "an empty nameserver= did not clear the list" "$OUT"
OUT=$(dnsconf "dns_timeout=banana")
echo "$OUT" | grep -q "bad dns_timeout 'banana', keeping 5" \
    && ok "a bad dns_timeout warns and keeps the default" \
    || bad "a bad dns_timeout was not refused" "$OUT"
OUT=$(dnsconf "dns_retries=-1")
echo "$OUT" | grep -q "bad dns_retries '-1', keeping 2" \
    && ok "a negative dns_retries warns and keeps the default" \
    || bad "a negative dns_retries was not refused" "$OUT"
OUT=$(dnsconf "nameserver=10.0.0.1
nameserver=10.0.0.2
nameserver=10.0.0.3
nameserver=10.0.0.4
nameserver=10.0.0.5
nameserver=10.0.0.6
nameserver=10.0.0.7
nameserver=10.0.0.8
nameserver=10.0.0.9")
echo "$OUT" | grep -q "more than 8 nameserver lines, '10.0.0.9' ignored" \
    && ok "the nameserver list is bounded, and says which line it dropped" \
    || bad "the nameserver list is unbounded" "$OUT"

# --- drift guard: the SHIPPED /etc/apkg.conf template must name the
#     resolver keys too, and agree with the binary about their defaults ---
if [ -s "$TMPL" ]; then
    MISSING=
    for k in nameserver dns_timeout dns_retries; do
        grep -q "^$k=" "$TMPL" || MISSING="$MISSING $k"
    done
    [ -z "$MISSING" ] \
        && ok "the shipped apkg.conf template names every resolver key" \
        || bad "shipped apkg.conf template is missing:$MISSING"
    grep -q '^nameserver=$' "$TMPL" \
        && ok "the shipped template's nameserver default is EMPTY" \
        || bad "the shipped template configures a nameserver by default" \
               "$(grep '^nameserver' "$TMPL")"
    OUT=$("$APKG" -v -c "$TMPL" list 2>&1)
    echo "$OUT" | grep -q "$DNSDEF" \
        && ok "the shipped template's resolver values are the binary's defaults" \
        || bad "shipped apkg.conf template has drifted from the resolver defaults" \
               "$OUT"
else
    bad "could not extract the apkg.conf template for the resolver keys"
fi

# ======================================= kernel space (apkg 0.3)
#
# amix-dlm contracts, version 2 (2026-10-26): C2-2 (the #ext kpkg block and
# the install record /var/apkg/kpkg/<name>) and C2-4 (kbootset as a called
# program).  Integrity in 1.1 is SHA-256 + size per kernel-space package,
# no signature (D-3 §13); the hook records "unverified".  kbootset does not
# exist on a box yet, so a mock stands in for it here: it logs its argv and
# answers with the status the test asks for (C2-4 §1: 0 done, 1 I/O,
# 2 usage, 3 rule, 4 gate).  tests/kbootset-consumer.sh runs the record
# apkg writes through the REAL kbootset build (amix-dlm), separately.

# --- SHA-256: FIPS 180-4 vectors and agreement with sha256sum ---
echo "== building the sha256 driver =="
SHADRV=$WORK/sha256-driver
( cd "$SRC" && gcc -std=gnu89 -O2 -Wall -Wextra -o "$SHADRV" \
    tests/sha256-driver.c util.c conf.c vercmp.c catalog.c md5.c http.c \
    dns.c install.c source.c kspace.c txn.c sha256.c ) 2>"$WORK/shadrv.err" \
    && [ ! -s "$WORK/shadrv.err" ] \
    && ok "the sha256 driver builds clean (-Wall -Wextra)" \
    || bad "sha256 driver build failed or warned" "$(cat "$WORK/shadrv.err")"
SV=$WORK/shavec
mkdir -p "$SV"
: > "$SV/empty"
printf abc > "$SV/abc"
printf 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq' > "$SV/two-block"
python3 -c 'import sys; sys.stdout.write("a" * 1000000)' > "$SV/million-a"
shav() { "$SHADRV" "$1" | cut -c1-64; }
[ "$(shav "$SV/empty")" = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 ] \
    && ok "sha256 of the empty message (FIPS 180-4)" \
    || bad "sha256 empty-message vector wrong" "$(shav "$SV/empty")"
[ "$(shav "$SV/abc")" = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad ] \
    && ok "sha256 of 'abc' (FIPS 180-4)" \
    || bad "sha256 'abc' vector wrong" "$(shav "$SV/abc")"
[ "$(shav "$SV/two-block")" = 248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1 ] \
    && ok "sha256 of the 448-bit two-block message (FIPS 180-4)" \
    || bad "sha256 two-block vector wrong" "$(shav "$SV/two-block")"
[ "$(shav "$SV/million-a")" = cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0 ] \
    && ok "sha256 of one million 'a' (FIPS 180-4)" \
    || bad "sha256 million-a vector wrong" "$(shav "$SV/million-a")"
# every length around the 64-byte block and the 8 KB read buffer, plus odd
# sizes, against the system's sha256sum
for n in 55 56 63 64 65 119 120 127 128 8191 8192 8193 16385 100003; do
    head -c $n /dev/urandom > "$SV/r$n"
done
GOT=$(cd "$SV" && "$SHADRV" r*); WANT=$(cd "$SV" && sha256sum r*)
[ "$GOT" = "$WANT" ] \
    && ok "sha256_file agrees with sha256sum at 14 lengths around block/buffer edges" \
    || bad "sha256_file disagrees with sha256sum" "$GOT
--- sha256sum:
$WANT"

# --- fixtures: kernel-space datastreams, shims, the kbootset mock ---
KR=$WORK/krepo
KLOG=$WORK/kbootset.log
mkdir -p "$KR/pkgs/kernel"
cp -r "$WORK/repo/pkgs/." "$KR/pkgs/"
# a fake datastream: a real SVR4 header and a real first cpio archive
# (pkginfo + pkgmap, tests/mkds.py) followed by the shim's directives: it
# installs the FILE lines, records DIR lines as directories, SHARED lines as
# a file two packages own (status- and class-decorated token in the contents
# DB).  apkg reads the header and the pkgmap (40 §6 pure files).
mkds() {    # mkds <out> <pkginst> <version> <payload-word> [extra pkgmap line]
    {
        printf 'DIR /stand\nDIR /stand/k46\n'
        printf 'FILE /stand/k46/%s %s-%s\n' "$4" "$4" "$3"
        printf 'FILE /stand/k46/%s.kabi kabi-of-%s\n' "$4" "$4"
        printf 'SHARED /stand/k46/README.%s readme\n' "$2"
        [ -n "${5:-}" ] && printf 'PKGMAP %s\n' "$5"
    } | python3 "$TESTS/mkds.py" "$1" "$2" "$3"
}
mkds "$KR/pkgs/kernel/kernel-k46-1.1.0.pkg" KERNK46  1.1.0 unix
mkds "$KR/pkgs/kernel/z3660scsi-k46-1.0.pkg" Z3660SCS 1.0 z3660scsi
mkds "$KR/pkgs/kernel/modbad-1.0.pkg"  MODBAD  1.0 modbad
mkds "$KR/pkgs/kernel/modpin-1.0.pkg"  MODPIN  1.0 modpin
mkds "$KR/pkgs/kernel/modk30-1.0.pkg"  MODK30  1.0 modk30
mkds "$KR/pkgs/kernel/liar-1.0.pkg"    LIARPKG 1.0 liar
mkds "$KR/pkgs/kernel/badsha-1.0.pkg"  BADSHA  1.0 badsha
mkds "$KR/pkgs/kernel/kernel-k46-1.1.1.pkg" KERNK46 1.1.1 unix
mkds "$KR/pkgs/kernel/kernel-k46-2.0.pkg"   KERNK46 2.0   unix
# not pure files (40 §6): each must be refused before anything installs
mkds "$KR/pkgs/kernel/impure-e-1.0.pkg"   IMPUREE 1.0 impe "1 e none /etc/kmod.conf 0644 root sys 1 1 1"
mkds "$KR/pkgs/kernel/impure-c-1.0.pkg"   IMPUREC 1.0 impc "1 f kcls /stand/k46/impc.x 0644 root sys 1 1 1"
mkds "$KR/pkgs/kernel/impure-s-1.0.pkg"   IMPURES 1.0 imps "1 i postinstall 20 1 1"
mkds "$KR/pkgs/kernel/impure-l-1.0.pkg"   IMPUREL 1.0 impl "1 s none /stand/k46/impl.lnk=/stand/k46/impl"
sha() { sha256sum "$1" | cut -c1-64; }
PIN=gcc-2.7.2.3-8949028
kline() {   # kline <name> <version> <role> <line> <kabi> <pin> <file> [extra]
    printf '#kpkg %s %s role=%s line=%s kabi=%s pin=%s size=%s sha256=%s file=%s%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$(sizeof "$KR/pkgs/$7")" \
        "$(sha "$KR/pkgs/$7")" "$7" "${8:+ $8}"
}
# the loader package (C2-3 v2 §3): boot1, boot2 and ldrinfo, one key=value
# per line; its entry (C2-2 v3 §1.1) has line=any and loader=, no kabi/pin
printf 'DIR /stand\nDIR /stand/loader\nFILE /stand/loader/boot1 b1bytes\nFILE /stand/loader/boot2 b2\nFILE /stand/loader/ldrinfo version=3\n' \
    | python3 "$TESTS/mkds.py" "$KR/pkgs/kernel/loader-3.pkg" LOADER 3
lline() {   # lline <name> <version> <role keys> [extra]
    printf '#kpkg %s %s role=loader %s size=%s sha256=%s file=kernel/loader-3.pkg%s\n' \
        "$1" "$2" "$3" "$(sizeof "$KR/pkgs/kernel/loader-3.pkg")" \
        "$(sha "$KR/pkgs/kernel/loader-3.pkg")" "${4:+ $4}"
}
mkkcat() {  # mkkcat <dest-catalog> <kernel-line> <extra-lines...>
    {
        cat "$WORK/repo/catalog"
        echo "#ext kpkg 1"
        echo "# a comment inside the block is ignored"
        echo "$2"
        kline z3660scsi-k46 1.0 module k46 k46.1.0 $PIN kernel/z3660scsi-k46-1.0.pkg "zz-future-key=1"
        kline modbad 1.0 module k46 k46.1.4 $PIN kernel/modbad-1.0.pkg
        kline modpin 1.0 module k46 k46.1.0 gcc-14.2-x kernel/modpin-1.0.pkg
        kline modk30 1.0 module k30 k30.1.0 $PIN kernel/modk30-1.0.pkg
        kline liar 1.0 module k46 k46.1.0 $PIN kernel/liar-1.0.pkg pkginst=NOTLIAR
        printf '#kpkg badsha 1.0 role=module line=k46 kabi=k46.1.0 pin=%s size=%s sha256=%s file=kernel/badsha-1.0.pkg\n' \
            $PIN "$(sizeof "$KR/pkgs/kernel/badsha-1.0.pkg")" \
            0000000000000000000000000000000000000000000000000000000000000000
        kline future 1.0 module k46 k46.1.0 $PIN kernel/modbad-1.0.pkg "!needs-signature=ed25519"
        echo "#kpkg nosha 1.0 role=kernel line=k46 kabi=k46.1.0 pin=$PIN size=1 file=kernel/x.pkg"
        lline loader 3 "line=any loader=3" "pkginst=LOADER"
        lline loaderkabi 3 "line=any loader=3 kabi=k46.1.0"
        lline loaderk46 3 "line=k46 loader=3"
        lline loadernov 3 "line=any"
        printf '#kpkg kernnopin 1.0 role=kernel line=k46 kabi=k46.1.0 size=%s sha256=%s file=kernel/kernel-k46-1.1.0.pkg\n' \
            "$(sizeof "$KR/pkgs/kernel/kernel-k46-1.1.0.pkg")" "$(sha "$KR/pkgs/kernel/kernel-k46-1.1.0.pkg")"
        for i in e c s l; do
            kline impure-$i 1.0 module k46 k46.1.0 $PIN kernel/impure-$i-1.0.pkg
        done
        echo "#ksig key-2026a catalog.sig"
        echo "#end kpkg"
    } > "$1"
}
KCAT_K110=$(kline kernel-k46 1.1.0 kernel k46 k46.1.0 $PIN kernel/kernel-k46-1.1.0.pkg)
mkkcat "$KR/catalog" "$KCAT_K110"

cat > "$WORK/bin/kpkgadd-shim" <<EOF
#!/bin/sh
# models pkgadd for the kernel-space tests: installs the fake datastream's
# FILE lines under \$APKG_ROOT<-R target> and writes SVR4 contents lines
echo "pkgadd \$*" >> $SHIMLOG
T=; F=; I=
while [ \$# -gt 0 ]; do
    case "\$1" in
    -R) T=\$2; shift 2 ;;
    -d) F=\$2; shift 2 ;;
    -a) shift 2 ;;
    -n) shift ;;
    *)  I=\$1; shift ;;
    esac
done
if [ -f $WORK/kshim.die ] && grep -qx "\$I" $WORK/kshim.die; then
    kill -9 \$PPID; sleep 1; exit 9      # a power cut, as apkg sees it
fi
R=\$APKG_ROOT\$T
C=\$R/var/sadm/install/contents
mkdir -p \$R/var/sadm/install \$R/var/sadm/pkg/\$I
touch \$C
awk -v i="\$I" '{ keep = 1
    for (k = 2; k <= NF; k++) { t = \$k; sub(/^[^A-Za-z0-9]+/, "", t)
        sub(/[\\\\:].*/, "", t); if (t == i) keep = 0 }
    if (keep) print }' \$C > \$C.t && mv \$C.t \$C
printf 'PKG=%s\nVERSION=%s\n' "\$I" "\$(sed -n 's/^VERSION //p' \$F)" \
    > \$R/var/sadm/pkg/\$I/pkginfo
sed -n 's/^DIR //p' \$F | while read d; do
    mkdir -p \$R\$d; echo "\$d d none 0755 root sys \$I" >> \$C; done
sed -n 's/^FILE //p' \$F | while read p c; do
    mkdir -p \$(dirname \$R\$p); echo "\$c" > \$R\$p
    echo "\$p f none 0644 root sys \$(wc -c < \$R\$p) 1 1700000000 \$I" >> \$C; done
sed -n 's/^SHARED //p' \$F | while read p c; do
    mkdir -p \$(dirname \$R\$p); echo "\$c" > \$R\$p
    printf '%s f none 0644 root sys %s 1 1 OTHERPKG +%s\\\\:kcls\n' \
        "\$p" "\$(wc -c < \$R\$p)" "\$I" >> \$C; done
exit 0
EOF
cat > "$WORK/bin/kpkgrm-shim" <<EOF
#!/bin/sh
echo "pkgrm \$*" >> $SHIMLOG
T=; I=
while [ \$# -gt 0 ]; do
    case "\$1" in -R) T=\$2; shift 2 ;; -a) shift 2 ;; -n) shift ;;
    *) I=\$1; shift ;; esac
done
R=\$APKG_ROOT\$T
C=\$R/var/sadm/install/contents
awk -v i="\$I" '{ keep = 1
    for (k = 2; k <= NF; k++) { t = \$k; sub(/^[^A-Za-z0-9]+/, "", t)
        sub(/[\\\\:].*/, "", t); if (t == i) keep = 0 }
    if (keep) print }' \$C > \$C.t && mv \$C.t \$C
rm -rf \$R/var/sadm/pkg/\$I
exit 0
EOF
# the kbootset mock (C2-4): the mode file says which call answers what
cat > "$WORK/bin/kbootset-mock" <<EOF
#!/bin/sh
echo "kbootset \$*" >> $KLOG
for cmd; do :; done
mode=\$(cat $WORK/kb.mode 2>/dev/null)
case "\$mode" in
"\$cmd"=*) st=\${mode#*=}
    case \$st in
    3) echo "kbootset: refused: the boot store is read-only" ;;
    4) echo "kbootset: gate 1 refused: /stand/k46/unix differs from its record" ;;
    *) echo "kbootset: \$cmd failed" ;;
    esac
    exit \$st ;;
esac
case "\$cmd" in
build)  echo "kbootset: generation 7 built in /stand/gen/7" ;;
commit) echo "kbootset: step 1 journal" >&2
        echo "kbootset: generation 7 committed; power-cycle to boot it" ;;
*)      exit 2 ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/kpkgadd-shim" "$WORK/bin/kpkgrm-shim" "$WORK/bin/kbootset-mock"

mkkconf() {  # mkkconf <file> <repo> [extra key=value lines]
    mkconf "$1" "$2" "$WORK/bin/kpkgadd-shim"
    sed -i "s|^pkgrm=.*|pkgrm=$WORK/bin/kpkgrm-shim|" "$1"
    echo "kbootset=$WORK/bin/kbootset-mock" >> "$1"
    [ -n "${3:-}" ] && printf '%s\n' "$3" >> "$1"
    return 0
}
KCONF=$WORK/conf-kspace
mkkconf "$KCONF" "file://$KR"
REC=$ROOT/var/apkg/kpkg
TXN=$ROOT/var/apkg/txn
kreset() { : > "$SHIMLOG"; : > "$KLOG"; rm -f "$WORK/kb.mode" "$WORK/kshim.die"; }
kreset

# --- the parser ---
"$APKG" -c "$KCONF" update > "$WORK/kupd.out" 2>&1; rc=$?
OUT=$(cat "$WORK/kupd.out")
[ $rc -eq 0 ] && echo "$OUT" | grep -q "catalog updated: 15 packages, 18 kernel-space" \
    && ok "update counts 15 ordinary + 18 kernel-space entries" \
    || bad "kernel-space catalog not accepted as expected (rc=$rc)" "$OUT"
echo "$OUT" | grep -q "unverified: no signature check" \
    && ok "update says the kernel-space block is unverified (60 §4 hook)" \
    || bad "the verification hook's verdict is not reported" "$OUT"
OUT=$("$APKG" -c "$KCONF" list 2>&1)
echo "$OUT" | grep -q "^kernel-k46 .*kernel .*kernel-space kernel, line k46, kabi k46\." \
    && ok "list shows a kernel-space entry with its role, line and kabi" \
    || bad "kernel-space entry missing from list" "$OUT"
echo "$OUT" | grep "^future " | grep -q "\[refused\]" \
    && ok "list marks an entry with a '!' key as refused" \
    || bad "the '!' entry is not marked refused" "$OUT"
OUT=$("$APKG" -c "$KCONF" info kernel-k46 2>&1)
echo "$OUT" | grep -q "SHA256:      $(sha "$KR/pkgs/kernel/kernel-k46-1.1.0.pkg")" && \
echo "$OUT" | grep -q "Pin:         $PIN" && \
echo "$OUT" | grep -q "Signature:   unverified" && \
echo "$OUT" | grep -q "Pkginst:     kernel-k46 (from the datastream)" \
    && ok "info shows sha256, pin, the unverified hook and the pkginst source" \
    || bad "kernel-space info wrong" "$OUT"
OUT=$("$APKG" -c "$KCONF" info future 2>&1)
echo "$OUT" | grep -q "Refused:     unknown mandatory key !needs-signature" \
    && ok "an unknown '!' key refuses the entry, not the catalog" \
    || bad "'!' key handling wrong" "$OUT"
OUT=$("$APKG" -c "$KCONF" info nosha 2>&1)
echo "$OUT" | grep -q "Refused:     .*missing key sha256=" \
    && ok "an entry without sha256= is refused" \
    || bad "a sha256-less entry was not refused" "$OUT"
OUT=$("$APKG" -c "$KCONF" info z3660scsi-k46 2>&1)
echo "$OUT" | grep -q "Refused" \
    && bad "an unknown plain key refused the entry (must be ignored)" "$OUT" \
    || ok "an unknown plain key is ignored"

# structural errors refuse the whole catalog, as an unsafe filename does
KBAD=$WORK/kbadrepo; mkdir -p "$KBAD"
mkkconf "$WORK/conf-kbad" "file://$KBAD"
kbadcat() { cat "$WORK/repo/catalog" > "$KBAD/catalog"; printf "$1" >> "$KBAD/catalog"; }
kbadcat '#ext kpkg 1\n#kpkg k 1 role=kernel\n'
run 3 "an unterminated kernel-space block rejects the catalog (exit 3)" \
    "$APKG" -c "$WORK/conf-kbad" update
kbadcat '#ext kpkg 1\nfoo2|1.0|FOO2|foo-1.0.pkg|00000000000000000000000000000000|1|none|system|x\n#end kpkg\n'
run 3 "an ordinary entry inside the block rejects the catalog (exit 3)" \
    "$APKG" -c "$WORK/conf-kbad" update
kbadcat '#ext kpkg 1\n#kpkg foo 1 role=kernel\n#end kpkg\n'
run 3 "a kernel-space name equal to an ordinary one rejects the catalog" \
    "$APKG" -c "$WORK/conf-kbad" update
kbadcat '#ext kpkg 1\n#end kpkg\n#ext kpkg 1\n#end kpkg\n'
run 3 "a second kernel-space block rejects the catalog" \
    "$APKG" -c "$WORK/conf-kbad" update
kbadcat '#ext kpkg 1\n#kpkg ../evil 1 role=kernel\n#end kpkg\n'
run 3 "a #kpkg name that is no safe record name rejects the catalog" \
    "$APKG" -c "$WORK/conf-kbad" update
kbadcat '#ext kpkg 2\n#kpkg newfmt 1 whatever\n#knew a line of a future format\n#end kpkg\n'
"$APKG" -c "$WORK/conf-kbad" update > "$WORK/kv2.out" 2>&1; rc=$?
[ $rc -eq 0 ] && grep -q "catalog updated: 15 packages$" "$WORK/kv2.out" \
    && ok "a block of another version is skipped whole (forward compatible)" \
    || bad "a kpkg version-2 block was not skipped (rc=$rc)" "$(cat "$WORK/kv2.out")"
# the 2048-byte line bound: a block line of 2047 bytes (with its newline)
# passes, one of 2048 is refused -- the same bound 0.2.x applies to every
# line, so the new reader can never accept what would brick an old one
padline() { python3 -c 'import sys; p = "#kpkg longk 1 role=kernel x="
print(p + "y" * (int(sys.argv[1]) - 1 - len(p)))' "$1"; }
PAD2047=$(padline 2047)
PAD2048=$(padline 2048)
kbadcat "#ext kpkg 1\n$PAD2047\n#end kpkg\n"
[ "$(sed -n '/^#kpkg longk/p' "$KBAD/catalog" | wc -c)" -eq 2047 ] || bad "fixture: 2047-byte line is not 2047 bytes"
run 0 "a 2047-byte block line (newline included) is accepted" \
    "$APKG" -c "$WORK/conf-kbad" update
kbadcat "#ext kpkg 1\n$PAD2048\n#end kpkg\n"
run 3 "a 2048-byte block line is refused (C2-2: every line under 2048 B)" \
    "$APKG" -c "$WORK/conf-kbad" update

# --- the OLD client skips the block unharmed (built from 0.2.3's source) ---
OLDC=cc02d52                       # amix-packagemanager: APKG 0.2.3 source
OLDDIR=$WORK/old-apkg
REPOTOP=$(cd "$SRC/../.." && pwd)
if command -v git >/dev/null 2>&1 && \
   git -C "$REPOTOP" cat-file -e "$OLDC:src/apkg/catalog.c" 2>/dev/null; then
    rm -rf "$OLDDIR"; mkdir -p "$OLDDIR"
    git -C "$REPOTOP" archive "$OLDC" src/apkg | tar -x -C "$OLDDIR"
    make -C "$OLDDIR/src/apkg" host >/dev/null 2>&1
    OLDAPKG=$OLDDIR/src/apkg/apkg
    [ "$("$OLDAPKG" version 2>&1)" = "apkg 0.2.3" ] \
        && ok "the 0.2.3 client builds from $OLDC" \
        || bad "could not build the 0.2.3 client from $OLDC"
    "$OLDAPKG" -c "$CONF" update >/dev/null 2>&1
    "$OLDAPKG" -c "$CONF" list > "$WORK/old.list.plain" 2>/dev/null
    OUT=$("$OLDAPKG" -c "$KCONF" update 2>&1); rc=$?
    [ $rc -eq 0 ] && echo "$OUT" | grep -q "^catalog updated: 15 packages$" \
        && ok "0.2.3 accepts the kernel-space catalog and counts 15 packages" \
        || bad "0.2.3 choked on the kernel-space block (rc=$rc)" "$OUT"
    "$OLDAPKG" -c "$KCONF" list > "$WORK/old.list.k" 2>/dev/null
    cmp -s "$WORK/old.list.plain" "$WORK/old.list.k" \
        && ok "0.2.3's list is byte-identical with and without the block" \
        || bad "the block changed 0.2.3's view" \
               "$(diff "$WORK/old.list.plain" "$WORK/old.list.k")"
    run 5 "0.2.3 never sees kernel space (kernel-k46 is not in its catalog)" \
        "$OLDAPKG" -c "$KCONF" -n install kernel-k46
    run 0 "0.2.3 still installs through a block-carrying catalog" \
        "$OLDAPKG" -c "$KCONF" -n install baz
    kbadcat "#ext kpkg 1\n$PAD2047\n#end kpkg\n"
    run 0 "0.2.3 takes the 2047-byte block line" "$OLDAPKG" -c "$WORK/conf-kbad" update
    kbadcat "#ext kpkg 1\n$PAD2048\n#end kpkg\n"
    run 3 "0.2.3 refuses a 2048-byte line: the bound the contract keeps" \
        "$OLDAPKG" -c "$WORK/conf-kbad" update
    "$APKG" -c "$KCONF" update >/dev/null 2>&1
else
    bad "cannot build the 0.2.3 client: git or commit $OLDC unavailable"
fi

# --- install a kernel: SHA-256 verify, pkgadd, the record, the trigger ---
kreset
"$APKG" -c "$KCONF" install kernel-k46 > "$WORK/kinst.out" 2>&1; rc=$?
OUT=$(cat "$WORK/kinst.out")
[ $rc -eq 0 ] && ok "install kernel-k46 (rc 0)" || bad "kernel install failed (rc=$rc)" "$OUT"
echo "$OUT" | grep -q "kernel space: 1 package in this transaction; a generation build (kbootset) and a power cycle follow" \
    && ok "the transaction announces kernel space before it starts" \
    || bad "no kernel-space announcement" "$OUT"
grep -q "^pkgadd -n -a $ROOT/var/apkg/admin -d $KR/pkgs/kernel/kernel-k46-1.1.0.pkg KERNK46$" "$SHIMLOG" \
    && ok "pkgadd got the verified medium file and the pkginst from the datastream header" \
    || bad "kernel pkgadd argv wrong" "$(cat "$SHIMLOG")"
KREC=$REC/kernel-k46
U=$ROOT/stand/k46/unix
K=$ROOT/stand/k46/unix.kabi
S=$ROOT/stand/k46/README.KERNK46
cat > "$WORK/krec.want" <<EOF
name kernel-k46
version 1.1.0
role kernel
line k46
kabi k46.1.0
pin $PIN
sha256 $(sha "$KR/pkgs/kernel/kernel-k46-1.1.0.pkg")
source $KR
installed X
verified no
file /stand/k46/unix $(sizeof "$U") $(sha "$U")
file /stand/k46/unix.kabi $(sizeof "$K") $(sha "$K")
file /stand/k46/README.KERNK46 $(sizeof "$S") $(sha "$S")
EOF
sed 's/^installed [0-9][0-9]*$/installed X/' "$KREC" > "$WORK/krec.got" 2>/dev/null
cmp -s "$WORK/krec.want" "$WORK/krec.got" \
    && ok "the record is exactly C2-2 §2: fields in order, verified no, one file line per object" \
    || bad "the install record differs from C2-2 §2" "$(diff "$WORK/krec.want" "$WORK/krec.got" 2>&1)"
grep -q "^installed [0-9][0-9]*$" "$KREC" \
    && ok "the record's installed field is seconds since 1970" \
    || bad "installed field malformed" "$(cat "$KREC")"
grep -q " d " "$KREC" && bad "a directory reached the record" || \
    ok "directories are not recorded (plain files only; the shared one is)"
printf 'kbootset --journal /var/kbootset/journal build\nkbootset --journal /var/kbootset/journal commit\n' > "$WORK/kb.want"
cmp -s "$WORK/kb.want" "$KLOG" \
    && ok "kbootset ran as two calls: build, then commit (C2-4 §5)" \
    || bad "kbootset calls wrong" "$(cat "$KLOG")"
echo "$OUT" | grep -q "^apkg: generation 7 committed; power-cycle to boot it$" \
    && ok "on status 0 apkg repeats kbootset's last line" \
    || bad "the commit line was not repeated" "$OUT"
[ ! -f "$TXN" ] && ok "the journal is gone after a finished transaction" \
    || bad "journal left behind" "$(cat "$TXN")"
OUT=$("$APKG" -c "$KCONF" list installed 2>&1)
echo "$OUT" | grep -q "^kernel-k46 .*\[installed 1.1.0\]" \
    && ok "an installed kernel-space package is known by its record" \
    || bad "list installed does not show the kernel" "$OUT"
kreset
OUT=$("$APKG" -c "$KCONF" install kernel-k46 2>&1); rc=$?
[ $rc -eq 0 ] && echo "$OUT" | grep -q "already installed" && [ ! -s "$KLOG" ] \
    && ok "an installed kernel is skipped and nothing is triggered" \
    || bad "re-install of an installed kernel misbehaved (rc=$rc)" "$OUT"

# --- pre-flight: kabi family/major/minor, compiler pin, line ---
kreset
run 0 "a module whose kabi and pin match the installed kernel installs" \
    "$APKG" -c "$KCONF" install z3660scsi-k46
grep -q "^role module$" "$REC/z3660scsi-k46" 2>/dev/null \
    && ok "the module's record is written" || bad "no module record"
[ "$(grep -c . "$KLOG")" -eq 2 ] && ok "the module install triggered build + commit" \
    || bad "module install trigger wrong" "$(cat "$KLOG")"
kreset
run 5 "a module needing a newer kabi minor is refused (exit 5)" \
    "$APKG" -c "$KCONF" install modbad
OUT2=$OUT
run 5 "a module built with another compiler pin is refused (exit 5)" \
    "$APKG" -c "$KCONF" install modpin
echo "$OUT" | grep -q "compiler pin gcc-14.2-x differs" \
    && ok "the pin refusal names both pins" || bad "pin refusal message" "$OUT"
run 5 "a module of a line with no kernel is refused (exit 5)" \
    "$APKG" -c "$KCONF" install modk30
[ ! -s "$SHIMLOG" ] && [ ! -s "$KLOG" ] && [ ! -f "$TXN" ] \
    && ok "a pre-flight refusal stages, installs and journals nothing" \
    || bad "pre-flight refusal touched something" "$(cat "$SHIMLOG" "$KLOG")"
echo "$OUT2" | grep -q "needs a newer kernel" && ok "the minor refusal says why" \
    || bad "minor refusal message" "$OUT2"
run 3 "a refused catalog entry cannot be installed (exit 3)" \
    "$APKG" -c "$KCONF" install future
run 3 "a datastream whose sha256 differs from the catalog is refused (exit 3)" \
    "$APKG" -c "$KCONF" install badsha
run 3 "a datastream whose header contradicts pkginst= is refused (exit 3)" \
    "$APKG" -c "$KCONF" install liar
for i in e c s l; do
    case $i in
    e) why="an object of type e at /etc/kmod.conf" ;;
    c) why="an object in class kcls" ;;
    s) why="it carries an install script: postinstall" ;;
    l) why="an object of type s at /stand/k46/impl.lnk=/stand/k46/impl" ;;
    esac
    run 3 "a kernel-space datastream with $why is refused (exit 3)" \
        "$APKG" -c "$KCONF" install impure-$i
    echo "$OUT" | grep -qF "impure-$i: not a pure-file kernel-space package: $why" \
        && ok "the pure-files refusal says why ($why)" \
        || bad "pure-files refusal message for impure-$i" "$OUT"
done
[ ! -s "$SHIMLOG" ] && [ ! -f "$TXN" ] && ok "no pkgadd ran and nothing was journaled for any refused package" \
    || bad "pkgadd ran for a refused package" "$(cat "$SHIMLOG")"

# a new kernel whose kabi major moves strands the installed module: refused
KR2=$WORK/krepo2; mkdir -p "$KR2"; ln -sfn "$KR/pkgs" "$KR2/pkgs"
mkkcat "$KR2/catalog" "$(kline kernel-k46 2.0 kernel k46 k46.2.0 $PIN kernel/kernel-k46-2.0.pkg)"
mkkconf "$WORK/conf-k2" "file://$KR2"
"$APKG" -c "$WORK/conf-k2" update >/dev/null 2>&1
kreset
run 5 "upgrading the kernel to kabi k46.2.0 under a k46.1.0 module is refused" \
    "$APKG" -c "$WORK/conf-k2" upgrade kernel-k46
echo "$OUT" | grep -q "the installed module z3660scsi-k46 must be upgraded or removed with the kernel kernel-k46" \
    && ok "the refusal names the module that would be stranded" \
    || bad "stranded-module message" "$OUT"

# --- upgrade (same kabi): instance=overwrite, the record follows ---
mkkcat "$KR2/catalog" "$(kline kernel-k46 1.1.1 kernel k46 k46.1.0 $PIN kernel/kernel-k46-1.1.1.pkg)"
"$APKG" -c "$WORK/conf-k2" update >/dev/null 2>&1
kreset
run 0 "upgrade kernel-k46 1.1.0 -> 1.1.1" "$APKG" -c "$WORK/conf-k2" upgrade kernel-k46
grep -q "^pkgadd -n -a $ROOT/var/apkg/admin.overwrite -d $KR2/pkgs/kernel/kernel-k46-1.1.1.pkg KERNK46$" "$SHIMLOG" \
    && ok "the kernel upgrade is one pkgadd with instance=overwrite" \
    || bad "kernel upgrade argv" "$(cat "$SHIMLOG")"
grep -q "^version 1.1.1$" "$KREC" && grep -q "^file /stand/k46/unix $(sizeof "$U") $(sha "$U")$" "$KREC" \
    && ok "the record carries the new version and the new file's sha256" \
    || bad "record not updated by the upgrade" "$(cat "$KREC")"
[ "$(grep -c . "$KLOG")" -eq 2 ] && ok "the upgrade triggered build + commit" \
    || bad "upgrade trigger" "$(cat "$KLOG")"
"$APKG" -c "$KCONF" update >/dev/null 2>&1

# --- the five kbootset statuses, mapped (C2-4 §1) ---
kreset; echo build=4 > "$WORK/kb.mode"
run 7 "a gate refusal at build exits 7" "$APKG" -c "$KCONF" -f install z3660scsi-k46
echo "$OUT" | grep -q "refused at a gate (status 4): gate 1 refused: /stand/k46/unix differs" && \
echo "$OUT" | grep -q "the committed generation is unchanged" \
    && ok "status 4: the kbootset line is passed on, 'the committed generation is unchanged'" \
    || bad "status 4 message" "$OUT"
[ "$(cat "$KLOG")" = "kbootset --journal /var/kbootset/journal build" ] \
    && ok "after a refused build, commit is not called" || bad "commit ran after a refused build" "$(cat "$KLOG")"
[ ! -f "$TXN" ] && ok "a refusal is an answer: no journal is kept" || bad "journal kept after a refusal"
kreset; echo build=3 > "$WORK/kb.mode"
run 7 "a rule refusal (status 3) exits 7" "$APKG" -c "$KCONF" -f install z3660scsi-k46
echo "$OUT" | grep -q "refused by a rule (status 3): refused: the boot store is read-only" \
    && ok "status 3 passes the kbootset line on" || bad "status 3 message" "$OUT"
kreset; echo build=2 > "$WORK/kb.mode"
run 6 "status 2 (usage) exits 6" "$APKG" -c "$KCONF" -f install z3660scsi-k46
echo "$OUT" | grep -q "contract C2-4 version 2" && ok "status 2 asks whether kbootset speaks C2-4" \
    || bad "status 2 message" "$OUT"
"$APKG" -c "$KCONF" -f recover >/dev/null 2>&1
kreset; echo build=1 > "$WORK/kb.mode"
run 6 "status 1 at build exits 6" "$APKG" -c "$KCONF" -f install z3660scsi-k46
grep -q "^state installed$" "$TXN" 2>/dev/null \
    && ok "after status 1 the journal is kept (state installed: the trigger is owed)" \
    || bad "no journal after status 1" "$(cat "$TXN" 2>&1)"
run 1 "a pending journal blocks the next transaction" "$APKG" -c "$KCONF" install foo
echo "$OUT" | grep -q "run 'apkg recover'" && ok "the block says to run apkg recover" \
    || bad "pending-journal message" "$OUT"
kreset
run 0 "apkg recover re-runs the trigger and finishes" "$APKG" -c "$KCONF" recover
[ "$(grep -c . "$KLOG")" -eq 2 ] && [ ! -f "$TXN" ] && ! grep -q pkgadd "$SHIMLOG" \
    && ok "recover ran build + commit only (nothing re-installed) and cleared the journal" \
    || bad "recover of a pending trigger" "$(cat "$KLOG" "$SHIMLOG")"
kreset; echo commit=1 > "$WORK/kb.mode"
run 6 "build succeeds, commit fails: exit 6" "$APKG" -c "$KCONF" -f install z3660scsi-k46
echo "$OUT" | grep -q "built but not committed: the next boot is unchanged" \
    && ok "a failure between build and commit is reported, next generation uncommitted" \
    || bad "build-ok/commit-fail message" "$OUT"
grep -q "^state built$" "$TXN" 2>/dev/null && ok "the journal says the build was done" \
    || bad "journal state after build" "$(cat "$TXN" 2>&1)"
kreset
run 0 "recover after a failed commit builds and commits again" "$APKG" -c "$KCONF" recover
[ ! -f "$TXN" ] && ok "journal cleared by recover" || bad "journal left"

# kbootset not there (today's boxes) / bootset=manual / -n / -R / --journal
mkkconf "$WORK/conf-nokb" "file://$KR"
sed -i "s|^kbootset=.*|kbootset=$WORK/no/such/kbootset|" "$WORK/conf-nokb"
kreset
run 6 "kbootset missing: the packages install, exit 6" \
    "$APKG" -c "$WORK/conf-nokb" -f install z3660scsi-k46
echo "$OUT" | grep -q "kbootset not found at $WORK/no/such/kbootset" \
    && ok "a missing kbootset is named" || bad "missing-kbootset message" "$OUT"
run 0 "apkg -f recover discards the journal" "$APKG" -c "$KCONF" -f recover
[ ! -f "$TXN" ] && echo "$OUT" | grep -q "discarding the journal" \
    && ok "-f recover reports the transaction and discards it" || bad "-f recover" "$OUT"
kreset
mkdir -p "$ROOT/etc/default"; echo "bootset=manual" > "$ROOT/etc/default/bootset"
run 0 "bootset=manual: install succeeds without running kbootset" \
    "$APKG" -c "$KCONF" -f install z3660scsi-k46
[ ! -s "$KLOG" ] && echo "$OUT" | grep -q "bootset=manual; compose the next generation with: $WORK/bin/kbootset-mock --journal /var/kbootset/journal build" \
    && ok "bootset=manual prints the commands instead" || bad "manual mode" "$OUT $(cat "$KLOG")"
rm -f "$ROOT/etc/default/bootset"
kreset
run 0 "-n on a kernel-space install" "$APKG" -c "$KCONF" -n -f install z3660scsi-k46
[ ! -s "$KLOG" ] && [ ! -s "$SHIMLOG" ] && [ ! -f "$TXN" ] && \
echo "$OUT" | grep -q "would write the record $REC/z3660scsi-k46" && \
echo "$OUT" | grep -q "would run: $WORK/bin/kbootset-mock --journal /var/kbootset/journal commit" \
    && ok "-n prints the pkgadd, the record and both kbootset calls, runs nothing" \
    || bad "-n kernel-space plan" "$OUT"
KT=$WORK/ktgt
kreset
run 0 "-R <target>: kernel-space install into a target" \
    "$APKG" -c "$KCONF" -R "$KT" install kernel-k46
printf 'kbootset -R %s --journal %s/var/kbootset/journal build\nkbootset -R %s --journal %s/var/kbootset/journal commit\n' \
    "$KT" "$KT" "$KT" "$KT" > "$WORK/kb.want"
cmp -s "$WORK/kb.want" "$KLOG" && ok "kbootset is told -R <target> and the target's journal" \
    || bad "-R kbootset argv" "$(cat "$KLOG")"
[ -f "$ROOT$KT/var/apkg/kpkg/kernel-k46" ] && grep -q "^file /stand/k46/unix " "$ROOT$KT/var/apkg/kpkg/kernel-k46" \
    && ok "the target's record lives under the target, paths as the target sees them" \
    || bad "target record" "$(ls -R "$ROOT$KT/var/apkg" 2>&1)"
mkkconf "$WORK/conf-kj" "file://$KR" "kbootset_journal=/var/tmp/kbj"
kreset
run 0 "kbootset_journal= is honoured" "$APKG" -c "$WORK/conf-kj" -f install z3660scsi-k46
grep -q "^kbootset --journal /var/tmp/kbj build$" "$KLOG" \
    && ok "--journal carries the configured path" || bad "--journal" "$(cat "$KLOG")"

# --- an interrupted transaction (power cut during the 2nd pkgadd) ---
"$APKG" -c "$KCONF" remove z3660scsi-k46 >/dev/null 2>&1
"$APKG" -c "$KCONF" remove kernel-k46 >/dev/null 2>&1
kreset; echo Z3660SCS > "$WORK/kshim.die"
"$APKG" -c "$KCONF" install kernel-k46 z3660scsi-k46 > "$WORK/kcut.out" 2>&1; rc=$?
[ $rc -eq 137 ] && ok "apkg was killed mid-transaction (the cut)" \
    || bad "the cut did not happen (rc=$rc)" "$(cat "$WORK/kcut.out")"
grep -q "^pkg 1 0 1 .* kernel-k46 " "$TXN" 2>/dev/null && grep -q "^pkg 0 0 1 .* z3660scsi-k46 " "$TXN" \
    && ok "the journal has the kernel done and the module pending" \
    || bad "journal after the cut" "$(cat "$TXN" 2>&1)"
[ -f "$REC/kernel-k46" ] && [ ! -f "$REC/z3660scsi-k46" ] && [ ! -s "$KLOG" ] \
    && ok "after the cut: kernel recorded, module not, kbootset never ran" \
    || bad "state after the cut" "$(ls "$REC"; cat "$KLOG")"
kreset
run 0 "apkg recover finishes the interrupted transaction" "$APKG" -c "$KCONF" recover
grep -q "^pkgadd -n -a $ROOT/var/apkg/admin.overwrite -d $KR/pkgs/kernel/z3660scsi-k46-1.0.pkg Z3660SCS$" "$SHIMLOG" && \
! grep -q KERNK46 "$SHIMLOG" \
    && ok "recover re-adds only the pending package, with instance=overwrite" \
    || bad "recover pkgadd" "$(cat "$SHIMLOG")"
[ -f "$REC/z3660scsi-k46" ] && [ "$(grep -c . "$KLOG")" -eq 2 ] && [ ! -f "$TXN" ] \
    && ok "recover wrote the record, ran the trigger once and cleared the journal" \
    || bad "recover end state" "$(cat "$KLOG"; cat "$TXN" 2>&1)"
echo "$OUT" | grep -q "1 of 2 packages done" && ok "recover reports what it found" \
    || bad "recover report" "$OUT"
run 0 "recover with no journal is a no-op" "$APKG" -c "$KCONF" recover
echo "$OUT" | grep -q "no unfinished transaction" && ok "and says so" || bad "no-journal message" "$OUT"

# --- a pkgadd failure inside a kernel-space transaction keeps the journal ---
"$APKG" -c "$KCONF" remove z3660scsi-k46 >/dev/null 2>&1
mkkconf "$WORK/conf-kfail" "file://$KR"
sed -i "s|^pkgadd=.*|pkgadd=$WORK/bin/pkgadd-fail|" "$WORK/conf-kfail"
kreset
run 4 "a failed kernel-space pkgadd exits 4" "$APKG" -c "$WORK/conf-kfail" install z3660scsi-k46
[ -f "$TXN" ] && [ ! -s "$KLOG" ] && echo "$OUT" | grep -q "the boot store is untouched" \
    && ok "the journal is kept, the trigger never ran, the store is untouched" \
    || bad "kernel-space pkgadd failure" "$OUT"
"$APKG" -c "$KCONF" -f recover >/dev/null 2>&1

# --- remove: pkgrm of the pkginst owning the recorded files, record, trigger ---
"$APKG" -c "$KCONF" install z3660scsi-k46 >/dev/null 2>&1
kreset
run 0 "remove a kernel-space package" "$APKG" -c "$KCONF" remove z3660scsi-k46
grep -q "^pkgrm -n -a $ROOT/var/apkg/admin Z3660SCS$" "$SHIMLOG" && [ ! -f "$REC/z3660scsi-k46" ] \
    && ok "remove runs pkgrm on the owning pkginst and deletes the record" \
    || bad "kernel-space remove" "$(cat "$SHIMLOG"; ls "$REC")"
[ "$(grep -c . "$KLOG")" -eq 2 ] && ok "the remove triggered build + commit" \
    || bad "remove trigger" "$(cat "$KLOG")"

# --- the loader role (C2-2 v3 §1.1, C2-3 v2 §3) ---
OUT=$("$APKG" -c "$KCONF" info loader 2>&1)
echo "$OUT" | grep -q "^Kernel-space: loader, line any$" && echo "$OUT" | grep -q "^Loader:      3$" && \
! echo "$OUT" | grep -q "^Kabi:\|^Pin:\|^Refused" \
    && ok "a loader entry: line any, loader 3, no kabi or pin, not refused" \
    || bad "loader entry info" "$OUT"
OUT=$("$APKG" -c "$KCONF" info loaderkabi 2>&1)
echo "$OUT" | grep -q "^Refused:     a loader entry may not carry kabi= (C2-2 v3 §1.1)$" \
    && ok "a loader entry carrying kabi= is refused (C2-2 v3)" || bad "loader+kabi" "$OUT"
OUT=$("$APKG" -c "$KCONF" info loaderk46 2>&1)
echo "$OUT" | grep -q "^Refused:     a loader needs line=any, not k46$" \
    && ok "a loader entry with line=k46 is refused" || bad "loader line" "$OUT"
OUT=$("$APKG" -c "$KCONF" info loadernov 2>&1)
echo "$OUT" | grep -q "^Refused:     missing key loader= (C2-2 v3 §1.1)$" \
    && ok "a loader entry without loader= is refused" || bad "loader without loader=" "$OUT"
OUT=$("$APKG" -c "$KCONF" info kernnopin 2>&1)
echo "$OUT" | grep -q "^Refused:     missing key pin= (C2-2 v3 §1.1)$" \
    && ok "a kernel entry missing pin= is refused (C2-2 v3)" || bad "kernel without pin" "$OUT"
run 3 "a refused loader entry cannot be installed (exit 3)" "$APKG" -c "$KCONF" install loaderkabi
kreset
run 0 "install the loader package" "$APKG" -c "$KCONF" install loader
LB=$ROOT/stand/loader
cat > "$WORK/lrec.want" <<EOF
name loader
version 3
role loader
line any
loader 3
sha256 $(sha "$KR/pkgs/kernel/loader-3.pkg")
source $KR
installed X
verified no
file /stand/loader/boot1 $(sizeof "$LB/boot1") $(sha "$LB/boot1")
file /stand/loader/boot2 $(sizeof "$LB/boot2") $(sha "$LB/boot2")
file /stand/loader/ldrinfo $(sizeof "$LB/ldrinfo") $(sha "$LB/ldrinfo")
EOF
sed 's/^installed [0-9][0-9]*$/installed X/' "$REC/LOADER" > "$WORK/lrec.got" 2>/dev/null
cmp -s "$WORK/lrec.want" "$WORK/lrec.got" \
    && ok "the loader's record /var/apkg/kpkg/LOADER (pkginst=, C2-2 v4): line any, a loader line, no kabi or pin" \
    || bad "loader record" "$(diff "$WORK/lrec.want" "$WORK/lrec.got" 2>&1)"
grep -q "^pkgadd .* LOADER$" "$SHIMLOG" && [ "$(grep -c . "$KLOG")" -eq 2 ] \
    && ok "the loader installs as LOADER and triggers build + commit" \
    || bad "loader install" "$(cat "$SHIMLOG" "$KLOG")"
kreset
run 0 "remove the loader package" "$APKG" -c "$KCONF" remove loader
[ ! -f "$REC/LOADER" ] && ok "the loader's record is gone" \
    || bad "loader record left" "$(ls "$REC")"

# --- C2-2 v4: the record file is the pkginst, not the name.  An s5 root
#     keeps 14 characters of a file name, so "kernel-k46-zacd" (15) and
#     its ".new" would collapse into one name; "KERNZACD.new" stays apart.
mkds "$KR/pkgs/kernel/kernel-k46-zacd-1.0.pkg" KERNZACD 1.0 zacd
mkkcat "$KR/catalog" "$KCAT_K110
$(kline kernel-k46-zacd 1.0 kernel k46 k46.1.0 $PIN kernel/kernel-k46-zacd-1.0.pkg pkginst=KERNZACD)"
"$APKG" -c "$KCONF" update >/dev/null 2>&1
kreset
run 0 "install kernel-k46-zacd (a 15-character name, pkginst KERNZACD)" \
    "$APKG" -c "$KCONF" install kernel-k46-zacd
[ -f "$REC/KERNZACD" ] && [ ! -e "$REC/kernel-k46-zacd" ] && [ -z "$(ls "$REC" | grep -v '^KERNZACD$\|^kernel-k46$')" ] \
    && ok "its record file is the 8-character pkginst, KERNZACD (C2-2 v4 §2)" \
    || bad "record file name for a long name" "$(ls "$REC")"
grep -qx "name kernel-k46-zacd" "$REC/KERNZACD" 2>/dev/null \
    && ok "the full 15-character name stays in the record's name line" \
    || bad "record name line" "$(cat "$REC/KERNZACD" 2>&1)"
[ "$(printf '%s' KERNZACD.new | wc -c)" -le 14 ] \
    && ok "KERNZACD.new fits the s5 14-character limit (distinct from the record)" \
    || bad "KERNZACD.new too long for s5"
OUT=$("$APKG" -c "$KCONF" list installed 2>&1)
echo "$OUT" | grep -q "^kernel-k46-zacd .*\[installed 1.0\]" \
    && ok "list installed finds it through its pkginst-named record" \
    || bad "list installed for the long name" "$OUT"
run 0 "install of it again is a skip (installed state read by pkginst)" \
    "$APKG" -c "$KCONF" install kernel-k46-zacd
echo "$OUT" | grep -q "already installed" && ok "and says already installed" || bad "re-install skip" "$OUT"
kreset
run 0 "remove kernel-k46-zacd by its name" "$APKG" -c "$KCONF" remove kernel-k46-zacd
grep -q "^pkgrm .* KERNZACD$" "$SHIMLOG" && [ ! -f "$REC/KERNZACD" ] \
    && ok "remove found the record by its name line, ran pkgrm KERNZACD, deleted KERNZACD" \
    || bad "remove of the long name" "$(cat "$SHIMLOG"; ls "$REC")"
"$APKG" -c "$KCONF" install kernel-k46-zacd >/dev/null 2>&1
run 0 "remove by the pkginst works too" "$APKG" -c "$KCONF" remove KERNZACD
[ ! -f "$REC/KERNZACD" ] && ok "the record is gone" || bad "record left after remove KERNZACD"
# an interrupted install of it: the journal carries the record's file name
kreset; echo KERNZACD > "$WORK/kshim.die"
"$APKG" -c "$KCONF" install kernel-k46-zacd > /dev/null 2>&1
grep -q " KERNZACD$" "$TXN" 2>/dev/null \
    && ok "the journal records the record's file name (apkg-txn 3)" \
    || bad "journal reckey" "$(cat "$TXN" 2>&1)"
kreset
run 0 "recover finishes it" "$APKG" -c "$KCONF" recover
[ -f "$REC/KERNZACD" ] && grep -qx "name kernel-k46-zacd" "$REC/KERNZACD" \
    && ok "recover wrote the record under the pkginst" || bad "recover record" "$(ls "$REC")"
"$APKG" -c "$KCONF" remove kernel-k46-zacd >/dev/null 2>&1
mkkcat "$KR/catalog" "$KCAT_K110"
"$APKG" -c "$KCONF" update >/dev/null 2>&1

# --- upgrade with several names: ONE transaction, ONE trigger ---------
# The stage-2 exit row (amix-dlm S2-46) upgrades a kernel, the loader and
# kbootset together; with one name per call that was one generation per
# package.  Here: kernel-k46 1.1.0 -> 1.1.1, loader 3 -> 4, and the userland
# oldpkg 1.0 -> 2.0, in one call.
printf 'DIR /stand\nDIR /stand/loader\nFILE /stand/loader/boot1 b1v4\nFILE /stand/loader/boot2 b2v4\nFILE /stand/loader/ldrinfo version=4\n' \
    | python3 "$TESTS/mkds.py" "$KR/pkgs/kernel/loader-4.pkg" LOADER 4
KR3=$WORK/krepo3; mkdir -p "$KR3"; ln -sfn "$KR/pkgs" "$KR3/pkgs"
mkkcat "$KR3/catalog" "$(kline kernel-k46 1.1.1 kernel k46 k46.1.0 $PIN kernel/kernel-k46-1.1.1.pkg)"
sed -i "s|^#kpkg loader 3 role=loader line=any loader=3 size=[0-9]* sha256=[0-9a-f]* file=kernel/loader-3.pkg|#kpkg loader 4 role=loader line=any loader=4 size=$(sizeof "$KR/pkgs/kernel/loader-4.pkg") sha256=$(sha "$KR/pkgs/kernel/loader-4.pkg") file=kernel/loader-4.pkg|" "$KR3/catalog"
mkkconf "$WORK/conf-k3" "file://$KR3"
"$APKG" -c "$KCONF" install loader >/dev/null 2>&1
"$APKG" -c "$WORK/conf-k3" update >/dev/null 2>&1
cp "$ROOT/var/sadm/pkg/OLDPKG/pkginfo" "$WORK/oldpkg.pkginfo.save"
kreset
run 0 "upgrade kernel-k46 loader oldpkg: one call" \
    "$APKG" -c "$WORK/conf-k3" upgrade kernel-k46 loader oldpkg
[ "$(grep -c '^pkgadd .*admin.overwrite' "$SHIMLOG")" = 3 ] && \
grep -q " KERNK46$" "$SHIMLOG" && grep -q " LOADER$" "$SHIMLOG" && grep -q " OLDPKG$" "$SHIMLOG" \
    && ok "three pkgadds, each with instance=overwrite" \
    || bad "multi-upgrade pkgadds" "$(cat "$SHIMLOG")"
[ "$(cat "$KLOG")" = "kbootset --journal /var/kbootset/journal build
kbootset --journal /var/kbootset/journal commit" ] \
    && ok "ONE kbootset build + commit for the whole transaction" \
    || bad "multi-upgrade trigger" "$(cat "$KLOG")"
grep -qx "version 1.1.1" "$REC/kernel-k46" && grep -qx "loader 4" "$REC/LOADER" && [ ! -f "$TXN" ] \
    && ok "both records carry the new versions; the journal is gone" \
    || bad "records after the multi-upgrade" "$(cat "$REC/kernel-k46" "$REC/LOADER" 2>&1)"
echo "$OUT" | grep -q "kernel space: 2 packages in this transaction" \
    && ok "the transaction announces its two kernel-space packages once" \
    || bad "multi-upgrade announcement" "$OUT"
cp "$WORK/oldpkg.pkginfo.save" "$ROOT/var/sadm/pkg/OLDPKG/pkginfo"
kreset
run 0 "an up-to-date name is reported and left out, the rest upgrade" \
    "$APKG" -c "$WORK/conf-k3" upgrade samepkg oldpkg
echo "$OUT" | grep -q "samepkg is up to date" && [ "$(grep -c '^pkgadd' "$SHIMLOG")" = 1 ] \
    && grep -q " OLDPKG$" "$SHIMLOG" && [ ! -s "$KLOG" ] \
    && ok "samepkg skipped, oldpkg upgraded, no trigger for userland" \
    || bad "partial up-to-date multi-upgrade" "$OUT $(cat "$SHIMLOG" "$KLOG")"
cp "$WORK/oldpkg.pkginfo.save" "$ROOT/var/sadm/pkg/OLDPKG/pkginfo"
kreset
run 1 "a name that is not installed refuses the whole call (exit 1)" \
    "$APKG" -c "$WORK/conf-k3" upgrade oldpkg foo
[ ! -s "$SHIMLOG" ] && echo "$OUT" | grep -q "nothing was upgraded" \
    && ok "nothing was upgraded, and it says so" || bad "refusal touched something" "$OUT"
run 5 "a name not in the catalog refuses the whole call (exit 5)" \
    "$APKG" -c "$WORK/conf-k3" upgrade oldpkg nosuch
[ ! -s "$SHIMLOG" ] && ok "nothing ran" || bad "pkgadd ran after a refusal" "$(cat "$SHIMLOG")"
run 0 "everything already current: nothing to do" \
    "$APKG" -c "$WORK/conf-k3" upgrade kernel-k46 loader
[ ! -s "$SHIMLOG" ] && [ ! -s "$KLOG" ] && ok "no pkgadd and no trigger when nothing is newer" \
    || bad "an up-to-date upgrade ran something" "$(cat "$SHIMLOG" "$KLOG")"
"$APKG" -c "$KCONF" remove loader >/dev/null 2>&1
"$APKG" -c "$KCONF" update >/dev/null 2>&1

# --- userland through the new client: no trigger, no journal left ---
kreset
run 0 "a userland install through the kernel-space catalog" \
    "$APKG" -c "$KCONF" -f install foo
[ ! -s "$KLOG" ] && [ ! -f "$TXN" ] \
    && ok "userland: no kbootset call, no journal left" || bad "userland touched kspace" "$(cat "$KLOG")"
rm -rf "$REC" "$ROOT$KT" "$ROOT/stand" "$ROOT/var/sadm/install/contents" \
       "$ROOT/var/sadm/pkg/KERNK46" "$ROOT/var/sadm/pkg/Z3660SCS"
"$APKG" update >/dev/null 2>&1    # the plain catalog for what follows

# ------------------------------------------------ exit-code sanity extras
run 1 "unknown verb fails with exit 1" "$APKG" frobnicate
run 1 "missing -c file fails with exit 1" "$APKG" -c /nonexistent-conf list
run 0 "version verb works" "$APKG" version

# ------------------------------------------------ summary
echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
