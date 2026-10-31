#!/bin/sh
#
# build.sh -- package the module kernel of the 030 line (pin.sh).
#
#     sh kernel/k30/pkg/kernel-k30-m/build.sh     (or kernel/k30/pkg/build.sh)
#
# Outputs ($KSPACE, common.sh):
#     $KSPACE/kernel-k30-m/dest/stand/k30/{unix,kabi,unix.sym}
#     $KSPACE/kernel-k30-m/dest/etc/conf/{mod.d,modreg.d}/{ufs,s5}
#     $KSPACE/pkg/kern30m-<version>.pkg
#
# The brel, its sidecar and unix.sym are copied VERBATIM: the kernel build
# shipped the brel and wrote both for it (C2-3 v4, v6).  Everything below
# checks them: the pins; the sidecar's keys; sym= naming unix.sym by size
# and SHA-256; unix.sym's form and its end = image + bss=; elf2brel
# reproducing the brel from the ET_REL; bss= measured twice; abi= equal to
# the reference of the pinned kabi (abi/k30/abi-<kabi>.txt); arena= a
# multiple of 16 (C3-3 v5); sdcards= passed through (C2-3 v7); ksymgate on the ET_REL's symbol block.
# Since -20 (C2-3 v8 sec 1, S5-12): the cut carries no built-in ufs or s5 and
# its sidecar no rootfs=; the package ships the cut's ufs and s5 core-tier
# modules verbatim at /etc/conf/mod.d (build/pkg/common/kfsmod.sh: pins,
# modcheck, .moddata build= the sidecar's, and a rebuild from the carve
# sources byte-equal to them), each with a comment-only modreg.d file.

set -e

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../common.sh"
. "$HERE/pin.sh"

BUILD="$KSPACE/$K30M_CATALOG_NAME"
DEST="$BUILD/dest"
WORK="$BUILD/work"
LIC="$BUILD.inputs"
OUT="$KSPACE/pkg/$K30M_PKG-$K30M_VERSION.pkg"
SRC="$K30M_SRC/$K30M_SYSDIR"

echo "=== $K30M_CATALOG_NAME $K30M_VERSION (PKG=$K30M_PKG, build $K30M_BUILDID) ==="

# the cut's output is an input from outside the recipe: absent, the roll is
# not failed but missing (exit 3, build.sh)
[ -f "$K30M_SRC/$K30M_SUMS" ] || {
	echo "[MISSING] kspace: kernel/k30: $K30M_PKG: no cut $K30M_BUILDID at $K30M_SRC (P-38 S2.2, the k30 station: make kernel-k30)" >&2
	exit 3; }
case "$K30M_PORT_COMMIT" in "$K30M_KIT_PORT"*) ;; *)
	echo "[FAIL] pin.sh: K30M_PORT_COMMIT is not K30M_KIT_PORT in full" >&2; exit 1 ;; esac

echo "--- the inputs from amix $K30M_AMIX_COMMIT and the pinned forks ---"
rm -rf "$LIC"; mkdir -p "$LIC"
K30M_ELF2BREL_AT="$LIC/elf2brel.py"
kspace_amix_file "$K30M_AMIX_COMMIT" "$K30M_ELF2BREL" "$K30M_ELF2BREL_AT"
amix_verify "$K30M_ELF2BREL_AT" "$K30M_ELF2BREL_SHA"
echo "$K30M_LICENCES" | while read n h w; do
	[ -n "$n" ] || continue
	f="$LIC/$(echo "$n" | tr / _)"
	case "$w" in
	amix:*) kspace_amix_file "$K30M_AMIX_COMMIT" "${w#amix:}" "$f" ;;
	port:*) kspace_fork_file port "$K30M_PORT_COMMIT" "${w#port:}" "$f" ;;
	paula:*) kspace_fork_file paula "$K30M_PAULA_COMMIT" "${w#paula:}" "$f" ;;
	*) echo "[FAIL] pin.sh: $n comes from '$w'" >&2; exit 1 ;;
	esac
	amix_verify "$f" "$h"
done

