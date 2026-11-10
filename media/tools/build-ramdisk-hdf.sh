#!/usr/bin/env bash
# build-ramdisk-hdf.sh -- the RAM-disk installer's boot as a disk: one AmigaDOS (FFS, DOS\1)
# partition holding the CD boot tree, for a machine that boots neither the install disc nor the
# floppy pair (an A4000 with no floppy route, the disc on the IDE slave).
#
#   tools/build-ramdisk-hdf.sh --cd-tree DIR --out HDF [--pri N] [--hba NAME]
#
#   --cd-tree  the RAM-disk CD boot tree (tools/build-ramdisk-cd.sh --out): S/Startup-Sequence,
#              BOOT/amix-cdboot, BOOT/K30, BOOT/K46. The disc boots the same way: Kickstart boots
#              AmigaDOS from the volume, its Startup-Sequence runs SYS:BOOT/amix-cdboot, which
#              loads the line's kernel and RAM-disk miniroot from SYS:BOOT/K30 or K46 and does
#              not return. The installer then finds the disc by its cdfs probe as from a disc boot.
#   --pri      the partition's boot priority (default 5: above an AmigaOS disk at 0 and a stock
#              Amix boot slice at 2). Take the disk out of the boot once the install is done.
#   --hba      the controller the disk hangs off (default z3660scsi): every partition's DosEnvec
#              Mask is its DMA reach (tools/dmamask.py)
#
# The partition is the tree plus a quarter and 2 MiB, to the whole MiB; the disk adds one MiB for
# the RDB. rdb_Flags is 0x00 (the boot ROM goes on to the units above it, as build-bootonly-hdf.sh).
# Beside the image: <HDF>.MANIFEST (sha256, crc32, bytes, the partition, each file's sha256).
# The image is a build artefact: never committed.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; repo="$(dirname "$here")"
. "$here/lib/media-epoch.sh"; media_epoch || exit 1
TREE= OUT= PRI=5 HBA=z3660scsi
while [ $# -gt 0 ]; do
	case "$1" in
	--cd-tree) TREE="$2"; shift 2 ;;
	--out) OUT="$2"; shift 2 ;;
	--pri) PRI="$2"; shift 2 ;;
	--hba) HBA="$2"; shift 2 ;;
	*) sed -n '2,22p' "$0"; exit 2 ;;
	esac
done
die() { echo "build-ramdisk-hdf: STOP: $*" >&2; exit 1; }
[ -n "$OUT" ] || die "--out HDF is required"
[ -f "$TREE/S/Startup-Sequence" ] && [ -f "$TREE/BOOT/amix-cdboot" ] || die "--cd-tree '$TREE' is not a RAM-disk CD boot tree (S/Startup-Sequence, BOOT/amix-cdboot)"
grep -q '^SYS:BOOT/amix-cdboot' "$TREE/S/Startup-Sequence" || die "$TREE/S/Startup-Sequence does not run SYS:BOOT/amix-cdboot"
case "$PRI" in ''|*[!0-9]*) die "--pri '$PRI' is not a boot priority (0-127)" ;; esac
[ "$PRI" -le 127 ] || die "--pri $PRI is not a boot priority (0-127)"
command -v rdbtool >/dev/null && command -v xdftool >/dev/null || die "rdbtool and xdftool (amitools) required"
# xdftool under the epoch (tools/lib/xdftool-epoch.py, amitools' own interpreter): the FFS dates of record
XDF_PY="${XDFTOOL_PY:-$(sed -n '1s/^#!//p' "$(command -v xdftool)")}"
xdf() { "$XDF_PY" "$here/lib/xdftool-epoch.py" "$@"; }
if git -C "$(dirname "$OUT")" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	git -C "$(dirname "$OUT")" check-ignore -q "$OUT" || die "$OUT is on a git-tracked path: a disk image is never committed"
fi
MASK="$(python3 "$here/dmamask.py" mask --hba "$HBA" --what "RAM-disk boot disk")" || die "no DMA Mask for --hba '$HBA'"
tree_kib=$(du -sk "$TREE" | cut -f1)
PART_MB=$(( (tree_kib * 5 / 4 + 2048 + 1023) / 1024 ))
DISK_MB=$(( PART_MB + 1 ))
W="$(mktemp -d "${OUT}.work.XXXXXX")"
trap 'rm -rf "${W:?}"' EXIT
# the volume: FFS, the tree's directories first, then every file under its own path
xdf "$W/part.hdf" create "size=${PART_MB}Mi" + format AmixBoot ffs > "$W/xdf.log" 2>&1 || { cat "$W/xdf.log" >&2; die "xdftool could not make the volume"; }
( cd "$TREE" && find . -mindepth 1 -type d | sed 's|^\./||' | sort ) | while read -r d; do
	xdf "$W/part.hdf" makedir "$d" >> "$W/xdf.log" 2>&1 || die "xdftool makedir $d"
