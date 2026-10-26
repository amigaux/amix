# C4-6 — the filesystem module form, version 2

- **Status:** agreed 2026-10-26 (orchestrator), with this draft's three
  choices: the renamed-table pattern (§2), the stock rows plus 4 (§2),
  and cdfs boot class on disk (§5). Implemented by core patch 0040
  (S4-41). Version 2 (2026-10-26): `vfs_register` is minor 2 (§3),
  since kabi 1.1 closed with the minted kernels. Other repositories
  build against this text; a change from here is a contract change with
  a version bump.
- **Implements:** `docs/spec/30-module-core.md` §2 patch 9 (`vfs_register`
  and a grown `vfssw`), §6 (filesystems as modules), §3 (`rootfstype`);
  `20-module-format-and-abi.md` §4.1 (the core tier); D-3 §4; measurements
  U12, M-FS1, M-FL1
- **Written by:**
  - amix-dlm: `vfs_register` and the grown table in the core (S4-41),
    the carve tool (S4-40);
  - amix-040-060-port and amix-kerntools: the kernel's side of the table
    (§2) and the kernels without ufs/s5 (S4-43);
  - amix-cdfs: cdfs as a module (S4-42).
- **Read by:** the ufs, s5 and cdfs modules; every stock walker of `vfssw`

## 1. A filesystem module

| Key | ufs, s5 | cdfs |
|---|---|---|
| `class` | `root` (placed by boot2, linked in `marc_root`) | `root` on the CD medium (it mounts the disc); `boot` on a disk-rooted box (§5) |
| `match` | `always` | `always` |
| `fs` | `ufs` / `s5`: the name it registers (C3-1 §3) | `cdfs` |
| `tier` | `core`, with the kernel's `build` (C3-1): a stock object imports more than the DDI (§4) | `ddi` |
| `unload` | `never`: a mounted filesystem is never unloaded | `never` |

**`_load`** calls `vfs_register` once with its `vfssw` row (§3) and
returns its result. s5's `_load` first calls `inoinit`, which the base's
`init_tbl` called before the base lost s5 (30 §6).

## 2. The table

The stock `vfssw` has no free row: 12 rows on the 040/060 line, 13 on the
030 line (30 §6). The kernel build renames the stock table to
`__amix_vfssw` and its count to `__amix_nfstype`, as it renames `execsw`
(the brief's step 7 rule: symbol weakening at the splice). The core
defines:
- `vfssw[NVFSSW]`, with NVFSSW the stock count + 4, in `.data`;
- `nfstype`, a live count.

At `dmainit` the core copies the stock rows and sets `nfstype` to their
count. Every stock reference to `vfssw` and `nfstype` resolves to the
core's, so every walker sees the grown table. Each walker reads
`nfstype` live (U12, measured in S4-71); one that held a copy would miss
a module's row.

The 040/060 line's cdfs, which takes the RFS row by a relocation retarget
today (`patch_cdfs_vfssw.py`), stops doing so when cdfs is a module: its
row comes from `vfs_register` like any other.

## 3. `vfs_register`

```c
int vfs_register(name, init, ops, flag)
	char *name;			/* the type name, the module's fs= */
	int (*init)();			/* vsw_init, run once now, or 0 */
	struct vfsops *ops;		/* vsw_vfsops */
	long flag;			/* vsw_flag */
```

A DDI name of minor 2 (k30.1.2, k46.1.2). It may be called from a root-
or boot-class module's `_load`:
- it refuses (`EINVAL`) a `name` other than the calling module's `fs=`,
  a 0 `ops`, or a call from outside a `_load`;
- `EEXIST` when a row of that name is there already (a static filesystem
  of the same name: two drivers for one type, as C4-4 §4.1 for disks);
- `ENOSPC` when the 4 spare rows are taken;
- otherwise it fills the next free row, runs `init` once (the stock
  `vfsinit` ran each row's at boot, before any module), raises
  `nfstype`, and returns 0.

`init` is called as `vfsinit` calls it, with the row and its index, and
its result is not read (the stock ones are `void`). A module with
`unload=allowed` is refused (`EINVAL`): a filesystem module is pinned.

There is no unregister: a filesystem module is pinned. A `_load` that
fails after `vfs_register` has its row taken back by the core, as
registrations are (C3-6 v3).

**Context.** In `marc_root`, `init` runs at level 7 with the clock
stopped, as the stock `init_tbl` and `vfsinit` ran it. The stock ufs and
s5 init routines are therefore run in the context they always had; S4-71
confirms that they return there on both lines.

## 4. The core tier

A stock filesystem object, carved from the base (S4-40, M-FS1), imports
more than the DDI: about 112 names for ufs and 108 for s5 (20 §4.1),
among them `bdevsw`, `vfssw` and `nfstype`. These are the core tier,
`abi/<line>/core.list`, written by the carve:
- every name a carved object imports that the DDI lacks;
- `vfssw` and `nfstype` resolve to the core's grown table (§2).

A core-tier module carries `tier=core` and the kernel's `build=`, and
loads only on that kernel build (C3-1). So the ufs and s5 modules are
built with the kernel cut and travel with it. An outside module may not
use the core tier (C3-2 §4). cdfs, our own source, stays in the DDI tier:
it registers through `vfs_register` and reaches the disk through
`sdqueue`, without `vfssw` or `nfstype`.

## 5. Choosing cdfs's class

30 §6 calls cdfs a demand-class module on disk-rooted boxes. Nothing in
the stock mount path loads a module for an unknown type: `mount` fails
in `vfs_getvfssw`. So this draft makes cdfs **boot class** on a
disk-rooted box. It loads at the first `sysinit` entry, with a 69 KB
image well inside U2's process-context total. It is root class on the CD
medium, whose package source is the disc. A load-by-type hook in the
mount path would be a change to stock code that the alternative avoids.

## 6. The root filesystem type

The loader record carries the manifest's `rootfs` (10 §6). The kernel's
RTH1 half sets `rootfstype` from it, so `vfs_mountroot` tries only that
type (30 §3). That type's row is the static one or a root-class module's
registered in `marc_root` just before. In safe mode the root
filesystem's module is in the safe set (C4-4 version 4 §2).

## 7. Measurements

- **U12:** every walker of `vfssw` reads `nfstype` live; `vfs_mountroot`
  with a module's row (bench).
- **M-FS1:** the carve, and the rebuilt 040/060 base (host, then bench,
  then metal).
- **M-FL1:** the floor kernel's size per line without the filesystems.
