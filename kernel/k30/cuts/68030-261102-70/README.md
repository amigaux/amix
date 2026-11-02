# Cut 68030-261102-70

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `406be5d` with -69's recipe. Against -69:

- **sdqueue at sdspl() or above** (`templates/sd.c.in`, raise only). `dd`, `sdpart` and `ct` already queue at
  `sdspl()`, but the raw passthrough (`scsi.c` `gsioctl`, `/dev/scsi`) queued at spl0. The stock A3000 SCSI
  driver resets its WD33C93 on its first command and polls for the reset's interrupt. With level 2 open,
  `a3091intr` took that interrupt first, read SS 0x01 while idle and shut the driver down (`a3091: 0x1 0 0x0`),
  so the command never ran. That happened when a SCSI inquiry was the WD's first command (`kbootset inquiry`
  from an installer). sdqueue now raises to level 2 only when its caller is below it, as the DDI allows a caller
  at any level but 6.
- **The A1200's Gayle IDE:** `kinfo030.c` gives the controller name `A1200 IDE` motherboard id 2, as
  `A4000 IDE`, and the port at `31edbc6` gives `rth1.c` the same rule, so a root record keyed on the Gayle port
  finds an A1200's IDE disk.

Byte proof: built from `406be5d` with -69's build id and port pin, the link inputs that differ from -69 are
`sd.o` and `kinfo.o`. Built with this record's port pin, the only further input that differs is `rth1.o`.
Everything else that differs follows from those: the relinked exps, the module core's symbol table, the linked
kernel files, the sidecar, and ufs and s5 by the build id they are bound to.

| File | What |
|---|---|
| `SHA256SUMS-68030-261102-70` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`31edbc6`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `406be5d`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `406be5d`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`31edbc6`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1541096 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar (with
`kbootset-min=1.1.0.261102-35`), `unix.sym` holds its symbols, and `unix` is the ET_REL it was made from.
`mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this build. Its sums were reproduced by
`../build.sh` on the host (gcc-cross-amix `33ebadc` built there) and in the build container
(`amix-toolchain:dist`, gcc-cross-amix `33ebadc`).
