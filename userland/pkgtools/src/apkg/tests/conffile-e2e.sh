#!/bin/bash
# conffile-e2e.sh - apkg's config-file handling against the real engine.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# apkg drives heirloom pkgadd/pkgrm/installf (-R, under fakeroot) from a
# FILE repository holding a toy package whose two conffiles carry
# ../conffile/i.conffile and r.conffile.  Walks P-36 W2: the report after
# a transaction, the questions at a terminal (on a pty, ptyrun.py), -y /
# --conf-keep / --conf-new, `apkg conffiles` and `conffiles resolve`,
# remove keeping edits, purge, and the config-files state.
#
# Needs heirloom/build-host.sh's engine, fakeroot and python3.
# Exit 0 all pass, 1 any failure, 77 skipped.

SRC=$(cd "$(dirname "$0")/.." && pwd)
TOP=$SRC/../..
HB=$TOP/heirloom/build-host/bin
VS=$(cd "$TOP/heirloom/build-host" 2>/dev/null && pwd)/var/sadm
GEN=$TOP/tools/repo/gen-catalog.py
CFS=$TOP/src/conffile
PTY=$SRC/tests/ptyrun.py

if [ ! -x "$HB/pkgadd" ] || ! command -v fakeroot >/dev/null 2>&1 ||
   ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: host engine (heirloom/build-host.sh), fakeroot or python3 missing"
    exit 77
fi
make -C "$SRC" host >/dev/null || { echo "host build failed"; exit 1; }

WORK=$(mktemp -d)
[ -n "${KEEP:-}" ] && echo "work: $WORK" || trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
check() {
    local what="$1"; shift
    if "$@"; then pass=$((pass + 1)); echo "  ok   $what"
    else fail=$((fail + 1)); echo "  FAIL $what"; fi
}

# ------------------------------------------------------------ packages ---
# mkpkg <version> <toy.conf default> <toy2.conf default>
mkpkg() {
    local v="$1" d="$WORK/src-$1"
    mkdir -p "$d" "$WORK/spool-$v" "$WORK/pkgs"
    printf '%s\n' "$2" > "$d/toy.conf"
    printf '%s\n' "$3" > "$d/toy2.conf"
    printf 'PKG=CONFT\nNAME=conffile test\nARCH=m68k\nVERSION=%s\nCATEGORY=utility\nCLASSES=none conffile\nBASEDIR=/\n' \
        "$v" > "$d/pkginfo"
    cat > "$d/prototype" <<EOF
i pkginfo=$d/pkginfo
i i.conffile=$CFS/i.conffile
i r.conffile=$CFS/r.conffile
e conffile /etc/toy.conf=$d/toy.conf 0644 root sys
e conffile /etc/toy2.conf=$d/toy2.conf 0644 root sys
EOF
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-$v" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-$v" "$WORK/pkgs/CONFT-$v.pkg" CONFT ) \
        >>"$WORK/mk.log" 2>&1
}
for v in 1 2 3 4 5 6; do
    mkpkg $v "v=$v" "two=$v" || { echo "FAIL: building CONFT-$v"; cat "$WORK/mk.log"; exit 1; }
done

# publish <version>: the FILE repository serves that one version
publish() {
    rm -rf "$WORK/repo"; mkdir -p "$WORK/repo/pkgs"
    cp "$WORK/pkgs/CONFT-$1.pkg" "$WORK/repo/pkgs/"
    python3 "$GEN" --packages-conf none -o "$WORK/repo" "$WORK/repo/pkgs" \
        >>"$WORK/gen.log" 2>&1
}

# ----------------------------------------------------------- the roots ---
# the client: its conf (-c), cache and admin file.  Not APKG_ROOT, which
# would prefix the -R target too.
C=$WORK/client
mkdir -p "$C/etc" "$C/var/apkg/cache"
cat > "$C/etc/apkg.conf" <<EOF
repo=$WORK/repo
cachedir=$C/var/apkg/cache
admin=$C/var/apkg/admin
pkgadd=$HB/pkgadd
pkgrm=$HB/pkgrm
EOF
# the target (-R): the host engine keeps its DB at <target>$VS, so the
# stock paths apkg reads are links to it
T=$WORK/t
mkdir -p "$T/etc" "$T$VS/pkg" "$T$VS/install" "$T/var/sadm"
printf 'root:x:%s:%s::/:/bin/sh\n' "$(id -u)" "$(id -g)" > "$T/etc/passwd"
printf 'root::%s:\nsys::%s:\n' "$(id -g)" "$(id -g)" > "$T/etc/group"
ln -s "$T$VS/pkg" "$T/var/sadm/pkg"
ln -s "$T$VS/install" "$T/var/sadm/install"
FS=$WORK/fakeroot.state; touch "$FS"

