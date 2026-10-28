# DDI v1 — the kernel interface of an Amix module (k30.1.0, k46.1.0; stage 4 adds names in minors 1 and 2, stage 5 in minor 3: each name's minor is its `ddi.list` line)

These are the names a module may use from the kernel. The list of record
is the ABI kit's `ddi.list` (`abi/<line>/ddi.list` here). The kernel's
symbol block holds exactly these names, and the module core refuses a
module that needs any other (`ERELOC`, C3-1 §4).
`docs/contracts/C3-2-symbols-and-ddi.md` §3 is the index and the decision
record. This page gives each name's contract.

**Context** says where a name may be used:
- **proc**: process context; it may sleep;
- **any**: interrupt level as well;
- **no-sleep**: never sleeps;
- **root**: a root-class module's `_load` in the root pass (level 7, the
  clock stopped; C3-6 §1.3).

In these kernels no spl masks level 6 (`spl5`–`spl7` stop at level 4).
So a level-6 handler calls none of these
(`docs/contracts/C3-6-driver-to-module.md` §1.3).

**Provider:**
- **stock**: the Amix 2.1 kernel, declared by its own headers in the kit's
  `sysroot/` and `stock/`;
- **core**: the module core, declared by `<sys/amixddi.h>` or
  `<sys/moddefs.h>`;
- **port**: the 68040/68060 port (k46 only);
- **cut**: the kernel cut's own build-time patch of a stock source.

The C is K&R. The kernel compiler runs with `-traditional`.

## Console and errors

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `printf` | `printf(fmt, ...)` | any | stock | to the console; `%s %d %u %x %o %c` |
| `cmn_err` | `cmn_err(level, fmt, ...)` | any | stock | `CE_CONT`, `CE_NOTE`, `CE_WARN`, `CE_PANIC` (`<sys/cmn_err.h>`); a leading `!` sends the message to the log only |
| `panic` | `panic(fmt)` | any | stock | does not return |
| `panicstr` | `char *` (data, read-only) | any | stock | nonzero once the system is panicking: a driver's halt or flush paths test it |

## Memory

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `kmem_alloc` | `char *kmem_alloc(size, flag)` | proc with `KM_SLEEP`; any with `KM_NOSLEEP` | stock | kernel heap; `KM_NOSLEEP` may return 0. Not for a board: C3-6 §1.5 |
| `kmem_zalloc` | as `kmem_alloc` | as `kmem_alloc` | stock | zero-filled |
| `kmem_free` | `kmem_free(p, size)` | any | stock | the same size as allocated |
| `sptalloc` | `char *sptalloc(npages, mode, pfn, flag)` | proc | stock | kernel virtual space; with `pfn` nonzero it maps those physical pages (`PG_V`, `phystopfn()`; `flag` 0, as the static drivers call it), which is how a module reaches a board window above `VSECT1`. It draws from `sptmap`, a fixed 4 MiB resource map: on boxes with much RAM a large run may not be left (0 returned). Map only what is needed, and keep it |
| `sptfree` | `sptfree(va, npages, flag)` | proc | stock | undoes `sptalloc`. The two flag values tear down differently: 1 goes through `segkmem_mapout`, as the port's `dev_kvunmap` does; 0 clears the page-table entries directly, with no cache or ATC flush (amix-kernel-analysis `vm-map/CM-PTE-WRITER-MATRIX.md`). Keep what the driver's static form does, and on k46 prefer `dev_kvmap`/`dev_kvunmap` for a device window |
| `vtop` | `paddr_t vtop(va, procp)` | any | stock | the physical address of a kernel (`procp` 0) or user virtual address |
| `dev_kvmap` | `char *dev_kvmap(phys, nbytes, cm, flags)` | proc | port (k46) | a device window at a cache class: `cm` 0x40 (non-cacheable serialised, for registers) or 0x60 (non-cacheable); `flags` bit 0 = no sleep. The kernel address of `phys`, the in-page offset kept, or 0 |
| `dev_kvunmap` | `dev_kvunmap(kva, nbytes)` | proc | port (k46) | undoes one `dev_kvmap`, with the same `nbytes` |

