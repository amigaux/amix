#!/bin/sh
# inflate-kernels.sh -- the decoder on real kernels: each 1.0 floppy boot
# image's LZW kernel is unpacked with gzip, deflated with zlib (level 9),
# inflated with our decoder and compared byte for byte.
# Inputs are not part of this repository; pass the boot floppy images in
# AX_FLOPPIES (space-separated).  Skipped when unset.
set -e
B=${B:-build}
[ -n "$AX_FLOPPIES" ] || { echo "inflate-kernels: AX_FLOPPIES unset, skipped"; exit 0; }
T=$B/ik; rm -rf $T; mkdir -p $T
for adf in $AX_FLOPPIES; do
	n=$(basename "$adf")
	python3 -I - "$adf" "$T/$n.raw" "$T/$n.def" <<'PY'
import struct, subprocess, sys, zlib
a = open(sys.argv[1], 'rb').read()
for i in range(0x400, 0x2800, 512):
    if a[i:i+4] == b'IBLK':
        size, full = struct.unpack('>II', a[i+8:i+16])
        if full and a[i+512:i+514] == b'\x1f\x9d':
            raw = subprocess.run(['gzip', '-dc'], input=a[i+512:i+512+size],
                                 capture_output=True, check=True).stdout
            open(sys.argv[2], 'wb').write(raw)
            c = zlib.compressobj(9, zlib.DEFLATED, -15)
            open(sys.argv[3], 'wb').write(c.compress(raw) + c.flush())
            break
else:
    sys.exit('no LZW kernel in ' + sys.argv[1])
PY
	size=$(wc -c < "$T/$n.raw")
	$B/axinflate "$T/$n.def" "$T/$n.out" "$size"
	cmp "$T/$n.raw" "$T/$n.out"
	echo "inflate-kernels: $n: $size bytes from $(wc -c < "$T/$n.def") deflated, identical"
done
