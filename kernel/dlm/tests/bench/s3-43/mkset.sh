#!/bin/sh
# mkset.sh -- S3-43's module set, built with the ABI kit of one line
# (docs/plan/stage-3.md S3-43; tests/bench/README.md, S3-43):
#   members, through the kit's make fragment and composed into the test
#   generation by kbootset (stand-in packages, s3-modpkg.sh):
#     monsw, z3660rtg  stand-ins on majors 52 and 49 (depend=monsw; monsw
#                      pinned, z3660rtg unload=allowed, as C3-6)
#     t43boot          boot class, unload=allowed, two parameters
#     t43leak          its _unload forgets its interrupt handler
#     t43fail          its _load attaches a handler and fails (EIO)
#     t43rel           the relocation oracle's module
#   off the generation, for /tmp/s43 on the box:
#     t43ext           a good module in no generation
#     kfam kmaj kmin kpin           built for another family, kabi major,
#                                   a minor above the kernel's, another pin
#     bshtrel brtype bzkey blong bv1 bsym
#                                   an SHT_REL section, a relocation type
#                                   outside the list, a zero match key, a
#                                   .moddata name over 14, version 1, a
#                                   kernel name outside the allowlist
# Each rule-breaker breaks one rule: verdicts.txt holds the kit checker's
# refusal for each, and the host loader's (the module core's dlm_ld, as
# `make core` builds it) errno where it refuses at load.
#
# usage: [KERNEL=<the line's ET_REL kernel>] mkset.sh KIT OUTDIR
#   KIT      a built kit (build/kit/<line>, `make kit`)
#   OUTDIR   gets tree/ (copy onto the box's root), s43/ (copy to /tmp/s43)
#            and verdicts.txt
# Needs the cross tools on PATH (m68k-cbm-sysv4-*); for the load-time
# verdicts, KERNEL, the staged core from `make core` and build/axrel.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
R=$(cd "$(dirname "$0")/../../.." && pwd)
S=$R/tests/bench/s3-43/src
K=$(cd "$1" && pwd) OUT=$2
[ -n "$OUT" ] && [ -f "$K/kit.conf" ] || { echo "usage: mkset.sh KIT OUTDIR" >&2; exit 2; }
. "$K/kit.conf"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
W=$OUT/work
rm -rf "$W" "$OUT/tree" "$OUT/s43" "$OUT/verdicts.txt"
mkdir -p "$W" "$OUT/tree" "$OUT/s43"
V=$OUT/verdicts.txt

# member NAME [DEPS]: through the kit's make fragment
member() {
	n=$1 d=$W/$1
	mkdir -p "$d"
	cp "$S/$n.c" "$d/"
	cp "$S/$n.Master" "$d/Master"
	{
		echo "KIT = $K"
		echo "MODULE = $n"
		echo "OBJS = $n.o"
		[ -z "$2" ] || echo "DEPS = $2"
		echo 'include $(KIT)/mk/module.mk'
	} > "$d/Makefile"
	(cd "$d" && make > make.log 2>&1) || { echo "mkset: $n:" >&2; cat "$d/make.log" >&2; exit 1; }
	echo "$n: built with the kit: $(grep '^modcheck' "$d/make.log" | tail -1)" >> "$V"
}
member monsw
member z3660rtg "$W/monsw/build/$LINE/mod.d/monsw"
for n in t43boot t43leak t43fail t43rel t43ext; do
	member $n
done
for n in monsw z3660rtg t43leak t43fail t43rel; do
	sh "$R/tests/bench/s3-modpkg.sh" "$W/$n/build/$LINE/mod.d/$n" $LINE "$OUT/tree" > /dev/null
done
sh "$R/tests/bench/s3-modpkg.sh" "$W/t43boot/build/$LINE/mod.d/t43boot" $LINE "$OUT/tree" \
	"param tag=s3-43" > /dev/null
cp "$W/t43ext/build/$LINE/mod.d/t43ext" "$OUT/s43/"

