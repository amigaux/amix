#!/bin/sh
# build-a4091-040.sh -- cross-build the 040/060 arm of src/a4091-wr.c (-DA4091_KVA) and gate it.
#
# This is the driver-side proof only.  The kernel relink that consumes the object (sd.c rows,
# sdcardbase() shim, loop bound, switch rows, init hook, devkvmap040.o) is the port's PO-04
# (relink-040-a4091.sh in amix-040-060-port); nothing here touches that repository.
#
#   sh tools/build-a4091-040.sh [--d42]        # --d42: import dma_prepare/dma_complete
#                                              # instead of the local stubs
# Environment (defaults in brackets; <amix> is the top of the amix checkout):
#   GCC_CROSS_ENV   gcc-cross-amix build/env.sh, at toolchain/gcc-cross-amix.pin
#                   [$GCA/env.sh, else <amix>/../gcc-cross-amix/build/env.sh]
#   MODELB_SYSROOT  the port's Model-B mirror sysroot (build/sysroot-modelb of a port checkout
#                   or archive)  [required]
#   PORT_DIR        a port checkout at kernel/port/port.pin, for tools/spl-gate.py and
#                   test-tools/scan060.py  [$PORT, else <amix>/../amix-040-060-port]  (read only)
# A git checkout at another commit than its pin is reported, not refused.
#
# Gates (any failure exits 1):
#   G1/G2   the port's spl-gate: volatile survives -traditional; every spl-calling function
#           writes %sr (per function).
#   scan060 no 68060-unimplemented candidate in kernel code.
#   widths  every 53C710 access is a byte on a byte register and a longword on a 32-bit one.
#   imports exactly the expected set (below); dev_kvmap is required (the define took).
#   no sptalloc, no fixed 0x40000000 in the 040 arm.
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
AMIX=$(cd "$HERE/../../.." && pwd)
D42=
[ "$1" = "--d42" ] && D42=-DA4091_D42
: "${GCC_CROSS_ENV:=${GCA:-$AMIX/../gcc-cross-amix/build}/env.sh}"
: "${PORT_DIR:=${PORT:-$AMIX/../amix-040-060-port}}"
pin_check() {	# pin_check <pin file> <checkout>
	read -r _url _want < "$1"
	[ -e "$2/.git" ] || return 0
	_have=$(git -C "$2" rev-parse HEAD 2>/dev/null) || return 0
	[ "$_have" = "$_want" ] || echo "[warn] $2 is at $_have, ${1#$AMIX/} pins $_want"
}
pin_check "$AMIX/toolchain/gcc-cross-amix.pin" "$(dirname "$GCC_CROSS_ENV")/.."
pin_check "$AMIX/kernel/port/port.pin" "$PORT_DIR"
[ -n "$MODELB_SYSROOT" ] || { echo "[FAIL] MODELB_SYSROOT not set (the port's build/sysroot-modelb)"; exit 1; }
. "$GCC_CROSS_ENV"
AMIX_SYSROOT=$MODELB_SYSROOT; export AMIX_SYSROOT
ALIEN=$AMIX_SYSROOT/usr/sys/amiga/alien
[ -f "$ALIEN/sd.h" ] || { echo "[FAIL] sd.h not under $ALIEN"; exit 1; }

OUT=$HERE/build/k040; mkdir -p "$OUT"
O=$OUT/a4091_040${D42:+-d42}.o
CF=$(echo "$AMIX_KERNEL_CFLAGS" | sed 's/-m68020/-m68040/')
echo "[*] cc: $CF -DA4091_KVA $D42"
m68k-cbm-sysv4-gcc $CF -DA4091_KVA $D42 -I"$ALIEN" -I"$HERE/src" -c "$HERE/src/a4091-wr.c" -o "$O"
sha256sum "$O" | sed 's/^/    /'

echo "[*] spl-gate G1/G2"
python3 "$PORT_DIR/tools/spl-gate.py" --object "$O" --source "$HERE/src/a4091-wr.c" --cflags "$CF" \
	-- -DA4091_KVA $D42 -I"$ALIEN" -I"$HERE/src"

echo "[*] scan060"
LC_ALL=C m68k-linux-gnu-objdump -d "$O" > "${O%.o}.lst"
SCAN=$(python3 "$PORT_DIR/test-tools/scan060.py" "${O%.o}.lst")
echo "$SCAN" | sed 's/^/    /'
echo "$SCAN" | grep -q 'CLEAN -- no candidate found' || { echo "[FAIL] scan060 not CLEAN"; exit 1; }

echo "[*] register access widths"
python3 "$HERE/tools/a4091-widths.py" "$O" | sed 's/^/    /'
python3 "$HERE/tools/a4091-widths.py" "$O" > /dev/null || { echo "[FAIL] widths"; exit 1; }

echo "[*] imports"
WANT="bprobe dev_kvmap dev_kvunmap printf sdcardbase"
[ -n "$D42" ] && WANT="bprobe dev_kvmap dev_kvunmap dma_complete dma_prepare printf sdcardbase"
GOT=$(m68k-linux-gnu-nm "$O" | awk '$1=="U"{print $2}' | sort | tr '\n' ' ' | sed 's/ $//')
echo "    $GOT"
[ "$GOT" = "$WANT" ] || { echo "[FAIL] imports differ from: $WANT"; exit 1; }
if LC_ALL=C m68k-linux-gnu-objdump -dr "$O" | grep -qE 'R_68K_32[[:space:]]+sptalloc|#1073741824'; then
	echo "[FAIL] the 040 arm still references sptalloc or a fixed 0x40000000"; exit 1
fi
echo "[OK] $O"
