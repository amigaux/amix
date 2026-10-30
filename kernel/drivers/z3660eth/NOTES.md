# NOTES — z3660eth (kernel/drivers/z3660eth, formerly amix-z3660net)

## ZS-05 — every board register access is armed (2026-10-26, module 1.0.0-5)

**The firmware fact** (Z3660 FPGA, real-CPU path; kernel/drivers/z3660scsi `90d03ae` (`9ceada6` before its move-in) is the reference
implementation, its NOTES.md 2026-10-26 and `docs/DI-1-misplaced-write.md` §10). The FPGA hands
each 060 access to the ARM as a REG1 word and `rtg_thread()` takes the address from it
(`zaddr = gpio & 0x1FFFFF`). On back-to-back cycles it samples **rising** address bits too early:
the access is delivered at **(previous address AND this address)**, silently, and the ARM
services it there, a write with whatever its DDR mirror holds for that cell. Reads go through
the same word, so they are exposed too. Register-file reads (`read_rtg_register()`) are pure in
the fork and in stock firmware, an undefined offset returns `0xFFFFFFFF`; amiberry's
`eth_reg_read()` likewise.

**Every pair in the driver before ZS-05** (previous access → access; rising = bits of the access
the previous one lacks; lands at = AND). "Arbitrary" = whatever board access ran last: another
driver path, z3660scsi's piscsi mailbox (board+`$2xxx`), the interrupted code.

