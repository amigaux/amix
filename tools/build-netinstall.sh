#!/usr/bin/env bash
#
# build-netinstall.sh -- the netinstall medium, form B (amix-dlm 50 §5; S4-53): a small
# bootable two-line ISO carrying one generation per line, each rooting on its line's
# netinstall RAM-disk image (tools/build-ramdisk-miniroot.sh --net --install). No packages:
# the installer reads them over HTTP (the miniroot's net_source).
#
#   tools/build-netinstall.sh --k46 IMAGE --k30 IMAGE --iso OUT [--work DIR] [--volid ID]
#                             [--mirror-from MASTER.iso --mirror DIR]
#
# The chain this disc ends (each step's own header has the details):
#   1. tools/build-install-iso.sh --profile <the two l11 profiles> --set full --four-card
#        --stage STAGE --keep-stage --out MASTER.iso   (the installer tree and the full set)
#   2. tools/build-ramdisk-miniroot.sh --line k46|k30 --kb 5120 [--fp-patch] --net
#        --install STAGE --apkg-http work/l11/apkg/apkg-http ...   (one image per line)
#   3. this tool, with the two images
# --mirror-from MASTER.iso --mirror DIR: also writes the repository snapshot the matrix's
# netinstall cells serve (install-matrix.sh l11-ni-* --mirror DIR): the master's tree with
# kspace -> install/l11/kpkg -- the same packages the full set and the medium carry.
#
# The generations are build-ramdisk-cd.sh's with the netinstall module lists: the RAM disk
# and the root controllers, no cdfs (there is no CD to read packages from). The disc is
# mastered as tools/build-iso.sh masters a CD-boot disc (System ID AMIGA BOOT, Rock Ridge,
# the loader 0755) and read back: the boot tree must pass lsstore -C off the image.
# Publication: unpublished; publishing it is a per-artefact owner decision.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(dirname "$here")"
die() { echo "build-netinstall: STOP: $*" >&2; exit 1; }

I46= I30= ISO= W="$repo/work/netinstall" VOLID=AMIX_NETINSTALL MFROM= MDIR=
while [ $# -gt 0 ]; do case "$1" in
  --k46) I46="$2"; shift 2;;
  --k30) I30="$2"; shift 2;;
  --iso) ISO="$2"; shift 2;;
  --work) W="$2"; shift 2;;
  --volid) VOLID="$2"; shift 2;;
  --mirror-from) MFROM="$2"; shift 2;;
  --mirror) MDIR="$2"; shift 2;;
  *) sed -n '2,25p' "$0"; exit 2;;
esac; done
[ -f "$I46" ] && [ -f "$I30" ] && [ -n "$ISO" ] || die "need --k46, --k30 and --iso (see the header)"
command -v xorriso > /dev/null || die "xorriso required"
L11="${L11_IN:-$repo/work/l11}"
mkdir -p "$W"
K46_MODS="ramdisk-k46 z3660scsi-k46 a4091-k46" K30_MODS="ramdisk-k30 a4091-k30" \
  bash "$here/build-ramdisk-cd.sh" --k46 "$I46" --k30 "$I30" --out "$W/tree" --work "$W/cd" \
  || die "build-ramdisk-cd.sh refused the netinstall generations"

root="$W/root"; rm -rf "$root"; mkdir -p "$root"
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
mkdir -p "$(dirname "$ISO")"; rm -f "$ISO"
xorriso -as mkisofs -o "$ISO" -V "$VOLID" -publisher "amix-installng" -A "AMIX 2.1 NETINSTALL" \
  -iso-level 3 -rational-rock -sysid "AMIGA BOOT" "$root" > "$W/xorriso.log" 2>&1 \
  || { tail -5 "$W/xorriso.log" >&2; die "xorriso refused"; }
back="$W/readback"; [ ! -d "$back" ] || chmod -R u+w "$back"; rm -rf "$back"; mkdir -p "$back"
xorriso -osirrox on -indev "$ISO" -extract / "$back" > /dev/null 2>&1 && chmod -R u+w "$back" || die "could not read $ISO back"
"$L11/dlm/build/lsstore" -C "$back" | tail -1 | grep -q '^lsstore: ok' || die "the boot tree on $ISO does not pass lsstore -C"
[ "$(xorriso -indev "$ISO" -pvd_info 2>/dev/null | sed -n 's/^System Id *: *//p')" = "AMIGA BOOT" ] \
  || die "$ISO's System ID is not AMIGA BOOT"
echo "build-netinstall: $ISO ($(wc -c < "$ISO") bytes, sha256 $(sha256sum < "$ISO" | cut -c1-16)); boot tree read back, lsstore -C ok"
if [ -n "$MFROM" ]; then
  [ -f "$MFROM" ] && [ -n "$MDIR" ] || die "--mirror-from needs the master ISO and --mirror DIR"
  [ ! -d "$MDIR" ] || chmod -R u+w "$MDIR"; rm -rf "$MDIR"; mkdir -p "$MDIR"
  xorriso -osirrox on -indev "$MFROM" -extract / "$MDIR" > /dev/null 2>&1 && chmod -R u+w "$MDIR" || die "could not extract $MFROM"
  ln -s install/l11/kpkg "$MDIR/kspace"
  [ -f "$MDIR/catalog" ] && [ -f "$MDIR/kspace/catalog" ] && [ -f "$MDIR/kspace/catalog.md5" ] \
    || die "$MFROM is not a 1.1 full-set master (no catalog, kspace/catalog or its md5)"
  echo "build-netinstall: repository snapshot $MDIR ($(grep -c '|' "$MDIR/catalog") userland rows, kernel space at kspace/)"
fi
