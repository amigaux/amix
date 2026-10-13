#!/usr/bin/env bash
# run-tests.sh -- host-side tests for amix-sadm-migrate.sh.
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# Builds a fake /var/sadm tree replicating the Amix 2.1c factory state
# (31 package dirs, 4 of them without install/, no VERSION= anywhere,
# world-writable contents) under SADM_ROOT and drives the migration
# script through dry-run / real / re-run scenarios.  The script is
# executed under dash (a strict POSIX sh) and additionally lint-checked
# against a list of post-Bourne constructs it must not contain, since the
# real target is the 1992 pre-POSIX /bin/sh on Amix.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../amix-sadm-migrate.sh"
FIX="$HERE/fixtures"

# Interpreter used to exercise the script: prefer dash (closest strict sh
# on a Linux host), fall back to sh.
if command -v dash >/dev/null 2>&1; then
    RUNSH=dash
else
    RUNSH=sh
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/apkg-migrate-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok  - $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL- $1"; }
check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

# Amix factory state: 31 installed packages; bnu/face/intf_install/nsu
# lack install/ (docs/design.md section 4, docs/stock-pkg-system.md).
PKGS_NOINSTALL="bnu face intf_install nsu"
PKGS_INSTALL="core net lp sysadm terminf ed sccs graf oam usrenv inet nfs \
rfs dfm ksh man spell crypt uucp mail x11r5 x11r5src backup restore audit \
acct help"

make_pkginfo() { # make_pkginfo <dir> <pkg>  -- factory-style, no VERSION
    cat > "$1/pkginfo" <<EOF
PKG=$2
NAME=$2 package
CATEGORY=system
ARCH=Amiga
CLASSES= none
PKGINST=$2
PKGSAV=/var/sadm/pkg/$2/save
OAMBASE=/usr/sadm/sysadm
EOF
}

build_tree() { # build_tree <root>
    local root="$1" pkg dir
    mkdir -p "$root/var/sadm/install" "$root/var/sadm/pkg"
    cp "$FIX/contents.sample" "$root/var/sadm/install/contents"
    # the factory DB even carries the corrupt space-in-pathname record
    echo '/usr/x11r5/fonts/server/MacFS/TrueType Fonts f none 0444 x sys 525157 64049 679609720 X11R5 X11R5' \
        >> "$root/var/sadm/install/contents"
    chmod 666 "$root/var/sadm/install/contents"
    for pkg in $PKGS_INSTALL; do
        dir="$root/var/sadm/pkg/$pkg"
        mkdir -p "$dir/install" "$dir/save"
        make_pkginfo "$dir" "$pkg"
    done
    for pkg in $PKGS_NOINSTALL; do
        dir="$root/var/sadm/pkg/$pkg"
        mkdir -p "$dir/save"
        make_pkginfo "$dir" "$pkg"
    done
}

snapshot() { # snapshot <root>  -- paths, modes, types + file checksums
    ( cd "$1" &&
      find . -printf '%p %m %y\n' | sort &&
      find . -type f | sort | xargs -r md5sum )
}

# ---------------------------------------------------------------- M0 ----
echo "M0: shell dialect (parse + forbidden-construct lint)"
check "parses under $RUNSH -n" $RUNSH -n "$SCRIPT"
# Constructs absent from the 1992 Amix Bourne shell.  \$\( also catches
# \$\(\(; echo -n/-e are unportable (SVR4 echo does \c instead).
LINT_RE='\$\(|\[\[|\]\]|(^|[^[:alnum:]_])local[[:space:]]|(^|[^[:alnum:]_])function([[:space:]]|\()|echo[[:space:]]+-[neE]|[[:alnum:]_]\+=|=\('
if grep -nE "$LINT_RE" "$SCRIPT"; then
    bad "no post-Bourne constructs"
else
    ok "no post-Bourne constructs"
fi

# ---------------------------------------------------------------- M1 ----
echo "M1: dry run changes nothing"
R1="$WORK/m1"; build_tree "$R1"
snapshot "$R1" > "$WORK/m1.before"
SADM_ROOT="$R1" $RUNSH "$SCRIPT" -n > "$WORK/m1.out" 2>&1
check "exit 0" test $? -eq 0
snapshot "$R1" > "$WORK/m1.after"
check "tree bit-identical after dry run" cmp -s "$WORK/m1.before" "$WORK/m1.after"
check "contents still mode 666" \
    test "$(stat -c %a "$R1/var/sadm/install/contents")" = 666
check "no backup created" test ! -f "$R1/var/sadm/install/contents.pre-migrate"
check "announces dry run" grep -q 'DRY RUN' "$WORK/m1.out"
check "would-copy line" grep -q 'would copy contents' "$WORK/m1.out"
check "would-append lines" grep -q 'would append VERSION=2.1' "$WORK/m1.out"
check "would-mkdir lines" grep -q 'would create' "$WORK/m1.out"
check "would-chmod line" grep -q 'would chmod 644' "$WORK/m1.out"
check "summary counts 31 VERSION appends" \
    grep -Eq 'VERSION=2.1 appended:[[:space:]]+31' "$WORK/m1.out"
