# Stage 5 — the exit ledger

80 §2 lists what stage 5 must prove: every row stage 4 carried, and every
medium of 50 built from the final packages and proven. 80 §3 lists what
it must not break: every disk named as the card-number gate of 30 §5.3
expects for its board set, safe mode included (spec 70 §4, S5-02), and
safe mode reaching a shell on every root controller and root filesystem.
This ledger gives, per line, the bytes of record and every row's result.
The stage closes in one commit, when no cell below is empty or pending.
A row's result is PASS or FAIL with its evidence (a Bench run id), or a
number for a measurement. The plan is `docs/plan/stage-5.md`.

## 1. The bytes of record (the final packages, S5-40)

| What | k46 | k30 |
|---|---|---|
| kernel (no ufs and no s5; S5-10, S5-11) | pending | pending |
| its core (`core/series`, `dlm_maximage`) | pending | pending |
| kernel package, with the ufs and s5 modules (S5-12) | pending | pending |
| loader (boot2, its size under 28 672) | pending | pending |
| kbootset (S5-03, S5-15, S5-44) | pending | pending |
| modadmin (S5-03) | pending | pending |
| ABI kit (kabi 1.2, or 1.3 if a stage-5 row needs it) | pending | pending |
| z3660scsi | pending | pending |
| A4091/A4092 | pending | pending |
| the A4000T 53C710 (S5-06) | pending | — (no A4000T on this line) |
| Gayle IDE | pending | pending |
| ramdisk | pending | pending |
| ufs, s5 (S5-12) | pending | pending |
| cdfs | pending | pending |
| z3660eth, z3660rtg, monsw | pending | pending |
| apkg | pending | pending |
| the catalog of record (S5-40) | pending | the same |
| the media of record (disk and SD images, the floppy pair, the CD, the netinstall medium; S5-41) | pending | pending |

## 2. Wave 1

| Row | k46 | k30 |
|---|---|---|
| S5-01 kbootset and modadmin on cf461e3: the box build's tests | pending | the same |
| S5-02 safe mode keeps the card numbers: the `kbuild` host case | pending | the same |
| S5-03 kbootset -21, modtools -7; the WD + A4091 safe boot names the root `ced0s1` | pending | pending |
| S5-04 `tools/carve.py`: the host round trip | pending | pending |
| S5-05 the floppy pair in one swap: `b2medium` and a re-cut pair | pending | pending |
| S5-06 the A4000T 53C710 module: host and emulation | pending | — |
| S5-07 M-A4T1 on the A4000T, its M-SD1 sets | pending | — |
| S5-08 C4-1 / C4-4: the root record of a board that is not AutoConfig'd | agreed: pending | the same |
| S5-09 a network in safe mode, opted in: a safe boot with z3660eth marked `safe` brings zen0 up; without the mark, none | pending | pending |

## 3. Wave 2: the filesystems leave the kernel

| Row | k46 | k30 |
|---|---|---|
| S5-10, S5-11 the cuts without ufs and s5 | pending | pending |
| S5-12 the kernel packages carry ufs and s5; `core.list` | pending | pending |
| root on ufs as a module | pending | pending |
| root on s5 as a module | — (no k46 s5 module, S5-37) | pending |
| a 2 KiB-block ufs on k46: mount, `mmap` and page I/O through the converted `ufs_allocmap`/`ufs_freemap` | pending | — |
| safe mode on a ufs root and on an s5 root | pending | pending |
| a damaged ufs module selects the menu | pending | pending |
| S4-71's init halves: ufs and s5 in the root pass and at the first `sysinit` | pending | pending |
| U12 with a mount of each type | pending | pending |
| S5-14 M-FS1 and M-FL1, final (`docs/measurements/2026-10-27-m-fs1-m-fl1.md`; re-check at the S5-15 cuts, §4; M-FS1's boot half is S5-13's) | -66: file 2 411 588, 36 634 under its control; memory 5 768 less (the carve stays zeroed in place); ufs 56 636 | -18: file 1 534 496, `bss=346388`; 109 240 bytes less than -17; ufs 56 636, s5 39 961 |
| S5-15 the 030-mode root record: `kbootset` -22 and z3660scsi | — (030 mode) | pending |
| S5-46 a motherboard controller's record by its id: the cuts with `rth1=2`, `kbootset` -22; a Gayle root beside the Z3660 window (A4000, 030 mode) and a 53C710 root beside Gayle (A4000T) mount by the record, not the built-in root | pending (A4000T) | pending (A4000 in 030 mode) |

## 4. Wave 3: carried metal

| Row | k46 | k30 |
|---|---|---|
| S5-16 the A4000T in 030 mode: the root record matches the window board | — | pending |
| S5-17 the s5 root on metal, and safe mode with it | — | pending |
| S5-18 the 030 DMA pool with no reachable memory: C4-5, host cases | — | pending |
| S5-20 the 030 line on the release firmware: M7, z3660scsi root | — | pending |
| S5-21 the A4000T after its repair: an A4092 root, CD boot on metal, the second bus, the A4091/A4092 module's metal, M-DMA1, S5-18's metal half | pending | pending |
| S5-22 the A4000D: z3660scsi and Gayle IDE roots, cold boots, M-HALT1 | pending | pending |
| S5-23 U3's cache half; M-FP2 | pending | pending |

## 5. The media

| Row | k46 | k30 |
|---|---|---|
| S5-30 rescue from the CD and from the floppy pair | pending | pending |
| S5-31 disk and SD images with rescue; tape as a package source | pending | pending |
| S5-32 the generic 060 target, from its pre-installed images | pending | — (a 68060 target) |
| S5-33 the raw RDB image, zen0 in the miniroot, a netinstall from a public host | pending | pending |
| S5-34 the static kernel families out of the catalog | pending | the same |
| S5-44 the disk nodes of cards 2 and 3: J4's root brought to the set by `kbootset` -22's commit, `check` clean, `pkgchk core` quiet; a fresh install on a three-controller set names the card-2 disks with no hand-made node | pending (Z3660 + A4092 + Gayle, J4's set) | pending (a k30 set with a card 2) |

## 6. Release acceptance

| Row | k46 | k30 |
|---|---|---|
| S5-40 the final packages, one catalog | pending | the same |
| S5-41 every medium of 50 rebuilt from them | pending | pending |
| S5-42 stage 4's media rows again on the rebuilt media | pending | pending |

## 7. Not cells of this ledger

S5-35 (the panic path after a failed root mount, the port) and S5-36 (the
Z3660 window probes, the driver repositories) are written where they are
worked.
