#!/bin/sh
#
# build.sh -- the ABI kit packages dlmkit30 and dlmkit46 (amix-dlm S3-22):
# USERLAND packages, rolled by the ordinary amix_pkgroll with every
# userland gate, one per kernel line.
#
#     sh kernel/dlm/pkg/dlmkit/build.sh [k30|k46]...      (default: both)
#
# The kit is amix-dlm's own `make kit` at the pinned commit (dlm-src.sh
# amix_dlm_kit), checked against the manifest digest in pin.sh, and
# installed whole under /usr/dlm/kit/<line>/, under the kit's own names: since
# amix-dlm f97b570 every kit name fits the s5 14-byte dirent (mkkit refuses a
# longer one), so -1's five renames and its S5NAMES file are gone; the roll's
# s5 gate still checks every path.
#
# Outputs ($KSPACE, common.sh):
#     $KSPACE/dlmkit/<line>/dest/usr/dlm/kit/<line>/...
#     $KSPACE/dlmkit/<line>/contents  (mode, size, md5, path per file)
#     $KSPACE/pkg/dlmkit<nn>-<version>.pkg

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../common.sh"
. "$HERE/pin.sh"

# The 68060 tree gate (amix_pkgroll, before pkgmk) scans every ELF in the
# payload and fails on one it cannot read as m68k -- as it should, a host
# program in a box package is a defect everywhere else.  The kit's
# tools/modfix IS a host program, checked below to be exactly that file and
# a Linux x86-64 ELF; so for this recipe the tree gate runs on a copy of the
# payload without it, and the datastream gate after the roll (scan060.py on
# the whole .pkg) still reads everything and inspects sunfont.o.
amix_gate_060_tree() {
	_g6t="$BUILD/gate060"
	rm -rf "$_g6t"; mkdir -p "$_g6t"; cp -R "$1/." "$_g6t/"
	rm -f "$_g6t$PFX/tools/modfix"
	echo "  060 gate: the payload without the host program $PFX/tools/modfix:"
	if _amix_gate_060_tree_impl "$_g6t"; then _g6r=0; else _g6r=1; fi
	rm -rf "$_g6t"
	return $_g6r
}

# amix_kit_manifest <kitdir> -- `<x|-> <sha256> <path>` per file, C order
amix_kit_manifest() {
	( cd "$1" && LC_ALL=C find . -type f | LC_ALL=C sort | while read -r _f; do
		if [ -x "$_f" ]; then _x=x; else _x=-; fi
		echo "$_x $(sha256sum < "$_f" | cut -c1-64) $_f"
	done )
}

LINES=${*:-k30 k46}
echo "=== dlmkit ($LINES) from amix-dlm $DK_DLM_COMMIT ==="
echo "--- make kit, amix-dlm $DK_DLM_COMMIT ---"
amix_dlm_kit "$DK_DLM_COMMIT" "$DK_MONSW_COMMIT" "$DK_K46_PORT_COMMIT"

