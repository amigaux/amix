#!/bin/bash
# conffile-gain.sh - an upgrade that turns plain files into conffiles,
# against the real engine.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT license - see ../LICENSE.
#
# GAINT 1 ships its files as `f none`; GAINT 2 ships them as `e conffile`
# with ../conffile/i.conffile and r.conffile.  An upgrade is one pkgadd
# over the installed instance.  Walks: an edited file kept with .new, an
# untouched one replaced silently (the baseline apkg stores before the
# pkgadd), an untouched one whose default did not change, a reordering
# edit that keeps size and sum, a relative path under BASEDIR, a symlink
# that becomes a conffile, a failed and a cut pkgadd, `apkg recover`,
# removal, the postinstall hook (`apkg conffiles prepare`) under the
# released apkg 0.3.11, a package that sorts before it, a package without
# conffiles (the same output as 0.3.11), and the package tools first with
# the re-exec of the new apkg.
#
# Needs heirloom/build-host.sh's engine, fakeroot, python3 and git (for
# 0.3.11, built from the tag 1.1).  Exit 0 all pass, 1 any failure, 77
# skipped.

SRC=$(cd "$(dirname "$0")/.." && pwd)
TOP=$SRC/../..
HB=$TOP/heirloom/build-host/bin
VS=$(cd "$TOP/heirloom/build-host" 2>/dev/null && pwd)/var/sadm
GEN=$TOP/tools/repo/gen-catalog.py
CFS=$TOP/src/conffile

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

# the released apkg 0.3.11 (tag 1.1), for the old-client rows
OLD=
if git -C "$SRC" rev-parse -q --verify 'refs/tags/1.1^{commit}' >/dev/null 2>&1; then
    mkdir -p "$WORK/old"
    GTOP=$(git -C "$SRC" rev-parse --show-toplevel)
    GPFX=$(git -C "$SRC" rev-parse --show-prefix)
    GPFX=${GPFX%/}
    if git -C "$GTOP" archive --format=tar 1.1 "$GPFX" |
       tar -x -C "$WORK/old" --strip-components="$(echo "$GPFX" | awk -F/ '{print NF}')" &&
       make -C "$WORK/old" host >/dev/null 2>&1; then
        OLD=$WORK/old/apkg
    fi
fi

# ------------------------------------------------------------ packages ---
# mkpkg <PKG> <version> <class of the files: none|conffile> <defaults dir>
# [preinstall]: /etc/g/{edit,touch,same,swap,mode}.conf and usr/g/app.def
# (relative, under BASEDIR); LINKT instead: /etc/g/link.conf, a symlink in
# class none that becomes a conffile
mkpkg() {
    local P="$1" v="$2" cls="$3" dd="$4" pre="$5" d="$WORK/src-$1-$2"
    local t=f
    [ "$cls" = conffile ] && t=e
    mkdir -p "$d" "$WORK/spool-$P-$v" "$WORK/pkgs"
    printf 'PKG=%s\nNAME=gain test\nARCH=m68k\nVERSION=%s\nCATEGORY=utility\nCLASSES=none conffile\nBASEDIR=/\n' \
        "$P" "$v" > "$d/pkginfo"
    {
        echo "i pkginfo=$d/pkginfo"
        echo "i i.conffile=$CFS/i.conffile"
        echo "i r.conffile=$CFS/r.conffile"
        [ -n "$pre" ] && echo "i preinstall=$pre"
        for f in edit touch same swap mode; do
            echo "$t $cls /etc/g/$f.conf=$dd/$f.conf 0644 root sys"
        done
        echo "$t $cls usr/g/app.def=$dd/app.def 0644 root sys"
    } > "$d/prototype"
    if [ "$P" = LINKT ]; then
        {   echo "i pkginfo=$d/pkginfo"
            echo "i i.conffile=$CFS/i.conffile"
            echo "i r.conffile=$CFS/r.conffile"
            if [ "$cls" = none ]; then
                echo "f none /etc/g/link-target=$dd/link-target 0644 root sys"
                echo "s none /etc/g/link.conf=link-target"
            else
                echo "e conffile /etc/g/link.conf=$dd/link.conf 0644 root sys"
            fi
        } > "$d/prototype"
    fi
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-$P-$v" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-$P-$v" "$WORK/pkgs/$P-$v.pkg" "$P" ) \
        >>"$WORK/mk.log" 2>&1
}
D1=$WORK/d1; D2=$WORK/d2; mkdir -p "$D1" "$D2"
for f in edit touch mode app; do printf '%s=1\n' "$f" > "$D1/$f.conf"; done
mv "$D1/app.conf" "$D1/app.def"
printf 'same=1\n' > "$D1/same.conf"; cp -p "$D1/same.conf" "$D2/same.conf"
printf 'alpha\nbeta\n' > "$D1/swap.conf"
printf 'L=1\n' > "$D1/link-target"
for f in edit touch mode app link; do printf '%s=2\n' "$f" > "$D2/$f.conf"; done
mv "$D2/app.conf" "$D2/app.def"
printf 'alpha\nbeta\ngamma\n' > "$D2/swap.conf"
# a preinstall that fails while <root>/FAIL exists
cat > "$WORK/pre-fail" <<'EOF'
if [ -f "$PKG_INSTALL_ROOT/FAIL" ]; then echo "preinstall: refusing"; exit 1; fi
exit 0
EOF
for P in GAINT AAGAIN; do
    mkpkg $P 1 none "$D1" "" && mkpkg $P 2 conffile "$D2" "$WORK/pre-fail" ||
        { echo "FAIL: building $P"; cat "$WORK/mk.log"; exit 1; }
