#!/bin/bash
# run-tests.sh -- host tests for i.conffile / r.conffile (P-36 W1).
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Toy packages built with the host engine's pkgmk/pkgtrans, installed and
# removed with heirloom `pkgadd -R` / `pkgrm -R` under fakeroot, walk the
# whole i.conffile table (first install, identical, unedited, edited, user
# deleted, written before the package), r.conffile (unedited, edited, gone)
# and the `installf -f` re-register of a file the user replaced.  Run from
# anywhere; needs heirloom/build-host.sh's engine and fakeroot.
#
# Exit 0 all pass, 1 any failure, 77 skipped (no host engine or fakeroot).

HERE="$(cd "$(dirname "$0")" && pwd)"
TOP="$HERE/../../.."
HB="$TOP/heirloom/build-host/bin"
ICF="$HERE/../i.conffile"
RCF="$HERE/../r.conffile"

if [ ! -x "$HB/pkgmk" ] || [ ! -x "$HB/pkgadd" ] ||
   ! command -v fakeroot >/dev/null 2>&1; then
    echo "SKIP: host engine (heirloom/build-host.sh) or fakeroot missing"
    exit 77
fi

WORK="$(mktemp -d)"
[ -n "$KEEP" ] && echo "work: $WORK" || trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
check() {
    local what="$1"; shift
    if "$@"; then pass=$((pass + 1)); echo "  ok   $what"
    else fail=$((fail + 1)); echo "  FAIL $what"; fi
}

# ---------------------------------------------------------------- setup ---
printf 'mail=\ninstance=overwrite\npartial=nocheck\nrunlevel=nocheck\nidepend=nocheck\nrdepend=nocheck\nspace=nocheck\nsetuid=nocheck\nconflict=nocheck\naction=nocheck\nbasedir=default\n' \
    > "$WORK/admin"

# mkpkg <version> <toy.conf default> <toy admin default>: CONFT, two
# conffiles (one in a directory the package creates) and one plain file
mkpkg() {
    local v="$1" d="$WORK/src-$1"
    mkdir -p "$d" "$WORK/spool-$v" "$WORK/pkgs"
    printf '%s\n' "$2" > "$d/toy.conf"
    printf '%s\n' "$3" > "$d/admin"
    printf 'plain %s\n' "$v" > "$d/plain"
    printf 'PKG=CONFT\nNAME=conffile test\nARCH=m68k\nVERSION=%s\nCATEGORY=test\nCLASSES=none conffile\nBASEDIR=/\n' \
        "$v" > "$d/pkginfo"
    cat > "$d/prototype" <<EOF
i pkginfo=$d/pkginfo
i i.conffile=$ICF
i r.conffile=$RCF
d none /var/toy 0755 root sys
e conffile /etc/toy.conf=$d/toy.conf 0644 root sys
e conffile /var/toy/admin=$d/admin 0644 root sys
f none /var/toy/plain=$d/plain 0644 root sys
EOF
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-$v" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-$v" "$WORK/pkgs/CONFT-$v.pkg" CONFT ) \
        >>"$WORK/mk.log" 2>&1
}
mkpkg 1 'v=1' 'admin=1' && mkpkg 2 'v=2' 'admin=2' && mkpkg 3 'v=3' 'admin=2' &&
mkpkg 4 'v=4' 'admin=4' || { echo "FAIL: building the toy packages"; cat "$WORK/mk.log"; exit 1; }
# mkcore <name> <toy.conf>: CORE, a stock-style package that ships
# /etc/toy.conf as a plain file (as core does /etc/inittab)
mkcore() {
    local d="$WORK/src-$1"
    mkdir -p "$d" "$WORK/spool-$1"
    printf '%s\n' "$2" > "$d/toy.conf"
    printf 'PKG=CORE\nNAME=core stand-in\nARCH=m68k\nVERSION=1\nCATEGORY=system\n' > "$d/pkginfo"
    printf 'i pkginfo=%s\nf none /etc/toy.conf=%s 0644 root sys\n' "$d/pkginfo" "$d/toy.conf" > "$d/prototype"
    ( cd "$d" && "$HB/pkgmk" -o -d "$WORK/spool-$1" -f prototype &&
      "$HB/pkgtrans" -s "$WORK/spool-$1" "$WORK/pkgs/$1.pkg" CORE ) >>"$WORK/mk.log" 2>&1
}
mkcore core-1 'v=1' && mkcore core-st 'v=stock' ||
    { echo "FAIL: building the CORE packages"; cat "$WORK/mk.log"; exit 1; }

