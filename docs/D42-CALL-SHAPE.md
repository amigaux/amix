# D42: how the A4091 calls the DMA-coherence service

Status: **agreed contract**, 2026-09-28. Names, magic, offsets, cache ops and edge policy are the port author's D42 decisions (letter 04, answering our proposal). The service side (`src/dma_cache040.s` in the port) is not written yet; the A4091 side is written against this contract and links with local stubs until it is (`src/a4091_dmarec.h`, `src/a4091-wr.c` under `-DA4091_KVA`). The port will carry the same offsets table under its `docs/contracts/`.

## The cut (D42 as amended, 2026-09-27)

- **One protocol and one state machine**, in the port's `src/dma_cache040.s`. There is no parallel copy in any driver.
- **The per-controller record lives in each controller's own object.** The service is handed a pointer to it on every call, so it needs no registration and can be tested on the machine that has that controller.
- The A3091's B2 wrappers (`dma_a3091_startdma` / `dma_a3091_stopdma`, one global record) stay as they are. The generalized entry points below take the record as an argument. The A3091 could later move onto them with its own record.

## Entry points

The names follow the kernel's DMA family (`dma_a3091_startdma`, `dma_cmpl_noprep`, `dma_magic`): a bare `dma_`, no `040` suffix. Plain C calling convention: arguments on the stack, right to left. `d0/d1/a0/a1` are scratch. Every other register is preserved.

```c
int  dma_prepare (struct dma_rec *r, ulong pa, ulong len, int dir);
void dma_complete(struct dma_rec *r, ulong pa, ulong len, int dir);

#define DMA_TO_DEVICE    0   /* device reads RAM  (SCSI write) */
#define DMA_FROM_DEVICE  1   /* device writes RAM (SCSI read)  */
```

Both entry points have the same contract:

- They are callable at any IPL the driver runs at.
- They never sleep and never panic.
- They never touch the device.

**`prepare`** is called after the driver has built everything the device will read, and before the write that arms the device. On the A4091 that write is `DSP`, which starts SCRIPTS.

- It takes ownership of `[pa, pa+len)`, rounded outward to 16-byte lines, and runs `cpushl dc` then `cinvl dc` on each line (see Cache ops).
- For `FROM_DEVICE` it counts `edge_shared` when `pa` or `pa + len` is not 16-byte aligned (see Edge lines).
- It returns `0` when the record is `PREPARED`, and nonzero when it is not (the record is off, a segment is still owned, or the range is bad).
- The driver arms either way. It keeps no state of its own about the result.

**`complete`** is called after the device has stopped touching the segment, and before the driver's completion callback. On the A4091 that callback is `sdcom.intr`, which may re-enter the driver for the next request.

- For `FROM_DEVICE` it runs `cinvl dc` over the owned lines, and nothing else: no second push of the edge lines. For `TO_DEVICE` it does no cache op.
- It consumes the record: the state goes to `EMPTY`.
- The `(pa, len, dir)` passed to it are the same as the ones passed to `prepare`. That lets the service count a mismatch without trusting either side.

**`pa` is physical.** `sdcom.addr` is physical by contract on this line. The service works by physical line (`cpushl`/`cinvl` on 16-byte lines), so one operation covers every virtual alias of the page. That includes a raw-I/O buffer's copyback user mapping.

## The record

`struct dma_rec` is **0x60** bytes. Every field is a longword, so the service can reach each one with `movel d16(a0)`. The offsets are the contract. All service fields are contiguous at `0x14..0x4c`, so one `kpeek` reads the whole service state; all driver fields are at `0x50..0x5c`.

In the "who" column, D means the driver writes the field and the service only reads it. S means the service writes the field and the driver only reads it, for diagnostics.

