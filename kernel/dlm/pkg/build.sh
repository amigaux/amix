#!/bin/sh
# build.sh -- kernel/dlm's kernel-space packages (P-38 S3.3): loader-amix,
# kbootset, modtools, dlmkit (dlmkit30 and dlmkit46).
#
# usage: sh kernel/dlm/pkg/build.sh [name...]      (default: all four)
#
# make dist's kspace step calls it (build/dist.sh). Each recipe's
# datastreams go to $AMIX_BUILD_ROOT/kspace/pkg/ (out/pkg/kspace/pkg/
# unless AMIX_BUILD_ROOT is set), its log to $AMIX_BUILD_ROOT/kspace/log/;
# on standard output one line per datastream, `pkg <file> <sha256>`.
# Exit status 1 on any failure (the recipe's log's tail on standard error),
# 2 for usage.
#
# MIT licence, see LICENSE in kernel/dlm.
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
ALL="loader-amix kbootset modtools dlmkit"
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

for n in $names; do
	log="$root/kspace/log/$n.log"
	if ! sh "$HERE/$n/build.sh" > "$log" 2>&1; then
		tail -20 "$log" >&2
		echo "[FAIL] kernel/dlm/pkg: $n did not roll; log $log" >&2
		exit 1
	fi
done
while read -r f; do
	echo "pkg ${f##*/} $(sha256sum < "$f" | cut -c1-64)"
done < "$KSPACE_LIST"
