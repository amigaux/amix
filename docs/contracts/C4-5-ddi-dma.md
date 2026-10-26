# C4-5 — DDI v1.2, the DMA interface, version 6

- **Status:** agreed 2026-10-26 (orchestrator), with §5 settled as
  shape (b) and the loader's clause (§5.2); version 2 (2026-10-26):
  the calls are minor 2 (k30.1.2, k46.1.2), since kabi 1.1 closed with
  the minted kernels (§2); version 3 (2026-10-27, S4-62's first piece):
  `dma_addr(r, pa)` takes the segment's address (§2.3), and the k30
  names are a placeholder until the 030 provider (§5.4); version 4
  (2026-10-27, from the port's heap reading): on k46 `dma_alloc` gives
  heap memory through its DTT0 alias (§3); version 5 (2026-10-27,
  S4-62's second piece, the 030 provider): on k30 a miss for a segment
  the board cannot reach gives `dma_addr` 0, and the driver does not arm
  (§2.2); the provider as built (§5.4); version 6 (2026-10-27, the
  Bench's N109b): the entry-0 decode, the identity map cacheable, so
  §5.4's read-after-complete rule stays (§5.3). Other repositories build
  against this text; a change from here is a contract change with a
  version bump.
- **Implements:** the owner's decision on 80 OQ-80.5 (`docs/plan/stage-4.md`
  Q4-6, "DDI v1.1 DMA", now minor 2): DDI DMA in the shape of the
  040/060 port's `dma_prepare` / `dma_complete`, on both lines, whose
  030 provider bounces through
  memory a Zorro bus master reaches; `20-module-format-and-abi.md` §4
  (`dma_alloc`, `dma_free`); C3-6 §1.5, which this lifts for v1.2
- **Base:** the port's service and record,
  `amix-040-060-port/docs/contracts/DMA040-SERVICE-RECORD.md` (layout
  version 2), and the A4091 driver line's call shape,
  `amix-a4091/docs/D42-CALL-SHAPE.md`. This contract adopts them; it adds
  one call (§2.3) and the memory calls (§3).
- **Providers:** k46, the port's `dma_cache040.s`; k30, the core's
  `core/plat/k30` (S4-62)
- **Read by:** amix-a4091 (A4091/A4092 and the A4000T 53C710 target),
  and any later bus-master driver

## 1. Why

A board that reads or writes memory itself (the 53C710's SCRIPTS and
data phases) needs two things the DDI v1.0 lacked:
1. **cache coherency** with the CPU's copyback caches around a transfer.
   The port's service does this on 040/060 by physical line;
2. **reachable memory.** On the 030 line with a Z3660, boot2 binds the
   kernel in the card's DDR, which Zorro DMA cannot reach (80 OQ-80.5).
   A transfer from or to such memory must go through memory the bus
   master reaches: motherboard fast RAM, or Zorro RAM.

C3-6 §1.5 ("never give a board the address of the module's own memory")
stands for every module that does not use this interface.

## 2. The calls (minor 2, both lines)

### 2.1 `dma_prepare`, `dma_complete`

As the port's record defines them, unchanged:

```c
int  dma_prepare (struct dma_rec *r, ulong pa, ulong len, int dir);
void dma_complete(struct dma_rec *r, ulong pa, ulong len, int dir);
#define DMA_TO_DEVICE    0
#define DMA_FROM_DEVICE  1
```

- `struct dma_rec`: 0x60 bytes, layout version 2, owned by the driver,
  one per controller instance. The field table and the D/S ownership
  are the port's document's.
- `pa` is physical. `prepare` is called after the driver has built what
  the device reads and before the write that arms it; `complete` after
  the device has stopped and before the completion callback.
- Callable at any level the driver runs at; neither sleeps, panics or
  touches the device.

### 2.2 What each line's provider does

| | k46 (the port's) | k30 (the core's, S4-62) |
|---|---|---|
| `prepare` | pushes the CPU's dirty lines over `[pa, pa+len)` and takes ownership | if `[pa, pa+len)` is reachable: as k46's, with the 030's cache operations. If not, takes a bounce buffer of `len` from the pool (§3), copies the bytes into it for `TO_DEVICE`, and owns that |
| `complete` | invalidates the owned lines for `FROM_DEVICE` | for a bounced `FROM_DEVICE`, copies the bounce buffer back to `pa`; then gives the buffer back |
| `dma_addr` (§2.3) | `pa` | the bounce buffer's physical address when bounced; `pa` when the board reaches it; else 0 |
| bounce buffers | the driver's own (its misaligned-read bounce, D42) | 16-byte aligned and rounded up to 16-byte lines, so a driver's own bounce in `dma_alloc` memory is never bounced again, and `edge_shared` stays 0 |

A `prepare` that cannot get a bounce buffer returns nonzero, as the
port's does when the seam is off, and counts the miss in the record's
`off_n`. On k46, and for a segment the board reaches on k30, the driver
arms all the same with `dma_addr(r, pa)` (§2.3), which gives `pa`. **For a
segment the board cannot reach (version 5), `dma_addr` gives 0: the
driver does not arm, and fails the transfer** (`EIO`, or a retry after
other transfers have given their bounces back). Arming such a segment
would point the board at memory it cannot reach.

### 2.3 `dma_addr`

```c
ulong dma_addr(struct dma_rec *r, ulong pa);
```

The physical address the device must be armed with for the segment at
`pa` after `prepare`: `pa` on k46 and for a reachable segment on k30,
the bounce buffer's address when `r` owns a bounce for that `pa`. A
driver written for both lines arms with `dma_addr(r, pa)` where the
port's driver armed with `pa`. This is the one change to the port's call
shape, and on k46 it is the identity.

`pa` is an argument (version 3) because the record cannot always give
it: on a miss the port's `prepare` stores nothing, and when a segment is
still owned the record's `pa` is the earlier segment's. A `dma_addr(r)`
reading the record would arm the device with a wrong address in exactly
the case §2.2 tells the driver to arm past.

**Where the address is taken** (the a4091 station and the port,
2026-10-26, from `amix-a4091/src/a4091-wr.c` at 27d2079):
- The A4091 driver has **one** site. The data address reaches the
  53C710 only through the DSA table (`ds.data1buf`), which a
  table-indirect MOVE reads; the DSP writes arm SCRIPTS, not data. The
  short-read recovery re-launch reuses the same table and segment, and
  there is no reconnect (IDENTIFY 0x80, no disconnect privilege).
- The order therefore becomes: `dma_prepare`, then
  `ds.data1buf = dma_addr(r, pa)`, then the DSP write. Today the table is
  built before `prepare`.
- The floor's A3091 (the A3000 WD33C93 DMAC), which the port's
  `dma_cache040.s` wraps, has two arm sites: the initial arm and the
  reconnect re-arm. If a k30 provider ever serves it, both take
  `dma_addr`. On k46 the result equals `pa`, so the stock bytes need no
  change.

## 3. Reachable memory: `dma_alloc`, `dma_free`

```c
char *dma_alloc(ulong len, ulong *pa);	/* proc; 0 when none */
void  dma_free(char *va, ulong len);
```

- `dma_alloc` gives `len` bytes the board can reach: a kernel virtual
  address, and its physical address in `*pa`. They are for what lives in
  host memory for the whole life of a transfer queue: SCRIPTS, the
  message and status buffers, the descriptor tables.
- On k46 it is kernel memory reached through the DTT0 identity map
  (0x00000000–0x3FFFFFFF, cache-inhibited), where the port's line keeps
  the driver's DMA structures today, as kernel-image statics in the
  Z3660's RAM. Zorro III bus-master DMA reaches it, proven on metal by
  the A4092 root rows (the port, 2026-10-26). The kernel heap's
  addresses lie in the kernel map above 0x40000000, but its pages are
  that RAM (the port, 2026-10-27): so `dma_alloc` takes a heap block,
  requires its pages physically contiguous below 0x40000000, and returns
  the physical address itself as the pointer (equal to `*pa`), a
  cache-inhibited alias. It pushes and invalidates the block by physical
  line at alloc and at free, against the heap mapping's own cache lines.
  **dma_alloc memory is addressed through the identity map; the kernel's
  own heap alias must not be used by the driver after dma_alloc
  returns.** The core keeps the heap address in the block's header,
  read through the alias, for `dma_free`.
  On k30 the memory comes from the pool (§5).
- As a module, a driver moves the structures it hands the chip (the
  DSA table, the SCRIPTS, the ident, CDB, status and message buffers,
  its own bounce: about 1.3 KiB for the A4091) into one `dma_alloc`
  area. A module's own `.data` is in the arena or kmem, which C3-6 §1.5
  forbids handing a board, and on k30 it is unreachable. SCRIPTS that are
  position-independent (relative jumps, table-indirect moves) copy
  unchanged, and DSP is their physical address.
- 16-byte aligned; at most 64 KiB a call; never freed while the device
  may touch it.
- In the root pass, `dma_alloc` is allowed as `KM_NOSLEEP` is: it never
  sleeps and returns 0 when the pool is short.

## 4. A driver's use

1. At `_load` (in the root pass for a root controller): `dma_alloc` the
   SCRIPTS and the per-unit buffers; initialise one `struct dma_rec` per
   controller (`magic`, `version` 2, `ctlid`, `unit`).
2. Per data transfer: `dma_prepare(r, pa, len, dir)`; then put
   `dma_addr(r, pa)` where the device takes the data address (for the 53C710,
   the DSA table); then arm; on completion `dma_complete(r, pa, len,
   dir)`.
3. The same calls on both lines. The 030 build, which today makes none,
   enables the seam too.
4. Zero-length transfers make no call (`drv_zero`, as the port's).
5. `_halt` stops the chip (C4-2 §5). An owned segment is then abandoned
   with the halt.

## 5. Where k30's pool comes from

### 5.1 What the k30 kernel does with memory

From the K030-U relink kit and the stock base (amix-kerntools, read
2026-10-26):
- The kernel's allocator takes **only the region it is bound in**.
  `config()` (`amiga/kernel/support.c`) copies `bootinfo.memory[]` as
  MemHeaders and sets the main store to the region holding `end`, joined
  with regions that touch it, reading only `mh_Lower` and `mh_Upper`;
  `mlsetup`, `kvm_init` and `page_init` then work over that range alone.
  Every other `memory[]` entry is ignored, so motherboard RAM below a
  Z3660 bind at 0x08000000 is never on a free list.
- The kernel never reads `mh_Attributes`: RAM is told apart by address
  (motherboard RAM ends at 0x08000000, CPU-card RAM starts there).
- `pstart` maps 0–1 GiB one to one, so motherboard and Zorro II RAM are
  reachable at a kernel address equal to the physical one. Zorro III RAM
  at 0x40000000 and above is not mapped, and cannot hold the pool.

### 5.2 The pool

**Shape (b):** the k30 provider (`core/plat/k30`, S4-62) makes the pool
at `dmainit`, with no kernel change and no new loader record:
- it takes a `memory[]` entry that is not chip RAM, lies below
  0x08000000 and is outside the main store, and carves the top 64–256 KiB
  of it, managed with a resource map (the pattern of the kernel's
  chip-RAM map, `amiga/console/memory.c`);
- when the main store itself lies below 0x08000000 (no CPU-card bind),
  everything the kernel allocates is reachable: `dma_alloc` takes kernel
  memory and nothing is bounced.

**The loader's clause** (10 §3.2): on k30, a region that touches the
bind region from below ends **one 2 KiB page short** of the bind base in
the `memory[]` boot2 hands over, instead of being emptied. `config()`'s
join test then fails, the region stays out of the main store, and its
range stays intact for the pool. boot2 pays for it in S4-11.

The pool is reachable by a 32-bit Zorro III bus master (the A4091). A
24-bit master (the A2091) reaches only chip and Zorro II RAM, which this
pool does not promise.

### 5.3 The k30 provider's acceptance (S4-62)

- **A force-bounce test hook:** a switch that bounces every segment,
  reachable or not. Amiberry's bank at 0x08000000 is reachable by
  emulated Zorro DMA, so a missed bounce passes in emulation and only
  metal shows it.
- **The cache mode of the identity map:** decode the status bits of the
  root-table entry 0, which differ from those of entries 2 and 3, before
  the first `FROM_DEVICE` test, to know whether the 030 data cache is on
  for the memory the pool and the bounce buffers live in. **Decoded**
  (amix-kerntools, N109b on kern30m -14, read live through `/dev/kmem`
  from `pstart`'s root table at `cpuroot`):
  - entry 0 `0x7fff0319 0x00000000`: an early-termination page
    descriptor, VA 0–1 GiB to PA 0, **CI clear: cacheable**;
  - entries 2 and 3 `0x7fff0341 0x80000000` / `0xc0000000`: CI set;
  - `pstart` writes status 0xc0 into entry 0 and 0xd0 into entries 2 and
    3; the 0x10 between them is CI, and nothing changes it later.

  So the pool and every bounce buffer lie in cacheable memory behind a
  write-through data cache, and §5.4's rule stays: a driver reads what the
  board wrote into `dma_alloc` memory only after a `dma_complete`.
- **The force-bounce hook and the pool, measured:** `dma_pool`
  0x07fdf800, `dma_poolsz` 0x20000, ending one 2 KiB page below the
  0x08000000 bind (10 §3.2); the console's `dma: pool 128 KiB at
  0x7FDF800` (N108).

### 5.4 The 030 provider (`core/plat/k30`, S4-62)

- **At `dmainit`** (`plat_line_init`): the pool is the top 128 KiB of the
  largest fast `memory[]` region between 0x00200000 and 0x08000000 that
  does not hold the kernel. When there is none and the kernel itself runs
  below 0x08000000, `dma_alloc` takes the heap through its identity
  alias, as k46 does, and nothing is bounced. Otherwise bus-master DMA is
  off: `dma_alloc` returns 0 and the console says so.
- **Reached:** a segment within 0x00200000–0x08000000 is not bounced.
  Chip memory and the CPU card's DDR are bounced.
- **The pool:** 16-byte lines, first fit over a map of free extents,
  joined on free, under level 7; `dma_alloc` and the bounces share it.
- **The cache:** the 68030's data cache is write-through, so nothing is
  pushed. `dma_complete` for `FROM_DEVICE` clears the whole data cache
  (CACR CD) before the bounce is copied back or the driver reads the
  bytes.
- **The force-bounce hook:** the kernel global `dma_forcebounce`, nonzero
  bounces every segment (§5.3).
- **The read-after-complete rule:** the identity map is cacheable (the
  entry-0 decode, §5.3), so a driver reads what the chip wrote into
  `dma_alloc` memory (status, message buffers) only after a
  `dma_complete`, which clears the data cache. This is permanent on k30.

## 6. Not in this contract

- The 53C710 drivers' own SCRIPTS and register use (amix-a4091).
- The port's record layout (its document; version 2 adopted here as is).
