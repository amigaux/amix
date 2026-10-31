#!/bin/sh
#
# build.sh -- package the module kernel of the 040/060 line (pin.sh).
#
#     sh kernel/port/pkg/kernel-k46-m/build.sh     (or kernel/port/pkg/build.sh)
#
# Outputs ($KSPACE, common.sh):
#     $KSPACE/kernel-k46-m/dest/stand/k46/{unix,kabi}
#     $KSPACE/kernel-k46-m/dest/etc/conf/{mod.d,modreg.d}/ufs
#     $KSPACE/pkg/kern46m-<version>.pkg
#
# unix (ET_REL) and kabi are copied VERBATIM.  Everything below checks them:
# the pins, the sidecar's keys (C2-3 v6 sec 2, C3-3), the image's own
# buildid equal to the sidecar's build=, the version from the build id, abi= equal to the reference of the pinned kabi (abi/k46/abi-<kabi>.txt),
# sdcards= passed through (C2-3 v7), the loader's relocator binding the kernel,
# and ksymgate on the kernel symbol block.
# Since -91 (C2-3 v8 sec 1, S5-12): the cut carries no built-in ufs or s5 and
# its sidecar no rootfs=; the package ships the cut's ufs core-tier module
# verbatim at /etc/conf/mod.d/ufs (build/pkg/common/kfsmod.sh: pins, modcheck,
# .moddata build= the sidecar's, and a rebuild from the carve sources
# byte-equal to it), with a comment-only modreg.d file.  No s5 on k46 (S5-37).
# Since -50 (S5-13): the cut's module core is the pinned commit and contains
# K46M_CORE_STRIP (the core that skips the stamp's leading blank), and the
# core's own rule holds over the shipped bytes (build/pkg/common/kbuildid.py):
# the image's buildid without its leading blanks == the sidecar's build= ==
# the ufs module's .moddata build=, byte for byte.  amix-packages'
# tools/kbuildid-selftest.sh proves the gate refuses -91's module against
# this kernel.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../common.sh"
. "$HERE/pin.sh"

BUILD="$KSPACE/$K46M_CATALOG_NAME"
DEST="$BUILD/dest"
WORK="$BUILD/work"
LIC="$BUILD.inputs"
OUT="$KSPACE/pkg/$K46M_PKG-$K46M_VERSION.pkg"
SRC="$K46M_SRC/$K46M_OUT"

echo "=== $K46M_CATALOG_NAME $K46M_VERSION (PKG=$K46M_PKG, build $K46M_BUILDID) ==="

# the cut's output is an input from outside the recipe: absent, the roll is
# not failed but missing (exit 3, build.sh)
[ -f "$K46M_SRC/$K46M_SUMS" ] || {
	echo "[MISSING] kspace: kernel/port: $K46M_PKG: no cut $K46M_BUILDID at $K46M_SRC (P-38 S2.3: make kernel-k46)" >&2
	exit 3; }
case "$K46M_PORT_COMMIT" in "$K46M_KIT_PORT"*) ;; *)
	echo "[FAIL] pin.sh: K46M_PORT_COMMIT is not K46M_KIT_PORT in full" >&2; exit 1 ;; esac

echo "--- the licences from amix $K46M_AMIX_COMMIT and the pinned forks ---"
rm -rf "$LIC"; mkdir -p "$LIC"
echo "$K46M_LICENCES" | while read n h w; do
	[ -n "$n" ] || continue
	f="$LIC/$(echo "$n" | tr / _)"
	case "$w" in
	amix:*) kspace_amix_file "$K46M_AMIX_COMMIT" "${w#amix:}" "$f" ;;
	paula:*) kspace_fork_file paula "$K46M_PAULA_COMMIT" "${w#paula:}" "$f" ;;
	*) echo "[FAIL] pin.sh: $n comes from '$w'" >&2; exit 1 ;;
	esac
	amix_verify "$f" "$h"
done

echo "--- verify the inputs against the pins ---"
amix_verify "$SRC/unix" "$K46M_UNIX_SHA"
amix_verify "$SRC/kabi" "$K46M_KABI_SHA"
amix_verify "$K46M_SRC/$K46M_FSEXP" "$K46M_FSEXP_SHA"
echo "$K46M_FSMODS" | awk 'NF { print $2, "'"$K46M_OUT"'/" $4 }' | {
	cat; echo "$K46M_UNIX_SHA $K46M_OUT/unix"; echo "$K46M_KABI_SHA $K46M_OUT/kabi"; echo "$K46M_FSEXP_SHA $K46M_FSEXP"; } |