| off | field | who | meaning |
|---|---|---|---|
| 0x00 | `magic` | D | `0x444D4152` "DMAR". Static; proves the address to a kmem reader |
| 0x04 | `version` | D | layout version, **2** (1 was the 0x5c proposal without `edge_shared`) |
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
| 0x48 | `edge_shared` | S | FROM_DEVICE prepares whose `pa` or `pa + len` is not on a 16-byte boundary (see Edge lines) |
| 0x4c | `off_n` | S | calls seen while `off != 0` |
| 0x50 | `drv_prep` | D | prepare calls the driver made |
| 0x54 | `drv_cmpl` | D | complete calls the driver made |
| 0x58 | `drv_zero` | D | zero-length transfers: the driver made no call |
| 0x5c | `drv_quiesce` | D | completes that followed a forced quiesce (see below) |

**Who owns the record.** The controller object owns it. The A4091 keeps one record per sd card in `a4091_dmarec[SDCARDS]`, a global the service or a kmem reader can find by name. The driver fills the identity fields (magic, version, ctlid, unit, off) at attach, before the first transfer. That is the `hat_cm_fb` registration contract: register before first use, never removed. The service never allocates or frees a record.

**The off switch.** The driver copies its patchable knob `a4091_dma_off` into `off` before every `prepare`, so one poke switches the seam for every A4091 card. It is DL-02's control arm: with the seam off and the data cache live, the emulator's copyback model should show the missing push/invalidate.

**Acceptance invariants** (read by kmem; none of them panics):

- `drv_prep == drv_cmpl` (every prepare is paired).
- With `off == 0` throughout: `prep_to + prep_from + prep_owned + range_ovf == drv_prep`, and `cmpl_to + cmpl_from + cmpl_noprep == drv_cmpl`.
- When idle: `seq == cmpl_to + cmpl_from`.
- `prep_owned == cmpl_noprep == cmpl_mismatch == range_ovf == edge_shared == 0`.
- `edge_shared <= prep_from` (only FROM_DEVICE prepares are counted).
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

## Cache ops (agreed)

- **Per range, not whole-cache.** The pilot's whole-cache `cpusha dc` was justified by "the A3091 is the only host-RAM DMA owner"; an A4091 (or the Z3660 piscsi) removes that premise. Whole-cache push was never unsafe, only imprecise. The per-range loop is the existing `cinvl` loop with `cpushl dc,(a0)` (`0xf468`). The A3091's B2 wrappers keep their `cpusha`.
- **`cpushl` paired with `cinvl`, per line, at prepare.** Correct in all cases without depending on CACR.DPI, which the unit neither owns nor can see (exception and FP paths reload CACR):

| | `cpushl` | the `cinvl` after it |
|---|---|---|
| 68040 | pushes and invalidates | no-op |
| 68060, DPI clear | pushes and invalidates | no-op |
| 68060, DPI set | pushes, line stays valid | invalidates |

## Edge lines (agreed)

The owned range is rounded outward to 16-byte lines. A `FROM_DEVICE` range whose `pa` or `pa + len` is not on a 16-byte boundary shares its first or last line with unrelated bytes. The 68040/060 writes a dirty line back whole, so once such a line is dirtied mid-transfer data is lost whatever complete does: `cinvl` loses the CPU's write, a re-push loses the device's freshly written bytes. **Complete therefore does not re-push.** Instead the service counts the range in `edge_shared` and the acceptance invariant requires zero, in the same family as `prep_owned`/`cmpl_noprep`/`cmpl_mismatch`/`range_ovf`: the unit names the violation rather than papering over it. Scope: `FROM_DEVICE` only; `TO_DEVICE` does no cache op at complete, so no edge arises.

B2's rule still holds: the CPU must not touch the owned rounded range until complete. The A4091 driver runs synchronously, so its own code cannot; the exposure is interrupt code, or another context, writing a neighbour of the buffer.

## GSIO alignment

The port author asked whether GSIO can actually hand the A4091 a misaligned buffer. **Yes, and it is not the only path that does.** Sources are the Model-B sysroot the 040 arm builds against (`amix-040-060-port/build/sysroot-modelb/usr/sys/amiga/alien/`).