The kernel maps physical addresses below `VSECT1` (0x40000000) one to one.
That is the page tables' early termination, not transparent translation.
A board window there is reachable at `phystokv(phys)`, which is the
identity (`<sys/immu.h>` on k30; `<sys/amixddi.h>` gives both names on k46,
whose kit has the port's 4 KiB-page `sys/immu.h` without them). On k46 the
kit's `sys/immu.h` and `sys/param.h` are the 4 KiB-page forms, so
`phystopfn()` and `btop()` are right.

## Copy and strings

| Name | Form | Context | Provider |
|---|---|---|---|
| `bcopy` | `bcopy(from, to, n)` | any | stock |
| `bzero` | `bzero(p, n)` | any | stock |
| `bcmp` | `int bcmp(a, b, n)`: 0 if equal | any | stock |
| `memcpy` | `memcpy(to, from, n)` | any | stock |
| `strlen`, `strcmp`, `strncmp` | as C | any | stock |
| `copyin` | `int copyin(user, kernel, n)`: 0, or -1 on a fault (return `EFAULT`) | proc | stock |
| `copyout` | `int copyout(kernel, user, n)`: as `copyin` | proc | stock |
| `uiomove` | `int uiomove(p, n, rw, uiop)`: 0 or an errno; `UIO_READ` copies to the user | proc | stock |

## Sleep and timers

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `sleep` | `int sleep(chan, pri)` | proc | stock | with `PCATCH` in `pri` it returns 1 when a signal ends the sleep |
| `wakeup` | `wakeup(chan)` | any but level 6 | stock | every sleeper on `chan` |
| `timeout` | `int timeout(fn, arg, ticks)` | any but level 6 | stock | `fn(arg)` once after `ticks` (HZ per second), at clock level; the id for `untimeout` |
| `untimeout` | `untimeout(id)` | any but level 6 | stock | a module's `_unload` cancels every timeout it armed |
| `lbolt` | `clock_t` (data, read-only) | any | stock | ticks since boot |

## Privilege and devices

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `suser` | `int suser(credp)` | proc | stock | nonzero for the superuser |
| `drv_priv` | `int drv_priv(credp)` | proc | stock | 0 if privileged, else `EPERM` |
| `getmajor`, `getminor` | `getmajor(dev)`, `getminor(dev)` | any | stock | |
| `makedevice` | `makedevice(major, minor)` | any | stock | |

## Autoconfiguration

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `autocon` | `int autocon(prod, index, &base, &size)` | proc | stock | finds AutoConfig board `index` (0 = the first) whose manufacturer and product match `prod` (manufacturer << 16 \| product); nonzero when found, with its base and size. Zorro III bases are returned too: map them (`sptalloc`, `dev_kvmap`), do not dereference above `VSECT1` |
| `bprobe` | `int bprobe(addr, v)` | proc | stock | one byte at `addr` with bus errors caught: `v < 0` reads, otherwise writes the low byte of `v`; 0 = no fault, 1 = bus error |
| `bootinfo` | data, read-only | any | stock | the boot record (`amiga/boot/bootinfo.h`): the AutoConfig board table among it |
| `cputype` | `long` (data, read-only) | any | stock on k46 (the port), core on k30 | 30, 40 or 60. `<sys/systm.h>` still declares a `short`: read it as `DDI_CPUTYPE` (`<sys/amixddi.h>`) |

## Interrupt level

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `spl0`…`spl4` | `int splN()` | any | core | raise (or for `spl0`, lower) to level N; the old status register |
| `spl5`, `spl6`, `spl7` | `int splN()` | any | core | **level 4**, as the kernel's own inline forms (`FAST_INTERRUPTS`) |
| `splx` | `splx(s)` | any | core | back to `s` |

`<sys/inline.h>` gives the same as inline code and `#define`s the names; a
module may use either.

## Interrupt chains

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `intr_attach` | `int intr_attach(level, fn, arg, name)` | proc | core | `level` 2 or 6. `fn(arg)` is called every time the level fires, after the stock handlers, and returns nonzero only when its own board raised it. 0; `EINVAL` (level, or no `fn`); `EEXIST` (already attached); `ECONFIG` (8 handlers per level); `ENXIO` (level 2 before the core armed it) |
| `intr_detach` | `int intr_detach(level, fn, arg)` | proc | core | 0, `EINVAL`, `ENOENT` |

A driver keeps its polled mode as the default. It attaches only after its
board is set up, and enables the board's interrupt only after a software
self-test passes (C3-6 §1.3). A level-6 handler acknowledges and masks its
board and records what happened. The work runs at level 4 or below, in a
level-2 handler raised through PORTS or in the poll.

## Disk controllers and the RAM disk (stage 4: `sd_register` 1.1; `root_defer` k46.1.1, k30.1.2; `iodone`, `ramdisk_image` 1.2)

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `iodone` | `iodone(bp)` | any but level 6 | stock | Ends a block request: a block driver's `strategy` calls it when the transfer of `bp` (a `struct buf *`, `<sys/buf.h>`) is done or has failed, with `b_flags`, `b_error` and `b_resid` set first, as a static driver does |
| `ramdisk_image` | `int ramdisk_image(paddr, size)` | any | core | The physical address and size of the RAM-disk image boot2 placed (contract C4-3 §4), from the loader record. 0; `ENOENT` (no image) |
| `root_defer` | `int root_defer(fn, arg)` | root | core | `fn(arg)` runs once at the first `sysinit` entry, in process context at level 0, before any boot-class module loads, in safe mode too: where a root-class driver attaches its interrupt and runs its self-test (contract C4-2 §3). 0; `EINVAL` (not in a root-class `_load`, or no `fn`); `ENOSPC` (8 already). `fn`'s nonzero return is printed; the module stays linked |
| `sd_register` | `int sd_register(queuefn, c, base, name, rank)` | root | core | Registers one board with sd (contract C4-1 §3). `queuefn(c, cp)` gets sd's requests for it; `base` is what `sdcardbase()` returns; `name` (the module's storage) what `sdhardwarename()` returns; `rank` the class the module declares in `.moddata` (1 `z3660`, 2 `zorro`, 3 `mobo`, 4 `ide`). 0; `EINVAL` (another class, no `queuefn` or `name`, or outside a module's `_load`); `ENOSPC` (four registered); `EBUSY` (sd's first open has closed registration). Allocates nothing; a failed `_load`'s registrations are removed |

