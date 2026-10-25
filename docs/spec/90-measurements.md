# 90 — Measurements

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §8 (proof order: each stage proven on the emulator and on metal before the next), D-3 §1 ("tested under emulation and on both boxes like a driver"), D-3 §2 (emulation runs the same bytes as metal)
- **Evidence classes (P-28 D51):** **bench** = the emulator, or a host-side computation over the real build outputs; **metal** = real hardware. Bench decides hook state, memory, relocation, export diffs, the mouse-button read injected over the emulator's control channel, and the A4091-ROM half of ROM questions. Metal decides floppy-rooted boots, the Z3660-ROM half of ROM questions, cache and DMA behaviour, the HID converters, the A4000T onboard-controller probe, and every cold-boot row. Where both are listed, bench comes first and metal confirms.
- **Stage:** the proof stage of `80-stages-and-proof.md` that needs the result before it can exit (0 = needed to freeze this specification).

Earlier measurement ids from the research record are kept in brackets (U1–U18
from `tmp/2026-10-14-modules-study/STUDY.md:436-452`, U-N from
`tmp/2026-10-22-modules-proposal/medium-network.md:110-115`, T-U from
`tmp/2026-10-22-modules-proposal/tape-medium-design.md:258-267`). None of
U1–U18 has a result yet (`tmp/2026-10-22-modules-proposal/RESEARCH.md:360`).

## 1. Loader

