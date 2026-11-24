#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# older-apkg-check.sh -- can the apkg of every earlier release read a new
# release tree?
#
#   older-apkg-check.sh [--ref TAG]... [--apkg-bin PATH]...
#                       [--floor-base V | --kbootset-conf FILE] TREE
#
# A box upgrades with the apkg it has, so a new catalog must be read by the
# apkg an earlier release shipped: a line that apkg refuses is left out of
# that box's first `apkg upgrade`.  Each apkg is built for the host from a
# release tag's userland/pkgtools/src/apkg (git archive; one build per
# distinct source tree), or given ready-built with --apkg-bin.  For each:
# `apkg update` on file://TREE must read every live line (the counts of
# its "catalog updated:" line), and `apkg list` must show no line refused,
# with one exception the release accepts: a module line whose kbootset= is
# above kbootset.conf's module-floor-base (C2-2 v8).  apkg 0.3.5-0.3.11
# refuse kbootset= on a module line; such a module installs, by name or in
# the next upgrade, once the first upgrade has brought the newer apkg.  It
# is named on a WAIT line.  So is a row whose deps carry a floor
# ("name>=version") for an apkg before 0.3.14, which reads the row but
# refuses to install it as a missing dependency until `apkg upgrade apkg`;
# such a row in a tree whose own apkg row is older than 0.3.14 fails: no
# apkg of the tree could install it.
#
#   --ref TAG        a release tag to take an apkg from (repeatable).
#                    Default: every tag of TREE's release series (TREE's
#                    last path component, 1.1: the tags 1.1, 1.1.1, ...).
#   --apkg-bin PATH  a host apkg binary, checked as well (repeatable).
#   --floor-base V   the module-floor-base; default: the one line in
#                    --kbootset-conf FILE (default amix's
#                    kernel/conf/kbootset.conf).  None: every refused
#                    module line fails.
#
# Exit: 0 every apkg reads the tree, 1 a line refused or not read, 2 usage
# or a build error, 3 nothing to check with (no tag, no git, no cc).

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../../.." && pwd)
refs=""
bins=""
base=""
base_set=0
kbconf=$TOP/kernel/conf/kbootset.conf
tree=""

usage() {
	echo "usage: older-apkg-check.sh [--ref TAG]... [--apkg-bin PATH]..." >&2
	echo "       [--floor-base V | --kbootset-conf FILE] TREE" >&2
	exit 2
}

while [ $# -gt 0 ]; do
	case $1 in
	--ref) [ $# -ge 2 ] || usage; refs="$refs $2"; shift 2 ;;
	--apkg-bin) [ $# -ge 2 ] || usage; bins="$bins $2"; shift 2 ;;
	--floor-base) [ $# -ge 2 ] || usage; base=$2; base_set=1; shift 2 ;;
	--kbootset-conf) [ $# -ge 2 ] || usage; kbconf=$2; shift 2 ;;
	-*) usage ;;
	*) [ -z "$tree" ] || usage; tree=$1; shift ;;
	esac
done
[ -n "$tree" ] || usage
[ -f "$tree/catalog" ] || { echo "older-apkg-check: no catalog in $tree" >&2; exit 2; }
tree=$(cd "$tree" && pwd)
if [ $base_set = 0 ] && [ -f "$kbconf" ]; then
	base=$(sed -n 's/^module-floor-base:[ 	]*\([^ 	]*\).*/\1/p' "$kbconf")
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/older-apkg.XXXXXX") || exit 2
trap 'rm -rf "${work:?}"' EXIT INT TERM

# the tags of TREE's series, unless named
if [ -z "$refs" ] && [ -z "$bins" ]; then
	series=$(basename "$tree")
	command -v git >/dev/null 2>&1 || {
		echo "[MISSING] older-apkg-check: no git for the release tags" >&2; exit 3; }
	refs=$(git -C "$TOP" for-each-ref refs/tags --format='%(refname:short)' |
		awk -v s="$series" 'index($0, s) == 1 && substr($0, length(s) + 1) ~ /^(\.[0-9]+)*$/')
	[ -n "$refs" ] || {
		echo "[MISSING] older-apkg-check: no release tag of series $series" >&2; exit 3; }
fi

# one host build per distinct apkg source tree
n=0
seen=""
for r in $refs; do
	t=$(git -C "$TOP" rev-parse --verify -q "$r^{}:userland/pkgtools/src/apkg") || {
		echo "older-apkg-check: $r has no userland/pkgtools/src/apkg" >&2; exit 2; }
	case " $seen " in *" $t "*) continue ;; esac
	seen="$seen $t"
	n=$((n + 1))
	d=$work/src$n
	mkdir -p "$d"
	git -C "$TOP" archive "$r" userland/pkgtools/src/apkg | tar -x -C "$d" --strip-components=4 || {
		echo "older-apkg-check: cannot unpack $r's apkg" >&2; exit 2; }
	make -C "$d" apkg > "$d/build.log" 2>&1 || {
		tail -5 "$d/build.log" >&2
		echo "older-apkg-check: $r's apkg did not build for the host" >&2; exit 2; }
	bins="$bins $d/apkg($r)"
