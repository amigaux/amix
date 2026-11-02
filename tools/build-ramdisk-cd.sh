#!/usr/bin/env bash
#
# build-ramdisk-cd.sh -- the CD boot tree of the RAM-disk installer medium (amix-dlm C4-3,
# docs/plan/stage-3-cd-boot.md): one generation per line, each rooting on its line's RAM-disk
# image, written by mkstore -C for `build-install-iso.sh --cd-boot TREE`.
#
#   tools/build-ramdisk-cd.sh --boot-mods DIR [--work DIR]
#   tools/build-ramdisk-cd.sh --k46 IMAGE --k30 IMAGE --out TREE [--work DIR]
#
#   --boot-mods   each line's boot- and demand-class module objects at DIR/<line>/<name>, the
#                 exact bytes its generation records, for the images (build-ramdisk-miniroot.sh
#                 --mod NAME=DIR/<line>/NAME, one per file): cdfs on both lines (demand class,
#                 loaded at the disc's first mount) and, since catalog
#                 b1f564f4 (kernels with no built-in ufs or s5), the kernel package's ufs on k30,
#                 where s5 is the promoted root and the miniroot mounts the ufs target with it
#   --k46, --k30  the line's RAM-disk image (tools/build-ramdisk-miniroot.sh): ufs on k46,
#                 s5 on k30 -- the rootfs record follows the line
#   --out         the tree to write (BOOT/K30, BOOT/K46, BOOT/amix-cdboot, S/Startup-Sequence)
#   --work        staging roots and specs (default: work/ramdisk-cd)
#
# The staging roots and the per-line modules: tools/lib/ramdisk-media.sh. Each generation is
# `kbootset -R ROOT media --cd ... --ramdisk IMAGE`, members raw; each image is then gated
# against its generation (tools/ramdisk-image-check.py: every boot- and demand-class record's
# object in the image byte for byte, a ufs image's block size at least 4096).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(dirname "$here")"; ws="$(dirname "$repo")"
die() { echo "build-ramdisk-cd: STOP: $*" >&2; exit 1; }
. "$here/lib/ramdisk-media.sh"

I46= I30= OUT= WD="$repo/work/ramdisk-cd" BMODS=
while [ $# -gt 0 ]; do case "$1" in
  --boot-mods) BMODS="$2"; shift 2;;
  --k46) I46="$2"; shift 2;;
  --k30) I30="$2"; shift 2;;
  --out) OUT="$2"; shift 2;;
  --work) WD="$2"; shift 2;;
  *) sed -n '2,24p' "$0"; exit 2;;
esac; done
if [ -n "$BMODS" ]; then
  rd_init "$WD"
  for l in k46 k30; do
    rd_bootmods "$l" "$BMODS" > "$W/bm-$l.names"
    for n in $(cat "$W/bm-$l.names"); do
      echo "build-ramdisk-cd: $BMODS/$l/$n ($(wc -c < "$BMODS/$l/$n") bytes, sha256 $(sha256sum < "$BMODS/$l/$n" | cut -c1-16))"
    done
  done
  exit 0
fi
[ -f "$I46" ] && [ -f "$I30" ] && [ -n "$OUT" ] || die "need --k46, --k30 and --out (see the header)"
I46="$(cd "$(dirname "$I46")" && pwd)/$(basename "$I46")"
I30="$(cd "$(dirname "$I30")" && pwd)/$(basename "$I30")"
mkdir -p "$(dirname "$OUT")"; OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rd_init "$WD"

compose() {   # compose LINE IMAGE
  local l=$1 img=$2
  rd_stage "$l"
  rm -rf "${W:?}/gen-${l:?}" "${W:?}/gen-${l:?}.spec"
  ( cd "$W" && "$B/kbootset" -R "stage-$l" media --cd "gen-$l" --version 3 --line "${l#k}" \
      --rootdev always --rootfs "$FS" --mem "$MEM" --ramdisk "$img" ) > "$W/media-$l.log" 2>&1 \
    || { tail -5 "$W/media-$l.log" >&2; die "$l: kbootset media refused the generation"; }
  echo "build-ramdisk-cd: $(rd_summary "$l" "$W/gen-$l.spec")"
  rd_imgcheck "$W/gen-$l.spec" "$img"
}
compose k46 "$I46"
compose k30 "$I30"
rm -rf "${OUT:?}"
( cd "$W" && "$B/mkstore" -C "$OUT" -x "$B/amix-cdboot" gen-k30.spec gen-k46.spec ) > "$W/mkstore.log" 2>&1 \
  || { tail -5 "$W/mkstore.log" >&2; die "mkstore -C refused the generations"; }
"$B/lsstore" -C "$OUT" | tail -1 | grep -q '^lsstore: ok' || die "lsstore -C does not pass $OUT"
echo "build-ramdisk-cd: $OUT written; lsstore -C ok"