1. **GSIO never passes a user buffer.** `scsi.c:gsioctl` copies the caller's data into a static kernel buffer and hands the driver that: `static uchar iobuf[1024]` (`scsi.c:22`), `sdcom.addr = iobuf` (`scsi.c:40`), copyin before / copyout after (`scsi.c:37`, `:51`). So user-buffer alignment is irrelevant, but:
   - **length** is checked only as `nbyte % DMA_GRANULARITY` with `DMA_GRANULARITY 4` (`scsi.c:10`, `:32`) and `nbyte <= 1024` (`scsi.c:33`; `scsi.o` compares `#1024`). An INQUIRY of 36 bytes ends at `iobuf + 0x24`, not on a line boundary.
   - **start**: `iobuf` sits at `.bss + 0x28` of `scsi.o` (after the static `sdcom`, 0x28 bytes; `.bss` aligned 2**2). The kernel's `.bss` is aligned 2**3 (`unix-040-fpe` relocatable), so `iobuf` is 8-aligned at best, 16-aligned only by luck of the final load address. Measured (DL-02e): stock `iobuf` is a char array at `.bss+0x4820` with no padding, landing 4 mod 16 in the shipped KD060-Z, 8 in the p15 D42 link and 0 in p16/p17, so the misaligned case occurs in shipping kernels.
   - Neighbours: the tail edge line holds `iobuf`'s own unused bytes; the head edge line (when misaligned) holds the tail of the static `sdcom` (`addr`, `nbyte`, `card`, `unit`, `intr` at +0x14..+0x27). Nothing writes those during the transfer: `gsioctl` sleeps, and the A4091 writes `cp->status`/`cp->okay` (+0x06/+0x05, a different line) only **after** `dma_complete` (`a4091-wr.c`, the `A4091_KVA` block before `(*cp->intr)(cp)`). So the edge is benign in fact, but `edge_shared` counts it.
2. **dd's REQUEST SENSE is misaligned by layout.** `dd.c:getsense` reads 16 bytes FROM_DEVICE into `dp->sense` (`dd.c:272-280`). `sense[16]` sits at +0x34 in `struct dd` (`dd.o`: `pea %a2@(52)`), and `ddtab[SDCARDS][SDUNITS]` has a 0x44 stride (`dd.o` `.bss` 0x440 = 2 x 8 x 0x44). 0x44 is 4 mod 16, so the sense buffer's alignment cycles through four residues across units: at most one unit in four is line-aligned. The tail edge line holds the **next** unit's `state`/`bhead`/`btail`, which `ddstrategy` and `ihandle` write; for `ddtab[0][7]` that is card 1's unit 0, which another controller's completion can reach from interrupt context. This is the one real exposure found.
3. **Block and raw I/O are aligned.** `dd.c:startio` sends `bp->b_bcount` (whole 512-byte blocks, `dd.c:255-258`). Raw character I/O does not reach the driver with user pages: `uiophysio -> breakup -> amiga_dma_pageio` (`dd.c:83`, `:137`) stages each chunk through a kernel buffer from `ngeteblk( NBPP)` (`physdsk.c:43`, copyout/copyin at `:75`, `:84`), so no user alignment reaches the driver. The start alignment of that buffer, and of buffer-cache buffers, comes from the kernel allocator and is not audited here; lengths are whole blocks.

**Consequence.** Unbounced, `edge_shared == 0` could not hold on this line: every sense on most units and every GSIO transfer whose length is not a multiple of 16 (INQUIRY, 36 bytes) would count. The owner chose the driver bounce (A4-18, 2026-09-29), below.

## Bounce (A4-18, implemented)

The 040/060 arm (`-DA4091_KVA` only; the 030 build is byte-identical) bounces misaligned reads itself. The sd layer and the service contract are unchanged.

