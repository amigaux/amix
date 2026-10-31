# Cut 68030-261031-64

The k30 module kernel, kabi k30.1.3 (abi 18c0a1c9), cut from amix `b391504` with -63's recipe and fixes (kzero,
grimoire quirk 90; ufs tail zeroing, quirk 91; the sendsig FPU gate, quirk 74; the STREAMS freeq guard, quirk 92).
Against -63 the module core's major registry carries `c 48 random` (`a8719fb`), so the random module's char major
is one the kernel registers itself.

| File | What |
|---|---|
| `SHA256SUMS-68030-261031-64` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |

Inputs (`cut.sh` names each by an environment variable):

- amix `b391504`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `b391504`);
- amix-system (the relink kit), gcc-cross-amix and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `kernel/port/port.pin` (`0d37eb1`: rth1.c, the ttcompat and tcp-hiwat fixes, the k46 kit
  headers);
- amix-paula at `kernel/drivers/paula/paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff, as in -63).

`unix.brel` is the form shipped (as `/stand/k30/unix`), `kabi` its sidecar, `unix.sym` its symbols, `unix` the
ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this build (module
kabi k30.1.2); their carve sources are in the cut's `carve/`. The first cut made by make dist's `kernel-k30` hook
(`../build.sh`): its sums came from the build container and were reproduced on the host and in the container again.