## Filesystems and the disk layer (k30.1.2, k46.1.2)

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `vfs_register` | `int vfs_register(name, init, ops, flag)` | `_load` | core | Appends a `vfssw` row for the module's filesystem type (contract C4-6 §3): `name` is the module's `fs=` and stays in its storage, `ops` its `struct vfsops`, `flag` the row's `vsw_flag`. `init`, when not 0, runs once now with the row and its index, as `vfsinit` runs the stock rows'; its result is not read. 0; `EINVAL` (a name other than `fs=`, no `ops`, outside a module's `_load`, or a module with `unload=allowed`); `EEXIST` (a row of that name, the kernel's own included); `ENOSPC` (the 4 spare rows taken). There is no unregister; a failed `_load`'s row is removed |
| `fs_nosys`, `fs_setfl`, `fs_frlock`, `fs_poll`, `fs_pathconf`, `fs_cmp`, `fs_rwlock`, `fs_rwunlock` | as `<fs/fs_subr.h>` | as the vnode or vfs operation they stand for | stock | the stock default operations a filesystem puts in its `vnodeops` and `vfsops` |
| `vn_rele` | `vn_rele(vp)` | proc | stock | drops one hold on a vnode, the function behind `VN_RELE` |
| `copyinstr` | `int copyinstr(from, to, max, &len)` | proc | stock | a user string into the kernel (a mount's `spec` or data). 0; `EFAULT`; `ENAMETOOLONG` |
| `getudev` | `int getudev()` | proc | stock | a free major for a filesystem's unnamed device number (`vfs_dev`, `vfs_fsid`); never a switch row, which only the registry assigns (20 §6) |
| `sdopen` | as the stock `sd.c` (`<amiga/alien/sd.h>`) | proc | stock | opens a disk through sd, as a mount of a block device does |
| `sdqueue` | `sdqueue(cp)` | any but level 6 | stock | queues `cp`, a `struct sdcom` (`<amiga/alien/sd.h>`), to its card's controller (C4-1 §1). The controller calls `cp->intr` when the command is done, at level 4 or below (C4-1 §3.2), so the callback may `wakeup` |

## DMA (k30.1.2, k46.1.2)

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `dma_prepare` | `int dma_prepare(r, pa, len, dir)` | any | port (k46), core (k30) | Before the write that arms the device: makes `[pa, pa+len)` coherent for the device and takes ownership in `r` (contract C4-5 §2). 0; nonzero is a miss (seam off, a segment still owned, no bounce buffer), and the driver arms all the same |
| `dma_complete` | `dma_complete(r, pa, len, dir)` | any | port (k46), core (k30) | After the device stopped, before the completion: for `DMA_FROM_DEVICE` makes the device's bytes visible to the CPU, and gives up the segment. On k30 the memory is cacheable (C4-5 §5.3), so read what the device wrote into `dma_alloc` memory only after it |
| `dma_addr` | `ulong dma_addr(r, pa)` | any | core | The address to arm the device with for the segment at `pa`: `pa`, or on k30 the bounce buffer `r` owns for it. **0 on k30 for a segment the board cannot reach that was not bounced: do not arm, fail the transfer** |
| `dma_alloc` | `char *dma_alloc(len, &pa)` | any (never sleeps) | core | `len` bytes (at most 64 KiB), 16-aligned, that a Zorro III bus master reaches, with their physical address: SCRIPTS, tables, message and status buffers. 0 when none. k46: a heap block through its DTT0 alias, the pointer equal to `pa`, cache-inhibited. k30: the provider's pool (C4-5 §5.4), or the heap through its identity alias when the kernel runs below 0x08000000 |
| `dma_free` | `dma_free(va, len)` | any | core | gives back one `dma_alloc` block, with its `len`. Never while the device may touch it |

`r` is the driver's `struct dma_rec`, one per controller, layout version 2
(the port's `DMA040-SERVICE-RECORD.md`). Zero-length transfers make no call.

## Chip memory and Paula (k30.1.3, k46.1.3)

The names the Paula module needs (amix-paula, `/dev/paula` on major 54).
A kernel exports minor 3 only when its cut defines `paula_busy` and
`audio_nopen`, the stock audio driver patched by amix-paula's
`port/src/patch_audio_paula.py` (C3-2 §2: its post-link gate refuses a
1.3 tag without them).

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `AllocMem` | `void *AllocMem(nbytes, MEMF_CHIP)` (`amiga/inc/memory.h` in the kit's `stock/`) | proc | stock | Chip memory, which Paula's and the blitter's DMA reach: below 0x200000, mapped one to one on both lines. Allocated in 32-byte units from the chip map; 0 when none is left (it does not sleep for it). **Not cleared**: the stock code clears only kernel heap, so `MEMF_CLEAR` does nothing with `MEMF_CHIP`. A module passes `MEMF_CHIP` only; for other memory it calls `kmem_alloc` |
| `FreeMem` | `FreeMem(p, nbytes)` | proc | stock | gives back one `AllocMem` block, with its `nbytes`. It tells chip memory from kernel heap by address (below 0x200000 is chip), so it is never given anything `AllocMem` did not return |
| `displaytype` | `unsigned int` (data, read-only) | any | stock | the video standard: 1 NTSC, 2 PAL, as `PAL` in `<sys/param.h>` tests it; 0 before the console has set it. The E clock is 709 379 Hz on PAL and 715 909 Hz on NTSC |
| `paula_busy` | `int` (data) | proc | cut | nonzero while `/dev/paula` holds Paula's channels; `/dev/audio`'s open fails with `EBUSY` while it is set. **Only the module that owns major 54 (`paula`) writes it**: it sets it in its open after testing `audio_nopen`, without sleeping between the two, and clears it in its close. Every other module only reads it |
| `audio_nopen` | `int` (data, read-only) | proc | cut | the number of `/dev/audio` clients now open; `/dev/paula`'s open fails with `EBUSY` while it is nonzero |

## STREAMS

| Name | Context | Provider |
|---|---|---|
| `allocb`, `freemsg`, `freeb`, `dupmsg`, `copymsg`, `linkb`, `unlinkb`, `msgdsize` | any but level 6 | stock |
| `putq`, `getq`, `putbq`, `putnext`, `qreply`, `canput`, `flushq` | any but level 6, as the STREAMS rules allow | stock |
| `OTHERQ`, `RD`, `WR` | any | stock (functions in these kernels) |

The forms are SVR4's (`<sys/stream.h>`). A STREAMS driver's `cdevsw` row
holds only `d_str` (C3-6 §1.2). The core holds the module from the open
that sets `q_ptr` until the close.

## Network attachment

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `if_attach` | `int if_attach(ifs)` | proc | core | puts the driver's `struct ifstats` (`<net/if.h>`, which begins with its link) on the list `netstat` reads; 0 or `EEXIST` |
| `if_detach` | `int if_detach(ifs)` | proc | core | takes it off; 0 or `ENOENT` |

A module never touches the kernel's `ifstats` list itself. A stock
header's tentative definitions (`ifnet`, `rawintrq` in `<net/if.h>`)
become private COMMON copies in a module. The kit's checker warns about
them.

## The console hook

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `cons_hook_set` | `int cons_hook_set(fn)` | proc | core | `fn(cp, p, n)` sees every console write before the native screen code: `cp` is the `struct console *` (`amiga/console/console.h`), `p` and `n` the bytes. Nonzero = taken. The hook takes only writes with `cp->screen == displayedscreen`, runs in the writer's context (perhaps an interrupt's) and never sleeps. 0, or `EBUSY` while another hook is set |
| `cons_hook_clear` | `cons_hook_clear()` | proc | core | a module's `_unload` clears its hook first |
| `displayedscreen` | `struct screen *` (data, read-only) | any | stock | the screen on display; no stock header declares it, so declare it beside the hook |

## libgcc

`__udivdi3`, `__umoddi3`, `__lshrdi3`: the compiler calls them for 64-bit
arithmetic. A module never names them.

**Provider: libgcc, forced into the module kernel's link by the builder
(amix-kerntools on k30, the port's relink on k46), not a kernel source
symbol.** A base has them only when one of its own objects pulled them
from libgcc: on k30 the static cdfs did, and kern30m -17, without it,
lost them until the builder named every `__` entry of `ddi.list` and
`core.list` with `-u` and linked `libgcc.a` in the module-core link,
whatever the filesystem set. Every builder of a module kernel does the
same, so no cut on either line can lose them silently; amix-dlm's core
harness does it too (`tests/core/run.sh`).

## The module interface

| Name | Form | Context | Provider | Contract |
|---|---|---|---|---|
| `mod_miscops`, `mod_execops`, `mod_hookops`, `mod_drvops`, `mod_strops` | data | — | core | the linkage operations; used through the wrapper macros of `<sys/moddefs.h>`, never by hand |
| `mod_hold` | `int mod_hold(wrapper)` | proc | core | keeps the module loaded across a window where nothing else holds it |
| `mod_rele` | `mod_rele(wrapper)` | proc | core | ends a `mod_hold` |

## Not in the DDI

These names are never in the DDI: `cdevsw`, `bdevsw`, `vfssw`, `int2_tbl`,
`conputc`, `ifstats`, and every other kernel global not listed above. Their
module forms are the core's interfaces (C3-6 §1). DMA is not in v1.0; it
came with 1.2 (above). A stage-4 interface comes as a minor. A name a
driver needs and the DDI lacks is asked for, and it enters as a minor
after review.