while read h n; do
	grep -qx "$h  $n" "$K46M_SRC/$K46M_SUMS" || {
		echo "[FAIL] the cut's $K46M_SUMS does not name $n $h" >&2; exit 1; }
done
echo "$K46M_NOTICES" | while read n h; do [ -n "$n" ] && amix_verify "$K46M_SRC/port/$n" "$h"; done
amix_dlm_build "$K46M_DLM_COMMIT" axrel
X="$AMIX_DLM_TREE"
echo "$K46M_DLM_LICENCES" | while read n h; do [ -n "$n" ] && amix_verify "$X/$n" "$h"; done

echo "--- the sidecar describes the shipped ET_REL (checked, not rewritten) ---"
for kv in "kabi=$K46M_KABI" "family=generic" "line=k46" "pin=gcc-2.7.2.3-8949028" \
	"build=$K46M_BUILDID" "size=$K46M_UNIX_SIZE" "sha256=$K46M_UNIX_SHA" "loader-min=2"; do
	grep -qx "$kv" "$SRC/kabi" || { echo "[FAIL] $SRC/kabi lacks '$kv'" >&2; exit 1; }
done
for k in ident arena ksym abi; do
	[ "$(grep -c "^$k=" "$SRC/kabi")" = 1 ] || { echo "[FAIL] $SRC/kabi: not exactly one $k=" >&2; exit 1; }
done
# the arena offset is a multiple of 16 (C3-3 v5, kabi 1.2; kbootset gate 4 refuses it otherwise)
_arena=$(sed -n 's/^arena=\(0x[0-9a-fA-F]*\) .*/\1/p' "$SRC/kabi")
[ -n "$_arena" ] && [ $(( _arena % 16 )) = 0 ] || {
	echo "[FAIL] $SRC/kabi: arena= '$_arena' is not a multiple of 16 (C3-3 v5)" >&2; exit 1; }
# sdcards= (C2-3 v7): passed through verbatim; at most one, 2 or 4
case "$(grep -c '^sdcards=' "$SRC/kabi")$(sed -n 's/^sdcards=//p' "$SRC/kabi")" in
	0|12|14) ;;
	*) echo "[FAIL] $SRC/kabi: sdcards= must be absent or one line of 2 or 4" >&2; exit 1 ;;
esac
# a cut without built-in ufs and s5 (C3-3 sec 3 v6): no rootfs=, rth1=2 (C2-3 v9)
grep -qx 'rth1=2' "$SRC/kabi" || { echo "[FAIL] $SRC/kabi: no rth1=2 (C2-3 v9)" >&2; exit 1; }
for k in bss sym rootfs; do
	! grep -q "^$k=" "$SRC/kabi" || { echo "[FAIL] $SRC/kabi: $k= on an ET_REL kernel" >&2; exit 1; }
