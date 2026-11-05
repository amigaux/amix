# zz9ksvc — the service channel of a ZZ9000-family board's second core

A Z3660, and a ZZ9000 with a firmware that has the services runtime (BlitterStudio
zz9000-firmware, SDK version 2), can do work on the board's second ARM core for an Amiga
program. `zz9ksvc` is the kernel's side of that: `/dev/zz9ksvcN` (character major 55,
minor N), one per board, mode 0666, through which a program hands the runtime buffers and
requests and waits for the replies. libzz9k is its user (a separate package).

It is a loadable kernel module of class `demand` for both Amix kernel lines, `k30` (68030) and
`k46` (68040/68060), built with the ABI kit from kernel/dlm. It has no static form.

**Licence.** This directory is GPL-3.0-or-later (`LICENSE`), because it carries the SDK's
headers verbatim (`sdk/zz9k`, see `sdk/PROVENANCE`); the rest of kernel/modules is MIT. The
interface board drivers use, `include/sys/zz9kbus.h`, and the registry module `zz9kbus` are MIT
and carry no GPL text, so an MIT board driver never links GPL code.

## Layout

| Path | Content |
|---|---|
| `src/zz9ksvc.c` | the driver: opens, buffers, requests, waits, mmap, the polling callout |
| `src/wire.c`, `src/wire.h` | the mailbox protocol and the request policy; `wire.c` is the only file that includes the SDK headers |
| `sdk/zz9k/*.h`, `sdk/PROVENANCE` | the ZZ9000 SDK v2 headers, verbatim from zz9000-firmware v2.9.1, with each file's sum |
| `shim/` | `stdint.h` and `stddef.h` for `wire.c`'s compile (the period sysroot has no `stdint.h`) |
| `include/sys/zz9ksvc.h` | the ioctl interface |
| `module/keys`, `module/Master`, `module/Makefile`, `module/VERSION` | as for every module here |
| `man/zz9ksvc.7` | the page `zz9ksvc(7)` |
| `test/hosttest.sh`, `test/td.h`, `test/stub/`, `test/stub-bus/` | the host test, its DDI stand-ins and client calls, the stub kernel headers |
| `test/fw.c`, `test/fw.h` | the stand-in runtime (libzz9k's host test uses it too) |
| `pkg/` | the package recipe, rolled by make dist's kspace step |

## How it works

**The board.** A board driver that finds the SDK bootstrap block on its board registers it
with zz9kbus (`include/sys/zz9kbus.h`): a 16-bit read of the bootstrap block only, the doorbell
write, the mailbox it mapped (descriptor and rings) and the answer to "where does this range
of the host-visible heap lie in physical memory". Nothing else of the board reaches zz9ksvc.
At `_load` zz9ksvc takes and holds each unit's board whose bootstrap magic and mailbox
descriptor check out (`src/wire.c`: magic, ABI major 2, the mailbox capability, both rings
inside the mapping and apart). With none, `_load` fails `ENXIO`, the module is not kept, and
the open fails `ENXIO`: the program uses its software path.

**Clients.** Every open is a clone: `d_open` gives it a minor of its own (2–65), so the
kernel keeps per-open state. A client has up to 16 buffers, 8 MiB of them in all, and 4
requests in flight; a unit has room for 32 clients and 16 requests (the kernel's own
included).

**Requests.** The client's request is copied in and checked, and the kernel builds the
mailbox entry itself:
- the request id is the kernel's; the opcode must be in `src/wire.c`'s list (core queries,
  decompression; one row per opcode as services are added); some are root's;
- the payload is at most 48 bytes, the entry's flags are the kernel's;
- every buffer reference (where in the payload, per opcode, is in the list) must name a live
  buffer of this client, and the offset and length used must lie inside it, checked without
  overflow; the kernel then writes the runtime's own handle there.

No address from a client reaches the runtime, and no runtime address reaches a client.

**Buffers** come from the runtime's `ALLOC_SHARED`, page-aligned and rounded to whole pages.
A mappable buffer must lie, whole and page-aligned, inside the host-visible heap window as the
board driver answers it, or it is freed at once and the allocation fails `EIO`. `mmap(2)`
maps a buffer by its cookie only: the offset carries the handle and a generation (a freed and
reused handle does not map through an old cookie) and `d_mmap` returns the page of that
buffer's range, or -1. The offset is range-checked in full, negative values included, and on
k46 both 2 KiB halves of a page give the same frame.

**A mapping outlives its cookie.** The driver is not told of `munmap`, so a buffer `d_mmap` has
given a frame of may still be mapped after its FREE. Such a buffer is held: its handle stays
taken, its bytes count against the quota, it maps nothing new and no request can use it, and it
is not handed back to the runtime while the open lives. The open's `d_close` frees it: specfs
calls `d_close` on a clone only after its last open file and its last mapping are gone (the map
count on the clone's common snode, tested by `spec_close` and `spec_delmap`), including the
unmap at exit, which comes after the files are closed. So no other client's buffer, and no
buffer of the kernel's, ever lies under pages a client can still reach. A buffer never mapped
(card-only, or not mapped yet) goes back at once. After a RESET the restarted runtime may place
a new buffer over pages a live open still has mapped; such an allocation is refused with
`EAGAIN` (and the buffer given back) until that open closes.

**Completions and waits.** Replies are polled from a `timeout()` callout every clock tick,
and only while something is in flight, quarantined or owed a free; an idle box costs nothing.
A wait sleeps in rounds of at most 2 s up to its bound (10 s by default); a signal ends it
with `EINTR` and leaves the request to be waited for again.

**Timeouts and quarantine.** The runtime cannot cancel work. A request whose wait times out is
orphaned, and its buffers are quarantined: not freed, not mapped, not handed out again until
its reply arrives or the runtime is reset. A client that closes (or is killed) with requests in
flight leaves its buffers quarantined the same way; its closed open stays until they are
released, and its idle buffers are freed at once. At most 32 buffers can be quarantined: a
request whose references could take quarantined plus in-flight references past 32 is refused
with `EAGAIN`. An allocation that times out or is interrupted gives its late buffer back to the
runtime when the reply comes.

**Privileged calls.** `ZZSIOC_STATS` and `ZZSIOC_RESET` (forget the runtime's state after it
restarted) check `drv_priv`. Module listing is a root-only opcode.

The callout runs at the clock's level; process-context code takes the tables at spl4.

## The module

| `.moddata` key | Value |
|---|---|
| `name` | `zz9ksvc` |
| `class` | `demand`: it loads at the first open of `/dev/zz9ksvcN` |
| `majors` | `c:55` (registered to `zz9ksvc` in the kit's `registry/majors`) |
| `unload` | `allowed`: refused while any client, closed ones waiting included, or request remains |
| `depend` | `zz9kbus` |

The module imports only DDI v1 minor-0 names (`copyin`, `copyout`, `drv_priv`, `getmajor`,
`getminor`, `makedevice`, `kmem_zalloc`, `kmem_free`, `lbolt`, `sleep`, `wakeup`, `timeout`,
`untimeout`, `spl4`, `splx`, `bcopy`, `bzero`, `memcpy`, `__udivdi3`, `__umoddi3`,
`mod_drvops`) and zz9kbus's `zz9kbus_get` and `zz9kbus_put`.

## Size and memory

| | k30 | k46 |
|---|---|---|
| file (`mod.d/zz9ksvc`) | 13,894 bytes | 13,790 bytes |
| allocated image (`modcheck`) | 12,568 bytes | 12,456 bytes |

`.bss` is 3,584 bytes: the two units' request tables. Each open takes one `kmem_zalloc` of
596 bytes (`KM_NOSLEEP`, `ENOMEM` when there is none). `wire.o` is 2,440 bytes of text.

## Building

```sh
make -C zz9ksvc/module             # both lines (zz9kbus first)
make -C zz9ksvc/module k46         # one line
make -C zz9ksvc/module test        # the host test (any host cc)
```

`src/wire.c` is compiled without the kit's `-traditional` (a target-specific
`KIT_CFLAGS` in `module/Makefile`), with `shim/` and `sdk/` first on the include path; the
rest with the kit's flags. Calls between the two use `int`, `long` and pointers only. The SDK's
static inline functions are not used, and no signed 64-bit arithmetic is: the kernels export
only the unsigned 64-bit helpers.

A kernel enforces the registry it was cut with: kernels cut before `c 55 zz9ksvc` refuse the
module (`ECONFIG`).

## Packages (amix-dlm C3-5)

| | k30 | k46 |
|---|---|---|
| catalog name | `zz9ksvc-k30` | `zz9ksvc-k46` |
| pkginst | `zz9ksvc30` | `zz9ksvc46` |
| version | `module/VERSION` | `module/VERSION` |

Each package ships `/etc/conf/mod.d/zz9ksvc`, `/etc/conf/modreg.d/zz9ksvc` (comments only),
`/dev/zz9ksvc0` and `/dev/zz9ksvc1` (`c 55 0` and `c 55 1`, mode 0666, class `zz9ksvc`), the page
`zz9ksvc(7)` and its whatis fragment. Its copyright file carries the GPL-3.0 text from
`LICENSE` and says where the source is: this repository at the release's revision, and the
SDK's repository and commit. It needs the zz9kbus package of its line.

## Testing

**`test/hosttest.sh`** runs on the host, with no box, once with each line's page size. It
checks the source (c 55 in `zz9ksvc.c` and `keys`; `zz9kbus.h` MIT with no GPL text; the SDK
headers included only by `wire.c` and the stand-in), then compiles the shipped `zz9ksvc.c`,
`wire.c` and `zz9kbus.c` with stand-ins for the DDI (a simulated clock drives `timeout` and
`sleep`) against `test/fw.c`, a stand-in runtime with a real ABI v2 mailbox that can hold,
park, delay or fail requests, a heap with host memory behind it placed first fit (a freed
range is handed out again), and DECOMPRESS of raw deflate, zlib and gzip done with the host's
zlib as the firmware does it; and a stub board whose host-visible window the test sets. It
covers:
- the descriptor checks (each way a descriptor can be wrong);
- `_load` with no board, no magic, no runtime, a bad descriptor, and a good one (the board held);
- clone opens, the node not usable itself, `ENOMEM`;
- the handle table: 16 handles, page rounding, alignment, card-only buffers;
- the quota (8 MiB), and every `ALLOC` refusal; a buffer outside the window freed again; an
  allocation that times out or is interrupted giving its late buffer back;
- mmap by handle: the right frame, both halves of a k46 page, past the end, negative offsets,
  a wrong generation, another client's cookie, a freed and reused handle;
- a mapped buffer freed: held (nothing to the runtime, no new mapping, no use, bytes still
  counted), another client's new buffer never on its frames, given back at the close and its
  frames handed out again after it; sixteen held buffers take every handle until the close;
  after a RESET, a new buffer over a live open's mapped pages refused until that open closes;
- a real DECOMPRESS of each format through the kernel: the bytes, the CRC-32, no room, a
  corrupt stream;
- the request policy, root-only opcodes, payload length, every reference check (range,
  overflow, ownership, free handles), the runtime seeing only its own handles, 4 in flight, a
  full ring, a stray reply;
- waits: the reply, wrong ids, another client's id, `EINTR` and waiting again;
- timeout and quarantine: buffers quarantined, not mapped, not usable, not reused, freed when the
  late reply comes; the 32-buffer cap; close with requests in flight; the polling stopping when
  idle;
- `STATS` and `RESET` as root only, `RESET`'s effects;
- unload refused while clients remain, then the board given back and all kernel memory freed.

**zz9kbus** has its own host test (`zz9kbus/test/hosttest.sh`).
