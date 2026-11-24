#!/bin/bash
# depfloor.sh - a dependency's floor ("name>=version" in the catalog's
# deps field, apkg 0.3.14) against the real engine.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# Real datastreams (host pkgmk/pkgtrans), a catalog from gen-catalog.py
# (the floor from the package's APKG_DEPS), the host pkgadd under fakeroot.
# LIB 1.0 is installed; APP needs LIB 2.0 or newer.  Four cases:
# the dependency missing, installed and new enough, installed and too old,
# and the floor above what the repository has (refused, nothing changed).
# Then the same catalog read by the apkg of the release tags, when the
# clone has them: it reads every row and refuses APP as a missing
# dependency, nothing installed.
#
# Needs heirloom/build-host.sh's engine, fakeroot and python3.
# Exit 0 all pass, 1 any failure, 77 skipped.

SRC=$(cd "$(dirname "$0")/.." && pwd)
TOP=$SRC/../..
HB=$TOP/heirloom/build-host/bin
VS=$(cd "$TOP/heirloom/build-host" 2>/dev/null && pwd)/var/sadm
GEN=$TOP/tools/repo/gen-catalog.py

if [ ! -x "$HB/pkgadd" ] || ! command -v fakeroot >/dev/null 2>&1 ||
   ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: host engine (heirloom/build-host.sh), fakeroot or python3 missing"
    exit 77
fi
make -C "$SRC" host >/dev/null || { echo "host build failed"; exit 1; }
NEW=$SRC/apkg

WORK=$(mktemp -d)
[ -n "${KEEP:-}" ] && echo "work: $WORK" || trap 'rm -rf "${WORK:?}"' EXIT
pass=0; fail=0
check() {
    local what="$1"; shift
    if "$@"; then pass=$((pass + 1)); echo "  ok   $what"
    else fail=$((fail + 1)); echo "  FAIL $what"; fi
}

# mkpkg <PKG> <version> [APKG_DEPS]: /opt/df/<pkg> holds "<PKG> <version>"
mkpkg() {
    local p="$1" v="$2" d="$WORK/src-$1-$2"
    mkdir -p "$d" "$WORK/spool-$p-$v" "$WORK/pkgs"
    printf '%s %s\n' "$p" "$v" > "$d/payload"
    printf 'PKG=%s\nNAME=floor test %s\nARCH=m68k\nVERSION=%s\nCATEGORY=utility\nCLASSES=none\n' \
        "$p" "$p" "$v" > "$d/pkginfo"
    [ -n "${3:-}" ] && printf 'APKG_DEPS=%s\n' "$3" >> "$d/pkginfo"
    {
        echo "i pkginfo=$d/pkginfo"
        echo "d none /opt 0755 root sys"
        echo "d none /opt/df 0755 root sys"
        echo "f none /opt/df/$p=$d/payload 0644 root sys"
    } > "$d/prototype"
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-$p-$v" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-$p-$v" "$WORK/pkgs/$p-$v.pkg" "$p" ) \
        >>"$WORK/mk.log" 2>&1
}
mkpkg LIB 1.0 && mkpkg LIB 2.0 && mkpkg APP 0.9 && mkpkg APP 1.0 'lib>=2.0' &&
    mkpkg BIG 1.0 'lib>=3.0' && mkpkg OK 1.0 'lib>=1.0' ||
    { echo "FAIL: building the packages"; cat "$WORK/mk.log"; exit 1; }

# publish <file>...: the FILE repository serves those datastreams
publish() {
    rm -rf "${WORK:?}/repo"; mkdir -p "$WORK/repo/pkgs"
    for f in "$@"; do cp "$WORK/pkgs/$f" "$WORK/repo/pkgs/"; done
    python3 "$GEN" --packages-conf none --kbootset-table none -o "$WORK/repo" \
        "$WORK/repo/pkgs" >>"$WORK/gen.log" 2>&1
}

newroot() {
    R=$WORK/$1; C=$R/client; T=$R/t
    mkdir -p "$C/etc" "$C/var/apkg/cache" "$T/etc" "$T$VS/pkg" "$T$VS/install" "$T/var/sadm"
    cat > "$C/etc/apkg.conf" <<EOF
repo=$WORK/repo
cachedir=$C/var/apkg/cache
admin=$C/var/apkg/admin
pkgadd=$HB/pkgadd
pkgrm=$HB/pkgrm
EOF
    printf 'root:x:%s:%s::/:/bin/sh\n' "$(id -u)" "$(id -g)" > "$T/etc/passwd"
    printf 'root::%s:\nsys::%s:\n' "$(id -g)" "$(id -g)" > "$T/etc/group"
    ln -s "$T$VS/pkg" "$T/var/sadm/pkg"
    ln -s "$T$VS/install" "$T/var/sadm/install"
    FS=$R/fakeroot.state; touch "$FS"
}
ap() { fakeroot -i "$FS" -s "$FS" "${A:-$NEW}" -c "$C/etc/apkg.conf" -R "$T" "$@" </dev/null >"$R/out" 2>&1; }
says() { grep -qF -- "$1" "$R/out"; }
ver() { sed -n 's/^VERSION=//p' "$T/var/sadm/pkg/$1/pkginfo" 2>/dev/null; }
pay() { cat "$T/opt/df/$1" 2>/dev/null; }
# a root with LIB 1.0 installed by apkg
lib1() { newroot "$1"; publish LIB-1.0.pkg; ap update; ap install lib; }

