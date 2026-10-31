#!/bin/sh
# kitdigest.sh -- the digests of a built ABI kit, for the release lock
# (P-38 S2.1) and the dlmkit package's pin.
#
# usage: kitdigest.sh KITDIR...      one line per kit
#        kitdigest.sh -l KITDIR      the file list the manifest digest is of
#
# A line:  kit LINE KABI MANIFEST NOREV KIT_REV=<rev> PORT_REV=<rev>|-
#   MANIFEST  the sha256 of the kit's file list, one "<x|-> <sha256> <path>"
#             per file ("x" when it is executable), paths "./..." sorted in
#             C order: the digest amix-packages' dlmkit recipe pins
#             (DK_K30_MANIFEST, DK_K46_MANIFEST)
#   NOREV     the same without kit.conf and NOTICE, whose KIT_REV and
#             PORT_REV lines name the commits (the revision-line exception):
#             equal across commits when the kit's bytes are
# KABI, KIT_REV and PORT_REV are kit.conf's; k30 has no PORT_REV ("-").
#
# MIT licence, see LICENSE in kernel/dlm.
set -e

# list DIR [EXCLUDE...]: the manifest list, leaving out ./EXCLUDE
list() {
	_d=$1
	shift
	( cd "$_d" && LC_ALL=C find . -type f | LC_ALL=C sort | while read -r _f; do
		for _e in "$@"; do
			[ "$_f" = "./$_e" ] && continue 2
		done
		if [ -x "$_f" ]; then _x=x; else _x=-; fi
		echo "$_x $(sha256sum < "$_f" | cut -c1-64) $_f"
	done )
}

conf() {
	_v=$(sed -n "s/^$2=//p" "$1/kit.conf")
	echo "${_v:--}"
}

if [ "$1" = -l ]; then
	[ $# -eq 2 ] || { echo "usage: kitdigest.sh -l KITDIR" >&2; exit 2; }
	list "$2"
	exit 0
fi
[ $# -ge 1 ] || { echo "usage: kitdigest.sh KITDIR..." >&2; exit 2; }
for k in "$@"; do
	[ -f "$k/kit.conf" ] || { echo "kitdigest: $k has no kit.conf" >&2; exit 1; }
	m=$(list "$k" | sha256sum | cut -c1-64)
	n=$(list "$k" kit.conf NOTICE | sha256sum | cut -c1-64)
	echo "kit $(conf "$k" LINE) $(conf "$k" KABI) $m $n KIT_REV=$(conf "$k" KIT_REV) PORT_REV=$(conf "$k" PORT_REV)"
done
