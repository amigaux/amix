#!/bin/sh
#
# build.sh -- the loader package (amix-dlm C2-3 v2 sec 3).
#
#     sh kernel/dlm/pkg/loader-amix/build.sh     (or kernel/dlm/pkg/build.sh)
#
# Outputs ($KSPACE, common.sh):
#     $KSPACE/loader-amix/dest/stand/loader/{boot1,boot2,ldrinfo}
#     $KSPACE/pkg/ldramix-<version>.pkg

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../common.sh"
. "$HERE/pin.sh"

BUILD="$KSPACE/$LDR_CATALOG_NAME"
DEST="$BUILD/dest"
WORK="$BUILD/work"
OUT="$KSPACE/pkg/$LDR_PKG-$LDR_PKG_VERSION.pkg"

echo "=== $LDR_CATALOG_NAME $LDR_PKG_VERSION (PKG=$LDR_PKG, loader version $LDR_VERSION) ==="

echo "--- build amix-dlm $LDR_DLM_COMMIT ---"
amix_dlm_build "$LDR_DLM_COMMIT" boot1.img boot2.bin
# LOADER_VERSION: a number in b2.h, or (since 124b86c) AX_LOADER_VERSION of
# loader/common/store.h
_lv=$(sed -n 's/^#define[ 	]*LOADER_VERSION[ 	]*\([A-Za-z0-9_]*\).*/\1/p' "$AMIX_DLM_TREE/loader/boot2/b2.h")
[ "$_lv" = AX_LOADER_VERSION ] && _lv=$(sed -n 's/^#define[ 	]*AX_LOADER_VERSION[ 	]*\([0-9]*\).*/\1/p' \
	"$AMIX_DLM_TREE/loader/common/store.h")
[ "$_lv" = "$LDR_VERSION" ] || {
	echo "[FAIL] amix-dlm $LDR_DLM_COMMIT LOADER_VERSION is ${_lv:-unset}, not $LDR_VERSION" >&2; exit 1; }
echo "  LOADER_VERSION $_lv"
amix_verify "$AMIX_DLM_TREE/build/boot1.img" "$LDR_BOOT1_SHA"
amix_verify "$AMIX_DLM_TREE/build/boot2.bin" "$LDR_BOOT2_SHA"
[ "$(stat -c%s "$AMIX_DLM_TREE/build/boot1.img")" = "$LDR_BOOT1_SIZE" ] \
	&& [ "$(stat -c%s "$AMIX_DLM_TREE/build/boot2.bin")" = "$LDR_BOOT2_SIZE" ] || {
	echo "[FAIL] boot1/boot2 sizes are not the pinned ones" >&2; exit 1; }

rm -rf "$BUILD"; mkdir -p "$DEST/stand/loader" "$WORK"
cp "$AMIX_DLM_TREE/build/boot1.img" "$DEST/stand/loader/boot1"
cp "$AMIX_DLM_TREE/build/boot2.bin" "$DEST/stand/loader/boot2"
# ldrinfo: one key=value per line, the C2-3 v2 sec 3 keys in its order
cat > "$DEST/stand/loader/ldrinfo" <<EOF
version=$LDR_VERSION
line=any
boot1-sha256=$LDR_BOOT1_SHA
boot2-size=$LDR_BOOT2_SIZE
boot2-sha256=$LDR_BOOT2_SHA
EOF
sed 's/^/  ldrinfo: /' "$DEST/stand/loader/ldrinfo"

{
	echo "$LDR_CATALOG_NAME $LDR_PKG_VERSION -- boot1 and boot2 of the amix boot loader,"
	echo "built from amix-dlm $LDR_DLM_COMMIT."
	echo
	cat "$AMIX_DLM_TREE/LICENSE"
} > "$WORK/copyright"

find "$DEST" -exec touch -h -d "@$LDR_SOURCE_EPOCH" {} +
chmod 0444 "$DEST/stand/loader/boot1" "$DEST/stand/loader/boot2" "$DEST/stand/loader/ldrinfo"

echo "--- package ---"
kspace_epoch "$LDR_SOURCE_EPOCH"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_kpkgroll "$WORK" "$DEST" "$LDR_PKG" "$LDR_PKG_VERSION" "$OUT"
kspace_done "$OUT"
