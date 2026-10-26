# C4-5 — DDI v1.1, the DMA interface, version 1

- **Status:** draft 2026-10-26 (amix-dlm), for the orchestrator's
  agreement; §5 holds one decision still open. Once agreed, other
  repositories build against this text, and a change is a contract change
  with a version bump.
- **Implements:** the owner's decision on 80 OQ-80.5 (`docs/plan/stage-4.md`
  Q4-6): DDI v1.1 DMA in the shape of the 040/060 port's `dma_prepare` /
  `dma_complete`, on both lines, whose 030 provider bounces through
  memory a Zorro bus master reaches; `20-module-format-and-abi.md` §4
  (`dma_alloc`, `dma_free`); C3-6 §1.5, which this lifts for v1.1
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

## 2. The calls (minor 1, both lines)

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
| `dma_addr` (§2.3) | `pa` | the bounce buffer's physical address when bounced, else `pa` |

A `prepare` that cannot get a bounce buffer returns nonzero, as the
port's does when the seam is off, and the driver arms all the same. So
the k30 driver must arm with `dma_addr(r)` (§2.3), which then gives `pa`
and counts the miss in the record's `off_n`.

### 2.3 `dma_addr`

```c
ulong dma_addr(struct dma_rec *r);
```

The physical address the device must be armed with for the segment `r`
owns after `prepare`: `pa` on k46 and for a reachable segment on k30,
the bounce buffer's address for a bounced one. A driver written for both
lines arms with `dma_addr(r)` where the port's driver armed with `pa`.
This is the one change to the port's call shape, and on k46 it is the
identity.

## 3. Reachable memory: `dma_alloc`, `dma_free`

```c
char *dma_alloc(ulong len, ulong *pa);	/* proc; 0 when none */
void  dma_free(char *va, ulong len);
```

- `dma_alloc` gives `len` bytes the board can reach: a kernel virtual
  address, and its physical address in `*pa`. They are for what lives in
  host memory for the whole life of a transfer queue: SCRIPTS, the
  message and status buffers, the descriptor tables.
- On k46 it is kernel memory as the port's line uses it today. On k30
  the memory comes from the pool (§5).
- 16-byte aligned; at most 64 KiB a call; never freed while the device
  may touch it.
- In the root pass, `dma_alloc` is allowed as `KM_NOSLEEP` is: it never
  sleeps and returns 0 when the pool is short.

## 4. A driver's use

1. At `_load` (in the root pass for a root controller): `dma_alloc` the
   SCRIPTS and the per-unit buffers; initialise one `struct dma_rec` per
   controller (`magic`, `version` 2, `ctlid`, `unit`).
2. Per data transfer: `dma_prepare(r, pa, len, dir)`; arm the device with
   `dma_addr(r)`; on completion `dma_complete(r, pa, len, dir)`.
3. Zero-length transfers make no call (`drv_zero`, as the port's).
4. `_halt` stops the chip (C4-2 §5). An owned segment is then abandoned
   with the halt.

## 5. Open: where k30's pool comes from

The pool must be physical memory a Zorro bus master reaches, sized for
the bounce buffers and the `dma_alloc` areas (64 KiB–256 KiB). The
kernel's own allocator cannot ask for a physical range. The candidates:

- **(a) boot2 reserves it.** It takes the pool from the top of the
  largest region a bus master reaches (motherboard fast RAM, or Zorro
  RAM), shortens that `memory[]` entry as it does for the RAM disk
  (C4-3 §2; the same code), and hands the address and size to the
  kernel. The loader record AXL1 is full at 124 bytes, so this needs
  AXL1 version 2 with 8 more bytes. Room exists: 188 of bootinfo's 244
  visible reserved bytes follow RTH1. It costs boot2 bytes (measured
  with S4-11). kbootset asks for it with a `dmapool <size>` manifest
  record only on a k30 generation with a Zorro bus-master root module.
- **(b) the kernel reserves it** at `dmainit`, from a `memory[]` region
  it recognises as reachable, before the page allocator takes the
  region. This is a change to the K030-U kernel's memory sizing
  (amix-kerntools), and costs no boot2 bytes.

**Recommendation: (b)** if the relink kit's memory-sizing code allows a
reservation by physical range, because it keeps boot2's bytes and the
loader record as they are. Otherwise (a). amix-kerntools answers which
from the relink kit before S4-62 starts.

## 6. Not in this contract

- The 53C710 drivers' own SCRIPTS and register use (amix-a4091).
- The port's record layout (its document; version 2 adopted here as is).