echo "--- verify the inputs against the pins ---"
amix_verify "$SRC/unix.brel" "$K30M_BREL_SHA"
amix_verify "$SRC/kabi" "$K30M_KABI_SHA"
amix_verify "$SRC/unix.sym" "$K30M_SYM_SHA"
amix_verify "$SRC/unix" "$K30M_ETREL_SHA"
echo "$K30M_FSMODS" | awk 'NF { print $2, "mod.d/" $1 }' | {
	cat; echo "$K30M_BREL_SHA unix.brel"; echo "$K30M_SYM_SHA unix.sym"; echo "$K30M_KABI_SHA kabi"
	echo "$K30M_ETREL_SHA unix"; echo "$K30M_AUDIO_SHA amiga/driver/audio.c"; } |
while read h n; do
	grep -qx "$h  $n" "$K30M_SRC/$K30M_SUMS" || {
		echo "[FAIL] the cut's $K30M_SUMS does not name $n $h" >&2; exit 1; }
done
[ "$(grep -c . "$K30M_SRC/$K30M_SUMS")" = 7 ] || {
	echo "[FAIL] $K30M_SUMS: not exactly the ET_REL, the brel, unix.sym, kabi, ufs, s5 and audio.c" >&2; exit 1; }
amix_verify "$SRC/amiga/driver/audio.c" "$K30M_AUDIO_SHA"
amix_dlm_build "$K30M_DLM_COMMIT" axrel
X="$AMIX_DLM_TREE"
echo "$K30M_DLM_LICENCES" | while read n h; do [ -n "$n" ] && amix_verify "$X/$n" "$h"; done

echo "--- the sidecar describes the shipped brel and unix.sym (checked, not rewritten) ---"
for kv in "kabi=$K30M_KABI" "family=generic" "line=k30" "pin=gcc-2.7.2.3-8949028" \
	"build=$K30M_BUILDID" "size=$K30M_BREL_SIZE" "sha256=$K30M_BREL_SHA" "bss=$K30M_BSS" \
	"loader-min=2" "sym=unix.sym $K30M_SYM_SIZE $K30M_SYM_SHA"; do
	grep -qx "$kv" "$SRC/kabi" || { echo "[FAIL] $SRC/kabi lacks '$kv'" >&2; exit 1; }
done
for k in ident arena ksym abi; do
	[ "$(grep -c "^$k=" "$SRC/kabi")" = 1 ] || { echo "[FAIL] $SRC/kabi: not exactly one $k=" >&2; exit 1; }
done
# a cut without built-in ufs and s5 (C3-3 sec 3 v6): no rootfs=, rth1=2 (C2-3 v9)
! grep -q '^rootfs=' "$SRC/kabi" || { echo "[FAIL] $SRC/kabi: rootfs= on a cut whose ufs/s5 are modules" >&2; exit 1; }
grep -qx 'rth1=2' "$SRC/kabi" || { echo "[FAIL] $SRC/kabi: no rth1=2 (C2-3 v9)" >&2; exit 1; }
# the arena offset is a multiple of 16 (C3-3 v5, kabi 1.2; kbootset gate 4 refuses it otherwise)
_arena=$(sed -n 's/^arena=\(0x[0-9a-fA-F]*\) .*/\1/p' "$SRC/kabi")
[ -n "$_arena" ] && [ $(( _arena % 16 )) = 0 ] || {
	echo "[FAIL] $SRC/kabi: arena= '$_arena' is not a multiple of 16 (C3-3 v5)" >&2; exit 1; }
# sdcards= (C2-3 v7): passed through verbatim; at most one, 2 or 4
case "$(grep -c '^sdcards=' "$SRC/kabi")$(sed -n 's/^sdcards=//p' "$SRC/kabi")" in
	0|12|14) ;;
	*) echo "[FAIL] $SRC/kabi: sdcards= must be absent or one line of 2 or 4" >&2; exit 1 ;;
esac
[ "$(stat -c%s "$SRC/unix.brel")" = "$K30M_BREL_SIZE" ] || { echo "[FAIL] brel size" >&2; exit 1; }
[ "$(od -An -tx1 -j16 -N2 "$SRC/unix.brel" | tr -d ' ')" = ff00 ] || {
	echo "[FAIL] $SRC/unix.brel is not a brel (e_type 0xff00)" >&2; exit 1; }
