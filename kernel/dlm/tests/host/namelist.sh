#!/bin/sh
# namelist.sh -- the namelist kbootset writes for /stand/unix (40 §4.2,
# kbootset/knl.c) against the kernels' own symbol blocks: every name of
# dlm_ksym, as the loader's relocator leaves the block at a bind address,
# must have that address in the namelist made for the same bind.
#   k46: the ET_REL module kernel, laid out by the relocator; and through
#        a unix.sym made from it at bind 0 (C2-3 §2.1): the same symbols.
#   k30: a unix.sym made from the .etrel at bind 0, against the block of
#        the brel as shipped (the converter's layout), bound by the loader.
# Optional inputs (not in this repository; skipped when absent):
#   NL_K46        the k46 module kernel (ET_REL)
#   NL_K30_ETREL  the k30 module kernel before elf2brel, NL_K30_BREL the
#                 brel, NL_K30_KABI its sidecar (for ksym=)
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
B=${B:-build}
K46=${NL_K46:-}
K30E=${NL_K30_ETREL:-}
K30B=${NL_K30_BREL:-}
K30S=${NL_K30_KABI:-}
T=$B/namelist
rm -rf "$T" && mkdir -p "$T"

# nlcmp NAMELIST BLOCK: the block's names at the namelist's addresses
nlcmp() {
	python3 -I - "$1" "$2" <<'PY'
import struct, sys
u32 = lambda b, o: struct.unpack('>I', b[o:o + 4])[0]
n = open(sys.argv[1], 'rb').read()
shoff, shnum = u32(n, 32), struct.unpack('>H', n[48:50])[0]
sh = [struct.unpack('>10I', n[shoff + 40 * i:shoff + 40 * i + 40]) for i in range(shnum)]
nl = {}
for s in sh:
    if s[1] == 2:
        st = sh[s[6]][4]
        for k in range(1, s[5] // 16):
            o = s[4] + 16 * k
            nm = n[st + u32(n, o):n.index(b'\0', st + u32(n, o))].decode()
            if n[o + 12] >> 4:      # the global: a static of the same name is another symbol
                nl.setdefault(nm, u32(n, o + 4))
b = open(sys.argv[2], 'rb').read()
nsym, so, stro = u32(b, 8), u32(b, 12), u32(b, 16)
lo, hi = u32(b, 28), u32(b, 32)
bad = []
for i in range(1, nsym):
    e = so + 16 * i
    nm = b[stro + u32(b, e):b.index(b'\0', stro + u32(b, e))].decode()
    if nl.get(nm) != u32(b, e + 4):
        bad.append('%s: block 0x%08x, namelist %s' % (nm, u32(b, e + 4), hex(nl[nm]) if nm in nl else 'none'))
if nl.get('stext') != lo:
    bad.append('stext is not the block\'s kh_lo')
if nl.get('end') != hi:
    bad.append('end is not the block\'s kh_hi')
if bad:
    print('\n'.join(bad))
    sys.exit(1)
print('%d names and stext, end' % (nsym - 1))
PY
}
# syms NAMELIST: its symbol table as text, to compare two namelists
syms() {
	python3 -I - "$1" <<'PY'
import struct, sys
u32 = lambda b, o: struct.unpack('>I', b[o:o + 4])[0]
n = open(sys.argv[1], 'rb').read()
shoff, shnum = u32(n, 32), struct.unpack('>H', n[48:50])[0]
sh = [struct.unpack('>10I', n[shoff + 40 * i:shoff + 40 * i + 40]) for i in range(shnum)]
for s in sh:
    if s[1] == 2:
        st = sh[s[6]][4]
        for k in range(1, s[5] // 16):
            o = s[4] + 16 * k
            print(n[st + u32(n, o):n.index(b'\0', st + u32(n, o))].decode(), hex(u32(n, o + 4)),
                  u32(n, o + 8), n[o + 12])
PY
}

if [ -f "$K46" ]; then
	for bind in 0x08000000 0x07f00000; do
		$B/nlmake "$K46" $bind $T/k46-$bind > $T/k46-$bind.lay
		python3 -I tools/ksymgate.py --extract $B/axrel "$K46" $bind $T/k46-$bind.blk > /dev/null
		r=$(nlcmp $T/k46-$bind $T/k46-$bind.blk) ||
			{ echo "namelist: k46 at $bind: $r" >&2; exit 1; }
	done
	echo "namelist: k46 ET_REL at 0x08000000 and 0x07f00000: $r"
	$B/nlmake "$K46" 0 $T/k46.sym > /dev/null
	$B/nlmake -s $T/k46.sym 0x08000000 $T/k46-viasym > /dev/null
	syms $T/k46-0x08000000 > $T/a; syms $T/k46-viasym > $T/b
	cmp -s $T/a $T/b || { echo "namelist: k46 through unix.sym differs" >&2; diff $T/a $T/b | head >&2; exit 1; }
	echo "namelist: k46 through a unix.sym made at bind 0: the same $(wc -l < $T/a) symbols"
	# a layout mismatch is the caller's to refuse: here, the layout given
	grep -q "^text 0x08000000 " $T/k46-0x08000000.lay
else
	echo "namelist: no k46 kernel (NL_K46=$K46), skipped"
fi

if [ -f "$K30E" ] && [ -f "$K30B" ] && [ -f "$K30S" ]; then
	$B/nlmake "$K30E" 0 $T/k30.sym > /dev/null
	ksym=$(sed -n 's/^ksym=//p' "$K30S")
	for bind in 0x00200000 0x07f00000; do
		$B/nlmake -s $T/k30.sym $bind $T/k30-$bind > $T/k30-$bind.lay
		$B/axrel "$K30B" $bind $T/k30-$bind.img > /dev/null
		python3 -I -c "
import sys
o, n = (int(x, 16) for x in sys.argv[2].split())
open(sys.argv[3], 'wb').write(open(sys.argv[1], 'rb').read()[o:o + n])" $T/k30-$bind.img "$ksym" $T/k30-$bind.blk
		r=$(nlcmp $T/k30-$bind $T/k30-$bind.blk) ||
			{ echo "namelist: k30 at $bind: $r" >&2; exit 1; }
	done
	echo "namelist: k30 unix.sym (from the .etrel at 0) against the shipped brel's block at 0x00200000 and 0x07f00000: $r"
else
	echo "namelist: no k30 kernels, skipped"
fi

# refusals: status 3, the reason said
no() {
	pat=$1; shift
	set +e; "$@" > $T/out 2>&1; got=$?; set -e
	[ $got = 3 ] && grep -q "$pat" $T/out ||
		{ echo "namelist: expected a refusal \"$pat\", got $got:" >&2; cat $T/out >&2; exit 1; }
}
printf 'not an elf' > $T/junk
no "the kernel has no symbols" $B/nlmake $T/junk 0x08000000 $T/x
no "unix.sym is not" $B/nlmake -s $T/junk 0x08000000 $T/x
[ ! -f "$K30B" ] || no "the kernel has no symbols" $B/nlmake "$K30B" 0x00200000 $T/x
echo "namelist: refusals (not ELF, a brel without unix.sym) ok"
