#!/bin/sh
# oracle.sh -- S3-43's relocation oracle on the box (80's stage-3 rows):
# the bytes the module core left in memory for t43rel against the host
# loader's image of the same object at the same base, resolved against the
# kernel's own symbol block bound where the loader bound the kernel.  The
# host loader is dlm_ld.c, which `make core` holds byte-identical to
# m68k-elf-ld (M-CORE1), so the box matches the cross linker too.
#
# usage: oracle.sh MODULE KERNEL SIDECAR BIND QFILE PFILE
#   MODULE   the t43rel object composed into the generation
#   KERNEL   the kernel as shipped, SIDECAR its sidecar (ksym=)
#   BIND     kinfo's bootdata text vaddr (C2-1 version 3, offset 540)
#   QFILE    the box's `modadmin -Q t43rel`
#   PFILE    the box's `modadmin -p t43rel_first:64 t43rel_fns:64`
# Needs build/axrel and build/core/test-bin/reloc (`make test`, `make core`).
#
# Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
set -e
R=$(cd "$(dirname "$0")/../../.." && pwd)
MODULE=$1 KERNEL=$2 SIDECAR=$3 BIND=$4 QFILE=$5 PFILE=$6
[ -n "$PFILE" ] || { echo "usage: oracle.sh MODULE KERNEL SIDECAR BIND QFILE PFILE" >&2; exit 2; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pc=$(python3 -I -c "import sys; d = open(sys.argv[1], 'rb').read(18); print('pcrel' if d[16:18] == b'\0\1' else '')" "$KERNEL")
"$R/build/axrel" "$KERNEL" "$BIND" "$T/img" $pc > /dev/null
ksym=$(sed -n 's/^ksym=//p' "$SIDECAR")
base=$(sed -n 's/^Base Address:[[:space:]]*//p' "$QFILE")
size=$(sed -n 's/^Module Size:[[:space:]]*//p' "$QFILE")
python3 -I -c "
import sys
o, n = (int(x, 16) for x in sys.argv[2].split())
open(sys.argv[3], 'wb').write(open(sys.argv[1], 'rb').read()[o:o + n])" "$T/img" "$ksym" "$T/ksym.bin"
"$R/build/core/test-bin/reloc" -k "$T/ksym.bin" -b "$base" -o "$T/want" "$MODULE" > "$T/reloc.out"
python3 -I - "$T/want" "$PFILE" "$base" "$size" <<'PY'
import re, struct, sys
want, base, size = open(sys.argv[1], 'rb').read(), int(sys.argv[3], 0), int(sys.argv[4])
seen, bad = {}, []
for l in open(sys.argv[2]):
    m = re.match(r'\S+\+\d+ 0x([0-9a-f]+): 0x([0-9a-f]+)', l.strip())
    if not m:
        continue
    a, v = int(m.group(1), 16), int(m.group(2), 16)
    o = a - base
    if o < 0 or o + 4 > size:
        continue
    w = struct.unpack('>I', want[o:o + 4])[0]
    if o in seen:
        continue
    seen[o] = 1
    if w != v:
        bad.append('+0x%x: box 0x%08x, host loader 0x%08x' % (o, v, w))
got = len(seen)
if not got:
    sys.exit('oracle: no word of the image in the modadmin -p output')
if bad:
    print('oracle: %d of %d words differ:\n%s' % (len(bad), got, '\n'.join(bad)))
    sys.exit(1)
print('oracle: t43rel at 0x%x: %d words, %d bytes of %d, identical to the host loader' %
      (base, got, 4 * got, size))
PY
