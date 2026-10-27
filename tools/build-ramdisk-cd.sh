#!/usr/bin/env bash
#
# build-ramdisk-cd.sh -- the CD boot tree of the RAM-disk installer medium (amix-dlm C4-3,
# docs/plan/stage-3-cd-boot.md): one generation per line, each rooting on its line's RAM-disk
# image, written by mkstore -C for `build-install-iso.sh --cd-boot TREE`.
#
#   tools/build-ramdisk-cd.sh --k46 IMAGE --k30 IMAGE --out TREE [--work DIR]
#
#   --k46, --k30  the line's RAM-disk image (tools/build-ramdisk-miniroot.sh): ufs on k46,
#                 s5 on k30 -- the rootfs record follows the line
#   --out         the tree to write (BOOT/K30, BOOT/K46, BOOT/amix-cdboot, S/Startup-Sequence)
#   --work        staging roots and specs (default: work/ramdisk-cd)
#
# Per line, a staging root gets the loader, the kernel and the line's modules from the
# medium's kernel-space catalog (work/l11/kpkg, tools/build-l11-inputs.sh), installed by the
# host apkg of that build through a pkgadd that only unpacks (device nodes are not needed to
# compose); then `kbootset -R ROOT media --cd ... --ramdisk IMAGE` composes the generation.
#   k46: ramdisk, z3660scsi and a4091 (root class: the disc sits on an A4091 in the rigs),
#        cdfs (boot class, from the image's /stand/gen/1/mod)
#   k30: ramdisk and a4091, cdfs (boot class; kern30m links no static cdfs since -17)
# K46_MODS / K30_MODS override the module lists.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; repo="$(dirname "$here")"; ws="$(dirname "$repo")"
die() { echo "build-ramdisk-cd: STOP: $*" >&2; exit 1; }

I46= I30= OUT= W="$repo/work/ramdisk-cd"
while [ $# -gt 0 ]; do case "$1" in
  --k46) I46="$2"; shift 2;;
  --k30) I30="$2"; shift 2;;
  --out) OUT="$2"; shift 2;;
  --work) W="$2"; shift 2;;
  *) sed -n '2,23p' "$0"; exit 2;;
esac; done
[ -f "$I46" ] && [ -f "$I30" ] && [ -n "$OUT" ] || die "need --k46, --k30 and --out (see the header)"
L11="${L11_IN:-$repo/work/l11}"
B="$L11/dlm/build"; APKG="$L11/apkg/apkg-host"
for f in "$B/kbootset" "$B/mkstore" "$B/lsstore" "$B/amix-cdboot" "$APKG" "$L11/kpkg/catalog"; do
  [ -e "$f" ] || die "$f missing (tools/build-l11-inputs.sh --set tools/l11-set.conf)"
done
PKGTRANS="$ws/amix-packagemanager/heirloom/build-host/bin/pkgtrans"
[ -x "$PKGTRANS" ] || die "no host pkgtrans at $PKGTRANS"
K46_MODS="${K46_MODS:-ramdisk-k46 cdfs-k46 z3660scsi-k46 a4091-k46}"
K30_MODS="${K30_MODS:-ramdisk-k30 cdfs-k30 a4091-k30}"
I46="$(cd "$(dirname "$I46")" && pwd)/$(basename "$I46")"
I30="$(cd "$(dirname "$I30")" && pwd)/$(basename "$I30")"
mkdir -p "$(dirname "$OUT")"; OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

mkdir -p "$W/bin"
# the unpacking pkgadd apkg calls: files and directories into -R, the contents file kept
cat > "$W/bin/pkgadd" <<P
#!/bin/bash
T=; F=; I=
while [ \$# -gt 0 ]; do case "\$1" in -R) T=\$2; shift 2;; -d) F=\$2; shift 2;; -a) shift 2;; -n) shift;; *) I=\$1; shift;; esac; done
U=\$(mktemp -d "$W/unpack.XXXXXX")
"$PKGTRANS" "\$F" "\$U" "\$I" >/dev/null 2>&1 || exit 1
C=\$T/var/sadm/install/contents; mkdir -p "\$(dirname "\$C")"; touch "\$C"
mkdir -p "\$T/var/sadm/pkg/\$I"; cp "\$U/\$I/pkginfo" "\$T/var/sadm/pkg/\$I/pkginfo"
while read -r part type class path mode owner group size cks mtime; do
	case "\$type" in
	d) mkdir -p "\$T\$path"; echo "\$path d \$class \$mode \$owner \$group \$I" >> "\$C" ;;
	f) mkdir -p "\$(dirname "\$T\$path")"; cp "\$U/\$I/root\$path" "\$T\$path"; chmod "\$mode" "\$T\$path"
	   echo "\$path f \$class \$mode \$owner \$group \$size \$cks \$mtime \$I" >> "\$C" ;;
	esac
done < "\$U/\$I/pkgmap"
rm -rf "\$U"
P
chmod 0755 "$W/bin/pkgadd"
printf 'mail=\ninstance=overwrite\naction=nocheck\n' > "$W/admin"

compose() {   # compose LINE IMAGE FS MEM MODS
  local l=$1 img=$2 fs=$3 mem=$4 mods=$5 t="$W/stage-$1"
  rm -rf "$t" "$W/cache-$l" "$W/gen-$l" "$W/gen-$l.spec"
  mkdir -p "$t/etc/default" "$t/var/apkg" "$t/var/kbootset" "$t/stand"
  printf 'bootset=manual\n' > "$t/etc/default/bootset"
  cat > "$W/apkg-$l.conf" <<C
repo=file://$L11/kpkg
cachedir=$W/cache-$l
admin=$W/admin
pkgadd=$W/bin/pkgadd
pkgrm=/bin/false
kbootset=$B/kbootset
C
  "$APKG" -c "$W/apkg-$l.conf" update > "$W/apkg-$l.log" 2>&1
  # shellcheck disable=SC2086
  "$APKG" -c "$W/apkg-$l.conf" -R "$t" install loader-amix "kernel-$l-m" $mods >> "$W/apkg-$l.log" 2>&1 \
    || { tail -5 "$W/apkg-$l.log" >&2; die "$l: apkg could not stage $mods"; }
  ( cd "$W" && "$B/kbootset" -R "stage-$l" media --cd "gen-$l" --version 3 --line "${l#k}" \
      --rootdev always --rootfs "$fs" --mem "$mem" --ramdisk "$img" ) > "$W/media-$l.log" 2>&1 \
    || { tail -5 "$W/media-$l.log" >&2; die "$l: kbootset media refused the generation"; }
  echo "build-ramdisk-cd: $l: $(grep -E '^kernel-build' "$W/gen-$l.spec"), rootfs $fs, modules:" \
       "$(grep -E '^module ' "$W/gen-$l.spec" | awk '{print $2 "(" $3 ")"}' | tr '\n' ' ')"
}
# --mem: the box memory kbootset's gates assume for the placement (k30 is held to 64 MiB)
compose k46 "$I46" ufs 33554432 "$K46_MODS"
compose k30 "$I30" s5 67108864 "$K30_MODS"
rm -rf "$OUT"
( cd "$W" && "$B/mkstore" -C "$OUT" -x "$B/amix-cdboot" gen-k30.spec gen-k46.spec ) > "$W/mkstore.log" 2>&1 \
  || { tail -5 "$W/mkstore.log" >&2; die "mkstore -C refused the generations"; }
"$B/lsstore" -C "$OUT" | tail -1 | grep -q '^lsstore: ok' || die "lsstore -C does not pass $OUT"
echo "build-ramdisk-cd: $OUT written; lsstore -C ok"
