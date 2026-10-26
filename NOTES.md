# NOTES — amix-z3660net

## Module form (2026-10-26, amix-dlm S3-25, contract C3-6 version 1)

**One source, a switch.** `-DZ3660ETH_MODULE` turns `src/z3660eth.c` into the
loadable module; without it the file is the static driver, byte for byte (the
`.o` of both lines is identical before and after, and the preprocessed token
stream too). The module is built with amix-dlm's ABI kit (S3-10), one kit per
line: `make -C module` builds `build/<line>/mod.d/z3660eth` through the kit's
`mk/module.mk` (its headers, `mkmod`, `modfix`, `modcheck.py`) from the one
`module/Master` (no `$cpu`: the kit's DEFCPU gives 68030 on k30, 68040 on k46).
`match=zorro:144b:01,mobo:z3660-window` (C3-6 section 2): kbootset refuses a
boot module without `match=` (C3-5 section 2, gate 3); `mobo:z3660-window`
covers the AGA fixed-base fallback, the board without an AutoConfig entry.
The module form includes the kit's `sys/amixddi.h` for `if_attach` and
`intr_attach`/`intr_detach`; the static form does not see it. BUILD.md section 9.

**What changes in the module.**
- `z3660eth_load(params)` does what the first open did: `z3660eth_map(0)`
  (autocon, then the AGA fixed base, the MAC probe), `ZZ_CONFIG_DISABLE`,
  and `if_attach(&board->ifstats)` with the name set, last. An error returns
  the map's errno (ENXIO absent, ENOMEM no VA) or if_attach's, with nothing
  armed or attached, after one `zen:` line naming the reason (the probe lines
  end "module not loaded" in the module form). Parser: `make -C module test`.
- Open no longer links `ifstats`; `extern ifstats` is gone. `z3660ethintr()`
  and `z3660ethinit()` are not compiled.
- Major 51 is data: `z3660eth_drvdata[]` carries the row (only `d_str`) and
  `drv_cmajor` 51; the core registers it from `.moddata` `majors=c:51`.
- `z3660eth_halt()`: the board's interrupt off, the poll stopped.
  `z3660eth_unload()`: `unload=never`, so the core calls it only when a
  linkage fails to install after `_load` succeeded (`lf_fail`, before any
  open). It then undoes `_load` (interrupt off, `if_detach`, unmap); after
  any open it is EBUSY. The first module boot (2026-10-26, k30) hit that case
  (the core's EINVAL, no STREAMS slot for a boot-class major): the old EBUSY
  left the ifstats link to the core's backstop and the sptalloc pages kept.

**Interrupts (C3-6 section 1.3).** `intr=0` (default) is the static driver's
polling. `intr=6` attaches at the first open (process context, board set up,
its interrupt off): `z3660eth_int6` on level 6 and, with `intrl2=1`
(default), `z3660eth_int2` on level 2. A self-test then raises EXTER from
software (INTREQ 0xA000, the way the firmware's INT6 arrives); the level-6
handler takes the test flag and, with `intrl2`, raises PORTS (0x8008) for the
level-2 handler's flag. Only when both flags came back is the board's
interrupt enabled; any failure detaches and stays polled, one console line.
- `z3660eth_int6` calls nothing: it reads `ZZ_INT_STATUS`, and for ETH writes
  `ZZ_CONFIG_DISABLE`. In the firmware (`rtg.c` REG_ZZ_CONFIG) that write both
  clears the ETH interrupt and stops it (`interrupt_enabled_ethernet = 0`), so
  it is the acknowledge and the mask in one. Then `int_on = 0`,
  `int_pending = 1`, and with `intrl2` PORTS.
- The drain stays at IPL 4: `z3660eth_rx_work` from the poll callout, or from
  `z3660eth_int2` under `splz3660eth()`; `z3660ethrsrv` as before. It clears
  `int_pending` and writes `ZZ_CONFIG_ENABLE` again. `int_pending` is set only
  after the board's interrupt is off, so the lower half reads and clears it
  under the board's mask; `int_on` goes to 1 before every enable, to 0 after
  every disable.
- Nothing is lost while the interrupt is off: the firmware re-raises ETH while
  the backlog is non-empty and the interrupt enabled (`rtg.c`
  ethernet_thread), and the poll tick still drains every tick in all modes.
- `intrl2=0` leaves the drain to the next poll tick (the other half M-INT1
  measures). Counters: `z3660eth_int6_n`, `z3660eth_int2_n`,
  `z3660eth_intr_mode` (6 = running on interrupts).

**Kit result (2026-10-26, amix-dlm 6ef133e kits, gcc-cross-amix 8949028).**
`modcheck.py` passes on both lines (`ok (k30.1.0, boot, 12444 bytes)`, the
same for k46.1.0). Imports, both lines: `OTHERQ RD WR allocb autocon bcmp bcopy
bzero canput cmn_err flushq freemsg getmajor getminor getq if_attach
intr_attach intr_detach lbolt makedevice memcpy mod_drvops panicstr putbq
putnext putq qreply sptalloc sptfree timeout unlinkb untimeout`, all on DDI
v1; one weak undefined, the wrapper's own `z3660eth_conf_data` (C3-1:
resolves to 0). 34 COMMON symbols, each a checker warning: `ifnet` and
`rawintrq` are tentative definitions in the stock `<net/if.h>` (in the static
object too; the module gets private copies, which the driver never uses), the
other 32 are the driver's own uninitialised counters and tunables, allocated
by the core with the module. The static objects compiled against the kits'
headers are the static objects of record: k30 `c2d6225e…`, k46 `142e2486…`
(`make -C module static`).

**In the module, the kmem tunables move.** `z3660eth_cache`,
`z3660eth_ci_enforce`, `z3660eth_reprobe` and the counters are pokes and reads
at a kernel address the static kernel's `nm` gives. In the module they live
wherever the core placed the module at load; their addresses are in the
module's symbol table the core builds at load (`getksym`, the kit's
`sys/ksym.h`), not in the kernel's. How a tool on the box reads them is
amix-dlm's side (S3-11, `modadmin`); until then the documented `/dev/kmem`
pokes (BUILD.md section 8) apply to the static driver only.

## RX backpressure (2026-10-19, T-47 decision D1)

**Rule: never free a received frame because an upstream queue is full.**

**The defect.** `toss_packet_up_stream` freed a frame when `canput()` on the
upstream queue failed (`couldnt_put`), after the drain had already released the
firmware slot, so the frame was gone. The drain runs at IPL 4, where IP's service
procedure cannot run, so every frame past IP's queue high-water mark in one drain
was lost. On metal (T-47, A4000D, real 060) the firmware and the driver had every
frame while IP got 329 of 2000 datagrams at 1600/s, and the 4 MiB TCP push ran at
22–31 KB/s with 319–372 retransmits.

**The shape now.**
- The drain copies the 14-byte header (16, to keep the payload copy aligned)
  and takes the verdict before it releases the slot: `z3660eth_rx_want` gives
  the streams that want the frame and those whose `canput()` passes.
- A wanting stream is full: the drain stops and leaves the frame and everything
  behind it in the firmware backlog. The failed `canput()` set `QWANTW` on the
  upstream queue; when that queue drains, STREAMS back-enables our read queue
  and the new read service procedure `z3660ethrsrv` resumes the drain, usually
  in the same tick (queuerun runs on the way back to user mode). The next poll
  tick is the fallback.
- A frame nobody wants is released without the payload copy.

**Why the service procedure and not `putq` on the read queue.** Queuing on our
own read queue would still release the slot early: the frame then lives in an
mblk, and a full read queue is again a choice between freeing and stopping. Leaving
it in the firmware backlog costs no memory and no copy, and the backlog is where the
firmware already keeps unread frames. The service procedure exists only to be
back-enabled; nothing is ever queued on the read side.

**Bounds** (`z3660eth.h`). The firmware backlog is not a ring: frames are stored at
slot 0, 1, 2, … of a round, and the round restarts at slot 0 only when the driver has
caught up (`ethernet.c` `ethernet_receive_frame`). Slot 32 is the TX staging frame
(`0x07EE0000`), and at 64 the firmware discards the whole backlog. A hold keeps the
round open, so it is bounded:
- `Z3660ETH_RX_HOLD_SLOTS` 24: once the round reaches slot 24 (one header read at
  slot 23, serial in sequence with the head), the drain catches up to empty
  instead of holding, delivering to every stream that can take a frame and
  dropping it for the rest (`couldnt_put`). That closes the round before it
  reaches the TX frame.
- `Z3660ETH_RX_HOLD_TICKS` 30 (HZ/2): a frame held that long means a stuck
  stream, not a slow one; it is released the same way.

`couldnt_put` counts only those forced drops now. The kmem counters
`z3660eth_rx_holds`, `z3660eth_rx_resumed`, `z3660eth_rx_force_slots` and
`z3660eth_rx_force_ticks` say which path ran; the GET_STATUS struct is unchanged
(it is the `zen` ABI).

**Masking.** `z3660ethrsrv` runs from queuerun, outside the callout, so it holds
`splz3660eth()` (IPL 4) across the drain, exactly what the callout does: the two
drainers never interleave on the ring cursor, `last_serial` or `rxbuff`.

**Not changed:** the firmware protocol, the poll period, the TX path. The ACK
timing of T-47 H4 (ACKs leave from inside the drain, so the sender's next burst
waits for a poll) is unchanged; resuming from the service procedure only adds
drains between ticks.

## Probe failure leaked kernel VA (2026-09-27, AB-04)

**Rule: map, probe, free on failure.** Anything `z3660eth_map()` maps before
the probe is released on every failure path (`z3660eth_unmap()`, `sptfree(va, n, 0)`;
flag 0 because these are board pages, not `page[]` frames).

**The leak.** On the sptalloc arm (board at or above `VSECT1`, e.g. `autoconfig_rtg YES`
putting the combo window at 0x40000000) the map takes two windows: `ZZ_REGS_PAGES` (1)
and `ZZ_FRAME_PAGES` (32 at NBPP 4096; 64 on the 030 line). The failure returns after
them (sptalloc half-failure, the F3-M0 cache check, the MAC-sanity probe) only zeroed
`info->regs`; there was no `sptfree` in the file. So every failed open kept
**33 pages** (65 on the 030 line). `S99zen` opens `/dev/zen` **16 times** at boot.
On the AB-04 rig (amiberry, MAC registers read 0) that left **18 free sptmap pages**
(549 with S99zen disabled; the kvwalk shows 16 leaked 1+32 pairs), so raw I/O and
big kmem pools slept forever on `Km_BigWanted`: the DL-13 "stall". Evidence kept
locally, not published (amiberry AB-04 test runs: process, kvwalk and kstat captures).
Metal never failed the probe, so it never showed there; a metal firmware whose MAC
reads 0 would.

**Also changed.**
- A failure verdict is cached per board (`info->map_verdict`). Later opens return
  it without mapping or probing. `z3660eth_reprobe` (a `/dev/kmem` poke) forgets
  one verdict, for a firmware whose ethernet comes up late; there is no Zorro hot-plug.
- One console line per verdict, keeping the grep-able prefix:
  `zen: no Z3660 ethernet found (MAC reads 0x.. 0x..); opens fail errno 6`
  (or `not AGA`, `no board`, `cache-inhibit check refused`).
- `open` returns the real errno: `ENXIO` absent (cached), `ENOMEM` no kernel VA
  (not cached, printed once; the next open retries, which is now leak-free).
- Diagnostics: `z3660eth_map_fails`, `z3660eth_spt_freed`.
- `close()` never unmaps (a mapped board stays mapped; `map()` returns early on it),
  and the direct-map arm has nothing to free, so `z3660eth_unmap()` is the only teardown.

**Object proof** (040 driver line, gcc-cross-amix env.sh with the T-9 flags, the
`relink-040-z3660.sh` compile — that script lives on a private branch of the
040/060 port repo, not published; HEAD 47092ee source rebuilds to `b93ce42d`, as pinned):
`z3660eth_040.o` sha256 `a1f49c54d114cf76241abfa88bd60e46e500ada123a9c788d44cba5e153a2a4d`,
`sum -r` `20612 14`. `sptfree` is called twice in `z3660eth_unmap` (`pea 1`, `pea 0x20`,
flag 0), reached from the sptalloc-failure path in `z3660eth_map` and from
`z3660eth_absent` (the other three failures). G2: `z3660ethxmit` 3, `z3660ethopen` 3,
`z3660ethioctl` 2 `%sr` writes, unchanged. Board register accesses are unchanged,
all `movel`. The only new undefined symbol is `sptfree`, which the driver-line
kernel defines. `relink-040-z3660.sh` reports no unresolved symbols and 0 complaints.

## Interrupt masking (2026-09-27, review T-9)

**Premise corrected.** `spl6()`/`splx()` exist: they are `static inline` in the
stock `<sys/inline.h>` (`:112-260`). The old header no-opped them because a link
once showed them UNDEF; that came from not including `inline.h`. The cross build's
`-traditional` also erased the asm `volatile` until gcc-cross-amix `7a1d727`
(`-Dvolatile=__volatile__ -Dconst=__const__`), so masks written then would have
been deleted by the compiler anyway.

**Levels on this kernel.** `spl5`/`spl6`/`spl7`/`spltty`/`splhi`/`splstr` all
become `_spl4`, which writes `SR = 0x2400` (`inline.h:239-251`, `stream.h:461`).
Callouts dispatch at IPL 4, and only the level-2 CIA-A clock triggers them
(grimoire, "spl / callout-IPL contract"). So `spl6()` at base level blocks the RX
poll callout completely. `_spl4` *sets* the IPL rather than raising it. Every caller
here runs at IPL 0 (base) or IPL 4 (the callout), so the call only ever raises the
level or leaves it unchanged.

**Contexts.** There are two:
- **Base.** `open`, `close`, `wput`→`proto`→`xmit`, `wsrv`→`xmit`, `ioctl`.
- **The poll callout.** `z3660eth_poll`→`drain`→`toss_packet_up_stream`, and
  `tx_drain`→`xmit`.

The callout runs to completion before base resumes, and base never preempts it. So
a race needs a base-level sequence that the callout can land inside.

| Pair | Where | Race it closes |
|---|---|---|
| **M1** | `z3660ethxmit` claim: test `tx_busy`/`regs`, set `tx_busy` | The single `txwin` and the static `tmp[]` have exactly one owner. The test-and-set is one masked unit, so the claim does not depend on the run-to-completion argument. It stays correct if a level-2 ISR (`z3660ethintr` via `int2_tbl`) ever calls `xmit`. |
| **M2** | `z3660ethopen` slot publication: `EBUSY` test, field resets, `zp->q = q` stored last | The RX demux routes on `zp->q`, `flags` and `sap`. `close` clears only `zp->q`. Before this fix, `zp->q` was published *before* `flags`/`sap` were reset. A tick in between delivered frames up the new stream under the **previous occupant's** SAP or RAW flag. |
| **M3** | `Z3660ETH_GET_STATUS`: the `if_*` fills plus the 108-byte struct copy, with `allocb` kept outside | The callout bumps the counters (RX drain, deferred TX, `tx_nolink`, which is the only link-state indication). A tick mid-copy gave a torn snapshot, for example `packets_received` and `if_ipackets` taken from different ticks. |

**Removed.**
- The hydra-idiom mask around the whole of `wput`→`proto`. With real primitives it would hold IPL 4 across the ~1 ms synchronous TX trigger (ETHERNET-SCOPING Q2/Q7).
- The mask on the `tx_busy = 0` release. That is a single aligned store, and `tx_busy` is now `volatile`, so it stays after the TX-result load (object: `movel %a0@(400),%d0` then `clrl %a5@(24)`).

**Deliberately unmasked.** Each item below says why it is safe without a mask.
- **The RX ring.** This is the `ZZ_ETH_RX_ADDR` cursor, the `last_serial` head, the `ZZ_ETH_RX` strobe, the hold state and the static `rxbuff`. The callout touches them at IPL 4; since 2026-10-19 the read service procedure does too, and it masks to IPL 4 around the drain (see "RX backpressure"). A future level-2 ISR cannot interleave with the callout in either direction: the clock is level 2, and the callout masks level 2. The drain loop already runs at IPL 4 as a callout, so a mask there would add nothing.
- **Hand-off to the stream.** `canput`/`allocb`/`putnext` come from the drain at IPL 4, and STREAMS protects its own queues with `splstr`.
- **`close`.** It stores `zp->q = 0` first as a single aligned store. The stop-poll sequence `poll_running = 0; untimeout(poll_id)` cannot be split in a harmful way: a tick between the two stores does not re-arm, and `untimeout` of an already-fired id is a no-op.
- **`DL_BIND`/`DL_UNBIND`.** The demux reads `sap` (a single store) and never reads `state`.
- **Known and accepted: reordering in `wsrv`.** `wsrv` can `getq` frame A, and a tick can then send the queue's frame B before `wsrv` claims `txwin`. Closing that would mean masking across the TX. DLPI connectionless service makes no ordering promise, and IP tolerates reordering.

**Object proof** (`z3660eth_040.o` sha256 `b93ce42d…`, `sum -r` `57252 12`). The per-function G2 gate checks spl call sites in the preprocessed body against `,%sr` writes:
- `z3660ethxmit` 3/3.
- `z3660ethopen` 3/3.
- `z3660ethioctl` 2/2.

The same source built without the new flags gives 0/0/0 (G1 and G2 both FAIL), so the gate is proven to catch the fault. The Z3660 register reads are 32-bit, for example `z3660ethintr` `movel %a0@(424),%d0` where the old flags gave `btst #0,%a0@(427)`.

**Still to verify on the bench.** Nothing in the three pairs is exercised by a boot alone. The DL cell has to run:
- zen0 bring-up;
- a sustained bidirectional flood, for example `ping -s 1400` both ways alongside an ftp transfer;
- repeated `slink` tear-down and re-open of zen0 while traffic arrives, which exercises M2;
- `zen` status polling in a loop under load, which exercises M3.

Pass criteria:
- no frames go to an unbound stream;
- `if_ipackets - packets_received` stays constant across snapshots within one open (the two are bumped back to back in the drain);
- no clock drift, which would indicate an over-long mask.
