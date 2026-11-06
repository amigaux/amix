# Cut 68030-261106-75

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `75ded5c`: -74's recipe with the ufs hole fix made
by a block lookup.  -74 is kept as it was cut; this cut replaces it.

- **hat_growsdt gives a shrunk segment table's tail back where it is**, as in -74: `tools/growsdt030.py` makes the
  second shift of hat_growsdt's free a nop (2 bytes in `unix`; `build-cross-kernel.sh`, on by default from `84ea5ae`,
  `--no-growsdt-fix` without).  See -74's README for the cause and the netinstall and watch evidence; the code is the
  same here.
- **A new ufs block never shows old disk data, and an allocated block is rewritten as stock.** For a write of whole
  pages as_iolock grants pagecreate, and ufs_bmap allocated a new block alloc-only, without reading or zeroing it, so
  the pages the write left alone read the disk block's former contents.  `src/ufs_bmap_hf.c` looks the block up
  first (ufs_bmap with S_READ, which allocates nothing, under the inode lock rwip holds for the real call) and turns
  alloc-only off for a hole, so ufs_bmap reads the new block -- zero-filled -- before the write; a block already
  allocated keeps alloc-only, which allocates nothing there, so its rewrite reads nothing, as stock.
  `tools/bmaphf030.py` retargets rwip's one call of ufs_bmap to it in the ufs object (on by default from `75ded5c`,
  `--no-ufs-hole-fix` without); as_iolock and ufs_bmap's other callers are stock.  -74 kept pagecreate only for writes
  from the 8 KiB window's start instead (`src/as_iolock_ufs.c`, retired), which made random rewrites of pages not in
  the cache read them first.
  In emulation at 16 MiB `tests/sparsehole` found 40 (direct, writes at page 1) and 122 direct and 205 indirect
  (writes on the block's last page) of 288 pages wrong on -73 and none on this cut and its trial build, in all four
  modes (`eof` and `keep` are regression cases: 0 on both).  20000 random 4 KiB rewrites of pages not in the cache of
  a 96 MB file at 64 MiB took 27 and 26 s on -73, 24 and 25 s on the trial in the same run and 24 and 25 s on this
  cut (-74's rule: 30 and 29 s against 23 and 23 s); appends and copies cost the same.  rnd found no bad block at 16
  and 64 MiB; for growsdt, forkst at 16 MiB under the chain-head watch logged none bad and vm30 printed what it did
  on -92.

Against -74 the shipped files differ only there: `unix` and `unix.brel` in the build id (one byte), `kabi` in its
`build=` and `sha256=` lines, `mod.d/s5` in its `build=` (one byte), `mod.d/ufs` in its `build=` and ufs_bmap_hf in
as_iolock_ufs's place (80261 bytes); `unix.sym` and `audio.c` are the same.

| File | What |
|---|---|
| `SHA256SUMS-68030-261106-75` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`0508945`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `75ded5c`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `75ded5c`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`0508945`: `rth1.c`, `patch_ttcompat_init.py` and `patch_tcp_hiwat.py` as at
  `31edbc6`, and `patch_ip_lrhiwat.py` with `kelf.py`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1543028 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build.
Its sums were reproduced by `cut.sh` on the host with gcc-cross-amix `33ebadc`, and by `../build.sh` on the host and in
the build container (`amix-toolchain:dist`).