done
mkpkg LINKT 1 none "$D1" "" && mkpkg LINKT 2 conffile "$D2" "" ||
    { echo "FAIL: building LINKT"; cat "$WORK/mk.log"; exit 1; }

# PLAIN 1 -> 2: no conffile at all
mkplain() {
    local v="$1" d="$WORK/src-PLAIN-$1"
    mkdir -p "$d" "$WORK/spool-PLAIN-$v"
    printf 'p=%s\n' "$v" > "$d/p.conf"
    printf 'PKG=PLAIN\nNAME=plain test\nARCH=m68k\nVERSION=%s\nCATEGORY=utility\nBASEDIR=/\n' "$v" > "$d/pkginfo"
    printf 'i pkginfo=%s\nf none /etc/plain.conf=%s 0644 root sys\n' "$d/pkginfo" "$d/p.conf" > "$d/prototype"
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-PLAIN-$v" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-PLAIN-$v" "$WORK/pkgs/PLAIN-$v.pkg" PLAIN ) >>"$WORK/mk.log" 2>&1
}
mkplain 1 && mkplain 2 || { echo "FAIL: building PLAIN"; cat "$WORK/mk.log"; exit 1; }

# APKG / APKGT: a stand-in client package.  Its /usr/apkg/bin/apkg is
# <script>; APKGT also carries the real postinstall, pointed at the host
# apkg and this target by PHOOK (the box's runs /usr/apkg/bin/apkg).
# mkclient <PKG> <version> <bin script> [preinstall] [postinstall]
mkclient() {
    local P="$1" v="$2" bin="$3" pre="$4" post="$5" d="$WORK/src-$1-$2"
    mkdir -p "$d" "$WORK/spool-$P-$v"
    printf 'PKG=%s\nNAME=client stand-in\nARCH=m68k\nVERSION=%s\nCATEGORY=utility\nBASEDIR=/\n' "$P" "$v" > "$d/pkginfo"
    {
        echo "i pkginfo=$d/pkginfo"
        [ -n "$pre" ] && echo "i preinstall=$pre"
        [ -n "$post" ] && echo "i postinstall=$post"
        echo "f none /usr/apkg/bin/apkg=$bin 0755 root sys"
    } > "$d/prototype"
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-$P-$v" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-$P-$v" "$WORK/pkgs/$P-$v.pkg" "$P" ) >>"$WORK/mk.log" 2>&1
}
# the hook as shipped, with the box paths swapped for the host apkg and
# the test's conf and target.  The engine clears the environment of its
# scripts (pkginstall/main.c), so they come from $WORK/phook.env, which
# ap writes before each run.
sed -e 's|"${PKG_INSTALL_ROOT:-/}"|/|' \
    -e "s|^if \[ -x /usr/apkg/bin/apkg \]|. $WORK/phook.env\\
