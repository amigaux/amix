# D42: how the A4091 calls the DMA-coherence service

Status: **proposal**, 2026-09-28. This is the text we send before the final code. Nothing here is agreed yet. The service side does not exist. The A4091 side is written against it and links with local stubs today (`src/a4091_dma040.h`, `src/a4091-wr.c` under `-DA4091_KVA`).

## The cut (D42 as amended, 2026-09-27)

- **One protocol and one state machine**, in the port's `src/dma_cache040.s`. There is no parallel copy in any driver.
- **The per-controller record lives in each controller's own object.** The service is handed a pointer to it on every call, so it needs no registration and can be tested on the machine that has that controller.
- The A3091's B2 wrappers (`dma_a3091_startdma` / `dma_a3091_stopdma`, one global record) stay as they are. The generalized entry points below take the record as an argument. The A3091 could later move onto them with its own record.

## Entry points

Plain C calling convention: arguments on the stack, right to left. `d0/d1/a0/a1` are scratch. Every other register is preserved.

```c
int  dma040_prepare (struct dma040_rec *r, ulong pa, ulong len, int dir);
void dma040_complete(struct dma040_rec *r, ulong pa, ulong len, int dir);

#define DMA040_TO_DEVICE    0   /* device reads RAM  (SCSI write) */
#define DMA040_FROM_DEVICE  1   /* device writes RAM (SCSI read)  */
```

Both entry points have the same contract:

- They are callable at any IPL the driver runs at.
- They never sleep and never panic.
- They never touch the device.

**`prepare`** is called after the driver has built everything the device will read, and before the write that arms the device. On the A4091 that write is `DSP`, which starts SCRIPTS.

- It takes ownership of `[pa, pa+len)` and pushes the CPU's dirty lines over it.
- It returns `0` when the record is `PREPARED`, and nonzero when it is not (the record is off, a segment is still owned, or the range is bad).
- The driver arms either way. It keeps no state of its own about the result.

**`complete`** is called after the device has stopped touching the segment, and before the driver's completion callback. On the A4091 that callback is `sdcom.intr`, which may re-enter the driver for the next request.

- For `FROM_DEVICE` it invalidates the owned lines. For `TO_DEVICE` it does no cache op.
- It consumes the record: the state goes to `EMPTY`.
- The `(pa, len, dir)` passed to it are the same as the ones passed to `prepare`. That lets the service count a mismatch without trusting either side.

**`pa` is physical.** `sdcom.addr` is physical by contract on this line. The service works by physical line (`cpushl`/`cinvl` on 16-byte lines), so one operation covers every virtual alias of the page. That includes a raw-I/O buffer's copyback user mapping.

## The record

`struct dma040_rec` is 0x5c bytes. Every field is a longword, so the service can reach each one with `movel d16(a0)`. The offsets are the contract.

In the "who" column, D means the driver writes the field and the service only reads it. S means the service writes the field and the driver only reads it, for diagnostics.

| off | field | who | meaning |
|---|---|---|---|
| 0x00 | `magic` | D | `0x44343252` "D42R". Static; proves the address to a kmem reader |
| 0x04 | `version` | D | layout version, 1 |
| 0x08 | `ctlid` | D | driver family: the AutoConfig id (A4091: `0x02020054`) |
| 0x0c | `unit` | D | controller instance (sd card number) |
| 0x10 | `off` | D | nonzero means the seam is **off**: the service counts the call, does no cache op and takes no ownership |
| 0x14 | `state` | S | 0 EMPTY, 1 PREPARING, 2 PREPARED (the B2 values) |
| 0x18 | `dir` | S | direction of the owned segment |
| 0x1c | `pa` | S | owned segment: physical base |
| 0x20 | `len` | S | owned segment: length |
| 0x24 | `seq` | S | prepares that took ownership |
| 0x28 | `prep_to` | S | prepares, TO_DEVICE |
| 0x2c | `prep_from` | S | prepares, FROM_DEVICE |
| 0x30 | `cmpl_to` | S | completes consumed, TO_DEVICE |
| 0x34 | `cmpl_from` | S | completes consumed, FROM_DEVICE |
| 0x38 | `prep_owned` | S | prepare while a segment is still owned: the call arms without ownership, and the live record is not overwritten |
| 0x3c | `cmpl_noprep` | S | complete with no PREPARED record: no cache op |
| 0x40 | `cmpl_mismatch` | S | complete whose `(pa,len,dir)` differs from the owned segment: the service uses the **owned** one |
| 0x44 | `range_ovf` | S | `pa + len` wrapped: refused, no ownership |
| 0x48 | `off_n` | S | calls seen while `off != 0` |
| 0x4c | `drv_prep` | D | prepare calls the driver made |
| 0x50 | `drv_cmpl` | D | complete calls the driver made |
| 0x54 | `drv_zero` | D | zero-length transfers: the driver made no call |
| 0x58 | `drv_quiesce` | D | completes that followed a forced quiesce (see below) |

