#!/bin/bash
# cut.sh OUT -- cut 68030-261030-56 (the k30 module kernel, kabi k30.1.3) from amix 4fc583f, the -22 recipe with
# kzero, ufs tail zeroing and the sendsig FPU gate on (all three are build-cross-kernel.sh defaults at 4fc583f).
# Inputs, by environment:
#   AMIX         an amix clone that has 4fc583f (kernel/ is taken from it by git archive, nothing else)
#   AMIX_SYSTEM  amigaux/amix-system (the relink kit; build-cross-kernel.sh)
#   GCA, G14     gcc-cross-amix and gcc14-cross-amix build/ directories (toolchain/*.pin)
#   PORT         amix-040-060-port at 88dcfc0 (rth1.c, the ttcompat and tcp-hiwat fixes, the k46 kit headers)
#   PAULA        amix-paula at 548d258 (--audio-paula)
# OUT gets tree/ (the archive, dlm tools + kit built in it), cut-68030-261030-56/ (WORK: usr/sys, carve/, dlm-core/)
# and SHA256SUMS-68030-261030-56; the sums must equal ./SHA256SUMS-68030-261030-56.
set -eu
REV=4fc583f KB=68030-261030-56
OUT=${1:?usage: cut.sh OUT}; : "${AMIX:?}" "${AMIX_SYSTEM:?}" "${GCA:?}" "${G14:?}" "${PORT:?}" "${PAULA:?}"
OUT=$(mkdir -p "$OUT" && cd "$OUT" && pwd); T=$OUT/tree
rm -rf "$T" "$OUT/cut-$KB"; mkdir -p "$T"
git -C "$AMIX" archive "$REV" kernel | tar -x -C "$T"
. "$GCA/env.sh"; export PATH=$G14/prefix/bin:$PATH GCA G14 PORT AMIX_SYSTEM KIT_REV=$REV; unset AMIX_DRIVERS
make -C "$T/kernel/dlm" tools kit > "$OUT/dlm.log" 2>&1
cd "$T/kernel/k30"
WORK=$OUT/cut-$KB AMIX_MUL64=keep PATCH_DIRS="../drivers/z3660scsi ../drivers/a4091" \
OBJ_ALLOW="amiga/alien/a2090.o amiga/alien/a2091.o amiga/alien/ct.o amiga/alien/dd.o amiga/alien/sd.o master.d/filesys.o master.d/kernel.o amiga/driver/audio.o" \
OBJ_ABSENT="amiga/alien/a4091.o amiga/alien/ide.o" \
./build-cross-kernel.sh --sd-cards 4 --kabi k30.1.3 --audio-paula "$PAULA" --bempty-ram --config c6s1unix --no-scsi-drivers \
 --no-fstypes --carve-fs ufs,s5 --ttcompat-fix "$PORT/src/patch_ttcompat_init.py" --tcp-hiwat-fix "$PORT/src/patch_tcp_hiwat.py" \
 --object-baseline contracts/k030u-r5-objects.sha256 --kinfo src/kinfo030.c --kinfo-build $KB --kinfo-family K030-U \
 --rth1 "$PORT/src/rth1.c" --dlm-core "$T/kernel/dlm" > "$OUT/cut-$KB.log" 2>&1
cd "$OUT/cut-$KB/usr/sys"
sha256sum unix unix.brel unix.sym kabi mod.d/ufs mod.d/s5 amiga/driver/audio.c > "$OUT/SHA256SUMS-$KB"
cat "$OUT/SHA256SUMS-$KB"