# the sym= gate: the file it names, by size and SHA-256, is the one shipped
set -- $(sed -n 's/^sym=//p' "$SRC/kabi")
[ "$1" = unix.sym ] && [ "$2" = "$(stat -c%s "$SRC/unix.sym")" ] && [ "$3" = "$(sha256sum < "$SRC/unix.sym" | cut -c1-64)" ] || {
	echo "[FAIL] sym= '$*' does not name the shipped unix.sym" >&2; exit 1; }
echo "  sym=unix.sym $2 ${3%${3#????????}}...: size and SHA-256 of the shipped unix.sym"
_v=$(echo "$K30M_BUILDID" | awk -F- -v k="$K30M_KABI" '{print k "." $2 "-" $3}')
[ "$_v" = "$K30M_VERSION" ] || { echo "[FAIL] version $K30M_VERSION, the build id gives $_v" >&2; exit 1; }
_abi=$(sha256sum < "$X/abi/k30/abi-$K30M_KABI.txt" | cut -c1-64)
grep -qx "abi=$_abi" "$SRC/kabi" || { echo "[FAIL] abi= is not abi/k30/abi-$K30M_KABI.txt ($_abi)" >&2; exit 1; }
echo "  kabi=$K30M_KABI family=generic line=k30 build=$K30M_BUILDID loader-min=2 bss=$K30M_BSS; ident/arena/ksym; abi=${_abi%${_abi#????????}}... = the reference; arena $_arena; sdcards=$(sed -n 's/^sdcards=//p' "$SRC/kabi"); rth1=2, no rootfs="

rm -rf "$BUILD"; mkdir -p "$DEST/stand/k30" "$WORK"

echo "--- the brel, its bss and unix.sym against the ET_REL ---"
python3 -I "$K30M_ELF2BREL_AT" -v "$SRC/unix" "$WORK/reconv.brel" 2> "$WORK/elf2brel.log"
cmp -s "$WORK/reconv.brel" "$SRC/unix.brel" || {
	echo "[FAIL] elf2brel does not reproduce the shipped brel from its ET_REL" >&2; exit 1; }
rm -f "$WORK/reconv.brel"
K_BSS_E2B=$(sed -n 's/.*bss-tail=\([0-9]*\).*/\1/p' "$WORK/elf2brel.log")
MEASURED=$(amix_kbrel_bss "$SRC/unix" "$SRC/unix.brel" "$X/build/axrel")
[ "$MEASURED" = "$K30M_BSS" ] || { echo "[FAIL] bss measured $MEASURED, the sidecar says $K30M_BSS" >&2; exit 1; }
echo "  elf2brel reproduces the brel; bss-tail and the relocator both give bss=$K30M_BSS"
# unix.sym (C2-3 v6 sec 2.1): ELF32 MSB m68k ET_EXEC with a .symtab; edata
# is the brel's image size and end the image plus bss=
_img=$("$X/build/axrel" "$SRC/unix.brel" 0 /dev/null 2>&1 | sed -n 's/.*end 0x\([0-9a-f]*\)$/\1/p')
[ "$(od -An -tx1 -N6 "$SRC/unix.sym" | tr -d ' ')" = 7f454c460102 ] && \
[ "$(od -An -tx1 -j16 -N4 "$SRC/unix.sym" | tr -d ' ')" = 00020004 ] || {
	echo "[FAIL] unix.sym is not an ELF32 MSB m68k ET_EXEC" >&2; exit 1; }
_sym() { "$OBJDUMP" -t "$SRC/unix.sym" 2>/dev/null | awk -v n="$1" '$NF == n {print $1; exit}'; }
_end=$(_sym end); _edata=$(_sym edata)
[ -n "$_end" ] && [ $((0x$_end)) = $((0x$_img + K30M_BSS)) ] && [ $((0x$_edata)) = $((0x$_img)) ] || {
	echo "[FAIL] unix.sym: end 0x$_end / edata 0x$_edata, image 0x$_img + bss $K30M_BSS" >&2; exit 1; }
