#!/bin/sh
# run.sh -- the ABI kit (S3-10): build the kit for both lines, build the
# sample module with each through the make fragment alone, and show that
# the checker refuses what C3-1 refuses.  With the module core's host
# loader (`make core` builds it) and the stage-3 module kernels at hand,
# the sample also loads against each kernel's own symbol block.
#
# usage: run.sh [KD060-Z-module-kernel K030-U-module-kernel.etrel]
#   (default: the S3-20/S3-21 cuts under the workspace's tmp/)
# Environment: B (build directory), GCA, G14, PORT as tools/mkkit.sh.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -u
R=$(cd "$(dirname "$0")/../.." && pwd)
WS=$(cd "$R/.." && pwd)
B=$(mkdir -p "${B:-$R/build}" && cd "${B:-$R/build}" && pwd)
G14=${G14:-$WS/gcc14-cross-amix/build}
. "${GCA:-$WS/gcc-cross-amix/build}/env.sh"
PATH="$PATH:$G14/prefix/bin"
K46=${1:-$WS/tmp/2026-10-26-s3-20/out/m/unix}
K30=${2:-$WS/tmp/2026-10-26-s3-21/dlm/usr/sys/unix}
fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
W=$B/kit-test
rm -rf "$W" && mkdir -p "$W"

# refused CASE LINE FILE PATTERN [modcheck args]: the checker says no, naming the rule
refused() {
	c=$1 l=$2 f=$3 p=$4; shift 4
	if python3 "$B/kit/$l/tools/modcheck.py" -k "$B/kit/$l" "$@" "$f" > "$W/$c.out" 2>&1; then
		fail "$l: $c accepted"; cat "$W/$c.out"
	elif grep -q "$p" "$W/$c.out"; then
		pass "$l: $c refused ($(grep -m1 "$p" "$W/$c.out" | sed 's/^modcheck: [^:]*: //'))"
	else
		fail "$l: $c refused for another reason"; cat "$W/$c.out"
	fi
}

# mkbad LINE NAME SOURCE MASTER [EXPORT]: a module through mkmod alone,
# with EXPORT added to the exports so modfix lets it through to the checker
mkbad() {
	l=$1 n=$2 src=$3 master=$4 x=${5:-}
	K=$B/kit/$l
	d=$W/$l-$n
	mkdir -p "$d/src"
	printf '%b' "$src" > "$d/$n.c"
	printf '%b' "$master" > "$d/src/Master"
	. "$K/kit.conf"
	CF="-O -traditional -fno-builtin -Dinline=__inline__ -Dvolatile=__volatile__ -Dconst=__const__ $CPUFLAG -D_KERNEL -DSVR40 -DSVR4 -I$K/include -I$K/stock/usr/include -I$K/stock/usr/sys -I$K/stock/usr/sys/amiga/inc"
	AMIX_SYSROOT=$K/sysroot m68k-cbm-sysv4-gcc $CF -c "$d/$n.c" -o "$d/src/Driver.o" 2> "$d/cc.log" ||
		{ fail "$l: $n does not compile"; cat "$d/cc.log"; return 1; }
	{ cat "$K/exports"; [ -z "$x" ] || echo "$x"; } > "$d/exports"
	MKMOD_CC="m68k-cbm-sysv4-gcc $CF" DLM_TOOLS=$K/tools sh "$K/tools/mkmod" -K "${KABI_OVERRIDE:-$KABI}" \
		-P "${PIN_OVERRIDE:-$PIN}" -e "$d/exports" -o "$d/out" "$d/src" > "$d/mkmod.log" 2>&1 ||
		{ fail "$l: mkmod $n"; cat "$d/mkmod.log"; return 1; }
}

M0='$modtype misc\n$class demand\n$cpu 68020\n'
WRAP='#include "sys/types.h"\n#include "sys/moddefs.h"\nstatic int l() { return 0; }\nstatic int u() { return 0; }\n'

