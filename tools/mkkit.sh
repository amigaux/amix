#!/bin/sh
# mkkit.sh -- build the ABI kit for one kernel line (docs/spec/20-module-
# format-and-abi.md section 5; plan item S3-10): everything a module build
# needs, with no Amix tree beside it.
#
# usage: mkkit.sh LINE OUTDIR        LINE: k30 or k46
#
# OUTDIR gets:
#   kit.conf             LINE, KABI, PIN, CPUFLAG, DEFCPU (a module's default
#                        cpu=), KIT_REV (the amix-dlm commit; -dirty when
#                        the kit's inputs had uncommitted changes)
#   include/sys/         mod.h, moddefs.h, ksym.h (the module core's, after
#                        core/series) and amixddi.h (abi/include)
#   sysroot/usr/include/ the stock headers of the pinned sysroot, which the
#                        gcc wrapper puts first ($AMIX_SYSROOT)
#   stock/usr/include/,  the stock headers AMIX_KERNEL_CFLAGS names
#   stock/usr/sys/       (headers only, never a source file), and
#                        amiga/console/sunfont.o, the stock Sun font
#                        assembled by tools/sunfont.py
#   tools/               mkmod, modfix (built here), modcheck.py, mkoffs and
#                        mkabi.py (the fingerprint, C3-3 section 4)
#   dlmoffs.c            the probe: the structure offsets mkoffs measures
#   abi.txt              the kernel line's fingerprint text (abi= is its SHA-256;
#                        abi/<line>/abi-<kabi>.txt here)
#   mk/module.mk         the make fragment
#   ddi.list, core.list, exports (their names), registry/
#   sample/hello/        the sample module
#   docs/                ddi.md, guide.md (docs/abi/writing-a-module.md) and
#                        contracts/C3-1.md, C3-2.md, C3-6.md
# Every name in the kit is at most 14 bytes, so the package installs on s5.
#   LICENSE, NOTICE, README.md
# On k46 the two page-geometry headers, sys/immu.h and sys/param.h, are the
# 68040/68060 port's 4 KiB forms (amix-040-060-port include-modelb/), the
# stock ones kept as sys/immu_stock.h and sys/param_stock.h, as the port's
# own mirror sysroot does.
#
# The stock headers are Commodore's: they go into the kit, which is
# published under the distribution permission of 2026-09-23 (D-3 section 7),
# and never into this repository (build/ is not tracked).
#
# Environment: GCA (gcc-cross-amix's build directory, default the sibling
# checkout), PORT (amix-040-060-port, default the sibling), HOSTCC.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
LINE=$1 OUT=$2
case "$LINE" in
k30) KABI=k30.1.2 CPUFLAG=-m68020 DEFCPU=68030 ;;
k46) KABI=k46.1.2 CPUFLAG=-m68040 DEFCPU=68040 ;;
*) echo "usage: mkkit.sh k30|k46 OUTDIR" >&2; exit 2 ;;
esac
[ -n "$OUT" ] || { echo "usage: mkkit.sh k30|k46 OUTDIR" >&2; exit 2; }
R=$(cd "$(dirname "$0")/.." && pwd)
WS=$(cd "$R/.." && pwd)
GCA=${GCA:-$WS/gcc-cross-amix/build}
PORT=${PORT:-$WS/amix-040-060-port}
. "$GCA/env.sh"
PIN=gcc-2.7.2.3-$(awk '$1 == "commit" {print $2}' "$R/toolchain.pin")
REV=$(git -C "$R" rev-parse --short HEAD 2>/dev/null || echo unknown)
# a kit built from uncommitted inputs says so in its revision
if [ -n "$(git -C "$R" status --porcelain -- abi core tools/mkkit.sh tools/sunfont.py \
	docs/abi/ddi.md docs/abi/writing-a-module.md docs/contracts LICENSE 2>/dev/null)" ]; then
	REV=$REV-dirty
	echo "mkkit: the kit's inputs have uncommitted changes: KIT_REV=$REV" >&2
fi

rm -rf "$OUT"
mkdir -p "$OUT/include/sys" "$OUT/tools" "$OUT/mk" "$OUT/registry" "$OUT/sample" \
	"$OUT/docs/contracts" "$OUT/sysroot/usr" "$OUT/stock/usr"
OUT=$(cd "$OUT" && pwd)

# the module core as shipped: core/upstream with core/series applied
S=$OUT/.core
mkdir -p "$S"
cp -R "$R/core/upstream/." "$S/"
while read p; do
	case "$p" in \#*|"") continue ;; esac
	patch -p1 -s -d "$S" < "$R/core/patches/$p"
