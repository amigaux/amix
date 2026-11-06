#!/bin/bash
# cut.sh OUT -- cut 68030-261106-74 (the k30 module kernel, kabi k30.1.4) from amix fb39fec: -73's recipe with
# hat_growsdt's shrink freeing the tail where it is (tools/growsdt030.py) and pagecreate kept only for writes that start
# at the 8 KiB window and cover it or reach EOF (src/as_iolock_ufs.c, tools/iolockufs030.py); both on by default at
# fb39fec (GROWSDT_FIX=1 UFS_HOLE_FIX=1 below).
# Port 0508945 (patch_ip_lrhiwat.py and kelf.py; rth1.c and the ttcompat and tcp-hiwat fixes as at 31edbc6).
# kabi k30.1.4 and abi 18c0a1c9 unchanged.
# Inputs, by environment:
#   AMIX         an amix clone that has fb39fec (kernel/ is taken from it by git archive, nothing else)
#   AMIX_SYSTEM  amigaux/amix-system (the relink kit; build-cross-kernel.sh)
#   GCA, G14     gcc-cross-amix and gcc14-cross-amix build/ directories (toolchain/*.pin)
#   PORT         amix-040-060-port at ./port.pin (0508945: rth1.c, the ttcompat, tcp-hiwat and ip-lrhiwat fixes,
#                the k46 kit headers)
#   PAULA        amix-paula at ./paula.pin (1b2736d: --audio-paula)
# OUT gets tree/ (the archive, dlm tools + kit built in it), cut-68030-261106-74/ (WORK: usr/sys, carve/, dlm-core/)
# and SHA256SUMS-68030-261106-74; the sums must equal ./SHA256SUMS-68030-261106-74.
set -eu
REV=fb39fec KB=68030-261106-74
OUT=${1:?usage: cut.sh OUT}; : "${AMIX:?}" "${AMIX_SYSTEM:?}" "${GCA:?}" "${G14:?}" "${PORT:?}" "${PAULA:?}"
OUT=$(mkdir -p "$OUT" && cd "$OUT" && pwd); T=$OUT/tree
rm -rf "${T:?}" "${OUT:?}/cut-$KB"; mkdir -p "$T"
git -C "$AMIX" archive "$REV" kernel | tar -x -C "$T"
. "$GCA/env.sh"; export PATH=$G14/prefix/bin:$PATH GCA G14 PORT AMIX_SYSTEM KIT_REV=$REV; unset AMIX_DRIVERS
# the switches build-cross-kernel.sh and the port's patchers read from the environment, at the values this cut is
export IPLR_HIWAT=0x10000 FPU_GATE=1 FREEQ_GUARD=1 ARENA8M=1 SEGVN_PROT=1 RMW_FAULT=1 KMEM_WAKE=1 SWAP_GUARD=1 PROC_LIMITS=1 \
 UFS_TAILZERO=1 KZERO=1 UFS_RWIP=1 GROWSDT_FIX=1 UFS_HOLE_FIX=1
make -C "$T/kernel/dlm" tools kit > "$OUT/dlm.log" 2>&1
cd "$T/kernel/k30"
WORK=$OUT/cut-$KB AMIX_MUL64=keep PATCH_DIRS="../drivers/z3660scsi ../drivers/a4091" \
OBJ_ALLOW="amiga/alien/a2090.o amiga/alien/a2091.o amiga/alien/ct.o amiga/alien/dd.o amiga/alien/sd.o master.d/filesys.o master.d/kernel.o amiga/driver/audio.o" \
OBJ_ABSENT="amiga/alien/a4091.o amiga/alien/ide.o" \
./build-cross-kernel.sh --sd-cards 4 --kabi k30.1.4 --audio-paula "$PAULA" --bempty-ram --config c6s1unix --no-scsi-drivers \
 --no-fstypes --carve-fs ufs,s5 --ttcompat-fix "$PORT/src/patch_ttcompat_init.py" --tcp-hiwat-fix "$PORT/src/patch_tcp_hiwat.py" \
 --ip-lrhiwat-fix "$PORT/src/patch_ip_lrhiwat.py" \
 --object-baseline contracts/k030u-r5-objects.sha256 --kinfo src/kinfo030.c --kinfo-build $KB --kinfo-family K030-U \
 --rth1 "$PORT/src/rth1.c" --dlm-core "$T/kernel/dlm" > "$OUT/cut-$KB.log" 2>&1
cd "$OUT/cut-$KB/usr/sys"
sha256sum unix unix.brel unix.sym kabi mod.d/ufs mod.d/s5 amiga/driver/audio.c > "$OUT/SHA256SUMS-$KB"
cat "$OUT/SHA256SUMS-$KB"