done
[ "$(stat -c%s "$SRC/unix")" = "$K46M_UNIX_SIZE" ] || { echo "[FAIL] unix size" >&2; exit 1; }
# the image's own id (.data buildid; the leading blank is inituname's
# separator) is the sidecar's build= (port fcaffcd, STAMP_BUILDID_CPU=60)
_bid=$(python3 -I -c '
import struct, sys
d = open(sys.argv[1], "rb").read()
shoff, = struct.unpack(">I", d[32:36]); es, n, si = struct.unpack(">HHH", d[46:52])
sh = [struct.unpack(">10I", d[shoff + i * es: shoff + i * es + 40]) for i in range(n)]
st = [x for x in sh if x[1] == 2][0]; ss = sh[st[6]]
for j in range(st[5] // 16):
    no, val, sz, info, oth, shn = struct.unpack(">IIIBBH", d[st[4] + j * 16: st[4] + j * 16 + 16])
    if d[ss[4] + no: d.index(b"\0", ss[4] + no)] == b"buildid":
        o = sh[shn][4] + val
        print("[" + d[o: d.index(b"\0", o)].decode() + "]")
' "$SRC/unix")
[ "$_bid" = "[ $K46M_BUILDID]" ] || {
	echo "[FAIL] the image's buildid $_bid is not '[ $K46M_BUILDID]' (STAMP_BUILDID_CPU=60)" >&2; exit 1; }
echo "  the image's buildid $_bid = a blank + build=$K46M_BUILDID"
# the core this cut links skips that blank (S5-13: the core of 76f83d8 took
# it verbatim and refused the cut's own ufs, EBADVER), and the core's rule
# holds over the shipped bytes (build/pkg/common/kfsmod.sh)
amix_kcore_strips "$K46M_SRC/port/build/dlm-rev/.rev" "$K46M_DLM_COMMIT" "$K46M_CORE_STRIP" || exit 1
amix_kbuildid3 "$SRC/unix" "$SRC/kabi" "$BUILD.kbuildid" $(echo "$K46M_FSMODS" | awk -v d="$SRC" 'NF { print d "/" $4 }') || exit 1
[ "$(od -An -tx1 -j16 -N2 "$SRC/unix" | tr -d ' ')" = 0001 ] || {
	echo "[FAIL] $SRC/unix is not ET_REL" >&2; exit 1; }
# the version is <kabi>.<yymmdd>-<nn> of the build id (C2-3 sec 1.1)
_v=$(echo "$K46M_BUILDID" | awk -F- -v k="$K46M_KABI" '{print k "." $2 "-" $3}')
[ "$_v" = "$K46M_VERSION" ] || { echo "[FAIL] version $K46M_VERSION, the build id gives $_v" >&2; exit 1; }
# abi= is the reference fingerprint of the pinned kabi (C3-3 v4)
_abi=$(sha256sum < "$X/abi/k46/abi-$K46M_KABI.txt" | cut -c1-64)
grep -qx "abi=$_abi" "$SRC/kabi" || { echo "[FAIL] abi= is not abi/k46/abi-$K46M_KABI.txt ($_abi)" >&2; exit 1; }
echo "  kabi=$K46M_KABI family=generic line=k46 build=$K46M_BUILDID loader-min=2; ident/arena/ksym; abi=${_abi%${_abi#????????}}... = the reference; arena $_arena; sdcards=$(sed -n 's/^sdcards=//p' "$SRC/kabi"); rth1=2, no rootfs="

echo "--- the loader's relocator and the symbol block ---"
"$X/build/axrel" "$SRC/unix" 0x01000000 /dev/null pcrel 2>&1 | sed 's/^/  /'
python3 -I "$X/tools/ksymgate.py" "$X/build/axrel" "$SRC/unix" "$X/abi/k46/ddi.list" "$X/abi/k46/core.list" \
	> "$BUILD.ksymgate" 2>&1 || { cat "$BUILD.ksymgate" >&2; echo "[FAIL] ksymgate" >&2; exit 1; }
echo "  ksymgate: $(grep -c '^PASS' "$BUILD.ksymgate") checks pass, $(tail -1 "$BUILD.ksymgate")"

rm -rf "$BUILD"; mkdir -p "$DEST/stand/k46" "$WORK"

echo "--- the filesystem module: pin, modcheck, .moddata, the rebuild (kit of amix-dlm $K46M_KIT_COMMIT) ---"
kspace_fork_have port "$K46M_PORT_COMMIT"
amix_dlm_kit "$K46M_KIT_COMMIT" "" "$K46M_KIT_PORT" >/dev/null
KIT="$AMIX_DLM_TREE/build/kit/k46"
# the carve's Makefile names the exp object by the absolute path the cut was
# made at; it must be the cut's own $K46M_FSEXP (pinned above), and the
# rebuild links that file where the cut is now (EXTRA=)
e=$(sed -n 's/^EXTRA = //p' "$K46M_SRC/$K46M_CARVE/Makefile")
case "$e" in */"$K46M_FSEXP") ;; *)
	echo "[FAIL] $K46M_CARVE/Makefile links '$e', not the cut's $K46M_FSEXP" >&2; exit 1 ;; esac
echo "$K46M_FSMODS" | while read fs h sz f; do
	[ -n "$fs" ] || continue
	amix_kfsmod_check k46 "$fs" "$SRC/$f" "$h" "$sz" "$K46M_BUILDID" "$K46M_KABI" "$KIT" "$WORK/chk-$fs" "$K46M_FSKABI"
	amix_kfsmod_rebuild k46 "$fs" "$K46M_SRC/$K46M_CARVE" "$SRC/$f" "$KIT" "$WORK/carve-$fs" "$K46M_SRC/$K46M_FSEXP"