done < "$R/core/series"
cp "$S/include/sys/mod.h" "$S/include/sys/moddefs.h" "$S/include/sys/ksym.h" "$OUT/include/sys/"
cp "$R/abi/include/sys/amixddi.h" "$OUT/include/sys/"
cp "$S/tools/mkmod" "$S/tools/mkoffs" "$OUT/tools/"
cp "$S/dlmoffs.c" "$OUT/"		# the probe: tools/mkoffs finds it here
${HOSTCC:-cc} -std=gnu89 -O -w -o "$OUT/tools/modfix" "$S/tools/modfix.c"
cp "$S/LICENSE" "$OUT/tools/LICENSE.core"
rm -rf "$S"
cp "$R/abi/tools/modcheck.py" "$OUT/tools/"
cp "$R/abi/mk/module.mk" "$OUT/mk/"

cp "$R/abi/$LINE/ddi.list" "$R/abi/$LINE/core.list" "$OUT/"
cp "$R/abi/$LINE/abi-$KABI.txt" "$OUT/abi.txt"
cp "$R/tools/mkabi.py" "$OUT/tools/"
cat "$OUT/ddi.list" "$OUT/core.list" | sed 's/#.*//' | awk 'NF {print $1}' | sort -u > "$OUT/exports"
cp "$R/abi/registry/"* "$OUT/registry/"
cp -R "$R/abi/sample/hello" "$OUT/sample/"
sed -i 's|^KIT    ?= .*|KIT    ?= ../..|' "$OUT/sample/hello/Makefile"

# the guides by name: docs/abi/ also holds the DDI review draft, which
# leaves this repository only on the owner's word
cp "$R/docs/abi/ddi.md" "$OUT/docs/"
cp "$R/docs/abi/writing-a-module.md" "$OUT/docs/guide.md"
for c in C3-1-module-object C3-2-symbols-and-ddi C3-6-driver-to-module; do
	cp "$R/docs/contracts/$c.md" "$OUT/docs/contracts/${c%%-[a-z]*}.md"