**Who owns the record.** The controller object owns it. The A4091 keeps one record per sd card in `a4091_dmarec[SDCARDS]`, a global the service or a kmem reader can find by name. The driver fills the identity fields (magic, version, ctlid, unit, off) at attach, before the first transfer. That is the `hat_cm_fb` registration contract: register before first use, never removed. The service never allocates or frees a record.

**The off switch.** The driver copies its patchable knob `a4091_dma040_off` into `off` before every `prepare`, so one poke switches the seam for every A4091 card. It is DL-02's control arm: with the seam off and the data cache live, the emulator's copyback model should show the missing push/invalidate.

**Acceptance invariants** (read by kmem; none of them panics):

- `drv_prep == drv_cmpl` (every prepare is paired).
- With `off == 0` throughout: `prep_to + prep_from + prep_owned + range_ovf == drv_prep`, and `cmpl_to + cmpl_from + cmpl_noprep == drv_cmpl`.
- When idle: `seq == cmpl_to + cmpl_from`.
- `prep_owned == cmpl_noprep == cmpl_mismatch == range_ovf == 0`.
- With `off != 0`: `off_n` grows by one per call, and nothing else in the S fields moves.

## When the A4091 calls them

The A4091 driver is **synchronous and polled**. `a4091queue()` builds the DSA table, arms SCRIPTS, then polls `ISTAT` for `SIP|DIP` (at most 8,000,000 reads). `a4091intr()` is empty. So "after its interrupt" means after the polled `ISTAT` shows the chip halted.

1. Build the DSA table (command, status and message buffers live in kernel `.data` under DTT0's cache-inhibited identity; A4-12 audits that).
2. `prepare(r, cp->addr, cp->nbyte, cp->reading ? FROM : TO)`. Skipped (counted in `drv_zero`) when `nbyte == 0`.
3. `WR32(DSP)` arms SCRIPTS. Poll `ISTAT`.
4. On a short read (phase mismatch in DATA_IN), the FIFO is drained and SCRIPTS is re-launched at the phase dispatch. That moves only STATUS/MSG into `.data`, not a new segment, so it needs no second prepare.
5. On the poll bound (`rc == -2`), SCRIPTS may still be running. The driver first dumps the chip state, then quiesces (abort + soft reset, the same sequence every I/O starts with) and counts `drv_quiesce`.
6. `complete(r, same pa, len, dir)`.
7. `cp->intr(cp)`: the sd callback. It may re-enter `a4091queue` for the next request. By then the record is EMPTY.

At most one segment is owned per record at any time. The sd layer issues one command per card at a time, and the driver does not return until it has completed.

**Direction** comes from `sdcom.reading`. `dd.c` and `ct.c` set it. GSIO (`/dev/scsi`) takes it from the caller. A GSIO read labelled as a write would get no invalidate. GSIO is at most 1 KB on the driver line.

## What we ask of the service

- **Prepare by range, not whole-cache.** The pilot `cpusha dc` stays correct, since it writes dirty data back rather than discarding it. But the B2 note "the A3091 is the only host-RAM DMA owner" no longer holds with an A4091 (and the Z3660 piscsi) in the machine. A per-range `cpushl` over the owned lines is what several owners want.
- **Invalidate after a push on the 060.** `cpushl` invalidates only with CACR.DPI clear. z3660scsi pairs every `cpushl` with a `cinvl`. U56 is whether `cpusha dc` behaves as B2 assumes with DPI clear, and our LC060 + A4091 run (MD-1) should isolate that number.
- **Edge lines.** The service rounds the range outward to 16-byte lines. sd transfers are block-aligned. A misaligned GSIO buffer shares its edge lines with unrelated data. B2's rule (the CPU must not touch the owned rounded range until complete) holds on the A4091 path because the driver runs synchronously. Interrupt code that dirties a shared edge line mid-transfer would lose that write to the completing `cinvl`. Say whether you want the edges pushed again at complete, before the invalidate.
- **Names.** `dma040_prepare` / `dma040_complete` / `struct dma040_rec` are placeholders. We will take whatever names and offsets you choose, and the magic, before the final code.

## Today, until the service exists

- Without `-DA4091_D42`, `a4091-wr.c` defines both entry points as **local stubs**. They do no cache maintenance and leave the service fields untouched. They count `a4091_kstat.stub_prep` / `stub_cmpl`.
- Attach prints `D42 seam STUB (no cache maintenance)`. A stub kernel is coherent only with the data cache off, which is every emulated cell today. **It must not be taken to metal with a live data cache as a coherence candidate.**
- With `-DA4091_D42` the object imports `dma040_prepare` and `dma040_complete`. `tools/build-a4091-040.sh --d42` gates that import set.
- A coherence verdict comes only from metal (MD-1/MD-4). The emulator shows at most a missing CPUSH/CINV, with the cache kept live (AB-03).
