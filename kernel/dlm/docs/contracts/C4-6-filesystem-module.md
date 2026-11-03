# C4-6 — the filesystem module form, version 7

- **Status:** agreed 2026-10-26, with this draft's three
  choices: the renamed-table pattern (§2), the stock rows plus 4 (§2),
  and cdfs boot class on disk (§5). Implemented by core patch 0040.
  Version 2 (2026-10-26): `vfs_register` is minor 2 (§3),
  since kabi 1.1 closed with the minted kernels. Version 3 (2026-10-27): one rule for every
  filesystem module, boot class with the generation's `rootfs` promoted
  to a root record (§1, §5); the miniroot is s5. Version 4 (2026-10-27,
  from an amix-installng RAM-disk image): the miniroot is s5 on k30 and ufs on k46 (§1).
  Version 5 (2026-10-31): a filesystem module may be demand class, loaded
  at the first mount of its type (§1, §5); cdfs is (core patch 0048,
  kabi minor 4). Version 6 (2026-10-31): that load never waits for
  memory; short memory fails the mount with `ENOMEM` (§5, core patch
  0049). Version 7 (2026-11-03): the COMMONs stock kmem readers name
  stay in the kernel, and `inode` has an empty table while no s5 is
  loaded (§4).
  Other repositories
  build against this text; a change from here is a contract change with
  a version bump.
- **Implements:** `docs/spec/30-module-core.md` §2 patch 9 (`vfs_register`
  and a grown `vfssw`), §6 (filesystems as modules), §3 (`rootfstype`);
  `20-module-format-and-abi.md` §4.1 (the core tier); measurements
  U12, M-FS1, M-FL1
- **Written by:**
  - kernel/dlm: `vfs_register` and the grown table in the core,
    the carve tool;
  - amix-040-060-port and amix-kerntools: the kernel's side of the table
    (§2) and the kernels without ufs/s5;
  - amix-cdfs: cdfs as a module.
- **Read by:** the ufs, s5 and cdfs modules; every stock walker of `vfssw`

## 1. A filesystem module

**One rule for ufs, s5 and cdfs: a filesystem module is boot or demand
class; the generation's `rootfs` is promoted to a root record.** `kbootset`
composes the module whose `fs=` is the generation's `rootfs` as a root
record (boot2 places it, `marc_root` links it before the root is mounted,
and it is in the safe set; `match=always` when the module gives none),
every other boot-class filesystem module as a boot record, loaded at the
first `sysinit` entry before anything else is mounted (C4-4 §1.3, core
patch 0043), and a demand-class one as a demand record with `fs=`, loaded
at the first mount of its type (§5). So one object per line serves every
box, and the arena holds one filesystem at most.

| Key | ufs, s5 | cdfs |
|---|---|---|
| `class` | `boot`; promoted where it is the `rootfs` | `demand` (version 5): loaded at the first `cdfs` mount, so it is resident only on a box that mounts a disc; promoted only on a medium that roots on the CD itself, which none of 1.1 does (§5) |
| `match` | `always` | `always` |
| `fs` | `ufs` / `s5`: the name it registers (C3-1 §3) | `cdfs` |
| `tier` | `core`, with the kernel's `build` (C3-1): a stock object imports more than the DDI (§4) | `ddi` |
| `unload` | `never`: a mounted filesystem is never unloaded | `never` |

**`_load`** calls `vfs_register` once with its `vfssw` row (§3) and
returns its result. s5's `_load` first calls `inoinit`, which the base's
`init_tbl` called before the base lost s5 (30 §6). It must be safe in
both contexts, the root pass and the first `sysinit` entry.

**The roots of 1.1:** an installed disk roots on ufs. The media root on
their RAM disk (C4-3), whose image is **s5 on k30** (the stock miniroot's
type) **and ufs on k46**: s5 is broken under the 4 KiB-page line (on the
k46 s5 RAM-disk root `ls -l` and `/etc/sioc` die with a bus error),
which is why every k46 miniroot has been ufs. So the k46 media's
generation has `--rootfs ufs` and promotes ufs; on k30, s5 is promoted
and ufs is boot class to make the target disk. cdfs is demand class on
both, loaded when the disc is mounted (§5).

## 2. The table

The stock `vfssw` has no free row: 12 rows on the 040/060 line, 13 on the
030 line (30 §6). The kernel build renames the stock table to
`__amix_vfssw` and its count to `__amix_nfstype`, as it renames `execsw`
(symbol weakening at the splice). The core
defines:
- `vfssw[NVFSSW]`, with NVFSSW the stock count + 4, in `.data`;
- `nfstype`, a live count.

At `dmainit` the core copies the stock rows and sets `nfstype` to their
count. Every stock reference to `vfssw` and `nfstype` resolves to the
core's, so every walker sees the grown table. Each walker reads
`nfstype` live (U12); one that held a copy would miss
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
s5 init routines are therefore run in the context they always had; a
root-class probe module confirms that they return there on both lines.

