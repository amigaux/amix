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
pass() { printf "PASS %s\n" "$*"; }
fail() { printf "FAIL %s\n" "$*"; fails=$((fails + 1)); }
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
# edit FILE OUT: OUT is FILE with python's edit (stdin) applied to its bytes `d`
edit() {
	mkdir -p "$(dirname "$2")"
	python3 -c "
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
u16 = lambda o: struct.unpack('>H', d[o:o+2])[0]
u32 = lambda o: struct.unpack('>I', d[o:o+4])[0]
shoff, shnum = u32(32), u16(48)
sh = lambda i, f: u32(shoff + 40 * i + f)
$(cat)
open(sys.argv[2], 'wb').write(d)" "$1" "$2" || { fail "cannot make $2"; return 1; }
}
# a character driver, as the guide's section 4 shows: NAME on MAJOR, and
# STR=1 for a STREAMS driver (d_str only); built under a registered name
DRV='#include "sys/types.h"\n#include "sys/conf.h"\n#include "sys/moddefs.h"\nstatic int o() { return 0; }\nstatic int l() { return 0; }\nstatic int u() { return 0; }\n'
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
	   grep '^offs ' "$K/abi.txt" > "$W/offs-$l.want" && cmp -s "$W/offs-$l.got" "$W/offs-$l.want"; then
		pass "$l: the probe through the kit's headers: $(wc -l < "$W/offs-$l.got") offsets, as abi.txt"
	else
		fail "$l: the probe's offsets differ from abi.txt"; diff "$W/offs-$l.got" "$W/offs-$l.want"; cat "$W/offs-$l.log"
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
		# a 64-bit multiply the 68060 lacks, past the compiler's rewrite
		mkbad $l m64 "$WRAP"'int f(a, b) int a, b; { int h, lo; __asm__("mulsl %2,%0:%1" : "=d" (h), "=d" (lo) : "d" (b), "1" (a)); return h; }\nMOD_MISC_WRAPPER(m64, l, u, "x");\n' "$M0"'m64\tm64\n' &&
			refused "a 64-bit multiply on k46 (the 68060 scan)" $l "$W/$l-m64/out/mod.d/m64" "68060 scan"
	fi

	# driver-type modules through the kit (C3-6 section 1.2): a character
	# driver as monsw on 52 and a STREAMS driver as z3660eth on 51, the
	# majors registered to those names; drv_cmajor must agree with majors=
	mkbad $l monsw "$DRV"'struct mod_drv_data monsw_drvdata[] = { { { 0 }, 0, 0, { o, o, o, o, o }, 52, 1 } };\nMOD_DRV_WRAPPER(monsw, l, u, 0, "a character driver");\n' '$modtype drv\n$class demand\n$cpu 68020\n$majors c:52\nmonsw\tmonsw\n' &&
		if python3 "$K/tools/modcheck.py" -k "$K" "$W/$l-monsw/out/mod.d/monsw" > "$W/drv.out" 2>&1; then
			pass "$l: a character driver (MOD_DRV_WRAPPER, drv_cmajor 52 = majors=) passes"
		else fail "$l: the character driver"; cat "$W/drv.out"; fi
	mkbad $l z3660eth "$DRV"'char zinfo[16];\nstruct mod_drv_data z3660eth_drvdata[] = { { { 0 }, 0, 0, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, (struct streamtab *)zinfo, 0 }, 51, 1 } };\nMOD_DRV_WRAPPER(z3660eth, l, u, 0, "a STREAMS driver");\n' '$modtype drv\n$class demand\n$cpu 68020\n$majors c:51\nz3660eth\tz3660eth\n' &&
		if python3 "$K/tools/modcheck.py" -k "$K" "$W/$l-z3660eth/out/mod.d/z3660eth" > "$W/str.out" 2>&1; then
			pass "$l: a STREAMS driver (d_str only, drv_cmajor 51) passes"
		else fail "$l: the STREAMS driver"; cat "$W/str.out"; fi
	mkbad $l drvx "$DRV"'struct mod_drv_data drvx_drvdata[] = { { { 0 }, 0, 0, { o, o, o, o, o }, 52, 1 } };\nMOD_DRV_WRAPPER(drvx, l, u, 0, "x");\n' '$modtype drv\n$class demand\n$cpu 68020\ndrvx\tdrvx\n' &&
		refused "drv_cmajor not in majors=" $l "$W/$l-drvx/out/mod.d/drvx" "drv_cmajor 52"

	# format refusals, on edited copies of the sample
	edit "$H" "$W/$l-rtype/hello" <<'PY' && refused "a relocation type outside the list" $l "$W/$l-rtype/hello" "outside the list"