# one fakeroot state per root (see tools/repo/tests T23); every helper
# takes it from the root it is given
fr() { local fs="$WORK/fakeroot.$CUR"; touch "$fs"; fakeroot -i "$fs" -s "$fs" "$@"; }
# the host engine keeps its DB under its build tree (compiled-in VSADMDIR);
# r.conffile reads the box path, so each root links that to the DB
HBV="$(cd "$HB/.." && pwd)/var/sadm"
newroot() { CUR="$(basename "$1")"; rm -rf "$1"
    mkdir -p "$1/usr/bin" "$1/etc" "$1/var/sadm/install" "$1$HBV/install"
    ln -s "$1$HBV/install/contents" "$1/var/sadm/install/contents"
    printf 'root:x:%s:%s::/:/bin/sh\n' "$(id -u)" "$(id -g)" > "$1/etc/passwd"
    printf 'root::%s:\nsys::%s:\n' "$(id -g)" "$(id -g)" > "$1/etc/group"; }
add() { CUR="$(basename "$1")"; fr "$HB/pkgadd" -R "$1" -n -a "$WORK/admin" -d "$WORK/pkgs/CONFT-$2.pkg" CONFT \
        >"$WORK/add.out" 2>&1; }
rmp() { CUR="$(basename "$1")"; fr "$HB/pkgrm" -R "$1" -n -a "$WORK/admin" CONFT >"$WORK/rm.out" 2>&1; }
chk() { CUR="$(basename "$1")"; fr "$HB/pkgchk" -R "$1" CONFT >"$WORK/chk.out" 2>&1; }
chkn() { CUR="$(basename "$1")"; fr "$HB/pkgchk" -R "$1" -n CONFT >"$WORK/chkn.out" 2>&1; }
is() { test "$(cat "$1" 2>/dev/null)" = "$2"; }
base() { echo "$1/var/sadm/conffiles/CONFT"; }
pend() { cat "$1/var/sadm/conffiles/PENDING" 2>/dev/null; }
said() { grep -qF "$1" "$WORK/add.out"; }
quiet() { ! grep -q 'kept your\|you removed' "$WORK/add.out"; }
cdb() { find "$1" -path '*/var/sadm/install/contents' | head -1; }
# the DB record of /etc/toy.conf carries the bytes on disk
ondisk() { grep -q "^/etc/toy.conf e conffile 0644 root sys $(stat -c %s "$1/etc/toy.conf") $(sum -s "$1/etc/toy.conf" | cut -d' ' -f1) " "$(cdb "$1")"; }

# ---------------------------------------------------------- the scripts ---
echo "conffile scripts: stock-sh discipline"
for s in "$ICF" "$RCF"; do
    n="$(basename "$s")"
    check "$n parses under sh -n" sh -n "$s"
    check "$n uses no \$( ), \${var#...}, local, [[ or function keyword" \
        bash -c "! grep -v '^#' '$s' | grep -qE '\\\$\\(|\\\$\\{[A-Za-z_]+[#%]|^[[:space:]]*local |\\[\\[|^function '"
done
# ENDOFCLASS with an empty list: nothing to do, rc 0
check "i.conffile ENDOFCLASS with an empty list: rc 0" \
    bash -c "PKGINST=X PKG_INSTALL_ROOT='$WORK/eoc' sh '$ICF' ENDOFCLASS </dev/null"
mkdir -p "$WORK/out/etc"; echo d > "$WORK/out/src"
PKGINST=X PKG_INSTALL_ROOT="$WORK/in" sh "$ICF" </dev/null >/dev/null 2>&1
echo "$WORK/out/src $WORK/out/etc/x" |
    PKGINST=X PKG_INSTALL_ROOT="$WORK/in" sh "$ICF" >/dev/null 2>"$WORK/split.err"
check "a destination outside the install root is refused (rc 2)" test $? -eq 2
check "  ... and nothing is written there" test ! -e "$WORK/out/etc/x"
echo "$WORK/out/src $WORK/out/etc/x" | PKG_INSTALL_ROOT="$WORK/out" sh "$ICF" \
    >/dev/null 2>"$WORK/nopkg.err"
