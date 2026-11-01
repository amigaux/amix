# Cut 68030-261101-67

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `e155eb3` with -66's recipe. Against -66 it has
two changes:

- **The swapadd guard** (`build-cross-kernel.sh`'s default since `1dff121`). `swapadd` allocates a swap area's
  anon array, 16 bytes per page of the area, as a single block from kvseg. When kvseg had no free run that large,
  the allocation slept on `Km_OsizeWanted` for ever, so `swap -a` and the boot-time add of the swap slice's tail
  hung. With the guard (`src/swapguard030.c`, retargeted after the link by `tools/swapguard-retarget.py`), such an
  add fails at once with ENOMEM.
- **Patch 0050 of the module core:** a first-use load that finds memory short prints the first-use line.

No list name changes, so kabi and abi stay the same. The carved ufs and s5 modules stay kabi k30.1.2, boot class,
core tier.

| File | What |
|---|---|
| `SHA256SUMS-68030-261101-67` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`b0f1d86`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `e155eb3`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `e155eb3`);
- amix-system (the relink kit), gcc-cross-amix and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`b0f1d86`, as -66: rth1.c and the ttcompat and tcp-hiwat fixes are the same
  at the later `kernel/port/port.pin`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1539888 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build. Its sums were reproduced by `../build.sh` on the host and in the build container.