- **When.** A `FROM_DEVICE` transfer with `nbyte > 0` whose `pa` or `pa + len` is not on a 16-byte boundary. `TO_DEVICE` never bounces: complete does no cache op for it, so no edge arises. Block and raw I/O are whole aligned blocks and never bounce.
- **Where.** `a4091_bounce[1024 + 16]`, static `.bss` in the driver object (never a stack buffer), used from its first 16-byte boundary. Its address is its bus address by the same kernel-`.data` identity the DSA table (`&ds`) relies on.
- **How.** The DSA data pointer, `prepare` and `complete` all get the bounce's address. The SCSI transfer length (`ds.data1len`) is the caller's; the length passed to `prepare`/`complete` is the caller's **rounded up to a multiple of 16** (A4-19), so both edges of the serviced range sit inside the driver's own aligned buffer and `edge_shared` stays 0 by construction (the buffer has the headroom: start offset <= 15 plus <= 1024). After `complete` (so after the final `cinvl`) and before `sdcom.intr`, the driver copies `len` bytes to `sdcom.addr`.
- **Copy-out rule (A4-19).** The driver clears the rounded bounce range before `prepare` (whose `cpushl` writes the zeros back to memory). A command that transfers fewer bytes than requested, or none (TEST UNIT READY issued through GSIO with a non-zero `nbyte`), therefore copies out zeros for the untransferred tail, never a previous command's bytes. The exact transferred count is not used: the SCRIPTS does not record whether `DATA_IN` ran, and `DBC` after a normal completion belongs to the last STATUS/MSG move, so it is only meaningful on the phase-mismatch path. No `bounce_short` counter was added. The copy writes through `sdcom.addr` as a kernel pointer: every range that can bounce is a kernel static (GSIO `iobuf`, `dd` sense), which are identity-mapped.
- **Too long.** A misaligned `FROM_DEVICE` range longer than 1 KB is **refused**, never passed through unaligned: `bounce_toolong` counts it, one console line names it, and the command completes with `status 0xff`, `okay FALSE` (the same hardware-error result as an unmapped card; `sdcom` has no sense to fill). No path on this line produces one today (GSIO caps at 1024). The 64 KB GSIO buffer of `scsi.c.patch` exists only in the 030 cross-links that include this repo (e.g. K030-A4091-IDE); the 040/060 port relinks the stock `scsi.o`, so this 1 KB limit and that buffer never meet in one kernel, by build recipe rather than design (DL-02e).
- **Counters.** `a4091_kstat` gained `bounce_n` (transfers bounced) and `bounce_toolong` after `bw_mask[]`; its magic moved to `0x41344b32` "A4K2". The DMAR record is unchanged (version 2).
- **Concurrency.** One buffer serves every card. `a4091queue` runs one command to completion before returning (polled `ISTAT`, no sleep, `a4091intr` empty) and already shares `ds`, `cdb_buf` and `status_buf` across cards; the copy-out finishes before the sd callback can re-enter the driver. Commands cannot overlap on one controller or across controllers, so no per-command flag is needed.

**What the invariant now means.** On our line `edge_shared == 0` holds **by construction**: no misaligned `FROM_DEVICE` range reaches `prepare`. A nonzero `edge_shared` is therefore a driver bug (the bounce test missed a range) or another caller of the service with the same record. What still counts: `prep_owned`, `cmpl_noprep`, `cmpl_mismatch`, `range_ovf` (all zero), the pairing `drv_prep == drv_cmpl`, and `bounce_toolong == 0`. `bounce_n` is not a violation; it rises by exactly the transfers that `edge_shared` counted before (GSIO reads with `len % 16 != 0` or an unaligned `iobuf`, sense reads on units whose `sense` is off-line). The B2 rule (no CPU touch of the owned range until complete) now covers the bounce buffer, which only this driver touches.

## Today, until the service exists

- Without `-DA4091_D42`, `a4091-wr.c` defines both entry points as **local stubs**. They do no cache maintenance and leave the service fields untouched. They count `a4091_kstat.stub_prep` / `stub_cmpl`.
- Attach prints `D42 seam STUB (no cache maintenance)`. A stub kernel is coherent only with the data cache off, which is every emulated cell today. **It must not be taken to metal with a live data cache as a coherence candidate.**
- With `-DA4091_D42` the object imports `dma_prepare` and `dma_complete`. `tools/build-a4091-040.sh --d42` gates that import set.
- A coherence verdict comes only from metal (MD-1/MD-4). The emulator shows at most a missing CPUSH/CINV, with the cache kept live (AB-03).

