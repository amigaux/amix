#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# run.sh - the reproducible roll (T-56 D1) in the engine itself.  With
# SOURCE_DATE_EPOCH set, pkgmk and pkgtrans -s write a datastream that
# depends only on the prototype, the files and the epoch:
#   - two rolls of one package from different copies of its files (other
#     inodes, directory order, umask, file times, spool path) are the same
#     bytes;
#   - they are the bytes build/pkg's dsroll path (touch, umask, dsnorm.py
#     spool, a sorting find, dsnorm.py stream) makes of the same input,
#     and dsnorm.py finds nothing to change in them;
#   - a default PSTAMP is the epoch's UTC date, without the host's name.
# Unset, pkgmk and pkgtrans behave as before; a SOURCE_DATE_EPOCH that is
# not a number of seconds is refused.  Called from build-host.sh.
set -u
TOP="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$TOP/build-host/bin"
REPO="$(cd "$TOP/../../.." && pwd)"
COMMON="$REPO/build/pkg/common"
W="$TOP/build-host/repro"
E=1793404800
PKG=ZREPRO

rm -rf "$W"; mkdir -p "$W"
pass=0; fail=0
check() {
	local what="$1"; shift
	if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "repro roll: FAIL - $what"; fi
}

# the input: work/ (pkginfo, prototype, an install script) and a payload
# tree laid out in one order under one umask
mkdir -p "$W/work"
printf 'PKG=%s\nNAME=reproducible roll test\nARCH=m68k\nVERSION=1.0\nCATEGORY=application\nPSTAMP=repro\n' \
	"$PKG" > "$W/work/pkginfo"
printf '#!/sbin/sh\nexit 0\n' > "$W/work/postinstall"
cat > "$W/work/prototype" <<'EOF'
i pkginfo
i postinstall
d none /opt 0755 root sys
d none /opt/zr 0755 root sys
d none /opt/zr/b 0750 root sys
d none /opt/zr/a 0755 root sys
d none /opt/zr/a/deep 0755 root sys
f none /opt/zr/m 0644 root sys
f none /opt/zr/a/x 0600 root sys
f none /opt/zr/a/deep/y 0444 root sys
f none /opt/zr/b/run 0755 root bin
l none /opt/zr/b/m2=/opt/zr/m
EOF
lay() {	# lay <root> <umask> <order>: the payload, created in <order>
	local r="$1" n
	( umask "$2"
	  mkdir -p "$r/opt/zr"
	  for n in $3; do
		case $n in
		a) mkdir -p "$r/opt/zr/a/deep"; echo x > "$r/opt/zr/a/x"; echo y > "$r/opt/zr/a/deep/y" ;;
		b) mkdir -p "$r/opt/zr/b"; printf '#!/sbin/sh\n' > "$r/opt/zr/b/run" ;;
		m) echo m > "$r/opt/zr/m" ;;
		esac
	  done
	  [ -e "$r/opt/zr/b" ] && [ -e "$r/opt/zr/m" ] && ln "$r/opt/zr/m" "$r/opt/zr/b/m2" )
}
roll() {	# roll <work> <root> <spool> <out> [env...]: pkgmk + pkgtrans -s
	local wk="$1" rt="$2" sp="$3" out="$4"; shift 4
	rm -rf "$sp"; mkdir -p "$sp"
	( cd "$wk" && env "$@" "$BIN/pkgmk" -o -d "$sp" -f prototype -r "$rt" ) \
		> "$W/mk.log" 2>&1 &&
	env "$@" "$BIN/pkgtrans" -s "$sp" "$out" "$PKG" > "$W/tr.log" 2>&1
}

lay "$W/rootA" 002 "a b m"
lay "$W/rootB" 077 "m b a"
touch -d '2001-02-03 04:05:06' "$W/rootB/opt/zr/m" "$W/rootB/opt/zr/a/x"
cp -a "$W/work" "$W/workB"; touch "$W/workB/pkginfo"
check "roll A (SOURCE_DATE_EPOCH)" roll "$W/work" "$W/rootA" "$W/spA" "$W/A.pkg" SOURCE_DATE_EPOCH=$E
check "roll B: other inodes, order, umask, times and spool path" \
	roll "$W/workB" "$W/rootB" "$W/sp/B" "$W/B.pkg" SOURCE_DATE_EPOCH=$E
check "A and B are the same bytes" cmp -s "$W/A.pkg" "$W/B.pkg"
check "every pkgmap modtime is the epoch" \
	bash -c "! grep -E '^1 ([fev] \S+ \S+ \S+ \S+ \S+|i \S+) [0-9]+ [0-9]+ ' '$W/spA/$PKG/pkgmap' | grep -v ' $E\$'"
