# Stage 5 — carried metal and release acceptance: work breakdown

- **Status:** plan, 2026-10-27; stage 5 opens on catalog b198e9e2
- **Source:**
  - `docs/spec/80-stages-and-proof.md` §2 stage 5 and §3 (a carried row
    that changes a shipped byte rebuilds and re-proves every medium that
    carries it);
  - `docs/plan/stage-4-exit.md` §7 and §8: what stage 4 carried, and why;
  - `docs/plan/stage-4.md` §2.8–§2.9: the carried rows S4-33, S4-40 …
    S4-43, S4-60, S4-61, S4-64 … S4-67;
  - `docs/plan/s4-40-ufs-s5-carve.md`: the agreed carve (P1–P4, K1–K4 and
    A1–A3 answered);
  - review T-54 items 20 and 22 (the A4000D's rows; the carry, decided
    2026-10-27).
- **Exit gate (80 §2):** every carried row proven; every medium of
  `50-media.md` built from the final packages and proven.
- **Invariant carried forward (80 §3):** every disk is named as the
  card-number gate of 30 §5.3 expects for its board set, in safe mode too
  once S5-02 lands (spec 70 §4); safe mode reaches a shell on every root
  controller and root filesystem.
- **kabi:** 1.2 is frozen (stage 4's exit, 2db99e1). A DDI name or
  fingerprint line added in stage 5 is 1.3. None is planned: the carve's
  imports are core-tier names (`abi/<line>/core.list`), which bind to the
  kernel build, not to the kabi.

## 1. Conventions

As in `stage-4.md` §1: `S5-nn` for work, the owner is the repository the
work lands in, class `host`, `bench` (emulation) or `metal`. Contract
changes keep their C-numbers with a version bump. Stage 4's IDs are kept
beside each row (`was S4-nn`), so earlier evidence stays findable.

## 2. Work breakdown

### 2.1 Wave 1: no dependencies

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S5-01 | **kbootset and modadmin on gcc14-cross-amix cf461e3** (pointers in %a0 and %d0, structs through %a0). The -20 binaries were found unexposed (no struct-returning libc call linked; every libc pointer return sets both registers), so this is hygiene, not a fix; the box build and its tests again | amix-dlm | host | — | S5-03 | 0.25 |
| S5-02 | **Safe mode keeps the card numbers** (was S4-67; spec 70 §4): `kbootset` marks `safe=1` on the modules of every controller ranked before the root's, as well as the root controller's own; gate 6 and the arena count them; a `kbuild` host case | amix-dlm (`kbootset/kbuild.c`, C4-4 §2) | host | — | S5-03 | 0.5 |
| S5-03 | **One mint: kbootset -21, modtools -7**, from S5-01 + S5-02; then N145/N146's safe boots again: the WD root `ced0s1` in safe mode too | amix-packages; the Bench | host + bench | S5-01, S5-02 | — | 0.25 |
| S5-04 | **`tools/carve.py`** (was S4-40, the tool): k30 wraps the stock ufs and s5 objects (`MOD_MISC_WRAPPER`, `_load` = `vfs_register`; s5 calls `inoinit` first); k46 also cuts them out of the base by object markers, with their relocations, local symbols and private COMMONs, and refuses a base relocation into a carved range; `probe=1` for S4-71's init halves; host round trip on both lines | amix-dlm | host | the carve plan | S5-10, S5-11 | 1.5 |
| S5-05 | **A RAM-disk floppy pair in one swap** (was S4-64): `mkstore` lays out kernel, modules, image, in boot2's read order; `b2medium` counts one change per boot; installng re-cuts the pairs | amix-dlm (`tools/mkstore.c`); amix-installng | host + bench | — | S5-41 | 0.25 |
| S5-06 | **The A4000T onboard 53C710** (was S4-33): the A4091 driver's second target, `match=mobo:a4000t-710` gated by chipset identity, `rank mobo`, its own package; host and emulation first | amix-a4091 | host + bench | C4-2 §8 | S5-07 | 1.5 |
| S5-07 | **M-A4T1 on the A4000T** with S5-06's module as root, and its M-SD1 sets (alone; the A4092 beside it after S5-21) | the Bench | metal | S5-06 | — | 0.5 |
| S5-09 | **A network in safe mode, opted in per box** (the A4000D's M-FL2, 2026-10-27): safe mode loads no boot-class module, so a Z3660 box, whose only NIC is a module, has no network in a safe boot. The default stays network-less (the NIC module can be what broke the boot). A `safe` line for a boot-class module in `modreg.local.d` (the owner's file) makes `kbootset` write `safe=1` on its record, and in safe mode `marc_post` loads the boot-class records with `safe=1` and no others. A `_load` that fails there is not linked, and the root is already up. C3-5's `safe=1` row and C4-4 §2 at their next versions; spec 70 §4 | amix-dlm (`kbootset`, core `marc_post`) | host + bench | — | — | 0.5 |
| S5-08 | **The Z3660's root record in 030 mode: the contract** (was S4-65): C4-1 / C4-4 at their next versions say how a root record names a board that is not AutoConfig'd (the `mobo:z3660-window` registration with no board id), or how RTH1 matches it; the port and amix-z3660scsi review | amix-dlm (draft) | host | — | S5-15 | 0.25 |

### 2.2 Wave 2: the filesystems leave the kernel (after S5-04)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S5-10 | **The k30 cut without ufs and s5** (was S4-43): `--carve-fs ufs,s5` (fs/Makefile, `filesys.c` loses two rows, `kernel.c` loses `inoinit`); the module objects from the same stock objects, the cut's build id | amix-kerntools | host | S5-04 | S5-12 | 0.5 |
| S5-11 | **The k46 cut without ufs and s5** (was S4-43): `relink-040-carve.sh` on `b-new`, right after `relink-040.sh` and before any pass that branches across the gap; the base's `vfssw` and `nfstype` lose two rows, `init_tbl` loses `inoinit`; `patch_cdfs_vfssw.py` goes; the sidecar omits `rootfs=` | the port | host | S5-04 | S5-12 | 1 |
| S5-12 | **The kernel packages carry the ufs and s5 modules** (core tier, built per cut, C4-6 §4): on k30 both; on k46 ufs only, the port's `fsobj-patch.py` object with its module-only page conversions (ufs-exp.k46 `6636b27e…`, 87b8a88, with S5-13's mount guard; modcheck ok with no waiver), s5 held (S5-37); `abi/<line>/core.list` from the carve; the modules travel in the kernel package and its version sorts above the line's kernel of record (C2-3 v8; the k46 cut -66 is under -82, so it is re-stamped first); recipe `docs/plan/s5-12-packaging.md` | amix-packages; amix-dlm (`core.list`) | host | S5-10, S5-11 | S5-13 | 0.5 |
| S5-13 | **The filesystem rows**, both lines in emulation: root on ufs as a module; root on s5 as a module (k30 only, S5-37); safe mode on each; a damaged ufs module selects the menu; S4-71's ufs/s5 init halves (level and `lbolt` around each init, root pass and first `sysinit`); U12 with a mount of each type; **on k46, a ufs with blocks under the page size is refused at mount, EINVAL, and the box stays up** (the port 87b8a88, module only, ufs-exp.k46 `6636b27e…`): stock mkfs refuses a bsize under 4096 on both lines, and a crafted 2 KiB-block ufs panicked k46 (-50 and the static -82) at first access with "ufs_getapage bad bsize", the unconverted PAGESIZE/2 arm, so the converted `ufs_allocmap`/`ufs_freemap` small-block paths cannot be reached on k46 (k30 -20 runs that disk); proved on test cut `68060-261028-51`, shipped with the next k46 packaging cut | the Bench | bench | S5-12 | S5-16 | 1 |
| S5-14 | **M-FS1 and M-FL1, final**: the carve's sizes and the floor kernel per line | amix-dlm | host | S5-12 | — | 0.25 |
| S5-15 | **The Z3660's root record in 030 mode: the code** (C4-1 v4 §5.1, agreed): `kinfo030.c` keys an unmatched card at `0x10000000` as id 4 (amix-kerntools); the port's k46 kinfo maps `Z3660 SCSI` to id 4 and `src/rth1.c` matches either form, exactly one card (the port); `kbootset` -22 composes any Z3660 card as `id=144b0100 base=0` (amix-dlm). Also kerntools' note: `card_of()` (kbox.c) gives a boot device the loader saw no board for (id 0) the *first* motherboard card, which an A4000 in 030 mode with Gayle makes ambiguous (the window and Gayle). It picks, among the motherboard cards, the one whose unit's disk holds a slice starting at AXL1's partition start; the boot device's name CRC breaks a tie. No loader bytes. Host cases for both | amix-dlm; amix-kerntools; the port | host | S5-08 | S5-16 | 0.75 |

