#!/bin/bash
# partial.sh - an upgrade cut short, and the plain `apkg upgrade` that
# repairs it, against the real engine.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# PART 1 ships /etc/p/{edit,touch}.conf as plain files and a tree of data
# files; PART 2 ships the two as `e conffile` (../conffile/i.conffile), a
# class "slow" laid before them, and one interruption point per variant:
# the file laydown, the class action script, the postinstall, a failing
# preinstall; and the record an update moves aside (.save.PART) before it
# writes the new one, made here as the engine does it (the host engine
# runs no checkinstall script as a non-root user, so that window is not
# cut for real here).  Each is cut two ways: apkg killed with the engine (a power
# loss: the journal stays) and the engine alone (apkg sees pkgadd fail).
# Then one `apkg upgrade` (or `apkg recover`) must finish the package:
# the engine's !I-Lock! gone, pkgchk clean, the edited config file kept
# with .new, the untouched one at the new default.
#
# Needs heirloom/build-host.sh's engine, fakeroot and python3.
# Exit 0 all pass, 1 any failure, 77 skipped.

SRC=$(cd "$(dirname "$0")/.." && pwd)
TOP=$SRC/../..
HB=$TOP/heirloom/build-host/bin
VS=$(cd "$TOP/heirloom/build-host" 2>/dev/null && pwd)/var/sadm
GEN=$TOP/tools/repo/gen-catalog.py
CFS=$TOP/src/conffile

if [ ! -x "$HB/pkgadd" ] || ! command -v fakeroot >/dev/null 2>&1 ||
   ! command -v python3 >/dev/null 2>&1 || ! command -v pkill >/dev/null 2>&1; then
    echo "SKIP: host engine (heirloom/build-host.sh), fakeroot, python3 or pkill missing"
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

# ------------------------------------------------------------ packages ---
NDATA=400
HALF=200
LAST=$(printf '%04d' $NDATA)
# mkpkg <version> <stall: none|lay|cas|post|prefail>
mkpkg() {
    local v="$1" st="$2" d="$WORK/src-$1-$2" cls=none t=f i
    mkdir -p "$d/data" "$WORK/spool-$v-$st" "$WORK/pkgs"
    [ "$v" = 2 ] && { cls=conffile; t=e; }
    printf 'edit=%s\n' "$v" > "$d/edit.conf"
    printf 'touch=%s\n' "$v" > "$d/touch.conf"
    printf 'slow=%s\n' "$v" > "$d/slow"
    for i in $(seq -f %04g 1 $NDATA); do printf 'data %s %s\n' "$v" "$i" > "$d/data/f$i"; done
    printf 'mid=%s\n' "$v" > "$d/mid"
    printf 'PKG=PART\nNAME=partial test\nARCH=m68k\nVERSION=%s\nCATEGORY=utility\nCLASSES=none mid late slow conffile\nBASEDIR=/\n' \
        "$v" > "$d/pkginfo"
    # the stall, while <root>/STALLOK exists: a file made, then a long
    # sleep (the test kills it); without STALLOK the same datastream
    # installs straight through, so a journal can finish it
    printf '[ -f "$PKG_INSTALL_ROOT/STALLOK" ] || exit 0\ntouch "$PKG_INSTALL_ROOT/STALL"; sleep 120\n' > "$d/stall"
    printf 'if [ -f "$PKG_INSTALL_ROOT/FAIL" ]; then echo "preinstall: refusing"; exit 1; fi\nexit 0\n' > "$d/prefail"
    # i.slow lays its objects with the pkgmap's mode and mtime
    printf 'while read s d; do cp "$s" "$d"; chmod 644 "$d"; touch -r "$s" "$d"; done\n' > "$d/i.slow"
    # i.mid sits between the two halves of the tree, which the engine
    # lays itself (classes none and late): the lay variant stalls there,
    # so the cut leaves half the tree new and half old
    cp "$d/i.slow" "$d/i.mid"
    if [ "$st" = cas ]; then
        printf '[ -f "$PKG_INSTALL_ROOT/STALLOK" ] || exit 0\ntouch "$PKG_INSTALL_ROOT/STALL"; sleep 120\n' >> "$d/i.slow"
    else
        printf 'exit 0\n' >> "$d/i.slow"
    fi
    if [ "$st" = lay ]; then
        printf '[ -f "$PKG_INSTALL_ROOT/STALLOK" ] || exit 0\ntouch "$PKG_INSTALL_ROOT/STALL"; sleep 120\n' >> "$d/i.mid"
    else
        printf 'exit 0\n' >> "$d/i.mid"
    fi
    {
        echo "i pkginfo=$d/pkginfo"
        echo "i i.conffile=$CFS/i.conffile"
        echo "i r.conffile=$CFS/r.conffile"
        echo "i i.slow=$d/i.slow"
        echo "i i.mid=$d/i.mid"
        [ "$st" = post ] && echo "i postinstall=$d/stall"
        [ "$st" = prefail ] && echo "i preinstall=$d/prefail"
        echo "d none /usr/p 0755 root sys"
        for i in $(seq -f %04g 1 $HALF); do echo "f none /usr/p/f$i=$d/data/f$i 0644 root sys"; done
        echo "f mid /etc/p/mid=$d/mid 0644 root sys"
        for i in $(seq -f %04g $((HALF + 1)) $NDATA); do echo "f late /usr/p/f$i=$d/data/f$i 0644 root sys"; done
        echo "f slow /etc/p/slow=$d/slow 0644 root sys"
        echo "$t $cls /etc/p/edit.conf=$d/edit.conf 0644 root sys"
        echo "$t $cls /etc/p/touch.conf=$d/touch.conf 0644 root sys"
    } > "$d/prototype"
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-$v-$st" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-$v-$st" "$WORK/pkgs/PART-$v-$st/PART-$v.pkg" PART ) \
        >>"$WORK/mk.log" 2>&1
}
for st in none lay cas post prefail; do mkdir -p "$WORK/pkgs/PART-2-$st"; done
mkdir -p "$WORK/pkgs/PART-1-none"
mkpkg 1 none && for st in none lay cas post prefail; do mkpkg 2 $st || break; done ||
    { echo "FAIL: building the packages"; cat "$WORK/mk.log"; exit 1; }

