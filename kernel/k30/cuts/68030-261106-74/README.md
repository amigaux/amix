# Cut 68030-261106-74

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `fb39fec` with -73's recipe and two fixes:

- **hat_growsdt gives a shrunk segment table's tail back where it is.** The 030 hat keeps each address space's
  segment tables in 64-byte units (hat_sdtalloc, hat_sdtfree); when the swapper shrinks a table, the stock
  hat_growsdt freed its tail at table + units * 512 instead of table + units * 64, and hat_sdtfree then cleared bits
  in whatever page that address fell in -- on a data page the head of its mapping chain, so the chain walks of
  hat_unload and hat_swapout never ended, and a page left with no bits was freed while still mapped.
  `tools/growsdt030.py` checks hat_growsdt and hat_sdtfree against the stock code and makes the second shift a nop
  (2 bytes in `unix`; `build-cross-kernel.sh`, on by default from `84ea5ae`, `--no-growsdt-fix` without).  In
  emulation the 16 MiB netinstall, which stopped for good in 5 of 5 runs on builds from -71 to -73's code, completed 3
  of 3 on a build with -73's ufs and this fix, and an install under a watch on every store to a page's chain head
  logged none bad (the same watch on the unfixed kernel named hat_sdtfree).
- **A new ufs block never shows old disk data.** For a write of whole pages as_iolock granted pagecreate, and
  ufs_bmap then allocated a new block without reading or zeroing it, so the pages the write left alone read the disk
  block's former contents.  `src/as_iolock_ufs.c` keeps pagecreate only for a write that starts at its 8 KiB window
  and covers it or runs to the end of the file, as Solaris's ufs_wrip does; `tools/iolockufs030.py` retargets rwip's
  one call of as_iolock to it in the ufs object (on by default from `56f7845`, `--no-ufs-hole-fix` without).  In
  emulation `tests/sparsehole`'s hole modes found 40 to 242 of 288 pages wrong on -73 and none with the fix; its
  `eof` and `keep` modes found 0 on both (regression cases).  Random 4 KiB rewrites of pages not in the cache took
  28% and 50% longer in the two rows measured (they now read the page first); appends and copies cost the same.

Against -73 the shipped files differ only there: `unix` and `unix.brel` in the build id (one byte) and the 2 bytes of
the growsdt fix, `kabi` in its `build=` and `sha256=` lines, `mod.d/s5` in its `build=` (one byte), `mod.d/ufs` in its
`build=` and as_iolock_ufs linked in (80143 bytes); `unix.sym` and `audio.c` are the same.

| File | What |
|---|---|
| `SHA256SUMS-68030-261106-74` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`0508945`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `fb39fec`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `fb39fec`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`0508945`: `rth1.c`, `patch_ttcompat_init.py` and `patch_tcp_hiwat.py` as at
  `31edbc6`, and `patch_ip_lrhiwat.py` with `kelf.py`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1543028 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build.
Its sums were reproduced by `../build.sh` on the host (gcc-cross-amix `33ebadc`) and in the build container
(`amix-toolchain:dist`), and by `cut.sh` twice on the host with the host's own m68k binutils.
