# Host tests: the a4091 module form

`src/a4091-wr.c` built with `-DA4091_MODULE` on host gcc. The real driver
source runs against `mock.c`, which stands in for the kernel names the
module calls:
- `autocon`;
- the board pages (`sptalloc` on k30; `dev_kvmap` and `bprobe` on k46);
- `sd_register`;
- the C4-5 DMA names.

There are two binaries, one per line's map arm:
- `modtest-k30`: `sptalloc`;
- `modtest-k46`: `-DA4091_KVA`, `dev_kvmap` with a first-touch `bprobe`.

```sh
make -C test/host check     # build and run both; exit 0 when every case passes
make -C test/host clean
```

## What the cases check

| Case | What it shows |
|---|---|
| one A4091 | One registration: board index 0, the autocon base, `A4091 SCSI`, rank 2. The `dma_alloc` area is kept with its physical address, the SCRIPTS are copied into it, and the D42 record is filled |
| A4092 identity, A4770 identity | `c0de:01` registers as `A4092 SCSI` and `c0de:02` as `A4770 SCSI`, rank 2. The record's `ctlid` is the driver family's |
| two boards | An A4092 below an A4091. The module registers in product order (A4091 c 0, A4092 c 1); sd's (rank, base) order makes the A4092 card 0. A card-0 request (`queuefn(1, cp)`) arms the A4092's chip, and the A4091's registers stay untouched |
| four-board cap | Five boards found, four registered |
| no board / no board maps | `ENXIO`, nothing registered, the area given back |
| no `dma_alloc` area | `ENOMEM` before any probe (k30 before the 030 provider's pool) |
| a board that does not map | Skipped; the next board becomes c 0 |
| `sd_register` refuses | Its errno is returned, the mapped boards are stopped and the area is given back |
| halt | Every mapped board is aborted, soft-reset and re-initialised |
| queue: aligned READ | `prepare(pa, 512, FROM)`, then `dma_addr(r, pa)`, then `complete`. `data1buf` is `dma_addr`'s answer, not `pa`. DSA, DSP and the IDENTIFY/CDB pointers are physical addresses inside the area |
| queue: misaligned READ | A 16-byte sense lands in the driver's bounce: prepared by its physical address (16-aligned, in the area) and copied out by its kernel address, to exactly 16 bytes |
| queue: zero length / WRITE | No data DMA call (`drv_zero`); `TO_DEVICE` on the caller's address, no bounce. Either way, the data step is followed by the cache-clearing sync: prepare and complete FROM_DEVICE over a 16-aligned 16-byte clear line in the area that overlaps neither the status nor the message bytes (C4-5 v5 §5.4). An aligned or bounced READ has none: its own complete clears the cache |
| status under force-bounce (N109) | The mock models the k30 hook: the chip's GOOD status (0x00) lands before any complete, then a FROM complete copies a stale bounce (0x5a) over its segment. WRITE, TUR and READ must all return status 0x00. 1.0.0-3, which synced the status line itself, reads 0x5a |
| selection timeout is silent | An absent id (ISTAT SIP, SSTAT0 STO, rc -1) fails the command with no `A4091 slow` line; a phase error (DSPS 0xff05, rc -3) still prints one |
| queue: out of reach | `dma_addr` gives 0 (C4-5 v5): no DSP write, the command fails (status 0xff, callback once), then `dma_complete` (the provider counts `cmpl_noprep`; `drv_prep == drv_cmpl`), and the next command runs |

## How the harness works

- `mock.c` gives `dma_alloc` a physical address the host never maps
  (0x00f00000). A driver that handed the chip its own kernel address fails a
  check, and one that dereferenced the physical address faults.
- The chip is not emulated. A mock board's read side reports a finished
  command: ISTAT DIP, DSTAT SIR, DSPS 0xff00. Writes land in the write
  shadow (+0x40), where the checks read them.
- Each case runs in its own child process, because the driver keeps
  per-board state in statics, as it does in the kernel.
- The SCSI bus reset reads the beam counter at 0xDFF006, so the harness sets
  `a4091_busreset = 0`.

## Mutation check (2026-10-27)

Each of these bugs makes a case fail (the last four added with C4-5 v5, N109 and RD-1):
- arming with `dpa` instead of `dma_addr(r, dpa)`;
- indexing the tables by `cp->card` instead of `c`;
- writing DSA with the table's kernel address;
- arming past a `dma_addr` of 0;
- skipping the cache-clearing sync after a WRITE or a TUR;
- syncing the status line itself instead of the clear line (the N109 bug);
- tracing a selection timeout (RD-1 E955).