done
# the interface headers of generic modules, versioned with the module's
# release: sys/monsw.h from amix-modules' include/sys/ (where every generic
# module's header sits) once monsw is there, from the port's copy until then
MONSW_H=${MONSW_H:-$WS/amix-modules/include/sys/monsw.h}
[ -f "$MONSW_H" ] || MONSW_H=$PORT/src/sys/monsw.h
[ -f "$MONSW_H" ] || { echo "mkkit: no sys/monsw.h ($MONSW_H)" >&2; exit 1; }
cp "$MONSW_H" "$OUT/include/sys/monsw.h"
# where it came from: the repository's commit, -dirty if the file differs
MONSW_DIR=$(dirname "$MONSW_H")
MONSW_REV=$(git -C "$MONSW_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)
git -C "$MONSW_DIR" diff --quiet HEAD -- "$MONSW_H" 2>/dev/null || MONSW_REV=$MONSW_REV-dirty
MONSW_REPO=$(basename "$(git -C "$MONSW_DIR" rev-parse --show-toplevel 2>/dev/null || echo unknown)")
cp "$R/LICENSE" "$OUT/LICENSE"
cp "$R/abi/README.md" "$OUT/README.md"

# the stock headers, headers only
headers() {	# headers SRC DST
	[ -d "$1" ] || { echo "mkkit: no $1" >&2; exit 1; }
	mkdir -p "$2"
	(cd "$1" && find . -name '*.h' -type f) > "$OUT/.list"
	tar -C "$1" -cf - -T "$OUT/.list" | tar -C "$2" -xf -
	rm -f "$OUT/.list"
}
headers "$AMIX_SYSROOT/usr/include" "$OUT/sysroot/usr/include"
headers "$AMIX_ROOT/usr/include" "$OUT/stock/usr/include"
headers "$AMIX_ROOT/usr/sys" "$OUT/stock/usr/sys"
# sd.h as the kernels of this kabi build it: the four-card sd layer
# (C4-1 section 2; amix-kerntools build-cross-kernel.sh --sd-cards 4, the
# port's sd4card base), each stock line replaced exactly once
SDH=$OUT/stock/usr/sys/amiga/alien/sd.h
for e in '#define	SDCARDS	2|#define	SDCARDS	4' \
	 '#define	sdcard( dev)	((dev)>>3 \& 01)|#define	sdcard( dev)	((dev)>>3 \& 01 | (dev)>>6 \& 02)'; do
	old=$(printf '%s' "${e%%|*}" | sed 's/\\&/\&/g') new=$(printf '%s' "${e#*|}" | sed 's/\\&/\&/g')
	n=$(grep -cxF -- "$old" "$SDH" || true)
	[ "$n" = 1 ] || { echo "mkkit: '$old' occurs $n time(s) in $SDH, want 1" >&2; exit 1; }
	OLD=$old NEW=$new awk '$0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; next } { print }' \
		"$SDH" > "$SDH.edit" && mv "$SDH.edit" "$SDH"
done
# the stock console's Sun font as a linkable object (a console-drawing
# driver links it, C3-6 section 3); built from the stock source, which is
# not copied
mkdir -p "$OUT/stock/usr/sys/amiga/console"
python3 "$R/tools/sunfont.py" "$AMIX_ROOT/usr/sys/amiga/console" \
	"$OUT/stock/usr/sys/amiga/console/sunfont.o" > /dev/null
if [ "$LINE" = k46 ]; then
	for d in "$OUT/sysroot/usr/include/sys" "$OUT/stock/usr/include/sys"; do
		for h in immu param; do
			[ -f "$PORT/include-modelb/sys/$h.h" ] ||
				{ echo "mkkit: no $PORT/include-modelb/sys/$h.h (the k46 4 KiB headers)" >&2; exit 1; }
			mv "$d/$h.h" "$d/${h}_stock.h"
			cp "$PORT/include-modelb/sys/$h.h" "$d/$h.h"
		done
	done
	# the port commit the two headers come from, -dirty if they differ from it
	PORT_REV=$(git -C "$PORT" rev-parse --short HEAD 2>/dev/null || echo unknown)
	git -C "$PORT" diff --quiet HEAD -- include-modelb/sys/immu.h include-modelb/sys/param.h \
		2>/dev/null || PORT_REV=$PORT_REV-dirty
fi

cat > "$OUT/kit.conf" <<EOF
# the ABI kit for $LINE (amix-dlm $REV): read by mk/module.mk and modcheck.py
LINE=$LINE
KABI=$KABI
PIN=$PIN
CPUFLAG=$CPUFLAG
DEFCPU=$DEFCPU
KIT_REV=$REV
EOF
[ "$LINE" = k46 ] && echo "PORT_REV=$PORT_REV" >> "$OUT/kit.conf"
echo "MONSW_REV=$MONSW_REPO@$MONSW_REV" >> "$OUT/kit.conf"
cat > "$OUT/NOTICE" <<EOF
The Amix ABI kit for $KABI, built from amix-dlm $REV.

Under the MIT licence (LICENSE), Copyright (c) 2026 Jussi Alanärä:
include/sys/amixddi.h, tools/modcheck.py, mk/, sample/, docs/, the lists and
the registries.  include/sys/mod.h, moddefs.h, ksym.h, tools/mkmod and
tools/modfix come from kdedon's MIT module core, with amix-dlm's changes
(tools/LICENSE.core).
include/sys/monsw.h, the monitor switch's interface, is Jussi Alanärä's, from
$MONSW_REPO at $MONSW_REV$( [ "$MONSW_REPO" = amix-modules ] && printf ' (MIT)' ).

sysroot/ and stock/ hold Commodore's Amix 2.1 kernel headers, published in
this kit under the distribution permission given to the project on
2026-09-23.$( [ "$LINE" = k46 ] && printf '\nsys/immu.h and sys/param.h there are the 68040/68060 port'"'"'s 4 KiB page\nforms of the stock headers (amix-040-060-port include-modelb/ at '"$PORT_REV"').' )$( [ "$LINE" = k30 ] && printf '\n\nThe DMA names (dma_prepare and the others, contract C4-5) are listed, but\ntheir k30 provider is a placeholder until the 030 provider (S4-62):\ndma_alloc returns 0, so a bus-master driver fails its _load on this line.' )
EOF
# s5 keeps 14 bytes of a name: the package must install there
long=$(cd "$OUT" && find . | awk -F/ '{ for (i = 2; i <= NF; i++) if (length($i) > 14) { print; break } }')
[ -z "$long" ] || { echo "mkkit: names over 14 bytes: $long" >&2; exit 1; }
n=$(find "$OUT/sysroot" "$OUT/stock" -name '*.h' | wc -l)
echo "mkkit: $OUT: $LINE $KABI, pin $PIN, $n stock headers, amix-dlm $REV"