&|" \
    -e "s|/usr/apkg/bin/apkg conffiles prepare|\"\$PHOOK_APKG\" -c \"\$PHOOK_CONF\" -R \"\$PHOOK_T\" conffiles prepare|" \
    -e "s|\[ -x /usr/apkg/bin/apkg \]|[ -x \"\$PHOOK_APKG\" ]|" \
    "$SRC/postinstall" > "$WORK/post-hook"
grep -q 'PHOOK_APKG" -c' "$WORK/post-hook" || { echo "FAIL: adapting the postinstall"; exit 1; }
# a working client: logs each run, then is the host apkg
printf '#!/bin/sh\necho "client: $*" >> "%s/client.log"\nexec "%s" "$@"\n' "$WORK" "$NEW" > "$WORK/bin-good"
printf '#!/bin/sh\necho "client: $*" >> "%s/client.log"\nexit 1\n' "$WORK" > "$WORK/bin-bad"
chmod 755 "$WORK/bin-good" "$WORK/bin-bad"
mkclient APKG 1 "$WORK/bin-good" "" "" &&
mkclient APKG 2 "$WORK/bin-good" "" "" &&
mkclient APKG 3 "$WORK/bin-bad" "" "" &&
mkclient APKG 4 "$WORK/bin-good" "$WORK/pre-fail" "" &&
mkclient APKGT 1 "$WORK/bin-good" "" "" &&
mkclient APKGT 2 "$WORK/bin-good" "" "$WORK/post-hook" ||
    { echo "FAIL: building the client packages"; cat "$WORK/mk.log"; exit 1; }

# ----------------------------------------------------------- the roots ---
# publish <PKG-version>...: the FILE repository serves exactly those
publish() {
    rm -rf "${WORK:?}/repo"; mkdir -p "$WORK/repo/pkgs"
    local p
    for p in "$@"; do cp "$WORK/pkgs/$p.pkg" "$WORK/repo/pkgs/"; done
    python3 "$GEN" --packages-conf none -o "$WORK/repo" "$WORK/repo/pkgs" \
        >>"$WORK/gen.log" 2>&1
}
# newroot <name>: a client conf and a target (-R) of their own
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
# what /etc/g/link.conf and its target are after an upgrade
linkstate() { ls -l "$T/etc/g/link.conf" 2>&1 | awk '{print $1, $NF}'
    cat "$T/etc/g/link.conf" "$T/etc/g/link.conf.new" "$T/etc/g/link-target" 2>&1 | sed "s|$T||"; }
# ap <apkg binary> [options] <verb> ...: the root's conf and target
ap() { local b="$1"; shift
       printf 'PHOOK_APKG=%s\nPHOOK_CONF=%s\nPHOOK_T=%s\n' "$NEW" "$C/etc/apkg.conf" "$T" > "$WORK/phook.env"
       fakeroot -i "$FS" -s "$FS" "$b" -c "$C/etc/apkg.conf" -R "$T" "$@" </dev/null >"$R/out" 2>&1; }
says() { grep -qF -- "$1" "$R/out"; }
silent() { ! grep -qF -- "$1" "$R/out"; }
is() { test "$(cat "$1" 2>/dev/null)" = "$2"; }
pend() { cat "$T/var/sadm/conffiles/PENDING" 2>/dev/null; }
base() { echo "$T/var/sadm/conffiles/$1"; }
cdb() { echo "$T/var/sadm/install/contents"; }
# the edits: edit.conf rewritten, swap.conf's two lines swapped (the
# same size and byte sum, a new mtime), mode.conf rewritten and chmod 600
edits() {
    printf 'edit=mine\n' > "$T/etc/g/edit.conf"
    printf 'beta\nalpha\n' > "$T/etc/g/swap.conf"
    touch -d '@1700000000' "$T/etc/g/swap.conf"
    printf 'mode=mine\n' > "$T/etc/g/mode.conf"; chmod 600 "$T/etc/g/mode.conf"
}

# ------------------------------------------------- the upgrade, 0.3.12 ---
echo "an upgrade that turns plain files into conffiles"
newroot a; publish GAINT-1; ap "$NEW" update
ap "$NEW" install gaint; check "install GAINT 1: rc 0" test $? -eq 0
check "  ... the files are class none in the contents DB" \
    grep -q '^/etc/g/touch.conf f none 0644 root sys' "$(cdb)"
