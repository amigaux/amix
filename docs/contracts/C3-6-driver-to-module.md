# C3-6 — what a driver changes to become a module, version 3

- **Status:** agreed 2026-10-26 (orchestrator), version 1; version 2
  (2026-10-26, from the z3660rtg station's module build): the console
  hook's `cp` is the console, not the screen (§1.4); `_halt` returns
  nothing (§1.1); z3660rtg's `_unload`, font, console modes and blitter
  parameters (§3); from the z3660net station's: the STREAMS row is zeros
  but `d_str`, interrupts attach at first open with a software self-test
  (§1.3), z3660eth's handlers, `intrl2` and its acknowledge-and-mask
  write (§2), the k46 page-geometry headers in the kit (§1.7);
  z3660eth's `match=` (§2: a boot-class module needs one, C3-5);
  version 3 (2026-10-26, from S3-B5): every module has an `_unload`,
  which the core also calls when a load fails after `_load` succeeded
  (§1.1, §2). The
  driver-change
  brief of the z3660net and z3660rtg stations (and of the monsw owner).
  Other repositories build against this text; a change from here is a
  contract change with a version bump.
- **Implements:** `docs/spec/20-module-format-and-abi.md` §2–§5,
  `30-module-core.md` §3–§4; it applies C3-1 (the object), C3-2 (the
  symbols and DDI v1) and C3-5 (the package) to three drivers
- **For:**
  - amix-z3660net: z3660eth (S3-25);
  - amix-z3660rtg: z3660rtg, today's static `zz9000` (S3-26);
  - the monsw owner: monsw (S3-27; P-8 question (c), plan Q3-2).
- **Built with:** the ABI kit (S3-10, amix-dlm): headers, `mkmod`/`modfix`,
  the checker, the make fragment.

The static form of each driver stays buildable until the stage-3 exit:
one source, with the module glue under a switch (`-D<DRIVER>_MODULE`, the
station's choice of name). A module is built once per line (k30, k46) with
that line's flags. The kabi differs, so the k30 and k46 objects are two
packages.

## 1. The rules, for every driver

### 1.1 The wrapper and the three entry points

- One wrapper per module, from the kit's `<sys/moddefs.h>`: a character
  or STREAMS driver uses `MOD_DRV_WRAPPER(prefix, load, unload, halt,
  desc)` with a `prefix_drvdata[]` holding its `cdevsw` row and major
  (C3-1 §2). The prefix may stay the driver's own (`zz9000`, `z3660eth`);
  the module **name**, which is the file name, is the registry's (§2–§4).
- **`_load(params)`**:
  - called once, in process context; it may sleep;
  - called **before** the core installs the linkages, so the `cdevsw`
    row does not exist yet: nothing in `_load` may rely on it;
  - `params` is the manifest's `param <module>.<name>=<value>` records as
    one string, `name=value` separated by spaces, or 0 when there are
    none; it is valid only during `_load`, so copy what you keep, and
    apply the `.moddata` defaults yourself for names that are absent;
  - does what the static driver's init did (`init_tbl`, `io_init`, the
    `parinit` wrapper): find the board, map its windows, set its state;
  - returns 0, `ENXIO` when there is no board (the module is then not
    kept, C3-1 §3), or another errno. On any nonzero return it leaves
    nothing behind: no timeout armed, no handler attached, no hook set,
    no mapping kept, the board's interrupt off.
- **`_unload()`**: every module has one. It undoes all of `_load`, and
  every hook, handler, timeout and mapping set since, in reverse order,
  and returns 0 or `EBUSY`. The core calls it in two cases:
  - at `moduload`, only with `unload=allowed`, and only when nothing
    holds the module (an open STREAMS queue or device holds it; a module
    that names it in `depend` holds it);
  - whatever `unload=` says, when a load fails after `_load` returned 0
    (the driver's linkage refused, for example). Its return is then
    ignored, and the module is freed.

  `unload=never` refuses `moduload`; it does not spare a driver its
  `_unload`. Anything still pointing into the module after it (an
  interrupt handler, an `ifstats` link, the console hook) is removed by
  the core's backstop and named on the console, but a driver must not
  rely on that.
- **`_halt()`**: called from the halt pass from stage 4 on, newest module
  first, with no sleep and interrupts perhaps off. A driver whose board
  can interrupt or write memory stops it here (its interrupt off at the
  board). Write it now; until stage 4 nothing calls it. It returns
  nothing (`void`, as `mw_halt` in `<sys/moddefs.h>` and C3-1 §2); the
  wrapper's halt entry may be 0 when there is nothing to stop.

### 1.2 Majors from `.moddata`, never a switch-table edit

- `.moddata` `majors=c:<n>` names each major, and `prefix_drvdata[]`'s
  `drv_cmajor` is the same number. The registry
  (`abi/registry/majors`) must give that major to the module's name, or
  the core refuses it (`ECONFIG`).
- Gone in the module form: the `master.d/kernel.c` row edit, the
  `init_tbl` entry, the `parinit` wrapper, the relocation patches of the
  `cdevsw` row (`patch_*_cdevsw.py`), and any store into `cdevsw` at run
  time. The module kernel's acceptance asks for majors 49, 51 and 52
  neither used nor filled at boot (the brief, §4).
- A STREAMS driver keeps its `streamtab`; its row is zeros except
  `d_str` (`nodev` is not a DDI name: the core reads a zero entry as
  `nodev`, `dlm_slot.c`). The core installs its own open and close
  trampolines in the row and holds the module from the open that sets
  `q_ptr` to the close.
- `/dev` nodes are made by the package or the installer (S3-22, S3-31),
  as today.

### 1.3 Interrupts: `intr_attach`, and polled stays the default

- No patch of `int2_tbl`, `p6int` or `aciabintr`. A handler goes on a
  chain with `intr_attach(level, fn, arg, name)` (level 2 or 6) and comes
  off with `intr_detach(level, fn, arg)`; both in process context.
  Errors: `EINVAL` (level), `EEXIST`, `ECONFIG` (the chain is full: 8 per
  level), `ENXIO` (level 2 before the core armed it).
- The handler is called as `fn(arg)` every time its level fires, whatever
  raised it, and returns nonzero only when its own board did. It must
  return fast when its board did not.
- **A driver with a polled mode keeps it as the default** (30 §4). It
  attaches only once its board is set up to interrupt, in process
  context (the first open, or `_load` if the board is set up there),
  enables the board's interrupt only after a self-test of the attached
  handler passes, and stays polled if either fails. The choice is a
  module parameter (`param intr:int:0:0:6` or as fits: 0 polled).
- **The self-test** raises the level from software and checks that the
  handler ran and claimed: for level 6, `INTREQ` (0xdff09c) = 0xa000
  (SETCLR | EXTER) with the board's own interrupt-pending state set, as
  the board would. The stock CIA-B handler runs once as well, as it does
  for every level-6 interrupt the board raises; that is harmless.
- **Level 6.** No spl masks level 6 in these kernels: `spl5`–`spl7`
  raise to level 4 only (C3-2 §3). So:
  - a level-6 handler shares no state with its own lower-level code
    except under the board's own mask: the lower-level code disables the
    board's interrupt around the shared state and enables it after;
  - **a level-6 handler calls no DDI function.** STREAMS, `timeout`,
    `wakeup` and the allocators protect their state with spl, which a
    level-6 interrupt passes straight through. The handler acknowledges
    its board, masks it, records what happened in the driver's own
    variables, and hands the work to code at level 4 or below: the
    polled path picks it up on its next tick, or a level-2 handler of
    the same driver, attached with it, does the work after the level-6
    handler raises PORTS (a write of 0x8008, SETCLR | PORTS, to `INTREQ`
    at 0xdff09c). The level-2 handler
    claims only when the driver's own flag is set. M-INT1 (S3-44, S3-46)
    measures which of the two the driver keeps;
  - level-2 handlers run below level 4 and may call the DDI as the stock
    level-2 drivers do.
- `_unload` and `_halt` turn the board's interrupt off before
  `intr_detach`.

### 1.4 The console: `cons_hook_set`

- No `conputc` swap, no `c1.c` edit, no `scrcon_put` patch. A driver that
  shows the console registers `fn` with `cons_hook_set(fn)` and removes it
  with `cons_hook_clear()`; one hook at a time (a second is `EBUSY`).
- `fn(cp, p, n)` sees every write to the console, from a virtual terminal
  or from the kernel's `printf`, before the native screen code. These are
  the stock `scrcon_put`'s arguments: `cp` is the **console**, a
  `struct console *` (`amiga/console/console.h` in the kit's `stock/usr/sys`;
  `coputc` passes `&consoles[0]`), and `p` and `n` are the bytes. It
  returns nonzero if it took the write, zero to let the native code draw
  it. It takes only writes to the screen it shows:
  **`cp->screen == displayedscreen`**, the test `c1.c` itself makes.
  `displayedscreen` is the kernel's `struct screen *` (DDI v1 data,
  read-only); no stock header declares it, so the driver declares
  `extern struct screen *displayedscreen;`.
- It is called with the writer's context and spl, which may be an
  interrupt's, and must not sleep.
- `_unload` clears the hook first.

### 1.5 Memory and device windows

- **No DMA interface in DDI v1.0** (C3-2 §3, the 2026-10-26 decision). A
  stage-3 module never gives the address of its own memory (its `.data`
  or `.bss`, `kmem_alloc`, `sptalloc` of RAM) to a board as a physical
  address. Memory the board writes and the CPU reads stays on the board,
  or waits for the stage-4 DMA interface.
- **Device windows** are reached as the kernel maps them, never by
  assuming virtual = physical elsewhere:
  - `phystokv()` (the identity, `<sys/immu.h>`) only for a physical
    range the kernel maps one to one: below `VSECT1`, on both lines, as
    the static drivers do today;
  - otherwise `sptalloc(npages, PG_V, phystopfn(base))` and `sptfree` in
    `_unload`; on k46 `dev_kvmap`/`dev_kvunmap` are in the DDI as well;
  - a `d_mmap` returns `phystopfn()` of device memory only.
- A mapping made in `_load` or at open is released in `_unload`.

### 1.6 Only allowlisted symbols

- Every undefined symbol of the module object is a name of
  `abi/<line>/ddi.list` (DDI v1, C3-2 §3) or a global of a module named
  in `depend` (C3-2 §1). The core refuses any other (`ERELOC`), and the
  kit's checker refuses it at build time. A **weak** undefined symbol is
  not counted: it resolves to 0 when nothing defines it (C3-1 §1), as the
  wrapper macros' `<prefix>_conf_data` does.
- Not in the DDI and gone in the module form: `cdevsw`, `bdevsw`,
  `int2_tbl`, `conputc`, `ifstats` and every other kernel global the
  driver reached directly. `ifstats` becomes `if_attach(ifs)` /
  `if_detach(ifs)` (the driver's `struct ifstats`, which begins with its
  link, goes on or off the stock list; `EEXIST`, `ENOENT`).
- A symbol the driver needs and the DDI lacks is asked for, not worked
  around: it enters DDI v1 as a minor (C3-2 §3), after review.

### 1.7 Built with the kit

- The line's pinned gcc-cross-amix (`gcc-2.7.2.3-8949028`) with
  `AMIX_KERNEL_CFLAGS` and the 060-safe rewrite (C3-1 §1), against the
  kit's headers and the pinned sysroot; on k46 also the 4 KiB page
  geometry the static build uses: the kit's k46 `sys/immu.h` and
  `sys/param.h` are the port's 4 KiB forms (`include-modelb/`), so
  `phystopfn` and `btop` are right; page counts the driver writes as
  numbers are its own to convert.
- `ld -r` of everything the module needs that the kernel does not
  export (a font object, for example) into the one module object.
- `mkmod` writes `.moddata` from the driver's key list: `name`, `kabi`
  (`k30.1.0` / `k46.1.0`), `cc`, `cpu`, `class`, `majors`, `depend`,
  `unload`, each `param`, `desc` (C3-1 §3); `modfix` sets the section
  type.
- The kit's checker passes: the format, the relocation types, the
  undefined symbols against the allowlist, the 68060 scan.
- The kit's make fragment does all of the above; a driver's makefile
  includes it and names its sources and keys. Until the kit lands
  (S3-10, amix-dlm, next after this contract), the source changes of §2–§4
  can be made and compiled; the module objects are made with the kit.

## 2. z3660eth (amix-z3660net, S3-25)

What it does today (amix-z3660net `src/z3660eth.c`; the k46 relink in
amix-040-060-port; the k30 source-kernel path in amix-kerntools):

- a STREAMS/DLPI driver, `streamtab z3660ethinfo`, on major 51:
  - on k46 the `parinit` glue stores `&z3660ethinfo` into
    `cdevsw[51].d_str` at boot;
  - on k30 the `kernel.c` row is edited;
- `z3660ethinit` is registered nowhere; the board is found and mapped at
  first open (lazy open);
- polled RX: `timeout(z3660eth_poll, …, 1)` re-armed every tick from
  open, `untimeout` at last close;
- the board's ethernet interrupt is written off (`ZZ_CONFIG_DISABLE`) at
  init and last close: an enabled INT6 with no handler stormed and hung
  real hardware; `z3660ethintr()` exists, unwired;
- the board window by `phystokv(base)` below `VSECT1`, else `sptalloc`;
  RX and TX through static buffers; board state in `z3660eth_board[]`;
- imports `ifstats` directly; every other import is in DDI v1.

The module:

| Item | Content |
|---|---|
| `.moddata` | `name=z3660eth`, `class=boot`, `majors=c:51`, `unload=never`, `cpu=68030` (k30) / `68040` (k46), `param=intr:int:0:0:6`, `param=intrl2:int:1:0:1` (with `intr=6`: 1 drains in a level-2 handler raised through PORTS, 0 in the poll tick; M-INT1 chooses); `match=zorro:144b:01,mobo:z3660-window`: a boot-class module must carry `match=` (C3-5 §2, gate 3), and with the AGA fixed-base fallback the board can be present without an AutoConfig entry, which is the case the registry's `mobo:z3660-window` probe covers (20 §6) |
| Wrapper | `MOD_DRV_WRAPPER(z3660eth, …)`, the row zeros except `d_str = &z3660ethinfo`, `drv_cmajor` 51 |
| `_load` | find the board as the first open does today (`autocon(0x144B0001)`, then the AGA fallback); `ENXIO` if none. Map the board here (as the module form does), or lazily at first open; `ENOMEM` when no kernel address space is left for it. Write `ZZ_CONFIG_DISABLE`. `if_attach(&ifstats of the board)` here or at first open (once), instead of linking into `ifstats` |
| Interrupts | polled stays the default (`intr=0`). `intr=6`, at the first open: `intr_attach(6, z3660eth_int6, board, "z3660eth")`, and with `intrl2=1` also `intr_attach(2, z3660eth_int2, board, "z3660eth")`; the self-test (§1.3); then the board's interrupt on; polled on any failure. `z3660eth_int6` only acknowledges, masks and flags: on this board one write, `ZZ_CONFIG_DISABLE`, both acknowledges and masks (an acknowledge alone does not mask; the firmware treats acknowledge and enable/disable as exclusive). The drain runs at level 4 or below, in `z3660eth_int2` or the poll tick, never at level 6; the static `z3660ethintr`, which drains at its own level, is not attached. M-INT1 on metal decides the default; the emulator raises no INT6 |
| Memory | unchanged (board window, static buffers); §1.5 holds as is |
| Symbols | `ifstats` → `if_attach`, `if_detach` in `_unload` (§1.1); add `intr_attach`/`intr_detach` |
| `_halt` | `ZZ_CONFIG_DISABLE`, and stop the poll if it can without sleeping |
| `_unload` | present, though `unload=never` refuses `moduload`: the core calls it after a failed load (§1.1). `untimeout`, interrupt off, `intr_detach`, `if_detach`, `z3660eth_unmap` (last close does not unmap today), reset `map_verdict` |
| Kept | `/dev/zen0` (c 51 0) and `S99zen`'s `slink` (S3-31) |

## 3. z3660rtg (amix-z3660rtg, S3-26)

What it does today (`overlay/usr/sys/amiga/driver/zz9000/zz9000.c`; the k46
relink; amix-kerntools' `chardevs.conf`):

- a character driver on major 49: open, close, read, write, ioctl, mmap;
  `zz9000init` (`zz9k_probe(0)`) from `init_tbl` (kerntools) or the
  `parinit` wrapper (the port);
- no interrupts and no timeouts;
- the board window at its physical address (the probe requires it in the
  low 1 GB); `d_mmap` returns `phystopfn(zz9k_devphys(…))`;
- the console by swapping the kernel's `conputc` pointer, from the ioctl
  `ZZ9KIOC_CONSOLE` only (never at boot); the `c1.c` hook of kerntools'
  `console=` option is opt-in and off;
- imports `autocon bootinfo conputc copyin copyout printf uiomove`, the
  three `monsw_*` with `-DZZ9K_MONSW`, `hat_cm_fb_add` with
  `-DZZ9K_FB_NC`; `../../console/sunfont.o` is linked into its object;
- compile-time options: the target (`ZZ9K_TARGET_Z3660` or ZZ9000), the
  console geometry, `ZZ9K_NO_BUILTINFONT`.

The module:

| Item | Content |
|---|---|
| `.moddata` | `name=z3660rtg`, `class=demand` (it loads at the first open of `/dev/zz9000`), `majors=c:49`, `depend=monsw`, `unload=allowed`, `cpu=68030` / `68040` |
| Wrapper | `MOD_DRV_WRAPPER(zz9000, …)`, the six entry points in the row, `drv_cmajor` 49 |
| `_load` | `zz9k_probe(0)`; `ENXIO` if no board. No console at load: as today it is the ioctl's |
| Console | `ZZ9KIOC_CONSOLE` ENABLE and REDIRECT (the same today): `cons_hook_set(zz9k_cons_hook)`, where the hook takes `(cp, p, n)` and returns nonzero only for writes with `cp->screen == displayedscreen` that it drew (not passed on); the per-character `zz9k_conputc` becomes a loop over `p`. DISABLE: `cons_hook_clear()`. No `conputc`. **By design the hook also takes virtual-terminal writes** to the displayed screen, where the `conputc` swap saw only the kernel's `printf`: the RTG then shows that screen as the native code would |
| Memory | unchanged; `d_mmap` hands out device pages only (§1.5) |
| Symbols | `conputc` → `cons_hook_set`/`cons_hook_clear`, plus `displayedscreen`; `monsw_*` through `depend=monsw`. **`hat_cm_fb_add` is not in the DDI:** build without `-DZZ9K_FB_NC` (§5, §6) |
| Font | `sunfont.o` linked into the module object (§1.7), and the module built **without** `ZZ9K_NO_BUILTINFONT` (that option stays for the static k46 relinks). The kit provides a `sunfont.o` the cross tools can link (the stock `sunfont.s` is m4 and SVR4 assembler syntax). `builtinfont` is also a stock k30 kernel name: the module makes it local (`objcopy --localize-symbol=builtinfont`, the make fragment's `LOCALIZE`) so it never shadows or exports it |
| Parameters | the kernel-patchable `zz9k_blit_on` and `zz9k_blit_maxarea` have no patch path in a module: `param=blit:bool:1` and `param=maxarea:int:0:0:<the driver's limit>`, defaults equal to today's patched values |
| Targets | one module per line serves both targets: the probe tells the ZZ9000 and the Z3660 apart at run time, so the target is no longer a compile-time switch in the module form; one name, one major (§6) |
| `_unload` | `cons_hook_clear()` if the console is on; the switch back to native (`ZZ9K_MONSW_SET(0)`, as DISABLE does); `monsw_unregister()` for each board it registered (monsw keeps a pointer to the board's name, which is in this module's `.data`). No timeout and no interrupt is armed. The core does not call it while `/dev/zz9000` is open |
| `_halt` | none, the wrapper's entry 0 (the board neither interrupts nor writes memory) |

## 4. monsw (S3-27)

What it does today (`amix-040-060-port/src/monsw.c`, `src/sys/monsw.h`):
`/dev/monsw` on major 52 (open, close, ioctl), `monswinit` from the
`parinit` wrapper, the kernel API `monsw_set`, `monsw_register`,
`monsw_unregister`, `monsw_lastclose` for the RTG driver, and the
patchable `int monsw_config = -1`. It drives the CIA-B PRA/DDRA bits at
IPL 4 and has static state only. Imports `copyout drv_priv printf`.

The module:

| Item | Content |
|---|---|
| `.moddata` | `name=monsw`, `class=demand` (the first open of `/dev/monsw`, or as z3660rtg's dependency: the core loads a dependency first), `majors=c:52`, `unload=never`, `cpu=68030` / `68040`, `param=config:int:-1:-1:51` |
| Wrapper | `MOD_DRV_WRAPPER(monsw, …)`, open/close/ioctl in the row, `drv_cmajor` 52 |
| `_load` | `monswinit`'s work; `config` from `params` replaces the patched `monsw_config` (a value other than -1 acts as the patched one does today: `MONSWIOC_SETCFG` returns `EBUSY`). A box's value (the owner's boxes: 34) goes in `/etc/conf/modreg.local.d/monsw` or the installer's `modreg.d` default |
| Exports | `monsw_set`, `monsw_register`, `monsw_unregister`, `monsw_lastclose` stay globals of the module: z3660rtg reaches them through `depend=monsw`, never through the kernel's allowlist (C3-2 §1) |
| Symbols | unchanged; all in DDI v1 |
| `_halt` | none, the wrapper's entry 0 |

## 5. Open DDI item (not a stage-3 blocker)

- **`hat_cm_fb_add`**, the 68040/68060 non-cached framebuffer mapping
  z3660rtg uses with `-DZZ9K_FB_NC`, is not in DDI v1.0. If RTG
  performance needs it, it comes as a DDI minor (k46) after the port's
  review.

## 6. Settled at agreement (2026-10-26)

- §1's rules as written, for every driver turned into a module.
- **`hat_cm_fb_add` stays out of the stage-3 z3660rtg module.** The module
  maps its windows without it and builds without `-DZZ9K_FB_NC` (§5).
- **monsw's source location is the owner's decision** (P-8 question (c),
  plan Q3-2). Until he decides, S3-27 stays as the plan says, and nothing
  on z3660eth or z3660rtg waits on it. `<sys/monsw.h>`, which z3660rtg's
  module build includes on both lines, goes with that decision; until
  then the station builds against the port's copy (version 2).
- **z3660rtg is one module per line with a run-time probe for both
  targets** (ZZ9000 and Z3660): one name, one major.
- **The INT6 path's second half** (§1.3), the poll tick or a level-2
  handler raised through PORTS, is M-INT1's to decide on metal. Polled
  stays the default, and the contract keeps both forms.
- **`unload=never` for z3660eth and monsw.** S3-43's allowed-unload row
  uses z3660rtg.