check "no PKGINST: refused (rc 2)" test $? -eq 2
# the stock 2.1 mkdir -p fails when the last directory already exists
# (rig E1, 2026-10-31): two files in one directory, under such a mkdir
mkdir -p "$WORK/m40/etc"; echo a > "$WORK/m40/a.src"; echo b > "$WORK/m40/b.src"
printf '%s\n' "$WORK/m40/a.src $WORK/m40/etc/a" "$WORK/m40/b.src $WORK/m40/etc/b" |
    PKGINST=X PKG_INSTALL_ROOT="$WORK/m40" bash -c '
        mkdir() {
            [ "$1" = -p ] || { command mkdir "$@"; return; }
            shift; for d; do [ -d "$d" ] && { echo "mkdir: \"$d\": File exists" >&2; return 1; }; done
            command mkdir -p "$@"
        }
        export -f mkdir; bash "$1"' sh "$ICF" >/dev/null 2>"$WORK/m40.err"
check "under a 4.0 mkdir -p, two files in one directory: rc 0" test $? -eq 0
check "  ... both baselines are stored" \
    test -f "$WORK/m40/var/sadm/conffiles/X/etc/a" -a -f "$WORK/m40/var/sadm/conffiles/X/etc/b"

# -------------------------------------------------------- i.conffile table ---
echo "i.conffile: the table under heirloom pkgadd -R"
R="$WORK/r1"; newroot "$R"; B="$(base "$R")"

# first install
add "$R" 1; check "first install: pkgadd rc 0" test $? -eq 0
check "first install: the default is laid down" is "$R/etc/toy.conf" 'v=1'
check "  ... also in a directory the package creates" is "$R/var/toy/admin" 'admin=1'
check "  ... its baseline is stored" is "$B/etc/toy.conf" 'v=1'
check "  ... no .new, nothing pending, no message" \
    bash -c "test ! -e '$R/etc/toy.conf.new' && test -z \"\$(cat '$R/var/sadm/conffiles/PENDING' 2>/dev/null)\""
check "  ... silent" quiet
check "  ... mode 0644" test "$(stat -c %a "$R/etc/toy.conf")" = 644
chk "$R"; check "  ... plain pkgchk clean" test $? -eq 0

# identical: re-add the same version
add "$R" 1; check "identical: pkgadd rc 0" test $? -eq 0
check "identical: the file is unchanged" is "$R/etc/toy.conf" 'v=1'
check "  ... silent, no .new" bash -c "test ! -e '$R/etc/toy.conf.new'" ; check "  ... no message" quiet

# unedited: upgrade replaces it
add "$R" 2; check "unedited upgrade: pkgadd rc 0" test $? -eq 0
check "unedited upgrade: the new default replaces it" is "$R/etc/toy.conf" 'v=2'
check "  ... the baseline follows" is "$B/etc/toy.conf" 'v=2'
check "  ... no .new, silent" bash -c "test ! -e '$R/etc/toy.conf.new'"
check "  ... no message" quiet
chk "$R"; check "  ... plain pkgchk clean" test $? -eq 0

# edited: kept, .new, PENDING, message
printf 'v=mine\n' > "$R/etc/toy.conf"
add "$R" 3; check "edited upgrade: pkgadd rc 0" test $? -eq 0
check "edited upgrade: your file is kept" is "$R/etc/toy.conf" 'v=mine'
check "  ... the new default is <file>.new" is "$R/etc/toy.conf.new" 'v=3'
check "  ... the baseline is the new default" is "$B/etc/toy.conf" 'v=3'
check "  ... PENDING names it" test "$(pend "$R")" = "CONFT /etc/toy.conf"
check "  ... the message says so" said '/etc/toy.conf: kept your version; the new default is /etc/toy.conf.new'
check "  ... the unedited sibling took its default silently" is "$R/var/toy/admin" 'admin=2'
chkn "$R"; check "  ... pkgchk -n clean" test $? -eq 0
chk "$R"; check "  ... plain pkgchk clean (the DB records the kept file)" test $? -eq 0
check "  ... the DB record carries the kept file's size and sum" ondisk "$R"

# still edited, re-added: one PENDING line, not two
add "$R" 3
check "edited, re-added: still kept" is "$R/etc/toy.conf" 'v=mine'
check "  ... PENDING holds one line" test "$(pend "$R" | wc -l)" = 1

