# C4-7 — disk commands with segment lists, draft

- **Status:** draft (2026-11-22). The names, layouts and rules below are
  meant for review by their three consumers before any kernel takes
  them. Nothing here is in a kit yet: the header is
  `abi/include/sys/sdseg.h` and `make kit` does not copy it, `ddi.list`
  does not list `sd_limits`, and no `abi-<tag>.txt` describes the new
  layouts. They enter the kit together, with each line's next minor
  (§7), once the kernel side can consume them. Until then a change here
  needs no version bump; from then on it is a contract change, as for
  every C-text.
- **Extends:** C4-1 (`sd_register`, `sdqueue`, the completion's level)
  and C4-5 (the DMA calls of minor 2), which stand unchanged
- **Written by:** kernel/dlm (`sd_limits`, `sd_lim`, `sdqueuex` in the
  module core; the header); the 030 kernel (dd's request builder, from
  source); the 040/060 port (the same for k46)
- **Read by:** the disk controller modules (A4091/A4092 and the A4000T
  53C710, z3660scsi, the IDE controllers), the 030 kernel's dd and the
  port's

## 1. Why

The stock disk interface, `struct sdcom` in `<amiga/alien/sd.h>`, gives
a controller one physical address (`addr`) and one length (`nbyte`), so
every command is physically contiguous. Nothing in the kernel gives
contiguous memory above a page, so every path cuts at the page:
- the raw path (`/dev/rdsk`): dd's strategy hands each request to
  `amiga_dma_pageio`, which stages it through one page-sized buffer,
  one command at a time: command, wait, copy, next;
- the block path (ufs): page lists go out one command per page
  (`gen_strategy`), and buffers larger than a page one piece per page
  (`buf_breakup`).

So a disk moves 2 KiB per command on the raw path of both lines (the
k46 port leaves `amiga_dma_pageio`'s 2 KiB pieces as they are) and a
page per command on the block path, and the per-command cost
(selection, the command and status phases, the driver's setup, on the
raw path a sleep, a wakeup and a copy) sets the throughput whatever the
request size.

This contract lets one command carry up to a controller's declared
maximum, as a list of segments, while every stock driver and every
module built for an earlier minor sees exactly the commands it sees
today.

Measured with the A4091 driver on k46:
- raw I/O goes out as 8192 commands of exactly 2048 bytes per 16 MiB,
  at every `dd` block size; ufs as 4 KiB commands;
- on metal a raw read moves 1580 KB/s: about 790 commands a second,
  1.27 ms per command.

A 64 KiB command replaces 32 of today's raw commands. Where the
per-command cost dominates, as these figures say it does, that is the
gain to expect, until the bus or the disk becomes the bound. The bounce
form (§5) keeps one CPU copy per command; a 2 KiB copy is estimated at a
few hundred microseconds on an 030, small against 1.27 ms.

## 2. The extended command, `struct sdcomx`

```c
struct sdseg {
	ulong		ss_pa;		/* physical address, as sdcom.addr */
	ulong		ss_len;		/* bytes, > 0 */
};

struct sdcomx {
	struct sdcom	sx_com;		/* the stock command, unchanged */
	ushort		sx_flags;	/* SDX_SEG */
	ushort		sx_nseg;	/* entries in sx_seg when SDX_SEG */
	struct sdseg	*sx_seg;	/* the segments, in transfer order */
	uint		sx_resid;	/* bytes not transferred; the driver sets it */
};

#define	SDX_SEG		0x0001
```

The stock structure keeps its size, 40 bytes on both lines, and every
offset: it is in each line's fingerprint (`ABI_SDCOM_SZ`, C3-3 §4),
where a changed size would raise the major, and the stock drivers are
compiled against it. The new fields follow it at the end of a larger
structure whose head is a `struct sdcom`, so a pointer to an `sdcomx`
is a valid `struct sdcom *`.

| Field | Offset | Meaning |
|---|---|---|
| `sx_com` | 0 | the stock command: `next`, `reading`, `okay`, `status`, `cdb`, `card`, `unit` and `intr` as today |
| `sx_flags` | 40 | `SDX_SEG`: the data is the list in `sx_seg`. Clear: the data is `addr`/`nbyte`, one segment, as today. Other bits are 0 |
| `sx_nseg` | 42 | with `SDX_SEG`, 1 to the controller's `sl_maxseg` |
| `sx_seg` | 44 | with `SDX_SEG`, the issuer's array, valid until the completion returns |
| `sx_resid` | 48 | §2.2 |
| size | 52 | |

Each field sits on its natural boundary, so the layout is the same
whether the compiler aligns `long` to 2 or to 4.

### 2.1 With `SDX_SEG`

- `sx_com.nbyte` is the sum of the segments' lengths, and
  `sx_com.addr` is `sx_seg[0].ss_pa`, so a log line or an error path
  that prints `addr`/`nbyte` stays meaningful.
- The CDB addresses the whole transfer: one READ(10)/WRITE(10) of
  `nbyte` bytes.
- The segments are taken in array order; byte `k` of the transfer is in
  the first segment whose lengths, summed, exceed `k`.
- Every segment meets the controller's declared limits (§3): its start
  is a multiple of `sl_align`, its length of `sl_gran`, it lies within
  the controller's reach, and `nbyte` is at most `sl_maxbytes`.

### 2.2 The residual

`sx_resid` is the number of bytes **not** transferred, as `b_resid`
counts: `nbyte - sx_resid` bytes landed, and they are the first ones,
in segment order. The driver sets it on every extended command before
it calls the completion. A driver that knows only all or nothing sets 0
when `okay` is true and `nbyte` when it is false; that is the first
drivers' form, and it is enough.

The first kernels treat a command whose `okay` is false as failed as a
whole, whatever the residual: every page of it errored, none done.
Per-page completion of a partial command comes later, when a driver
reports real residuals.

### 2.3 Without `SDX_SEG`

An `sdcomx` without the flag is a one-segment command in the stock
form, with a residual. A kernel may use it for a controller that
declared limits but takes no segment lists (§3.1).

## 3. A controller's limits, `sd_limits`

```c
struct sdlim {
	ushort		sl_ver;		/* SDLIM_VER */
	ushort		sl_flags;	/* SDL_SEG, SDL_ALLRAM */
	ulong		sl_maxbytes;	/* per command */
	ushort		sl_maxseg;	/* segments per command */
	ushort		sl_align;	/* each segment's start, a power of two */
	ushort		sl_gran;	/* each segment's length, a power of two */
	ushort		sl_pad;		/* 0 */
	ulong		sl_reach;	/* the last physical address the engine reaches */
	bool		(*sl_queue)();	/* called as sl_queue(c, cpx) */
};

#define	SDLIM_VER	1
#define	SDL_SEG		0x0001		/* takes segment lists */
#define	SDL_ALLRAM	0x0002		/* reaches all RAM the CPU does */

int sd_limits(bool (*queuefn)(), uint c, struct sdlim *l);
```

| Field | Offset | Meaning |
|---|---|---|
| `sl_ver` | 0 | 1. A later version may grow the structure at its end |
| `sl_flags` | 2 | `SDL_SEG`: `sl_queue` takes `SDX_SEG` commands. `SDL_ALLRAM`: §3.2 |
| `sl_maxbytes` | 4 | the most one command carries, a multiple of 512, at least 512 |
| `sl_maxseg` | 8 | with `SDL_SEG` at least 1; without it, 1 |
| `sl_align` | 10 | 1 for any byte address; 2, 4, … 4096 |
| `sl_gran` | 12 | 1 for any length; 2, 4, … 512. The last segment's length too |
| `sl_pad` | 14 | 0 |
| `sl_reach` | 16 | inclusive: `0xFFFFFFFF` for a 32-bit engine, `0x00FFFFFF` for a Zorro II one |
| `sl_queue` | 20 | the controller's queue function for `sdcomx` commands, called as `queuefn` is (C4-1 §1) with the board index `c` and a `struct sdcomx *` |
| size | 24 | |

`sd_limits` names a registration made by `sd_register` (C4-1 §3) by its
`queuefn` and `c`, and attaches the limits to it.

- **When:** after that `sd_register` returned 0, in the same `_load`,
  in the root pass: the context of C4-1 §3 (level 7, the clock stopped,
  no sleep). It allocates nothing.
- **The structure** is the module's storage, kept for the kernel's
  life; a root-class controller is never unloaded (C4-1 §3.1). The core
  keeps the pointer.
- **Returns** 0, or:

  | Error | When |
  |---|---|
  | `EBUSY` | registration has closed (C4-1 §3.1) |
  | `ENOENT` | the calling module made no registration with this `queuefn` and `c` |
  | `EINVAL` | `sl_ver` is 0, `sl_queue` is 0, or a field is outside the table above |
  | `ENOSYS` | from `DDI_SD_LIMITS` on a kernel before the segment minor (§6) |

  A refused call leaves the registration as it was: the controller gets
  today's commands (§3.1), and the console says
  `sd: %s: limits refused (%d)` with the controller's name.
- A second call for the same registration replaces the first.

### 3.1 What a controller gets

| Declared | Commands |
|---|---|
| nothing (every stock driver, every module built for an earlier minor, a refused call) | today's: stock `struct sdcom` through `queuefn`, one segment of at most a page |
| limits without `SDL_SEG` | one segment of up to `sl_maxbytes`, as an `sdcomx` without the flag, through `sl_queue` |
| limits with `SDL_SEG` | `sdcomx` commands with or without `SDX_SEG`, through `sl_queue` |

`queuefn` keeps receiving the stock commands other callers build: the
tape driver, the `GSIO` ioctl, a filesystem module's own `sdqueue`
(amix-cdfs). A controller that declares limits therefore keeps both
entries, and tells the two forms apart by the entry they came through,
never by a field.

### 3.2 Reach

`sl_reach` is the engine's address width. A bus master on a Zorro board
also reaches only the memory a Zorro bus master reaches: not RAM local
to an accelerator card, such as the Z3660's DDR in which boot2 may bind
a k30 kernel (C4-5 §1). So, unless the controller declares
`SDL_ALLRAM`, the kernel gives it a segment directly only when the
segment lies within `sl_reach` and in that memory, by the same
knowledge `dma_alloc` and the k30 pool use (C4-5 §3, §5). `SDL_ALLRAM`
is for an engine that reaches whatever the CPU does: a controller that
moves the data with the CPU (programmed I/O), or one on the CPU's own
bus.

## 4. With the DMA calls of minor 2 (C4-5)

The DMA calls are unchanged; a segment is what they call a segment.

- **Per segment:** the driver calls `dma_prepare(r, pa, len, dir)` for
  every segment before the write that arms the device, puts
  `dma_addr(r, pa)` where the device takes that segment's address, and
  calls `dma_complete` for every segment after the device has stopped
  and before the completion. `dma_addr`'s 0 (k30: a segment the board
  cannot reach that was not bounced) is the per-segment fallback point:
  the driver does not arm, and fails the command (`okay` false,
  `sx_resid` `nbyte`).
- **One record per segment in flight.** A `struct dma_rec` owns one
  segment at a time (a segment still owned is a miss, C4-5 §2.2), so a
  driver that arms several segments at once holds `sl_maxseg` records
  per controller and gives segment `i` record `i`.
- **The k30 bounce is per segment.** On k30 `dma_prepare` bounces an
  unreachable segment through the pool on its own (C4-5 §2.2). The
  kernel's builder avoids that path (§5), so a provider bounce is the
  rare case, and a shortage of bounce buffers fails the command, not the
  box.
- **A programmed-I/O controller** makes the same two calls per segment,
  for the CPU caches' sake: on k46 it reaches a segment through the
  cache-inhibited identity map while the process's mapping may be
  copyback, so the lines must be pushed before a write (`dma_prepare`,
  `DMA_TO_DEVICE`) and invalidated after a read (`dma_complete`,
  `DMA_FROM_DEVICE`). It needs no `dma_addr`.
- **The memory the kernel's bounce uses** comes from `dma_alloc` (at
  most 64 KiB a call, 16-aligned, reachable), so a bounced command's
  segments are never bounced again by the k30 provider.