# ap [apkg options] <verb> ...: the conf and target come first
ap() { fakeroot -i "$FS" -s "$FS" "$SRC/apkg" -c "$C/etc/apkg.conf" -R "$T" "$@" \
        </dev/null >"$WORK/out" 2>&1; }
apty() { local ans="$1"; shift
        fakeroot -i "$FS" -s "$FS" python3 "$PTY" "$ans" \
        "$SRC/apkg" -c "$C/etc/apkg.conf" -R "$T" "$@" >"$WORK/out" 2>&1; }
says() { grep -qF -- "$1" "$WORK/out"; }
is() { test "$(cat "$1" 2>/dev/null)" = "$2"; }
pend() { cat "$T/var/sadm/conffiles/PENDING" 2>/dev/null; }
chk() { fakeroot -i "$FS" -s "$FS" "$HB/pkgchk" -R "$T" CONFT >"$WORK/chk.out" 2>&1; }
cdb() { echo "$T/var/sadm/install/contents"; }
upto() { publish "$1"; ap update >/dev/null; }

# ------------------------------------------------------------- install ---
echo "install and the report"
upto 1
ap install conft; check "install: rc 0" test $? -eq 0
check "  ... both defaults laid down" \
    bash -c "test \"\$(cat '$T/etc/toy.conf')\" = v=1 && test \"\$(cat '$T/etc/toy2.conf')\" = two=1"
check "  ... no config-file report" bash -c "! grep -q 'config files kept' '$WORK/out'"

# edited, upgrade with no terminal and no flag: reported, left pending
printf 'v=mine\n' > "$T/etc/toy.conf"
upto 2
ap upgrade conft; check "upgrade over an edit, no terminal: rc 0" test $? -eq 0
check "  ... the engine kept the edit" is "$T/etc/toy.conf" 'v=mine'
check "  ... the unedited one took its new default" is "$T/etc/toy2.conf" 'two=2'
check "  ... apkg lists it after the transaction" \
    says '/etc/toy.conf (CONFT): the new default is /etc/toy.conf.new'
check "  ... and says how to decide" says 'decide with: apkg conffiles resolve'
check "  ... it stays pending, .new in place" \
    bash -c "test \"\$(cat '$T/var/sadm/conffiles/PENDING')\" = 'CONFT /etc/toy.conf' && test -f '$T/etc/toy.conf.new'"

# ----------------------------------------------------------- conffiles ---
echo "apkg conffiles"
ap conffiles; check "conffiles: rc 0" test $? -eq 0
check "  ... lists the pending file" says 'CONFT      /etc/toy.conf                  pending'
check "  ... and not the unedited one" bash -c "! grep -q toy2 '$WORK/out'"
ap conffiles list conft; check "conffiles list <name>: the same, by catalog name" says '/etc/toy.conf'
ap conffiles resolve; check "conffiles resolve with no terminal and no flag: rc 1" test $? -eq 1
check "  ... says to give a flag" says 'give --conf-keep or --conf-new'
check "  ... nothing decided" test "$(pend)" = "CONFT /etc/toy.conf"
ap -n --conf-new conffiles resolve
check "-n --conf-new resolve: nothing changes" \
    bash -c "test \"\$(cat '$T/etc/toy.conf')\" = v=mine && test -f '$T/etc/toy.conf.new' && grep -q 'would install' '$WORK/out'"
ap --conf-keep conffiles resolve; check "--conf-keep resolve: rc 0" test $? -eq 0
check "  ... keeps yours" is "$T/etc/toy.conf" 'v=mine'
check "  ... removes the .new and the PENDING line" \
    bash -c "test ! -e '$T/etc/toy.conf.new' && test -z \"\$(cat '$T/var/sadm/conffiles/PENDING')\""
ap conffiles; check "  ... conffiles now shows it as edited" says 'CONFT      /etc/toy.conf                  edited'

