#!/bin/sh
# m-ld7.sh -- inputs for M-LD7 (CRC-32 and SHA-256 time) and M-LD8 (inflate
# time) on the Amiga: copies axtime, the two floppy-class static kernels and
# their raw-deflate streams (as mkstore stores them) into <outdir>, and
# writes EXPECTED with the commands to run and the CRC-32 and SHA-256 that
# axtime must print.  See docs/plan/stage-1.md S1-23.
#
# usage: m-ld7.sh <workspace> <outdir>
#   <workspace>  the Amix project workspace (holds amix-kerntools/)
# Run from the repository root after `make axtime`.
set -e
WS=$1 OUT=$2
B=${B:-build}
K=$WS/amix-kerntools/work/k0-chains
mkdir -p "$OUT"
cp $B/axtime "$OUT/axtime"
cp $B/axtime-chip "$OUT/axtime-chip"
cp "$K/K030-U-FD/K030-U-FD-c0-u6" "$OUT/k30.kernel"
cp "$K/KD060-FD/KD060-FD-fd0" "$OUT/k46.kernel"
python3 -I - "$OUT" <<'EOF'
import hashlib, os, sys, zlib
out = sys.argv[1]
lines = ['# axtime runs for M-LD7/M-LD8; each must print the crc32 and sha256 shown.',
         '# axtime-chip is the same program loaded into chip RAM (boot2 runs from',
         '# chip RAM behind boot1): run every line with both']
for k in ('k30', 'k46'):
    raw = open(os.path.join(out, k + '.kernel'), 'rb').read()
    best = None
    for ml in (8, 9):  # as mkstore: the smaller of zlib memory levels 8 and 9
        c = zlib.compressobj(9, zlib.DEFLATED, -15, ml)
        z = c.compress(raw) + c.flush()
        if best is None or len(z) < len(best):
            best = z
    open(os.path.join(out, k + '.z'), 'wb').write(best)
    crc = '%08x' % (zlib.crc32(raw) & 0xffffffff)
    sha = hashlib.sha256(raw).hexdigest()
    lines.append('axtime %s.kernel          # %d bytes: crc32 %s, sha256 %s' % (k, len(raw), crc, sha))
    lines.append('axtime %s.z %d   # %d stored bytes, inflated: the same crc32 and sha256' % (k, len(raw), len(best)))
open(os.path.join(out, 'EXPECTED'), 'w').write('\n'.join(lines) + '\n')
EOF
cat "$OUT/EXPECTED"