echo "the catalog"
publish LIB-2.0.pkg APP-1.0.pkg BIG-1.0.pkg OK-1.0.pkg
check "gen-catalog writes APP's floor from APKG_DEPS" \
    grep -q '^app|1.0|APP|APP-1.0.pkg|.*|lib>=2.0|' "$WORK/repo/catalog"

echo "1. the dependency missing"
newroot r1; ap update
ap install app; rc=$?
check "install app: rc 0" test $rc -eq 0
check "LIB 2.0 and APP 1.0 installed" bash -c "test '$(ver LIB)' = 2.0 && test '$(ver APP)' = 1.0 && test '$(pay LIB)' = 'LIB 2.0'"

echo "2. installed and new enough"
lib1 r2; publish LIB-2.0.pkg APP-1.0.pkg BIG-1.0.pkg OK-1.0.pkg; ap update
ap install ok; rc=$?
check "install ok: rc 0" test $rc -eq 0
check "LIB stays 1.0, the newer one reported" \
    bash -c "test '$(ver LIB)' = 1.0 && test '$(pay LIB)' = 'LIB 1.0' && grep -qF 'lib 1.0 installed, catalog has 2.0 (dependency satisfied' '$R/out'"

echo "3. installed and too old"
lib1 r3; publish LIB-2.0.pkg APP-1.0.pkg BIG-1.0.pkg OK-1.0.pkg; ap update
ap install app; rc=$?
check "install app: rc 0" test $rc -eq 0
check "it says what it upgrades and why" says "upgrading lib 1.0 -> 2.0 (app 1.0 needs 2.0 or newer)"
check "LIB 2.0 over its instance (one LIB record), then APP" \
    bash -c "test '$(ver LIB)' = 2.0 && test '$(pay LIB)' = 'LIB 2.0' && test '$(ver APP)' = 1.0 && test \$(ls '$T/var/sadm/pkg' | grep -c '^LIB') = 1"
check "no journal left" test ! -e "$T/var/apkg/txn"

echo "4. the floor above what the repository has"
lib1 r4; publish LIB-2.0.pkg APP-1.0.pkg BIG-1.0.pkg OK-1.0.pkg; ap update
ap install big; rc=$?
check "install big: rc 5" test $rc -eq 5
check "it names the floor and the catalog's version" says "big 1.0 needs lib 3.0 or newer; the catalog has lib 2.0"
check "nothing changed: LIB 1.0, no BIG, nothing fetched" \
    bash -c "test '$(ver LIB)' = 1.0 && test ! -e '$T/var/sadm/pkg/BIG' && test -z \"\$(ls '$C/var/apkg/cache')\""

echo "upgrade by name: APP 0.9 (no floor) -> 1.0 (lib>=2.0), LIB 1.0 installed"
newroot r5; publish LIB-1.0.pkg APP-0.9.pkg; ap update; ap install lib app
check "set up: LIB 1.0 and APP 0.9" bash -c "test '$(ver LIB)' = 1.0 && test '$(ver APP)' = 0.9"
publish LIB-2.0.pkg APP-1.0.pkg; ap update
ap upgrade app; rc=$?
check "upgrade app: rc 0, LIB upgraded for the floor" \
    bash -c "test $rc -eq 0 && grep -qF 'upgrading lib 1.0 -> 2.0 (app 1.0 needs 2.0 or newer)' '$R/out'"
check "LIB 2.0 and APP 1.0, one record each" \
    bash -c "test '$(ver LIB)' = 2.0 && test '$(ver APP)' = 1.0 && test \$(ls '$T/var/sadm/pkg' | grep -c '^LIB') = 1 && test \$(ls '$T/var/sadm/pkg' | grep -c '^APP') = 1"

# the release tags' apkg: the catalog is read, APP refused, nothing installed
GT=$(git -C "$SRC" rev-parse --show-toplevel 2>/dev/null)
for tag in 1.1.1 1.1.2; do
    t=$(git -C "$SRC" rev-parse -q --verify "$tag^{}:userland/pkgtools/src/apkg" 2>/dev/null) || {
        echo "  skip- apkg of tag $tag (not in this clone)"; continue; }
    d=$WORK/old-$tag; mkdir -p "$d"
    git -C "$GT" archive "$tag" userland/pkgtools/src/apkg | tar -x -C "$d" --strip-components=4 &&
        make -C "$d" apkg >"$d/build.log" 2>&1 || { echo "  FAIL building apkg of $tag"; fail=$((fail + 1)); continue; }
    v=$("$d/apkg" version)
    echo "$v (tag $tag)"
    lib1 "o-$tag"; publish LIB-2.0.pkg APP-1.0.pkg BIG-1.0.pkg OK-1.0.pkg
    A=$d/apkg ap update
    check "$v reads every row" says "catalog updated: 4 packages"
    A=$d/apkg ap install app; rc=$?
    check "$v refuses app as a missing dependency (rc 5), nothing installed" \
        bash -c "test $rc -eq 5 && grep -qF 'missing dependency: lib>=2.0 (needed by app)' '$R/out' && test '$(ver LIB)' = 1.0 && test ! -e '$T/var/sadm/pkg/APP'"
done

echo
echo "depfloor: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