## Metal, 2026-10-02 (A4000D, Z3660 060, A4092 card 1, KD060-ZA dl4)

What the first metal runs show, and what they do not:

| Run | Seam | Result |
|---|---|---|
| A1-dl4, raw reads of LBA 0, 4 MiB and 32 MiB, two boots, copyback (`hat_cm_ram 0x20`) | on | host-true (`sum -r` identical, LBA 0 byte-identical); 38,913 + 4,097 segments, every invariant holds, `edge_shared 0` |
| control arm, the same reads | **off** (`a4091_dma_off 1`) | **also host-true**; `off_n` = 2 × `drv_prep`, the S fields did not move |

- **Why the control arm cannot fail on the raw path.** `amiga_dma_pageio` (physdsk.c) stages every chunk of a raw
  request through ONE buffer from `ngeteblk(NBPP)` (= `getfreeblk`, a buffer-cache buffer). It DMAs into it, then
  copyouts from its kernel VA, chunk after chunk. A copyback-cached VA would hand chunk N+1 chunk N's lines. 32 MiB
  host-true with the seam off therefore says that VA is not cached.
- **Why it did not fail. The first guess was wrong.** The guess was that the buffer's VA lies in DTT0's uncached
  identity window. C1 (a `bfreelist` walk on the running kernel, 2026-10-02) refutes it: every free buffer's `b_addr`
  is in kvseg (`0x402BD000`-`0x40363000`, `b_bufsize` 8192). kvseg pages are managed RAM, so their leaf PTEs get
  `hat_cm_ram` (0x20, copyback) through the HAT's cache-class selector (port hat040.s `Lcm_sel`: segu → NC, no page
  → NCS, else `hat_cm_ram`). The staging buffer **is** copyback-cached.
- **Not eviction either.** The control arm's 32 MiB passes used `dd bs=64k`, so each `read()` ran 32 × 2 KB chunks
  through the **same** staging buffer, with a copyout between DMAs. 2 KB of source plus 2 KB of destination fits an
  8 KB 4-way cache with nothing evicted, so stale lines should have been hit. They were not.
- **The answer: hardware snooping on the Z3660** [S, Z3660 `CPLD/DMA _WIP/z3660.vhd:459`]:
  `nSNOOP <= '0' when DMA_BUSY='1' or nBG_ARM='0'`. The DMA_WIP CPLD (jed 222B6735, both boxes) asserts the 060's
  SNOOP input on every Amiga-side DMA cycle into the card's memory, and on every ARM bus access. With SNOOP asserted
  the 060 invalidates any data-cache line that an alternate master's write hits, but it does not supply dirty data
  on an alternate master's read [I, MC68060 user's manual, bus snooping; verify]. So:
  - **FROM_DEVICE (complete's `cinvl`) is redundant on this platform.** The hardware already does it. It is harmless
    and stays, for accelerators without snoop.
  - **TO_DEVICE (prepare's `cpushl`) is not covered.** Dirty lines are not supplied to the DMA read, so the push half
    is load-bearing. Only a write cell can show it.
  - **No raw read can discriminate here**, with a C reader or otherwise. The read half is coherent in hardware.
- **What the seam is for on this line:** every DMA into managed RAM, since all of it is copyback through some VA. That
  covers the raw staging buffer (in kvseg), the page cache (segmap and user mmap), and anonymous pages on swap. The raw
  WRITE path is the most sensitive push-half test: copyin dirties the staging buffer microseconds before the
  TO_DEVICE DMA, so the lines are still dirty in the cache when the device reads RAM.
- **Consequence for the claim.** These runs prove the data path and Zorro III DMA reach into the Z3660's DDR, and
  that the record stays self-consistent under copyback. They do **not** yet test coherence; the seam has not been
  load-bearing in any metal run. On the Z3660 the read half is hardware-coherent (SNOOP); the verdict that
  matters is the push half, and only a raw write cell on a scratch disk, seam on vs off, can give it.