# edited, and the package's default has not changed since: silent, and a
# fresh root shows no .new and nothing pending (dpkg asks only when the
# default changed)
R6="$WORK/r6"; newroot "$R6"
add "$R6" 1; printf 'v=mine\n' > "$R6/etc/toy.conf"; add "$R6" 1
check "edited, default unchanged: still kept" is "$R6/etc/toy.conf" 'v=mine'
check "  ... silent" quiet
check "  ... no .new and nothing pending" \
    bash -c "test ! -e '$R6/etc/toy.conf.new' && test -z \"\$(cat '$R6/var/sadm/conffiles/PENDING' 2>/dev/null)\""
add "$R6" 2
check "  ... the next changed default does pend" \
    bash -c "test \"\$(cat '$R6/etc/toy.conf.new')\" = v=2 && grep -q '^CONFT /etc/toy.conf\$' '$R6/var/sadm/conffiles/PENDING'"

# the user takes the new default by hand: identical again
cp "$R/etc/toy.conf.new" "$R/etc/toy.conf"
add "$R" 3
check "edit resolved to the new default: the stale .new goes" test ! -e "$R/etc/toy.conf.new"
check "  ... and its PENDING line goes" test -z "$(pend "$R")"

# user deleted: the engine verifies every object of the class after the
# script and fails on a missing one, so the default comes back, said aloud.
# A pending .new from an earlier edit goes with it.
printf 'v=mine\n' > "$R/etc/toy.conf"; add "$R" 3
rm -f "$R/etc/toy.conf"
add "$R" 4; check "user-deleted upgrade: pkgadd rc 0" test $? -eq 0
check "user-deleted: the new default is back" is "$R/etc/toy.conf" 'v=4'
check "  ... the message says so" said "/etc/toy.conf: you had removed it; the package's default is back"
check "  ... the stale .new and its PENDING line are gone" \
    bash -c "test ! -e '$R/etc/toy.conf.new' && test -z \"\$(cat '$R/var/sadm/conffiles/PENDING')\""
check "  ... the unedited admin took its default" is "$R/var/toy/admin" 'admin=4'
chk "$R"; check "  ... plain pkgchk clean" test $? -eq 0
# the engine's own refusal, for the record: without the copy-back an absent
# object fails pkgadd.  Shown with a class script that writes nothing.
printf 'while read s d; do :; done\nexit 0\n' > "$WORK/i.null"
sed "s|^i i.conffile=.*|i i.conffile=$WORK/i.null|" "$WORK/src-1/prototype" \
    > "$WORK/src-1/prototype.null"
mkdir -p "$WORK/spool-null"
( cd "$WORK/src-1" && "$HB/pkgmk" -o -d "$WORK/spool-null" -f prototype.null &&
  "$HB/pkgtrans" -s "$WORK/spool-null" "$WORK/pkgs/CONFT-null.pkg" CONFT ) \
    >>"$WORK/mk.log" 2>&1
RN="$WORK/rnull"; newroot "$RN"
add "$RN" null
check "(the engine) a class script that leaves the object absent fails pkgadd" \
    test $? -ne 0
check "  ... on the attribute check of the missing path" \
    grep -q 'pathname does not exist' "$WORK/add.out"

# written before the package (installer or user; no baseline)
R2="$WORK/r2"; newroot "$R2"
printf 'v=installer\n' > "$R2/etc/toy.conf"
add "$R2" 1
check "written before the package: kept as edited" is "$R2/etc/toy.conf" 'v=installer'
check "  ... .new, PENDING and the message" \
    bash -c "test \"\$(cat '$R2/etc/toy.conf.new')\" = v=1 && grep -q '^CONFT /etc/toy.conf\$' '$R2/var/sadm/conffiles/PENDING' && grep -q 'kept your version' '$WORK/add.out'"
R3="$WORK/r3"; newroot "$R3"
printf 'v=1\n' > "$R3/etc/toy.conf"
add "$R3" 1
check "written before the package, equal to the default: silent" quiet
check "  ... no .new" test ! -e "$R3/etc/toy.conf.new"
check "  ... the baseline is stored" is "$(base "$R3")/etc/toy.conf" 'v=1'

