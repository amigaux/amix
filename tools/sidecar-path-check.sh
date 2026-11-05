#!/usr/bin/env bash
# sidecar-path-check.sh -- no machine path in a release file's sidecar (MEDIA.txt, *.MANIFEST,
# SHA256SUMS, *.sha256, RELEASE-CHECK.txt, README.txt): they are published with the media.
#
#   tools/sidecar-path-check.sh FILE...     exit 0 clean (one line), 1 a path found (each hit printed)
#   tools/sidecar-path-check.sh --self-test
#
# A path here is an absolute one under a home, a mount or a scratch directory, or under this
# workspace. Paths on the installed system (/opt/amix, /var/sadm ...) are not machine paths.
set -u
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ws="$(cd "$here/../../.." && pwd)"
check() {
	local n=0 hits
	for f in "$@"; do
		[ -f "$f" ] || continue
		hits=$(grep -nE "(^|[^A-Za-z0-9_.-])/(home|Users|root|mnt|nas|tmp)/" "$f"; grep -nF "$ws/" "$f")
		[ -z "$hits" ] || { echo "$hits" | sort -un | cut -c1-160 | sed "s|^|sidecar-path-check: $(basename "$f"):|"; n=1; }
	done
	[ "$n" = 0 ] && echo "sidecar-path-check: $# file(s), no machine path"
	return $n
}
if [ "${1:-}" = --self-test ]; then
	t=$(mktemp -d); ok=1
	printf 'amix-1.1-install.iso  1 bytes  sha256 ab\n# inputs: INPUTS sha256 ab\n  kernel kern46m.pkg\n/opt/amix/doc/rdate/\n' > "$t/good"
	printf '# inputs: /home/someone/work/l11/INPUTS\n' > "$t/home"
	printf 'cell: PASS (%s/x)\n' "$ws" > "$t/ws"
	printf 'a /%s/share/x\n' nas > "$t/nas"
	check "$t/good" > /dev/null && echo "  ok   a clean sidecar, with a path on the installed system -> clean" || { echo "  FAIL a clean sidecar"; ok=0; }
	for c in home ws nas; do
		check "$t/$c" > /dev/null; [ $? = 1 ] && echo "  ok   $c path -> refused" || { echo "  FAIL $c path not refused"; ok=0; }
	done
	rm -rf "${t:?}"
	echo "sidecar-path-check selftest: $([ "$ok" = 1 ] && echo PASS || echo FAIL)"
	[ "$ok" = 1 ]; exit $?
fi
[ $# -gt 0 ] || { sed -n '2,8p' "$0"; exit 2; }
check "$@"
