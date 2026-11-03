#!/usr/bin/env bash
# release-files.sh -- the release files of a set of images of record and media, checked.
#
#   tools/release-files.sh --images DIR [--media FILE]...
#
# For each DIR/amix-1.1-<line>-4g.img: DIR/amix-1.1-<line>-4g.zip holding that one image, plain
# zip (`zip -fz-`: no zip64 -- an image is under 4 GiB, and old built-in unzippers choke on zip64),
# under 2 GiB (a release host's file cap); `zipinfo -v` must show no zip64 extra field, and
# `unzip -t` must pass. Then DIR/SHA256SUMS over the zips and the images, and the content check
# (amix's tools/release-check: no Kickstart or board ROM, no private address, local name or secret,
# no build trace; the ROM register roms/MANIFEST.sha256 and $PRIVACY_PATTERNS, the bench's names)
# over every image and every --media file (an ISO, whose .sha256 beside it is checked too).
# Everything goes to DIR/RELEASE-CHECK.txt. Exit 0 all clean, 1 a check failed, 2 usage.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# the workspace: the directory holding this repository's git directory (a worktree's too); amix's
# tools/release-check is the one content check every release file passes
ws="$(cd "$(dirname "$(git -C "$(dirname "$here")" rev-parse --path-format=absolute --git-common-dir)")/.." && pwd)"
# the pinned content check (amix tools/ at the set's revision, tools/build-l11-inputs.sh), not the checkout's tip
RC="${L11_IN:-$(dirname "$here")/work/l11}/amix-tools/release-check"
IMG= MEDIA=()
while [ $# -gt 0 ]; do
	case "$1" in
	--images) IMG="$2"; shift 2 ;;
	--media) MEDIA+=("$2"); shift 2 ;;
	*) sed -n '2,14p' "$0"; exit 2 ;;
	esac
done
[ -d "$IMG" ] || { echo "release-files: --images DIR is required" >&2; exit 2; }
[ -x "$RC" ] && [ -n "${PRIVACY_PATTERNS:-}" ] && [ -f "$PRIVACY_PATTERNS" ] \
	|| { echo "release-files: needs $RC and \$PRIVACY_PATTERNS (the bench's local names)" >&2; exit 2; }
command -v zip >/dev/null && command -v zipinfo >/dev/null && command -v unzip >/dev/null \
	|| { echo "release-files: zip, zipinfo and unzip are required" >&2; exit 2; }
CAP=$((2 * 1024 * 1024 * 1024))
R="$IMG/RELEASE-CHECK.txt"
bad=0
say() { echo "$*" | tee -a "$R"; }
: > "$R"
say "# release files, $(date -u +%Y-%m-%dT%H:%M:%SZ), tools/release-files.sh"
for img in "$IMG"/amix-1.1-*-4g.img; do
	[ -f "$img" ] || continue
	b="$(basename "$img" .img)" z="$IMG/$b.zip"
	rm -f "${z:?}"
	( cd "$IMG" && zip -q -9 -fz- "$b.zip" "$b.img" ) || { say "FAIL $b.zip: zip failed"; bad=1; continue; }
	zs=$(stat -c %s "$z")
	n=$(zipinfo -1 "$z" | wc -l)
	z64=$(zipinfo -v "$z" | grep -ci 'zip64')
	unzip -tq "$z" > /dev/null 2>&1; ut=$?
	v=ok
	[ "$n" = 1 ] && [ "$(zipinfo -1 "$z")" = "$b.img" ] || { v="FAIL (not exactly $b.img inside)"; bad=1; }
	[ "$z64" = 0 ] || { v="FAIL (zip64 in zipinfo -v: $z64 line(s))"; bad=1; }
	[ "$zs" -lt "$CAP" ] || { v="FAIL ($zs bytes: not under 2 GiB)"; bad=1; }
	[ "$ut" = 0 ] || { v="FAIL (unzip -t rc $ut)"; bad=1; }
	say "zip $b.zip: $zs bytes ($(awk -v a="$zs" 'BEGIN { printf "%.1f", a / 1048576 }') MiB) holding $b.img $(stat -c %s "$img") bytes; zip64 lines in zipinfo -v: $z64; unzip -t rc $ut: $v"
done
( cd "$IMG" && sha256sum amix-1.1-*-4g.zip amix-1.1-*-4g.img > SHA256SUMS ) || { say "FAIL SHA256SUMS"; bad=1; }
say "# SHA256SUMS"
cat "$IMG/SHA256SUMS" | tee -a "$R"
say "# content check"
imgs=("$IMG"/amix-1.1-*-4g.img)
for m in "${MEDIA[@]+"${MEDIA[@]}"}"; do
	[ -f "$m" ] || { say "FAIL $m: no such file"; bad=1; continue; }
	if [ -f "$m.sha256" ]; then
		( cd "$(dirname "$m")" && sha256sum -c --quiet "$(basename "$m").sha256" ) > /dev/null 2>&1 \
			&& say "sha256 $(basename "$m"): matches its .sha256" || { say "FAIL $(basename "$m"): its .sha256 does not match"; bad=1; }
	fi
	say "medium $(basename "$m"): $(stat -c %s "$m") bytes, sha256 $(sha256sum < "$m" | cut -c1-64)"
done
python3 "$RC" --rom-register "$ws/roms/MANIFEST.sha256" --private-patterns "$PRIVACY_PATTERNS" \
	"${imgs[@]}" "${MEDIA[@]+"${MEDIA[@]}"}" 2>&1 | tee -a "$R"
[ "${PIPESTATUS[0]}" = 0 ] || bad=1
say "release-files: $( [ $bad = 0 ] && echo 'ALL CLEAN' || echo 'FAILED')"
exit $bad