# publish <dir under pkgs/>: the FILE repository serves that one datastream
publish() {
    rm -rf "${WORK:?}/repo"; mkdir -p "$WORK/repo/pkgs"
    cp "$WORK/pkgs/$1/"*.pkg "$WORK/repo/pkgs/"
    python3 "$GEN" --packages-conf none --kbootset-table none -o "$WORK/repo" \
        "$WORK/repo/pkgs" >>"$WORK/gen.log" 2>&1
}

# ----------------------------------------------------------- the roots ---
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
ap() { fakeroot -i "$FS" -s "$FS" "$NEW" -c "$C/etc/apkg.conf" -R "$T" "$@" </dev/null >"$R/out" 2>&1; }
apbg() { fakeroot -i "$FS" -s "$FS" "$NEW" -c "$C/etc/apkg.conf" -R "$T" "$@" </dev/null >"$R/cut.out" 2>&1 & }
says() { grep -qF -- "$1" "$R/out"; }
is() { test "$(cat "$1" 2>/dev/null)" = "$2"; }
lockf() { echo "$T/var/sadm/pkg/PART/!I-Lock!"; }
savef() { echo "$T/var/sadm/pkg/.save.PART"; }
chk() { fakeroot -i "$FS" -s "$FS" "$HB/pkgchk" -R "$T" PART >"$R/chk.out" 2>&1; }
# set up: PART 1 installed by apkg, edit.conf edited
setup() {
    newroot "$1"; publish PART-1-none; ap update; ap install part
    printf 'edit=mine\n' > "$T/etc/p/edit.conf"
}
# cut <variant> <how: all|engine>: start `apkg upgrade` to PART 2 <variant>
# and kill at its stall (lay: between the two halves of the tree); all = apkg
# with the engine (the journal stays: a power loss), engine = pkgadd and
# pkginstall only (apkg sees the pkgadd fail)
cut() {
    local st="$1" how="$2" i
    publish "PART-2-$st"; ap update
    rm -f "$T/STALL"; touch "$T/STALLOK"
    apbg upgrade
    for i in $(seq 1 1200); do [ -f "$T/STALL" ] && break; sleep 0.05; done
    [ "$how" = all ] && pkill -9 -f "^$NEW -c $C/etc/apkg.conf"
    pkill -9 -f "build-host/.*-R $T"
    pkill -9 -f "sleep 120" 2>/dev/null
    wait 2>/dev/null
    sleep 0.3
    rm -f "$T/STALLOK"
}
# the repaired state
repaired() {
    local tag="$1"
    check "$tag: no !I-Lock! left" test ! -e "$(lockf)"
    check "$tag: no record left moved aside (.save.PART)" test ! -e "$(savef)"
    check "$tag: pkginfo says 2" grep -q '^VERSION=2$' "$T/var/sadm/pkg/PART/pkginfo"
    chk; check "$tag: pkgchk PART clean" test $? -eq 0
    check "$tag: the tree is version 2" bash -c "grep -q 'data 2' '$T/usr/p/f0001' && grep -q 'data 2' '$T/usr/p/f$LAST' && test \"\$(cat '$T/etc/p/slow')\" = slow=2"
    check "$tag: the edited config file kept, .new beside it" \
        bash -c "test \"\$(cat '$T/etc/p/edit.conf')\" = edit=mine && test \"\$(cat '$T/etc/p/edit.conf.new')\" = edit=2"
    check "$tag: the untouched one at the new default, no .new" \
        bash -c "test \"\$(cat '$T/etc/p/touch.conf')\" = touch=2 && test ! -e '$T/etc/p/touch.conf.new'"
    check "$tag: PENDING holds the edited file only" \
        test "$(cat "$T/var/sadm/conffiles/PENDING" 2>/dev/null)" = "PART /etc/p/edit.conf"
    check "$tag: no journal left" test ! -e "$T/var/apkg/txn"
}

