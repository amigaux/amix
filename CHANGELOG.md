# Changelog

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
