# xsurf: Individual Computers X-Surf and X-Surf-100 ethernet for Amix

A STREAMS/DLPI ethernet driver for two Zorro cards from Individual Computers.
It is a loadable kernel module for both kernel lines: k30 (68030) and k46
(68040/68060).

| Card | AutoConfig | Chip | Bus |
|---|---|---|---|
| X-Surf-100 | 0x1212:0x64 | ASIX AX88796B | Zorro II or Zorro III |
| X-Surf | 0x1212:0x17 | Realtek (an RTL8019AS in the emulator) | Zorro II |

The interface is `xsf0` (then `xsf1`, … in board order) and the device node is
`/dev/xsf0`. `ifup` brings it up from `/etc/inet/interfaces`, as it does every
interface.

**Status: tested in emulation, not on a real card** (see Tested). The board
facts the driver is built on, and where each was checked, are in
[docs/facts.md](docs/facts.md).

## Support

| Card | Mode | k30 (68030) | k46 (68040/68060) |
|---|---|---|---|
| X-Surf-100 | Zorro II | yes | yes |
| X-Surf-100 | Zorro III | yes | yes |
| X-Surf | Zorro II | yes | yes |

The X-Surf's chip sits behind an ISA bridge. The driver looks for it at ISA
port 0x300. If nothing answers there, the driver configures it through ISA
plug-and-play and says so on the console. The board's IDE ports are never
touched.

How each line maps the board:

- **k46.** `dev_kvmap` with the kit's register class (non-cacheable,
  serialised; kernel/dlm `docs/abi/ddi.md`), in both Zorro modes.
- **k30.** Zorro II windows are reached through the kernel's identity
  map. A Zorro III window is mapped with `sptalloc`.
- **The data cache on k30.** The maker requires that a 68030 in Zorro III
  mode does not use the data cache for the chip. That rule holds because
  the k30 kernel runs with the data cache off in supervisor mode, where
  all of this driver's accesses happen. The page mapping does not make the
  window uncached. The driver never maps the board into a user process.

## Interrupts and polling

The module parameter `intr` chooses how the driver hears the chip:

- **`intr=2`, the default.** At load the driver puts its handler on the
  level-2 interrupt chain and makes the board raise one real interrupt: a
  one-word remote read with only the remote-DMA-complete event unmasked. Only
  if the handler sees that interrupt does the driver unmask the chip's
  receive and transmit events. If the attach or the test fails, the board is
  polled.
- **`intr=0`.** The board is polled from the clock tick, 60 times a second.

At load the console prints one line per board: the card, its address, and
the mode it ended in (`interrupt I/O`, `polled`, or
`polled (interrupt self-test failed)`).

In interrupt mode the tick keeps watch. If the chip has events waiting and
no interrupt has been taken for three ticks, the driver masks the chip,
polls from then on, and says once `xsfN: interrupts stopped; polled`. The
tick also restarts a transmit that has not finished in 200 ms.

This default follows the kit's driver contract, kernel/dlm C3-6 version 12
section 1.3. A driver may enable interrupts by default when two things
hold: it turns them on only after the board itself has raised one and the
handler has claimed it, and it falls back to polling, saying so, when they
stop. This driver does both.

## Installing

The packages are `xsurf-k30` (pkginst `xsurf30`) and `xsurf-k46`
(`xsurf46`), one for each kernel line. Each installs:

- the module, `/etc/conf/mod.d/xsurf`;
- the nodes `/dev/xsf0` and `/dev/xsf1` (character major 56);
- the `ifup` entry, `/etc/inet/link.d/xsurf`.

The major comes from the kbootset registry, so install a kbootset whose
registry has `c 56 xsurf` (1.1.0.261114-45 or later) first:
`apkg update; apkg upgrade`. Then configure `xsf0` in
`/etc/inet/interfaces`, for example `xsf0 dhcp`.

## Status

`userland/xsf.c` reads the driver's status record: card, Zorro mode,
interrupt mode and every receive and transmit counter, one per line. Build
it on the box with `cc -o xsf xsf.c`, with `src/xsurfuser.h` beside it.

- `xsf` prints `/dev/xsf0`'s record;
- `xsf 1` prints the second board's;
- `xsf -S` exits 0 when the board is there and 1 when it is not.

## Tested

**In emulation only.** Nobody working on this driver has either card. The
rows below ran in the Amiberry emulator (amigaux fork, with its NE2000 receive
poll), on the released 1.1 disk images and kernels (k30 68030-261106-77, k46
68060-261106-66), with kbootset 1.1.0.261114-45 and the xsurf packages
installed by `apkg`, 2026-11-14.