check "the spool's files carry pkgmap's modes" \
	bash -c "[ \$(stat -c %a '$W/spA/$PKG/root/opt/zr/a/x') = 600 ] && [ \$(stat -c %a '$W/spA/$PKG/root/opt/zr/b') = 750 ] && [ \$(stat -c %a '$W/spA/$PKG/pkgmap') = 644 ]"

# against build/pkg's dsroll path, and dsnorm.py as a check
if [ -f "$COMMON/dsroll.sh" ] && [ -f "$COMMON/dsnorm.py" ]; then
	lay "$W/rootC" 022 "b m a"
	cp -a "$W/work" "$W/workC"
	( SOURCE_DATE_EPOCH=$E AMIX_PKG_COMMON="$COMMON" AMIX_PKGMK="$BIN/pkgmk" \
	  AMIX_PKGTRANS="$BIN/pkgtrans" AMIX_REPO_ROOT="$REPO" \
	  bash -c '. "$AMIX_PKG_COMMON/dsroll.sh"; amix_dsroll "$1" "$2" "$3" "$4"' \
		dsroll "$W/workC" "$W/rootC" "$PKG" "$W/C.pkg" ) > "$W/dsroll.log" 2>&1
	check "build/pkg's amix_dsroll rolls the same input" test -f "$W/C.pkg"
	check "the engine's bytes are amix_dsroll's" cmp -s "$W/A.pkg" "$W/C.pkg"
	cp "$W/A.pkg" "$W/A2.pkg"
	python3 -I "$COMMON/dsnorm.py" stream "$W/A2.pkg" $E > "$W/dsnorm.log" 2>&1
	check "dsnorm.py stream finds nothing to change" cmp -s "$W/A.pkg" "$W/A2.pkg"
	cp -a "$W/spA" "$W/spA2"
	python3 -I "$COMMON/dsnorm.py" spool "$W/spA2" "$PKG" $E >> "$W/dsnorm.log" 2>&1
	check "dsnorm.py spool finds nothing to change" bash -c \
		"diff <(cd '$W/spA' && find . -printf '%p %m %T@ %s\n' | sort) <(cd '$W/spA2' && find . -printf '%p %m %T@ %s\n' | sort) >/dev/null"
else
	echo "repro roll: build/pkg/common/dsroll.sh not here; the dsroll comparison is skipped"
fi

# the datastream installs as before: the heirloom reader takes it back
mkdir -p "$W/back"
check "pkgtrans reads the normalised stream back" \
	bash -c "'$BIN/pkgtrans' '$W/A.pkg' '$W/back' $PKG >/dev/null 2>&1"
check "  ... to the same spool" diff -r "$W/spA/$PKG" "$W/back/$PKG"

# a default PSTAMP: the epoch's date in UTC, no host name
sed '/^PSTAMP=/d' "$W/work/pkginfo" > "$W/workD.pkginfo"
cp -a "$W/work" "$W/workD"; cp "$W/workD.pkginfo" "$W/workD/pkginfo"
check "roll without PSTAMP" roll "$W/workD" "$W/rootA" "$W/spD" "$W/D.pkg" SOURCE_DATE_EPOCH=$E
check "  ... the default PSTAMP is the epoch's UTC date alone" \
	grep -qx "PSTAMP=$(date -u -d @$E +%Y%m%d%H%M%S)" "$W/spD/$PKG/pkginfo"

# unset: as before (pkgmap says the files' own times)
check "roll without SOURCE_DATE_EPOCH" roll "$W/work" "$W/rootB" "$W/spU" "$W/U.pkg" SOURCE_DATE_EPOCH=
check "  ... pkgmap keeps the file's own modtime" \
	grep -q "^1 f none /opt/zr/m 0644 root sys [0-9]* [0-9]* $(stat -c %Y "$W/rootB/opt/zr/m")\$" "$W/spU/$PKG/pkgmap"
check "  ... and the stream differs from the epoch roll" bash -c "! cmp -s '$W/A.pkg' '$W/U.pkg'"

# not a number of seconds: refused
check "pkgmk refuses SOURCE_DATE_EPOCH=soon" \
	bash -c "! ( cd '$W/work' && SOURCE_DATE_EPOCH=soon '$BIN/pkgmk' -o -d '$W/spX' -f prototype -r '$W/rootA' ) >/dev/null 2>&1"
check "pkgtrans refuses SOURCE_DATE_EPOCH=soon" \
	bash -c "! SOURCE_DATE_EPOCH=soon '$BIN/pkgtrans' -s '$W/spA' '$W/X.pkg' $PKG >/dev/null 2>&1"

if [ "$fail" -eq 0 ]; then
	echo "repro roll:        OK ($pass checks; SOURCE_DATE_EPOCH rolls are bytes of their input)"
	rm -rf "$W"
	exit 0
fi
echo "repro roll: $fail of $((pass + fail)) checks failed (work: $W)"
exit 1
