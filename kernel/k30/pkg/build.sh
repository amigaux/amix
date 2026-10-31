#!/bin/sh
# build.sh -- kernel/k30's kernel-space package (P-38 S3.3): kernel-k30-m
# (kern30m), the module kernel of the 68030 line.
#
# usage: sh kernel/k30/pkg/build.sh [name...]      (default: all)
#
# make dist's kspace step calls it (build/dist.sh). Each recipe's
# datastreams go to $AMIX_BUILD_ROOT/kspace/pkg/ (out/pkg/kspace/pkg/
# unless AMIX_BUILD_ROOT is set), its log to $AMIX_BUILD_ROOT/kspace/log/;
# on standard output one line per datastream, `pkg <file> <sha256>`.
# Exit status 1 on any failure (the recipe's log's tail on standard error),
# 2 for usage, 3 when a recipe's input from outside it is absent (its
# [MISSING] line on standard error; the other recipes still roll).
#
# MIT licence, see LICENSE in kernel/k30.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ALL="kernel-k30-m"
names=${*:-$ALL}
for n in $names; do
	case " $ALL " in
	*" $n "*) ;;
	*) echo "usage: build.sh [$(echo $ALL | sed 's/ /|/g')]..." >&2; exit 2 ;;
	esac
done

AMIX_TOP=$(cd "$HERE/../../.." && pwd)
root=${AMIX_BUILD_ROOT:-$AMIX_TOP/out/pkg}
mkdir -p "$root/kspace/log"
KSPACE_LIST="$root/kspace/log/built.$$"
export KSPACE_LIST
trap 'rm -f "$KSPACE_LIST"' EXIT INT TERM
: > "$KSPACE_LIST"

missing=
for n in $names; do
	log="$root/kspace/log/$n.log"
	rc=0
	sh "$HERE/$n/build.sh" > "$log" 2>&1 || rc=$?
	case $rc in
	0) ;;
	3)
		grep '^\[MISSING\]' "$log" >&2
		missing=1
		;;
	*)
		tail -20 "$log" >&2
		echo "[FAIL] kernel/k30/pkg: $n did not roll; log $log" >&2
		exit 1
		;;
	esac
done
while read -r f; do
	echo "pkg ${f##*/} $(sha256sum < "$f" | cut -c1-64)"
done < "$KSPACE_LIST"
[ -z "$missing" ] || exit 3