# bad NAME SOURCE MASTER [EXPORT]: through mkmod alone (modfix lets EXPORT
# through), with KABI_OVERRIDE / PIN_OVERRIDE for the kabi breakers
CF="-O -traditional -fno-builtin -Dinline=__inline__ -Dvolatile=__volatile__ -Dconst=__const__ $CPUFLAG -D_KERNEL -DSVR40 -DSVR4 -I$K/include -I$K/stock/usr/include -I$K/stock/usr/sys -I$K/stock/usr/sys/amiga/inc"
bad() {
	n=$1 d=$W/bad-$1
	mkdir -p "$d/src"
	printf '%b' "$2" > "$d/$n.c"
	printf '%b' "$3" > "$d/src/Master"
	AMIX_SYSROOT=$K/sysroot m68k-cbm-sysv4-gcc $CF -c "$d/$n.c" -o "$d/src/Driver.o"
	{ cat "$K/exports"; [ -z "$4" ] || echo "$4"; } > "$d/exports"
	MKMOD_CC="m68k-cbm-sysv4-gcc $CF" DLM_TOOLS=$K/tools sh "$K/tools/mkmod" -K "${KABI_OVERRIDE:-$KABI}" \
		-P "${PIN_OVERRIDE:-$PIN}" -e "$d/exports" -o "$d/out" "$d/src" > "$d/mkmod.log" 2>&1 ||
		{ echo "mkset: mkmod $n:" >&2; cat "$d/mkmod.log" >&2; exit 1; }
	cp "$d/out/mod.d/$n" "$OUT/s43/${5:-$n}"
}
# edit NAME: s43/NAME with python's edit (stdin) applied to its bytes `d`
edit() {
	python3 -I -c "
import struct, sys
d = bytearray(open(sys.argv[1], 'rb').read())
u16 = lambda o: struct.unpack('>H', d[o:o+2])[0]
u32 = lambda o: struct.unpack('>I', d[o:o+4])[0]
shoff, shnum = u32(32), u16(48)
sh = lambda i, f: u32(shoff + 40 * i + f)
$(cat)
open(sys.argv[1], 'wb').write(d)" "$OUT/s43/$1"
}
WRAP='#include "sys/types.h"\n#include "sys/moddefs.h"\nextern int printf();\nstatic int l() { printf("%%s loaded\\n", "NAME"); return 0; }\nstatic int u() { return 0; }\n'
M0='$modtype misc\n$class demand\n$cpu '"$DEFCPU"'\n$unload allowed\n'
w() { printf '%s' "$WRAP" | sed "s/NAME/$1/"; printf 'MOD_MISC_WRAPPER(%s, l, u, "S3-43 %s");\n' "$1" "$2"; }

other=$([ $LINE = k30 ] && echo k46 || echo k30)
KABI_OVERRIDE=$other.1.0 bad kfam "$(w kfam 'another family')" "$M0"'kfam\tkfam\n'
KABI_OVERRIDE=$LINE.2.0 bad kmaj "$(w kmaj 'another kabi major')" "$M0"'kmaj\tkmaj\n'
KABI_OVERRIDE=$LINE.1.1 bad kmin "$(w kmin 'a minor above the kernel')" "$M0"'kmin\tkmin\n'
PIN_OVERRIDE=gcc-2.95.3-0000000 bad kpin "$(w kpin 'another compiler pin')" "$M0"'kpin\tkpin\n'
bad bshtrel "$(w bshtrel 'an SHT_REL section')" "$M0"'bshtrel\tbshtrel\n'
edit bshtrel <<'PY'
for i in range(shnum):
    if sh(i, 4) == 4:
        struct.pack_into('>I', d, shoff + 40 * i + 4, 9); break
PY
bad brtype "$(w brtype 'a relocation type outside the list')" "$M0"'brtype\tbrtype\n'
edit brtype <<'PY'
for i in range(shnum):
    if sh(i, 4) == 4:
        o = sh(i, 16); d[o + 7] = 7; break