edits
check "the reordering edit keeps size and byte sum (the premise of the mtime check)" \
    test "$(sum -s "$T/etc/g/swap.conf" | cut -d' ' -f1)" = "$(sum -s "$D1/swap.conf" | cut -d' ' -f1)"
publish GAINT-2; ap "$NEW" update
ap "$NEW" -v upgrade gaint; check "upgrade to GAINT 2: rc 0" test $? -eq 0
cp "$R/out" "$WORK/a-upgrade.out"
check "edited: kept" is "$T/etc/g/edit.conf" 'edit=mine'
check "  ... the new default beside it" is "$T/etc/g/edit.conf.new" 'edit=2'
check "untouched, default changed: replaced" is "$T/etc/g/touch.conf" 'touch=2'
check "  ... no .new" test ! -e "$T/etc/g/touch.conf.new"
check "  ... nothing said about it but the -v note" \
    bash -c "! grep -q 'touch.conf: kept' '$R/out' && grep -q '/etc/g/touch.conf: untouched; the new default will replace it' '$R/out'"
check "  ... its baseline is now the new default" is "$(base GAINT)/etc/g/touch.conf" 'touch=2'
check "untouched, default unchanged: quiet, in place" \
    bash -c "test \"\$(cat '$T/etc/g/same.conf')\" = same=1 && test ! -e '$T/etc/g/same.conf.new' && ! grep -q 'same.conf: kept' '$R/out'"
check "reordered (same size and sum, new mtime): kept as edited" \
    bash -c "test \"\$(printf 'beta\nalpha')\" = \"\$(cat '$T/etc/g/swap.conf')\" && test -f '$T/etc/g/swap.conf.new'"
check "relative path under BASEDIR, untouched: replaced" is "$T/usr/g/app.def" 'app=2'
check "edited and chmod 600: kept" is "$T/etc/g/mode.conf" 'mode=mine'
check "  ... with its own mode (600), as i.conffile keeps any edited file" \
    test "$(stat -c %a "$T/etc/g/mode.conf")" = 600
check "PENDING: the three kept files, nothing else" \
    test "$(pend | sort | tr '\n' ' ')" = "GAINT /etc/g/edit.conf GAINT /etc/g/mode.conf GAINT /etc/g/swap.conf "
check "the report names them" \
    bash -c "grep -q '/etc/g/edit.conf (GAINT): the new default is' '$R/out' && ! grep -q 'touch.conf (GAINT)' '$R/out'"

# removal afterwards: conffiles as usual
ap "$NEW" remove gaint; check "remove: rc 0" test $? -eq 0
check "  ... the edited file survives pkgrm" is "$T/etc/g/edit.conf" 'edit=mine'
check "  ... the untouched (replaced) file goes, with its baseline" \
    bash -c "test ! -e '$T/etc/g/touch.conf' && test ! -e '$(base GAINT)/etc/g/touch.conf'"

# the same upgrade under 0.3.11, for the record: the defect
if [ -n "$OLD" ]; then
    newroot a-old; publish GAINT-1; ap "$OLD" update; ap "$OLD" install gaint; edits
    publish GAINT-2; ap "$OLD" update; ap "$OLD" upgrade gaint
    cp "$R/out" "$WORK/a-old-upgrade.out"
    check "0.3.11 (the defect): the untouched file is kept with the old default" \
        bash -c "test \"\$(cat '$T/etc/g/touch.conf')\" = touch=1 && test -f '$T/etc/g/touch.conf.new' && grep -q 'touch.conf: kept your version' '$R/out'"
    check "0.3.11: the edited file is kept too (nothing destroyed)" is "$T/etc/g/edit.conf" 'edit=mine'
else
    echo "  skip 0.3.11 rows (no tag 1.1 or its build failed)"
fi

# ------------------------------------- a symlink that becomes a conffile ---
echo "a symlink that becomes a conffile (a type change: no baseline stored)"
for b in new old; do
    if [ $b = new ]; then B=$NEW; else B=$OLD; fi
    [ -z "$B" ] && continue
    newroot "l-$b"; publish LINKT-1; ap "$B" update; ap "$B" install linkt
    publish LINKT-2; ap "$B" update; ap "$B" upgrade linkt; echo "rc=$?" >> "$R/out"
    { linkstate; sed "s|$WORK/l-$b|ROOT|g" "$R/out"; } > "$WORK/l-$b.state"