done
mkdir -p "$DEST/etc/conf/mod.d" "$DEST/etc/conf/modreg.d"
echo "$K46M_FSMODS" | while read fs h sz f; do
	[ -n "$fs" ] || continue
	cp "$SRC/$f" "$DEST/etc/conf/mod.d/$fs"
	cp "$HERE/modreg.$fs" "$DEST/etc/conf/modreg.d/$fs"
done

cp "$SRC/unix" "$DEST/stand/k46/unix"
cp "$SRC/kabi" "$DEST/stand/k46/kabi"

{
	echo "$K46M_CATALOG_NAME $K46M_VERSION -- the module kernel of Amiga UNIX (Amix), 68040/68060"
	echo "line, build $K46M_BUILDID."
	echo
	echo "Amiga UNIX is Commodore's port of AT&T UNIX System V Release 4; portions"
	echo "are copyright AT&T, UNIX System Laboratories and their successors, and"
	echo "Commodore-Amiga, Inc.  On 2026-09-23 Amiga Corporation approved the"
	echo "distribution of the Commodore Amiga binaries this project builds on."
	echo "This project and its developers are not affiliated with, endorsed by, or"
	echo "sponsored by Amiga Corporation.  Amiga is a registered trademark of Amiga"
	echo "Corporation."
	echo
	echo "The 68040/68060 port (amix-040-060-port) is MIT, below; the Motorola"
	echo "FPSP/ISP and NetBSD FPE code linked into this kernel carry the notices"
	echo "after it.  Linked in from another repository, under the licence after"
	echo "those: the W-D7 support probe and the sddevsize constant written in after"
	echo "the link (amix-kerntools); the module core linked in is amix-dlm's (MIT)"
	echo "on the adopted DLM core (MIT, kdedon), last.  The Z3660 SCSI driver is"
	echo "not linked in: it comes as a root module package.  The stock audio"
	echo "driver (amiga/driver/audio.c) is compiled with amix-paula's three"
	echo "patches (MIT, below): the /dev/paula exclusion, a safe close and a"
	echo "bounded wait in the /dev/audio open."
	echo
	echo "This cut has no built-in ufs or s5 filesystem.  The package carries ufs"
	echo "as a core-tier module built with the cut (/etc/conf/mod.d/ufs): the"
	echo "stock Amiga UNIX ufs object (under the note above) as the 040/060 port"
	echo "patches it for the 4 KiB page and for zeroing a shrunk file's tail (MIT,"
	echo "below), linked with a small wrapper"
	echo "and the module header by amix-dlm's carve.py and ABI kit (amix-dlm, MIT,"
	echo "below).  s5 stays out on this line (no k46 s5 module)."
	echo "$K46M_NOTICES" | while read n h; do
		[ -n "$n" ] || continue
		echo; echo "======== $n ========"; echo
		cat "$K46M_SRC/port/$n"
	done
	echo "$K46M_LICENCES" | while read n h w; do
		[ -n "$n" ] || continue
		echo; echo "======== $n ========"; echo
		cat "$LIC/$(echo "$n" | tr / _)"
	done
	echo "$K46M_DLM_LICENCES" | while read n h; do
		[ -n "$n" ] || continue
		echo; echo "======== amix-dlm $n ========"; echo
		cat "$X/$n"
	done
} > "$WORK/copyright"

find "$DEST" -exec touch -h -d "@$K46M_SOURCE_EPOCH" {} +
chmod 0644 "$DEST/stand/k46/unix"; chmod 0444 "$DEST/stand/k46/kabi"
chmod 0644 "$DEST"/etc/conf/mod.d/* "$DEST"/etc/conf/modreg.d/*
cmp -s "$DEST/stand/k46/unix" "$SRC/unix" && cmp -s "$DEST/stand/k46/kabi" "$SRC/kabi" \
	&& cmp -s "$DEST/etc/conf/mod.d/ufs" "$SRC/ufs.mod" && [ "$(ls "$DEST/etc/conf/mod.d")" = ufs ] || {
	echo "[FAIL] staged files are not verbatim copies" >&2; exit 1; }
# the modreg.d file is comments only (C3-5 sec 1.2: the module's own defaults)
! grep -vq '^#' "$DEST"/etc/conf/modreg.d/* || { echo "[FAIL] a modreg.d file has a non-comment line" >&2; exit 1; }

echo "--- package ---"
kspace_epoch "$K46M_SOURCE_EPOCH"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_kpkgroll "$WORK" "$DEST" "$K46M_PKG" "$K46M_VERSION" "$OUT"
kspace_done "$OUT"
