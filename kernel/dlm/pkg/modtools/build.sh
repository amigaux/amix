#!/bin/sh
#
# build.sh -- the modtools package (amix-dlm S3-11): a USERLAND package,
# rolled by the ordinary amix_pkgroll with every userland gate.
#
#     sh kernel/dlm/pkg/modtools/build.sh     (or kernel/dlm/pkg/build.sh)
#
# Pure files since -9: the boot-class module line in /etc/inittab is amix-base's
# (inittab is its conffile, P-36 W8); -8 and earlier carried a postinstall and
# preremove for it, which stock pkgadd/pkgrm -n cannot run unattended.
#
# Outputs ($KSPACE, common.sh):
#     $KSPACE/modtools/dest/sbin/modadmin
#     $KSPACE/pkg/modtools-<version>.pkg

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../common.sh"
. "$HERE/pin.sh"

PKG=modtools
BUILD="$KSPACE/modtools"
DEST="$BUILD/dest"
WORK="$BUILD/work"
OUT="$KSPACE/pkg/$PKG-$MT_VERSION.pkg"

echo "=== modtools $MT_VERSION (amix-dlm $MT_DLM_COMMIT) ==="

case "$MT_DLM_COMMIT$MT_SHA" in *pending*)
	echo "[FAIL] pin.sh: the amix-dlm commit / box binary sha256 for $MT_VERSION are pending" >&2
	exit 1 ;;
esac

rm -rf "$BUILD"; mkdir -p "$DEST/sbin" "$WORK"
echo "--- build amix-dlm $MT_DLM_COMMIT ---"
amix_dlm_build "$MT_DLM_COMMIT" box/modadmin
amix_verify "$AMIX_DLM_TREE/build/box/modadmin" "$MT_SHA"
cp "$AMIX_DLM_TREE/build/box/modadmin" "$DEST/sbin/modadmin"

echo "--- gates ---"
amix_gate_elf "$DEST/sbin/modadmin"
# static: no interpreter, no DT_NEEDED -- nothing on the box to resolve
if "$OBJDUMP" -p "$DEST/sbin/modadmin" 2>/dev/null | grep -Eq 'NEEDED|INTERP'; then
	echo "[FAIL] modadmin is not static" >&2; exit 1
fi
echo "  static ok  no INTERP, no NEEDED"
# built by GCC 14: the gcc14 FPU gate (no 040/060-only FPU form, which a
# 68881/68882 lacks), read with GCC 14's own objdump
_g14b="$AMIX_G14_BUILD/prefix/bin"
OBJDUMP="$_g14b/m68k-elf-objdump" READELF="$_g14b/m68k-elf-readelf" \
	amix_gate_g14_fpu "$DEST/sbin/modadmin" || exit 1
echo "  size     $("$_g14b/m68k-elf-size" "$DEST/sbin/modadmin" | tail -1 | awk '{print "text " $1 ", data " $2 ", bss " $3}')"

{
	echo "modtools $MT_VERSION -- /sbin/modadmin, built from amix-dlm $MT_DLM_COMMIT."
	echo
	echo "modadmin.c is the module core's administrator (kdedon/ashnazag, MIT,"
	echo "first licence below) with amix-dlm's patch queue applied; libmod.c and"
	echo "the patches are amix-dlm's (MIT, second licence below).  Statically"
	echo "linked with the Amiga UNIX (Amix) libc (Commodore's SVR4; distribution"
	echo "approved by Amiga Corporation on 2026-09-23), libamixc99 of"
	echo "gcc14-cross-amix (MIT, Copyright (c) 2026 Antti Sokero) and GCC 14's"
	echo "libgcc (GPL-3.0 with the GCC Runtime Library Exception)."
	echo
	cat "$AMIX_DLM_TREE/core/upstream/LICENSE"
	echo
	cat "$AMIX_DLM_TREE/LICENSE"
} > "$WORK/copyright"

find "$DEST" -exec touch -h -d "@$MT_SOURCE_EPOCH" {} +
chmod 0755 "$DEST/sbin/modadmin"

echo "--- package ---"
kspace_epoch "$MT_SOURCE_EPOCH"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$MT_VERSION" "$OUT"
kspace_done "$OUT"
