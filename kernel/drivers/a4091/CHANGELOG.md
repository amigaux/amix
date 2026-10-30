# Changelog

## 2026-10-30 — moved in from amix-a4091

jusii/amix-a4091 master 9a2753a (99 commits) moved into amix kernel/drivers/a4091 by subtree merge after a filter-repo
--replace-text rewrite of an old local path prefix in the first 10 commits; tip tree unchanged, no commit pruned;
old→new map in docs/history-map.txt (tip 9a2753a → 0ede9f0). privacy-check --all: 0 hits (was 10, class 1).

## 2026-10-28 — docs: A4000T-ONBOARD-710.md §10.10, a4kt710 unsupported with the Z3660 in 030 mode (no NCR tag in the A3000 Kickstart, SIMMs hidden in amix_mode so no bus-master DMA memory, $DD0000 mapped to the emulated A3000 SCSI); the real-060 k46 line is the supported path (facf889)

## 2026-10-27 — module/a4kt710: rebuild when the included a4091-wr.c changes

A stale object without the C4-2 v6 §8.1 gate had been checked and reported; the mint was built fresh and is correct (k46 95bebecb,
k30 e65b4f7d). The host tests compile the source directly and were valid; re-run from clean, all pass.

## 2026-10-27 — S5-06: a4kt710, the A4000T onboard NCR 53C710 as a second module target of the A4091 driver (6cc01e4, d9fe9f7, e9a0257, a74708e)

mobo:a4000t-710, rank mobo. Its gate is C4-2 v6 §8.1: the running Kickstart's "NCR scsi.device" cold-start tag (or declared=1),
then AGA, then a read-only fingerprint; otherwise ENXIO with nothing under $DD0000 touched. modcheck ok on k46/k30; host 12/12
per line, mutation-checked; the a4091 module and the static objects unchanged.

## 2026-10-27 — a4091 module 1.0.0-5: a selection timeout is silent (9dfdf5b)

An absent id answering a bus scan (rc -1) is counted in a4091_kstat.seltimeout and no longer traced; the installer's source probe
and disk scan had filled the k30 console with "A4091 slow" lines (rd1h E955; the gate traced any failed command, identical on both
lines). Slow polls, the poll bound, phase errors and short-read recoveries still trace; no debug param added. Host 18/18 per arm,
mutation-checked; modcheck ok k46 (5524 B, 8655e87a) / k30 (4532 B, 6a6b6b3c); static objects unchanged.

## 2026-10-27 — a4091 module 1.0.0-4: the WRITE/TUR sync runs over a clear line, not the status line (3ec2ecd, 21d3bac)

Bench N109's NO-SENSE retries under dma_forcebounce: the cache-clearing sync ran over the chip-written status line, so a bounced
FROM complete copied stale bytes over the status. The area gains a 16-byte clear line nobody writes (1348 B) and the sync runs
there. The host mock models the hook (GOOD lands, then 0x5a copied back): red on 1.0.0-3, green now, 17/17 per arm,
mutation-checked. modcheck ok k46 (5476 B, 3d8cc066) / k30 (4492 B, 69929d09); static objects unchanged. E6 marked passed.

## 2026-10-27 — a4091 module 1.0.0-3: the attach lines name the board, not a card (aa4c278)

sd assigns the card only after registration (Bench N106: the Z3660 ranked first made the A4091 card 1 after the module had
printed "card 0"), so the k46 attach lines say `a4091: board N at …`; RTH1/kinfo name the card. The static strings are unchanged
(one macro per message). k46 object 54405c68; k30 byte-identical to 1.0.0-2. Host 16/16 per arm. E1 (N105/N105b) and E2 (N106)
marked passed in the README.

## 2026-10-27 — a4091 module: the refused arm also calls dma_complete (drv_prep == drv_cmpl)

dma_complete with nothing prepared only counts cmpl_noprep on both providers (dlm), so the refused arm completes too.
Host 16/16 per arm; modcheck ok k46.1.2 (5492 B, ef8cd0dc) / k30.1.2 (4484 B, adbc4e47); static objects unchanged. Still 1.0.0-2
(1.0.0-2 is unminted; it mints in the -79/-14 wave).

