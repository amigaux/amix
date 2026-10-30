# Cut 68030-261030-56

The k30 module kernel, kabi k30.1.3 (abi 18c0a1c9), cut from amix `4fc583f` with the -22 recipe and the three
fixes that are build-cross-kernel.sh defaults there: kzero (grimoire quirk 90), ufs tail zeroing (quirk 91) and the
sendsig FPU gate (quirk 74).

| File | What |
|---|---|
| `SHA256SUMS-68030-261030-56` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |

Inputs (`cut.sh` names each by an environment variable):

- amix `4fc583f`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `4fc583f`);
- amix-system (the relink kit), gcc-cross-amix and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `88dcfc0` (rth1.c, the ttcompat and tcp-hiwat fixes, the k46 kit headers);
- amix-paula at `548d258` (`--audio-paula`: audio.c 1f43c5ff, as in -22).

The cut also reproduces, all seven sums, with the port at `d0e8857` (`kernel/port/port.pin` at `4fc583f`, nine
commits after `88dcfc0`): the files the recipe reads (rth1.c, the two patchers, the k46 kit headers) are the same.

`unix.brel` is the form shipped (as `/stand/k30/unix`), `kabi` its sidecar, `unix.sym` its symbols, `unix` the
ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this build (module
kabi k30.1.2); their carve sources are in the cut's `carve/`. Against -22: the kernel adds the three fixes and keeps
kabi k30.1.3; the module core is amix kernel/dlm at `4fc583f`.
