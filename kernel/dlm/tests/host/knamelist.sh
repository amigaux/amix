#!/bin/sh
# knamelist.sh -- `kbootset namelist`, `mark-good` and `status` on the box's
# /stand/unix (40 §4.2, C2-4 §9, §12), on the host: the cut kernels
# committed into a store, a version-3 kinfo record giving the bind address
# (C2-1), the namelist written, found current, found stale, and refused
# for each reason C2-4 §12 names.  A /stand/unix that is a hard link to
# /stand/2.1_unix (as 1.0 left it) must leave that file as it was.
# The kernels are optional inputs (namelist.sh's NL_K46, NL_K30_*);
# without them the cases are skipped.
# Run from the repository root after `make tools` and store-roundtrip.sh.
set -e
B=${B:-build}
K46=${NL_K46:-}
K30E=${NL_K30_ETREL:-}
K30B=${NL_K30_BREL:-}
T=$B/knamelist
rm -rf "${T:?}" && mkdir -p $T
sha() { sha256sum "$1" | cut -c1-64; }
size() { wc -c < "$1" | tr -d ' '; }

# kinfo VERSION GEN LAYOUTFILE [FLAGS]: a kinfo record whose bootdata block
# is where nlmake laid the kernel out (its "text <vaddr> <size>" lines)
cat > $T/kinfo.py <<'EOF'
import os, struct, sys
ver, gen, lay = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
extra = int(sys.argv[5], 0) if len(sys.argv) > 5 else 0
medium = sys.argv[6] if len(sys.argv) > 6 else ''     # cd or floppy: AXL1 flag 0x08
l = {w[0]: (int(w[1], 16), int(w[2])) for w in (x.split() for x in open(lay))}
ml = 576 if ver == 3 else 536
mods = [m.split(':') for m in os.environ.get('KINFO_MODS', '').split()]   # name:base:size
r = bytearray(ml + 4 + 32 * len(mods))
struct.pack_into('>I', r, ml, len(mods))
for i, (mn, mb, ms) in enumerate(mods):
    o = ml + 4 + 32 * i
    r[o:o + len(mn)] = mn.encode()
    struct.pack_into('>II', r, o + 24, int(mb, 0), int(ms, 0))
struct.pack_into('>II', r, 0, 0x4b494631, (ver << 16) | len(r))
struct.pack_into('>III', r, 12, 60, 46, 0x000f)
r[24:31] = b'k46.1.0'; r[48:63] = b'68060-261026-56'
a = 84
struct.pack_into('>I', r, a, 0x41584c31)
struct.pack_into('>IIIIII', r, a + 12, 2, 0, 60, 0xf, gen, 2)
if medium:
    struct.pack_into('>II', r, a + 32, 3, 0x08)      # pristine, a read-only medium
    if medium == 'cd':
        struct.pack_into('>I', r, a + 44, 0xffffffff) # no boot node: started by AmigaDOS
s = sum(struct.unpack('>31I', r[a:a + 124])) & 0xffffffff
struct.pack_into('>I', r, a + 8, (-s) & 0xffffffff)
struct.pack_into('>I', r, 80, 1 | extra)
if ver == 3:
    t, ro, d = l['text'], l['rodata'], l['data']
    struct.pack_into('>10I', r, 536, t[0], t[0], 0, t[1], ro[0], 0, ro[1], d[0], 0, d[1])
