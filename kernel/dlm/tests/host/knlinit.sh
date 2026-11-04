#!/bin/sh
# knlinit.sh -- `kbootset namelist` and `status` when a brel kernel's namelist
# cannot be made (the k30 line: no kabi, no sym=, another kernel installed, no
# unix.sym, a changed unix.sym; C2-4 section 12), with no state left
# uninitialised.  kbootset is built here with every automatic variable filled
# with a pattern and with AddressSanitizer, so a path that frees or walks what
# it never set dies instead of passing by luck.  The kernel is a stand-in: the
# paths stop before its symbols are read.  Skipped when the compiler has no
# such options.  Run from the repository root after store-roundtrip.sh.
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
B=${B:-build}
T=$B/knlinit
rm -rf "${T:?}" && mkdir -p $T/root/stand/k30
CC=${HOSTCC:-cc}
SRC="kbootset/kbootset.c kbootset/ks.c kbootset/kbuild.c kbootset/kbox.c kbootset/kmod.c kbootset/kreg.c
     kbootset/knl.c kbootset/kdeflate.c kbootset/knode.c loader/common/crc32.c loader/common/store.c
     loader/common/manifest.c loader/common/inflate.c loader/common/select.c loader/common/rel.c
     loader/common/bootinfo.c loader/common/sha256.c"
if ! $CC -std=c89 -O1 -g -ftrivial-auto-var-init=pattern -fsanitize=address -Iloader/common -Ikbootset \
	-o $T/kbootset $SRC 2> $T/cc.log; then
	echo "knlinit: $CC has no -ftrivial-auto-var-init or -fsanitize=address, skipped"
	exit 0
fi
export ASAN_OPTIONS=detect_leaks=0
R=$T/root
KB="$T/kbootset -R $R --image $T/store"

# a stand-in brel: an ELF header whose type is 0xff00
python3 -I - $T/unix <<'EOF'
import sys
h = bytearray(4096)
h[:6] = b'\x7fELF\x01\x02'
h[16:18] = b'\xff\x00'
open(sys.argv[1], 'wb').write(h)
EOF
head -c $((8 << 20)) /dev/zero > $T/store
$B/kbootset --image $T/store create $((8 << 20)) $B/rt/boot2.bin > /dev/null
printf 'line k30\nkabi k30.1.0\nloader-min 1\nrootfs ufs\nroot sd id=144b0100 base=00000000 unit=6 slice=1\nkernel unix %s bss=4096\n' \
	$T/unix > $T/spec
$B/kbootset --image $T/store commit --spec $T/spec > /dev/null 2>&1
# a version-3 kinfo record: generation 1, booted by our loader
python3 -I - $T/kinfo <<'EOF'
import struct, sys
ml = 576
r = bytearray(ml + 4)
struct.pack_into('>II', r, 0, 0x4b494631, (3 << 16) | len(r))
struct.pack_into('>III', r, 12, 30, 30, 0x0004)
r[24:31] = b'k30.1.0'; r[48:63] = b'68030-261104-01'
a = 84
struct.pack_into('>I', r, a, 0x41584c31)
struct.pack_into('>IIIIII', r, a + 12, 2, 0, 30, 0x4, 1, 2)
s = sum(struct.unpack('>31I', r[a:a + 124])) & 0xffffffff
struct.pack_into('>I', r, a + 8, (-s) & 0xffffffff)
struct.pack_into('>I', r, 80, 1)
struct.pack_into('>10I', r, 536, 0x200000, 0x200000, 0, 4096, 0, 0, 0, 0x201000, 0, 4096)
s = sum(struct.unpack('>%dI' % (len(r) // 4), r)) & 0xffffffff
struct.pack_into('>I', r, 8, (-s) & 0xffffffff)
open(sys.argv[1], 'wb').write(r)
EOF
export KBOOTSET_KINFO=$T/kinfo KBOOTSET_KMEM=$T/nokmem

# case REASON: namelist refuses, exit 3, saying it; status goes on and says none
case_() {
	set +e; $KB namelist > $T/out 2>&1; rc=$?; set -e
	[ $rc = 3 ] && grep -q "no namelist: .*$1" $T/out ||
		{ echo "knlinit: namelist: wanted status 3 and \"$1\", got $rc:" >&2; cat $T/out >&2; exit 1; }
	set +e; $KB status > $T/out 2>&1; rc=$?; set -e
	[ $rc = 0 ] && grep -q "^namelist: none (.*$1" $T/out ||
		{ echo "knlinit: status: wanted status 0 and \"$1\", got $rc:" >&2; cat $T/out >&2; exit 1; }
}
sha=$(sha256sum < $T/unix | cut -c1-64)
case_ "/stand/k30/kabi cannot be read"
printf 'kabi=k30.1.0\nsha256=%s\n' "$sha" > $R/stand/k30/kabi
case_ "the kernel has no symbols"
zero=0000000000000000000000000000000000000000000000000000000000000000
printf 'kabi=k30.1.0\nsha256=%s\nsym=unix.sym 5 %s\n' "$zero" "$zero" > $R/stand/k30/kabi
case_ "kernel is not the installed one"
printf 'kabi=k30.1.0\nsha256=%s\nsym=unix.sym 5 %s\n' "$sha" "$zero" > $R/stand/k30/kabi
case_ "is missing or not the size"
printf 'abcde' > $R/stand/k30/unix.sym
case_ "differs from its sidecar"
echo "knlinit: a brel with no namelist to make: five refusals, namelist and status, nothing uninitialised"
