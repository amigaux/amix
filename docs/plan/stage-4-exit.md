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
| ABI kit (DDI 1.2, `abi=2ab48658…` from 0572fcf) | pending | pending |
| z3660scsi | pending | pending |
| A4091/A4092 | pending | pending |
| the A4000T 53C710 | pending | — (no A4000T on this line) |
| Gayle IDE | pending (gayle 1.1.0-1 passes its rows, a12120b; the bytes of record at the exit) | pending (as k46) |
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

## 2a. The first root-class boots (S4-72-1, S4-73)

| Row | k46 | k30 |
|---|---|---|
| a root reached through a module: z3660scsi placed by boot2 (loader version 3), linked in `marc_root`, the root mounted through it | **PASS** — N103r (`tmp/2026-10-26-s4-72-1/cell-r/N103`): kern46m -77, kabi `k46.1.2`; boot2 `module z3660scsi 12988 bytes`; `kbootset status` `module z3660scsi (root): loaded`; `/` on `c6d0s1` | **PASS** — N104r (`tmp/2026-10-26-s4-73/cell-r/N104`), S4-73: kern30m -12, kabi `k30.1.2`; the same lines; z3660scsi linked at 0x081098a0 in the arena; `/` on `c6d0s1` |

The rig's own verdict on both cells reads `FAIL (b1:lifecycle)`. That is
its stale-mark check (the slot's image carried an earlier run's
`/etc/rig-lifecycle.mark`, `want 'none'`), not the row: both boots
mounted their root through the module and the second boot read back the
first's mark. The first run, N103, failed on the arena's 8-mod-16
alignment (fixed in a829c44, C3-3 version 5).

## 3. The emulator rows (S4-72; 80 §2)

| Row | k46 | k30 |
|---|---|---|
| M-SD1, one row per emulated board set of record (30 §5.3), judged against its expectation; on k46 including the no-Z3660 sets (A3000 onboard alone and + A4091/A4092 (renamed: `c6d0` → `ced0`), A4091/A4092 alone, Gayle IDE + A4091/A4092, the A4000T 53C710 alone and + A4092) | pending | pending |
| M-FL2 safe mode on each root controller and root filesystem | pending | pending |
| root on ufs as a module | pending | pending |
| root on s5 as a module | pending | pending |
| cdfs as a boot-class module (C4-6 §5) | pending | pending |
| a damaged root module selects the menu | pending | pending |
| L5 arena overflow (a backstop: gate 4 refuses first); an unmatched root entry skipped silently by the core (L7 retired, C4-4 v3) | pending | pending |
| `sd_register` after sd's first open: `EBUSY` and a console line | pending | pending |
| a failed root-class `_load` leaves the kernel as it was | pending | pending |
| the deferred self-test point (S4-05): Gayle IDE leaves polled | **PASS** — N111 (kern46m -80, `intr=1`: the READ VERIFY self-test passed, 32 755 interrupts, 0 spurious); repeated over three halt and reboot cycles (N115) and in safe mode (N116); amix-kerntools a12120b | **PASS** — N117 (kern30m -15: 27 706 interrupts); N121 (halt and reboot), N122 (safe mode); a12120b |

## 4. The media (S4-50–S4-56; 50)

| Row | k46 | k30 |
|---|---|---|
| S4-50 the installer on a RAM-disk root | pending | pending |
| S4-51 M-CD1 bench half: CD boot, install and rescue on the A4091 ROM | pending | pending |
| S4-52 the floppy pair: M-FP1 again (fit), boot, install, rescue | pending | pending |
| S4-53 the netinstall medium: form A or B, M-NET1c, M-NET1e, M-NET1f | pending | pending |
| S4-54 the upgrade install, from a 1.1 disk and from a 1.0 disk | pending | pending |
| S4-56 disk and SD images with rescue; tape as a package source | pending | pending |
| S4-57 the generic 060 target, emulated: an A3000 with a 68060, an A4091 root and a ZZ9000 in Zorro II; an A4000 with a 68060, an A4092 or Gayle IDE root and a ZZ9000 in Zorro II; each from its pre-installed image through the first-boot dialog | pending | — (a 68060 target) |

## 5. The measurements (S4-70, S4-71; 90)

