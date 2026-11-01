# libzz9k — the ZZ9000 SDK v2 host library for Amix

**Package `libzz9k` 2.9.1-2.** A Z3660, and a ZZ9000 whose firmware has the services runtime
(BlitterStudio zz9000-firmware, SDK version 2), can do work for an Amiga program on the board's
second ARM core. The kernel reaches each such board through `zz9ksvc` (kernel/modules/zz9ksvc,
`/dev/zz9ksvc0` and `1`). libzz9k is the program's side: the SDK's own host API over those
channels, a pool of the boards with their capability catalogues, and calls that run on a board
when one offers the service and in software when none does, with the same result either way.
The first is `zz9k_inflate` (raw deflate, zlib, gzip).

    sh build/pkg/pkgbuild.sh userland/packages/libzz9k        # after zlib (BUILD_DEPENDS)
    sh userland/packages/libzz9k/tests/hosttest.sh             # the host test alone

## Licence

**GPL-3.0-or-later**, the licence of the SDK's host code, which carries no linking exception.
A program that links libzz9k is a combined work under the GPL, version 3 or later, as a whole.
So far only our own tools link it. The licence text is `LICENSE`, shipped as
`/opt/amix/doc/libzz9k/LICENSE`.

## Layout

| Path | Content |
|---|---|
| `src/zz9k_host.c`, `src/include/zz9k/*.h` | the SDK's host API and headers, verbatim from zz9000-firmware v2.9.1 (`src/PROVENANCE`: the commit and each file's sum) |
| `patches/0001-amix-transport.patch` | the Amix branch of `zz9k_host.c`, `ZZ9K_HOST_AMIX`, applied by the build |
| `src/zz9k_amix.c`, `src/include/zz9k/amix.h` | our own: the pool, `zz9k_inflate` and its software path |
| `src/zz9k-test.c` | the on-box check, shipped as `/opt/amix/bin/zz9k-test` |
| `tests/hosttest.sh`, `tests/t.c`, `tests/kern.c`, `tests/sysshim.c` | the host test |
| `tests/smoke.sh` | the on-box acceptance test |
| `man/libzz9k.3`, `man/zz9k-test.1` | the pages |

## The Amix branch

On AmigaOS the SDK's host code finds the board, maps it and writes the mailbox rings itself. On
Amix the kernel owns the mailbox, and a program reaches it only through `zz9ksvc`. With
`ZZ9K_HOST_AMIX` (the build sets it):

- a context is an open of `/dev/zz9ksvcN`: `zz9k_open` takes the first unit that answers,
  `zz9k_open_unit` a given one, `zz9k_find_board` reports the first board;
- `zz9k_call`, through which every request goes, is `ZZSIOC_SUBMIT` then `ZZSIOC_WAIT`; the
  kernel gives the request its id, lets through only the opcodes it lists and puts the runtime's
  handles in place of the open's, so the SDK's request and reply code is used unchanged;
- `zz9k_alloc_shared` is `ZZSIOC_ALLOC` and an `mmap(2)` of the cookie (none for a card-only
  buffer); `zz9k_free_shared` unmaps exactly what was mapped, then frees; `zz9k_close` unmaps
  everything first, so the kernel can give the buffers back at its close;
- `zz9k_submit`, `zz9k_poll` and the interrupt calls answer `ZZ9K_STATUS_UNSUPPORTED`, as on any
  host without a mailbox: the kernel rings the doorbell and polls;
- an errno of the channel becomes a status: `ENXIO` → `NOT_FOUND`, `EINVAL` (a request the
  kernel does not pass on) → `UNSUPPORTED`, `EAGAIN` → `BUSY`, `ETIMEDOUT` → `TIMEOUT`.

The patch only adds lines, except the platform test's `#if`, which becomes an `#elif` after the
new branch.

## The pool and zz9k_inflate

The pool opens every `/dev/zz9ksvcN` once per process, at the first call, and reads each board's
catalogue: `QUERY_CAPS`, and the CODEC service's flags by `QUERY_SERVICE`. A node that gives
`ENXIO` (no board, or a board without a runtime) is left out, and so is a board whose runtime does
not answer `QUERY_CAPS`. A call goes to the first board whose CODEC service has the algorithm's
flag.

**The same result either way.** The firmware's one-shot DECOMPRESS of the zlib family is zlib's
`inflate` with `Z_FINISH` into the caller's buffer, the CRC-32 of the output, and a fixed status
for each outcome (end of stream `OK`; no room `NO_MEMORY`; anything else `BAD_REQUEST`). The
software path does exactly that with this system's zlib (`libz.a`, linked by the program). Around
both paths come the host-side checks of the SDK's helpers: before, `zz9k_request_decompress`'s
(an unknown algorithm or flag, an empty source or destination: `BAD_REQUEST`); after,
`zz9k_reply_decompress_result`'s (no bytes consumed or written: `INTERNAL_ERROR`). On anything but
`OK` the host sees only the status, so the result is zero on both paths. The host test checks,
call by call, that the status, the result and the bytes agree.

**One answer for every stream.** In `ZZ9K_INFLATE_AUTO` only a board's `OK` is taken. Any other
answer of the board is decided again in software and zlib's verdict returned: a firmware may judge
a corrupt stream that would overfill the destination `BAD_REQUEST` where zlib says `NO_MEMORY`,
and errors are rare enough that the second pass costs nothing that matters. A
`ZZ9K_INFLATE_BOARD` call returns the board's own status.

