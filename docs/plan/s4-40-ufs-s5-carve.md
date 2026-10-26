# S4-40 — ufs and s5 leave the kernel: the carve plan

- **Status:** plan, 2026-10-27 (amix-dlm), for the orchestrator, the port
  and amix-kerntools. No code yet. The questions in §9 are numbered for
  answers by number. **Answered by the orchestrator:** A1 yes (C4-6
  version 3: one boot-class rule, `rootfs` promoted); A2 cdfs is boot
  class on the 1.1 CD medium too, which roots on its RAM disk; A3 the
  miniroot is s5. P1–P4 and K1–K4 sent to the port and amix-kerntools.
- **Implements:** `docs/spec/30-module-core.md` §6, `70-static-floor.md`
  §2 (OQ-70.1, OQ-70.2), contract C4-6 (`vfs_register`, the core tier),
  C4-4 §1.3 (core patch 0043, the promotion); the plan rows S4-40 (the
  carve), S4-43 (the kernels without ufs and s5), and the ufs/s5 halves of
  S4-71 and M-FS1/M-FL1.
- **Measured here** (2026-10-27, host, read-only): the stock 030 objects
  `amixroot/usr/sys/fs/ufs/exp` and `fs/s5/exp`, every other stock object
  of that tree, and the k46 base `amix-kerntools/work/k0-chains/KD060-Z/
  KD060-Z-c0-u6`.

## 1. What the stage needs

The 1.1 kernels carry no ufs and s5 bytes. ufs and s5 are modules on both
lines; a box roots on whichever its generation names (`rootfs`), and safe
mode loads that one beside the root controller (70 §2). Nothing of either
stays static in a stage-4 module kernel. The 1.0 static families keep
theirs until they retire (S4-24).

## 2. What was measured

| Fact | ufs | s5 |
|---|---|---|
| 030 object: `.text` / `.data` / `.bss` | 50 236 / 1 004 / 24 | 37 776 / 380 / 16 |
| COMMON symbols (private tables) | 13, about 4.9 KiB (`ihead` 4 KiB, `dqhead` 512) and `rootvp` | 6, about 1.1 KiB (`hinode` 1 KiB, `ifreelist`, …) |
| defined globals | 82 | 53 |
| imports | 112 | 108 |
| imports outside DDI 1.2 | 88 | 90 (99 in the union: the core tier, §4) |
| referenced from the rest of the stock tree | `ufsinit` from `master.d/filesys.o` (the `vfssw` row) | `s5init` from `master.d/filesys.o`; `inoinit` from `master.d/kernel.o` (`init_tbl`) |
| references between ufs and s5 | none | none |
| k46 base: `.text` | contiguous: 0x76e7c–0x81a60, no other object's global inside | contiguous: 0x6c3d8–0x7184a |
| k46 base: `.data` | contiguous: 0x8260–0x864c (`mastertemplate` … `ufs_ra`); `rootvp` lies apart (0x9200) | contiguous: 0x7fb0–0x8104 |
| k46 base: globals the 030 object defines and the base lacks | none | none |

So the separation is clean on both lines. On k30 the stock objects
themselves are the modules' bodies (they are the 030 line's own 2 KiB-page
code). On k46 no separate 4 KiB-page objects exist (30 §6): the k46
modules are carved from the base object, by symbol range, with their
relocations, and the base is relinked without them.

`rootvp` is a COMMON in ufs's object and a definition in the kernel: it is
the kernel's, and the module must use it. The core resolves a module's
COMMON against the kernel's symbol block when the name is there (dlm_ld,
the undefined-and-common pass), so `rootvp` goes into the core tier (§4)
and every other COMMON stays the module's own, allocated in its tail.

## 3. The class: boot, promoted by `rootfs`

ufs and s5 both have `class=boot`, `fs=ufs`/`fs=s5` and `match=always`,
exactly as cdfs (C4-4 §1.3, core patch 0043):
- on a generation whose `rootfs` is ufs, kbootset composes ufs as a root
  record (boot2 places it, `marc_root` links it before the root is
  mounted, `safe=1`); s5 stays a boot record and loads at the first
  `sysinit` entry, before `mountall` mounts anything else;