## 4. The core tier

A stock filesystem object, carved from the base (M-FS1), imports
more than the DDI: about 112 names for ufs and 108 for s5 (20 §4.1),
among them `bdevsw`, `vfssw` and `nfstype`. These are the core tier,
`abi/<line>/core.list`, written by the carve:
- every name a carved object imports that the DDI lacks;
- `vfssw` and `nfstype` resolve to the core's grown table (§2);
- the COMMONs stock kmem readers name, `inode`, `ifreelist`, `ufs_inode`,
  `inodeNINODE` and `ifreeh` (version 7, C3-2 §4). The kernel keeps
  them. While no s5 is loaded, the module core points `inode` at an empty
  table: ninode inodes of read-only pages that all map one zeroed page,
  so `sar -v` reads zeros rather than low memory. s5's `inoinit` replaces
  the pointer, and the s5 wrapper keeps the empty table's address for an
  unload to put back.

A core-tier module carries `tier=core` and the kernel's `build=`, and
loads only on that kernel build (C3-1). So the ufs and s5 modules are
built with the kernel cut and travel with it. An outside module may not
use the core tier (C3-2 §4). cdfs, our own source, stays in the DDI tier:
it registers through `vfs_register` and reaches the disk through
`sdqueue`, without `vfssw` or `nfstype`.

## 5. Choosing the class

**Boot class** loads a filesystem module at the first `sysinit` entry,
before `mountall`, in process context; ufs and s5 are boot class where
they are not the root. The root filesystem cannot wait for `sysinit`, so
it is promoted (§1).

**Demand class** (version 5, core patch 0048) loads a filesystem module
at the first mount of its type, so a filesystem that most boxes never
mount costs nothing until then. cdfs is demand class: resident only on
a box that mounts a disc. No stock code changes, because
the stock mount path reaches a filesystem only through its `vfssw` row:
`smount` takes the row's `vsw_vfsops` (by index, or by name through
`vfs_getvfssw`) and calls its `vfs_mount`, and `sysfs` and `statfs` read
only the row's name and index.
- **The stub row.** `marc_post`'s demand pass (never in safe mode) gives
  each demand record with `fs=<type>` a row in a spare `vfssw` row (§2):
  `vsw_name` is the type, `vsw_vfsops` one of the core's stub tables, one
  per spare row, so the stub knows its type from the vfs's ops pointer. A
  type the kernel or a boot-class module already has gets no stub (the
  module would never load; the console says so).
- **The first mount.** The stub's `vfs_mount`, in the mount system call's
  process context, loads the module as a demand major's first open does
  (manifest-only, its SHA-256 checked, C3-4). The module's `_load` calls
  `vfs_register`, which fills the stub's row in place, keeping its index;
  the stub then puts the row's ops into the vfs and mounts through them.
  A mount that took the stub while another loaded the module finds the
  row filled and goes on. A load that fails, or a module that registers
  no row, fails the mount with that error (`ENXIO` for the latter) and
  leaves the stub, so a later mount tries again. The load never waits
  for memory (core patch 0049): when kernel memory is short the mount
  fails with `ENOMEM` and the console says
  `dlm: <module>: not loaded: kernel memory short (error 12)`.
- **The other stub entries** answer without loading: `vfs_sync` 0, since
  the stock `sync()` calls every row's; `vfs_mountroot` and the rest
  `EINVAL`, since `vfs_mountroot` tries only `rootfstype` (§6) and no vfs
  is mounted through a stub.
- **Safe mode** gives no stub rows, so a mount of the type fails with
  `EINVAL` and nothing loads, as on a box without the module.
- **Unload.** A filesystem module stays pinned (§3): once loaded, it stays
  until the next boot.
- **The kernel** must be at kabi minor 4, whose core has the stub path
  (C3-2 §3). A demand-class filesystem module is tagged minor 4, so
  `kbootset` gate 2 and apkg's pre-flight refuse it on an older kernel.

The 1.1 CD medium roots on its RAM disk (C4-3), so cdfs is demand class
there too and loads when the medium's installer mounts the disc; a medium
that rooted on the CD itself would promote it by the same rule as ufs.

## 6. The root filesystem type

The loader record carries the manifest's `rootfs` (10 §6). The kernel's
RTH1 half sets `rootfstype` from it, so `vfs_mountroot` tries only that
type (30 §3). That type's row is the static one or the promoted module's
(§1), registered in `marc_root` just before. In safe mode the root
filesystem's module is in the safe set (C4-4 version 4 §2).

## 7. Measurements

- **U12:** every walker of `vfssw` reads `nfstype` live; `vfs_mountroot`
  with a module's row (bench).
- **M-FS1:** the carve, and the rebuilt 040/060 base (host, then bench,
  then metal).
- **M-FL1:** the floor kernel's size per line without the filesystems.
