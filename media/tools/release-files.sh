#!/usr/bin/env bash
# release-files.sh -- the release files of a set of images of record and media, checked.
#
#   tools/release-files.sh --images DIR [--kind 4g|ide-2g] [--media FILE]...
#
# For each DIR/amix-1.1-<line>-<kind>.img (kind 4g by default; ide-2g the IDE images): its .zip holding that one image, plain
# zip (`zip -fz-`: no zip64 -- an image is under 4 GiB, and old built-in unzippers choke on zip64),
# under 2 GiB (a release host's file cap); `zipinfo -v` must show no zip64 extra field, and
# `unzip -t` must pass. Then DIR/SHA256SUMS over the zips and the images, and the content check
# (amix's tools/release-check: no Kickstart or board ROM, no private address, local name or secret,
# no build trace; the ROM register $ROM_MANIFEST and $PRIVACY_PATTERNS, never in this repository)
# over every image and every --media file (an ISO, whose .sha256 beside it is checked too), and
# amix's tools/known-bad-modules.txt with it (no known-bad module).
# Everything goes to DIR/RELEASE-CHECK.txt. Exit 0 all clean, 1 a check failed, 2 usage.
set -uo pipefail
KIND=4g   # --kind: the images' name suffix, amix-1.1-<line>-<kind>.img
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# amix's tools/release-check is the one content check every release file passes: this checkout's
RC="$(cd "$here/../.." && pwd)/tools/release-check"
# not_release_files FILE...: names a file of the release set must not have (a raw k30 netinstall image is a
# bench medium, build-netinstall.sh --raw-k30), by its name and by the rows of a SHA256SUMS. 0 when none.
# missing_lines DIR: the kernel lines with no image in DIR; one line's image is not a release set. 0 when none.
missing_lines() {
	local L hit=0
	for L in k46 k30; do
		[ -f "$1/amix-1.1-$L-$KIND.img" ] || { echo "$L"; hit=1; }
	done
	return $hit
}
not_release_files() {
	local f hit=0
	for f in "$@"; do
		case "$(basename "$f")" in
		*netinstall-k30*) echo "$f"; hit=1 ;;
		SHA256SUMS) grep -a 'netinstall-k30' "$f" 2>/dev/null && hit=1 ;;
		esac
	done
	return $((hit == 0 ? 0 : 1))
}
if [ "${1:-}" = --selftest ]; then
	d=$(mktemp -d) || exit 1; rc=0
	: > "$d/amix-1.1-netinstall.iso"; : > "$d/amix-1.1-k30-4g.img"; echo "00  amix-1.1-install.iso" > "$d/SHA256SUMS"
	not_release_files "$d"/* > /dev/null || { echo "  FAIL the release set flagged"; rc=1; }
	: > "$d/amix-1.1-netinstall-k30.img"
	not_release_files "$d"/* > /dev/null && { echo "  FAIL a raw k30 image passed"; rc=1; }
	rm -f "${d:?}/amix-1.1-netinstall-k30.img"; echo "00  amix-1.1-netinstall-k30.img" > "$d/SHA256SUMS"
	not_release_files "$d"/* > /dev/null && { echo "  FAIL a SHA256SUMS row for it passed"; rc=1; }
	[ "$(missing_lines "$d")" = k46 ] || { echo "  FAIL k30 alone counted as the set"; rc=1; }
	: > "$d/amix-1.1-k46-4g.img"
	missing_lines "$d" > /dev/null || { echo "  FAIL both lines refused"; rc=1; }
	rm -f "${d:?}/amix-1.1-k30-4g.img"
	[ "$(missing_lines "$d")" = k30 ] || { echo "  FAIL k46 alone counted as the set"; rc=1; }
	rm -f "${d:?}/amix-1.1-k46-4g.img"
	[ "$(missing_lines "$d" | tr '\n' ' ')" = "k46 k30 " ] || { echo "  FAIL an empty directory counted as the set"; rc=1; }
	rm -rf "${d:?}"
	[ "$rc" = 0 ] && echo "release-files --selftest: PASS" || echo "release-files --selftest: FAIL"
	exit $rc
fi
IMG= MEDIA=()
while [ $# -gt 0 ]; do
	case "$1" in
	--images) IMG="$2"; shift 2 ;;
	--media) MEDIA+=("$2"); shift 2 ;;
	--kind) case "$2" in 4g|ide-2g) KIND=$2 ;; *) echo "release-files: --kind 4g|ide-2g" >&2; exit 2 ;; esac; shift 2 ;;
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
if _m=$(missing_lines "$IMG"); then :; else
	say "FAIL no image of the line(s): $(echo $_m): stop"; say "release-files: FAILED"; exit 1
fi
declare -a _mdirs=()
for m in "${MEDIA[@]+"${MEDIA[@]}"}"; do _mdirs+=("$(dirname "$m")"/*); done
if _h=$(not_release_files "$IMG"/* "${_mdirs[@]+"${_mdirs[@]}"}" "${MEDIA[@]+"${MEDIA[@]}"}"); then :; else
	say "FAIL not release files, a raw k30 image is a bench medium: $_h"; bad=1
fi
for img in "$IMG"/amix-1.1-k??-"$KIND".img; do
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
( cd "$IMG" && sha256sum amix-1.1-k??-"$KIND".zip amix-1.1-k??-"$KIND".img > SHA256SUMS ) || { say "FAIL SHA256SUMS"; bad=1; }
say "# SHA256SUMS"
cat "$IMG/SHA256SUMS" | tee -a "$R"
say "# content check"
imgs=("$IMG"/amix-1.1-k??-"$KIND".img)
for m in "${MEDIA[@]+"${MEDIA[@]}"}"; do
	[ -f "$m" ] || { say "FAIL $m: no such file"; bad=1; continue; }
	if [ -f "$m.sha256" ]; then
		( cd "$(dirname "$m")" && sha256sum -c --quiet "$(basename "$m").sha256" ) > /dev/null 2>&1 \
			&& say "sha256 $(basename "$m"): matches its .sha256" || { say "FAIL $(basename "$m"): its .sha256 does not match"; bad=1; }
	fi
	say "medium $(basename "$m"): $(stat -c %s "$m") bytes, sha256 $(sha256sum < "$m" | cut -c1-64)"
done
python3 "$RC" --rom-register "${ROM_MANIFEST:?release-files: ROM_MANIFEST names the ROM register}" --private-patterns "$PRIVACY_PATTERNS" \
	"${imgs[@]}" "${MEDIA[@]+"${MEDIA[@]}"}" 2>&1 | tee -a "$R"
[ "${PIPESTATUS[0]}" = 0 ] || bad=1
bash "$here/medium-address-check.sh" "${imgs[@]}" "${MEDIA[@]+"${MEDIA[@]}"}" 2>&1 | tee -a "$R"
[ "${PIPESTATUS[0]}" = 0 ] || bad=1
python3 "$here/public-text-check.py" --disc "${imgs[@]}" "${MEDIA[@]+"${MEDIA[@]}"}" 2>&1 | tee -a "$R"
[ "${PIPESTATUS[0]}" = 0 ] || bad=1
# the images' README is the kind's own: build-preinstalled.sh writes README.txt for 4g, README-ide-2g.txt for ide-2g
RDM=README.txt; [ "$KIND" = ide-2g ] && RDM=README-ide-2g.txt
bash "$here/sidecar-path-check.sh" "$IMG"/*.MANIFEST "$IMG/$RDM" "$IMG"/SHA256SUMS "$R" 2>&1 | tee -a "$R"
[ "${PIPESTATUS[0]}" = 0 ] || bad=1
say "release-files: $( [ $bad = 0 ] && echo 'ALL CLEAN' || echo 'FAILED')"
exit $bad
