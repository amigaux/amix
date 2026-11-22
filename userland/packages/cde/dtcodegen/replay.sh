#!/bin/sh
# replay.sh ARGS... -- dtcodegen in the build of dtbuilder and ttsnoop (build.sh sets
# make's DTCODEGEN to it): writes what the target dtcodegen wrote, run with the same
# ARGS on Amix in the same state of the directory (README, The App Builder's code);
# dtcodegen's own log, .dtcodegen.log, is not kept or written.
# Fails, so the build stops, when the directory is not in that state.
# MIT licence, see LICENSE in userland/packages.
here=$(dirname "$0")
case $(pwd) in
*/programs/dtappbuilder/src/ab) set_=ab ;;
*/programs/ttsnoop) set_=tt ;;
*) echo "replay: no recorded dtcodegen runs for $(pwd)" >&2; exit 1 ;;
esac
a="$*"
d=
for r in "$here/$set_"/*/; do
	[ "$(cat "$r/args")" = "$a" ] && { d=${r%/}; break; }
done
[ -n "$d" ] || { echo "replay: no recorded run of dtcodegen $a in $set_" >&2; exit 1; }
# the run's inputs and the earlier contents of every file it rewrote, as they were on Amix
sha256sum -c --quiet --strict "$d/before.sha256" >&2 || {
	echo "replay: $set_: the directory is not as it was for dtcodegen $a" >&2; exit 1; }
while read -r f; do
	[ ! -e "$f" ] || { echo "replay: $set_: $f exists; dtcodegen $a created it" >&2; exit 1; }
done < "$d/created"
while read -r f; do
	rm -f -- "./${f#./}"
done < "$d/removed"
# what it created, whole; what it rewrote with other contents, as diffs
if [ -d "$d/after" ]; then
	( cd "$d/after" && find . -type f ) | while read -r f; do
		mkdir -p "$(dirname "$f")"
		cp -- "$d/after/$f" "$f"
	done
fi
if [ -d "$d/diffs" ]; then
	( cd "$d/diffs" && find . -type f -name '*.diff' ) | LC_ALL=C sort | while read -r f; do
		patch -s -p1 --batch --fuzz=0 --no-backup-if-mismatch < "$d/diffs/$f" || {
			echo "replay: $set_: $f does not apply" >&2; exit 1; }
	done
fi
