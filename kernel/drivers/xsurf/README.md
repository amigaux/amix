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

**Status: tested in emulation; users report one real set-up working and one
failing** (see Tested). The board
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

At load the console prints one line per board: the card, its address, its
station address, the mode it ended in (`interrupt I/O`, `polled`, or
`polled (interrupt self-test failed)`) and its link (see Link and
diagnostics).

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
- the nodes `/dev/xsf0` and `/dev/xsf1` (character major 56), and the
  status node `/dev/xsfctl` (minor 15);
- the `ifup` entry, `/etc/inet/link.d/xsurf`;
- the status program `/usr/sbin/xsf`;
- the pages `xsurf(7)` and `xsf(1M)`.

The major comes from the kbootset registry, so install a kbootset whose
registry has `c 56 xsurf` (1.1.0.261114-45 or later) first:
`apkg update; apkg upgrade`. Then configure `xsf0` in
`/etc/inet/interfaces`, for example `xsf0 dhcp`.

## Link and diagnostics

The console line at load is gone once the system is up: it comes before
the system log runs. So everything it says can be read again with `xsf`.

- **The link.** The X-Surf-100's chip reports link, speed and duplex in its
  Device Status Register (0x17). The X-Surf's RTL8019AS has no link bit,
  but set to auto-detect it sends on its coax port when the 10BASE-T link
  test fails, and says so in its CONFIG0 register. The driver reports that
  as `no link (10BASE-T link test failed; sending on coax)`. Set to one
  medium, the link is not known, and the line names the setting. The tick
  reads the link twice a second. A change is said on the console once it
  has held for a second, at most once every ten seconds per board.
- **Transmit failures.** The first of each kind is said once per boot, then
  only counted: a transmit that did not complete (the chip restarted), a
  remote-DMA write that did not complete, a transmit aborted after 16
  collisions, any other transmit error. Collisions go into the interface's
  counter, so `netstat -i` shows them.
- **A board that does not take register writes.** After its reset, the
  probe writes two patterns to two page-1 registers and reads them back. A
  board whose writes are lost refuses at load with a console line
  (`its registers do not take writes`). Without this check it would pass
  the probe: after power-on the chip already reads as reset, and the
  station-address check takes any unicast junk. If every board found is
  refused, the module stays loaded with nothing attached, so that `xsf`
  can say why. `/dev/xsf0` still fails at once, and `ifup` stops there.

- **The probe's own checks.** After the chip's reset, the X-Surf-100
  waits for the chip's ready bit (D_RDY), because the datasheet says the
  chip is busy right after a reset. Then the register check runs. If byte
  writes do not land, it tries word cycles, the access the maker gives for
  the register area. Then a remote-DMA self-test writes four full-size
  frames into the chip's memory and reads them back. If the card's
  longword windows fail it, the test runs again on the 16-bit data port.
  The load line names any choice other than byte cycles and the windows.
  A board that fails gets a console line saying why and is refused.
  Parameters `regs` and `data` fix the choices for a tester; see
  `xsurf(7)`.
- **What xsf shows after one failed attempt:**
  - the probe's raw values: CR and ISR before the reset, the wait for
    D_RDY, the byte read back by each kind of register cycle, the PROM
    image as read, the self-test's result;
  - the chip's ISR, TSR and CR at the first transmit timeout;
  - its ISR and remote address at the first remote-DMA write timeout.

Diagnostics cost nothing in the receive and transmit paths beyond the
counters: the link read and the notes ride the clock tick.

## Status

`xsf` (`userland/xsf.c`, installed as `/usr/sbin/xsf`) prints what the
driver knows. First come the load line again, with the link as it is now,
then the frames and errors, the transmit failures by kind, and what they
point at when no frame was ever sent. Then every counter of the status
record, one `name value` per line.

- `xsf` shows `xsf0`, then any board refused at load;
- `xsf 1` shows the second board;
- `xsf -a` shows every board found, in use or refused;
- `xsf -S` exits 0 when the board is in use and 1 when it is not.

It reads `/dev/xsfN` for a board in use. It reads `/dev/xsfctl` for every
board found, which works even when every board was refused. The pages
`man/xsurf.7` and `man/xsf.1m` say how to read the output.

## Tested

**Reported by users, with driver 1.0.0-3 on the 1.1.1 k46 kernel
(68060-261106-66).** Nobody working on this driver has either card; these are
users' reports, passed on as they came:

- **Working:** an A4000D with a CyberStorm MkII 68060 and an X-Surf-100. The
  interface took a DHCP lease, and traffic went both ways (a ping by name
  answered). The card's Zorro mode was not reported.
- **Failing:** one user's set-up reported failing, where the card
  afterwards did not work under AmigaOS either.

**In emulation.** The
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

Module 1.0.0-3 answers SIOCGIFFLAGS and SIOCSIFFLAGS with IP's request, so
`ifconfig` shows the interface's flags (1.0.0-2 showed `flags=0<>`). It was
checked again from its packages, with one boot each and interrupts: the
X-Surf-100 in Zorro III (k46) and Zorro II (k30), and the X-Surf (k46).
Each boot ran the checks above, and also:

- `ifconfig xsf0` showed `flags=23<UP,BROADCAST,NOTRAILERS>` and the
  broadcast address after a static address, a DHCP lease and ifdown/ifup;
- `ifconfig xsf0 down` gave `flags=22`, and `up` gave 23 again;
- the guest answered a ping of the network's broadcast address.

