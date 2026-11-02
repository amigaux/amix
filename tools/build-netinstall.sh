#!/usr/bin/env bash
#
# build-netinstall.sh -- the netinstall medium, form B (amix-dlm 50 §5; S4-53): a small
# bootable two-line ISO carrying one generation per line, each rooting on its line's
# netinstall RAM-disk image (tools/build-ramdisk-miniroot.sh --net --install). No packages:
# the installer reads them over HTTP (the miniroot's net_source).
#
#   tools/build-netinstall.sh --boot-mods DIR [--work DIR]
#   tools/build-netinstall.sh --k46 IMAGE --k30 IMAGE --iso OUT [--raw PREFIX] [--work DIR]
#                             [--volid ID] [--mirror-from MASTER.iso --mirror DIR]
#
# The chain this disc ends (each step's own header has the details):
#   1. tools/build-install-iso.sh --profile <the two l11 profiles> --set full --four-card
#        --stage STAGE --keep-stage --out MASTER.iso   (the installer tree and the full set)
#   2. this tool, --boot-mods DIR: each line's boot- and demand-class module objects at DIR/<line>/<name>
#        -- every `module NAME boot` record of the line's generation, the exact bytes: z3660eth
#        (S5-33) and, since catalog b1f564f4, the kernel package's ufs on k30 (s5 is the root)
#   3. tools/build-ramdisk-miniroot.sh --line k46|k30 --kb 5120 [--fp-patch] --net
#        --install STAGE --apkg-http work/l11/apkg/apkg-http --mod NAME=DIR/<line>/NAME (each)
#        ...   (one image per line)
#   4. this tool, with the two images
# --mirror-from MASTER.iso --mirror DIR: also writes the repository snapshot the matrix's
# netinstall cells serve (install-matrix.sh l11-ni-* --mirror DIR): the master's tree with
# kspace -> install/l11/kpkg -- the same packages the full set and the medium carry.
#
# The generations are build-ramdisk-cd.sh's with the netinstall module lists: the RAM disk,
# the root controllers and z3660eth as a boot-class module (50 section 5; zen0, S5-33), no
# cdfs (there is no CD to read packages from). Each image is gated against its generation by
# tools/ramdisk-image-check.py --zen0 (every boot record's path= holds its sha256=; /dev/zen0 is
# c 51,0). The disc is mastered as tools/build-iso.sh masters a CD-boot disc (System ID
# AMIGA BOOT, Rock Ridge, the loader 0755) and read back: the boot tree must pass lsstore -C.
# --raw PREFIX: form B's second half (50 section 5), PREFIX-k46.img and PREFIX-k30.img, each
# the line's generation (the disc's, byte for byte) in a read-only disk store, for a box without
# a CD drive, written whole to a disk, a CF card, a ZuluSCSI or a Z3660 SD image: an RDB (RDSK
# at block 0, 64-block cylinders, attach-safe flags) with one partition, UNIX_Boot (UNI\0,
# bootable, priority 5, two boot blocks), holding the store mkstore writes (-r; boot1/boot2 of
# the staged loader-amix), generation 1, pristine. Members raw, as on the disc; read back with
# lsstore and the RDB reader. One image per line, not one for both: the core loads a boot
# module only from /stand/gen/<booted id>/mod (the k30 generation as id 2 of a shared store
# found its z3660eth at /stand/gen/1 and refused it), and both images' RAM disks hold gen 1.
# Why mkstore and not kbootset: `media --disk` carries no RAM disk, so the store is written
# from the spec `media --cd` gated. Priority 5 wins over an installed or mkroot'd Amix disk
# (priority 2) and AmigaOS's 0: take the medium out after the install, as a CD.
# --raw-hba NAME: the controller the raw image will hang off (tools/lib/dmamask.py names); its
# DosEnvec Mask is that controller's DMA reach. The image is written to whatever disk the user has,
# so absent: the conservative 0x07FFFFFE, with a warning.
# Publication: unpublished; publishing it is a per-artefact owner decision.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(dirname "$here")"
die() { echo "build-netinstall: STOP: $*" >&2; exit 1; }

