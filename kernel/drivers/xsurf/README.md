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

**Status: in development.** The board facts the driver is built on, and
where each was checked, are in [docs/facts.md](docs/facts.md).

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

The kit's driver contract (kernel/dlm C3-6 section 1.3) keeps polling as
the default for a driver whose interrupt path is unproven. This driver meets
that rule's purpose in a different way. It never enables a chip interrupt it
has not seen arrive. It falls back to polling when one stops arriving. For a
Zorro network card the level-2 interrupt is the usual path; the stock A2065
driver works that way.

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