- on an s5-rooted generation (the miniroot of the media, §6) the reverse.

So the arena never holds both, and one object per line serves every box.
This changes C4-6 §1's table, which drafted ufs and s5 as root class
everywhere (question A1).

## 4. The module form and the core tier

| Key | ufs | s5 |
|---|---|---|
| `name`, `fs` | `ufs` | `s5` |
| `class`, `match` | `boot`, `always` (promoted, §3) | the same |
| `tier`, `build` | `core`, the kernel cut's build id (C3-1) | the same |
| `unload` | `never` | `never` |
| `_load` | `vfs_register("ufs", ufsinit, &ufs_vfsops, <flag>)` | `inoinit()`, then `vfs_register("s5", s5init, &s5_vfsops, <flag>)` |

- **The wrapper** is a small object the carve tool writes and links to
  the body: `MOD_MISC_WRAPPER`, the `_load` above, an empty `_unload`.
  `<flag>` is the stock `vfssw` row's `vsw_flag`, read from
  `master.d/filesys.o` (k30) and from the base's `vfssw` (k46) by the
  carve.
- **The core tier**, `abi/<line>/core.list`, is the union of what the two
  objects import outside DDI 1.2: 99 names on k30 (§2), among them
  `bdevsw`, `vfssw`, `nfstype`, the buffer cache, the page layer, `u`,
  `rootdev`, `rootvfs`, and `rootvp`. The k46 list comes from the carved
  objects and should be the same names. A core-tier module loads only on
  its kernel build (C3-1), so ufs and s5 are built with each kernel cut
  and travel in its kernel package (C4-6 §4).
- **`vfssw` and `nfstype`** are in the core tier because ufs's mount path
  walks the table (`vfs_devsearch`). They resolve to the core's grown
  table (core patch 0040), so the walk sees every module's row.
- **Init context.** Promoted to root, ufs's `ufsinit` (and s5's `inoinit`,
  `s5init`) run in `marc_root`, at level 7 with the clock stopped, which
  is the stock `init_tbl` and `vfsinit` context (C4-6 §3). Loaded as boot
  class, they run at the first `sysinit` entry, process context, level 0:
  a context they never had in the stock kernel. **S4-71's ufs/s5 halves
  measure both**, on both lines: the wrapper takes a parameter `probe=1`
  that prints the level and whether `lbolt` moved before and after each
  init call, as `tests/bench/s4-71` does.

## 5. The kernel cuts

### 5.1 k30 (amix-kerntools)

1. The K030-U relink leaves `fs/ufs/exp` and `fs/s5/exp` out of the link.
2. `master.d/filesys.o` loses the ufs and s5 rows: 11 stock rows instead
   of 13. The core copies whatever `__amix_nfstype` says, so no core
   change follows; C4-6 §2's "stock rows plus 4" then gives 15.
3. `master.d/kernel.o`'s `init_tbl` loses `inoinit` (the s5 module calls
   it from `_load`).
4. The tunables and tables ufs and s5 import (`ufs_ninode`, `ndquot`, the
   inode counts) stay in the base, from `master.d`; they are core-tier
   names.
5. `rootfstype` comes from the loader record as today (30 §6).
6. The ufs and s5 module objects are built in the same run, from the
   same stock objects, with the cut's build id, and go into the kernel
   package.

### 5.2 k46 (the port)

1. The carve: the ufs and s5 `.text` and `.data` ranges of §2, with their
   relocations and local symbols, become two ET_REL objects; their
   COMMONs move with them, except `rootvp`. The base is relinked without
   those ranges (M-FS1).
2. The base's `vfssw` loses the ufs and s5 rows, and `nfstype` drops by
   two; `init_tbl` loses `inoinit`. No relocation in the base may still
   reach into a carved range (the carve checks it and refuses).
3. cdfs's relocation retarget (`patch_cdfs_vfssw.py`) goes, since cdfs is
   a module (C4-6 §2).
4. The page geometry: the carved code is the base's own 4 KiB-page code,
   so modcheck's scan applies unchanged.

### 5.3 What the core needs

