#!/bin/sh
#
# onever-selftest.sh -- prove the one-version guard (build/pkg/common/onever.sh)
# refuses a changed datastream under a listed version and allows an
# identical one, through the real roll path.
#
#     [AMIX_KSPACE_REPO=<amix-packages checkout>] sh build/pkg/tests/onever-selftest.sh
#
# Reads the catalog of record (build/kspace/repo) and its kern46m and
# kbootset datastreams (since fff860dc: -61 and -24), and the kernel-k46-m
# recipe, from AMIX_KSPACE_REPO: the amix-packages checkout that keeps the
# kernel-space line until it moves (default: amix-packages beside the main
# working tree of this checkout). Without one it says SKIP and exits 77.
# Writes only under a temporary directory.
#
#   1. a text-only re-roll of the record's kern46m (the recipe's pkginfo at the
#      record's version, the record's payload) through amix_kpkgroll is
#      refused; the datastream already at
#      the output path is left as it was, nothing is left in the work dir
#   2. the same with the record's OWN pkginfo and control-file mtimes is
#      refused too: the record was rolled before dsroll.sh (its newc headers
#      carry the spool's inode numbers), so no rebuild gives its bytes, and
#      any rebuild of that version is
#   3. a byte-identical datastream (the record's) is allowed and says so
#   4. an unlisted version is allowed as new
#   5. an ordinary (md5) row: the record's kbootset identical allowed, one byte off
#      refused
#   6. the default root list holds the catalog of record and the superseded
#      roots
#
# Exit 0 and "onever-selftest: PASS" last, or non-zero on the first miss.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
AMIX_TOP=$(cd "$HERE/../../.." && pwd)
. "$AMIX_TOP/build/pkg/layout.sh"
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1793303717}	# the roll stamps every time with it
if [ -z "${AMIX_KSPACE_REPO:-}" ]; then
	_g=$(git -C "$AMIX_TOP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
		_g=$(cd "$(dirname "$_g")/.." && pwd)/amix-packages && [ -d "$_g" ] && AMIX_KSPACE_REPO=$_g
fi
REPO=${AMIX_KSPACE_REPO:-}
[ -f "$REPO/build/kspace/repo/catalog" ] && [ -f "$REPO/recipes/kernel-k46-m/pkginfo" ] || {
	echo "onever-selftest: SKIP -- no kspace catalog of record: set AMIX_KSPACE_REPO" \
		"to an amix-packages checkout with build/kspace/repo and recipes/kernel-k46-m${REPO:+ ($REPO has none)}" >&2
	exit 77
}
. "$AMIX_PKG_COMMON/amix-env.sh" >/dev/null
. "$AMIX_PKG_COMMON/kpkgroll.sh"
. "$AMIX_PKG_COMMON/onever.sh"

T=$(mktemp -d "${TMPDIR:-/tmp}/onever.XXXXXX")
trap 'rm -rf "$T"' EXIT

fail() { echo "onever-selftest: FAIL -- $*" >&2; exit 1; }
n=0
ok() { n=$((n + 1)); echo "  ok $n  $*"; }

REC="$REPO/build/kspace/repo"
[ -f "$REC/catalog" ] || fail "no catalog of record at $REC"
K46=$(sed -n 's/^#kpkg kernel-k46-m \([^ ]*\) .*/\1/p' "$REC/catalog")
KF="$REC/pkgs/base/kern46m-$K46.pkg"
KB=$(sed -n 's/^kbootset|\([^|]*\)|.*/\1/p' "$REC/catalog")
BF="$REC/pkgs/base/kbootset-$KB.pkg"
[ -f "$KF" ] && [ -f "$BF" ] || fail "the record's kern46m $K46 / kbootset $KB datastreams are missing"
export AMIX_ONEVER_ROOTS="$REC"
RMD=$(md5sum < "$REC/catalog" | cut -c1-8)

# the record's kern46m, unpacked: its payload is the re-roll's
mkdir -p "$T/x"; "$AMIX_PKGTRANS" "$KF" "$T/x" kern46m >/dev/null 2>&1 || true
[ -f "$T/x/kern46m/pkgmap" ] || fail "cannot unpack $KF"

reroll() {	# reroll <tag> <pkginfo>: kern46m $K46 through amix_kpkgroll
	w="$T/w-$1"; rm -rf "$w"; mkdir -p "$w" "$T/out-$1"
	cp "$2" "$w/pkginfo"; cp "$T/x/kern46m/install/copyright" "$w/copyright"
	cp "$REPO/recipes/kernel-k46-m/prototype" "$w/"
	cp "$KF" "$T/out-$1/kern46m-$K46.pkg"     # the datastream already there
	( amix_kpkgroll "$w" "$T/x/kern46m/root" kern46m "$K46" "$T/out-$1/kern46m-$K46.pkg" ) > "$T/roll-$1.log" 2>&1
}

# --- 1. a text-only re-roll --------------------------------------------------
# the recipe's pkginfo at the record's version: as it is while the recipe
# pins the record's cut, else with its version rewritten to the record's
# (the recipe has moved on to a newer cut, -51 since 2026-10-28)
RV=$(sed -n 's/^VERSION=//p' "$REPO/recipes/kernel-k46-m/pkginfo")
[ -n "$RV" ] || fail "recipe pkginfo has no VERSION="
sed "s/$RV/$K46/g" "$REPO/recipes/kernel-k46-m/pkginfo" > "$T/text-pkginfo"
grep -q "^VERSION=$K46\$" "$T/text-pkginfo" || fail "recipe pkginfo cannot be set to $K46"
cmp -s "$T/text-pkginfo" "$T/x/kern46m/pkginfo" && fail "recipe pkginfo equals the record's: no text change to test"
if reroll text "$T/text-pkginfo"; then fail "a text-only re-roll of kern46m $K46 was written"; fi
grep -q "one-version: kern46m $K46 is already listed with other bytes" "$T/roll-text.log" \
	&& grep -q "$REC (catalog $RMD, base/kern46m-$K46.pkg)" "$T/roll-text.log" \
	&& grep -q "not written to $T/out-text/kern46m-$K46.pkg (left as it was)" "$T/roll-text.log" \
	|| { cat "$T/roll-text.log" >&2; fail "refusal message"; }
cmp -s "$T/out-text/kern46m-$K46.pkg" "$KF" || fail "the datastream already at the output path changed"
[ -z "$(ls -A "$T/w-text/.roll" 2>/dev/null)" ] || fail "the refused roll left $(ls "$T/w-text/.roll")"
ok "a text-only re-roll of kern46m $K46 (the recipe's pkginfo, $RV, set to $K46) is refused by amix_kpkgroll; the output path keeps the record's bytes"

# --- 2. a re-roll of the record's own control files --------------------------
M=$(awk '$2 == "i" && $3 == "pkginfo" {print $6}' "$T/x/kern46m/pkgmap")
cp -p "$T/x/kern46m/pkginfo" "$T/own-pkginfo"; touch -d "@$M" "$T/own-pkginfo"
if reroll own "$T/own-pkginfo"; then fail "a re-roll with the record's own pkginfo was written"; fi
grep -q "already listed with other bytes" "$T/roll-own.log" || { cat "$T/roll-own.log" >&2; fail "own re-roll message"; }
cmp -s "$T/out-own/kern46m-$K46.pkg" "$KF" || fail "the output path changed (own re-roll)"
ok "a re-roll with the record's own pkginfo is refused as well: the record predates the reproducible roll"

# --- 3. a byte-identical datastream ------------------------------------------
cp "$KF" "$T/same.pkg"; mkdir -p "$T/out-same"
( amix_one_version "$T/same.pkg" kern46m "$K46" "$T/out-same/kern46m-$K46.pkg" ) > "$T/same.log" 2>&1 \
	|| { cat "$T/same.log" >&2; fail "a byte-identical datastream was refused"; }
grep -q "one-version: kern46m $K46 is byte-identical to the listed datastream in 1 root(s) .*allowed, an identical rebuild" "$T/same.log" \
	|| { cat "$T/same.log" >&2; fail "identical message"; }
cmp -s "$T/out-same/kern46m-$K46.pkg" "$KF" || fail "the identical datastream was not installed"
ok "a byte-identical kern46m $K46 is allowed and says so: $(sed 's/^ *//' "$T/same.log" | cut -c1-90)"

# --- 4. an unlisted version --------------------------------------------------
cp "$KF" "$T/new.pkg"
( amix_one_version "$T/new.pkg" kern46m "$K46-selftest" "$T/out-new/x.pkg" ) > "$T/new.log" 2>&1 \
	&& grep -q "is listed in no root: a new version" "$T/new.log" && [ -f "$T/out-new/x.pkg" ] \
	|| { cat "$T/new.log" >&2; fail "an unlisted version"; }
ok "an unlisted version is written as new"

# --- 5. an ordinary row (md5) ------------------------------------------------
cp "$BF" "$T/kb.pkg"
( amix_one_version "$T/kb.pkg" kbootset "$KB" "$T/out-kb/kb.pkg" ) > "$T/kb.log" 2>&1 \
	&& grep -q "byte-identical" "$T/kb.log" || { cat "$T/kb.log" >&2; fail "kbootset identical"; }
cp "$BF" "$T/kb2.pkg"; printf 'x' >> "$T/kb2.pkg"
if ( amix_one_version "$T/kb2.pkg" kbootset "$KB" "$T/out-kb2/kb.pkg" ) > "$T/kb2.log" 2>&1; then
	fail "kbootset $KB with one byte more was written"; fi
grep -q "already listed with other bytes" "$T/kb2.log" && [ ! -e "$T/out-kb2/kb.pkg" ] && [ ! -e "$T/kb2.pkg" ] \
	|| { cat "$T/kb2.log" >&2; fail "kbootset refusal"; }
ok "kbootset $KB (an ordinary md5 row): identical allowed, one byte off refused"

# --- 6. the default roots ----------------------------------------------------
D=$(unset AMIX_ONEVER_ROOTS; AMIX_REPO_ROOT=$REPO; amix_onever_roots)
case " $D " in *" $REC "*) ;; *) fail "default roots lack $REC: $D" ;; esac
NS=$(ls -d "$REPO"/build/kspace/superseded/repo-*/catalog 2>/dev/null | wc -l)
[ "$(echo "$D" | tr ' ' '\n' | grep -c '/superseded/repo-')" = "$NS" ] || fail "default roots lack superseded roots: $D"
ok "default roots: the catalog of record, $NS superseded root(s)$(echo "$D" | grep -q candidate- && echo ', the candidate')"

echo "onever-selftest: PASS ($n checks)"