done

# vgt A B: 1 when A is above B in apkg's version order (gen-catalog's
# vercmp, the same as src/apkg/vercmp.c), else 0
vgt() {
	python3 -I -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("gencat", sys.argv[1])
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)
print(1 if m.vercmp(sys.argv[2], sys.argv[3]) > 0 else 0)' "$HERE/gen-catalog.py" "$1" "$2"
}

# what the tree's live part holds: ordinary rows, and #kpkg lines in the
# kpkg block (apkg's "N packages, K kernel-space")
nrows=$(awk '!/^#/ && NF { n++ } END { print n + 0 }' "$tree/catalog")
nk=$(awk '/^#ext kpkg 1$/ { k = 1; next } /^#end kpkg$/ { k = 0; next }
	k && /^#kpkg / { n++ } END { print n + 0 }' "$tree/catalog")

# rows whose deps carry a floor (apkg 0.3.14), and the tree's own apkg
floored=$(awk -F'|' '!/^#/ && NF >= 9 && $7 ~ />=/ { print $1 "|" $7 }' "$tree/catalog")
treeapkg=$(awk -F'|' '!/^#/ && $1 == "apkg" { print $2; exit }' "$tree/catalog")
FLOOR_APKG=0.3.14

rc=0
if [ -n "$floored" ] && { [ -z "$treeapkg" ] || [ "$(vgt "$FLOOR_APKG" "$treeapkg")" = 1 ]; }; then
	for f in $floored; do
		echo "FAIL ${f%%|*}: its dependency floor (${f#*|}) needs apkg $FLOOR_APKG or newer; the tree's apkg is ${treeapkg:-missing}"
	done
	rc=1
fi
for b in $bins; do
	case $b in
	*"("*")") bin=${b%(*}; from=${b##*(}; from=${from%)} ;;
	*) bin=$b; from=$b ;;
	esac
	[ -x "$bin" ] || { echo "older-apkg-check: $bin is not executable" >&2; exit 2; }
	ver=$("$bin" version 2>/dev/null)
	root=$work/root
	rm -rf "${root:?}"
	mkdir -p "$root"
	printf 'repo=file://%s\ncachedir=%s/var/apkg/cache\nadmin=%s/admin\n' \
		"$tree" "$root" "$root" > "$root/apkg.conf"
	out=$(APKG_ROOT=$root "$bin" -c "$root/apkg.conf" update 2>&1)
	want="catalog updated: $nrows package"
	[ "$nrows" = 1 ] || want="${want}s"
	[ "$nk" = 0 ] || want="$want, $nk kernel-space"
	case $out in
	*"$want"*) ;;
	*)
		echo "FAIL $ver ($from): apkg update does not read every line: wanted '$want'"
		printf '%s\n' "$out" | sed 's/^/     /'
		rc=1
		continue ;;
	esac
	refused=$(APKG_ROOT=$root "$bin" -c "$root/apkg.conf" list 2>/dev/null |
		awk '$3 == "[refused]" { print $1 }')
	bad=0
	wait=0
	for name in $refused; do
		line=$(awk -v n="$name" '$1 == "#kpkg" && $2 == n { print; exit }' "$tree/catalog")
		kb=$(printf '%s\n' "$line" | tr ' ' '\n' | sed -n 's/^kbootset=//p')
		role=$(printf '%s\n' "$line" | tr ' ' '\n' | sed -n 's/^role=//p')
		why=$(APKG_ROOT=$root "$bin" -c "$root/apkg.conf" info "$name" 2>/dev/null |
			sed -n 's/^Refused:[ 	]*//p')
		above=0
		if [ "$role" = module ] && [ -n "$kb" ] && [ -n "$base" ]; then
			above=$(vgt "$kb" "$base")
		fi
		if [ "$above" = 1 ]; then
			echo "WAIT $ver ($from): $name: $why (kbootset=$kb is above module-floor-base $base; it installs once the first upgrade has brought a newer apkg)"
			wait=$((wait + 1))
		else
			echo "FAIL $ver ($from): $name is refused: $why"
			bad=$((bad + 1))
		fi
	done
	bare=${ver#apkg }
	if [ -n "$floored" ] && [ "$(vgt "$FLOOR_APKG" "$bare")" = 1 ]; then
		for f in $floored; do
			echo "WAIT $ver ($from): ${f%%|*}: a dependency floor (${f#*|}); it installs once 'apkg upgrade apkg' has brought apkg $FLOOR_APKG or newer"
			wait=$((wait + 1))
		done
	fi
	if [ $bad -gt 0 ]; then
		rc=1
	else
		w=""
		[ $wait -gt 0 ] && w=", $wait waiting"
		echo "ok   $ver ($from): reads $nrows rows and $nk kernel-space lines$w"
	fi
done
[ -n "$bins" ] || { echo "[MISSING] older-apkg-check: no apkg to check with" >&2; exit 3; }
exit $rc
