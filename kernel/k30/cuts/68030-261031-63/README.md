# Cut 68030-261031-63

The k30 module kernel, kabi k30.1.3 (abi 18c0a1c9), cut from amix `c1b7842` with the -22 recipe and the four fixes
that are build-cross-kernel.sh defaults there: kzero (grimoire quirk 90), ufs tail zeroing (quirk 91), the sendsig
FPU gate (quirk 74) and the STREAMS freeq guard (quirk 92).

| File | What |
|---|---|
| `SHA256SUMS-68030-261031-63` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |

Inputs (`cut.sh` names each by an environment variable):

- amix `c1b7842`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `c1b7842`);
- amix-system (the relink kit), gcc-cross-amix and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `d0e8857`, `kernel/port/port.pin` at `c1b7842` (rth1.c, the ttcompat and tcp-hiwat fixes,
  the k46 kit headers);
- amix-paula at `548d258` (`--audio-paula`: audio.c 1f43c5ff, as in -22 and -56).

`unix.brel` is the form shipped (as `/stand/k30/unix`), `kabi` its sidecar, `unix.sym` its symbols, `unix` the
ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this build (module
kabi k30.1.2); their carve sources are in the cut's `carve/`. Against -56: the kernel adds the freeq guard (5 freeq
relocations, in qdetach, strclose and stropen, retargeted to freeq_guarded) and keeps kabi k30.1.3.  With
`--no-freeq-guard`, -56's build id and KIT_REV, the recipe on the guard's sources reproduced all six -56 kernel sums.