for i in range(shnum):
    if sh(i, 4) == 4:
        o = sh(i, 16); d[o + 7] = 7; break
PY
	edit "$H" "$W/$l-shtrel/hello" <<'PY' && refused "an SHT_REL section" $l "$W/$l-shtrel/hello" "SHT_REL"
for i in range(shnum):
    if sh(i, 4) == 4:
        struct.pack_into('>I', d, shoff + 40 * i + 4, 9); break
PY
	edit "$H" "$W/$l-v1/hello" <<'PY' && refused ".moddata without MD2 (version 1)" $l "$W/$l-v1/hello" "not version 2"
i = d.index(b'MD2\0'); d[i + 2] = ord('1')
PY
	edit "$H" "$W/$l-crit/hello" <<'PY' && refused "an unknown critical key" $l "$W/$l-crit/hello" "critical key"
i = d.index(b'desc='); d[i] = ord('!')
PY
	edit "$H" "$W/$l-nocpu/hello" <<'PY' && refused "a missing required key" $l "$W/$l-nocpu/hello" "required key cpu missing"
i = d.index(b'cpu='); d[i] = ord('x')
PY
	mkdir -p "$W/$l-hello"
	mkbad $l huge "$WRAP"'char huge_space[270000];\nMOD_MISC_WRAPPER(huge, l, u, "x");\n' "$M0"'huge\thuge\n' &&
		refused "an image over 256 KiB" $l "$W/$l-huge/out/mod.d/huge" "over 256 KiB"
	# a file of exactly 256 KiB: the core reads it whole into at most that (C3-1 section 6)
	edit "$H" "$W/$l-fat/hello" <<'PY' && refused "a file of 256 KiB" $l "$W/$l-fat/hello" "not under 256 KiB"
d += bytes(262144 - len(d))
PY
	# a demand-class module whose load needs over 160 KiB: warned, not refused (30 section 8)
	mkbad $l wide "$WRAP"'char wide_space[170000];\nMOD_MISC_WRAPPER(wide, l, u, "x");\n' "$M0"'wide\twide\n' &&
		if python3 "$K/tools/modcheck.py" -k "$K" "$W/$l-wide/out/mod.d/wide" > "$W/wide.out" 2>&1 &&
		   grep -q "warning: a demand-class load holds about" "$W/wide.out" &&
		   ! grep -q "demand-class load" "$W/hello-$l.log"; then
			pass "$l: a demand-class module over 160 KiB of load working set is warned about, not refused"
		else
			fail "$l: working-set warning"; cat "$W/wide.out"
		fi
	mkbad $l tierc "$WRAP"'MOD_MISC_WRAPPER(tierc, l, u, "x");\n' "$M0"'$tier core\ntierc\ttierc\n' &&
		refused "tier=core without build=" $l "$W/$l-tierc/out/mod.d/tierc" "needs build="
	# a dependency's globals count only when it is named (-d and depend=)
	mkbad $l dep1 "$WRAP"'int dep1_val;\nint dep1_get() { return dep1_val; }\nMOD_MISC_WRAPPER(dep1, l, u, "x");\n' "$M0"'dep1\tdep1\n' &&
	mkbad $l dep2 "$WRAP"'extern int dep1_get();\nint f() { return dep1_get(); }\nMOD_MISC_WRAPPER(dep2, l, u, "x");\n' "$M0"'$depend dep1\ndep2\tdep2\n' dep1_get &&
		if python3 "$K/tools/modcheck.py" -k "$K" -d "$W/$l-dep1/out/mod.d/dep1" "$W/$l-dep2/out/mod.d/dep2" > "$W/dep.out" 2>&1; then
			pass "$l: a dependency's global, with -d and depend=, passes"
		else fail "$l: the dependency"; cat "$W/dep.out"; fi &&
		refused "a dependency's global without -d" $l "$W/$l-dep2/out/mod.d/dep2" "dep1_get is not in the allowlist"

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
