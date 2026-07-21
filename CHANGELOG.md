# Changelog

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
