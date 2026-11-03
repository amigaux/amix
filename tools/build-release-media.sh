#!/usr/bin/env bash
# build-release-media.sh -- the published 1.1 installer media, under their public names.
#
#   tools/build-release-media.sh --cd-tree DIR --rdm-k46 IMG --rdm-k30 IMG --out DIR
#                                [--ni-k46 IMG --ni-k30 IMG] [--set x11]
#
# Inputs ($L11_IN, the inputs of record: tools/build-l11-inputs.sh --set tools/l11-set.conf):
#   --cd-tree         the RAM-disk CD boot tree (tools/build-ramdisk-cd.sh --out) of the two lines
#   --rdm-k46/-k30    the lines' RAM-disk images (tools/build-ramdisk-miniroot.sh --kbootset ...)
#   --ni-k46/-k30     the netinstall RAM-disk images (build-ramdisk-miniroot.sh --net --install
#                     --kbootset, over this run's master stage); without them no netinstall disc
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
#   $PRIVACY_PATTERNS, the bench's local names, and the ROM register roms/MANIFEST.sha256), and
#   tools/known-bad-scan.py on every medium (no module of tools/known-bad-modules.txt).
# The master stage is kept at --out/stage (netinstall's --install takes it). Publication of any of
# these files is a separate, per-artefact decision. Exit 0 all built and clean, 1 not, 2 usage.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(dirname "$here")"
. "$here/lib/media-epoch.sh"; media_epoch || exit 1
# the workspace: the directory holding this repository's git directory (a worktree's too); amix's
# tools/release-check is the one content check every release file passes
ws="$(cd "$(dirname "$(git -C "$(dirname "$here")" rev-parse --path-format=absolute --git-common-dir)")/.." && pwd)"
# the pinned content check (amix tools/ at the set's revision, tools/build-l11-inputs.sh), not the checkout's tip
RC="${L11_IN:-$repo/work/l11}/amix-tools/release-check"
TREE= R46= R30= OUT= N46= N30= SET=x11
while [ $# -gt 0 ]; do
	case "$1" in
	--cd-tree) TREE="$2"; shift 2 ;;
	--rdm-k46) R46="$2"; shift 2 ;;
	--rdm-k30) R30="$2"; shift 2 ;;
	--ni-k46) N46="$2"; shift 2 ;;
	--ni-k30) N30="$2"; shift 2 ;;
	--out) OUT="$2"; shift 2 ;;
	--set) SET="$2"; shift 2 ;;
	*) sed -n '2,27p' "$0"; exit 2 ;;
	esac
done
die() { echo "build-release-media: STOP: $*" >&2; exit 1; }
[ -d "$TREE" ] && [ -f "$R46" ] && [ -f "$R30" ] && [ -n "$OUT" ] || { sed -n '2,6p' "$0" >&2; exit 2; }
{ [ -z "$N46$N30" ] || { [ -f "$N46" ] && [ -f "$N30" ]; }; } || die "--ni-k46 and --ni-k30 go together"
L11_IN="${L11_IN:-$repo/work/l11}"; export L11_IN
[ -x "$RC" ] && [ -n "${PRIVACY_PATTERNS:-}" ] && [ -f "$PRIVACY_PATTERNS" ] || die "needs $RC and \$PRIVACY_PATTERNS (the bench's local names)"
[ -f "$L11_IN/INPUTS" ] || die "no $L11_IN/INPUTS (tools/build-l11-inputs.sh)"
[ ! -s "$L11_IN/UNPINNED" ] || die "$L11_IN rolled userland unpinned: not inputs of record"
[ -z "$(git -C "$repo" status --porcelain)" ] || die "the tree has uncommitted changes: release media name one commit"
mkdir -p "$OUT"
W="$OUT/work"; mkdir -p "$W"
rel() {	# rel FILE -- its .sha256 beside it
	( cd "$(dirname "$1")" && sha256sum "$(basename "$1")" > "$(basename "$1").sha256" )
}
# 1. the install CD
ISO="$OUT/amix-1.1-install.iso"
rm -rf "${OUT:?}/stage" "${ISO:?}"
STAGING="$L11_IN/staging" bash "$here/build-install-iso.sh" --profile universal-k46 --profile universal-k30 --set "$SET" \
	--cd-boot "$TREE" --stage "$OUT/stage" --keep-stage --out "$ISO" > "$W/master.log" 2>&1 \
	|| { tail -15 "$W/master.log" >&2; die "build-install-iso.sh failed (work/master.log)"; }