# ------------------------------------------------------- r.conffile -------
echo "r.conffile: pkgrm -R"
# R3: unedited -> removed with its baseline, directories pruned
rmp "$R3"; check "pkgrm, unedited: rc 0" test $? -eq 0
check "unedited: the file is removed" test ! -e "$R3/etc/toy.conf"
check "  ... its baseline too, and the empty baseline tree" test ! -e "$(base "$R3")"
check "  ... the plain file is removed by pkgrm as usual" test ! -e "$R3/var/toy/plain"
# reinstall after that: a first install
add "$R3" 2
check "reinstall after an unedited remove: a fresh first install" is "$R3/etc/toy.conf" 'v=2'
check "  ... silent" quiet

# R2: edited -> kept with its baseline; .new and PENDING go
rmp "$R2"; check "pkgrm, edited: rc 0" test $? -eq 0
check "edited: the file is kept" is "$R2/etc/toy.conf" 'v=installer'
check "  ... the message says so" grep -qF '/etc/toy.conf: kept your edited version' "$WORK/rm.out"
check "  ... its .new is removed" test ! -e "$R2/etc/toy.conf.new"
check "  ... its PENDING line is removed" test -z "$(pend "$R2")"
check "  ... its baseline stays (config-files)" is "$(base "$R2")/etc/toy.conf" 'v=1'
check "  ... the unedited sibling and its baseline are gone" \
    bash -c "test ! -e '$R2/var/toy/admin' && test ! -e '$(base "$R2")/var'"
# a kept file inside a directory the package owns: the directory stays,
# pkgrm still succeeds and the package is gone (heirloom pkgremove takes
# ENOTEMPTY as "not empty" like SVR4's EEXIST, AMIX PORT 2026-10-30)
R5="$WORK/r5"; newroot "$R5"
add "$R5" 1; printf 'admin=mine\n' > "$R5/var/toy/admin"
rmp "$R5"; check "pkgrm, edited file in a package directory: rc 0" test $? -eq 0
check "  ... the file and its directory stay" is "$R5/var/toy/admin" 'admin=mine'
check "  ... the package is gone" \
    bash -c "! fakeroot -i '$WORK/fakeroot.r5' '$HB/pkginfo' -R '$R5' CONFT >/dev/null 2>&1"
# reinstall: the kept file meets its baseline -> the edited row
add "$R2" 2
check "reinstall over a kept edit: still kept" is "$R2/etc/toy.conf" 'v=installer'
check "  ... .new is the new default" is "$R2/etc/toy.conf.new" 'v=2'

# R: edited with a .new pending, then the file deleted before pkgrm: its
# baseline and .new go, and PENDING is emptied
printf 'v=mine\n' > "$R/etc/toy.conf"; add "$R" 3
check "(setup) an edit with a .new pending" test -e "$R/etc/toy.conf.new"
rm -f "$R/etc/toy.conf"
rmp "$R"; check "pkgrm, file already gone: rc 0" test $? -eq 0
check "already gone: .new removed" test ! -e "$R/etc/toy.conf.new"
check "  ... baseline removed" test ! -e "$(base "$R")/etc/toy.conf"
check "  ... PENDING emptied" test -z "$(pend "$R")"

# ------------------------------------------ shared with another package ---
# D-N24: amix-base ships core's files as conffiles.  The engine hands a
# shared editable file to r.conffile, which leaves it to the other owner.
echo "r.conffile: a conffile another package also owns"
addc() { CUR="$(basename "$1")"; fr "$HB/pkgadd" -R "$1" -n -a "$WORK/admin" -d "$WORK/pkgs/$2.pkg" CORE \
        >"$WORK/addc.out" 2>&1; }
R7="$WORK/r7"; newroot "$R7"
addc "$R7" core-1; add "$R7" 1
check "CORE then CONFT, same bytes: both own /etc/toy.conf" \
    grep -q '^/etc/toy.conf e conffile .*CORE.* CONFT' "$(cdb "$R7")"
