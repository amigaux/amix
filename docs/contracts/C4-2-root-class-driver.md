# C4-2 — what a root-class driver changes, version 1

- **Status:** draft 2026-10-26 (amix-dlm), for the orchestrator's
  agreement. Once agreed, other repositories build against this text, and
  a change is a contract change with a version bump.
- **Implements:** `docs/spec/30-module-core.md` §3 (`marc_root` and its
  context), §4 (interrupt attachment), §5 (the sd contract), §7 (the RAM
  disk), §8 (memory classes); `70-static-floor.md` §4 (safe mode); D-3 §4
- **Extends:** C3-6 version 4, which every module still meets (the
  wrapper, `_load`/`_unload`/`_halt`, DDI only, the console hook, board
  windows). This contract adds what a module of class `root` needs. It is
  its own document, not a C3-6 version, so C3-6 can take the board
  register rule (S4-63) on its own schedule.
- **Read by:** the root-class driver owners: amix-z3660scsi (z3660scsi),
  amix-a4091 (A4091/A4092 and the A4000T onboard 53C710 as its second
  target), amix-gayle-ide (Gayle IDE), amix-modules (`ramdisk`)
- **Depends on:** C4-1 (`sd_register`), C4-3 (the RAM-disk hand-off),
  C4-4 (the arena), C4-5 (DDI v1.1 DMA); core patches 0029–0034

## 1. The `.moddata` of a root-class module

| Key | Value |
|---|---|
| `class` | `root` |
| `match` | required (C3-1 §3): the board's `zorro:MMMM:PP`, or a registry probe `mobo:<name>` (20 §6), or `always` (the ramdisk). boot2 places the module only when a key is satisfied; for `mobo:` the module's own gated probe decides in `_load` (C4-4 §1) |
| `rank` | a disk controller's class, C4-1 §4.1: `z3660`, `zorro`, `mobo` or `ide`. The ramdisk has none |
| `unload` | `never` (the default). A root-class module is never unloaded: it holds the root disk, and a block row needs a pinned module (core patch 0031) |
| `majors` | the ramdisk's `b:20`; a disk controller has none, since sd owns the disk majors |
| `depend` | only other root-class modules, which then come first in the arena (C4-4 §1.1). A dependency is never read from a file |

The kit's make fragment builds the object so that boot2 and the core can
run it in place. Every allocated section's file offset must be a multiple
of its alignment, and no section or COMMON may be aligned above 16
(C4-4 §4; `kbootset` refuses otherwise, `km_tail`). Its image and file
stay within C3-1 §6.

## 2. `_load` in the root pass

`_load` runs in `marc_root`: process 0, inside `rth1_mountroot`, before
the root is mounted (30 §3). U1 measured that context on both lines:
**level 7, the clock stopped**. So:
- **no sleep and no wait:** no `sleep`, no `timeout`, no `delay`, no spin
  that waits for an interrupt or for `lbolt` to move;
- **memory:** `kmem_alloc`/`kmem_zalloc` with `KM_NOSLEEP` only, at most
  1 MiB a request, and every result checked. The core's own allocations
  are in no-sleep mode too (patch 0029);
- **no file I/O and no page fault:** the module's code and data are in
  the arena (C4-4), and its parameters come as `_load`'s string;
- **board probes polled.** Interrupts are attached later (§3);
- **the result:** 0 linked; `ENXIO` no board here, silent, the module not
  linked; any other errno is printed and the module is not linked. Either
  way the core undoes what it registered (C3-6 v3, core patch 0020).

**The DDI names a root-class `_load` may call.** Every name whose context
is *any* in `docs/abi/ddi.md`; `kmem_alloc`/`kmem_zalloc` with
`KM_NOSLEEP`; `sd_register` (C4-1); `root_defer` (§3). Also `autocon`,
`bprobe`, `sptalloc`/`sptfree` and on k46 `dev_kvmap`, which `ddi.md`
marks *proc*: today's static root drivers call them in `init_tbl`, which
U1 found to be the same context. **S4-71 confirms each one on both lines
with a root-class probe module**, which shows that it returns at level 7
with the clock stopped. Until that row passes, a driver port may build on
them but not ship. A name of context *proc* not listed here waits for the
deferred call (§3).

