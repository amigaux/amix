#!/usr/bin/env bash
# medium-address-check.sh -- no release medium, image or RAM disk carries the repository's address.
#
#   tools/medium-address-check.sh FILE|DIR...     exit 0 clean (one line), 1 a hit (each printed)
#   tools/medium-address-check.sh --self-test
#
# pkg.amigaux.org is reached by name only, because the host may move: no hosts line, no default, no
# comment. The bytes are searched raw (an ISO and a disk hold their files whole, a package datastream is
# cpio); a deflated store is covered by scanning the RAM disk images before they are stored. The
# addresses: the host's known one, and whatever the name resolves to now.
set -u
ADDRS="52.59.174.203"
now=$(getent ahostsv4 pkg.amigaux.org 2>/dev/null | awk 'NR == 1 {print $1}')
[ -z "$now" ] || [ "$now" = "$ADDRS" ] || ADDRS="$ADDRS $now"
check() {
	local a f n hit=0 where
	for a in $ADDRS; do
		for f in "$@"; do
			if [ -d "$f" ]; then
				where=$(grep -rlaF -- "$a" "$f" 2>/dev/null | head -8)
				[ -z "$where" ] || { echo "$where" | sed "s|^|medium-address-check: $a in |"; hit=1; }
			elif [ -f "$f" ]; then
				n=$(grep -acF -- "$a" "$f")
				[ "$n" = 0 ] || { echo "medium-address-check: $a in $(basename "$f"): $n line(s)"; hit=1; }
			fi
		done
	done
	[ "$hit" = 0 ] && echo "medium-address-check: $# artefact(s), no repository address"
	return $hit
}
if [ "${1:-}" = --self-test ]; then
	t=$(mktemp -d); ok=1
	printf 'pkg.amigaux.org\n192.0.2.1\n' > "$t/good"; mkdir "$t/dgood" "$t/dbad"; cp "$t/good" "$t/dgood/f"
	printf 'x\0# echo 52.59.174.203 pkg.amigaux.org\n' > "$t/bad"; cp "$t/bad" "$t/dbad/f"
	check "$t/good" "$t/dgood" > /dev/null && echo "  ok   a file and a tree naming the host only -> clean" || { echo "  FAIL clean"; ok=0; }
	check "$t/bad" > /dev/null; [ $? = 1 ] && echo "  ok   the address in a binary file -> refused" || { echo "  FAIL file"; ok=0; }
	check "$t/dbad" > /dev/null; [ $? = 1 ] && echo "  ok   the address in a tree -> refused" || { echo "  FAIL tree"; ok=0; }
	rm -rf "${t:?}"
	echo "medium-address-check selftest: $([ "$ok" = 1 ] && echo PASS || echo FAIL)"
	[ "$ok" = 1 ]; exit $?
fi
[ $# -gt 0 ] || { sed -n '2,10p' "$0"; exit 2; }
check "$@"
