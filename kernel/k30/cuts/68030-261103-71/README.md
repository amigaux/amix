# Cut 68030-261103-71

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `c0d7df1` with -70's recipe. Against -70:

- **The kmem readers' names stay the kernel's.** The stock tools that read kernel tables through `/dev/kmem` and the
  namelist (`sadc`, so `sar` and `timex -s`, and `crash`) look up `inode`, `ifreelist`, `ifreeh`, `ufs_inode` and
  `inodeNINODE`. The carve had moved them into the s5 and ufs modules, so `sar` failed with "sadc cannot copy inode
  table". `kernel/dlm`'s `abi/k30/core.list` now lists them, and `build-cross-kernel.sh` step 8i links a `.comm`
  for every core.list name that is a COMMON of a carved stock object and nothing else in the link has (size and
  alignment from that object: `carvecom.o`). The modules' COMMONs bind to the kernel's copies when they load.
- **The module core** (amix `kernel/dlm` at `c0d7df1`) points `inode` at a read-only table of zeroed pages while s5
  is not loaded; s5's inoinit replaces it with the real table, and the s5 wrapper keeps the empty table's address
  (s5 is unload never). `ninode` is the kernel's.
- **kbootset-min=1.1.0.261103-37**: kbootset -37 writes a namelist that carries `crash_sync`'s word and the loaded
  modules' globals, which `crash` needs. An older kbootset refuses this kernel.

Byte proof: built from `c0d7df1` with -70's build id, the inputs that differ from -70 are `carvecom.o`, the module
core's objects (`dlm.o`, `dlm-f.o`, `ksym.o`, `plat-amiga.o`, `plat-k30-line.o`) and the s5 wrapper. Everything else that
differs follows from those: the linked kernel files, the sidecar and the s5 module. `mod.d/ufs` is unchanged apart
from the build id it is bound to.

| File | What |
|---|---|
| `SHA256SUMS-68030-261103-71` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`31edbc6`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `c0d7df1`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `c0d7df1`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`31edbc6`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1541700 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build. Its sums were reproduced by `../build.sh` on the host (gcc-cross-amix `33ebadc` built there) and
in the build container (`amix-toolchain:dist`, gcc-cross-amix `33ebadc`).
