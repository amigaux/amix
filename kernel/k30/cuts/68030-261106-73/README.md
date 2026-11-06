# Cut 68030-261106-73

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `38ee0a2` with -72's recipe and one fix:

- **ufs rwip gives segmap_pagecreate the address the write starts at.** The stock ufs object passes the segmap
  window's base where SVR4's source passes base + mapon, so a write of whole pages that does not start at the 8 KiB
  window's start created the window's first pages without reading them: they kept their frames' old contents in the
  page cache (an earlier block of the file, zeros, another file's data) while the disk held the right data.
  `tools/rwippc030.py` checks the stock instructions around the call and makes the address push `pea a0@(0,d3:l)`,
  4 bytes in the ufs module (`build-cross-kernel.sh`, on by default from `38ee0a2`; `--no-ufs-rwip-fix` is -72's
  module).  Measured in emulation with a byte-checked random-rewrite test, -72 against this fix on the same rows:
  16 MiB with a 16 MB file, 4 KiB and 2 KiB writes, and 64 MiB with a 64 MB file, 4 KiB writes; -72 read back wrong
  data within the first 2325 to 21152 writes, each of the bad blocks it reported (rnd stops at 10) at offset 0 of its
  8 KiB window, and the fix ran
  100000 to 200000 operations with none.

Against -72 the shipped files differ only there: `unix` and `unix.brel` in the build id (one byte), `kabi` in its
`build=` and `sha256=` (the brel's hash) lines, `mod.d/s5` in its `build=` (one byte), `mod.d/ufs` in its `build=` and the
four bytes of the fix; `unix.sym` and `audio.c` are the same.

| File | What |
|---|---|
| `SHA256SUMS-68030-261106-73` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`0508945`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `38ee0a2`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `38ee0a2`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`0508945`: `rth1.c`, `patch_ttcompat_init.py` and `patch_tcp_hiwat.py` as at
  `31edbc6`, and `patch_ip_lrhiwat.py` with `kelf.py`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1543028 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build.
Its sums were reproduced by `../build.sh` on the host (gcc-cross-amix `33ebadc`) and in the build container
(`amix-toolchain:dist`), and by `cut.sh` twice on the host with the host's own m68k binutils.
