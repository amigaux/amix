# C4-2 — what a root-class driver changes, version 6

- **Status:** agreed 2026-10-26 (orchestrator), version 1: its own
  contract beside C3-6, and `root_defer` a DDI call (core patch 0036);
  version 2 (2026-10-26, from the a4091 station): the A4770's key in the
  A4091 row, and the A4091 polled in its first module form (§8);
  version 3 (2026-10-26, the kabi 1.2 cut): `root_defer` is minor 2 on
  k30, whose minted kernel (kern30m -10) does not export it (§3);
  version 4 (2026-10-27, S4-74's first metal row): a module carries
  every arm the kernel build applied to the static driver it replaces
  (§1.1); version 5 (2026-10-27): §1.1's example names the mechanism, a
  dirty copyback line written back over the board's data; version 6
  (2026-10-27, S5-06): the A4000T onboard 53C710's gate is the running
  Kickstart's `NCR scsi.device` resident (§8.1).
  Other repositories build against this text; a change from here is a
  contract change with a version bump.
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
  target), amix-gayle-ide (Gayle IDE), kernel/modules (`ramdisk`)
- **Depends on:** C4-1 (`sd_register`), C4-3 (the RAM-disk hand-off),
  C4-4 (the arena), C4-5 (DDI v1.2 DMA); core patches 0029–0034

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

### 1.1 The build passes' arms move into the module (version 4)

**A module that replaces a statically linked driver must carry every
arm, knob or stamp that the kernel's build passes applied to the static
driver** (cache arms, CPU-type switches, patched constants), set at
`_load` from the kernel's facts (`cputype`, `kinfo`) or as a parameter
with the line's default. The kernel build no longer stamps them: a
module kernel has no static driver for its passes to find. **The
module's README lists them.**

Found on metal (S4-74, the A4000T with a real 68060, kern46m -81): the
port's `f4arms --cache 60` pass stamps `z3660_cache` = 60 (the 68060
data-cache arm) into every static k46 z3660scsi. The module kept its
.data word's 0 (no cache maintenance), so a dirty copyback line was
written back over the data the Z3660's ARM had just put in DDR, and the
first directory read through piscsi failed: `swapconf` panicked
(`lookupname /dev/dsk/c6d0s2 failed - error 20`). The mechanism is the
write-back, not a stale read: a whole-cache push between two lookup
passes gave the same ENOTDIRs (August's ATT4 A/B), and only the arm's
push before the transfer closes it. So a module must push before the
transfer; invalidating after a read is not enough. Emulators need 0, so
every emulator row passed. The fix is the module's own (ZS-06: the arm
from `cputype` at `_load`, a `cache=` parameter, 0 on k30 always).

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

`root_defer(fn, arg)` is a DDI name of k46.1.1 and k30.1.2, root
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
  through DDI v1.2's DMA interface (C4-5). Never hand a board the address
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
| A4091 / A4092 / A4770 | amix-a4091 | `zorro:0202:54,zorro:c0de:01,zorro:c0de:02` (the A4770 as its `driver.conf` has it; untested on hardware) | `zorro` | none in v1: the driver is synchronous and polled (C4-2 §3 allows it); INT2 through `root_defer` when it is added | stop SCRIPTS (the init path's abort and soft reset) | the per-card arrays a constant 4 (C4-1 §2.3); its chip-visible structures in one `dma_alloc` area, DMA through C4-5; the A4092 needs the kernel's unsigned-autocon fix in every family |
| A4000T onboard 53C710 | amix-a4091 (second target, `a4kt710`) | `mobo:a4000t-710` (gated in `_load`, §8.1; M-A4T1) | `mobo` | through `root_defer` | stop SCRIPTS | the cardless A4000T's only SCSI root |
| Gayle IDE | amix-gayle-ide | `mobo:gayle` | `ide` | INT2 through `root_defer` (its own interrupt-table search goes) | mask | `amix-gayle-ide/docs/module-form.md` |
| ramdisk | amix `kernel/modules` | `always` | — | none | none | block row `b:20`; unit 0 the loader's image (C4-3) |

### 8.1 The A4000T onboard 53C710's gate (version 6)

On a Z3660 box any access to `$DD00xx` hangs the bus for ever unless the
A4000T Kickstart's NCR driver has initialised the chip (amix-a4091's T0).
No probe can make that safe, and a `mobo:` key always matches (C4-4 §1),
so `_load` decides before its first access under `$DD0000`:

1. **The declaration: the running Kickstart has the A4000T's NCR
   driver.** `_load` maps the 512 KiB Kickstart at physical `0xF80000`
   read-only (k30 `sptalloc`, k46 `dev_kvmap`, both root-context names of
   §2), then looks for a valid ROM tag: the word `0x4AFC` at an even
   offset whose `rt_MatchTag` is its own address and whose `rt_Name`
   points inside the image at exactly `NCR scsi.device`, with
   `RTF_COLDSTART` set. Every A4000T Kickstart in the workspace's ROM
   store carries it (3.1 40.70; 3.2.1 47.102, 47.115: idString
   `A4000T_scsidisk`), and none of the A3000 or A4000 ones does. exec
   runs every cold-start tag at every boot before the strap starts
   boot1, so a box that reaches Amix with the tag in its Kickstart has
   had the chip initialised. No tag found: `ENXIO`, silent, and no
   access under `$DD0000`. An A4000T booted on an A4000 Kickstart (such
   as A4kOS323) has no tag and is refused.
2. **The chipset (G0)**: AGA in `VPOSR`, so an A3000 never gets this far.
3. **The chip (G1, G2)**: read-only `bprobe` of ISTAT, then amix-a4091's
   fingerprint (`docs/A4000T-ONBOARD-710.md` §10.2).
4. **The parameter `declared`** (int, default -1): -1, item 1 decides; 0,
   never touch the window; 1, touch it without item 1. 1 is the owner's
   override for a box item 1 cannot read, such as a software MMU remap of
   a Kickstart other than the one at `0xF80000`. On the Z3660 the ARM
   serves the mapped Kickstart at that physical address, so a mapped ROM
   needs no override.

The scan reads at most 512 KiB once, at level 7 in the root pass. It
costs boot2 nothing and adds no DDI name. The known limit is an A4000T
Kickstart on hardware without the chip (an A4000 running a T ROM): item 1
passes there. Whether the ROM's own init then hangs before boot1 depends
on how it probes, which is not measured. `declared=0` is the override for
such a box.

## 9. Not in this contract

- How the loader selects and places the module (C4-4).
- The RAM-disk image's hand-off (C4-3).
- The DMA interface itself (C4-5).
- The Z3660 board register rule (C3-6 §1 at its next version, S4-63).
