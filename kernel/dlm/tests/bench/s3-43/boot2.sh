#!/bin/sh
# boot2.sh -- S3-43's loader rows (docs/spec/10-boot-loader.md §9):
#   l14.spec    for `kbootset commit --spec` on the box: the module kernel
#               with the manifest's arena capacity other than the identity
#               record's; boot2 refuses it with L14
#   l5.img      a store image built on the host by mkstore: generation 1
#               the module kernel as built (good), generation 2 (trial) a
#               copy of it whose identity record says a 64-byte arena (its
#               check fixed) with a manifest that says the same, so the
#               identity matches and the manifest copy does not fit: L5.
#               kbootset cannot write it (gate 4 refuses the generation:
#               "the manifest copy needs N bytes, the arena has 64"), so
#               the row writes this image over a slot copy's boot slice
# The kernels are deflated (z=deflate).  The script checks both against
# boot2's own rules (core.c arena_fill) before it writes them.
#
# usage: boot2.sh KERNEL SIDECAR OUTDIR "ROOTREC" [STORESIZE]
#   KERNEL, SIDECAR as s3-standin.sh takes them; ROOTREC the vehicle's
#   root record; STORESIZE the vehicle's boot slice in bytes (default
#   4 MiB).  Writes OUTDIR/l14.spec, OUTDIR/l5.img and their inputs.
# Needs build/mkstore, build/boot2.bin and build/boot1.img (`make`).
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
KERNEL=$1 SIDECAR=$2 OUT=$3 ROOTREC=$4 SSIZE=${5:-4194304}
R=$(cd "$(dirname "$0")/../../.." && pwd)
[ -n "$ROOTREC" ] || { echo "usage: boot2.sh KERNEL SIDECAR OUTDIR ROOTREC" >&2; exit 2; }
key() { sed -n "s/^$1=//p" "$SIDECAR" | head -1; }
LINE=$(key line) KABI=$(key kabi) BSS=$(key bss) FS=$(key rootfs | cut -d, -f1)
ARENA=$(key arena) IDENT=$(key ident)
[ -n "$ARENA" ] && [ -n "$IDENT" ] || { echo "boot2.sh: not a module kernel's sidecar" >&2; exit 1; }
mkdir -p "$OUT/stand/$LINE"
cp "$KERNEL" "$OUT/stand/$LINE/unix.l5"
python3 -I - "$OUT/stand/$LINE/unix.l5" "$ARENA" <<'PY'
import struct, sys
p, (aoff, acap) = sys.argv[1], (int(x, 16) for x in sys.argv[2].split())
d = bytearray(open(p, 'rb').read())
u = lambda o: struct.unpack('>I', d[o:o + 4])[0]
hits = [i for i in range(0, len(d) - 64, 2)
        if d[i:i + 8] == b'AXK1\x00\x01\x00\x40' and u(i + 40) == aoff and u(i + 44) == acap]
if len(hits) != 1:
    sys.exit('boot2.sh: the identity record is not found once in the kernel (%d)' % len(hits))
i = hits[0]
struct.pack_into('>I', d, i + 44, 64)            # a 64-byte arena
struct.pack_into('>I', d, i + 8, 0)
s = sum(struct.unpack('>16I', d[i:i + 64])) & 0xffffffff
struct.pack_into('>I', d, i + 8, (-s) & 0xffffffff)
open(p, 'wb').write(d)
PY
KLINE() { echo "kernel unix /stand/$LINE/$1${BSS:+ bss=$BSS} z=deflate"; }
AOFF=${ARENA% *} ACAP=${ARENA#* }
hdr() { printf 'line %s\nkabi %s\nloader-min 2\nrootfs %s\nroot %s\narena %s\nident %s\n' \
	"$LINE" "$KABI" "$FS" "$ROOTREC" "$1" "$IDENT"; }
{ hdr "$AOFF 0x00050000"; KLINE unix; } > "$OUT/l14.spec"
# l5.img's two generations, with host paths
cp "$KERNEL" "$OUT/stand/$LINE/unix"
G() { printf 'generation %s\nstate %s\n' "$1" "$2"; hdr "$3"
      echo "kernel unix $OUT/stand/$LINE/$4${BSS:+ bss=$BSS} z=deflate"; }
G 1 good "$ARENA" unix > "$OUT/l5-g1.spec"
G 2 trial "$AOFF 0x00000040" unix.l5 > "$OUT/l5-g2.spec"
rm -f "$OUT/l5.img"
"$R/build/mkstore" -o "$OUT/l5.img" -s "$SSIZE" -1 "$R/build/boot1.img" -2 "$R/build/boot2.bin" \
	-v 2 -d 1 "$OUT/l5-g1.spec" "$OUT/l5-g2.spec" > "$OUT/mkstore.log"
# boot2's checks, as core.c arena_fill makes them: L14 on the first, the
# identity passing and the manifest copy (over 32 bytes) not fitting on
# the second
python3 -I - "$KERNEL" "$OUT/stand/$LINE/unix.l5" "$ARENA" <<'PY'
import struct, sys
aoff, acap = (int(x, 16) for x in sys.argv[3].split())
def rec(p):
    d = open(p, 'rb').read()
    i = d.index(b'AXK1\x00\x01\x00\x40')
    w = struct.unpack('>16I', d[i:i + 64])
    return w, sum(w) & 0xffffffff
w, s = rec(sys.argv[1])
assert s == 0 and w[10] == aoff and w[11] == acap and acap != 0x50000, 'l14: the kernel'
w, s = rec(sys.argv[2])
assert s == 0 and w[10] == aoff and w[11] == 64, 'l5: the patched record'
PY
echo "boot2.sh: $OUT/l14.spec (arena capacity 0x50000 against the kernel's $ACAP); $OUT/l5.img (generation 1 good, 2 trial with a 64-byte arena; $SSIZE bytes)"
