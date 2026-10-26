# DDI v1 — the kernel interface for Amix modules, for review

This is the list of kernel symbols that loadable modules on Amiga UNIX 1.1
may use. We ask you to review it before the module kit is frozen. It is
written to stand on its own.

## What it is

From 1.1, the network and graphics drivers (stage 3), and later the root
disk controllers and filesystems, load as modules: ELF relocatable
objects, built with the same GCC 2.7.2.3 cross compiler as the kernel.
The module core is a patch queue on kdedon's MIT-licensed DLM core.

Modules do not see the kernel's whole symbol table. The kernel carries an
**allowlist** in `.data`, and a module may link only against:
- the names on this list (the "DDI tier");
- names exported by modules it declares as dependencies.

The list is fixed per kernel line:
- **k30**: the 68030 kernels;
- **k46**: your 68040/68060 kernels.

A version tag `k46.<major>.<minor>` governs it. Adding a name raises the
minor, and old modules keep working. Removing a name, or changing what one
means or the layout of a structure it uses, raises the major, and every
module of the line is rebuilt.

A second, "core" tier is reserved for the stock filesystem objects (ufs,
s5, cdfs) when they become modules. It is not part of this review.

## What we measured on your kernels

On KD040-A and KD060-A (the A4091 family, as built for 1.0):
- **The two images differ in one byte, the CPU stamp.** Their 4 458
  global symbols agree in name, kind and data-object size. So we plan
  **one k46 interface for both CPUs**. If you ever intend the 68040 and
  68060 kernels to come from different sources or layouts, please tell
  us: the two would then need separate tags.
- `sysentsize` is 142 and slots 64–69 hold `nosys`. The module system
  takes those six system calls.
- Character majors 49, 51, 52 and 53 are free except where a static
  driver holds them today; block majors 0–15 and 21–31 are free;
  `fmodcnt` is 11.

## The list (stage 3, version 1.0)

Context means where the function may be called:
- *any*: interrupt level included;
- *proc*: process context, may sleep;
- *no-sleep*: never sleeps.

"Provided by" says where the symbol comes from:
- *stock*: defined in today's 040/060 kernels;
- *core*: the module core links its own provider, because today's kernels
  lack it or inline it.

| Group | Names | Context | Provided by (k46) |
|---|---|---|---|
| console, errors | `printf`, `cmn_err`, `panic` | any | stock |
| panic state | `panicstr` (data, read-only) | any | stock |
| kernel memory | `kmem_alloc`, `kmem_zalloc`, `kmem_free` | proc with `KM_SLEEP`, no-sleep with `KM_NOSLEEP` | stock |
| large memory | `sptalloc`, `sptfree` | proc | stock |
| memory mapping | `vtop`, `dev_kvmap`, `dev_kvunmap` | proc | `vtop` stock; `dev_kvmap`/`dev_kvunmap` your `devkvmap040.o`, linked into every k46 module kernel |
| copy, string | `bcopy`, `bzero`, `bcmp`, `memcpy`, `strlen`, `strcmp`, `strncmp`, `copyin`, `copyout`, `uiomove` | `copyin`/`copyout`/`uiomove` proc; the rest any | stock |
| sleep, timers | `sleep`, `wakeup`, `timeout`, `untimeout`, `lbolt` (data, read-only) | `sleep` proc; the rest any | stock |
| privilege, devices | `suser`, `drv_priv`, `getmajor`, `getminor`, `makedevice` | the first two proc; the rest any | stock |
| autoconfig | `autocon`, `bprobe` | proc | stock |
| interrupt level | `spl0`…`spl7`, `splx`, as real functions; spl5–spl7 raise to **level 4 only**, as the kernel's inline forms do (`FAST_INTERRUPTS` in `<sys/inline.h>`) | any | core (the kernels inline them) |
| interrupts | `intr_attach`, `intr_detach` | proc | core: an INT2 chain walker in `int2_tbl`'s last handler slot (the handler it displaces is called first), and an INT6 chain after the CIA-B handler. A handler returns whether it claimed the interrupt; drivers with a polled mode keep it as the default |
| STREAMS | `allocb`, `freemsg`, `freeb`, `dupmsg`, `copymsg`, `linkb`, `unlinkb`, `msgdsize`, `putq`, `getq`, `putbq`, `putnext`, `qreply`, `canput`, `flushq`, `OTHERQ`, `RD`, `WR` | as the STREAMS rules say | stock |
| network attachment | `if_attach`, `if_detach` | proc | core (replaces drivers touching `ifstats`) |
| console hook | `cons_hook_set`, `cons_hook_clear` | proc | core (replaces drivers calling `conputc`) |
| compiler helpers | `__udivdi3`, `__umoddi3`, `__lshrdi3` | any | core on k46 (the 030 kernels have them) |
| identity | `bootinfo`, `cputype` (data, read-only) | any | stock |
| console | `displayedscreen` (data, read-only): which screen is on display, so a console hook takes only its own screen's writes | any | stock |
| module interface | `mod_miscops`, `mod_execops`, `mod_hookops`, `mod_drvops`, `mod_strops` (data), `mod_hold`, `mod_rele` | proc | the module core itself: every module references its linkage operations through the wrapper macros, and `mod_hold`/`mod_rele` hold a module while it is in use |

**Never exported:**
- the switch tables and vectors themselves (`cdevsw`, `bdevsw`, `vfssw`,
  `int2_tbl`);
- `conputc`;
- `ifstats`.

Modules reach the tables only through registration, and attach to
interrupts only through `intr_attach`.

**Coming later as minors:**
- stage 4 (root disk controllers as modules): `sd_register`, `sdqueue`,
  `iodone`;
- stage 5 (filesystems): `vfs_register`.

## What we would like your view on

1. **Anything missing or wrong for drivers on your line.** In
   particular, are `dev_kvmap` and `vtop` the right memory-mapping
   primitives there? DMA is left out of v1.0, since no stage-3 module
   needs it. Your `dma_prepare` and `dma_complete` (`dma_cache040.o`, the
   A3091 copy-back hooks) stay kernel-internal. We would like to design
   a DMA interface for the root controllers with you in stage 4, under
   names that cannot clash with yours.
2. **`intr_attach` placed in `int2_tbl`'s last slot.** On your kernels
   that slot holds `aenintr`, after `a3091intr_demux`. Does the chain
   walker sit correctly beside your demultiplexer, or do you want a
   different seat?
3. **The `spl` functions.** We provide real functions for modules,
   identical to the kernel's inline forms, while the kernel keeps
   those. Under `FAST_INTERRUPTS` in `<sys/inline.h>`, spl5, spl6 and
   spl7 raise to level 4 only, so **no spl masks level 6** (CIA-B, and
   the Z3660 firmware's ethernet interrupt). We copy that exactly, and
   the list tells driver authors that an INT6 driver masks at its own
   board, never with spl7. Is that the behaviour you want modules to
   see? And any objection on the 68060 (pipeline, `sr` handling)?
4. **One interface for the 68040 and the 68060,** as measured above. Is
   that your intention going forward?
5. **Anything you would not want a module to touch** that we have listed.

The module format, the identity record and the loader's side are fixed
separately. Only this list is open for your review. After the review the
list freezes as v1.0, and later additions only raise the minor.
