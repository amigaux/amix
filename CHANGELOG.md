# Changelog

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