echo "  unix.sym: ET_EXEC, $("$OBJDUMP" -t "$SRC/unix.sym" | grep -c ' g ') globals; edata 0x$_edata = the image, end 0x$_end = image + bss="
python3 -I "$X/tools/ksymgate.py" "$X/build/axrel" "$SRC/unix" "$X/abi/k30/ddi.list" "$X/abi/k30/core.list" \
	> "$WORK/ksymgate" 2>&1 || { cat "$WORK/ksymgate" >&2; echo "[FAIL] ksymgate" >&2; exit 1; }
echo "  ksymgate (on the ET_REL): $(grep -c '^PASS' "$WORK/ksymgate") checks pass, $(tail -1 "$WORK/ksymgate")"
rm -f "$WORK/ksymgate"

echo "--- the filesystem modules: pins, modcheck, .moddata, the rebuild (kit of amix-dlm $K30M_KIT_COMMIT) ---"
kspace_fork_have port "$K30M_PORT_COMMIT"
amix_dlm_kit "$K30M_KIT_COMMIT" "" "$K30M_KIT_PORT" >/dev/null
KIT="$AMIX_DLM_TREE/build/kit/k30"
# the object each carve Makefile links (its EXTRA=): the stock one, as pinned
# and as the cut's carve/stock.sha256 names it -- or, for a filesystem named
# in K30M_FSEXTRA, the cut's own object built from the stock one (-56: ufs
# links qz/ufs.exp, the quirk-91 fix), pinned by sha256; the stock object
# is still checked against stock.sha256 either way
echo "$K30M_FSSTOCK" | while read n h; do
	[ -n "$n" ] || continue
	fs=${n#fs/}; fs=${fs%/exp}
	e=$(sed -n 's/^EXTRA = //p' "$K30M_SRC/$K30M_CARVE/$fs/Makefile")
	x=$(echo "$K30M_FSEXTRA" | awk -v f="$fs" '$1 == f {print $2, $3}')
	if [ -n "$x" ]; then
		set -- $x
		case "$e" in */${K30M_CARVE%/carve}/$1) ;; *) echo "[FAIL] carve/$fs/Makefile links '$e', not the cut's $1" >&2; exit 1 ;; esac
		amix_verify "$e" "$2"
	else
		case "$e" in */usr/sys/$n) ;; *) echo "[FAIL] carve/$fs/Makefile links '$e', not the stock $n" >&2; exit 1 ;; esac
		amix_verify "$e" "$h"
	fi
	grep -qx "$h  $n" "$K30M_SRC/$K30M_CARVE/stock.sha256" || {
		echo "[FAIL] the cut's carve/stock.sha256 does not name $n $h" >&2; exit 1; }
done
echo "$K30M_FSMODS" | while read fs h sz; do
	[ -n "$fs" ] || continue
	amix_kfsmod_check k30 "$fs" "$SRC/mod.d/$fs" "$h" "$sz" "$K30M_BUILDID" "$K30M_KABI" "$KIT" "$WORK/chk-$fs" "$K30M_FSKABI"
	amix_kfsmod_rebuild k30 "$fs" "$K30M_SRC/$K30M_CARVE/$fs" "$SRC/mod.d/$fs" "$KIT" "$WORK/carve-$fs"
done
mkdir -p "$DEST/etc/conf/mod.d" "$DEST/etc/conf/modreg.d"
for fs in $(echo "$K30M_FSMODS" | awk 'NF {print $1}'); do
	cp "$SRC/mod.d/$fs" "$DEST/etc/conf/mod.d/$fs"
	cp "$HERE/modreg.$fs" "$DEST/etc/conf/modreg.d/$fs"
done

cp "$SRC/unix.brel" "$DEST/stand/k30/unix"
cp "$SRC/kabi" "$DEST/stand/k30/kabi"
cp "$SRC/unix.sym" "$DEST/stand/k30/unix.sym"