## 2026-10-27 — a4091 module 1.0.0-2, C4-5 v5 (0c00bc9, 7ad5299, 53bebc5)

A dma_addr of 0 is never armed: no DSP write, status 0xff, okay FALSE, callback, a4091_kstat.noreach++ (no dma_complete;
invariant drv_prep == drv_cmpl + noreach). After a WRITE or TUR the area's own 16-byte status line gets a FROM_DEVICE
prepare/complete before the status read (the k30 write-through cache), counted in stsync. Area 1332 B (sline, SCRIPTS, DSA,
ident+CDB, bounce). modcheck ok k46.1.2 (5476 B, 2ba85168) / k30.1.2 (4468 B, fe163b4e); host tests 16/16 per arm,
mutation-checked; static objects unchanged. README: E6 with dma_forcebounce, E6b the pool-miss EIO row.

## 2026-10-27 — S4-31 tests: test/host and the module README's test matrix (caa35b5, 23e34ba)

test/host (new): the real a4091-wr.c with -DA4091_MODULE on host gcc, mocks for autocon, the two map arms, sd_register and the
five DMA names; 15/15 cases per line: registrations, A4092/A4770 identities, two-board sd order (an A4092 below an A4091 is
card 0), 4-board cap, ENXIO/ENOMEM/dead-board/refused-registration paths, _halt per board, the C4-5 order and addresses;
mutation-checked. README matrix: H1/H2, emulation E1–E6 (k46 -78+; A4092/A4770 cannot be emulated — amiberry takes the board
id from a byte-swapped ROM), metal M1–M5. Static pins untouched.

## 2026-10-27 — S4-31: the A4091/A4092/A4770 root-class module (d9ee8d7, a7f7fea)