check "summary counts 4 install dirs" \
    grep -Eq 'install dirs created:[[:space:]]+4' "$WORK/m1.out"
check "summary counts 37 total" \
    grep -q '37 change(s) would be made' "$WORK/m1.out"

# ---------------------------------------------------------------- M2 ----
echo "M2: real run makes exactly the expected changes"
SADM_ROOT="$R1" $RUNSH "$SCRIPT" > "$WORK/m2.out" 2>&1
check "exit 0" test $? -eq 0
check "backup exists" test -f "$R1/var/sadm/install/contents.pre-migrate"
check "backup identical to contents" \
    cmp -s "$R1/var/sadm/install/contents" \
           "$R1/var/sadm/install/contents.pre-migrate"
ALLVER=1; ONEVER=1
for d in "$R1"/var/sadm/pkg/*; do
    grep -qx 'VERSION=2.1' "$d/pkginfo" || ALLVER=0
    test "$(grep -c '^VERSION=' "$d/pkginfo")" = 1 || ONEVER=0
done
check "all 31 pkginfo got VERSION=2.1" test "$ALLVER" = 1
check "exactly one VERSION line each" test "$ONEVER" = 1
MISSING=0
for pkg in $PKGS_NOINSTALL; do
    test -d "$R1/var/sadm/pkg/$pkg/install" || MISSING=1
done
check "install dirs created for bnu/face/intf_install/nsu" test "$MISSING" = 0
check "contents now mode 644" \
    test "$(stat -c %a "$R1/var/sadm/install/contents")" = 644
check "pkginfo body above VERSION untouched" \
    grep -qx 'OAMBASE=/usr/sadm/sysadm' "$R1/var/sadm/pkg/net/pkginfo"
check "summary: 37 changes made" grep -q '37 change(s) made' "$WORK/m2.out"

# ---------------------------------------------------------------- M3 ----
echo "M3: second run is a no-op and says so"
snapshot "$R1" > "$WORK/m3.before"
SADM_ROOT="$R1" $RUNSH "$SCRIPT" > "$WORK/m3.out" 2>&1
check "exit 0" test $? -eq 0
snapshot "$R1" > "$WORK/m3.after"
check "tree bit-identical after re-run" cmp -s "$WORK/m3.before" "$WORK/m3.after"
check "says nothing to do" grep -q 'nothing to do' "$WORK/m3.out"
check "backup step reports skipped" \
    grep -q 'contents.pre-migrate already exists - skipped' "$WORK/m3.out"
check "zero VERSION appends on re-run" \
    grep -Eq 'VERSION=2.1 appended:[[:space:]]+0' "$WORK/m3.out"

# ---------------------------------------------------------------- M4 ----
echo "M4: pre-existing VERSION= is left untouched"
R4="$WORK/m4"; build_tree "$R4"
echo 'VERSION=3.7' >> "$R4/var/sadm/pkg/net/pkginfo"
cp "$R4/var/sadm/pkg/net/pkginfo" "$WORK/m4.net.before"
mkdir -p "$R4/var/sadm/pkg/straydir"   # pkg dir without pkginfo
SADM_ROOT="$R4" $RUNSH "$SCRIPT" > "$WORK/m4.out" 2>&1
check "exit 0" test $? -eq 0
check "net pkginfo byte-identical (VERSION=3.7 kept)" \
    cmp -s "$R4/var/sadm/pkg/net/pkginfo" "$WORK/m4.net.before"
check "only 30 packages patched" \
    grep -Eq 'VERSION=2.1 appended:[[:space:]]+30' "$WORK/m4.out"
check "missing-pkginfo dir warned, not fatal" \
    grep -q 'straydir has no pkginfo' "$WORK/m4.out"
check "stray dir still got install/" test -d "$R4/var/sadm/pkg/straydir/install"

# ---------------------------------------------------------------- M5 ----
echo "M5: refuses a missing sadm tree"
SADM_ROOT="$WORK/nonexistent" $RUNSH "$SCRIPT" > "$WORK/m5.out" 2>&1
check "exit nonzero" test $? -ne 0
check "error message names the path" grep -q 'not a directory' "$WORK/m5.out"
SADM_ROOT="$WORK/nonexistent" $RUNSH "$SCRIPT" --bogus > /dev/null 2>&1
check "unknown flag -> usage error" test $? -ne 0

# -------------------------------------------------------------- done ----
echo
echo "migrate script ($RUNSH): $PASS passed, $FAIL failed"
test "$FAIL" -eq 0
