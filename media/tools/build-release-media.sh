#!/usr/bin/env bash
# build-release-media.sh -- the installer media of a release, under their public names (media/build.sh runs it).
#
#   tools/build-release-media.sh --cd-tree DIR --rdm-k46 IMG --rdm-k30 IMG --out DIR
#                                [--ni-k46 IMG --ni-k30 IMG] [--set x11] [--release 1.1]
#
# Inputs ($L11_IN, laid out by media/build.sh from make dist's out/):
#   --cd-tree         the RAM-disk CD boot tree (tools/build-ramdisk-cd.sh --out) of the two lines
#   --rdm-k46/-k30    the lines' RAM-disk images (pinned inputs, media/inputs/; authored on an Amix box)
#   --ni-k46/-k30     the netinstall RAM-disk images (the same); without them no netinstall disc
# Names below say 1.1 for --release 1.1.
# Writes to --out:
#   amix-1.1-install.iso             the one install CD for every 1.1 target, both lines
#                                    (tools/build-install-iso.sh --profile universal-k46
#                                    --profile universal-k30, the --set offered, CD-bootable)
#   amix-1.1-boot-k46-1.adf, -2.adf  the floppy pairs that boot it (tools/build-ramdisk-floppy.sh)
#   amix-1.1-boot-k30-1.adf, -2.adf
#   amix-1.1-boot-z3660.hdf          the same boot as an AmigaOS disk for a Z3660 without a floppy
#                                    (tools/build-ramdisk-hdf.sh, priority 5)
#   amix-1.1-netinstall.iso          (with --ni-*) the network installer (tools/build-netinstall.sh)
#   <each>.sha256, SHA256SUMS, MEDIA.txt (names, sizes, sha256, the inputs) and the content check
#   (amix's tools/release-check on every ISO: no ROM, no private address, name or secret; needs
#   $ROM_MANIFEST and $PRIVACY_PATTERNS, or RELEASE_PUBLIC=1 for its public tests only), and
#   amix's tools/known-bad-modules.txt with it (no known-bad module: release-check searches by piece hashes).
# The master stage is kept at --out/stage (netinstall's --install takes it). Publication of any of
# these files is a separate, per-artefact decision. Exit 0 all built and clean, 1 not, 2 usage.
set -uo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; repo="$(dirname "$here")"
. "$here/lib/media-epoch.sh"; media_epoch || exit 1
. "$here/lib/media-paths.sh"
# amix's tools/release-check is the one content check every release file passes: this checkout's
RC="$MEDIA_TOP/tools/release-check"
# wipe_earlier OUT: nothing from an earlier build may pass as this one's, nor be counted in its record
wipe_earlier() {
	rm -f "${1:?}"/amix-*.iso "${1:?}"/amix-*.adf "${1:?}"/amix-*.hdf "${1:?}"/amix-*.sha256 \
		"${1:?}"/amix-*.MANIFEST "${1:?}/SHA256SUMS" "${1:?}/MEDIA.txt" "${1:?}/RELEASE-CHECK.txt"
}
# cdboot_same WANT NAME FILE -- FILE (the cd-tree's, or one read back off a disc) must be WANT byte for byte
cdboot_same() {
	[ -f "$3" ] && cmp -s "$1" "$3" && return 0
	echo "build-release-media: $2's BOOT/amix-cdboot is not make dist's (sha256 $(sha256sum < "$1" | cut -c1-16)," \
		"this one $( [ -f "$3" ] && sha256sum < "$3" | cut -c1-16 || echo missing))" >&2
	return 1
}
if [ "${1:-}" = --selftest ]; then
	d=$(mktemp -d) || exit 1; rc=0
	printf 'cdboot-a' > "$d/w"; printf 'cdboot-a' > "$d/same"; printf 'cdboot-b' > "$d/other"
	cdboot_same "$d/w" t "$d/same" || { echo "  FAIL cdboot_same refuses the same bytes"; rc=1; }
	cdboot_same "$d/w" t "$d/other" 2>/dev/null && { echo "  FAIL cdboot_same takes other bytes"; rc=1; }
	cdboot_same "$d/w" t "$d/none" 2>/dev/null && { echo "  FAIL cdboot_same takes a missing file"; rc=1; }
	rm -f "${d:?}/w" "${d:?}/same" "${d:?}/other"
	for f in amix-1.1-install.iso amix-1.1-netinstall.iso amix-1.1-netinstall.iso.sha256 amix-1.1-boot-k46-1.adf amix-1.1-boot-z3660.hdf \
		amix-1.1-install.iso.MANIFEST SHA256SUMS MEDIA.txt RELEASE-CHECK.txt keep.txt; do : > "$d/$f"; done
	mkdir "$d/work"
	wipe_earlier "$d"
	[ "$(ls -A "$d" | tr '\n' ' ')" = "keep.txt work " ] || { echo "  FAIL left behind: $(ls -A "$d" | tr '\n' ' ')"; rc=1; }
	rm -rf "${d:?}"
	[ "$rc" = 0 ] && echo "build-release-media --selftest: PASS" || echo "build-release-media --selftest: FAIL"
	exit $rc