# ----------------------------------------------------------- --conf-new ---
echo "--conf-new"
upto 3
ap --conf-new upgrade conft; check "--conf-new upgrade: rc 0" test $? -eq 0
check "  ... the new default is installed" is "$T/etc/toy.conf" 'v=3'
check "  ... yours is <file>.old" is "$T/etc/toy.conf.old" 'v=mine'
check "  ... no .new, nothing pending" \
    bash -c "test ! -e '$T/etc/toy.conf.new' && test -z \"\$(cat '$T/var/sadm/conffiles/PENDING')\""
chk; check "  ... installf re-registered it: plain pkgchk clean" test $? -eq 0
check "  ... in class conffile" grep -q '^/etc/toy.conf e conffile ' "$(cdb)"

# ------------------------------------------------- questions on a pty ---
echo "questions at a terminal"
printf 'v=mine\n' > "$T/etc/toy.conf"
upto 4
apty 'd,n' upgrade conft; check "upgrade at a terminal: rc 0" test $? -eq 0
check "  ... it asked" says '[k]eep yours, install the [n]ew default, show the [d]iff, or decide [l]ater? [k]'
check "  ... d showed the diff of yours against the new default" \
    bash -c "grep -q '^< v=mine' '$WORK/out' && grep -q '^> v=4' '$WORK/out'"
check "  ... n installed the new default" is "$T/etc/toy.conf" 'v=4'
printf 'v=mine\n' > "$T/etc/toy.conf"
upto 5
apty 'l' upgrade conft
check "l (later): kept, still pending" \
    bash -c "test \"\$(cat '$T/etc/toy.conf')\" = v=mine && grep -q '^CONFT /etc/toy.conf\$' '$T/var/sadm/conffiles/PENDING'"
apty '' conffiles resolve; check "Enter at resolve: rc 0" test $? -eq 0
check "  ... keep is the default answer" \
    bash -c "test \"\$(cat '$T/etc/toy.conf')\" = v=mine && test ! -e '$T/etc/toy.conf.new' && test -z \"\$(cat '$T/var/sadm/conffiles/PENDING')\""

# -y keeps without asking, even at a terminal
upto 6
apty 'n' -y upgrade conft
check "-y at a terminal: no question" bash -c "! grep -qF '[k] ' '$WORK/out'"
check "  ... kept, .new removed" \
    bash -c "test \"\$(cat '$T/etc/toy.conf')\" = v=mine && test ! -e '$T/etc/toy.conf.new'"

# ------------------------------------------------ remove, config-files ---
echo "remove keeps edits; the config-files state; purge"
ap remove conft; check "remove: rc 0" test $? -eq 0
check "  ... the edited file is kept" is "$T/etc/toy.conf" 'v=mine'
check "  ... the unedited one is gone" test ! -e "$T/etc/toy2.conf"
ap list installed
check "list installed shows [config-files]" says '[config-files]'
ap info conft; check "info says config-files" says 'Installed:   no (config-files'
ap conffiles; check "conffiles marks the package removed" says '(package removed)'
ap -n purge conft
check "-n purge changes nothing" \
    bash -c "test -f '$T/etc/toy.conf' && test -d '$T/var/sadm/conffiles/CONFT'"
ap purge conft; check "purge: rc 0" test $? -eq 0
check "  ... the kept file is deleted" test ! -e "$T/etc/toy.conf"
check "  ... and its .old" test ! -e "$T/etc/toy.conf.old"
check "  ... and its baselines" test ! -e "$T/var/sadm/conffiles/CONFT"
ap list installed
check "  ... no longer listed" bash -c "! grep -q conft '$WORK/out'"
ap purge conft; check "purge again: rc 1, nothing to purge" test $? -eq 1
check "  ... says so" says 'is not installed and has no config files'

# remove --purge on an installed package
ap install conft >/dev/null; printf 'v=mine\n' > "$T/etc/toy.conf"
ap remove --purge conft; check "remove --purge: rc 0" test $? -eq 0
check "  ... package and edited file both gone" \
    bash -c "test ! -e '$T/etc/toy.conf' && test ! -d '$T/var/sadm/pkg/CONFT' && test ! -e '$T/var/sadm/conffiles/CONFT'"

echo
echo "== conffile e2e: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
