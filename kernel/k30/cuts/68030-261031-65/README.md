# Cut 68030-261031-65

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9, as k30.1.3's), cut from amix `74405ce` with -64's recipe and
fixes. Against -64 the module core carries patch 0048: a demand-class filesystem module (one with `fs=`) loads at
the first mount of its type, through a stub row the core puts into a spare vfssw row at boot. kabi k30.1.4 adds no
list name. The carved ufs and s5 modules stay kabi k30.1.2, boot class, core tier.

| File | What |
|---|---|
| `SHA256SUMS-68030-261031-65` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`b0f1d86`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `74405ce`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `74405ce`); with
  `build-cross-kernel.sh` and `tools/kabi-sidecar030.py` from `4eeb376`, which take kabi k30.1.4;
- amix-system (the relink kit), gcc-cross-amix and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`b0f1d86`: rth1.c, the ttcompat and tcp-hiwat fixes, the k46 kit headers;
  against -64's `0d37eb1` they differ in comments only);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1538308 bytes) is the form shipped (as `/stand/k30/unix`), `kabi` its sidecar, `unix.sym` its
symbols, `unix` the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to
this build. Its sums came from the build container through `../build.sh` and were reproduced on the host and in the
container again.