| pair (prev → access) | where | rising | lands at | effect |
|---|---|---|---|---|
| arbitrary → R `$198` MAC_HI | map (attach) | any | `p & $198` | wrong MAC_HI; an undefined cell gives `0xFFFFFFFF` = the "MAC reads" absent verdict (ENXIO) |
| R `$198` → R `$19C` MAC_LO | map | `$004` | `$198` | MAC bytes 2–5 = MAC_HI's value: wrong station MAC, unicast RX filtered, silent |
| R `$19C` → W `$104` DISABLE | `_load`; static first open | none | `$104` | safe |
| arbitrary → W `$104` | open (module), close, unload, halt, intr_start after the self-test's sleeps | any | `p & $104` ∈ `$000/$004/$100/$104` | the CONFIG write lost; at `$100` a MODE write |
| arbitrary → R `$1A4` cursor | drain entry | any | `p & $1A4` | e.g. after W `$194`: `$184`, after R `$190`: `$180`, after W `$104`: `$104` — all read `0xFFFFFFFF`: `rx_overrun++`, the drain ends a tick early |
| R `$1A4` → W `$194` ETH_RX strobe | drain (3 sites) | `$010` | `$184` ACC_OP | **the strobe is lost, silently** (ACC_OP re-runs from the mirror cell); the driver has taken the frame, the firmware cursor stays: the next drain reads a consumed serial at the cursor = the ring wedge 1.0.0-4 resyncs past (intr=6 only) |
| W `$194` → R `$1A4` | drain loop, every path (no board access between; closest in the `continue` paths) | `$020` | `$184` | `0xFFFFFFFF`: `rx_overrun++`, drain ends early |
| R `$1A4` → W `$190` TX trigger | poll tick: drain then `tx_drain` | `$010` | `$180` BLITTER_DMA_OP | **the TX is lost**; the result read returns the previous result (normally 0: counted as sent) |
| arbitrary → W `$190` | `wput`/`wsrv` at base level | any | `p & $190` | as above, or a MODE write at `$100` |
| W `$190` → R `$190` result | xmit | none | `$190` | safe |
| arbitrary → R `$1A8` INT_STATUS | int6, static `z3660ethintr` | any | `p & $1A8` | e.g. after R `$1A4`: `$1A0` FW_VERSION (bit 0 = the minor version's: a spurious claim or a real one missed); `0xFFFFFFFF` = unclaimed |
| R `$1A8` → W `$104` DISABLE / ACK | int6, static `z3660ethintr` | `$004` | `$100` MODE | **"[RTG] Error mode: 255"** (both boxes); the acknowledge is lost, the firmware keeps INT6 up and the handler re-enters until one lands |
| R `$1A4` / W `$194` → W `$104` ENABLE | `rx_work` after the drain | none | `$104` | safe |

Frame-window cycles (the TX copy to board+`$07EE0000`, the slot header and payload reads at
board+`$07ED0000+k`) are not register events; whether they move the capture is not known. If
they do, the TX copy's last store (low 21 bits `$0E0000 + n`) → W `$190` lands at `n & $190`
(a 60-byte frame: `$010`; a 1514-byte frame: `$180`), and a slot read → W `$194`/`$104` lands on
the slot offset's bits. The INTREQ writes (`$DFF09C`) are never followed directly by a board
register access (int6 writes INTREQ after CONFIG; the self-test polls RAM and sleeps after
EXTER); if custom-chip cycles moved the capture, the low bits `$09C` would cover none of the
three write targets (no `$100`). ZS-05 does not depend on any of this: the arm is the access
right before each one.

**The fix (`src/z3660eth.c`, the ZS-05 block above the probe code).** Rule: every board register
access is issued right after a read of an offset that has no bit the access's offset lacks, with
nothing in between; then the AND is the access's own address. Three macros are the only way the
driver touches a register (`WRLONG`/`RDLONG` are gone), each ONE asm block run at IPL 7 for its
two to four instructions: `move.w %sr,dN; or.w #0x700,%sr` … `move.w dN,%sr`, so no interrupt
handler's board access (this driver's INT6, z3660scsi's piscsi mailbox) or exception stacking
can fall between the arm and the access.
- `Z3660ETH_WRA(regs, arm, off, val)` read arm, write off: `Z3660ETH_CONFIG` = arm `$1A4`
  (RX_ADDR, a pure read) for CONFIG `$104`; `Z3660ETH_RX_STROBE` = arm `$19C` (MAC_LO) for
  ETH_RX `$194` (`$1A4`/`$1AC` lack bit `$010`). Both write-only registers, so neither can arm
  itself without an undefined read. A compile-time `#error` pins `$104 ⊆ $1A4`, `$194 ⊆ $19C`.
- `Z3660ETH_WRV(regs, $190, len, rc)` read `$190`, write `$190`, `nop`, read `$190`: the TX
  trigger armed by its own result register, the result read in the same block. The `nop` is
  the barrier `z3660eth_sync()` gave there (now unconditional; `z3660eth_sync_n` no longer counts
  this site). IPL 7 spans the synchronous ~1 ms trigger cycle, which delays no interrupt that
  would have been taken: none is taken inside a bus cycle, and SR is restored right after the
  result read.
- `Z3660ETH_RDA(regs, off, v)` read off (discarded), read off: MAC_HI, MAC_LO, the drain
  cursor, INT_STATUS — the reads whose predecessor is arbitrary or rises.

The arming read can itself be misdelivered (`p & arm`): always inside the register file
(`arm < $200`), a pure read, its value discarded. Nothing else changes: same registers, same
values, same order, the polled and interrupt paths as before. Round trips: an RX frame 2 → 4,
an empty poll tick 1 → 2, a TX 2 → 3, an INT6 2 → 4, a re-enable 1 → 2. Not measured; on the
emulated path a trip is dearer (PSTAT/ping before and after on the bench: proposed, not run).

**Shared, not module-only.** The macros and the shared sites (map, initialize, close, xmit, the
drain's cursor and two strobes) are outside `#ifdef Z3660ETH_MODULE`; the module-only sites
(int6, rx_work, intr_start, `_load`, `_unload`, `_halt`, the resync strobe) and the static-only
`z3660ethintr` are armed the same way. The static objects therefore change (k30 `c2d6225e…` →
`c9370806…`, k46 `142e2486…` → `37185507…`); the static kernels of record get ZS-05 at the
stage-4 cut. ZS-05 closes the lost-strobe way into the ring wedge for every form; the
firmware's catch-up race (1.0.0-4) is the other way and stays.

**Object proof** (`make -C module zs05`: both lines, both forms, then `module/check-zs05.py`,
which disassembles each object, takes each block's offsets from the `lea`/`addaw` that set its
address registers, and requires exactly the expected blocks per function). k30 module, block
start (`oriw #1792,%sr`) and shape; k46 identical addresses, static k30 in brackets:

| function | block | arm → access |
|---|---|---|
| `z3660eth_map` | `0x520`, `0x534` [same] | RDA `$198`, RDA `$19C` |
| `z3660eth_initialize` | `0x764` [same] | WRA `$1A4` → W `$104` |
| `z3660ethclose` | `0x978` [`0x994`] | WRA `$1A4` → W `$104` |
| `z3660ethxmit` | `0xc02` [`0xc12`] | WRV `$190`: R, W, `nop`, R |
| `z3660eth_drain` | `0xe92`, `0xf4c`, `0xfbc`, `0x10da` [`0xdf8`, `0xeb6`, `0xfc8`] | RDA `$1A4`; WRA `$19C` → W `$194` (the resync strobe module-only) |
| `z3660eth_int6` | `0x1b24`, `0x1b50` | RDA `$1A8`; WRA `$1A4` → W `$104` |
| `z3660eth_rx_work`, `_intr_start`, `_load`, `_unload`, `_halt` | `0x1c7a`, `0x1ece`, `0x2068`, `0x213e`, `0x21b6` | WRA `$1A4` → W `$104` |
| `z3660ethintr` (static) | [`0x11b0`, `0x11d6`] | RDA `$1A8`; WRA `$1A4` → W `$104` |

A WRA block, e.g. `z3660eth_int6`: `lea %a2@(420),%a1; lea %a2@(260),%a0; clrl %d2; movew
%sr,%d1; oriw #1792,%sr; movel %a1@,%d0; movel %d2,%a0@; movew %d1,%sr`. The WRV block:
`movew %sr,%d0; oriw #1792,%sr; movel %a0@,%d1; movel %d3,%a0@; nop; movel %a0@,%d1; movew
%d0,%sr` with `%a0 = regs + 400`.

Negative controls (one-line mutants of a scratch copy, k30 module flags): the int6 CONFIG
write, one drain strobe, the drain cursor read, the TX trigger each made a plain access — the
gate fails naming the function; the strobe armed by `$1A4` — "W $194 armed by $1A4: bits
rise"; the WRA macro without the `or.w` — the gate finds no blocks; `ZZ_ARM_ETH_RX = $1A4` —
the compile stops at the `#error`.

**Host test.** This repo's host harness is `test-params.sh`, which cuts one pure function out
of the source; there is no mock register seam to run the drain or the handlers against an AND
capture model (z3660scsi's `mock_piscsi.c` has one for its mailbox). The object gate above is
the mechanical check instead: it proves the shape on the shipped objects, and the table above
is the address arithmetic. Metal proof belongs to the tripwire firmware (Z3660 `dd9d179`): with
ZS-05 this driver's own MODE/ACC_OP phantoms should be 0.

## Module form (2026-10-26, kernel/dlm S3-25, contract C3-6 version 1)

**One source, a switch.** `-DZ3660ETH_MODULE` turns `src/z3660eth.c` into the
loadable module; without it the file is the static driver, byte for byte (the
`.o` of both lines is identical before and after, and the preprocessed token
stream too). The module is built with kernel/dlm's ABI kit (S3-10), one kit per
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
The open runs at IPL 4 (the stock `qattach()` sets SR 0x2400 around the
driver's open: k46 0x4ee1c, k30 0x5190c), so the PORTS stays pending inside
it: the level-6 flag is spun on, the level-2 flag is waited for with one-tick
`timeout`/`sleep` rounds (up to 4) while the IPL drops elsewhere. 1.0.0-2
spun on both and printed "interrupt self-test failed; polled" every time.
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
- **Ring resync (1.0.0-4, after S3-46 on the A4000D).** The first metal
  intr=6 run died under a 5 ms ping flood with the firmware at "backlog 32
  fetched 0": the cursor at slot 0 carried the serial the driver had consumed
  last, so every drain broke on its empty-ring sentinel while the firmware
  filled the other 31 slots and tail-dropped. The level-6/level-2 handoff is
  not where it stops: `int_pending` is cleared, the backlog drained and the
  interrupt re-enabled by every poll tick, and an unacknowledged INT6 would
  hard-lock the box, which stayed up. Two ways into that state: a lost ETH_RX
  strobe, or the firmware's catch-up (10c7501 `ethernet.c:734-744`) writing
  the released serial into slot 0 after resetting the backlog, so an RX
  interrupt in between has its new slot-0 frame relabelled with the old
  serial. With intr=6 the drain now checks the sentinel (`z3660eth_rx_wedged`):
  at a slot k > 0 it is always a lost strobe; at slot 0, slot 1 holding serial
  + 1 or + 2 (and slot 0 unchanged on a second read) means a backlog. Then one
  ETH_RX strobe per drain steps past the slot, delivering nothing (at most one
  frame lost). Counters `z3660eth_rx_resyncs` and `z3660eth_rx_resync_last`
  (slot byte offset, or the slot-0 gap). Polled (intr=0) and the static driver
  do not have it yet: the same state would kill them too. Since ZS-05 the
  lost strobe has a known cause, the R `$1A4` → W `$194` address capture, and
  every form arms the strobe ("ZS-05" above).

**Kit result (2026-10-26, kernel/dlm 6ef133e kits, gcc-cross-amix 8949028).**
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
(`make -C module static`); since ZS-05 (1.0.0-5) k30 `c9370806…`, k46
`37185507…`.

**In the module, the kmem tunables move.** `z3660eth_cache`,
`z3660eth_ci_enforce`, `z3660eth_reprobe` and the counters are pokes and reads
at a kernel address the static kernel's `nm` gives. In the module they live
wherever the core placed the module at load; their addresses are in the
module's symbol table the core builds at load (`getksym`, the kit's
`sys/ksym.h`), not in the kernel's. How a tool on the box reads them is
kernel/dlm's side (S3-11, `modadmin`); until then the documented `/dev/kmem`
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
