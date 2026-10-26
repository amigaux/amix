#!/bin/sh
# build-module.sh -- the z3660eth driver as a loadable-module object, one per
# kernel line (amix-dlm docs/contracts/C3-6-driver-to-module.md section 2).
#
#   sh tools/build-module.sh [k30|k46 ...]        default: both lines
#
# For each line: compile src/z3660eth.c with -DZ3660ETH_MODULE into ONE
# relocatable object, build/<line>/z3660eth.o, write build/<line>/z3660eth.keys
# (src/z3660eth.modkeys filled in for the line), and gate it: every undefined
# symbol must be a name of that line's DDI v1 list (amix-dlm abi/<line>/ddi.list);
# the one weak undefined allowed is the wrapper's own z3660eth_conf_data, which
# C3-1 section 1 resolves to 0 when the kit provides none.  Also: the 68060 scan
# (the toolchain's scan060), and on k46 no 2 KiB page shift.  Prints the imports
# and the exports.  The ABI kit (amix-dlm S3-10) wraps the object: .moddata
# from the keys (mkmod), the section type (modfix).  Nothing here does that.
#
#   k30: -m68020, the toolchain's stock sysroot (2 KiB pages), kabi k30.1.0
#   k46: -m68040, a mirror sysroot whose <sys/immu.h> and <sys/param.h> are the
#        040/060 port's Model-B headers (4 KiB pages), kabi k46.1.0
#
# Inputs, read only (defaults: the sibling checkouts):
#   GCA   gcc-cross-amix build dir (env.sh)         ../gcc-cross-amix/build
#   DLM   amix-dlm checkout (core, abi lists)       ../amix-dlm
#   PORT  amix-040-060-port checkout (include-modelb) ../amix-040-060-port
#   DLM_INC  the kit's include dir, when the kit exists; otherwise the
#            module core's headers are staged from DLM's patch queue.
# Output: build/ in this repository only.
set -e
LC_ALL=C; export LC_ALL

HERE=$(cd "$(dirname "$0")/.." && pwd)
WS=$(cd "$HERE/.." && pwd)
GCA=${GCA:-$WS/gcc-cross-amix/build}
DLM=${DLM:-$WS/amix-dlm}
PORT=${PORT:-$WS/amix-040-060-port}
B=$HERE/build
CC_PIN=gcc-2.7.2.3-8949028

. "$GCA/env.sh"
REAL=$AMIX_SYSROOT
mkdir -p "$B"

# ---- the module core's headers (sys/moddefs.h at wrapper revision 2)
if [ -z "$DLM_INC" ]; then
	rm -rf "$B/dlm-core"
	cp -R "$DLM/core/upstream" "$B/dlm-core"
	grep -v '^#' "$DLM/core/series" | grep -v '^[ 	]*$' | while read -r p; do
		patch -s -p1 -d "$B/dlm-core" < "$DLM/core/patches/$p"
	done
	DLM_INC=$B/dlm-core/include
fi
grep -q '^#define[ 	]*MODREV[ 	]*2' "$DLM_INC/sys/moddefs.h" \
	|| { echo "FAIL: $DLM_INC/sys/moddefs.h is not wrapper revision 2"; exit 1; }