### 2.3 Wave 3: carried metal

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S5-16 | **The A4000T in 030 mode with S5-15**: the root record matches the window board, a second sd card beside it keeps the root's name | the Bench | metal | S5-13, S5-15 | — | 0.5 |
| S5-17 | **The s5 root on metal** (k30 on the A4000T), and safe mode with it | the Bench | metal | S5-13 | — | 0.5 |
| S5-18 | **The 030 DMA pool when all fast memory is the Z3660's** (was S4-66): C4-5 at its next version says what the k30 provider does with no reachable pool (chip memory, or the board refused, said once); `core/plat/k30`; host cases | amix-dlm | host | — | S5-21 | 0.5 |
| S5-20 | **The 030 line on the Z3660's release firmware** (was S4-60): stage 3's M7 again, then z3660scsi as root on the k30 kernel, on metal | Z3660; the Bench | metal | the owner's firmware session | S5-40 | 1 |
| S5-21 | **The A4000T's Zorro-dependent rows after its repair** (was S4-61): an A4092 root, CD boot on metal (M-CD1's metal half), the second bus; the A4091/A4092 module's metal and M-DMA1; S5-18's metal half | the Bench | metal | the owner's repair | S5-40 | 1 |
| S5-22 | **The A4000D's rows** (T-54 item 20): z3660scsi and Gayle IDE roots as modules, cold boots, Gayle on metal, M-HALT1 there | the Bench | metal | the hand-over | S5-40 | 1 |
| S5-23 | **U3's cache half and M-FP2** on metal | the Bench | metal | S5-21 or S5-22 | — | 0.5 |