# ------------------------------------------------------------- the cuts ---
for st in lay cas post; do
    for how in all engine; do
        tag="$st/$how"
        echo "cut in the ${st} step, killing ${how}"
        setup "r-$st-$how"
        cut "$st" "$how"
        check "$tag: the engine left its !I-Lock!" test -e "$(lockf)"
        [ "$st" = lay ] && check "$tag: the cut left the first half new, the second old" \
            bash -c "grep -q 'data 2' '$T/usr/p/f0001' && grep -q 'data 1' '$T/usr/p/f$LAST'"
        if [ "$how" = all ]; then
            check "$tag: the journal stays" test -e "$T/var/apkg/txn"
        else
            check "$tag: apkg saw the pkgadd stop part-way and says so; no journal" \
                bash -c "test ! -e '$T/var/apkg/txn' && grep -q 'pkgadd of part 2 stopped part-way: part is partially installed' '$R/cut.out' && grep -q \"'apkg upgrade part' lays it again\" '$R/cut.out'"
        fi
        ap list installed
        check "$tag: list shows it [partial]" says "[partial]"
        ap info part
        check "$tag: info says partially installed" says "Installed:   partially: an install was cut short"
        # the repair: a plain upgrade, the repository as it was
        ap upgrade; rc=$?
        cp "$R/out" "$R/repair.out"
        check "$tag: apkg upgrade repairs it (rc 0)" test $rc -eq 0
        if [ "$how" = all ]; then
            check "$tag: ... finishing the journaled transaction first" \
                says "finishing the interrupted transaction first (apkg recover)"
        else
            check "$tag: ... naming the partial package" \
                says "part is partially installed (an install was cut short); installing 2 again"
        fi
        repaired "$tag"
        ap upgrade
        check "$tag: the next upgrade has nothing to do" says "every installed package is up to date"
    done
done

echo "a power loss, and the repository has moved on since"
setup r-moved
cut cas all
check "moved: the journal stays" test -e "$T/var/apkg/txn"
publish PART-2-none; ap update
ap upgrade; rc=$?
cp "$R/out" "$R/repair.out"
check "moved: apkg upgrade repairs it (rc 0)" test $rc -eq 0
check "moved: ... saying the journal's datastream changed and installing from the catalog" \
    bash -c "grep -q 'no longer matches its md5' '$R/out' && grep -q 'the journal is dropped' '$R/out' && grep -q 'part is partially installed' '$R/out'"
repaired moved

echo "a failing preinstall, then the upgrade again"
setup r-prefail
publish PART-2-prefail; ap update
touch "$T/FAIL"
ap upgrade; check "prefail: apkg upgrade rc 4" test $? -eq 4
check "prefail: the engine left its !I-Lock! and pkginfo says 2 already" \
    bash -c "test -e '$(lockf)' && grep -q '^VERSION=2$' '$T/var/sadm/pkg/PART/pkginfo'"
ap upgrade
check "prefail: while it still fails, the upgrade tries again (rc 4), not 'up to date'" \
    bash -c "! grep -q 'up to date' '$R/out' && grep -q 'part is partially installed' '$R/out'"
rm -f "$T/FAIL"
ap upgrade; check "prefail: once the preinstall passes, apkg upgrade repairs it (rc 0)" test $? -eq 0
repaired prefail

echo "apkg recover with no journal repairs a partial package"
setup r-recover
cut cas engine
ap recover; check "recover: rc 0" test $? -eq 0
check "recover: says there is no journal, then installs the package again" \
    bash -c "grep -q 'no unfinished transaction' '$R/out' && grep -q 'part is partially installed' '$R/out'"
repaired recover

echo "the installed record moved aside (.save.PART), none in its place"
setup r-save
publish PART-2-none; ap update
mv "$T/var/sadm/pkg/PART" "$(savef)"
ap list installed
check "save: list shows it [partial]" says "[partial]"
ap info part
check "save: info says partially installed" says "Installed:   partially: an install was cut short"
ap upgrade; rc=$?
cp "$R/out" "$R/repair.out"
check "save: apkg upgrade repairs it (rc 0)" test $rc -eq 0
check "save: ... naming the partial package" says "part is partially installed (an install was cut short); installing 2 again"
repaired save

echo "a package directory without pkginfo is not taken for a partial install"
setup r-stock
# stock 2.1 keeps such directories (bnu, face, nsu on a 1.1.1 disk)
mkdir -p "$T/var/sadm/pkg/bnu/install"; : > "$T/var/sadm/pkg/bnu/install/depend"
ap upgrade; check "stock: apkg upgrade rc 0" test $? -eq 0
check "stock: no word about bnu" bash -c "! grep -q bnu '$R/out'"
ap list installed
check "stock: PART is not partial" bash -c "! grep -qF '[partial]' '$R/out'"

echo
echo "== partial: $pass passed, $fail failed =="
[ $fail -eq 0 ]