-DA4091_MODULE turns a4091-wr.c into module `a4091` (C4-2 v3 §8, C4-5 v3): the chip-visible statics move to one 1328 B
dma_alloc area (SCRIPTS, DSA table, ident/CDB/status/msg, the 1040 B bounce), the data address armed with dma_addr(r, pa);
autocon over zorro:0202:54, c0de:01, c0de:02, up to four boards; polled, rank zorro, _halt = a4091init per board. modcheck
ok on k46.1.2 (5324 B, 00469cdf) and k30.1.2 (4316 B, 856823d6); k30 _load returns ENOMEM until S4-62 piece 2. Static objects
unchanged (030 b5042e96, 040 c9f0e467, --d42 7d75ab42). Not yet run on any kernel (needs kern46m -78's symbol block).

## 2026-10-13 — Publication scrub before the first push since August (05dffa2)

NOTICE and README carry the Amiga Corporation trademark wording and point at amigaux.org/about/ instead of an
internal file (the 2026-09-26 "before any push" to-do below is done). Docs and tools: evidence paths, report ids,
letter numbers and process wording made generic; README names the sibling repos the 040/060 build expects.
Objects unchanged (030 b5042e96, 040 c9f0e467, 040 --d42 7d75ab42).

## 2026-10-05 — A4-24: re-arm the bus reset after a stuck command (a0c99a6)

A4-24: after a stuck command (poll-bound timeout, or err_phase with the target still holding BSY, e.g. a 512-byte dd
against a 2048-byte CD unit) the driver re-arms its once-per-card SCSI bus reset, so the next command clears the bus
instead of the card staying wedged; counter a4091_rearm_n. Objects 030 b5042e96, 040 c9f0e467, 040 --d42 7d75ab42.

## 2026-10-04 — D42 on metal: defensive today, load-bearing after B2; d42wcell (9f6a5ab..cdfbfbb)

D42 on metal: the verdict is "defensive on the Z3660 today" (SNOOP, write-through staging, bp_map push) with the
conditions that make it load-bearing; tool src/d42wcell.c; the 68040/68060 arm carried a root filesystem on an
A4092.

## 2026-10-03 — A4-21/A4-22/A4-23, the A4000T onboard-710 note, D42 on metal (062e514..eaaa66f)

A4-21: the "A4091 slow" print is gated on a poll threshold (a4091_slow_poll; a4091_maxpoll high-water). A4-22: one SCSI
bus reset per card before its first command, closing the ROM-driver SYNC hazard (a4091_busreset_n/_to). A4-23: unsigned
manufacturer shift in support.c.patch (stock autocon never matched ids >= 0x8000). Docs: the A4000T onboard-710 design
note (T0 series: an uninitialised 53C710 window hangs the CPU under the Z3660; presence = declaration + ROM initialisation;
T0b decoding with the lane rule, the SXFER byte and the pass criteria); D42-CALL-SHAPE metal section: the DMA_WIP CPLD
asserts SNOOP, so DMA into Z3660 RAM is read-coherent in hardware and only the write half can show the seam; A1 GREEN on
metal with a byte-exact 32 MiB compare against host truth and the control arm.

## 2026-09-29 — A4-18/A4-19: the 040/060 bounce; A4-20 docs

The 040/060 arm bounces any misaligned FROM_DEVICE read ≤ 1 KB (GSIO iobuf, dd sense) through a static
16-aligned buffer and copies out after dma_complete; a longer one is refused (bounce_toolong). Counters
bounce_n/bounce_toolong in the kstat block, magic "A4K2" (A4-18). The service is handed the bounced range with a
length rounded up to 16 bytes and the bounce is zeroed before prepare, so edge_shared == 0 holds by construction and a
no-data command copies out zeros (A4-19; objects stub 4641f912, --d42 e07c7619; 030 byte-identical). Docs: the 64 KB
GSIO patch is 030-only; stock iobuf has no alignment guarantee (A4-20).

## 2026-09-29 — the D42 contract, the chipset gate, the card-order fact

support.c.patch detects AGA by the Agnus id low nibble (NTSC ECS is not AGA; found by the amix-gayle-ide review). The 040/060 arm follows the D42 contract agreed upstream (`dma_prepare`/`dma_complete`, `struct dma_rec`, "DMAR", 0x60, `edge_shared`; the GSIO/sense alignment answer in docs/D42-CALL-SHAPE.md). README: root on the A4091 is an A4000 shape; on an A3000 the A4091 is card 1.

## 2026-09-29 — support.c.patch: AGA by the Agnus id low nibble (NTSC ECS is not AGA)

The chipset gate tested `id >= 0x22`, which misread an NTSC ECS Agnus (0x30) as AGA and would skip an NTSC A3000's internal SCSI probe (losing its root). It now tests `(id & 0x0F) >= 2`. Found by Emre Bastuz's amix-gayle-ide review; the same fix landed in kerntools' W-D7 probe (KT-09b) and amix-z3660scsi (ZS-03).

## 2026-09-28 — A4-11: the 040/060 arm

a4091-wr.c gains the 040/060 arm behind -DA4091_KVA (dev_kvmap NCS register pages, autocon via sdcardbase(), D42 record + local stubs, U77 byte-write probe off by default); the 030 build is byte-identical. tools/build-a4091-040.sh builds and gates the object (a4091_040.o c869795f, scan060 CLEAN, G2 2/2). docs/D42-CALL-SHAPE.md is the DMA call-shape proposal sent to the upstream port author. Built, not yet booted.

## 2026-09-26

- **Legal + NOTICE: the Amix release restriction is lifted** (`2008597`). README no longer describes
  Amix as unlicensed abandonware; it records Amiga Corporation's approval (Mike Battilana, 2026-09-19,
  confirmed 2026-09-23) and the owner's ruling. The four patches carry 160 verbatim stock lines (135
  context + 25 replaced), Commodore/AT&T-USL-derived and not under this repo's MIT licence. New
  `NOTICE` lists the four provenances: the MIT original work, the stock patch context, the NetBSD
  ncr53cxxx notice behind `reference/scripts/*.out`, and the per-file licences of the git-ignored
  a4091-software checkout. Before any push: the README's citation of the workspace CLAUDE.md is
  replaced by the amigaux.org disclaimer page.

## 2026-09-01