### 2.4 Media carries, and items routed elsewhere

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S5-30 | **Rescue** from the CD and from the floppy pair | amix-installng | bench | — | S5-41 | 0.5 |
| S5-31 | **Disk and SD images with rescue; tape as a package source** (was S4-56) | amix-installng | bench | — | S5-41 | 1 |
| S5-32 | **The generic 060 target** (was S4-57): the A3000 and A4000 with a 68060, the A4091/A4092 or Gayle root, a ZZ9000 in Zorro II; pre-installed images through the first-boot dialog | amix-installng | bench | S5-12 | S5-41 | 1 |
| S5-33 | **The netinstall extras**: the raw RDB image, zen0 in the miniroot, a netinstall from a public host | amix-installng; amix-z3660net (zen0) | bench | — | S5-41 | 1 |
| S5-34 | **The static kernel families leave the catalog** (S4-24): kernel-k30-u, kernel-k46-z, kernel-k46-zacd, their 1.0 rows under `superseded/` | amix-packages | host | — | S5-40 | 0.1 |
| S5-35 | **The panic path after a failed root mount** (N149/N150: `ufs_update` +0x58 after `vfs_mountroot` errno 6) | the port | host | — | — | 0.25 |
| S5-36 | **The Z3660 window probes on a box without one** (22 caught bus timeouts, N149r/N150r): quieter, or a cheaper first check | amix-z3660net; amix-z3660scsi | host | — | — | 0.25 |
| S5-37 | **s5 on k46** (C4-6 v4: broken under the 4 KiB-page line): no k46 s5 module ships, since no k46 medium needs one (the k46 miniroot is ufs) and the stock code keeps live 2 KiB page sites (`bmap`, about 35 in all by Antti's census, amix-kernel-analysis ee18d5f), while `page_t`'s `p_dblist[4]` and `S5MAXREQ` cannot describe a 4 KiB page over 512-byte blocks. A bounded 1 KiB/2 KiB-block conversion that refuses 512-byte mounts, when one is planned. The k46 cut drops the static s5 (S5-11). Small ufs blocks on k46 would also need `ufs_getapage`'s PAGESIZE/2 arm converted (S5-13) | the port; amix-dlm | host + bench | — | — | project |
| S5-44 | **The disk nodes of cards 2 and 3 on an installed root** (Bench J4, M-G3, the A4000D with Z3660 + A4092 + Gayle, a 1.1 set: Gayle is card 2, and the root held only c0-cf, so IDE-D `c16` and the CD `c15` had no names; hand-made nodes read both): C4-1 v5 §2.4, every four-card root holds c0-c1f d0 s0-s7 and no d1 nodes, whatever the board set; `kbootset nodes` (C2-4 v12 §14) makes them, `commit` runs it on the running box, `check` reports it; firstboot calls it in place of its step 4d (recipe `docs/plan/s5-44-disk-nodes.md`) | amix-dlm (`kbootset` -22); amix-installng | host + bench | kbootset -22 | S5-41 | 0.5 |
| S5-45 | **`kbootset media --disk --ramdisk`** (from amix-installng's S5-33, ni7): the netinstall raw image's store gated by kbootset directly, composed as `media --cd` composes and written by mkstore's engine read-only, members raw (C2-4 v13 §13, C4-3 v4 §1); host only, so the box kbootset and the -22 bytes are unchanged; `build-netinstall.sh` may call it in place of `mkstore` on the `--cd` spec (the same bytes) | amix-dlm; amix-installng (optional switch) | host | — | — | 0.1 |
| S5-46 | **A motherboard controller's record names it** (C4-1 v6 §5.2, C2-3 v9; from the port's S5-15 work): RTH1 matched a `mobo` record to any card with no AutoConfig board, so an A4000 in 030 mode (Gayle + the Z3660 window) and an A4000T (53C710 + Gayle) fell back to the built-in root. The record becomes `sd id=0000000N base=00000000` (N the kinfo motherboard id, no `mobo` flag: boot2 takes it as it is, no loader byte changes); RTH1 matches it by kinfo's rule and no longer matches a `mobo` record to the window; the kernel says so with `rth1=2`; `kbootset` rewrites an old `mobo` root record only for such a kernel | the port (`rth1.c`, `kabi-sidecar.py`); amix-kerntools (`kabi-sidecar030.py`, the k30 cut); amix-dlm (`kbootset` -22) | host | S5-15 | S5-12, S5-16 | 0.5 |

### 2.5 Release acceptance (last)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S5-40 | **The final packages**: every package of the 1.1 set at its release version, one catalog | amix-packages | host | every row above that changes a shipped byte | S5-41 | 0.5 |
| S5-41 | **Every medium of 50 rebuilt from the final packages**: disk and SD images, the floppy pair, the CD, the netinstall medium | amix-installng | host + bench | S5-40 | S5-42 | 1 |
| S5-42 | **Stage 4's media rows again** on the rebuilt media (80 §2), both lines | amix-installng; the Bench | bench | S5-41 | S5-43 | 1 |
| S5-43 | **The exit row**: `stage-5-exit.md` closed in one commit | amix-dlm | host | S5-42 | stage exit | 0.25 |

## 3. Order

Wave 1 runs in parallel across repositories: amix-dlm takes S5-01,
S5-02, then S5-04, S5-05 and S5-08; amix-a4091 takes S5-06. The mint
S5-03 waits for S5-01 and S5-02 only. Wave 2 starts when S5-04 lands:
S5-10 and S5-11 in parallel, then S5-12 and the rows. S5-15 waits for
S5-08's agreement and for the cuts, so `kbootset` changes once more at
most: -22 carries S5-05, S5-09, S5-15 and S5-44. Wave 3's metal follows the box hand-overs and the owner's repair
and firmware sessions; S5-18's host half may run any time. Release
acceptance runs last: any row that changes a shipped byte after S5-40
reopens S5-41 and S5-42 for every medium that carries it (80 §3).

## 4. Not in stage 5

Anything outside 80 §2's stage 5: new drivers, new media, a DDI 1.3
name without a stage-5 row that needs it.

A RAM-disk image shared between generations, as a raw medium for both
lines in one store would need, is not in stage 5. The core loads a boot
module only from the booted id's directory, so an image serves one
generation id (C4-3 v4 §1), and the netinstall ships one raw image per
line. It becomes a decision when such a medium is wanted.