done
check "apkg 0.3.12 stores no baseline for it" \
    test ! -e "$WORK/l-new/t/var/sadm/conffiles/LINKT/etc/g/link.conf.tmp"
[ -n "$OLD" ] && check "  ... and the outcome is 0.3.11's, byte for byte" \
    cmp -s "$WORK/l-new.state" "$WORK/l-old.state"

# ------------------------------------------- back to a version without the class ---
echo "a downgrade to a version that ships the files as plain files"
newroot dn; publish GAINT-1; ap "$NEW" update; ap "$NEW" install gaint; edits
publish GAINT-2; ap "$NEW" update; ap "$NEW" upgrade gaint
check "set-up: edit.conf kept with .new and pending" \
    bash -c "test \"\$(cat '$T/etc/g/edit.conf')\" = edit=mine && test -f '$T/etc/g/edit.conf.new' && grep -q 'GAINT /etc/g/edit.conf' '$T/var/sadm/conffiles/PENDING'"
publish GAINT-1; ap "$NEW" update
ap "$NEW" -f install gaint; check "apkg -f install of GAINT 1: rc 0" test $? -eq 0
cp "$R/out" "$WORK/dn.out"
check "  ... says the edits are not kept and where yours is" \
    says '/etc/g/edit.conf: this version of GAINT does not keep edits to it; yours is saved as /etc/g/edit.conf.old'
check "  ... yours is in edit.conf.old, the plain default in place" \
    bash -c "test \"\$(cat '$T/etc/g/edit.conf.old')\" = edit=mine && test \"\$(cat '$T/etc/g/edit.conf')\" = edit=1"
check "  ... an untouched one is not saved" test ! -e "$T/etc/g/touch.conf.old"
check "  ... the report claims nothing kept" bash -c "! grep -q 'config files kept' '$R/out'"
check "  ... no .new, no PENDING line, no baseline left" \
    bash -c "test ! -e '$T/etc/g/edit.conf.new' && ! grep -q GAINT '$T/var/sadm/conffiles/PENDING' 2>/dev/null && test ! -e '$(base GAINT)'"
ap "$NEW" conffiles
check "  ... apkg conffiles lists nothing of GAINT" bash -c "! grep -q GAINT '$R/out'"

# ------------------------------------------------------ a failed pkgadd ---
echo "a failed pkgadd, then the next upgrade"
newroot b; publish GAINT-1; ap "$NEW" update; ap "$NEW" install gaint; edits
publish GAINT-2; ap "$NEW" update
touch "$T/FAIL"
ap "$NEW" upgrade gaint; check "upgrade with a failing preinstall: rc 4" test $? -eq 4
check "  ... the edited file is as the user left it" is "$T/etc/g/edit.conf" 'edit=mine'
check "  ... the untouched file is the old default" is "$T/etc/g/touch.conf" 'touch=1'
check "  ... its baseline is stored (the old default)" is "$(base GAINT)/etc/g/touch.conf" 'touch=1'
check "  ... no baseline for an edited file" test ! -e "$(base GAINT)/etc/g/edit.conf"
check "  ... the engine records GAINT 2, partially installed: the old entries are gone" \
    grep -q '^/etc/g/touch.conf e conffile .* \*GAINT$' "$(cdb)"
cp -rp "$T" "$WORK/b-after-fail"
rm -f "$T/FAIL"
ap "$NEW" upgrade gaint; rc=$?
check "the next plain upgrade installs it again (rc 0)" test $rc -eq 0
check "  ... naming it partial" says 'gaint is partially installed (an install was cut short); installing 2 again'
check "  ... untouched replaced, edited kept with .new" \
    bash -c "test \"\$(cat '$T/etc/g/touch.conf')\" = touch=2 && test \"\$(cat '$T/etc/g/edit.conf')\" = edit=mine && test -f '$T/etc/g/edit.conf.new'"