Module 1.0.0-4 was checked from its packages on 2026-11-15 and 16. The
plain rows ran on the emulator's earlier build, then on the build that
models the X-Surf-100's link and its stricter board options:

- **Each card on each line, two boots** (interrupts, then polled through
  `param intr=0` with `kbootset build` and `commit`, as `xsurf(7)` gives
  it): the X-Surf-100 in Zorro III (k46) and Zorro II (k30), the X-Surf on
  both lines. Each boot ran the checks above. It also checked:
  - the load line with its link words;
  - that `xsf` prints the same line;
  - `xsf -a`, `xsf -S` and `xsf 1` (no such board);
  - `/dev/xsfctl` as c 56 15, the pages, and netstat's collision column;
  - a version-2 status record with no note and no refusal.
- **The link.** With the X-Surf-100's cable pulled in the emulator:
  - `xsf` said `no link`, and the console line reached
    `/var/log/bus-errors`;
  - frames still counted as sent, with no restart.
  After the cable went back: `link up 100 full`, two link changes in all.
  A pull shorter than a second said nothing. The X-Surf's model has its
  link test switched off, so a pull changes nothing the driver can see.
- **The upgrade.** The released 1.1.1 k46 image, with its own apkg 0.3.11
  and xsurf 1.0.0-3 from its installer, had xsf0 up. Then
  `apkg upgrade xsurf-k46` ran from a file repository. After a power
  cycle, xsf0 came up by itself, `xsf` worked, and `/dev/xsfctl` was there
  with mode 0600. The same upgrade also passed from a 1.1 image with
  kbootset -45.
- **The probe's refusals and fallbacks,** with test builds of the module
  that were never shipped:
  - register writes that never land: the board is refused with
    `its registers do not take writes (...; by word cycles too)`, the module
    stays loaded, `/dev/xsf0` and `ifup` fail at once, and `xsf` says why;
  - a self-test that fails on the longword windows: the driver moves to the
    data port, the load line says so, and ping and a 10 MiB copy go through
    it.
- **The emulator's strict X-Surf-100 options:**
  - byte writes dropped in Zorro III, with word cycles reaching one
    register: `, registers by word cycles`, and traffic;
  - the same with the register in the low half of a word:
    `, registers by word cycles (low byte)`, and traffic;
  - windows that drop or corrupt data: `, data through the data port`, and
    traffic;
  - a busy time after the reset: `xsf` shows the wait (200 µs and 2000 µs
    of busy time).

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

They also cover every DLPI primitive, the interface ioctls IP sends down
(the flags acknowledged with its request, the rest refused) and hostile
frames from the wire. From 1.0.0-4 they also cover:

- the link state of both chips, its console lines and their rate limit;
- the transmit notes;
- the probe's register check: a lost write, a write landing in a
  neighbouring register, the word-cycle fallback and the parameters;
- the remote-DMA self-test and the data-port fallback;
- the station-address PROM read through the board's data path;
- `xsf`'s output, run against a model of its devices.

In all: t_core 835 checks, t_boards 152, t_xsf 53. Of 94 deliberate faults
put into the sources, the tests catch 93. The one they miss changes
nothing: a page select before the link read that the tick has already
done.

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
host tests. Nobody working on it has either card; the users' reports above
do not say which of these their set-ups exercised. These points rest on the
maker's documentation, on Linux's drivers or on the emulator, and wait for
a run on a real board:

- **Interrupts.** Interrupt delivery from a real board on level 2: the
  driver's self-test decides at load time and falls back to polling.
- **X-Surf-100 registers:**
  - Which cycles a real card in Zorro III mode takes for its registers.
    The driver tries byte cycles, then word cycles, and the parameter
    `regs` can fix either. The emulator takes both by default; its strict
    options show each path working, not which one a card needs.
  - How long the chip stays busy after its reset (D_RDY). The emulator
    has a busy time only as a test option.
  - The word-cycle form (the register byte in both halves of the word,
    read back from the high half, else the low one) and the 16-bit data
    port path: written from the maker's register map, never run on a card.
  - The link from the Device Status Register: read as the datasheet
    describes it. The emulator's link model gives the same bits, so it
    checks the decode against that model, not against a card.
  - The PHY left as it comes from reset, with no MII handling.
    The datasheet gives the PHY's control register as 0x3100 at reset:
    powered, autonegotiating.
  - Zorro III operation on a real board, and the warning when the board
    is placed at or above 0x80000000.
- **X-Surf:**
  - The link from CONFIG0 and CONFIG2: read as the RTL8019AS datasheet
    describes them. Which medium setting a real X-Surf's EEPROM gives is
    not known.
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

Settled from the AX88796B datasheet (V1.6), against what Linux's
`ax88796.c` assumes:

- **Register 0x17 is not a GPOC.** A write sets the back-pressure jam
  limit; a read is the Device Status Register. Driver 1.0.0-3 and earlier
  wrote 0 there at set-up and 0x40 at unload, which only mattered with back
  pressure on (it is off). From 1.0.0-4 the driver never writes it, and it
  reads the link there.
- **RCR bit 6 is reserved.** The driver sets it on the X-Surf-100 as Linux
  does. Setting it does nothing.

## Credits

The driver's X-Surf-100 access (register layout, FIFO windows, interrupt
status, reset, PHY power, the station-address read) was first worked out for
Amix by **ales9030**, in an X-Surf-100 port based on **isoriano1968**'s
Hydra AMIX driver. That port was the reference for this driver's X-Surf-100
support; the code here is new. Board facts are from Individual Computers'
documentation, and Linux's 8390 drivers were read for how the hardware
behaves (no code taken).