# ---- the k46 mirror sysroot (as amix-040-060-port src/mk_modelb_sysroot.sh)
mirror() {
	M=$B/sysroot-k46
	rm -rf "$M"
	mkdir -p "$M/usr/include/sys"
	for e in "$REAL"/usr/*; do
		[ "$(basename "$e")" = include ] || ln -s "$e" "$M/usr/$(basename "$e")"
	done
	for e in "$REAL"/usr/include/*; do
		[ "$(basename "$e")" = sys ] || ln -s "$e" "$M/usr/include/$(basename "$e")"
	done
	for e in "$REAL"/usr/include/sys/*; do
		ln -s "$e" "$M/usr/include/sys/$(basename "$e")"
	done
	for h in immu param; do
		rm -f "$M/usr/include/sys/$h.h"
		ln -s "$REAL/usr/include/sys/$h.h" "$M/usr/include/sys/${h}_stock.h"
		cp "$PORT/include-modelb/sys/$h.h" "$M/usr/include/sys/$h.h"
	done
}

fails=0
[ $# -gt 0 ] || set -- k30 k46
for line in "$@"; do
	case $line in
	k30) CPU=68030; CF=$AMIX_KERNEL_CFLAGS; SR=$REAL ;;
	k46) CPU=68040; CF=$(echo "$AMIX_KERNEL_CFLAGS" | sed 's/-m68020/-m68040/')
	     mirror; SR=$B/sysroot-k46 ;;
	*) echo "usage: build-module.sh [k30|k46 ...]"; exit 2 ;;
	esac
	O=$B/$line
	mkdir -p "$O"
	echo "== $line ($CPU, kabi $line.1.0)"
	AMIX_SYSROOT=$SR m68k-cbm-sysv4-gcc $CF -DZ3660ETH_MODULE -I"$DLM_INC" \
		-I"$HERE/src" -c "$HERE/src/z3660eth.c" -o "$O/z3660eth.o"
	sed -e "s/@KABI@/$line.1.0/" -e "s/@CPU@/$CPU/" -e "s/@CC@/$CC_PIN/" \
		"$HERE/src/z3660eth.modkeys" | grep -v '^#' > "$O/z3660eth.keys"

	LIST=$DLM/abi/$line/ddi.list
	# binutils 2.8.1's nm prints a weak undefined as U: bind from readelf
	readelf -sW "$O/z3660eth.o" > "$O/symtab"
	awk '$7 == "UND" && $5 == "GLOBAL" { print $8 }' "$O/symtab" | sort > "$O/imports"
	awk '$7 == "UND" && $5 == "WEAK" { print $8 }' "$O/symtab" | sort > "$O/weak"
	awk '$7 != "UND" && $5 == "GLOBAL" { print $8 }' "$O/symtab" | sort > "$O/exports"
	awk '$7 == "COM" { print $8 }' "$O/symtab" | sort > "$O/common"
	awk '!/^#/ && NF { print $1 }' "$LIST" | sort > "$O/ddi"
	off=$(comm -23 "$O/imports" "$O/ddi")
	echo "   imports ($(wc -l < "$O/imports")): $(tr '\n' ' ' < "$O/imports")"
	echo "   weak:    $(tr '\n' ' ' < "$O/weak")"
	echo "   exports ($(wc -l < "$O/exports")): $(tr '\n' ' ' < "$O/exports")"
	echo "   of them COMMON ($(wc -l < "$O/common")), allocated by the core per module"
	if [ -n "$off" ]; then
		echo "FAIL $line: undefined, not on $LIST: $off"; fails=$((fails + 1))
	else
		echo "PASS $line: every undefined symbol is on abi/$line/ddi.list"
	fi
	if [ "$(cat "$O/weak")" != z3660eth_conf_data ] && [ -s "$O/weak" ]; then
		echo "FAIL $line: weak undefined other than z3660eth_conf_data"; fails=$((fails + 1))
	fi
	for s in z3660eth_wrapper z3660eth_load z3660eth_unload z3660eth_halt z3660eth_drvdata; do
		grep -qx "$s" "$O/exports" || { echo "FAIL $line: $s not defined"; fails=$((fails + 1)); }
	done
	if m68k-cbm-sysv4-scan060 --quiet "$O/z3660eth.o"; then
		echo "PASS $line: scan060 finds no 68060-unimplemented instruction"
	else
		echo "FAIL $line: scan060"; fails=$((fails + 1))
	fi
	if [ "$line" = k46 ]; then
		if m68k-cbm-sysv4-objdump -d "$O/z3660eth.o" | grep -A1 'moveq #11,' | grep -q 'lsrl\|asrl'; then
			echo "FAIL k46: a 2 KiB page shift (by 11)"; fails=$((fails + 1))
		else
			echo "PASS k46: no 2 KiB page shift"
		fi
	fi
	sha256sum "$O/z3660eth.o" | sed "s|$B/||; s/^/   /"
done
[ $fails -eq 0 ] || { echo "$fails check(s) failed"; exit 1; }
