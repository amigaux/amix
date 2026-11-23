# Cut 68030-261123-79

The k30 module kernel, kabi k30.1.6 (abi 18c0a1c9), cut from amix `c7b59dda`: -78's recipe with dd cutting its own
block requests and bouncing whole ones for a controller that declares its DMA limits, the module core with dlm core
0059, and the stock soft data and vmem limits.

- **dd cuts its own block requests.** fix_swtbls reads each block row's `d_flag` once at boot; without `D_NOBRKUP`
  it puts gen_strategy in front of the driver, which cut a page list into one command per page and a larger buffer
  through buf_breakup. `kernel.c.patch` points dd's row at `ddflag` (`D_NOBRKUP`), and `dd.c.patch` makes the same
  pieces in place: a page list one command per page (`vtop` of each frame), any other buffer over a page a piece per
  page. No buffer header is built (no pageio_setup, no fixed header array), nothing sleeps, a piece that fails ends a
  non-page-list request, a page list shorter than the count fails, and the next request starts before `iodone`, the
  completion order the Z3660 SCSI driver's own dd.c patch used to carry (that patch is gone; z3660scsi supplies no
  stock-file patch). Sense data is 16-aligned. The raw path of a controller that declares no limits keeps
  `amiga_dma_pageio`.
- **Whole requests for a controller that declares limits.** dd.c is compiled with `-DDD_SDLIM`, which
  build-cross-kernel.sh passes for a kernel with the module core at kabi minor 6 or later and the four-card sd,
  beside a copy of the kit's `sys/sdseg.h`. At the first open dd asks every card sd opens for its limits (`sd_lim`);
  a card that declares them gets a bounce region of up to 64 KiB (`dma_alloc`, the declared maximum rounded down to
  512, capped by `ddx_maxbytes`) and a 16-byte sense slot per unit. A request goes whole, up to the region's size per
  command, through `sdqueuex`: a write is copied into the region first, a read out of it after; `b_resid` comes from
  `sx_resid`. One unit holds a card's region at a time; the others wait in order. The copy walks a page list, a
  kernel buffer or a user buffer (`vtop` per page with `b_proc`), and fails the request where a page is missing.
  A card whose limits are below a page, whose region `dma_alloc` refuses or whose region lies out of its reach
  keeps page commands, with one console line, `dd: <card>: <why>, page commands`. adb reads `ddxstat` (`cmd`,
  `wait`, `err`, `fallback`) and `ddx_maxbytes`. Probing at the first open (the root's) is deliberate: a 64 KiB
  region asked for later can fail once the kernel heap is fragmented.
- **kabi k30.1.6.** The module core carries dlm core 0059: `sd_limits` (a driver declares its limits for a card),
  `sd_lim` and `sdqueuex` (C4-7). The new names are functions, so `abi=` is 1.5's.
- **The stock soft data and vmem limits.** Cuts -68 to -78 raised the soft data and vmem limits to unlimited
  (`PROC_LIMITS=1` in their cut.sh). This cut leaves master.d/kernel.h's 16 MiB (hard limits unlimited), and
  `--rlimits-text` checks kern30m's pkginfo against the linked `rlimits` table.

Against -78 the shipped files differ in `unix` (dd.o, kernel.o, the rlimits table, the module core, the build id) and
so `unix.brel` (1549840 bytes), `unix.sym` and `kabi`; `mod.d/ufs` and `mod.d/s5` differ only in the build id they
carry. audio.c is -78's (3f434f35).

The build's own checks (`cut-68030-261123-79.log`): dd.o compiled in the bounce form; the 80 stock objects equal the
baseline and exactly the allowed eight differ; the linked rlimits table is data and vmem 1000000/7fffffff, and
pkginfo says so; the hardbus, sync and btwalk checks as in -78, before and after the module core's splice;
`mkabi --check` gives abi 18c0a1c9; the sidecar checks; relsim finds no relocation the boot loader would refuse.

| File | What |
|---|---|
| `SHA256SUMS-68030-261123-79` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`59e1b77`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `c7b59dda`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `c7b59dda`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`59e1b77`: `syncguard.s`, `btwalk.s`, and `rth1.c`, `patch_ttcompat_init.py`,
  `patch_tcp_hiwat.py`, `patch_ip_lrhiwat.py` and `kelf.py` as at `0508945`; the port's later commits up to
  `2dff5e4` change none of them);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: its three patchers make audio.c 1f43c5ff, which
  `tools/patch_audio_replies.py` makes 3f434f35).

`unix.brel` is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its symbols, and
`unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this
build. Its sums were reproduced by `cut.sh` twice on the host with gcc-cross-amix `33ebadc`.