for LINE in $LINES; do
	case "$LINE" in
	k30) PKG=dlmkit30; PIN_M=$DK_K30_MANIFEST ;;
	k46) PKG=dlmkit46; PIN_M=$DK_K46_MANIFEST ;;
	*) echo "[FAIL] no kernel line '$LINE' (k30, k46)" >&2; exit 1 ;;
	esac
	KIT="$AMIX_DLM_TREE/build/kit/$LINE"
	KABI=$(sed -n 's/^KABI=//p' "$KIT/kit.conf")
	VERSION="$KABI.$DK_DATE-$DK_REV.$DK_DLM_COMMIT"
	BUILD="$KSPACE/dlmkit/$LINE"
	DEST="$BUILD/dest"
	WORK="$BUILD/work"
	PFX=/usr/dlm/kit/$LINE
	OUT="$KSPACE/pkg/$PKG-$VERSION.pkg"
	echo "=== $PKG $VERSION ==="

	grep -qx "LINE=$LINE" "$KIT/kit.conf" && grep -qx "KIT_REV=$DK_DLM_COMMIT" "$KIT/kit.conf" || {
		echo "[FAIL] $KIT/kit.conf is not LINE=$LINE KIT_REV=$DK_DLM_COMMIT" >&2; exit 1; }
	case "$LINE.$KABI" in k30.k30.*|k46.k46.*) ;; *)
		echo "[FAIL] $KIT/kit.conf: KABI=$KABI is not a $LINE tag" >&2; exit 1 ;; esac
	# kit.conf is read by sh (mk/module.mk's users, scripts): it must source
	# cleanly, and since 6492c3b it names where sys/monsw.h came from
	_kc=$(sh -c '. "$1" && echo "$MONSW_REV"' sh "$KIT/kit.conf" 2>&1) &&
	[ "$_kc" = "$DK_MONSW_REPO@$DK_MONSW_COMMIT" ] || {
		echo "[FAIL] $KIT/kit.conf does not source cleanly in sh with MONSW_REV=$DK_MONSW_REPO@$DK_MONSW_COMMIT: $_kc" >&2
		exit 1; }
	echo "  kit.conf sources in sh; MONSW_REV=$_kc"

	mkdir -p "$BUILD"
	amix_kit_manifest "$KIT" > "$BUILD/manifest"
	M=$(sha256sum < "$BUILD/manifest" | cut -c1-64)
	echo "  kit      $(wc -l < "$BUILD/manifest") files, manifest sha256 $M"
	if [ "$PIN_M" = pending ]; then
		echo "[FAIL] pin.sh: the $LINE kit manifest digest is pending (this build: $M)" >&2; exit 1
	fi
	[ "$M" = "$PIN_M" ] || {
		echo "[FAIL] the $LINE kit is not the pinned one: manifest $M, pin $PIN_M" >&2
		echo "       ($BUILD/manifest)" >&2; exit 1; }
	echo "      manifest sha256 pinned, verified"

	rm -rf "$DEST" "$WORK"; mkdir -p "$DEST$PFX" "$WORK"
	cp -R "$KIT/." "$DEST$PFX/"
	find "$DEST" -type d -exec chmod 0755 {} +
	find "$DEST" -type f -perm -u+x -exec chmod 0755 {} +
	find "$DEST" -type f ! -perm -u+x -exec chmod 0644 {} +
	if [ -n "$(find "$DEST" ! -type d ! -type f)" ] || \
	   [ -n "$(find "$DEST" -name '*[ =$]*')" ]; then
		echo "[FAIL] the staged kit has a link/special file or a path with space, = or \$" >&2
		exit 1
	fi
	find "$DEST" -exec touch -h -d "@$DK_SOURCE_EPOCH" {} +

	echo "--- gates ---"
	# two ELF files, both expected: the stock console font as a linkable m68k
	# object, and tools/modfix, a host (Linux x86-64) program of the kit
	_elfs=$(amix_gate_elfs "$DEST" | LC_ALL=C sort | tr '\n' ' ')
	[ "$_elfs" = "$DEST$PFX/stock/usr/sys/amiga/console/sunfont.o $DEST$PFX/tools/modfix " ] || {
		echo "[FAIL] the kit's ELF files are not sunfont.o and tools/modfix: $_elfs" >&2; exit 1; }
	amix_gate_elf "$DEST$PFX/stock/usr/sys/amiga/console/sunfont.o"
	case "$(LC_ALL=C file -b "$DEST$PFX/tools/modfix")" in
	*"ELF 64-bit LSB"*x86-64*) echo "  host     tools/modfix is the kit's Linux x86-64 program (not for the box)" ;;
	*) echo "[FAIL] tools/modfix: $(file -b "$DEST$PFX/tools/modfix")" >&2; exit 1 ;;
	esac

	# the kit as installed builds and checks its sample
	# module through the make fragment alone, with the pinned compiler; the
	# module says the highest minor it imports, never below KABI_MIN (since
	# kabi 1.3 the sample says KABI_MIN: it imports no minor-3 name)
	KABI_MIN=$(sed -n 's/^KABI_MIN=//p' "$KIT/kit.conf")
	[ -n "$KABI_MIN" ] || KABI_MIN=$KABI
	rm -rf "$BUILD/sample"; mkdir -p "$BUILD/sample"
	cp "$DEST$PFX/sample/hello/hello.c" "$DEST$PFX/sample/hello/Master" \
		"$DEST$PFX/sample/hello/Makefile" "$BUILD/sample/"
	( . "$AMIX_CROSS_ENV" >/dev/null 2>&1
	  make -C "$BUILD/sample" KIT="$DEST$PFX" ) > "$BUILD/sample.log" 2>&1 &&
	grep -q "^modcheck: hello: ok ($KABI_MIN, " "$BUILD/sample.log" || {
		echo "[FAIL] the staged $LINE kit does not build its sample:" >&2
		tail -10 "$BUILD/sample.log" >&2; exit 1; }
	echo "  sample   $(grep '^modcheck: hello' "$BUILD/sample.log") with the kit as installed"

	{
		echo "$PKG $VERSION -- the amix-dlm ABI kit for $LINE, built by amix-dlm's"
		echo "\`make kit\` at $DK_DLM_COMMIT, installed under $PFX/."
		echo
		cat "$KIT/NOTICE"
		echo
		echo "---- LICENSE ----"
		cat "$KIT/LICENSE"
		echo
		echo "---- tools/LICENSE.core ----"
		cat "$KIT/tools/LICENSE.core"
	} > "$WORK/copyright"

	cp "$HERE/pkginfo.$LINE" "$WORK/pkginfo"
	cp "$HERE/prototype" "$WORK/prototype"
	(
		cd "$DEST"
		LC_ALL=C find ".$PFX" | LC_ALL=C sort | while read -r _p; do
			_p=${_p#.}
			if [ -d "$DEST$_p" ]; then
				echo "d none $_p 0755 root sys"
			elif [ -x "$DEST$_p" ]; then
				echo "f none $_p 0755 root bin"
			else
				echo "f none $_p 0644 root bin"
			fi
		done
	) >> "$WORK/prototype"
	( cd "$DEST" && LC_ALL=C find ".$PFX" -type f | LC_ALL=C sort | while read -r _p; do
		echo "$(stat -c '%a %s' "$_p") $(md5sum < "$_p" | cut -c1-32) ${_p#.}"
	done ) > "$BUILD/contents"
	echo "  staged   $(wc -l < "$BUILD/contents") files, $(awk '{s += $2} END {print s}' "$BUILD/contents") bytes under $PFX ($BUILD/contents)"

	echo "--- package ---"
	kspace_epoch "$DK_SOURCE_EPOCH"
	amix_pkgroll "$WORK" "$DEST" "$PKG" "$VERSION" "$OUT"
	kspace_done "$OUT"
done