| ID | Measurement | Class | Stage | Spec |
|---|---|---|---|---|
| M-LD1 | Which bootblock header fields (magic, checksum, trailer) the strap checks on a floppy and on an RDB `UNI\0` partition, per Kickstart version in use (3.1, 3.2.x) | bench (A4091 ROM, WD, Gayle, floppy) + metal (Z3660 boot ROM) | 1 | 10 §2.1 |
| M-LD2 | CD boot (D-3 §10): an `AMIGA BOOT` ISO boots AmigaDOS through the ROM's CD filesystem; `S/Startup-Sequence` runs `amix-cdboot`, which loads a kernel and miniroot from files and hands off; minimum Kickstart; memory left after AmigaDOS; no AmigaDOS activity (CD filesystem, device DMA, interrupts) survives the take-over | bench (A4091 ROM) + metal (A4092) | 1 | 10 §4.4, 50 §4 |
| M-LD3 | What the strap does when a bootblock returns a failure code (does Kickstart try the next boot node?) — **bench half, Z3660 boot ROM chain, 2026-10-25:** no; a recoverable alert AN_BootError (3000 0001), the ROM's BootPoint, then a reset, about every 14 s (S1-16, evidence in the workspace's tmp/2026-10-25-s1-16/); boot1 now stops instead of returning. Other boot ROMs and metal open | bench + metal (Z3660 ROM) | 1 | 10 §3.1 |
| M-LD4 | Writes through the strap's IOStdReq on each boot ROM: boot2's control-block write (try-once, one-shot) and boot1's tally-block write (loader trial), with read-back on the next boot | bench (A4091, WD, Gayle) + metal (Z3660 ROM, both boxes) | 1 | 10 §4.2, §7 |
| M-LD5 [U18] | Menu input: keyboard matrix, left/right mouse buttons and serial input at the menu window; through the HID converters on both reference machines; phantom key or button reads on a marginal card | bench (input injected over the emulator's control channel) + metal (HID path) | 1 | 10 §7.4 |
| M-LD6 | CPU probe gives the right answer on 68030, 68040, LC/full 68060, including a 68060 without SetPatch | bench (030, 040, LC060 models) + metal (real 68060) | 1 | 10 §3.2 |
| M-LD7 | CRC-32 and SHA-256 time over a 2 MB kernel on a 25 MHz 68030 and a 68060 (decides whether the loader checks SHA-256 too) | bench (upper bound) + metal (68060; 68030 per OQ-80.1) | 1 | 10 §5.1 |
| M-LD8 | Deflate vs LZW (`compress -b16`) ratio on K030-U-FD- and KD060-FD-class kernels and on a miniroot image; inflate time on a 68030 — ratio part measured 2026-10-25 on the 1.0 floppy kernels: deflate = 73 % (K030-U-FD) and 71 % (KD060-FD) of the LZW size (`docs/measurements/2026-10-25-m-net1.md`); decode time open | bench (host computation; decode timing on the emulator as an upper bound) | 1 | 10 §5.5 |
| M-LD9 | Cold boots of static kernels through our loader from every controller on both boxes, compared with the stock loader (root naming, devices, RTH1 line) | bench + metal | 1 | 80 §2 |
| M-FD1 | Floppy DMA into chip RAM under the 040/060 caches (DTT0 window) on a real floppy or Gotek | metal | 1 | 70 §2 |
| M-FP1 | Floppy-pair fit per line in the RAM-disk profile: compressed kernel + root-class modules + compressed miniroot + store overhead against two DD volumes — **static part closed 2026-10-25**: with the trimmed engine, k30 fits with 270 336 B free (15.3 %) and k46 with 212 992 B free (12.0 %); the full 1.0 engine misses the 5 % rule on both lines; the miniroot needs extents that span volumes (10 §4.3); evidence `docs/measurements/2026-10-25-m-fp1.md` | bench (host computation) | 1 (static), again 5 | 10 §4.3, 50 §3 |
| M-FP2 | Floppy-pair boot on metal, both lines (RAM-disk profile; fd0-root profile if chosen), including the volume change | metal | 1, again 5 | 50 §3 |
| M-EMU1 | The emulated Z3660 with the autoboot option (DIAGVALID advertised) boots our loader like metal | bench | 1 (prerequisite) | 50 §7 |
| M-RD1 | The kernel's memory sizing honours a `memory[]` region shortened by the loader (RAM-disk carve-out); the RAM-disk module maps the image | bench | 4 | 10 §5.4, 30 §7 |
| M-RD2 | The kernel half applies the loader record's root selector: an sd root on cards 0–3 (bit-7 encoding) and a RAM-disk root (block major 20); `swap none` boots without a swap device | bench | 4 | 10 §6, 30 §3, §5.2 |

## 2. Lifecycle

| ID | Measurement | Class | Stage | Spec |
|---|---|---|---|---|
| M-GEN1 | Generation size per line (kernel, root-class modules, boot/demand modules; compressed and not) | bench (host computation) | 2 | 40 §2.1 |
| M-GEN2 | `kbootset commit` time on a 68030 and a 68060 | bench + metal | 2 | 40 §3.2 |
| M-GEN3 | Power cut at each commit step (emulator killed; one metal row per box) leaves a booting generation | bench + metal | 2 | 40 §3.2 |
| M-GEN4 [T-U6, U-N7] | `kbootset` static binary size per line | bench (host computation) | 2 | 40 §3 |
| M-GEN5 | Upgrade, commit, mark-good, rollback, one-shot previous, try-once fallback on a trial that panics in `rc` | bench + metal (one row per box per line) | 2 | 40 §3, 10 §7 |
| M-UPG1 | Upgrade install of a 1.0 disk: configuration captured and restored, layout re-laid, first boot | bench + metal (one per box) | 2 | 40 §7 |
| M-SIG1 [U17] | Signature verification time on a 68030 and a 68060 — **deferred with signing** (D-3 §13) | bench (upper bound) + metal | — | 60 §5 |
| M-SIG2 | SHA-256 throughput on a 68030 and a 68060 (apkg, `kbootset check`) | bench (upper bound) + metal | 2 | 60 §3 |
| M-PKG1 [U11] | Files dropped by `pkgadd instance=overwrite`; stock `pkgadd` on `/stand` conflicts | bench | 2 | 40 §8 |

## 3. Module core and ABI

| ID | Measurement | Class | Stage | Spec |
|---|---|---|---|---|
| U1 | Status register and kmem state at `dmainit` and at the `marc_root` hook; whether `kmem_zalloc(KM_SLEEP)` is safe there | bench | 3 | 30 §3 |
| U2 | Free kernel virtual space for copied modules at 128 MB of RAM | bench | 3 | 30 §8 |
| U3 | Execution from the arena in `.data` through ITT0 on 040/060; cache class of module `.bss` | bench (mapping) + metal (cache behaviour) | 4 | 30 §8 |
| U4 | Large `kmem` requests routed to `sptalloc` behave (no silent hang) | bench | 3 | 30 §2 |
| U5 | `execsw`/`fmodsw`/`vfssw` references are symbol-relative on both lines so tables can be grown | bench (host computation) | 3 | 30 §6 |
| U12 | Every walker of `vfssw` reads `nfstype` live; `vfs_mountroot` with module rows | bench | 5 | 30 §6 |
| U15 | File loading in process 0 after root is mounted (else the first `sysinit` entry) | bench | 3 | 30 §3 |
| U16 | The 040/060 port's relocation and page-geometry checks pass with the arena's zero block in `.data` | bench (host computation) | 3 | 30 §8 |
| M-ABI1 [U7] | Export and header diff between the 68040 and 68060 kernels of the k46 family | bench (host computation) | 3 | 20 §3.1 |
| M-ABI2 [U6] | `elf2brel` carries the ~1000 `.long` relocations of the exported-symbol block on the 030 line; table cost | bench (host computation) | 3 | 20 §1.2 |
| M-REG1 | Registry values (majors, empty rows, `sysentsize`, `fmodcnt`, structure offsets) against every built kernel | bench (host computation) | 3 | 20 §6 |
| M-MOD1 | Object sizes of every root-class module (z3660scsi, a4091, gayle-ide, a4000t-710, ufs, s5, cdfs, ramdisk) → arena capacity = 2 × set rounded to 64 KiB | bench (host computation) | 3 | 10 §5.3, 20 §8 |
| M-CORE1 [U13] | The adopted core's host tests (relocation oracle, state harness) built with our toolchain | bench (host) | 3 | 30 §1 |
| M-INT1 | INT2 and INT6 chains; z3660eth with interrupt receive; polled fallback | bench (chain logic) + metal (the emulated board raises no INT6) | 3 | 30 §4 |
| M-SIG3 | The kernel refuses `modload`, dependency loads and first-open loads of any file not a member of the booted manifest or whose SHA-256 differs; the development-load flag lifts this and is printed | bench | 3 | 30 §2 |
| M-THR1 | z3660eth and RTG throughput as modules vs the static drivers' figures of record | metal | 3 | 80 §2 |

## 4. Root as a module, filesystems, safe mode

| ID | Measurement | Class | Stage | Spec |
|---|---|---|---|---|
| M-SD1 | Card-number contract over the board sets of record (`30-module-core.md` §5.3): unchanged-order sets name every disk as the 1.0 static kernel did; the listed changed sets give exactly the listed new names; three- and four-controller sets give the contract's expected names | bench + metal (both boxes' board sets) | 4 | 30 §5 |
| M-FS1 | The 040/060 base rebuilt without ufs/s5: the carved ufs and s5 objects are self-contained (symbol ranges, relocations), the rebuilt image passes the port's gates, and root on ufs and s5 modules boots | bench (host computation, then emulator) + metal | 5 | 30 §6 |
| M-A4T1 | The A4000T onboard 53C710 probe: gated, never touches the controller window ungated, hangs nothing | metal | 4 | 20 §6, 30 §5 |
| M-DMA1 | Cache and DMA behaviour per root controller module (z3660scsi, A4091/A4092, Gayle IDE, 53C710) | metal | 4 | 30 §8 |
| M-FL1 | Floor kernel size per line once controllers and filesystems leave it | bench (host computation) | 5 | 70 §6 |
| M-FL2 | Safe-mode boot on every root controller and root filesystem | bench + metal | 4, again 5 | 70 §4 |
| M-HALT1 | The halt pass stops every root controller before power-off (A4091 SCRIPTS stopped) | bench + metal | 4 | 30 §2 |