| Card | Mode | k30 (A4000, 68030) | k46 (A4000, 68060 + Z3660) |
|---|---|---|---|
| X-Surf-100 | Zorro III | passed | passed |
| X-Surf-100 | Zorro II | passed | passed |
| X-Surf | Zorro II, set up through plug-and-play | passed | passed |
| none | the card absent | passed | passed |

Each card row booted twice: first with interrupts (`intr=2`), then polled
(`intr=0`). Each boot checked:

- the console line;
- a static address and a DHCP lease;
- ping both ways, also with 1472-byte frames;
- 10 MiB and 100 MiB copied by FTP each way, with checksums compared;
- the A2065 carrying control traffic at the same time, without a miss;
- ifdown and ifup three times;
- hostile frames (runt, oversize, trailer and unknown types) dropped and
  counted;
- the status record before and after: no transmit timeout, DMA timeout,
  ring resync, chip restart or interrupt fallback;
- no bus error on any boot.

With the card absent, the module is not kept, the console says nothing and
`ifup` returns at once. A kbootset older than -45 refuses the package at
gate 3 ("major c:56 is not in the registry") and leaves the boot
generation as it was.

Throughput **in the emulator** (100 MiB by FTP; it says nothing about a
real card):

| | interrupts | polled |
|---|---|---|
| guest to host | 87–178 s | 319–371 s |
| host to guest | 78–117 s | 554–579 s |

`make -C module test` runs the host tests. They build the driver's own
sources for the host against a model kernel and a model DP8390. The model
injects what the emulator cannot produce:

- a receive overrun, checking that the documented recovery order was
  followed before the receiver runs again;
- tally counters that keep their interrupt set until they are read;
- transmit aborts, a transmit that never ends, and a remote DMA that never
  completes;
- corrupt ring headers and a dead interrupt line;
- memory shortages.

They also cover every DLPI primitive and hostile frames from the wire.

What the emulator's model of these boards cannot show, so no row above
covers it:

- it never overruns the receive ring;
- it keeps its tally counters at zero and never raises their interrupt;
- it always reports a transmit as sent, with no error, collision or abort;
- it always reports a receive as good, and drops oversize frames itself;
- it returns 0xFF past the 32-byte station-address PROM;
- it has no MII/PHY on the X-Surf-100. Its register 0x14 (MII and EEPROM)
  decodes as the data port there, so the driver never touches it;
- it emulates the X-Surf's plug-and-play only in part, and keeps it
  configured across a warm reset;
- no bus timing and no caches.

An A2065 can share a machine with one X-Surf board, but not with two.

## Not confirmed on hardware

The driver is tested in the Amiberry emulator and against a model chip in
host tests. Nobody working on it has either card. These points rest on the
maker's documentation, on Linux's drivers or on the emulator, and wait for
a run on a real board:

- **Interrupts.** Interrupt delivery from a real board on level 2: the
  driver's self-test decides at load time and falls back to polling.
- **X-Surf-100 registers:**
  - Byte access to the chip registers at board+0x800. Linux does this; the
    maker's page says word access only.
  - RCR bit 6, set as Linux sets it on this board. Its meaning on the
    AX88796B was not checked against the datasheet.
  - The PHY powered on through GPOC, with the link left to the chip; there
    is no MII handling.
  - Zorro III operation on a real board, and the warning when the board
    is placed at or above 0x80000000.
- **X-Surf:**
  - Byte writes to the chip registers through the ISA window. Linux does
    this; the maker's page says writes should be word-wide.
  - Whether the chip comes up at ISA 0x300 by itself (as Linux assumes) or
    needs ISA plug-and-play (as the emulator does). The driver tries 0x300
    first.
  - Which ISA interrupt the chip is given under plug-and-play.
- **The recovery paths:** receive overrun, the tally-counter interrupt, a
  transmit error or abort, and the transmit timeout. The emulator cannot
  raise them; host tests drive them against a model chip.
- **The 68030 data cache.** A cache-inhibited mapping of a Zorro III window
  on the 68030 line.

## Credits

The driver's X-Surf-100 access (register layout, FIFO windows, interrupt
status, reset, PHY power, the station-address read) was first worked out for
Amix by **ales9030**, in an X-Surf-100 port based on **isoriano1968**'s
Hydra AMIX driver. That port was the reference for this driver's X-Surf-100
support; the code here is new. Board facts are from Individual Computers'
documentation, and Linux's 8390 drivers were read for how the hardware
behaves (no code taken).