| Row | k46 | k30 |
|---|---|---|
| M-MOD1 again: the root set and the arena | pending | pending |
| M-FL1 the floor kernel's size | pending | pending |
| M-FS1 the carve and the rebuilt base | pending | pending (the relink kit's separation) |
| U3 execution from `.data` through ITT0 (mapping) | pending | — (U3 is the 040/060 line's, 30 §8) |
| U12 `vfssw` walkers read `nfstype` live | pending | pending |
| M-RD1 the shortened `memory[]` region honoured | shown (installng rd1h on kern46m -81: the image at 0x9E00000, Available memory 2 MiB below Total; amix-installng bd1baf2, 29c1da8, 1ace7d5); the Bench's row pending | shown (rd1h on kern30m -16, the same lines); the Bench's row pending |
| M-RD2 the root selector: sd cards 0–3, the RAM disk, `swap none` | the RAM disk shown (rd1h: `RTH1: root ramdisk (b 20,0) from the loader record, swap /dev/fakeswap, rootfstype ufs`, to the installer's interview); the Bench's row pending | the RAM disk shown (rd1h: rootfstype s5, to the interview); the Bench's row pending |
| M-HALT1, the bench half | pending | pending |

## 6. The plan's rows

| Row | Status |
|---|---|
| C4-1 … C4-6 the interfaces | **agreed**: C4-1 v3, C4-2 v3, C4-3 v1 (agreed with S4-11), C4-4 v5, C4-5 v5, C4-6 v2 |
| S4-01 … S4-08 the core | built (core patches 0029–0043; state harness 257/257 on both kernels); their bench halves are rows above |
| S4-10 … S4-12 loader and `kbootset` | built: S4-10 (placement), S4-11 (the RAM-disk image, 4003c9f: file 28 646, image + bss 28 420 of 28 672), S4-12 (composition); M-RD1/M-RD2 shown on both lines (rd1h), the Bench's rows pending |
| S4-22, S4-23 the root-class kernels | pending |
| S4-24 the 1.0 families retire | pending |
| S4-25 packages | pending |
| S4-30 … S4-34 the root-class modules | S4-30 z3660scsi: **PASS** both lines (N103r, N104r, §2a). S4-31 the A4091/A4092: **PASS** both lines (N105/N105b, N106 on k46; N109/N109b on k30; E6b on -15, N110). **S4-32 Gayle IDE: PASS** both lines in emulation (amix-kerntools a12120b: N111a–N116 on kern46m -80, N117a–N122 on kern30m -15, gayle 1.1.0-1: the IDE root alone polled and with interrupts, the k46 interrupt path's first run with the READ VERIFY self-test passing, IDE + Z3660 with the IDE as card 1, the A3000 ECS row's silent ENXIO, the ATAPI slave, halt and reboot with interrupts, safe mode); the CD check of record (`mount -F cdfs`) with gayle 1.1.0-2 and metal pending. S4-33 the A4000T 53C710: pending. S4-34 the ramdisk: shown (rd1h, M-RD1/M-RD2) |
| S4-40 … S4-43 the filesystems and the kernels without them | pending |
| S4-62 the DDI 1.2 DMA providers | built: k46 (0e4c34f, 01024f5), k30 (e9665e6: the pool, the bounce, the force-bounce hook). **k46 PASS**: N105/N105b, the first A4091 root-class boot (kern46m -78, a4091 1.0.0-1; `cp` and `sync` clean through `dma_alloc` memory; amix-kerntools d1a2e3c), and N106, two root modules ranked with the A4091 root as card 1 (1653ea3). **k30 PASS**: N109/N109b (E6), a4091-k30 1.0.0-3 rooted on the A4091 alone on kern30m -14, the pool at 0x7FDF800, a raw read and `cp`/`sync` identical under `dma_forcebounce` 0 and 1; the entry-0 decode read live, the identity map cacheable (C4-5 v6 §5.3); amix-kerntools c326ccb. E6b (the pool-miss path) is reachable only through `dma_forcefail`: pending on kern30m -15 |
| S4-63 C3-6 §1, the register-write rule | pending |
| S4-71 the root context (C4-2 §2) | the probe and its row defined (c2dc7fb, `tests/bench/s4-71`). **k46 PASS**: N107 (kern46m -78; every call at level 7 with the clock stopped, `bprobe` of a decoded address 0 and of an unheld one 1, the fault caught; amix-kerntools 1653ea3): C4-2 §2's list stands on k46. **k30 PASS**: N108 (kern30m -14; every call at level 7, the fault caught, and `dma: pool 128 KiB at 0x7FDF800` on the console; amix-kerntools c326ccb): C4-2 §2's list stands on both lines |
| S4-73 exit row | **PASS** k30 — N104r (§2a) |
| S4-74 metal: the A4000D and the cardless A4000T (root controllers, M-A4T1, M-DMA1, M-HALT1, U3's cache half, root filesystems, M-FP2, M-NET1g) | pending |

## 7. What remains (2026-10-27)

- **E6b on kern30m -15**: the A4091's do-not-arm path, driven through the
  `dma_forcefail` hook (C4-5 v7), with the force-bounce exemption of
  dma_alloc memory (v8). S4-71 and the A4091 rows passed on both lines
  (N107, N108; N105/N105b, N106, N109/N109b).
- **The k30 module rows on kern30m -14**: the 030 DMA pool's console line,
  the module set of record.
- **cdfs, S4-42**: the module (amix-cdfs ef96470) with its page-shift
  waivers (8fc87de), boot class on disk and promoted to root on the CD
  (core 0043); U12 with its first mount.
- **The Bench's formal M-RD1 / M-RD2 rows** on the installer medium rd1h:
  shown on both lines by installng (rd1h on -81/-16: placement, `memory[]`
  honoured, the `ramdisk` root on `/dev/fakeswap`, to the installer's
  interview), the Bench's rows after the Gayle rows.
- **The rest of §1–§5's cells** (the bytes of record, the media, the
  filesystems as modules after S4-40/S4-43, the measurements) and S4-74
  on metal.
- **The stage-5 carries** below.

## 8. kabi 1.2 closes with the stage

kabi 1.2 (k30.1.2, k46.1.2) is the stage-4 minor. **It closes when stage
4 exits**, in the exit commit: from then `abi/<line>/abi-<line>.1.2.txt`
and the 1.2 names of `ddi.list` are frozen, and any DDI name added or
fingerprint line changed after it is **1.3**. Until the exit, 1.2 takes
the stage's additions, and kernels cut on an earlier 1.2 text carry its
hash: `fea18182…` for the 1.2 cuts before 0572fcf (kern46m -77, -78;
kern30m -12, -13; the 1.1 cuts -71 and -10 had the same text), and
`2ab48658…` from 0572fcf (kern46m -79, kern30m -14 and later). A module
built for 1.2 loads on any 1.2 kernel whose symbol block has the names it
imports; the exit's re-cut of record carries the final 1.2 text.

**Carried to stage 5, not cells here (Q4-5):** S4-60, the 030 line on the
1.1 release firmware; S4-61, the A4000T's Zorro-dependent rows after its
repair (an A4092 root, CD boot on metal, the second bus), with the
A4091/A4092 module's metal and M-DMA1 rows.
