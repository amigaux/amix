# Stage 4 — the exit ledger

80 §2 lists what stage 4 must prove, and 80 §3 what it must not break:
every disk is named as the card-number gate of 30 §5.3 expects for its
board set. This ledger gives, per line, the bytes of record and every
row's result. The stage closes in one commit, when no cell below is empty
or pending. A row's result is PASS or FAIL with its evidence (a Bench run
id), or a number for a measurement. The plan is `docs/plan/stage-4.md`.

## 1. The bytes of record

| What | k46 | k30 |
|---|---|---|
| kernel (the root-class kernel, S4-21 / S4-22) | pending | pending |
| its core (`core/series`, `dlm_maximage`) | pending | pending |
| kinfo | pending | pending |
| kernel package | pending | pending |
| loader (boot2, its size under 28 672) | pending | pending |
| kbootset | pending | pending |
| modadmin | pending | pending |
| ABI kit | pending | pending |
| z3660scsi | pending | pending |
| A4091/A4092 | pending | pending |
| Gayle IDE | pending | pending |
| ramdisk | pending | pending |
| the A4000T 53C710 (if its driver exists, S4-33) | pending | — (no A4000T on this line) |
| z3660eth, z3660rtg, monsw (carried from stage 3) | pending | pending |
| apkg | pending | pending |

## 2. The first stage-4 cut and media (S4-20, S4-55)

| Row | k46 | k30 |
|---|---|---|
| S4-20 the cut: 0027/0028, the ZS-05 static drivers | pending | pending |
| S4-55 the first stage-4 media, one cell | pending | pending |

## 3. The emulator rows (S4-72; 80 §2)

| Row | k46 | k30 |
|---|---|---|
| M-SD1, one row per emulated board set of record (30 §5.3), judged against its expectation | pending | pending |
| M-FL2 safe mode on each root controller | pending | pending |
| a damaged root module selects the menu | pending | pending |
| L5 arena overflow; L7 no root module matched | pending | pending |
| `sd_register` after sd's first open: `EBUSY` and a console line | pending | pending |
| a failed root-class `_load` leaves the kernel as it was | pending | pending |
| the deferred self-test point (S4-05): Gayle IDE leaves polled | pending | pending |

## 4. The measurements (S4-70, S4-71; 90)

| Row | k46 | k30 |
|---|---|---|
| M-MOD1 again: the root set and the arena | pending | pending |
| U3 execution from `.data` through ITT0 (mapping) | pending | — (U3 is the 040/060 line's, 30 §8) |
| M-RD1 the shortened `memory[]` region honoured | pending | pending |
| M-RD2 the root selector: sd cards 0–3, the RAM disk, `swap none` | pending | pending |
| M-HALT1, the bench half | pending | pending |

## 5. The plan's rows

| Row | Status |
|---|---|
| C4-1 … C4-4 the interfaces | pending |
| S4-01 … S4-08 the core | pending |
| S4-10 … S4-12 loader and `kbootset` | pending |
| S4-21, S4-22 the root-class kernels | pending |
| S4-23 the 1.0 families retire | pending |
| S4-24 packages | pending |
| S4-30 … S4-34 the root-class modules | pending (S4-33 contingent on its driver) |
| S4-50 … S4-54 media and the installer (bench cells; the proof is stage 5's) | pending |
| S4-60 the 030 line on the 1.1 release firmware | pending |
| S4-61 the A4000T's rows after its repair | pending |
| S4-62 the A4091's DMA reach on the 030 line | pending |
| S4-63 C3-6 §1, the register-write rule | pending |
| S4-73 exit row | pending |
| S4-74 metal: each root controller cold-booted on both boxes, M-A4T1, M-DMA1, M-HALT1, U3's cache half | pending |

## 6. Open, outside the Bench's sweep

- The stage-5 work started in stage 4 (`stage-4.md` §2.6, §2.7) is
  recorded here as it lands, but gates nothing in this ledger.