for l in k30 k46; do
	echo "== $l"
	if sh "$R/tools/mkkit.sh" $l "$B/kit/$l" > "$W/mkkit-$l.log" 2>&1; then
		pass "$l: kit built ($(tail -1 "$W/mkkit-$l.log" | sed 's/^mkkit: [^:]*: //'))"
	else
		fail "$l: mkkit"; cat "$W/mkkit-$l.log"; continue
	fi
	K=$B/kit/$l
	# the sample, through the make fragment alone
	if (cd "$K/sample/hello" && make > "$W/hello-$l.log" 2>&1); then
		pass "$l: sample: $(grep '^modcheck' "$W/hello-$l.log")"
	else
		fail "$l: sample build"; cat "$W/hello-$l.log"
	fi
	H=$K/sample/hello/build/$l/mod.d/hello
	# the probe, measured through the kit's own headers, gives the offsets
	# of the line's fingerprint (C3-3 section 4)
	. "$K/kit.conf"
	CF="-O -traditional -fno-builtin -Dinline=__inline__ -Dvolatile=__volatile__ -Dconst=__const__ $CPUFLAG -D_KERNEL -DSVR40 -DSVR4 -I$K/include -I$K/stock/usr/include -I$K/stock/usr/sys -I$K/stock/usr/sys/amiga/inc"
	if AMIX_SYSROOT=$K/sysroot sh "$K/tools/mkoffs" m68k-cbm-sysv4-gcc $CF > "$W/offs-$l.h" 2> "$W/offs-$l.log" &&
	   awk '/^#define/ {print "offs", $2, $3}' "$W/offs-$l.h" | LC_ALL=C sort > "$W/offs-$l.got" &&
	   grep '^offs ' "$K/abi-$KABI.txt" > "$W/offs-$l.want" && cmp -s "$W/offs-$l.got" "$W/offs-$l.want"; then
		pass "$l: the probe through the kit's headers: $(wc -l < "$W/offs-$l.got") offsets, as abi-$KABI.txt"
	else
		fail "$l: the probe's offsets differ from abi-$KABI.txt"; diff "$W/offs-$l.got" "$W/offs-$l.want"; cat "$W/offs-$l.log"
	fi
	# a font-drawing module: the kit's Sun font linked in, builtinfont local
	d=$W/$l-font
	mkdir -p "$d"
	printf '%b' "$WRAP"'extern char builtinfont[];\nchar *font() { return builtinfont; }\nMOD_MISC_WRAPPER(fontmod, l, u, "font");\n' > "$d/fontmod.c"
	printf '%b' "$M0"'fontmod\tfontmod\n' > "$d/Master"
	printf 'KIT = %s\nMODULE = fontmod\nOBJS = fontmod.o\nEXTRA = $(KIT)/stock/usr/sys/amiga/console/sunfont.o\nLOCALIZE = builtinfont\ninclude $(KIT)/mk/module.mk\n' "$K" > "$d/Makefile"
	if (cd "$d" && make > make.log 2>&1) && m68k-elf-nm "$d/build/$l/mod.d/fontmod" | grep -q ' d builtinfont$'; then
		pass "$l: a module with the kit's sunfont.o and LOCALIZE=builtinfont: ok, builtinfont local"
	else
		fail "$l: the font module"; cat "$d/make.log"
	fi
	if (cd "$d" && make LOCALIZE_OBJCOPY=no-such-objcopy > nolocal.log 2>&1); then
		fail "$l: LOCALIZE without its objcopy was not refused"
	elif grep -q "LOCALIZE needs no-such-objcopy" "$d/nolocal.log"; then
		pass "$l: LOCALIZE without its objcopy is refused up front, naming the tool"
	else
		fail "$l: LOCALIZE without its objcopy"; cat "$d/nolocal.log"
	fi

	# what the checker refuses
	cp "$H" "$W/$l-hello2" && refused "name other than the file" $l "$W/$l-hello2" "the file name is the module name"
	mkbad $l cdevsw "$WRAP"'extern int cdevsw[];\nint f() { return cdevsw[0]; }\nMOD_MISC_WRAPPER(cdevsw, l, u, "x");\n' "$M0"'cdevsw\tcdevsw\n' cdevsw &&
		refused "an off-list kernel name" $l "$W/$l-cdevsw/out/mod.d/cdevsw" "cdevsw is not in the allowlist"
	mkbad $l major "$WRAP"'MOD_MISC_WRAPPER(major, l, u, "x");\n' "$M0"'$majors c:60\nmajor\tmajor\n' &&
		refused "an unregistered major" $l "$W/$l-major/out/mod.d/major" "major c:60 is not in the registry"
	mkbad $l owned "$WRAP"'MOD_MISC_WRAPPER(owned, l, u, "x");\n' "$M0"'$majors c:51\nowned\towned\n' &&
		refused "another module's major" $l "$W/$l-owned/out/mod.d/owned" "registered to z3660eth"
	mkbad $l boolp "$WRAP"'MOD_MISC_WRAPPER(boolp, l, u, "x");\n' "$M0"'$param on:bool:yes\nboolp\tboolp\n' &&
		refused "a bool default other than 0 or 1" $l "$W/$l-boolp/out/mod.d/boolp" "is not a bool value"
	mkbad $l root "$WRAP"'MOD_MISC_WRAPPER(root, l, u, "x");\n' '$modtype misc\n$class root\n$cpu 68020\n$match always\nroot\troot\n' &&
		refused "class root before stage 4" $l "$W/$l-root/out/mod.d/root" "root-class modules come with stage 4"
	mkbad $l zkey "$WRAP"'MOD_MISC_WRAPPER(zkey, l, u, "x");\n' "$M0"'$match zorro:0000:01\nzkey\tzkey\n' &&
		refused "a zero match key" $l "$W/$l-zkey/out/mod.d/zkey" "may be zero"
	PIN_OVERRIDE=gcc-2.95.3-0000000 mkbad $l pin "$WRAP"'MOD_MISC_WRAPPER(pin, l, u, "x");\n' "$M0"'pin\tpin\n' &&
		refused "another compiler pin" $l "$W/$l-pin/out/mod.d/pin" "the kit's pin is"
	other=$([ $l = k30 ] && echo k46.1.0 || echo k30.1.0)
	KABI_OVERRIDE=$other mkbad $l kabi "$WRAP"'MOD_MISC_WRAPPER(kabi, l, u, "x");\n' "$M0"'kabi\tkabi\n' &&
		refused "the other line's kabi" $l "$W/$l-kabi/out/mod.d/kabi" "this kit is"
	mkbad $l common "$WRAP"'int ifnet, common_count;\nint f() { return ifnet + common_count; }\nMOD_MISC_WRAPPER(common, l, u, "x");\n' "$M0"'common\tcommon\n' &&
		if python3 "$K/tools/modcheck.py" -k "$K" "$W/$l-common/out/mod.d/common" > "$W/common.out" 2>&1 &&
		   grep -q "warning: COMMON symbol ifnet" "$W/common.out" &&
		   ! grep -q "COMMON symbol common_count" "$W/common.out"; then
			pass "$l: a COMMON outside the module's names is warned about (not its own), not refused"
		else
			fail "$l: COMMON warning"; cat "$W/common.out"
		fi
	if [ $l = k46 ]; then
		mkbad $l geom "$WRAP"'unsigned f(a) unsigned a; { return a >> 11; }\nMOD_MISC_WRAPPER(geom, l, u, "x");\n' "$M0"'geom\tgeom\n' &&
			refused "a 2 KiB page shift on k46" $l "$W/$l-geom/out/mod.d/geom" "shift by 11"
	fi

	# the sample against the module kernel's own symbol block, as the loader leaves it
	KERN=$([ $l = k46 ] && echo "$K46" || echo "$K30")
	KNAME=$([ $l = k46 ] && echo "the KD060-Z module kernel" || echo "the K030-U module kernel")
	if [ -x "$B/core/test-bin/reloc" ] && [ -f "$KERN" ]; then
		python3 "$R/tools/ksymgate.py" --extract "$B/core/test-bin/axrel" "$KERN" 0x08000000 "$W/ksym-$l.bin" > /dev/null 2>&1
		if "$B/core/test-bin/reloc" -k "$W/ksym-$l.bin" -b 0x300000 "$H" 2>&1 | grep -q '^OK'; then
			pass "$l: the sample loads against $KNAME's symbol block"
		else
			fail "$l: the sample against the module kernel's block"; "$B/core/test-bin/reloc" -k "$W/ksym-$l.bin" -b 0x300000 "$H"
		fi
	else
		echo "SKIP $l: no host loader (make core) or no module kernel: the load against the block"
	fi
done
# one module directory, both kits: each line's objects and module apart
d=$W/both
mkdir -p "$d"
cp "$R/abi/sample/hello/hello.c" "$R/abi/sample/hello/Master" "$d/"
printf 'MODULE = hello\nOBJS = hello.o\ninclude $(KIT)/mk/module.mk\n' > "$d/Makefile"
if (cd "$d" && make KIT="$B/kit/k30" > make30.log 2>&1 && make KIT="$B/kit/k46" > make46.log 2>&1) &&
   strings "$d/build/k30/mod.d/hello" | grep -q '^kabi=k30.1.0$' &&
   strings "$d/build/k46/mod.d/hello" | grep -q '^kabi=k46.1.0$'; then
	pass "one directory, both kits: build/k30 and build/k46 each hold their own line's module"
else
	fail "one directory, both kits"; cat "$d"/make*.log
fi
if (cd "$d" && make KIT="$B/kit/k46" MODOUT=. clean > clean.log 2>&1); then
	fail "clean with MODOUT=. was not refused"
else
	pass "clean refuses MODOUT=."
fi

echo "kit: $fails failed"
[ $fails -eq 0 ]
