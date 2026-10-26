# a4091 — the root-class module

The A4091 SCSI driver (`src/a4091-wr.c`) as an Amix loadable kernel module of
class `root`. It drives the A4091, the A4092 and the A4770 (all NCR 53C710).
The module core's root pass (`marc_root`) loads it before the root filesystem
is mounted, and it registers each board with sd.

The contracts are amix-dlm's:
- C4-2 version 3: the root-class driver form, and the A4091 row of §8;
- C4-1 version 2: `sd_register` and the four cards;
- C4-5 version 3: DDI 1.2 DMA;
- C3-1: the object;
- C3-6: what a driver changes.

There is one source. `-DA4091_MODULE` selects the module form, and
`-DA4091_KVA` is added on k46. Without them the file is the static driver,
byte for byte.

## Build

```sh
make -C module                 # build/k30/mod.d/a4091, build/k46/mod.d/a4091
make -C module k46             # one line (or k30)
make -C module clean
```

The kits are amix-dlm's ABI kits (`DLM=…/amix-dlm`, default the sibling
checkout's `build/kit/<line>`). You can also name them with `KIT_k30=` /
`KIT_k46=`.
- Build against kabi `k30.1.2` / `k46.1.2`, KIT_REV bbd20b6 or later: the
  first kit whose DDI lists the five DMA names.
- The pinned cross tools (`m68k-cbm-sysv4-*`, gcc-cross-amix's
  `build/env.sh`) and `python3` must be on `PATH`.
- The kit's modcheck then gives `a4091: ok (k46.1.2, root, …)` and
  `a4091: ok (k30.1.2, root, …)`.

The static objects are built elsewhere, and the module switch leaves them
unchanged:
- 030: `b5042e96…`, by amix-kerntools;
- 040/060: `c9f0e467…`, and `7d75ab42…` with `--d42`, by
  `tools/build-a4091-040.sh`.

## The module

| Item | Content |
|---|---|
| `.moddata` | `name=a4091`, `class=root`, `match=zorro:0202:54,zorro:c0de:01,zorro:c0de:02`, `rank=zorro`, `unload=never`, `cpu=68030` / `68040`, `kabi=k30.1.2` / `k46.1.2`. No `majors`: sd owns the disk majors |
| Wrapper | `MOD_HDRV_WRAPPER(a4091, a4091_load, 0, a4091_halt, …)`: no switch-table slot, no `_unload` |
| `_load` | Takes one `dma_alloc` area and copies the SCRIPTS into it. Then, for every board `autocon()` finds (four at most): maps it, fills its D42 record, and calls `sd_register(a4091queue, k, base, name, 2)` |
| `_halt` | On every mapped board, the init path's abort and soft reset: SCRIPTS stopped, SIEN/DIEN 0 |
| Interrupts | None in v1. The driver is synchronous and polled, as the static one; `root_defer` is not called (C4-2 §8) |
| DMA | Through C4-5: `dma_prepare`, then `ds.data1buf = dma_addr(r, pa)`, then the DSP write; `dma_complete` before the sd callback. One site: the 53C710 takes the data address only from the DSA table |
| Version | `VERSION` (`1.0.0-1`), the package version |

### The `dma_alloc` area

Everything the chip reads or writes besides the caller's buffer is in one
area of 1328 bytes, never in the module's own `.data`. C3-6 §1.5 forbids
handing a board the module's own memory, and on k30 the arena is out of a
Zorro master's reach.

| Offset | Content |
|---|---|
| 0x000 | the SCRIPTS, 184 bytes, copied from the template |
| 0x0b8 | the DSA table, 76 bytes |
| 0x104 | the IDENTIFY, CDB, status and message buffers, 28 bytes |
| 0x120 | the misaligned-read bounce, 1040 bytes (D42 "Bounce") |

- The SCRIPTS are position-independent (relative jumps, table-indirect
  moves), so they copy unchanged, and DSP is the copy's physical address.
- On k46 the area is identity-mapped, cache-inhibited kernel memory below
  0x40000000, the same class the static 040/060 driver's statics live in.
- On k30 it comes from the core's pool (C4-5 §5.2).

### Boards and cards

`a4091queue(c, cp)` takes the board index `c` the module registered:
- The per-card tables are indexed by `c` and sized 4 (C4-1 §2.3).
- The static driver indexes them by `cp->card` and sizes them `SDCARDS`.
- sd assigns the card numbers after registration closes (rank, then base).
- The D42 record's `unit` is `c`.

## What `_load` does in the root pass

`_load` runs in process 0 inside `rth1_mountroot`, at **level 7 with the
clock stopped** (C4-2 §2). There it:
- takes the `dma_alloc` area (never sleeps; 0 when there is none);
- asks `autocon()` for each product in turn: 0202:54, then c0de:01, then
  c0de:02;
- maps each board:
  - **k46:** `dev_kvmap` NCS pages, and a first-touch `bprobe` of ISTAT, so
    a dead window is "no board", not a bus error;
  - **k30:** `sptalloc`, as the static 030 driver does, with no fixed
    0x40000000 fallback;
- prints the k46 attach line per board;
- calls `sd_register()` once per board that mapped.

It returns:
- 0: linked;
- `ENXIO`: no board answered;
- `ENOMEM`: no `dma_alloc` area;
- `sd_register`'s errno, after it has stopped its boards and freed the
  area.

A board that does not map is skipped, and the others are registered.

## What it cannot do there, and does not

It never sleeps, calls `timeout()` or `delay()`, waits for an interrupt or
`lbolt`, allocates with `KM_SLEEP`, takes a page fault or runs an interrupt
self-test.

The queue path's polls are bounded by a read count. The once-per-card SCSI
bus reset before a board's first command (A4-22) is timed by the beam
counter (VHPOSR), not by the clock. So sd's first open (`rth1_apply`, still
in the root pass) can drive the board at level 7.

## The line status (2026-10-27)

- **k46:** the provider is the port's `dma_cache040.s`. `dma_addr` is the
  identity, and `dma_alloc` gives kernel memory. **Test the module here.**
- **k30:** the provider is a **placeholder** until S4-62's 030 piece:
  `dma_alloc` returns 0, so **`_load` returns `ENOMEM` and the module does
  not link on k30 yet.** The object builds and passes modcheck. It gets its
  first test when the core's pool exists.
- **A4092** (manufacturer 0xc0de): it needs the kernel's unsigned
  `autocon()` shift. Both module kernels have it:
  - kern46m -77 carries the port's ISSUE-76 `lsrl`;
  - kern30m -12's cut tree has `support.c.patch` (A4-23).
- **A4770:** in the match keys as `driver.conf` has it; untested on hardware.
- **Emulation first** (amiberry's A4091 rows), metal later.

## Package (C3-5)

The package carries the module object and its `modreg` line only, with no
device nodes: sd lays the disk nodes. There is one package per line,
because the kabi differs (C3-5 §1.1):

| Line | Catalog name | pkginst | Version |
|---|---|---|---|
| k30 | `a4091-k30` | `a409130` | `module/VERSION` |
| k46 | `a4091-k46` | `a409146` | `module/VERSION` |

The short name `a4091` is proposed for C3-5 §1.1's table; C3-5 version 9
has no row for it yet.