fi
TREE= R46= R30= OUT= N46= N30= SET=x11 REL=1.1
while [ $# -gt 0 ]; do
	case "$1" in
	--cd-tree) TREE="$2"; shift 2 ;;
	--rdm-k46) R46="$2"; shift 2 ;;
	--rdm-k30) R30="$2"; shift 2 ;;
	--ni-k46) N46="$2"; shift 2 ;;
	--ni-k30) N30="$2"; shift 2 ;;
	--out) OUT="$2"; shift 2 ;;
	--set) SET="$2"; shift 2 ;;
	--release) REL="$2"; shift 2 ;;
	*) sed -n '2,27p' "$0"; exit 2 ;;
	esac
done
die() { echo "build-release-media: STOP: $*" >&2; exit 1; }
[ -d "$TREE" ] && [ -f "$R46" ] && [ -f "$R30" ] && [ -n "$OUT" ] || { sed -n '2,6p' "$0" >&2; exit 2; }
{ [ -z "$N46$N30" ] || { [ -f "$N46" ] && [ -f "$N30" ]; }; } || die "--ni-k46 and --ni-k30 go together"
[ -x "$RC" ] || die "no $RC"
# a public rebuild (RELEASE_PUBLIC=1) has no ROM register and no private list: the check's public tests
if [ -n "${RELEASE_PUBLIC:-}" ]; then
	ROM_MANIFEST="${ROM_MANIFEST:-}" PRIVACY_PATTERNS="${PRIVACY_PATTERNS:-}"
else
	[ -n "${ROM_MANIFEST:-}" ] && [ -f "$ROM_MANIFEST" ] && [ -n "${PRIVACY_PATTERNS:-}" ] && [ -f "$PRIVACY_PATTERNS" ] \
		|| die "needs \$ROM_MANIFEST and \$PRIVACY_PATTERNS (never in this repository), or RELEASE_PUBLIC=1"
fi
[ -f "$L11_IN/INPUTS" ] || die "no $L11_IN/INPUTS (media/build.sh)"
mkdir -p "$OUT"
wipe_earlier "$OUT"
W="$OUT/work"; mkdir -p "$W"
rel() {	# rel FILE -- its .sha256 beside it
	( cd "$(dirname "$1")" && sha256sum "$(basename "$1")" > "$(basename "$1").sha256" )
}
# 1. the install CD
ISO="$OUT/amix-$REL-install.iso"
rm -rf "${OUT:?}/stage" "${ISO:?}"
STAGING="$L11_IN/staging" bash "$here/build-install-iso.sh" --profile universal-k46 --profile universal-k30 --set "$SET" \
	--cd-boot "$TREE" --stage "$OUT/stage" --keep-stage --out "$ISO" > "$W/master.log" 2>&1 \
	|| { tail -15 "$W/master.log" >&2; die "build-install-iso.sh failed (work/master.log)"; }
rel "$ISO"
# what the disc runs, read back: every pkgtools binary on it is the one this round's inputs built
_rb="$W/iso-readback"; [ ! -d "$_rb" ] || chmod -R u+w "$_rb"; rm -rf "${_rb:?}"; mkdir -p "$_rb"
xorriso -osirrox on -indev "$ISO" -extract /install/bin "$_rb/bin" -extract /install/l11/bin "$_rb/l11" > /dev/null 2>&1 \
	|| die "cannot read /install/bin back from $ISO"