Nothing beyond what exists: `vfs_register` (0040), the promotion (0043),
the core tier and COMMON resolution against the kernel (dlm_ld). The carve
tool and the wrapper are new (S4-40, amix-dlm `tools/carve.py`); for k30
it only wraps, for k46 it also cuts.

## 6. The media and the miniroot

The installer media root on a RAM disk (C4-3), whose image is a
filesystem of the generation's `rootfs`. **Recommendation: s5 for the
miniroot**: a smaller module (about 38 KB against 51 KB) in the media's
arena, and the stock miniroot's own type. The installer then loads ufs as
boot class, to make and mount the target's ufs filesystems, and cdfs as
boot class to mount the CD after the root is up. So on the CD medium
cdfs is boot class too, unless a medium roots on the CD itself; C4-6 §1
says root (question A2).

## 7. Budgets

- **The arena (0x60000, 393 216 bytes).** The largest root set of
  record: ufs (about 51 KB of file, about 6 KB of tail) beside the root
  controller (z3660scsi 13 KB, or the A4091, or Gayle IDE) and, on the
  media, s5 in ufs's place and the ramdisk module (3 KB). About 80 KB in
  all, a fifth of the arena, with the directory and the manifest copy
  (about 2 KB). Two filesystems never share it (§3). Gate 4 checks each
  generation.
- **Kernel memory after the root.** The boot-class filesystem (s5 on a
  ufs box, about 40 KB with its tables) is a kmem image after the root is
  up: inside U2's budget for modules on both lines.
- **The kernel image** loses about 89 KB of text and 1.4 KB of data
  (M-FL1 measures it per line).
- **boot2** is not touched.

## 8. Tests

- **Host:** the carve tool's round trip on both lines: the module object
  passes modcheck with `tier=core`; the relinked k46 base has no
  relocation into a carved range and no undefined symbol but `etext`,
  `edata`, `end`; mkabi on the cut. The state harness: a `tier=core`
  module resolving a COMMON against the kernel (the `rootvp` case).
- **Bench:** the ledger's rows "root on ufs as a module" and "root on s5
  as a module", each line; safe mode with each; a damaged ufs module
  selects the menu; S4-71's init halves (§4); U12 with a mount of each
  type; M-FS1 and M-FL1.

## 9. Questions

**For the orchestrator:**
- **A1.** ufs and s5 as boot class with `fs=`, promoted by `rootfs`
  (§3), instead of C4-6 §1's root class everywhere: agreed? Then C4-6 v3
  changes §1's table.
- **A2.** cdfs on the CD medium: boot class, since the medium roots on
  its RAM disk (§6), unless a medium is meant to root on the CD itself?
- **A3.** The miniroot as s5 (§6)?

**For the port (k46):**
- **P1.** Is the carve by the ranges of §2 sound for the base as you build
  it (KD060-Z and its successors), or does a later relink move data so
  that a range is no longer one object's?
- **P2.** Does any byte patch or override of yours lie inside the ufs or
  s5 ranges, or reference them from outside (beyond `vfssw` and
  `init_tbl`)?
- **P3.** Who carves: your relink with amix-dlm's `tools/carve.py`, or
  your own tool with amix-dlm's checks? The module objects travel in the
  kernel package either way.
- **P4.** OQ-70.2 on your line: any boot-time consumer of ufs inside the
  base (swap, `/stand`, the dump path)?

**For amix-kerntools (k30):**
- **K1.** Can the K030-U relink drop `fs/ufs/exp` and `fs/s5/exp` and take
  `filesys.o` and `kernel.o` without those rows and without `inoinit`, by
  the same exact-line stock edits as `--sd-cards 4`, or do they need
  their master.d sources rebuilt?
- **K2.** Do `ufs_ninode`, `ndquot` and the inode-table sizes come from
  master.d objects that stay in the link (§5.1, point 4)?
- **K3.** OQ-70.2 on the 030 line: any boot-time consumer of ufs in the
  base? The import scan of §2 found none beyond `vfssw` and `init_tbl`.
- **K4.** The ufs and s5 modules built in the same run as the cut, and
  shipped in the kernel package (§5.1, point 6): agreed?