**When software takes over** (`ZZ9K_INFLATE_AUTO`): the source is shorter than the threshold
(`ZZ9K_INFLATE_BOARD_MIN`, 1024 bytes until the bench measures the board's round trip;
`zz9k_inflate_threshold` sets it for the process); no board offers the algorithm; the channel or
its buffers cannot be had; the kernel refuses the request; the request times out; or the board
answers anything but `OK`. An algorithm only a board can do (LZ4, LZMA, LZH) goes to the board
whatever its size. A board whose request timed out is left out of AUTO calls for 30 seconds, so a stalled
runtime costs one bound and not one per call; a `ZZ9K_INFLATE_BOARD` call still asks it, and an
answer brings it back. `zz9k_pool_timeout` sets the bound (default: the kernel's 10 s).

**Buffers.** `zz9ksvc` gives a freed buffer that was mapped back to the runtime only when the
channel closes (the mapping outlives its cookie; zz9ksvc(7)). So each board keeps two shared
buffers, source and destination, mapped once and reused; one grows, at least doubling from
64 KiB, only when a call needs more. When growing runs out of handles or of the 8 MiB quota, the
channel is closed and opened again, which gives every held buffer back. A call that cannot fit the
quota at all runs in software. The old channel's close queues a FREE for each held buffer; when
there were many, the fresh channel's first allocation can find the request ring still full (the
kernel answers `EAGAIN`), and that one call runs in software.

## What is installed

| Path | Bytes |
|---|---|
| `/opt/amix/lib/libzz9k.a` | 84,340 |
| `/opt/amix/include/zz9k/`: `amix.h`, `host.h`, `abi.h`, `crypto.h`, `text.h`, `compression.h` | 158,754 |
| `/opt/amix/bin/zz9k-test` | 57,668 text |
| `/opt/amix/man/{1,3}`, `whatis.d/libzz9k`; `/opt/amix/doc/libzz9k/{LICENSE,PROVENANCE}` | |

The headers are what `zz9k/amix.h` and `zz9k/host.h` need. The SDK's `request.h`, `reply.h` and
`image.h` are not shipped: they include `image_geometry.h`, whose name, like
`service_registry.h`'s, is longer than s5's 14 bytes, and shipping them would make the package
UFS-only. The library uses them inside.

**Size and memory.** `zz9k_host.c` is the whole SDK host API in one file: 50,428 bytes of text
at `-O2`; `zz9k_amix.c` adds 2,321 (and 148 bytes of bss, the pool). Both are compiled with a
section per function, so a program linked with **`-Wl,--gc-sections`** keeps only the calls it
makes: `zz9k-test`, which uses the pool, `zz9k_inflate` and zlib's deflate and inflate, has
57,668 bytes of text that way, 103,858 without. At run time the pool costs two shared buffers per
board in use, on the card, and one kernel open per board; the software path costs zlib's inflate
state (about 7 KiB, plus its 32 KiB window), freed at the end of each call.

The library is not safe for threads.

## Testing

**`tests/hosttest.sh`** runs on the host, with no box, once with each line's page size. It first
checks the upstream files against `src/PROVENANCE`, then builds the library as the package does
(`src/` copied, `patches/` applied, `ZZ9K_HOST_AMIX`) and runs it against kernel/modules' own
`zz9ksvc.c`, with its host harness (`zz9ksvc/test/td.h`) and two stand-in runtimes
(`zz9ksvc/test/fw.c`) that inflate with the host's zlib as the firmware does. The library's
system calls on `/dev/zz9ksvcN` go to the driver (`tests/sysshim.c`), which closes a channel the
way specfs does, only after its last mapping is gone. 241 checks:

- no board (the node gives `ENXIO`): an empty pool, `NOT_FOUND`, everything in software;
- one board: the catalogue; the threshold (a short source in software without a tick, `BOARD`
  ignoring it, the setter, an algorithm only a board can do going to it under the threshold);
  each format on the board and in software, the same; a board that answers `BAD_REQUEST` where
  zlib says `NO_MEMORY` (AUTO gives zlib's verdict, BOARD the board's); no room, a
  truncated stream with and without `EXPECT_END`, a corrupt stream, an unknown flag or algorithm,
  an empty source, a stream with no output; an algorithm nobody offers; the buffers reused, grown,
  the channel opened again when the held ones use up the handles (in the same call when the ring
  has room), a call too big for the quota in software; the SDK's own calls on the Amix branch (`zz9k_find_board`, `zz9k_open`, `zz9k_ping`,
  `zz9k_query_caps`, mapped and card-only buffers, `zz9k_decompress` by handle, an opcode the
  kernel refuses, no raw ring access, `zz9k_close` giving its channel back);
- two boards: each call on the first board that offers its algorithm;
- unit 0 without a runtime: the pool is unit 1, `zz9k_open` takes it;
- a board without the CODEC service, and one whose catalogue fails: software;
- a runtime that stops answering: the call times out and runs in software, AUTO calls skip the
  board without waiting, the timed-out channels are reaped when it answers, and the board is
  used again;
- after each: no open left in the kernel, no mapping or descriptor in the program, no buffer in
  the runtimes, every unmap exactly a mapping; at the end the driver unloads with all its memory
  freed.

Of thirteen mutants of the library, twelve are killed (no copy back, no unmap at free or close,
no skip of a stalled board, no fresh channel in the same call, the reply's length lost, the
empty-output check gone, a board's error taken in AUTO, no threshold, the threshold applied to
BOARD calls or to an algorithm only a board can do, a threshold of 0 by default); the thirteenth, the `EXPECT_END` branch of the
software path removed, is an equivalent mutant, since `inflate` with `Z_FINISH` returns `Z_STREAM_END` or `Z_BUF_ERROR`, never
`Z_OK`, and both give `BAD_REQUEST`.

**`tests/smoke.sh`** runs `zz9k-test` on the box. Its board rows need a firmware with the inflate
service and a board driver that registers the board with `zz9kbus`.