# the user edits the file between the failed run and the next one (the
# retry by name, apkg -f install, takes the same way)
newroot b2; cp -rp "$WORK/b-after-fail/." "$T/"; rm -f "$T/FAIL"; cp "$WORK/b/fakeroot.state" "$FS"
publish GAINT-2; ap "$NEW" update
printf 'touch=edited-later\n' > "$T/etc/g/touch.conf"
ap "$NEW" -f install gaint; check "edited after the failed run, then the retry: rc 0" test $? -eq 0
check "  ... kept (its stored baseline is the old default), .new beside it" \
    bash -c "test \"\$(cat '$T/etc/g/touch.conf')\" = touch=edited-later && test \"\$(cat '$T/etc/g/touch.conf.new')\" = touch=2"
# removal straight after the failed run: the stored baselines go
newroot b3; cp -rp "$WORK/b-after-fail/." "$T/"; rm -f "$T/FAIL"; cp "$WORK/b/fakeroot.state" "$FS"
publish GAINT-2; ap "$NEW" update
ap "$NEW" remove gaint; check "remove after the failed run: rc 0" test $? -eq 0
check "  ... the stored baselines whose files pkgrm took are gone" test ! -e "$(base GAINT)"
ap "$NEW" list installed; check "  ... no config-files state left" silent 'config-files'

# ---------------------------------------------------- a cut, then recover ---
echo "a pkgadd cut short, then apkg recover"
newroot c; publish GAINT-1; ap "$NEW" update; ap "$NEW" install gaint; edits
publish GAINT-2; ap "$NEW" update
printf '#!/bin/sh\nkill -9 $PPID\nexit 1\n' > "$R/pkgadd-cut"; chmod 755 "$R/pkgadd-cut"
sed -i "s|^pkgadd=.*|pkgadd=$R/pkgadd-cut|" "$C/etc/apkg.conf"
ap "$NEW" upgrade gaint
check "apkg killed in the middle: the journal stays" test -f "$T/var/apkg/txn"
check "  ... the untouched file's baseline is stored, the files are as they were" \
    bash -c "test \"\$(cat '$(base GAINT)/etc/g/touch.conf')\" = touch=1 && test \"\$(cat '$T/etc/g/edit.conf')\" = edit=mine"
sed -i "s|^pkgadd=.*|pkgadd=$HB/pkgadd|" "$C/etc/apkg.conf"
ap "$NEW" recover; check "apkg recover: rc 0" test $? -eq 0
check "  ... untouched replaced, edited kept with .new, journal gone" \
    bash -c "test \"\$(cat '$T/etc/g/touch.conf')\" = touch=2 && test \"\$(cat '$T/etc/g/edit.conf')\" = edit=mine && test -f '$T/etc/g/edit.conf.new' && test ! -e '$T/var/apkg/txn'"

# ------------------------------------------ the 1.1.1 hop: the postinstall ---
if [ -n "$OLD" ]; then
    echo "apkg 0.3.11 upgrades the client and GAINT in one run (the postinstall)"
    newroot d; publish APKGT-1 GAINT-1; ap "$OLD" update; ap "$OLD" install apkgt gaint; edits
    publish APKGT-2 GAINT-2; ap "$OLD" update
    ap "$OLD" upgrade; check "0.3.11 apkg upgrade: rc 0" test $? -eq 0
    cp "$R/out" "$WORK/d-upgrade.out"
    check "  ... the client went first (catalog order)" \
        bash -c "grep -n 'upgraded apkgt\|upgraded gaint' '$R/out' | head -1 | grep -q apkgt"
    check "  ... untouched replaced silently" \
        bash -c "test \"\$(cat '$T/etc/g/touch.conf')\" = touch=2 && test ! -e '$T/etc/g/touch.conf.new' && ! grep -q 'touch.conf: kept' '$R/out'"
    check "  ... edited kept with .new" \
        bash -c "test \"\$(cat '$T/etc/g/edit.conf')\" = edit=mine && test -f '$T/etc/g/edit.conf.new'"
    check "  ... nothing pending for the untouched file" bash -c "! grep -q touch.conf '$T/var/sadm/conffiles/PENDING'"

    echo "a package that sorts before the client"
    newroot e; publish APKGT-1 AAGAIN-1; ap "$OLD" update; ap "$OLD" install apkgt aagain; edits
    publish APKGT-2 AAGAIN-2; ap "$OLD" update
    ap "$OLD" upgrade; check "0.3.11 apkg upgrade: rc 0" test $? -eq 0
    check "  ... aagain went before the client" \
        bash -c "grep -n 'upgraded apkgt\|upgraded aagain' '$R/out' | head -1 | grep -q aagain"
    check "  ... safe: edited kept with .new" \
        bash -c "test \"\$(cat '$T/etc/g/edit.conf')\" = edit=mine && test -f '$T/etc/g/edit.conf.new'"
    check "  ... the untouched file keeps the old default, its new one pending (0.3.11's behaviour)" \
        bash -c "test \"\$(cat '$T/etc/g/touch.conf')\" = touch=1 && grep -q 'AAGAIN /etc/g/touch.conf' '$T/var/sadm/conffiles/PENDING'"
    ap "$NEW" --conf-new conffiles resolve aagain
    check "  ... and apkg conffiles resolve --conf-new takes it" is "$T/etc/g/touch.conf" 'touch=2'

    echo "no conffile in the package: the same output as 0.3.11"
    for b in old new; do
        newroot "g-$b"; publish PLAIN-1; ap "$NEW" update; ap "$NEW" install plain
        publish PLAIN-2; ap "$NEW" update
        [ $b = old ] && ap "$OLD" upgrade plain || ap "$NEW" upgrade plain
        echo "rc=$?" >> "$R/out"
        sed "s|$WORK/g-$b|ROOT|g" "$R/out" > "$WORK/g-$b.out"
    done
    check "PLAIN 1 -> 2: byte-identical output, rc 0" cmp -s "$WORK/g-old.out" "$WORK/g-new.out"
    check "  ... and the same file" cmp -s "$WORK/g-old/t/etc/plain.conf" "$WORK/g-new/t/etc/plain.conf"
