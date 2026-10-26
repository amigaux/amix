# Stage 4 — the exit ledger

80 §2 lists what stage 4 must prove: root controllers, root filesystems
and every medium of 50 (changed after the freeze, 2026-10-26). 80 §3 lists
what it must not break: every disk is named as the card-number gate of
30 §5.3 expects for its board set, and safe mode reaches a shell on every
root controller and root filesystem. This ledger gives, per line, the
bytes of record and every row's result. The stage closes in one commit,
when no cell below is empty or pending. A row's result is PASS or FAIL
with its evidence (a Bench run id), or a number for a measurement. The
plan is `docs/plan/stage-4.md`. The rows carried to stage 5 (§6) are not
cells of this ledger.

## 1. The bytes of record

| What | k46 | k30 |
|---|---|---|
| kernel (root-class, no root filesystem; S4-22, S4-23, S4-43) | pending | pending |
| its core (`core/series`, `dlm_maximage`) | pending | pending |
| kinfo | pending | pending |
| kernel package | pending | pending |
| loader (boot2, its size under 28 672) | pending | pending |
| kbootset | pending | pending |
| modadmin | pending | pending |
| ABI kit (DDI v1.1) | pending | pending |
| z3660scsi | pending | pending |
| A4091/A4092 | pending | pending |
| the A4000T 53C710 | pending | — (no A4000T on this line) |
| Gayle IDE | pending | pending |
| ramdisk | pending | pending |
| ufs | pending | pending |
| s5 | pending | pending |
| cdfs | pending | pending |
| z3660eth, z3660rtg, monsw (carried from stage 3) | pending | pending |
| apkg | pending | pending |
| the media of record (disk and SD images, the floppy pair, the CD, the netinstall medium) | pending | pending |

## 2. The cuts and the first media (S4-20, S4-21, S4-55)

| Row | k46 | k30 |
|---|---|---|
| S4-20 the first cut: 0027/0028, the ZS-05 static drivers | built: -61, `cb2499f1…` | built: -04, `c0f69e0a…` |
| S4-21 the second cut: four-card sd/dd, `bdevsw` row 20 free | pending | pending |
| S4-55 the first stage-4 media, one cell | pending | pending |

## 3. The emulator rows (S4-72; 80 §2)

| Row | k46 | k30 |
|---|---|---|
| M-SD1, one row per emulated board set of record (30 §5.3), judged against its expectation | pending | pending |
| M-FL2 safe mode on each root controller and root filesystem | pending | pending |
| root on ufs as a module | pending | pending |
| root on s5 as a module | pending | pending |
| cdfs as a demand module | pending | pending |
| a damaged root module selects the menu | pending | pending |
| L5 arena overflow (a backstop: gate 4 refuses first); an unmatched root entry skipped silently by the core (L7 retired, C4-4 v3) | pending | pending |
| `sd_register` after sd's first open: `EBUSY` and a console line | pending | pending |
| a failed root-class `_load` leaves the kernel as it was | pending | pending |
| the deferred self-test point (S4-05): Gayle IDE leaves polled | pending | pending |

## 4. The media (S4-50–S4-56; 50)

| Row | k46 | k30 |
|---|---|---|
| S4-50 the installer on a RAM-disk root | pending | pending |
| S4-51 M-CD1 bench half: CD boot, install and rescue on the A4091 ROM | pending | pending |
| S4-52 the floppy pair: M-FP1 again (fit), boot, install, rescue | pending | pending |
| S4-53 the netinstall medium: form A or B, M-NET1c, M-NET1e, M-NET1f | pending | pending |
| S4-54 the upgrade install, from a 1.1 disk and from a 1.0 disk | pending | pending |
| S4-56 disk and SD images with rescue; tape as a package source | pending | pending |

## 5. The measurements (S4-70, S4-71; 90)

| Row | k46 | k30 |
|---|---|---|
| M-MOD1 again: the root set and the arena | pending | pending |
| M-FL1 the floor kernel's size | pending | pending |
| M-FS1 the carve and the rebuilt base | pending | pending (the relink kit's separation) |
| U3 execution from `.data` through ITT0 (mapping) | pending | — (U3 is the 040/060 line's, 30 §8) |
| U12 `vfssw` walkers read `nfstype` live | pending | pending |
| M-RD1 the shortened `memory[]` region honoured | pending | pending |
| M-RD2 the root selector: sd cards 0–3, the RAM disk, `swap none` | pending | pending |
| M-HALT1, the bench half | pending | pending |

## 6. The plan's rows

| Row | Status |
|---|---|
| C4-1 … C4-6 the interfaces | pending |
| S4-01 … S4-08 the core | pending |
| S4-10 … S4-12 loader and `kbootset` | pending |
| S4-22, S4-23 the root-class kernels | pending |
| S4-24 the 1.0 families retire | pending |
| S4-25 packages | pending |
| S4-30 … S4-34 the root-class modules | pending |
| S4-40 … S4-43 the filesystems and the kernels without them | pending |
| S4-62 the DDI v1.1 DMA providers | pending |
| S4-63 C3-6 §1, the register-write rule | pending |
| S4-73 exit row | pending |
| S4-74 metal: the A4000D and the cardless A4000T (root controllers, M-A4T1, M-DMA1, M-HALT1, U3's cache half, root filesystems, M-FP2, M-NET1g) | pending |

**Carried to stage 5, not cells here (Q4-5):** S4-60, the 030 line on the
1.1 release firmware; S4-61, the A4000T's Zorro-dependent rows after its
repair (an A4092 root, CD boot on metal, the second bus), with the
A4091/A4092 module's metal and M-DMA1 rows.