rmp "$R7"; check "pkgrm CONFT: rc 0" test $? -eq 0
check "  ... /etc/toy.conf stays" is "$R7/etc/toy.conf" 'v=1'
check "  ... still listed under CORE" grep -q '^/etc/toy.conf .*CORE' "$(cdb "$R7")"
check "  ... and no longer under CONFT" bash -c "! grep -q '^/etc/toy.conf .*CONFT' '$(cdb "$R7")'"
check "  ... no stale baseline" test ! -e "$(base "$R7")/etc/toy.conf"
check "  ... pkgrm says so" grep -qF '/etc/toy.conf: left in place; it also belongs to CORE' "$WORK/rm.out"
check "  ... the unshared conffile went as usual" test ! -e "$R7/var/toy/admin"
R8="$WORK/r8"; newroot "$R8"
addc "$R8" core-st; add "$R8" 1
check "over a stock file: kept, the default is .new" \
    bash -c "test \"\$(cat '$R8/etc/toy.conf')\" = v=stock && test -f '$R8/etc/toy.conf.new'"
rmp "$R8"; check "pkgrm CONFT: rc 0" test $? -eq 0
check "  ... the stock file stays" is "$R8/etc/toy.conf" 'v=stock'
check "  ... its .new, PENDING line and baseline go" \
    bash -c "test ! -e '$R8/etc/toy.conf.new' && test -z \"\$(cat '$R8/var/sadm/conffiles/PENDING' 2>/dev/null)\" && test ! -e '$(base "$R8")/etc/toy.conf'"

# the contents lines r.conffile parses, run directly: a stock 2.1 shared
# line (core:none, a trailing '\'), a line of another type, decoys that
# only contain the path, and a file only X owns
S="$WORK/rsh"; mkdir -p "$S/etc" "$S/var/sadm/install" "$S/var/sadm/conffiles/X/etc"
for f in a b d; do echo "$f" > "$S/etc/$f"; echo "$f" > "$S/var/sadm/conffiles/X/etc/$f"; done
cat > "$S/var/sadm/install/contents" <<'CONTENTS'
/etc/a f conffile 0664 root sys 2 97 1793431436 core:none X\
/etc/b e conffile 0644 root sys 2 98 1793431436 X
/etc/b.old f none 0644 root sys 2 98 1793431436 core
/x/etc/b e none 0644 root sys 2 98 1793431436 core
/etc/l=/etc/b s none core
/etc/d d none 0755 root sys core X
CONTENTS
printf '%s\n' "$S/etc/a" "$S/etc/b" "$S/etc/d" |
    PKGINST=X PKG_INSTALL_ROOT="$S" sh "$RCF" >"$WORK/rsh.out" 2>&1
check "direct: rc 0" test $? -eq 0
check "  ... the stock shared line: kept for core" \
    bash -c "test -f '$S/etc/a' && grep -qF '/etc/a: left in place; it also belongs to core' '$WORK/rsh.out'"
check "  ... X's own file: removed, decoys ignored" test ! -e "$S/etc/b"
check "  ... another type: kept" grep -qF '/etc/d: left in place; it also belongs to a package (type d)' "$WORK/rsh.out"
check "  ... every baseline goes" bash -c "test -z \"\$(ls '$S/var/sadm/conffiles/X/etc' 2>/dev/null)\""

# -------------------------------------------- installf -f re-register ----
# P-36 1.2 marks UNVERIFIED that `installf <pkg> <path> e` + `installf -f`
# re-reads size and checksum of an existing e entry -- apkg --conf-new
# relies on it after it moves <file>.new over the user's file.
echo "installf -f re-registers a replaced conffile"
R4="$WORK/r4"; newroot "$R4"
add "$R4" 1; printf 'v=mine\n' > "$R4/etc/toy.conf"; add "$R4" 2
mv "$R4/etc/toy.conf.new" "$R4/etc/toy.conf"      # what --conf-new does
chk "$R4"; check "after the replace, plain pkgchk flags the conffile" test $? -ne 0
CUR=r4
# without -c the entry falls back to class none -- the class must be named
fr "$HB/installf" -R "$R4" -c conffile CONFT /etc/toy.conf e >"$WORK/if.out" 2>&1
check "installf -c conffile CONFT /etc/toy.conf e: rc 0" test $? -eq 0
fr "$HB/installf" -R "$R4" -f CONFT >>"$WORK/if.out" 2>&1
check "installf -f CONFT: rc 0" test $? -eq 0
chk "$R4"; check "installf -f re-read the file: plain pkgchk clean" test $? -eq 0
check "  ... the DB record carries the new size and sum" ondisk "$R4"
check "  ... the class is still conffile" \
    grep -q '^/etc/toy.conf e conffile ' "$(cdb "$R4")"

echo
echo "== conffile: $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