fi

# ------------------------------------------- the package tools first ---
echo "the package tools first, then the new apkg"
newroot f; publish APKG-1 GAINT-1 PLAIN-1; ap "$NEW" update; ap "$NEW" install apkg gaint plain
printf 'apkg=%s\n' "$T/usr/apkg/bin/apkg" >> "$C/etc/apkg.conf"
publish APKG-2 GAINT-2 PLAIN-2; ap "$NEW" update
: > "$WORK/client.log"
ap "$NEW" upgrade; check "apkg upgrade: rc 0" test $? -eq 0
cp "$R/out" "$WORK/f-upgrade.out"
check "  ... apkg upgraded on its own first" \
    bash -c "grep -n 'upgraded ' '$R/out' | head -1 | grep -q 'upgraded apkg to 2'"
check "  ... then the new apkg runs the rest, once" \
    bash -c "grep -q 'the package tools are upgraded; apkg' '$R/out' && test \"\$(grep -c '^client: .* upgrade\$' '$WORK/client.log')\" = 1"
check "  ... the rest is done" \
    bash -c "grep -q 'upgraded gaint to 2' '$R/out' && grep -q 'upgraded plain to 2' '$R/out'"

echo "a new apkg that does not run"
newroot f2; publish APKG-1 PLAIN-1; ap "$NEW" update; ap "$NEW" install apkg plain
printf 'apkg=%s\n' "$T/usr/apkg/bin/apkg" >> "$C/etc/apkg.conf"
publish APKG-3 PLAIN-2; ap "$NEW" update
ap "$NEW" upgrade; check "apkg upgrade: rc 0" test $? -eq 0
check "  ... says so and goes on with the running apkg" \
    bash -c "grep -q 'does not run; this apkg' '$R/out' && grep -q 'upgraded plain to 2' '$R/out'"

echo "a package tools transaction that fails"
newroot f3; publish APKG-1 PLAIN-1; ap "$NEW" update; ap "$NEW" install apkg plain
printf 'apkg=%s\n' "$T/usr/apkg/bin/apkg" >> "$C/etc/apkg.conf"
publish APKG-4 PLAIN-2; ap "$NEW" update
touch "$T/FAIL"; : > "$WORK/client.log"
ap "$NEW" upgrade; check "apkg upgrade: rc 4" test $? -eq 4
check "  ... nothing else upgraded, no re-exec" \
    bash -c "grep -q 'nothing else was' '$R/out' && grep -q '^/etc/plain.conf f none 0644 root sys 4' '$(cdb)' && ! grep -q upgrade '$WORK/client.log'"
check "  ... no journal left" test ! -e "$T/var/apkg/txn"

echo
echo "== conffile gain: $pass passed, $fail failed =="
[ $fail -eq 0 ]