{
	echo "$K30M_CATALOG_NAME $K30M_VERSION -- the module kernel of Amiga UNIX (Amix), 68030 line,"
	echo "build $K30M_BUILDID."
	echo
	echo "Amiga UNIX is Commodore's port of AT&T UNIX System V Release 4; portions"
	echo "are copyright AT&T, UNIX System Laboratories and their successors, and"
	echo "Commodore-Amiga, Inc.  On 2026-09-23 Amiga Corporation approved the"
	echo "distribution of the Commodore Amiga binaries this project builds on."
	echo "This project and its developers are not affiliated with, endorsed by, or"
	echo "sponsored by Amiga Corporation.  Amiga is a registered trademark of Amiga"
	echo "Corporation."
	echo
	echo "Linked in besides the stock kernel, under the licences below: the"
	echo "A2091/A3091/scsi/support stock-file patches (amix-a4091; its NOTICE says"
	echo "which parts are MIT and which stock context), the Z3660 SCSI dd.c"
	echo "completion-ordering patch (amix-z3660scsi), rth1/ttcompat/"
	echo "tcp_hiwat from the 040/060 port (amix-040-060-port), /dev/kinfo with the"
	echo "build harness's generated tables (amix-kerntools), and the module core:"
	echo "amix-dlm (MIT) on the adopted DLM core (MIT, kdedon).  The 64-bit"
	echo "arithmetic helpers the module core exports to modules come from GCC"
	echo "2.7.2.3's libgcc (GPL-2.0 with the libgcc linking exception: linking it"
	echo "does not put this kernel under the GPL).  The A4091/A4092/A4770 SCSI"
	echo "driver, the Gayle IDE driver and the cdfs CD filesystem are not linked"
	echo "in: they come as module packages (a4091-k30, gayle-k30, cdfs-k30)."
	echo "The stock audio driver (amiga/driver/audio.c) is compiled with"
	echo "amix-paula's three patches (MIT, below): the /dev/paula exclusion, a"
	echo "safe close and a bounded wait in the /dev/audio open."
	echo
	echo "This cut has no built-in ufs or s5 filesystem.  The package carries"
	echo "them as core-tier modules built with the cut (/etc/conf/mod.d/ufs and"
	echo "s5): the stock Amiga UNIX ufs and s5 objects (fs/ufs/exp, fs/s5/exp,"
	echo "under the note above), each linked with a small wrapper and the module"
	echo "header by amix-dlm's carve.py and ABI kit (amix-dlm, MIT, below)."
	echo "$K30M_LICENCES" | while read n h w; do
		[ -n "$n" ] || continue
		echo; echo "======== $n ========"; echo
		cat "$LIC/$(echo "$n" | tr / _)"
	done
	echo "$K30M_DLM_LICENCES" | while read n h; do
		[ -n "$n" ] || continue
		echo; echo "======== amix-dlm $n ========"; echo
		cat "$X/$n"
	done
} > "$WORK/copyright"

find "$DEST" -exec touch -h -d "@$K30M_SOURCE_EPOCH" {} +
chmod 0644 "$DEST/stand/k30/unix" "$DEST/stand/k30/unix.sym"; chmod 0444 "$DEST/stand/k30/kabi"
chmod 0644 "$DEST"/etc/conf/mod.d/* "$DEST"/etc/conf/modreg.d/*
cmp -s "$DEST/stand/k30/unix" "$SRC/unix.brel" && cmp -s "$DEST/stand/k30/kabi" "$SRC/kabi" \
	&& cmp -s "$DEST/stand/k30/unix.sym" "$SRC/unix.sym" \
	&& cmp -s "$DEST/etc/conf/mod.d/ufs" "$SRC/mod.d/ufs" && cmp -s "$DEST/etc/conf/mod.d/s5" "$SRC/mod.d/s5" || {
	echo "[FAIL] staged files are not verbatim copies" >&2; exit 1; }
# the modreg.d files are comments only (C3-5 sec 1.2: the module's own defaults)
! grep -vq '^#' "$DEST"/etc/conf/modreg.d/* || { echo "[FAIL] a modreg.d file has a non-comment line" >&2; exit 1; }

echo "--- package ---"
kspace_epoch "$K30M_SOURCE_EPOCH"
cp "$HERE/pkginfo" "$HERE/prototype" "$WORK/"
amix_kpkgroll "$WORK" "$DEST" "$K30M_PKG" "$K30M_VERSION" "$OUT"
kspace_done "$OUT"