I46= I30= ISO= W="$repo/work/netinstall" VOLID=AMIX_NETINSTALL MFROM= MDIR= BMODS= RAW= RAWHBA=
while [ $# -gt 0 ]; do case "$1" in
  --boot-mods) BMODS="$2"; shift 2;;
  --raw) RAW="$2"; shift 2;;
  --raw-hba) RAWHBA="$2"; shift 2;;
  --k46) I46="$2"; shift 2;;
  --k30) I30="$2"; shift 2;;
  --iso) ISO="$2"; shift 2;;
  --work) W="$2"; shift 2;;
  --volid) VOLID="$2"; shift 2;;
  --mirror-from) MFROM="$2"; shift 2;;
  --mirror) MDIR="$2"; shift 2;;
  *) sed -n '2,47p' "$0"; exit 2;;
esac; done
L11="${L11_IN:-$repo/work/l11}"
# the netinstall generations' module lists (tools/lib/ramdisk-media.sh reads them): every disk
# controller driver the installed generation carries (so the cards number as at the first boot),
# and z3660eth for the network the packages come over
export K46_MODS="ramdisk-k46 z3660scsi-k46 a4091-k46 a4kt710-k46 gayle-k46 z3660eth-k46"
export K30_MODS="ramdisk-k30 a4091-k30 z3660scsi-k30 a4kt710-k30 gayle-k30 z3660eth-k30"
if [ -n "$BMODS" ]; then
  # step 2: stage each line as its generation will be, and hand out the boot- and demand-class objects
  ws="$(dirname "$repo")"
  . "$here/lib/ramdisk-media.sh"
  mkdir -p "$W"; rd_init "$W/cd"   # rd_init makes W the staging dir
  for l in k46 k30; do
    rd_bootmods "$l" "$BMODS" > "$W/bm-$l.names"
    grep -qx z3660eth "$W/bm-$l.names" || die "$l: the netinstall generation records no boot-class z3660eth"
    for m in $(cat "$W/bm-$l.names"); do
      f="$BMODS/$l/$m"
      echo "build-netinstall: $f ($(wc -c < "$f") bytes, sha256 $(sha256sum < "$f" | cut -c1-16))"
    done
  done
  exit 0
fi
[ -f "$I46" ] && [ -f "$I30" ] && [ -n "$ISO" ] || die "need --k46, --k30 and --iso (see the header)"
command -v xorriso > /dev/null || die "xorriso required"
mkdir -p "$W"
bash "$here/build-ramdisk-cd.sh" --k46 "$I46" --k30 "$I30" --out "$W/tree" --work "$W/cd" \
  || die "build-ramdisk-cd.sh refused the netinstall generations"
python3 "$here/ramdisk-image-check.py" --zen0 "$W/cd/gen-k46.spec" "$I46" ufs "$W/cd/gen-k30.spec" "$I30" s5 \
  || die "a netinstall image does not hold what its generation records (see above)"

root="$W/root"; rm -rf "${root:?}"; mkdir -p "$root"
cp -R "$W/tree/BOOT" "$W/tree/S" "$root/"
find "$root/BOOT" "$root/S" -type d -exec chmod 0755 {} +
find "$root/BOOT" "$root/S" -type f -exec chmod 0644 {} +
chmod 0755 "$root/BOOT/amix-cdboot"
cat > "$root/LICENSING" <<EOF
Amix 2.1 netinstall medium -- release-cleared 2026-09-23.

This disc boots the Amix 1.1 installer into memory (68030 and 68040/68060 lines); the
system's packages are read over the network from the package repository. It carries
no packages itself.

Publication: unpublished (publishing this medium is a per-artefact owner decision).
EOF
mkdir -p "$(dirname "$ISO")"; rm -f "${ISO:?}"
xorriso -as mkisofs -o "$ISO" -V "$VOLID" -publisher "amix-installng" -A "AMIX 2.1 NETINSTALL" \
  -iso-level 3 -rational-rock -sysid "AMIGA BOOT" "$root" > "$W/xorriso.log" 2>&1 \
  || { tail -5 "$W/xorriso.log" >&2; die "xorriso refused"; }