chmod -R u+w "$_rb"
_st="$L11_IN/pkgtools/heirloom/build-amix-static"
for _b in bin/pkgadd:bin/pkgadd bin/pkgtrans:bin/pkgtrans bin/pkginfo:bin/pkginfo bin/pkgchk:bin/pkgchk \
	bin/contents-fsck:bin/contents-fsck sadm-helpers/pkginstall:bin/pkginstall bin/apkg:bin/apkg; do
	cmp -s "$_st/${_b%%:*}" "$_rb/${_b#*:}" || die "the disc's /install/${_b#*:} is not the inputs' ${_b%%:*}"
done
cmp -s "$L11_IN/apkg/apkg" "$_rb/l11/apkg" || die "the disc's /install/l11/bin/apkg is not the inputs' apkg"
# the CD boot program is make dist's (the inputs' kspace beside/amix-cdboot, media/build.sh): the
# cd-tree's, and every disc's read back; inputs without one make a trial only, with MEDIA_CDBOOT_ANY=1
CDB="$L11_IN/kspace-beside/amix-cdboot" CDB_NOTE=
if [ -f "$CDB" ]; then
	xorriso -osirrox on -indev "$ISO" -extract /BOOT/amix-cdboot "$_rb/amix-cdboot" > /dev/null 2>&1
	cdboot_same "$CDB" "the cd-tree" "$TREE/BOOT/amix-cdboot" && cdboot_same "$CDB" "$(basename "$ISO")" "$_rb/amix-cdboot" \
		|| die "the media must carry make dist's amix-cdboot"
	CDB_NOTE="amix-cdboot sha256 $(sha256sum < "$CDB" | cut -c1-64), make dist's (kspace beside/)"
else
	[ "${MEDIA_CDBOOT_ANY:-0}" = 1 ] || die "the inputs carry no amix-cdboot from make dist's kspace (beside/): MEDIA_CDBOOT_ANY=1 for a trial"
	CDB_NOTE="amix-cdboot sha256 $(sha256sum < "$TREE/BOOT/amix-cdboot" | cut -c1-64), NOT make dist's: a trial (MEDIA_CDBOOT_ANY=1)"
fi
# 2. the floppy pairs
for L in k46 k30; do
	img="$R46"; [ $L = k30 ] && img="$R30"
	rm -rf "${W:?}/fp-${L:?}"; mkdir -p "$W/fp-$L"
	bash "$here/build-ramdisk-floppy.sh" --line $L --image "$img" --out "$W/fp-$L" --work "$W/fpw-$L" > "$W/floppy-$L.log" 2>&1 \
		|| { tail -5 "$W/floppy-$L.log" >&2; die "build-ramdisk-floppy.sh $L failed"; }
	for v in 1 2; do
		cp "$W/fp-$L/amix-rd-$L-$v.adf" "$OUT/amix-$REL-boot-$L-$v.adf" || die "no volume $v of the $L pair"
		rel "$OUT/amix-$REL-boot-$L-$v.adf"
	done
done
# 3. the Z3660 boot disk
rm -f "${OUT:?}/amix-${REL:?}-boot-z3660.hdf"
bash "$here/build-ramdisk-hdf.sh" --cd-tree "$TREE" --out "$OUT/amix-$REL-boot-z3660.hdf" > "$W/hdf.log" 2>&1 \
	|| { tail -5 "$W/hdf.log" >&2; die "build-ramdisk-hdf.sh failed"; }
rel "$OUT/amix-$REL-boot-z3660.hdf"
# 4. the network installer
NI=
if [ -n "$N46" ]; then
	NI="$OUT/amix-$REL-netinstall.iso"
	rm -f "${NI:?}"
	bash "$here/build-netinstall.sh" --k46 "$N46" --k30 "$N30" --iso "$NI" --work "$W/ni" --volid "AMIX_$(echo "$REL" | tr . _)_NETINSTALL" > "$W/ni.log" 2>&1 \
		|| { tail -5 "$W/ni.log" >&2; die "build-netinstall.sh failed"; }
	if [ -f "$CDB" ]; then
		xorriso -osirrox on -indev "$NI" -extract /BOOT/amix-cdboot "$_rb/ni-amix-cdboot" > /dev/null 2>&1
		cdboot_same "$CDB" "$(basename "$NI")" "$_rb/ni-amix-cdboot" || die "the media must carry make dist's amix-cdboot"
	fi
	rel "$NI"
