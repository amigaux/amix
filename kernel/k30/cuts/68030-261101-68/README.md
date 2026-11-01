# Cut 68030-261101-68

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `3b53a8a` with -67's recipe. Against -67:

- **gcc-cross-amix `33ebadc`** (was `8949028`). The sidecar says `pin=gcc-2.7.2.3-33ebadc`, and
  `build-cross-kernel.sh` checks that the sidecar's pin is the module core's `kernel/dlm/toolchain.pin`, the pin a
  module's `cc=` is checked against.
- **Patch 0051 of the module core:** a module's majors come from the booted manifest's major records, which kbootset
  -34 writes from the registry (it now has c 55 zz9ksvc). A generation without the records refuses every module
  major while the box still boots, so the kernel wants kbootset -34 or later.
- **Process limits:** the soft data and vmem limits are 0x7fffffff (unlimited), like their hard limits; the soft
  stack limit stays 16 MB (`master.d/kernel.h`, the linked `rlimits` table checked).

No list name changes, so kabi and abi stay the same. The carved ufs and s5 modules stay kabi k30.1.2, boot class,
core tier.

| File | What |
|---|---|
| `SHA256SUMS-68030-261101-68` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`b0f1d86`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `3b53a8a`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `3b53a8a`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`b0f1d86`, as -67);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1540744 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build. Its sums were reproduced by `../build.sh` on the host (gcc-cross-amix `33ebadc` built there)
and in the build container (`amix-toolchain:gca-33ebadc`).