PY
bad bzkey "$(w bzkey 'a zero match key')" "$M0"'$match zorro:0000:01\nbzkey\tbzkey\n'
bad bv1 "$(w bv1 '.moddata version 1')" "$M0"'bv1\tbv1\n'
edit bv1 <<'PY'
i = d.index(b'MD2\0'); d[i + 2] = ord('1')
PY
bad bsym "$(printf '#include "sys/types.h"\n#include "sys/moddefs.h"\nextern int cdevsw[];\nstatic int l() { return cdevsw[0]; }\nstatic int u() { return 0; }\nMOD_MISC_WRAPPER(bsym, l, u, "S3-43 an off-list kernel name");\n')" \
	"$M0"'bsym\tbsym\n' cdevsw
# a .moddata name over 14 (modfix stops one at 14): built as the 14-character
# blongname12345, saved as blong, its name= lengthened by one character and
# its desc= shortened by one, so the section keeps its size
bad blongname12345 "$(w blongname12345 'a name over 14')" "$M0"'$desc S3-43 a name over 14\nblongname12345\tblongname12345\n' '' blong
edit blong <<'PY'
for k in range(shnum):
    if sh(k, 4) == 13:
        o, n = sh(k, 16), sh(k, 20)
sec = bytes(d[o:o + n])
new = sec.replace(b'name=blongname12345\0', b'name=blongname123456\0')
i = new.index(b'desc=')
e = new.index(b'\0', i)
new = new[:e - 1] + new[e:]
assert len(new) == n
d[o:o + n] = new
PY

# the verdicts: the kit's checker on each, then the host loader
refusal() {	# refusal NAME: the checker's line for s43/NAME
	if python3 -I "$K/tools/modcheck.py" -k "$K" "$OUT/s43/$1" > "$W/$1.chk" 2>&1; then
		echo "$1: modcheck accepts it" >> "$V"
	else
		echo "$1: modcheck: $(grep -m1 -v '^warning' "$W/$1.chk" | sed 's/^modcheck: [^:]*: //')" >> "$V"
	fi
}
for n in t43ext kfam kmaj kmin kpin bshtrel brtype bzkey blong bv1 bsym; do
	refusal $n
done
# the host loader, built from the staged core (`make core`) with each
# dlm_ld step named when it refuses, against the cut kernel's own symbol
# block (KERNEL, an ET_REL: the k46 kernel or the k30 .etrel) bound at
# 0x08000000: the step decides the console line (dlm_core.c, C3-1 section 4)
D=$R/build/core/stage/kernel/dlm
if [ -n "$KERNEL" ] && [ -f "$D/test/reloc.c" ] && [ -x "$R/build/axrel" ]; then
	python3 -I - "$D/test/reloc.c" "$W/lstep.c" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r'\(e = (dlm_ld_(hdr|moddata|syms|image|reloc))\(ld\)\)', r'(e = step("\2", \1(ld)))', s)
s = s.replace('#include "dlm.h"', '#include "dlm.h"\nstatic int step(n, e) char *n; int e; { if (e) printf("STEP %s ", n); return e; }', 1)
open(sys.argv[2], 'w').write(s)
PY
	cc -std=gnu89 -w -DDLM_HOST -I"$D" -I"$D/include" -o "$W/lstep" "$W/lstep.c" "$D/dlm_ld.c" "$D/dlm_sym.c"
	python3 -I "$R/tools/ksymgate.py" --extract "$R/build/axrel" "$KERNEL" 0x08000000 "$W/ksym.bin" > /dev/null
	for n in t43ext bshtrel brtype bzkey blong bv1 bsym; do
		echo "$n: host loader: $("$W/lstep" -k "$W/ksym.bin" -b 0x08400000 "$OUT/s43/$n" 2>&1 | tail -1)" >> "$V"
	done
fi
( cd "$OUT/tree" && find . -type f | sort ) > "$W/tree.list"
echo "mkset: $OUT: $(wc -l < "$W/tree.list") files in tree/, $(ls "$OUT/s43" | wc -l) in s43/, kit $KIT_REV ($LINE)"