- **docs: README, `reference/a4091-study.md` and the sample configs brought up to the shipped
  state** (`bf389b5`, `75938db`, `486f602`, `1de3759`). README's last content commit was `fd7c852`
  (2026-07-08) — one day before the first of four undocumented kernel-patch changes landed — so it
  under-reported the repo in four ways, all now fixed. `src/kernel-patches/` ships **four** patches,
  not two: `a3091.c.patch` (`e70c1d7`) and `a2091.c.patch` (`791a117`) were invisible in the layout
  table and are now listed with their targets and with the fact that they fix latent defects in
  **stock** Amix. "What works" stopped at the 2026-06-05 universal-kernel milestone and now covers
  the tape DATA_IN phase-mismatch / filemark recovery (`e2976aa`), the GSIO iobuf 1 KB → 64 KB
  enlargement that unblocked the cdfs optical reads (`fd7c852`), the two stock-driver WD33C93 fixes
  (`791a117`, `be2f5e3`), and A4092/A4770 support, which shipped in `0a0b436` but was never claimed
  anywhere a reader would see it. Build & run step 2 told the reader to hand-apply exactly **one**
  patch, so anyone following it under-patched their kernel and inherited the a3091 cross-unit
  DMA-bounce defect; it now describes the amix-kerntools kpatch pipeline that applies all four
  (verify-then-apply against a vendored pristine stock tree, content-derived revision stamps) and
  keeps a labelled hand-apply fallback listing all four target paths. Smaller corrections:
  `amixsync.py push` takes `<local> <remote>`, not one argument; the Status table gains CD/optical,
  tape and A3000-multi-target rows; the closing paragraph describes the two-register anti-alias
  probe instead of its superseded single-register form; the Amiberry version the sample configs were
  captured on (8.1.6) is stated for the first time; and Legal now reads "the original contribution
  plus only the minimal diff context a patch needs" — the four patches carry ~152 verbatim stock
  context lines, so the old absolute claim was falsifiable in thirty seconds.
  `reference/a4091-study.md` gains a header framing it as archived 2026-06 research notes written
  against the `src/a4091.c` detection driver and superseded by `a4091-wr.c`, loses its three
  conversational preambles, and is now listed in the README layout table. The eight sample `.uae`
  configs no longer carry `amiberry.soundcardname=AD104 …`, the capture machine's audio hardware.

## 2026-08-08

- **kernel-patches: start-queue lifecycle fixed across disconnect/reselect — `a3091.c.patch` +
  `a2091.c.patch` revised** (`be2f5e3`). Latent since STOCK in both WD33C93 drivers (a2091.c is
  the template); found 2026-08-07 by instruction-level analysis during the P5.4 cdfs root-cause
  hunt. DFA case 2 requeues a preempted unit on the start queue and falls into case 3, which
  resumes it WITHOUT unlinking — the drained unit's stale queue link survives and the next
  `startany()` derefs a NULL `comhead` → garbage `device->sac` → wild DMA. Second shape found
  en route: `uqueue()`'s unconditional `up->next = 0` truncates the queue when re-linking an
  already-linked unit. Fix (both drivers, lockstep): new `unqueue()` on reselect-resume restores
  "linked on the start queue XOR active on the chip"; `uqueue()` refuses to double-link;
  `startany()` skips drained entries. Disjoint from the 07-21 per-unit bounce fix. Validated:
  `-F0` clean vs both stock trees, warning-parity cross-compile, relsim 0, **bench-smoke --deep
  PASS 7/7** through the patched-a3091 root path (doubling as the 07-21 regression proof), and
  the July repro's cross-unit dd+cp soak clean (10/10 sums identical, no panic). No before-arm
  repro (the interleave is not deterministically forceable on the bench) — structural argument +
  clean after-arm. kpatch re-applies automatically via the content-derived revision stamp. Metal
  A3000 re-run owed whenever such a session happens.

## 2026-07-21