done
( cd "$TREE" && find . -type f | sed 's|^\./||' | sort ) > "$W/files"
while read -r f; do
	xdf "$W/part.hdf" write "$TREE/$f" "$f" >> "$W/xdf.log" 2>&1 || die "xdftool write $f"
done < "$W/files"
# read every file back off the volume and compare
mkdir -p "$W/back"
while read -r f; do
	mkdir -p "$W/back/$(dirname "$f")"
	xdf "$W/part.hdf" read "$f" "$W/back/$f" >> "$W/xdf.log" 2>&1 && cmp -s "$TREE/$f" "$W/back/$f" || die "the volume's $f does not read back"
done < "$W/files"
# the disk: an RDB and the volume as its one partition, bootable at PRI
rdbtool -f "$W/disk.hdf" create "size=${DISK_MB}Mi" + init + addimg "$W/part.hdf" name=AMIXBOOT \
	bootable=1 "pri=$PRI" automount=1 "mask=$MASK" max_transfer=0xffffff num_buffer=30 > "$W/rdb.log" 2>&1 \
	|| { cat "$W/rdb.log" >&2; die "rdbtool could not make the disk"; }
python3 - "$W/disk.hdf" <<'PY'
import sys, struct
p = sys.argv[1]
with open(p, 'r+b') as fh:
    img = bytearray(fh.read(64 * 512)); rblk = None
    for b in range(64):
        if img[b*512:b*512+4] == b'RDSK': rblk = b; break
    if rblk is None: sys.exit("STOP: no RDSK block")
    o = rblk*512; summed = struct.unpack('>I', img[o+4:o+8])[0]
    struct.pack_into('>I', img, o+20, 0)            # rdb_Flags: 0x00
    struct.pack_into('>i', img, o+8, 0)
    s = sum(struct.unpack('>i', img[o+i*4:o+i*4+4])[0] for i in range(summed)) & 0xffffffff
    struct.pack_into('>I', img, o+8, (-s) & 0xffffffff)
    fh.seek(0); fh.write(img)
PY
python3 "$here/dmamask.py" check "$W/disk.hdf" --mask "$MASK" > "$W/mask.log" 2>&1 || { cat "$W/mask.log" >&2; die "the DosEnvec read-back failed"; }
show="$(rdbtool -r "$W/disk.hdf" info)"
grep -q "'AMIXBOOT'.*DOS1/0x444f5301.*auto.*boot($PRI)" <<< "$show" || { echo "$show" >&2; die "the partition does not read back as DOS1, automount, boot($PRI)"; }
mv "${W:?}/disk.hdf" "${OUT:?}"
{
	echo "# $(basename "$OUT") -- the RAM-disk installer's boot disk (AmigaDOS FFS, the CD boot tree)"
	echo "built: $(date -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y-%m-%dT%H:%M:%SZ) by media/tools/build-ramdisk-hdf.sh, amix $(git -C "$repo" rev-parse --short HEAD)$(git -C "$repo" diff --quiet -- . || echo +dirty)"
	echo "bytes: $(stat -c %s "$OUT") ($DISK_MB MiB)"
	echo "sha256: $(sha256sum < "$OUT" | cut -c1-64)"
	echo "crc32: $(python3 -c 'import sys,zlib
c=0
with open(sys.argv[1],"rb") as f:
    for b in iter(lambda: f.read(1 << 20), b""): c = zlib.crc32(b, c)
print("%08X" % c)' "$OUT")"
	echo "partition: AMIXBOOT, volume AmixBoot, DOS\\1 (FFS), ${PART_MB} MiB, bootable at priority $PRI, Mask $MASK ($HBA)"
	echo "boot: Kickstart boots the volume; S/Startup-Sequence runs SYS:BOOT/amix-cdboot (the line by CPU)"
	echo "tree: ${TREE#"$(cd "$repo/.." && pwd)"/}"
	echo "# the files (sha256)"
	while read -r f; do echo "$(sha256sum < "$TREE/$f" | cut -c1-64)  $f"; done < "$W/files"
} > "$OUT.MANIFEST"
echo "build-ramdisk-hdf: $OUT ($(stat -c %s "$OUT") bytes, ${PART_MB} MiB FFS at boot priority $PRI) sha256 $(sha256sum < "$OUT" | cut -c1-16)"
