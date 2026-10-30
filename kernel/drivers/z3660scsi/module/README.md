# z3660scsi — the root-class module

The Z3660 SCSI driver (`src/z3660.c`) as an Amix loadable kernel module of
class `root`: the module core's root pass (`marc_root`) loads it before the
root filesystem is mounted, and it registers the board with sd. The
contracts are kernel/dlm's C4-2 (the root-class driver form, version 1), C4-1
(`sd_register` and the four cards, version 2), C3-1 (the object) and C3-6
(what a driver changes). One source: `-DZ3660SCSI_MODULE` selects the module
form; without it the file is the static driver, byte for byte.

## Build

```sh
make -C module                 # build/k30/mod.d/z3660scsi, build/k46/mod.d/z3660scsi
make -C module k30             # one line (or k46)
make -C module static          # the static object compiled against each kit, and its sha256
make -C module clean
```

The kits are kernel/dlm's ABI kits (`DLM=…/kernel/dlm`, default this amix
checkout's `kernel/dlm/build/kit/<line>`), or name them with `KIT_k30=` / `KIT_k46=`.
Build against kabi `k30.1.1` / `k46.1.1` or later (KIT_REV 96205b6 or
later; 1.0.0-2 was built with KIT_REV 230a1e8, which stamps `k30.1.2` /
`k46.1.2`). Every name the module imports (`autocon`, `bcopy`, `cputype`,
`mod_miscops`, `printf`, `sd_register`, `sptalloc`) is a kabi 1.0 name. The
pinned cross tools (`m68k-cbm-sysv4-*`) and `python3` must be on `PATH`.

`make static`'s k30 sum is the static object's (`0e15a363…`). The 040/060
static object is built by the driver-line relink with its own flags and
4 KiB-page source rewrite, so the kit's k46 compile is not that object; its
pin (`b43e36e7…`) is checked by that relink.

## The module

| Item | Content |
|---|---|
| `.moddata` | `name=z3660scsi`, `class=root`, `match=zorro:144b:01,mobo:z3660-window`, `rank=z3660`, `unload=never`, `param=cache:int:-1:-1:60`, `cpu=68030` / `68040`, `kabi` the kit's; no `majors` (sd owns the disk majors) |
| Wrapper | `MOD_HDRV_WRAPPER(z3660scsi, z3660scsi_load, 0, z3660scsi_halt, …)`: no switch-table slot, no `_unload` |
| `_load` | the cache arm (below), then `z3660map()` polled (autocon first, the fixed base `0x10000000` only on AGA, the ZS-02 signature, the unit sweep), then `sd_register(z3660queue, 0, base, "Z3660 SCSI", 1)` |
| `_halt` | touches no register: the mailbox is idle between transactions; records `z3660_halted` |
| Interrupts | none: the piscsi mailbox is synchronous; `root_defer` is not called |
| DMA | none through the module's memory: the firmware moves data to the caller's buffer as the static driver's requests do |
| Version | `VERSION` (`1.0.0-2`: the cache arm), the package version |

## What `_load` does in the root pass

`_load` runs in process 0 inside `rth1_mountroot`, at **level 7 with the
clock stopped** (C4-2 §2). There it:

- sets the cache arm `z3660_cache` from `cputype` and the `cache=`
  parameter (below), before anything reads it;
- reads and writes the Z3660 window's mailbox registers, polled, every
  write armed against the address-capture race (ZS-05) exactly as the
  static driver does;
- reads `VPOSR` for the AGA gate and asks `autocon()` for the ConfigDev;
- maps the window: the identity map below `0x40000000` (the shipped
  config), `sptalloc()` for a board above it (autoconfig_rtg YES);
- prints the unit sweep's console lines;
- calls `sd_register()` once: the Z3660 is the CPU card, one board at most,
  and the driver's state is single-instance (`c` = 0);
- returns 0; `ENXIO` with no board, **silently** (ECS/OCS, or an AGA window
  with no piscsi mailbox: the static driver's "no piscsi mailbox" line is
  not printed in the module form); `ENOMEM` when the high window cannot be
  mapped; `ENXIO` from the cache-inhibit assertion (only with `z3660_cache`
  40/60 and `z3660_ci_enforce` set); or `sd_register`'s errno.

## The cache arm (ZS-06)

`z3660_cache` selects the driver's data-cache maintenance: 0 = none, 40 =
the 68040's, 60 = the 68060's (`cpushl`/`cinvl` around each transfer, and
the attach check that the board window is reached cache-inhibited,
`docs/BLIZZARD-F3.md`). The static k46 kernels get 60 stamped into the
linked image by the 040/060 port's `f4arms --cache 60` pass. A module
kernel runs no such pass, so the module sets the arm itself at `_load`, as
kernel/dlm C4-2 §1.1 requires of every module that replaces a static driver.

**Why:** the first module kernel on the A4000T's real 68060 (S4-74, kern46m
-81) ran with the module's own `.data` word, 0. No line op ran, a dirty
copyback line was written back over the data the Z3660's ARM had just put
in DDR, and the first directory lookup failed (`swapconf` panicked:
`lookupname /dev/dsk/c6d0s2 failed - error 20`) — August's ATT4 mechanism.
Emulators need 0, so every emulator row had passed.

| `cputype` | `cache=` absent or `-1` | `cache=0` | `cache=40` / `60` | anything else |
|---|---|---|---|---|
| 30 | 0 | 0 | 0, refused, one line | 0, one line |
| 40 | 40 | 0 | as given | 40, one line |
| 60 | 60 | 0 | as given | 60, one line |
| other | 0 | 0 | 0, refused, one line | 0, one line |

`.moddata`: `param=cache:int:-1:-1:60` (default -1 = from `cputype`).
kmem witnesses: `z3660_cache_src` (0 = from `cputype`, 1 = the parameter)
and `z3660_cache_bad` (parameters refused or not understood).

**On k30 the arm is 0, always.** `cpushl`/`cinvl` are line F on a 68030; the
Z3660's UAE_030 core emulates no 030 data cache; and no real 68030 hosts
the piscsi mailbox (the Z3660 is the CPU card).

**The Bench's check** after a boot on the 060 (kern46m -81): read with
`/dev/kmem` that `z3660_cache` = `0x3c` (60), `z3660_push_n` > 0 and
`z3660_ci_ok` = 1. The host harness gates the same three on its 060 cell
(`test/host/z3660_modtest.c`, `test_zs06_arm()`).

## What it cannot do there, and does not

- sleep, `timeout()`, `delay()`, or wait for any interrupt or `lbolt`;
- allocate with `KM_SLEEP` (it allocates nothing: its state is its own
  `.data`/`.bss`);
- open a file or take a page fault;
- run an interrupt self-test (the board has no interrupt);
- take the mailbox bracket: `spl6` moves the level to 4, which in the root
  pass would lower it from 7. `_load` does the bracket's nesting
  accounting without the spl.

After `_load`, sd's first open (`rth1_apply`, still in the root pass) calls
`z3660queue()`, whose `spl6` bracket moves the level to 4 and back for each
transaction, as the static driver does at the same point today.

## Package (C3-5)

The package carries the module object and its `modreg` line only; no device
nodes (sd lays the disk nodes). One package per line: the kabi differs.
