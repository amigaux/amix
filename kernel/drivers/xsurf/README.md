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
