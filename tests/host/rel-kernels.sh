#!/bin/sh
# rel-kernels.sh -- the relocator on real kernels, against an independent
# implementation: each ET_REL kernel is converted to brel with amix-kerntools'
# elf2brel.py; relocating the ET_REL with our ET_REL path and the brel with
# our brel path must give byte-identical memory images.
# Inputs are not part of this repository: AX_KERNELS (space-separated ET_REL
# kernels) and AX_ELF2BREL (path to elf2brel.py).  Skipped when unset.
set -e
B=${B:-build}
[ -n "$AX_KERNELS" ] && [ -n "$AX_ELF2BREL" ] || { echo "rel-kernels: AX_KERNELS/AX_ELF2BREL unset, skipped"; exit 0; }
T=$B/rk; rm -rf $T; mkdir -p $T
V=0x08000000
for k in $AX_KERNELS; do
	n=$(basename "$k")
	python3 -I "$AX_ELF2BREL" "$k" "$T/$n.brel" >/dev/null
	$B/axrel "$k" $V "$T/$n.elf.mem" pcrel
	$B/axrel "$T/$n.brel" $V "$T/$n.brel.mem"
	cmp "$T/$n.elf.mem" "$T/$n.brel.mem"
	echo "rel-kernels: $n: ET_REL and brel relocations identical ($(wc -c < "$T/$n.elf.mem") bytes)"
done