fi
# 5. the record and the content check
( cd "$OUT" && sha256sum amix-"$REL"-*.iso amix-"$REL"-*.adf amix-"$REL"-*.hdf > SHA256SUMS )
{
	# the date is the epoch the media are stamped with, never the clock: the same inputs give the same record
	echo "# amigaux $REL installer media, $(date -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y-%m-%dT%H:%M:%SZ), amix $(sed -n 's/^amix //p' "$L11_IN/INPUTS")"
	# published with the media: the inputs by their record's hash, no machine path
	echo "# inputs: INPUTS sha256 $(sha256sum < "$L11_IN/INPUTS" | cut -c1-64)"
	grep -E '^(tool|ramdisk) ' "$L11_IN/INPUTS" | sed 's/^/#   /'
	echo "# $CDB_NOTE"
	for f in "$OUT"/amix-"$REL"-*.iso "$OUT"/amix-"$REL"-*.adf "$OUT"/amix-"$REL"-*.hdf; do
		echo "$(basename "$f")  $(stat -c %s "$f") bytes  sha256 $(cut -c1-64 "$f.sha256")"
	done
} > "$OUT/MEDIA.txt"
cat "$OUT/MEDIA.txt"
python3 "$RC" ${ROM_MANIFEST:+--rom-register "$ROM_MANIFEST"} ${PRIVACY_PATTERNS:+--private-patterns "$PRIVACY_PATTERNS"} \
	${RELEASE_PUBLIC:+--public} "$ISO" ${NI:+"$NI"} "$OUT"/amix-"$REL"-*.adf "$OUT"/amix-"$REL"-*.hdf "$R46" "$R30" ${N46:+"$N46"} ${N30:+"$N30"} 2>&1 | tee "$OUT/RELEASE-CHECK.txt"
rc=${PIPESTATUS[0]}
# the repository by name only: the media, the master stage, and the RAM disks before they are deflated
bash "$here/medium-address-check.sh" "$OUT"/amix-"$REL"-*.iso "$OUT"/amix-"$REL"-*.adf "$OUT"/amix-"$REL"-*.hdf "$OUT/stage" "$R46" "$R30" ${N46:+"$N46"} ${N30:+"$N30"} 2>&1 \
	| tee -a "$OUT/RELEASE-CHECK.txt"
[ "${PIPESTATUS[0]}" = 0 ] || rc=1
# no process words: the media and the RAM disks before they are deflated by label, the master stage's own text in full
python3 "$here/public-text-check.py" --disc "$OUT"/amix-"$REL"-*.iso "$OUT"/amix-"$REL"-*.adf "$OUT"/amix-"$REL"-*.hdf "$R46" "$R30" ${N46:+"$N46"} ${N30:+"$N30"} 2>&1 \
	| tee -a "$OUT/RELEASE-CHECK.txt"
[ "${PIPESTATUS[0]}" = 0 ] || rc=1
python3 "$here/public-text-check.py" --stage "$OUT/stage" 2>&1 | tee -a "$OUT/RELEASE-CHECK.txt"
[ "${PIPESTATUS[0]}" = 0 ] || rc=1
bash "$here/sidecar-path-check.sh" "$OUT"/MEDIA.txt "$OUT"/SHA256SUMS "$OUT"/*.sha256 "$OUT"/*.MANIFEST "$OUT"/RELEASE-CHECK.txt 2>&1 \
	| tee -a "$OUT/RELEASE-CHECK.txt"
[ "${PIPESTATUS[0]}" = 0 ] || rc=1
[ "$rc" = 0 ] && echo "build-release-media: built and clean ($OUT)" || echo "build-release-media: the content check FAILED ($OUT/RELEASE-CHECK.txt)"
exit $([ "$rc" = 0 ] && echo 0 || echo 1)