rel "$ISO"
# 2. the floppy pairs
for L in k46 k30; do
	img="$R46"; [ $L = k30 ] && img="$R30"
	rm -rf "${W:?}/fp-${L:?}"; mkdir -p "$W/fp-$L"
	bash "$here/build-ramdisk-floppy.sh" --line $L --image "$img" --out "$W/fp-$L" --work "$W/fpw-$L" > "$W/floppy-$L.log" 2>&1 \
		|| { tail -5 "$W/floppy-$L.log" >&2; die "build-ramdisk-floppy.sh $L failed"; }
	for v in 1 2; do
		cp "$W/fp-$L/amix-rd-$L-$v.adf" "$OUT/amix-1.1-boot-$L-$v.adf" || die "no volume $v of the $L pair"
		rel "$OUT/amix-1.1-boot-$L-$v.adf"
	done
done
# 3. the Z3660 boot disk
rm -f "${OUT:?}/amix-1.1-boot-z3660.hdf"
bash "$here/build-ramdisk-hdf.sh" --cd-tree "$TREE" --out "$OUT/amix-1.1-boot-z3660.hdf" > "$W/hdf.log" 2>&1 \
	|| { tail -5 "$W/hdf.log" >&2; die "build-ramdisk-hdf.sh failed"; }
rel "$OUT/amix-1.1-boot-z3660.hdf"
# 4. the network installer
NI=
if [ -n "$N46" ]; then
	NI="$OUT/amix-1.1-netinstall.iso"
	rm -f "${NI:?}"
	bash "$here/build-netinstall.sh" --k46 "$N46" --k30 "$N30" --iso "$NI" --work "$W/ni" --volid AMIX_1_1_NETINSTALL > "$W/ni.log" 2>&1 \
		|| { tail -5 "$W/ni.log" >&2; die "build-netinstall.sh failed"; }
	rel "$NI"
fi
# 5. the record and the content check
( cd "$OUT" && sha256sum amix-1.1-*.iso amix-1.1-*.adf amix-1.1-*.hdf > SHA256SUMS )
{
	echo "# amigaux 1.1 installer media, $(date -u +%Y-%m-%dT%H:%M:%SZ), installng $(git -C "$repo" rev-parse --short HEAD)"
	echo "# inputs: $L11_IN/INPUTS"
	grep -E '^#   (dlm|kspace|dist) ' "$L11_IN/INPUTS" | sed 's/^#   /#   /'
	for f in "$OUT"/amix-1.1-*.iso "$OUT"/amix-1.1-*.adf "$OUT"/amix-1.1-*.hdf; do
		echo "$(basename "$f")  $(stat -c %s "$f") bytes  sha256 $(cut -c1-64 "$f.sha256")"
	done
} > "$OUT/MEDIA.txt"
cat "$OUT/MEDIA.txt"
python3 "$RC" --rom-register "$ws/roms/MANIFEST.sha256" --private-patterns "$PRIVACY_PATTERNS" \
	"$ISO" ${NI:+"$NI"} 2>&1 | tee "$OUT/RELEASE-CHECK.txt"
rc=${PIPESTATUS[0]}
python3 "$here/known-bad-scan.py" "$OUT"/amix-1.1-*.iso "$OUT"/amix-1.1-*.adf "$OUT"/amix-1.1-*.hdf 2>&1 \
	| tee -a "$OUT/RELEASE-CHECK.txt"
[ "${PIPESTATUS[0]}" = 0 ] || rc=1
[ "$rc" = 0 ] && echo "build-release-media: built and clean ($OUT)" || echo "build-release-media: the content check FAILED ($OUT/RELEASE-CHECK.txt)"
exit $([ "$rc" = 0 ] && echo 0 || echo 1)
