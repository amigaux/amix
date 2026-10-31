#!/bin/sh
#
# build.sh -- the kbootset package (amix-dlm C2-3 v2 sec 4): a USERLAND
# package, rolled by the ordinary amix_pkgroll with every userland gate.
#
#     sh kernel/dlm/pkg/kbootset/build.sh     (or kernel/dlm/pkg/build.sh)
#
# Outputs ($KSPACE, common.sh):
#     $KSPACE/kbootset/dest/sbin/kbootset, opt/amix/man/{1m,whatis.d}/kbootset
#     $KSPACE/pkg/kbootset-<version>.pkg

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../common.sh"
. "$HERE/pin.sh"

PKG=kbootset
BUILD="$KSPACE/kbootset"
DEST="$BUILD/dest"
WORK="$BUILD/work"
OUT="$KSPACE/pkg/$PKG-$KB_VERSION.pkg"

echo "=== kbootset $KB_VERSION (amix-dlm $KB_DLM_COMMIT) ==="

case "$KB_DLM_COMMIT$KB_SHA" in *pending*)
	echo "[FAIL] pin.sh: the amix-dlm commit / box binary sha256 for $KB_VERSION are pending" >&2
	exit 1 ;;
esac

echo "--- build amix-dlm $KB_DLM_COMMIT ---"
amix_dlm_build "$KB_DLM_COMMIT" box/kbootset
amix_verify "$AMIX_DLM_TREE/build/box/kbootset" "$KB_SHA"

rm -rf "$BUILD"; mkdir -p "$DEST/sbin" "$DEST/var/kbootset" "$WORK"
cp "$AMIX_DLM_TREE/build/box/kbootset" "$DEST/sbin/kbootset"
# kbootset(1M) and its whatis fragment (amix userland/packages/docs/man-pages.md)
M="$DEST/opt/amix/man"
mkdir -p "$M/1m" "$M/whatis.d"
amix_verify "$AMIX_DLM_TREE/man/1m/kbootset" "$KB_MAN_SHA"
amix_verify "$AMIX_DLM_TREE/man/whatis.d/kbootset" "$KB_WHATIS_SHA"
cp "$AMIX_DLM_TREE/man/1m/kbootset" "$M/1m/kbootset"
cp "$AMIX_DLM_TREE/man/whatis.d/kbootset" "$M/whatis.d/kbootset"
# the rc scripts (-26, P-36 W8) and their run-level names, hard links of
# the one script as in stock and amix-base
mkdir -p "$DEST/etc/init.d" "$DEST/etc/rc2.d"
amix_verify "$AMIX_DLM_TREE/kbootset/rc/kbnamelist" "$KB_RC_KBNAMELIST_SHA"
amix_verify "$AMIX_DLM_TREE/kbootset/rc/kbmarkgood" "$KB_RC_KBMARKGOOD_SHA"
cp "$AMIX_DLM_TREE/kbootset/rc/kbnamelist" "$DEST/etc/init.d/kbnamelist"
cp "$AMIX_DLM_TREE/kbootset/rc/kbmarkgood" "$DEST/etc/init.d/kbmarkgood"
chmod 0744 "$DEST/etc/init.d/kbnamelist" "$DEST/etc/init.d/kbmarkgood"
ln "$DEST/etc/init.d/kbnamelist" "$DEST/etc/rc2.d/S01kbnamelist"
ln "$DEST/etc/init.d/kbmarkgood" "$DEST/etc/rc2.d/S99zkbootset"

echo "--- gates ---"
amix_gate_elf "$DEST/sbin/kbootset"
# static: no interpreter, no DT_NEEDED -- nothing on the box to resolve
if "$OBJDUMP" -p "$DEST/sbin/kbootset" 2>/dev/null | grep -Eq 'NEEDED|INTERP'; then
	echo "[FAIL] kbootset is not static" >&2; exit 1
fi
echo "  static ok  no INTERP, no NEEDED"
# built by GCC 14: the gcc14 FPU gate (no 040/060-only FPU form, which a
# 68881/68882 lacks), read with GCC 14's own objdump
_g14b="$AMIX_G14_BUILD/prefix/bin"
OBJDUMP="$_g14b/m68k-elf-objdump" READELF="$_g14b/m68k-elf-readelf" \
	amix_gate_g14_fpu "$DEST/sbin/kbootset" || exit 1

{
	echo "kbootset $KB_VERSION -- built from amix-dlm $KB_DLM_COMMIT (MIT, below)."
	echo
	echo "Statically linked with the Amiga UNIX (Amix) libc (Commodore's SVR4;"
	echo "distribution approved by Amiga Corporation on 2026-09-23), libamixc99 of"
	echo "gcc14-cross-amix (MIT, Copyright (c) 2026 Antti Sokero) and GCC 14's"
	echo "libgcc (GPL-3.0 with the GCC Runtime Library Exception)."
	echo
	cat "$AMIX_DLM_TREE/LICENSE"
} > "$WORK/copyright"

find "$DEST" -exec touch -h -d "@$KB_SOURCE_EPOCH" {} +
chmod 0755 "$DEST/sbin/kbootset" "$DEST/var" "$DEST/var/kbootset"
chmod 0644 "$M/1m/kbootset" "$M/whatis.d/kbootset"

echo "--- package ---"
kspace_epoch "$KB_SOURCE_EPOCH"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_pkgroll "$WORK" "$DEST" "$PKG" "$KB_VERSION" "$OUT"
kspace_done "$OUT"