## 3. Interrupts: the deferred call

The interrupt self-test cannot run in the root pass: no level is taken
at level 7 (C3-6 v4 §1.3). So a root-class driver:
1. runs **polled** from `_load`, and the root mounts through it polled;
2. calls `root_defer(fn, arg)` from `_load`;
3. in `fn(arg)` attaches with `intr_attach`, runs the board's self-test,
   and enables the board's interrupt only if the test passes; otherwise
   it stays polled and says so.

`root_defer(fn, arg)` is a DDI name of minor 1 (k30.1.1, k46.1.1), root
context only, implemented by S4-05:
- the core keeps up to 8 calls, in order;
- it runs each once at the first `sysinit` entry (`MOD_C_POST`,
  `modadmin -B`): process context, level 0. The calls run before any
  boot-class module loads;
- `fn` returns 0 or an errno, which the core prints. The module stays
  linked either way;
- outside a root-class `_load` it is `EINVAL`, and a ninth call is
  `ENOSPC`;
- in safe mode the calls still run: safe mode drops modules, not the
  controller's interrupts.

A driver with no interrupt (the ramdisk, z3660scsi's synchronous
mailbox) does not call it.

## 4. sd

A disk controller registers each board it drives with `sd_register`
from `_load`, with its declared rank class (C4-1 §3). It names no disk
itself: sd's first open takes the registrations, and the card numbers
follow C4-1 §4. Its queue function is called by sd from then on.

## 5. `_halt`

A root-class driver whose board can write memory or interrupt has a
`_halt` (C3-6 §1.1). The core runs it from `dlm_halt()` in `mdboot`,
before the kernel halts or reboots, newest module first (core patch
0030):
- A4091/A4092 and the 53C710: stop SCRIPTS and mask the chip's
  interrupt (M-HALT1);
- Gayle IDE: mask its interrupt;
- z3660scsi: leave the mailbox idle;
- the ramdisk: nothing.

`_halt` takes no argument, returns nothing, and sleeps on nothing.

## 6. DMA and memory

- **The module's own code and data** are in the arena, inside the
  kernel's `.data`. On k46 they run through ITT0 and are reached through
  DTT0 cache-inhibited, as the static drivers' are (30 §8; U3 measures
  it).
- **A board that reads or writes memory by DMA** gets its buffers only
  through DDI v1.1's DMA interface (C4-5). Never hand a board the address
  of the module's own memory: C3-6 §1.5 stands until C4-5 is agreed.
  On the 030 line Zorro DMA cannot reach the Z3660's DDR (80 OQ-80.5).

## 7. Safe mode

In safe mode boot2 places only the root controller's module, the root
filesystem's module and what they depend on (C4-4 §2). A driver does
nothing for it, and `_load` cannot tell the difference.

## 8. Per driver

| Driver | Owner | `match` | `rank` | Interrupt | `_halt` | Notes |
|---|---|---|---|---|---|---|
| z3660scsi | amix-z3660scsi | `zorro:144b:01,mobo:z3660-window` | `z3660` | none: the piscsi mailbox is synchronous, polled | mailbox idle | ZS-05's armed register access (C3-6 §1, S4-63) |
| A4091 / A4092 | amix-a4091 | `zorro:0202:54,zorro:c0de:01` | `zorro` | INT2 through `root_defer` | stop SCRIPTS | the per-card arrays sized to 4 or bounded (C4-1 §2.3); DMA through C4-5 |
| A4000T onboard 53C710 | amix-a4091 (second target) | `mobo:a4000t-710` (gated by chipset identity; M-A4T1) | `mobo` | through `root_defer` | stop SCRIPTS | the cardless A4000T's only SCSI root |
| Gayle IDE | amix-gayle-ide | `mobo:gayle` | `ide` | INT2 through `root_defer` (its own interrupt-table search goes) | mask | `amix-gayle-ide/docs/module-form.md` |
| ramdisk | amix-modules | `always` | — | none | none | block row `b:20`; unit 0 the loader's image (C4-3) |

## 9. Not in this contract

- How the loader selects and places the module (C4-4).
- The RAM-disk image's hand-off (C4-3).
- The DMA interface itself (C4-5).
- The Z3660 board register rule (C3-6 §1 at its next version, S4-63).