## 5. Media

| ID | Measurement | Class | Stage | Spec |
|---|---|---|---|---|
| M-CD1 | CD boot and install on the A4091 ROM (emulated) and the A4092 (metal), both lines' generations from one disc | bench + metal | 5 | 50 §4 |
| M-NET1a [U-N3] | Uncompressed netinstall miniroot size per line, from today's binaries — **closed 2026-10-25**: k30 2 562 866 B, k46 2 468 595 B with the trimmed engine (3 265 054 / 3 170 783 B with the full 1.0 engine); evidence `docs/measurements/2026-10-25-m-net1.md`, tool `tools/measure/m-net1.py` | bench (host computation) | **0** (S0 freeze condition) | 50 §5.1 |
| M-NET1b | Its deflate-compressed size — **closed 2026-10-25**: k30 959 940 B, k46 924 595 B trimmed (1 228 315 / 1 192 293 B full); with the deflated 1.0 floppy kernel, margins on two DD volumes +16.1 % / +13.0 % trimmed, +1.1 % / −2.0 % full; evidence as M-NET1a | bench (host computation) | **0** (S0 freeze condition) | 50 §5.1 |
| M-NET1c | Compressed kernel + root-class modules under the 1.1 floor (DV-1) | bench (host computation) | 5 | 50 §5.1 |
| M-NET1d | Store overhead and usable bytes per DD volume (DV-1) — **closed 2026-10-25**: volume 1 data from 0x7800 (870 400 B usable; 868 352 B with boot2 at 28 KiB), later volumes from 0x800 (899 072 B), plus a manifest reservation per generation; evidence as M-FP1 | bench (host computation) | 1 (store format frozen) | 50 §5.1 |
| M-NET1e | RAM needed at boot vs the smallest supported machine per line (DV-1) | bench | 5 | 50 §5.1 |
| M-NET1f [U-N1] | A single-user miniroot runs the inet STREAMS stack (on a static kernel first; DV-1) | bench | 2 (early, static kernel), again 5 | 50 §5.1 |
| M-NET1g [U-N2, U-N8] | HTTP throughput and inactivity timeouts from the miniroot (DV-1) | metal | 5 | 50 §5.1 |
| M-TAPE1 [T-U1, T-U2] | Stock floppies + stock tape image install in the emulator; origin of the old "timeout" | bench | 2 | 50 §6 |
| M-TAPE2 [T-U5, T-U7] | TAPE1 written from a running box reads back; tape source throughput | bench | 2 | 50 §6 |
| M-TAPE3 [T-U3] | An emulated tape (ZuluSCSI tape image) behind the A4092: sense data, mode select, filemark spacing at close | metal | 2 | 50 §6 |
| M-TAPE4 [T-U4] | Tape on card 1 through the A4091 driver on the 060 line | metal | 2 | 50 §6 |

## 6. Retired from the research record

| Old id | Why retired |
|---|---|
| U8 (floppy budget for a slotted kernel) | replaced by M-FP1 (the slot is gone; the store changes the prefix) |
| U10 (Kickstart menu lists a second `UNI\0`) | one boot slice per disk (D-3 §6); relevant only to the proof-period development slice, where it is used as found, not shipped |
| U14 (`unix_boot040` keeps a large `.data`) | not a supported boot path |
