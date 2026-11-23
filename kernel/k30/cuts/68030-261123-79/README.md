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

Evidence, in emulation. The vehicle is the released 1.1.2 k30 image, first-booted on an A3000 (68030, 16 MiB
motherboard fast RAM, so `dma_alloc` takes the kernel heap), with this cut's files laid and kern30m's record set to
them, then a kbootset generation; the A4091 driver is a test build of 1.0.0-13 that declares 64 KiB commands of one
segment. The emulator records every disk transfer (its D245 write log), so the command shapes below are counts, not
estimates. The rows of the bounce form ran first on trial cut 68030-261123-93, whose `dd.o` is this cut's byte for
byte; this cut repeats the cells, the loop and the boot.

- **Boot and limits**: generation 2 of -79 booted with the A4091 driver loaded, `ddflag` 0x10 (`D_NOBRKUP`) and the
  console line `dd: A4091 SCSI: commands of up to 65536 bytes through a bounce region`. The running kernel's
  `rlimits` has data and vmem 0x1000000 soft, 0x7fffffff hard; `ulimit -d` and `-v` say 16384, and `ulimit -d
  unlimited` and `ulimit -v unlimited` take.
- **Command shapes, A4091**: the raw cells (16 MiB written, read and verified at 64 KiB, 1 MiB read at 2 KiB) are 1536
  transfers, 1024 of them 64 KiB, where page commands make 33280 of 2 KiB; ufs on the same disk 17251 instead of
  52381. The raw sequences equal -93's transfer for transfer on all three scratch disks.
- **Throughput, A4091, -93** (32 MiB raw at 64 KiB, two passes): read 29 to 35 MB/s against 13.5 to 13.7 with page
  commands, write 11.5 to 14.7 against 7.7 to 7.8; process system time per pass about 1 s against 2.1 to 2.5.
- **No declaring driver**: with the same A4091 build told to declare nothing (`limits=0`) dd sends page commands, and
  the raw sequences equal those of a kernel whose region is refused (`ddx_maxbytes` 1024: `limits below a page`) on
  all three disks; an A2091 disk beside it gives step for step the sequence it gave before the bounce form. A kernel
  compiled without `-DDD_SDLIM` (this recipe with the gate off; a kernel without the module core does not link) sends
  page commands to the same declaring A4091 build, the same sequences again, and the driver's whole-command count
  stays 0.
- **Correctness**: in each cells row the trees copied to ufs on each disk and read back are the same, six cells run
  concurrently across the A2091 and both A4091 disks pass, and every verify reads back what was written. Two units of
  one card sharing its region queued for it (`wait` 1 here, 12 on -93). A refused `dma_alloc` (a 64 KiB region asked
  for late, once the heap was fragmented) fell back to page commands cleanly; the cut now asks at the root's open.
- **Five boots** of -79, each a 4 MiB raw write and verify through the region and a root file written and read back:
  all pass, 140 whole commands per boot.

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
build. Its sums were reproduced by `cut.sh` twice on the host with gcc-cross-amix `33ebadc`, and by `../build.sh` on the
host and in the build container (`dist-33ebadc-d5a43a7`, the checkout's toolchain pins).