- **kernel-patches: per-unit DMA bounce state — `a3091.c.patch` rewritten + `a2091.c.patch`
  (new). Fixes cross-unit disconnect/reselect aliasing.** (`791a117`) The chip-mem DMA bounce
  kept its in-flight buffer pointer + byte count in single **file-static** (a3091) / **per-card**
  (a2091) state, but both WD33C93 drivers are multi-target: they run a disconnect/reselect DFA
  and already keep the saved SCSI transfer count **per unit** (`units[].tc0/tc1/tc2`) precisely
  because targets interleave on the bus. `stopdma()` copies `dma_tc` bytes from `chipaddr` to
  `curunitp->comhead->addr + nbyte − dma_tc`; when a reselect flips `curunitp` between `units[]`
  while the shared bounce state still names another unit, source/destination/length stop
  describing one unit → the copy-back lands outside the target buffer → stray write
  (`hat_pt2ptdat` panic / `User BUS ERROR`). Reproduced by `dd if=/dev/rdsk/c5d0s1 of=/dev/null`
  (unit 5) looped while `cp` writes DH0 (unit 6); either stream alone is clean. The fix moves the
  bounce buffer pointer + byte count into per-unit `struct unit` (mirroring `tc0/1/2`), so
  `stopdma()` reads source, destination and length all from one unit through `curunitp` — no
  reselect can cross them — and replaces the per-DMA interrupt-context `AllocMem`/`FreeMem` with
  a **persistent per-unit chip buffer** allocated once in `initialize()` (`BOUNCESZ` = one
  68030 page; a guard panics rather than overrun). The `≥0x1000000` bounce trigger and chip-RAM
  semantics are unchanged. Proven on the bench (kernel rebuilt with the fix, sum-r 42265):
  the exact cross-unit repro runs clean — no panic, byte-integrity `bad=0` across all completed
  transfers. `a2091.c.patch` applies the identical fix to the reference template (same latent
  defect for ≥16 MB buffers); **build-validated only** — a2091 is not exercised on the current
  bench (no emulated A2091 card). Both apply cleanly to stock Amix 2.1 and cross-compile clean.
  (Note: this corrects a real latent aliasing defect; how much it vs. the concurrent 8 MB
  bench under-provisioning drove any specific originally-observed crash is entangled — the fix
  is correct on its own terms and the cross-unit repro is clean with it.)

## 2026-07-13

- **kernel-patches: `support.c.patch` — WD33C93 probe hardened against an open-bus alias**
  (`adf3875`). The chipset-gated A3000 SCSI probe wrote 0x55 then 0xAA to the **same** WD33C93
  register (0x02) and read each back. Amiberry's open bus at `0xDD0000` echoes writes (per-address
  latch), so the readback always matched → false positive on ECS even with `scsi_a3000=false`. That
  synthesized a phantom A3000 at `0xDD0000`; `sd.c` `init()`/`insert()` sorts cards by base address
  (`0xDD0000 < 0x40000000`), pushing the A4091 to card1. The floppy install kernel's disk scan
  (`open c6d0s0` = card0/unit6) then dispatched target 6 to the non-existent A3000 (`a3091queue`)
  instead of the A4091, so the blank A4091 install target at SCSI id 6 (really `c14d0s0`) reported
  **"No hard disks are attached."** Fix: a **two-register anti-alias** probe — write 0x55 to reg
  0x02 and 0xAA to reg 0x03 through the shared data port, then re-select reg 0x02 and read. A real
  WD33C93 keeps the registers distinct (reg2==0x55); a per-address open-bus latch holds only the
  last write to `0xDD0043` (0xAA), so reg2 != 0x55 → absent. **Correct on metal with no metal
  behaviour change** (A3000 detected, A4000 skipped via the VPOSR gate, A2500/ECS-without-SCSI
  absent): it removes only the emulation false positive, so the ECS install config also resolves the
  A4091 as card0. End-to-end validation still owed — rebuild the `fd0unix` kernel (kerntools) and
  re-run the ECS install config. (Because this marker cannot distinguish the patch revisions, the
  kerntools `.kprev` revision stamp is what re-establishes an old box from pristine stock.)

## 2026-07-10