s = sum(struct.unpack('>%dI' % (len(r) // 4), r)) & 0xffffffff
struct.pack_into('>I', r, 8, (-s) & 0xffffffff)
open(sys.argv[1], 'wb').write(r)
EOF
# nlq.py NAMELIST NAME...: the section count, then per name its value,
# binding and type, or for crash_sync the 4 bytes crash reads, or absent
cat > $T/nlq.py <<'PYEOF'
import struct, sys
n = open(sys.argv[1], 'rb').read()
u32 = lambda o: struct.unpack('>I', n[o:o + 4])[0]
u16 = lambda o: struct.unpack('>H', n[o:o + 2])[0]
sh, k = u32(32), u16(48)
hdr = [sh + 40 * i for i in range(k)]
print('sections %d' % k)
st = [h for h in hdr if u32(h + 4) == 2][0]
strs = u32(hdr[u32(st + 24)] + 16)
syms = {}
for o in range(u32(st + 16) + 16, u32(st + 16) + u32(st + 20), 16):
    nm = n[strs + u32(o):n.index(b'\0', strs + u32(o))].decode()
    syms[nm] = (u32(o + 4), n[o + 12], u16(o + 14))
for nm in sys.argv[2:]:
    if nm not in syms:
        print('%s absent' % nm)
    elif nm == 'crash_sync':
        v, info, x = syms[nm]
        h = hdr[x]
        t = {1: 'PROGBITS', 8: 'NOBITS'}.get(u32(h + 4), '?')
        off = u32(h + 16) + v - u32(h + 12)
        print('%s shndx %d %s word %s' % (nm, x, t, n[off:off + 4].hex() if t == 'PROGBITS' else '-'))
    else:
        v, info, x = syms[nm]
        print('%s value %08x %s %d' % (nm, v, 'global' if info >> 4 == 1 else 'local', info & 15))
PYEOF
# store LINE KERNEL [bss=N]: a fresh store, one generation of KERNEL
store() {
	head -c $((8 << 20)) /dev/zero > $T/store
	$B/kbootset --image $T/store create $((8 << 20)) $B/rt/boot2.bin > /dev/null
	printf 'line %s\nkabi %s.1.0\nloader-min 1\nrootfs ufs\nroot sd id=144b0100 base=00000000 unit=6 slice=1\nkernel unix %s%s\n' \
		"$1" "$1" "$2" "${3:+ $3}" > $T/spec
	$B/kbootset --image $T/store commit --spec $T/spec > /dev/null 2>&1
}
KB="$B/kbootset -R $T/root --image $T/store"
# no RC PATTERN command...: it exits RC, saying PATTERN
no() {
	want=$1 pat=$2; shift 2
	set +e; "$@" > $T/out 2>&1; got=$?; set -e
	[ $got = $want ] && grep -q "$pat" $T/out ||
		{ echo "knamelist: expected status $want and \"$pat\", got $got:" >&2; cat $T/out >&2; exit 1; }
}
export KBOOTSET_KINFO=$T/kinfo
# the running kernel's memory: crash_sync's word, 0xffffffff as pstart sets
# it, at its address for each bind (kmemword NAMELIST); kbootset and nlmake
# read the same file
export KBOOTSET_KMEM=$T/kmem NLMAKE_KMEM=$T/kmem
: > $T/kmem
kmemword() {
	python3 -I - "$1" $T/kmem <<'PY'
import struct, sys
n = open(sys.argv[1], 'rb').read()
u32 = lambda o: struct.unpack('>I', n[o:o + 4])[0]
u16 = lambda o: struct.unpack('>H', n[o:o + 2])[0]
sh, k = u32(32), u16(48)
hdr = [n[sh + 40 * i:sh + 40 * i + 40] for i in range(k)]
st = [h for h in hdr if struct.unpack('>I', h[4:8])[0] == 2][0]
so, ss, sl = struct.unpack('>I', st[16:20])[0], struct.unpack('>I', st[20:24])[0], struct.unpack('>I', st[24:28])[0]
strs = struct.unpack('>I', hdr[sl][16:20])[0]
for o in range(so + 16, so + ss, 16):
    nm = n[strs + u32(o):n.index(b'\0', strs + u32(o))]
    if nm == b'crash_sync':
        f = open(sys.argv[2], 'r+b'); f.seek(u32(o + 4)); f.write(b'\xff' * 4); f.close()
PY
}
# nlmade [-s] IN BIND OUT: nlmake's namelist, crash_sync's word put in first
nlmade() {
	NLMAKE_KMEM= $B/nlmake "$@" > /dev/null && eval "kmemword \"\${$#}\"" && $B/nlmake "$@"
}

if [ -f "$K46" ]; then
	R=$T/root
	mkdir -p $R/stand/k46
	store k46 "$K46"
	nlmade "$K46" 0x08000000 $T/n46 > $T/lay46
	# /stand/unix as 1.0 left it: a hard link to the stock kernel
	echo "the stock kernel" > $R/stand/2.1_unix
	ln $R/stand/2.1_unix $R/stand/unix
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46
	$KB status > $T/out
	grep -q "^namelist: /stand/unix is not the booted kernel's: run kbootset namelist$" $T/out
	(umask 0; $KB namelist) > $T/out			# rc2's umask on the box
	grep -q "^kbootset: namelist /stand/unix written for generation 1, bound at 0x08000000$" $T/out
	cmp -s $R/stand/unix $T/n46				# what nlmake makes at that bind
	[ "$(stat -c %a $R/stand/unix)" = 644 ]			# never 0666
	[ "$(cat $R/stand/2.1_unix)" = "the stock kernel" ]	# the link's file is untouched
	[ "$(stat -c %h $R/stand/2.1_unix)" = 1 ]
	[ ! -e $R/stand/unix.new ]
	$KB namelist | grep -q "^kbootset: namelist for generation 1 is current$"
	$KB status | grep -q "^namelist: /stand/unix is generation 1's, bound at 0x08000000$"
	# mark-good writes it on every boot (here generation 1 is not a trial)
	rm "${R:?}"/stand/unix
	$KB status | grep -q "^namelist: /stand/unix is missing: run kbootset namelist$"
	$KB mark-good > $T/out
	grep -q "^kbootset: namelist /stand/unix written for generation 1" $T/out
	$KB mark-good > $T/out
	! grep -q namelist $T/out				# current: mark-good says nothing of it
	# refusals, each with its reason; /stand/unix stays as it is
	cp $R/stand/unix $T/keep
	python3 -I $T/kinfo.py $T/kinfo 2 1 $T/lay46
	no 3 "no namelist: kinfo version 2 gives no bind address" $KB namelist
	$KB status | grep -q "^namelist: none (kinfo version 2 gives no bind address)$"
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46 8
	no 3 "kinfo flags a loader fault (0x8)" $KB namelist
	awk '$1 == "data" { $2 = sprintf("0x%08x", strtonum($2) + 4) } { print }' $T/lay46 > $T/laybad
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/laybad
	no 3 "the layout does not match kinfo" $KB namelist
	python3 -I $T/kinfo.py $T/kinfo 3 7 $T/lay46
	no 3 "generation 7's kernel cannot be read from the store" $KB namelist
	cmp -s $R/stand/unix $T/keep
	# another bind: a new namelist
	nlmade "$K46" 0x07f00000 $T/n46b > $T/lay46b
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46b
	$KB status | grep -q "^namelist: /stand/unix is not the booted kernel's: run kbootset namelist$"
	$KB namelist | grep -q "bound at 0x07f00000$" && cmp -s $R/stand/unix $T/n46b
	echo "knamelist: k46 (written over a link to 2.1_unix, current, stale, missing, mark-good, refusals) ok"
	# a CD boot (C2-4 section 13): the store did not boot; the namelist comes
	# from the installed kernel when its build id is kinfo's
	cp "$K46" $R/stand/k46/unix
	echo "build=68060-261026-56" > $R/stand/k46/kabi
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46 0 cd
	rm -f "${R:?}"/stand/unix
	$KB status > $T/out
	grep -q "^booted: generation 1 of a read-only medium (a CD), not of this box's store; kernel 68060-261026-56" $T/out
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for the medium's kernel (68060-261026-56), bound at 0x08000000$"
	cmp -s $R/stand/unix $T/n46
	$KB status | grep -q "^namelist: /stand/unix is the medium's kernel's (68060-261026-56), bound at 0x08000000$"
	$B/lsstore $T/store 0 > $T/before
	$KB mark-good > $T/out
	grep -q "^kbootset: booted from a read-only medium (generation 1 of a CD): nothing to mark$" $T/out
	! grep -q "namelist" $T/out				# current
	$B/lsstore $T/store 0 | cmp -s - $T/before		# the store is untouched
	[ -z "$($KB retry)" ]
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46 0 floppy
	$KB mark-good | grep -q "(generation 1 of a floppy pair): nothing to mark"
	echo "build=68060-261026-57" > $R/stand/k46/kabi
	no 3 "booted from a read-only medium whose kernel (68060-261026-56) is not the one installed here (68060-261026-57)" $KB namelist
	echo "knamelist: k46 booted from a read-only medium (status, namelist from the installed kernel, no mark-good, no retry) ok"

	# crash_sync (C2-4 section 12): stock crash reads 4 bytes at the
	# symbol's own section's sh_offset + (st_value - sh_addr): a PROGBITS
	# section of its own holding the running kernel's word
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46
	rm -f "${R:?}"/stand/unix
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for generation 1, bound at 0x08000000$"
	python3 -I $T/nlq.py $R/stand/unix crash_sync > $T/q
	grep -q "^sections 9$" $T/q
	grep -q "^crash_sync shndx 8 PROGBITS word ffffffff$" $T/q	# what crash reads
	# no word to be had (no /dev/kmem): crash_sync left out, so crash only
	# warns that it checks no timestamps
	KBOOTSET_KMEM=$T/nokmem $KB namelist | grep -q "written for generation 1"
	python3 -I $T/nlq.py $R/stand/unix crash_sync > $T/q
	grep -q "^sections 8$" $T/q && grep -q "^crash_sync absent$" $T/q
	echo "knamelist: k46 crash_sync (its own PROGBITS word, read as crash reads it; left out without kmem) ok"

	# the loaded modules' globals, at the addresses getksym gives, kept only
	# inside the module's run: in while kinfo lists it, out once unloaded
	mkdir -p $R/stand/gen/1/mod
	python3 tests/host/mkmodobj.py $R/stand/gen/1/mod/modx name=modx class=boot D:modx_ops D:modx_hook D:modx_far
	head -c $((8 << 20)) /dev/zero > $T/store
	$B/kbootset --image $T/store create $((8 << 20)) $B/rt/boot2.bin > /dev/null
	printf 'line k46\nkabi k46.1.0\nloader-min 1\nrootfs ufs\nroot sd id=144b0100 base=00000000 unit=6 slice=1\nkernel unix %s\nmodule modx boot %s path=/stand/gen/1/mod/modx\n' \
		"$K46" "$(size $R/stand/gen/1/mod/modx)" > $T/spec
	$B/kbootset --image $T/store commit --spec $T/spec > /dev/null 2>&1
	printf 'modx_ops 40500010 1\nmodx_hook 40500200 2\nmodx_far 40900000 1\n' > $T/ksyms
	export KBOOTSET_KSYMS=$T/ksyms
	KINFO_MODS="modx:0x40500000:0x1000" python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for generation 1"
	python3 -I $T/nlq.py $R/stand/unix modx_ops modx_hook modx_far crash_sync > $T/q
	grep -q "^modx_ops value 40500010 global 1$" $T/q
	grep -q "^modx_hook value 40500200 global 2$" $T/q
	grep -q "^modx_far absent$" $T/q				# outside its run: another's answer
	grep -q "^crash_sync shndx 8 PROGBITS word ffffffff$" $T/q
	$KB namelist | grep -q "^kbootset: namelist for generation 1 is current$"
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46		# unloaded: kinfo lists no module
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for generation 1"
	python3 -I $T/nlq.py $R/stand/unix modx_ops modx_hook > $T/q
	grep -q "^modx_ops absent$" $T/q && grep -q "^modx_hook absent$" $T/q
	cmp -s $R/stand/unix $T/n46				# the kernel's own again
	KINFO_MODS="modx:0x40500000:0x1000" python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46
	# a module loaded since: the file is still the booted kernel's
	$KB status | grep -q "^namelist: /stand/unix is the booted kernel's, bound at 0x08000000; kbootset namelist adds the modules loaded since$"
	$KB namelist | grep -q "written for generation 1"	# loaded again
	python3 -I $T/nlq.py $R/stand/unix modx_ops > $T/q
	grep -q "^modx_ops value 40500010 global 1$" $T/q
	unset KBOOTSET_KSYMS
	echo "knamelist: k46 module symbols (in while loaded, kept to the module's run, out once unloaded, rewritten) ok"

	# a generation gone from the store leaves the root too, except the one
	# running, whose demand modules still load from there, and a build not
	# yet committed (C2-4 section 19)
	gendir() {
		mkdir -p $R/stand/gen/$1/mod
		for f in build facts unix.sym mod/x; do echo x > $R/stand/gen/$1/$f; done
	}
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46
	$KB commit --spec $T/spec > /dev/null 2>&1		# generation 2, the trial
	gendir 2; gendir 3
	python3 -I $T/kinfo.py $T/kinfo 3 2 $T/lay46		# it runs
	$KB commit --spec $T/spec > /dev/null 2>&1		# 3 replaces it in the store
	[ -f $R/stand/gen/2/mod/x ]				# running: stays
	gendir 4						# the next id: a build
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46 0 cd	# a medium: no running generation of this store
	$KB collect > /dev/null
	[ -f $R/stand/gen/2/mod/x ]
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay46
	$KB status > /dev/null					# a reader does not
	$KB next none > /dev/null				# nor what collects nothing
	[ -f $R/stand/gen/2/mod/x ]
	$KB collect > /dev/null
	[ ! -e $R/stand/gen/2 ]
	[ -f $R/stand/gen/1/mod/modx ] && [ -f $R/stand/gen/3/mod/x ] && [ -f $R/stand/gen/4/mod/x ]
	gendir 2
	$KB mark-good > /dev/null				# each boot finishes what a cut left
	[ ! -e $R/stand/gen/2 ]
	[ -f $R/stand/gen/1/mod/modx ] && [ -f $R/stand/gen/3/mod/x ] && [ -f $R/stand/gen/4/mod/x ]
	echo "knamelist: k46 collected generations' directories (removed; the running one, the store's and a build stay) ok"
	rm -rf "${R:?}"
else
	echo "knamelist: no k46 kernel, skipped"
fi

if [ -f "$K30E" ] && [ -f "$K30B" ]; then
	R=$T/root
	mkdir -p $R/stand/k30
	cp "$K30B" $R/stand/k30/unix
	store k30 $R/stand/k30/unix bss=349324
	NLMAKE_KMEM= $B/nlmake "$K30E" 0 $R/stand/k30/unix.sym > /dev/null	# bind 0: a unix.sym (C2-3 §2.1)
	nlmade -s $R/stand/k30/unix.sym 0x00200000 $T/n30 > $T/lay30
	python3 -I $T/kinfo.py $T/kinfo 3 1 $T/lay30
	sidecar() {
		printf 'kabi=k30.1.0\nline=k30\nsize=%s\nsha256=%s\nbss=349324\n' \
			"$(size $R/stand/k30/unix)" "${1:-$(sha $R/stand/k30/unix)}" > $R/stand/k30/kabi
		[ -z "$2" ] || echo "$2" >> $R/stand/k30/kabi
	}
	SYM="sym=unix.sym $(size $R/stand/k30/unix.sym) $(sha $R/stand/k30/unix.sym)"
	sidecar "" ""
	no 3 "the kernel has no symbols (no unix.sym)" $KB namelist
	sidecar 0000000000000000000000000000000000000000000000000000000000000000 "$SYM"
	no 3 "generation 1's kernel is not the installed one" $KB namelist
	sidecar "" "sym=unix.sym $(size $R/stand/k30/unix.sym) 0000000000000000000000000000000000000000000000000000000000000000"
	no 3 "unix.sym differs from its sidecar's sym=" $KB namelist
	sidecar "" "$SYM"
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for generation 1, bound at 0x00200000$"
	cmp -s $R/stand/unix $T/n30
	echo "knamelist: k30 brel through unix.sym (written; no sym=, another kernel, a changed unix.sym refused) ok"
	# the generation keeps its symbols: a rollback's boot of it, once the
	# package has replaced the kernel and unix.sym, still has a namelist
	cmp -s $R/stand/gen/1/unix.sym $R/stand/k30/unix.sym
	[ "$(stat -c %a $R/stand/gen/1/unix.sym)" = 644 ]
	[ ! -e $R/stand/gen/1/unix.sym.new ]
	cp $R/stand/k30/unix.sym $T/sym1
	{ cat "$K30B"; printf x; } > $R/stand/k30/unix
	printf other > $R/stand/k30/unix.sym
	sidecar "" "sym=unix.sym $(size $R/stand/k30/unix.sym) $(sha $R/stand/k30/unix.sym)"
	$KB namelist | grep -q "^kbootset: namelist for generation 1 is current$"
	$KB status | grep -q "^namelist: /stand/unix is generation 1's, bound at 0x00200000$"
	rm "${R:?}"/stand/unix
	$KB status | grep -q "^namelist: /stand/unix is missing: run kbootset namelist$"
	$KB namelist | grep -q "^kbootset: namelist /stand/unix written for generation 1, bound at 0x00200000$"
	cmp -s $R/stand/unix $T/n30
	cmp -s $R/stand/gen/1/unix.sym $T/sym1			# not replaced by the new package's
	# none kept (it last booted under an older kbootset): what the boot wrote
	# still stands while it matches kinfo; without it the reason is said
	rm "${R:?}"/stand/gen/1/unix.sym
	$KB namelist | grep -q "^kbootset: namelist for generation 1 is current$"
	$KB status | grep -q "^namelist: /stand/unix is generation 1's, bound at 0x00200000$"
	[ ! -e $R/stand/gen/1/unix.sym ]			# the package's is another kernel's
	rm "${R:?}"/stand/unix
	no 3 "generation 1's kernel is not the installed one" $KB namelist
	$KB status | grep -q "^namelist: none (generation 1's kernel is not the installed one"
	# the kernel installed again: kept again
	cp "$K30B" $R/stand/k30/unix
	cp $T/sym1 $R/stand/k30/unix.sym
	sidecar "" "$SYM"
	$KB namelist | grep -q "written for generation 1"
	cmp -s $R/stand/gen/1/unix.sym $T/sym1
	echo "knamelist: k30 a generation's own unix.sym (kept at its boot, used after the package changed) ok"
else
	echo "knamelist: no k30 kernels, skipped"
fi
