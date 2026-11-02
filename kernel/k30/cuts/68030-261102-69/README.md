# Cut 68030-261102-69

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `46c269c` with -68's recipe and pins. Against
-68, one change in the kernel:

- **Patch 0052 of the module core:** the INT2 and INT6 chain walks are skipped while no module has attached a
  handler. `int2_n` and `int6_n` count the attached handlers; `intr_attach` and `intr_detach` keep them. Level 2
  carries the clock tick and the stock SCSI and Ethernet interrupts, so a kernel with no attached module no longer
  walks eight empty slots on each of them.

Byte proof: built from `46c269c` with -68's build id, the only link input that differs from -68 is the core's
`dlm_intr.o`. Everything else that differs follows from it: the core's combined object, its symbol table, the
linked kernel files and the sidecar. ufs and s5 are -68's bytes. -69 then differs from that build only where the
build id is written, and in the hashes that follow.

The sidecar also gains `kbootset-min=1.1.0.261102-35`, copied from `kernel/dlm/core/kbootset-min`: the kernel
wants kbootset -35 or later.

| File | What |
|---|---|
| `SHA256SUMS-68030-261102-69` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`b0f1d86`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `46c269c`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `46c269c`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`b0f1d86`, as -68);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1540964 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build. Its sums were reproduced by `../build.sh` on the host (gcc-cross-amix `33ebadc` built there)
and in the build container (`amix-toolchain:dist`, gcc-cross-amix `33ebadc`).