- **kernel-patches: `a3091.c.patch` — chip-mem DMA bounce for the A3000
  internal-SCSI super-DMAC (fixes the a4091+cdfs boot panic).** The A3000 onboard
  SCSI driver `amiga/alien/a3091.c` (super-DMAC + WD33C93 @ 0xDD0000) programmed the
  caller's full 32-bit Fast-RAM buffer address straight into the DMAC
  (`device->sac = cp->addr`) with no bounce — unlike its A2091-card sibling
  `a2091.c`, which bounces any buffer ≥ `0x1000000` through `AllocMem(MEMF_CHIP)`.
  The super-DMAC cannot reach an arbitrary high Fast-RAM address, so once the kernel
  grew (adding the in-kernel `cdfs` filesystem, ~64 KB) `getrdb()`'s static RDB
  buffer (`union block` in `sdpart.c`) moved past the DMAC's reach: the root-device
  read returned all-zeros → `sdopen()` ENXIO → `s5mountroot VOP_OPEN error 6` /
  `PANIC vfs_mountroot errno 30`. Root-caused by an Amiberry-savestate differential
  (booting golden vs panicking cdfs kernel: `queue[0].f` populated in both, but the
  RDB buffer held a valid `UNIX_Root` PART block in golden vs all-zeros in the
  panic). Fix ports a2091's bounce into a3091: for buffers ≥ `0x1000000`,
  `AllocMem(cp->tc, MEMF_CHIP)` a chip scratch, copy caller→chip before a write /
  chip→caller after a read, `FreeMem` in `stopdma` — the direct (low-address) path
  is unchanged. Shipped as a `patch -p0` diff (target `amiga/alien/a3091.c`).
  **Proven on-box (2026-07-10):** with it the a4091+cdfs kernel boots warm AND cold,
  `cdfs` registers live (`sysfs(GETFSIND,"cdfs")==12`), and `mount -F cdfs 1,3
  /cdrom` reads a genuine Rock Ridge CD byte-exact (on-box `sum` == host `sum -s`;
  UTF-8 names, long names, symlinks, multi-level paths). NB: characterizing the
  super-DMAC's exact reach limit (to raise/remove the ≥ 16 MB bounce threshold) is a
  follow-up.

## 2026-07-08

- **kernel-patches: `scsi.c.patch` — enlarge the GSIO passthrough bounce buffer
  1 KB → 64 KB.** `gsioctl()` in `amiga/alien/scsi.c` bounces every `/dev/scsi`
  GSIO transfer through a single static `iobuf[]` and rejects `nbyte > sizeof
  iobuf`; at 1024 bytes a 2048-byte CD-ROM READ(10) data block cannot pass,
  blocking any CD/optical-filesystem GSIO consumer. Grow `iobuf` to 65536 so a
  2048-byte block and multi-sector chunks fit in one GSIO call, with both existing
  guards kept (the `nbyte % DMA_GRANULARITY` alignment check — DMA_GRANULARITY is
  4, and 2048/65536 are multiples; and the `nbyte > sizeof iobuf` bounds clamp,
  now 64 KB). Static kernel BSS only — no allocation path, real-HW-safe. Shipped as
  a `patch -p0` diff (target `amiga/alien/scsi.c`); the kerntools patch-application
  wiring is a separate change. **Proven on-box (2026-07-08):** in a native-built
  a4091 kernel (with this patch) under Amiberry-A4091, the `amix-cdfs`
  SCSI-passthrough backend reads a genuine 2048-byte CD end-to-end —
  `imgls`/`imgcat`/`imginfo` byte-exact vs host, including a multi-sector
  (102000-byte / 50-sector) read across the 32 KB chunk boundary, plus Rock Ridge
  long names, symlinks, and multi-level paths.

## 2026-07-06

