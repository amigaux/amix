#!/usr/bin/env bash
#
# build-ramdisk-floppy.sh -- the floppy pair of the RAM-disk installer medium, one pair per line
# (amix-dlm 50 §3, the RAM-disk profile; S4-52): two DD volumes holding one store -- boot1, the
# header and boot2 at the start of volume 1, then the kernel, the root-class modules and the
# line's RAM-disk image, deflated, the image running on to volume 2.
#
#   tools/build-ramdisk-floppy.sh --line k46|k30 --image IMAGE --out DIR [--work DIR]
#
#   --image  the line's RAM-disk image (tools/build-ramdisk-miniroot.sh): ufs on k46, s5 on k30
#   --out    DIR/amix-rd-LINE-1.adf and DIR/amix-rd-LINE-2.adf (901 120 bytes each)
#   --work   staging roots and specs (default: work/ramdisk-floppy)
#
# The staging roots and the per-line modules are build-ramdisk-cd.sh's (tools/lib/ramdisk-media.sh);
# the pair is `kbootset -R ROOT media --floppy V1 V2 --boot1 --boot2 ... --ramdisk IMAGE`, written by
# mkstore's floppy engine and read back whole by lsstore. The used and free bytes of volume 2 are
# printed: the image may grow into them (S4-53).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(dirname "$here")"; ws="$(dirname "$repo")"
die() { echo "build-ramdisk-floppy: STOP: $*" >&2; exit 1; }
. "$here/lib/ramdisk-media.sh"

LINE= IMG= OUT= WD="$repo/work/ramdisk-floppy"
while [ $# -gt 0 ]; do case "$1" in
  --line) LINE="$2"; shift 2;;
  --image) IMG="$2"; shift 2;;
  --out) OUT="$2"; shift 2;;
  --work) WD="$2"; shift 2;;
  *) sed -n '2,18p' "$0"; exit 2;;
esac; done
case "$LINE" in k30|k46) ;; *) die "--line must be k30 or k46";; esac
[ -f "$IMG" ] && [ -n "$OUT" ] || die "need --image and --out (see the header)"
IMG="$(cd "$(dirname "$IMG")" && pwd)/$(basename "$IMG")"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
rd_init "$WD"
rd_stage "$LINE"
V1="$OUT/amix-rd-$LINE-1.adf" V2="$OUT/amix-rd-$LINE-2.adf"
rm -f "$V1" "$V2"
( cd "$W" && "$B/kbootset" -R "stage-$LINE" media --floppy "$V1" "$V2" --boot1 "$B/boot1.img" \
    --boot2 "$B/boot2.bin" --version 3 --line "${LINE#k}" --rootdev always --rootfs "$FS" --mem "$MEM" \
    --ramdisk "$IMG" ) > "$W/media-$LINE.log" 2>&1 \
  || { tail -5 "$W/media-$LINE.log" >&2; die "$LINE: kbootset media refused the pair"; }
"$B/lsstore" "$V1" 0 "$V2" > "$W/lsstore-$LINE.txt" 2>&1 && tail -1 "$W/lsstore-$LINE.txt" | grep -q '^lsstore: ok' \
  || { tail -5 "$W/lsstore-$LINE.txt" >&2; die "lsstore does not pass the $LINE pair"; }
used=$(sed -n 's/.* \([0-9]*\) bytes used on the last volume.*/\1/p' "$W/media-$LINE.log" | tail -1)
size=$(wc -c < "$V2")
echo "build-ramdisk-floppy: $(rd_summary "$LINE" "$V1.spec")"
echo "build-ramdisk-floppy: $V1 + $V2 written; lsstore ok; volume 2: ${used:-?} of $size bytes used, $(( size - ${used:-0} )) free"