## 5. The kernel's request builder (dd)

For the 030 kernel's dd and the port's. The core provides two names to
them; neither is in the DDI:

```c
struct sdlim *sd_lim(uint card);	/* the card's limits, or 0 */
bool sdqueuex(struct sdcomx *cpx);	/* sl_queue of cpx->sx_com.card */
```

`sd_lim` answers after registration has closed (sd's first open) and
never changes after; `sdqueuex` is called as `sdqueue` is, at any level
but 6, and the completion comes as C4-1 §3.2 says.

Per request, by the card's limits:

1. **No limits:** today's path: `amiga_dma_pageio`, `gen_strategy` and
   `buf_breakup` as the stock kernel has them.
2. **Limits:** the builder makes `sdcomx` commands of up to
   `sl_maxbytes` each.
   - **Through the bounce (the first form):** each command's data goes
     through a contiguous bounce region of the controller's own,
     `min(sl_maxbytes, 64 KiB)` from `dma_alloc`, taken at the card's
     first open, one per controller so that no lock is shared: one
     segment, a copy per command instead of per page. This form needs
     no segment support and serves every controller that declares
     limits.
   - **Direct (a later form):** the segments are the request's own
     frames: from the soft-locked user pages on the raw path, from the
     page list on the block path; adjacent frames merged; a command cut
     where `sl_maxbytes` or `sl_maxseg` would be passed. A frame that
     fails `sl_align`, `sl_gran` or the reach of §3.2 sends its command
     through the bounce.
   - dd declares `D_NOBRKUP` and handles its own page lists, so
     `gen_strategy` no longer cuts them; `buf_breakup` leaves the path
     for such a card.
3. **The line rule for direct reads on k46.** The CPU caches lines of
   16 bytes. A direct `DMA_FROM_DEVICE` segment in memory the CPU uses
   must start and end on a line: `dma_complete` invalidates whole lines,
   and a line shared with live data would lose it. A read whose buffer
   does not start and end on a line goes through the bounce whole (the
   first direct form), or with its partial edge lines as segments of
   their own in the bounce region (allowed later).
4. **Direct DMA into copyback frames on k46** comes after metal cells
   have shown coherence on the controller: every segment through
   `dma_prepare`/`dma_complete`, the line rule above. Today raw I/O is
   coherent with the DMA seam off only because the staging buffer is
   write-through heap; a copyback user frame has no such net.

The first kernels take the bounce form only; the direct form is allowed
by this text and is enabled per controller later.

## 6. A driver's use

```c
#include <amiga/alien/rico.h>	/* bool */
#include <amiga/alien/sd.h>
#include <sys/sdseg.h>

DDI_SD_LIMITS_DECL;

static struct sdlim mylim = {
	SDLIM_VER, SDL_SEG, 65536, 16, 4, 4, 0, 0xFFFFFFFF, myqueuex
};

	/* in _load, once per board, after sd_register(myqueue, c, ...) returned 0 */
	(void)DDI_SD_LIMITS(myqueue, c, &mylim);
```

- `DDI_SD_LIMITS` refers to `sd_limits` weakly, as `DDI_FB_REGISTER`
  refers to `fb_register` (C3-2 §2): a module that declares limits keeps
  the minor its other imports give it, and still loads on a kernel
  before the segment minor, where the macro gives `ENOSYS` and the
  controller gets today's commands. A module that calls `sd_limits` by
  name carries the segment minor.
- `myqueuex` takes `struct sdcomx *`, `myqueue` the stock command, and
  both may share the code below the entry.
- A controller that takes no lists (z3660scsi: one address and a length
  per firmware request, at most 64 KiB) declares `sl_flags` 0,
  `sl_maxseg` 1 and its maximum, and gets one larger command through the
  bounce.

## 7. The minor

This is not minor 1.4: that minor is taken (the demand class, C3-2
§3), and k46 is at 1.6. The interface takes each
line's next minor when the kit takes it: k30.1.6 and k46.1.7 as the
kits stand today. That kit change:
- lists `sd_limits` in both lines' `ddi.list` at that minor;
- copies `sys/sdseg.h` into the kit's `include/sys/`;
- adds the new layouts to the probe (`dlmoffs.c`) and so to the
  fingerprint text, additive lines only (`offs ABI_SDCOMX_*`,
  `ABI_SDSEG_*`, `ABI_SDLIM_*`): the core reads an `sdlim` in a module's
  memory (C3-3 §4);
- adds a row to `ddi.md`.

A module built for an earlier minor loads unchanged on such a kernel:
`struct sdcom`, `sdqueue` and `sd_register` keep their form, and its
controller, having declared nothing, gets today's commands.

## 8. Not in this contract

- More than one command in flight per unit, and tagged queuing.
- Interrupt completion in the A4091 driver.
- A segment list in the Z3660 firmware's request.
- Per-page completion of a partial command (§2.2).
- `sdqueuex` for modules: a filesystem module's own commands stay in the
  stock form.