back="$W/readback"; [ ! -d "$back" ] || chmod -R u+w "$back"; rm -rf "${back:?}"; mkdir -p "$back"
xorriso -osirrox on -indev "$ISO" -extract / "$back" > /dev/null 2>&1 && chmod -R u+w "$back" || die "could not read $ISO back"
"$L11/dlm/build/lsstore" -C "$back" | tail -1 | grep -q '^lsstore: ok' || die "the boot tree on $ISO does not pass lsstore -C"
[ "$(xorriso -indev "$ISO" -pvd_info 2>/dev/null | sed -n 's/^System Id *: *//p')" = "AMIGA BOOT" ] \
  || die "$ISO's System ID is not AMIGA BOOT"
echo "build-netinstall: $ISO ($(wc -c < "$ISO") bytes, sha256 $(sha256sum < "$ISO" | cut -c1-16)); boot tree read back, lsstore -C ok"
if [ -n "$RAW" ]; then
  # form B's raw RDB images, one per line: the line's generation in a read-only disk store
  command -v rdbtool > /dev/null || die "rdbtool (amitools) required for --raw"
  DE_MASK="$(python3 "$here/dmamask.py" mask --hba "$RAWHBA" --what "raw netinstall image")" \
    || die "no DMA Mask for --raw-hba '$RAWHBA'"
  mkdir -p "$(dirname "$RAW")"; RAW="$(cd "$(dirname "$RAW")" && pwd)/$(basename "$RAW")"
  if git -C "$(dirname "$RAW")" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git -C "$(dirname "$RAW")" check-ignore -q "$RAW-k46.img" || die "$RAW-k46.img is on a git-tracked path: a disk image is never committed"
  fi
  B="$L11/dlm/build" LD="$(cd "$W/cd/stage-k46/stand/loader" && pwd)"
  LV=$(sed -n 's/^version=//p' "$LD/ldrinfo" 2>/dev/null)
  [ -f "$LD/boot1" ] && [ -f "$LD/boot2" ] && [ -n "$LV" ] || die "the staged loader-amix has no boot1/boot2/ldrinfo"
  [ "$(sha256sum < "$LD/boot2" | cut -d' ' -f1)" = "$(sed -n 's/^boot2-sha256=//p' "$LD/ldrinfo")" ] \
    || die "the staged boot2 is not the one its ldrinfo records"
  for l in k46 k30; do
    out="$RAW-$l.img"
    grep -q '^generation 1$' "$W/cd/gen-$l.spec" || die "gen-$l.spec is not generation 1 (the image's /stand/gen/1/mod)"
    # the store: every member raw, plus 1 MiB of headers and slack, in whole MiB
    mb=$(cd "$W/cd" && awk '$1 == "kernel" {print $3} $1 == "ramdisk" {print $3}
                            $1 == "module" && $3 == "root" {print $4}' "gen-$l.spec" \
         | xargs stat -c %s | awk '{s += $1} END {print int(s / 1048576) + 2}')
    SECS=64 CYLB=32768 OFFC=2
    PC=$(( mb * 1048576 / CYLB )); TOTAL=$(( OFFC + PC ))
    OFF=$(( OFFC * CYLB )) SZ=$(( PC * CYLB ))
    rm -f "${out:?}" "${out:?}.tmp"
    rdbtool -f "$out.tmp" create "chs=${TOTAL},1,${SECS}" bs=512 + init > /dev/null || die "rdbtool create refused"
    rdbtool "$out.tmp" add "start=$OFFC" "size=$PC" name=UNIX_Boot dostype=0x554e4900 bootable=1 pri=5 \
      automount=1 boot_blocks=2 "mask=$DE_MASK" max_transfer=0xffffff num_buffer=30 > /dev/null \
      || die "rdbtool add refused the boot partition"
    python3 - "$out.tmp" <<'PY' || die "could not clear the RDB flags"
import sys, struct
p = sys.argv[1]
with open(p, "r+b") as fh:
    img = bytearray(fh.read(64 * 512))
    o = next((b * 512 for b in range(64) if img[b * 512:b * 512 + 4] == b"RDSK"), None)
    if o is None:
        sys.exit("no RDSK block")
    n = struct.unpack(">I", img[o + 4:o + 8])[0]
    struct.pack_into(">I", img, o + 20, 0)     # rdb_Flags 0: attach-safe beside a higher id
    struct.pack_into(">i", img, o + 8, 0)
    s = sum(struct.unpack(">i", img[o + i * 4:o + i * 4 + 4])[0] for i in range(n)) & 0xffffffff
    struct.pack_into(">I", img, o + 8, (-s) & 0xffffffff)
    fh.seek(0)
    fh.write(img)
PY
    ( cd "$W/cd" && "$B/mkstore" -o "$out.tmp" -p "$OFF" -s "$SZ" -1 "$LD/boot1" -2 "$LD/boot2" -v "$LV" \
        -r -d 1 "gen-$l.spec" ) > "$W/raw-mkstore-$l.log" 2>&1 \
      || { tail -5 "$W/raw-mkstore-$l.log" >&2; die "$l: mkstore refused the raw image's store"; }
    [ "$(wc -c < "$out.tmp")" -eq $(( OFF + SZ )) ] || die "$l: the raw image is $(wc -c < "$out.tmp") bytes, not $(( OFF + SZ ))"
    "$B/lsstore" "$out.tmp" "$OFF" > "$W/raw-lsstore-$l.txt" 2>&1 && tail -1 "$W/raw-lsstore-$l.txt" | grep -q '^lsstore: ok' \
      || { tail -5 "$W/raw-lsstore-$l.txt" >&2; die "$l: lsstore does not pass the raw image's store"; }
    PYTHONPATH="$here/lib" python3 - "$out.tmp" "$OFF" "$SZ" <<'PY' || die "$l: the raw image's RDB does not read back"
import sys, rdb
img = open(sys.argv[1], "rb").read(1 << 16)
_, sl = rdb.read_rdb(img)
assert len(sl) == 1, "%d partitions, not one" % len(sl)
s = sl[0]
assert s.dostype == rdb.DT_BOOT and s.bootable, "slice 1 is not a bootable UNI\\0"
assert (s.byte_offset, s.byte_size) == (int(sys.argv[2]), int(sys.argv[3])), (s.byte_offset, s.byte_size)
PY
    python3 "$here/dmamask.py" check "$out.tmp" --mask "$DE_MASK" || die "$l: the DosEnvec read-back failed"
    mv "${out:?}.tmp" "${out:?}"
    echo "build-netinstall: $out ($(wc -c < "$out") bytes, sha256 $(sha256sum < "$out" | cut -c1-16)); RDB + UNIX_Boot store at $OFF, $SZ bytes, generation 1 ($l), lsstore ok"
  done
fi
if [ -n "$MFROM" ]; then
  [ -f "$MFROM" ] && [ -n "$MDIR" ] || die "--mirror-from needs the master ISO and --mirror DIR"
  [ ! -d "$MDIR" ] || chmod -R u+w "$MDIR"; rm -rf "${MDIR:?}"; mkdir -p "$MDIR"
  xorriso -osirrox on -indev "$MFROM" -extract / "$MDIR" > /dev/null 2>&1 && chmod -R u+w "$MDIR" || die "could not extract $MFROM"
  ln -s install/l11/kpkg "$MDIR/kspace"
  [ -f "$MDIR/catalog" ] && [ -f "$MDIR/kspace/catalog" ] && [ -f "$MDIR/kspace/catalog.md5" ] \
    || die "$MFROM is not a 1.1 full-set master (no catalog, kspace/catalog or its md5)"
  echo "build-netinstall: repository snapshot $MDIR ($(grep -c '|' "$MDIR/catalog") userland rows, kernel space at kspace/)"
fi