- **a4091-wr: real SCSI tape-read support — DATA_IN phase-mismatch / filemark
  recovery.** The a4091 SCRIPTS previously assumed the target transfers the exact
  requested DATA_IN byte count and then STATUS; a tape short-read at a filemark
  (the target enters STATUS phase early) produced a phase mismatch mid-MOVE that
  the rc ladder reported as "SCSI timeout". Now a DATA_IN phase-mismatch interrupt
  reads the residual (DBC), drains the SIOP FIFO (ORF/OLF, per `siop.c`),
  re-dispatches the SCRIPTS to read STATUS + MSG_IN via a new MSG_IN case, and
  returns `okay = TRUE` with the real target status (including CHECK CONDITION) and
  the short byte count — so the `ct` driver runs its normal REQUEST SENSE /
  File-Mark / EOF handling. Tapes read cleanly across filemarks; a full
  multi-package install from tape completes with zero a4091 I/O errors. Real-HW
  correct (matches how real tapes short-read at filemarks); disconnect/reselect
  remains deferred (real-metal only).
- **a4091-wr: bounded-poll completion + gated 53C710 diagnostics.** Replace the
  single ISTAT read (which assumed instantaneous target completion) with a bounded
  poll loop — needed for real-HW non-instant completion, harmless under emulation —
  and add gated 53C710-register diagnostics for tape-read debugging.

## 2026-06 — initial public release

The changelog itself starts at 2026-07-06 (`09f4226`); this section backfills the milestones that
came before it, `17c635f` (2026-06-03) through `e98b997` (2026-06-24).

- **Zorro III reached from an SVR4 68030 kernel** (`65b449d`, 2026-06-03). The A4091 lives at
  physical `0x40000000`, inside the unmapped gap between the 68030's two transparent-translation
  windows, so a stock Zorro II driver cannot touch its registers. The driver page-maps the board
  with `sptalloc(1, PG_V, phystopfn(base), 0)` instead (`a4091-wr.c`:203-204); DMA still lands in
  low RAM, so bus mastering is unaffected.
- **A real 53C710 SCSI transaction, then a block device** (`f219049`, `40e4bce`, `6c1cbfd`,
  2026-06-04). Table-indirect SCRIPTS identify the disk behind the card; then `READ(10)` end-to-end
  to `/dev/dsk/c8d0s0` through a generic `a4091queue`; then `WRITE(10)` — one SCRIPTS program doing
  both by dispatching on the live SCSI bus phase. `mkfs ufs` + `mount` follow (`e058037` era): the
  A4091 disk is a fully usable Amix filesystem, files persist across boots.
- **Root, swap and filesystem on the A4091** (`e058037`, `7299271`, 2026-06-04/05). The "can't boot
  from the A4091" panic was a device-*dispatch* bug, not a driver bug: a phantom A3000 SCSI,
  hardcoded whenever RAM > 7 MB, stole card 0 and sent the root read to hardware that was not there.
  With it fixed, Amix boots to multi-user login in ~160 s including fsck, with the A3000's own SCSI
  switched off.
- **The D245 boot-breaker root-caused** (`7299271`, 2026-06-04). Relinking the Amix kernel under
  emulation hits an intermittent (~70%) `ld` write corruption that Guru-Meditates the bootstrap
  relocator — not the poll-loop bug and not the relocator bug the first two hypotheses claimed. The
  amix-kerntools clean-gate defeats it by relinking until the output checksum recurs. This one bites
  anyone who relinks an Amix kernel, A4091 or not.
- **One universal auto-detecting kernel** (`1190fd2`, 2026-06-05). The same binary boots an A3000 on
  its own WD33C93 with the A4091 coexisting as a second card, and an A4000 + A4091 with root on the
  A4091 — a chipset gate (VPOSR) plus a WD33C93 probe in `autocon()`, not a hardcoded assumption.
- **Public release** (`0a0b436`, `e3a3276`, `f8e0da8`, `e98b997`, 2026-06-24). MIT licence in plain
  form so GitHub detects it; kernel changes shipped as patches only, with the `sd.c` rows and
  Makefile `OBJ` entries generated by kerntools from `driver.conf` rather than shipped; private lab
  data scrubbed and the lab notebook untracked; and `driver.conf` gains the A4092 (`0xc0de0001`) and
  A4770 (`0xc0de0002`) identities beside the A4091's `0x02020054`, answering the A4092 developer's
  2026-06-22 request.
