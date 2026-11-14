# X-Surf and X-Surf-100: the board facts this driver is built on

Each fact names where it was checked. The sources:

- **Maker:** the Individual Computers wiki pages
  [X-Surf-100](https://wiki.icomp.de/wiki/X-Surf-100) and
  [X-Surf](https://wiki.icomp.de/wiki/X-Surf), read 2026-11-14.
- **Linux:** Linux v6.12, `drivers/net/ethernet/8390/` (`xsurf100.c`,
  `ax88796.c`, `zorro8390.c`, `lib8390.c`, `8390.h`). These were read for how
  the hardware behaves. They are GPL code, and none of it is copied here: the
  driver is written from the facts below.
- **Amiberry:** the emulator the driver is tested on (`src/expansion.cpp`,
  `src/qemuvga/ne2000.cpp`, `src/cfgfile.cpp` at amiberry 1621e26). It is a
  model of the boards, not a reference for them. Where it differs from the
  maker, the maker wins, and the difference is listed so the driver works
  on both.
- **Earlier port:** the X-Surf-100 driver for Amix by ales9030, based on
  isoriano1968's Hydra AMIX driver, read as a reference for the X-Surf-100's
  access. It agrees with Linux on every register value used here.

Status: **confirmed** means two independent sources agree, or the maker states
it. **Model** means Amiberry behaviour only. **Unconfirmed** facts are also
listed in the README; they need a real board.

## X-Surf-100

| Fact | Sources | Status |
|---|---|---|
| AutoConfig manufacturer 4626 (0x1212), product 100 (0x64) | Maker; Linux `xsurf100.c:9-10`; Amiberry `expansion.cpp:6514-6530` | confirmed |
| Ethernet chip ASIX AX88796B, "mostly NE2000-compatible" | Maker; Linux drives it through `ax88796.c` | confirmed |
| Zorro II in an A2000, Zorro III in an A3000/A4000; a jumper forces Zorro II. Z2 size 64 KB; Z3 size 64 MB with a 64 KB sub-size | Maker | confirmed |
| In Zorro III mode the board shuts up if assigned an address at or above 0x80000000; a driver should say so | Maker | confirmed |
| Network interrupt status at board+0x0040: bit 15 of a word read, bit 7 of a byte read, 1 = active. Check only that bit; bit 13 was a copy on the older card | Maker. Linux tests the word against 0xaaaa (`xsurf100.c:60`). Amiberry returns bit 7 in both bytes (`ne2000.cpp:1783-1792`) | confirmed |
| The interrupt is the Amiga's level 2 (PORTS) | Linux `IRQ_AMIGA_PORTS` (`xsurf100.c:245`); the maker implies it | confirmed |
| Chip registers at board+0x0800, one register per 4 bytes, byte-swapped. Register r is at 0x800 + 4r | Maker; Linux `reg_offsets[reg] = 4 * reg` from 0x800 (`xsurf100.c:247, 277`) | confirmed |
| Register access width: the maker says word access only; Linux and the earlier port use byte access at 0x800 + 4r | Maker vs Linux (`ax88796.c` `ei_inb`/`ei_outb`) | **unconfirmed**: byte access is used, as Linux does. Amiberry implements byte access; there a word write to a register writes two registers (`ne2000.cpp:1039-1044`) |
| Data port (register 0x10) at board+0x0840; the maker also maps it at 0x0880–0x08FC, zero wait states | Maker; Linux `NE_DATAPORT` = `EI_SHIFT(0x10)` | confirmed |
| Long-word FIFO windows: read at 0x8800–0x8BFC (byte-swapped, one wait state in Z3), write at 0x8C00–0x8FFC (byte-swapped, upper half first). Each 32-bit access is two 16-bit chip accesses | Maker | confirmed |
| Linux uses the windows at 0x8880 (read) and 0x8C80 (write) in blocks of 0x80 bytes | Linux `xsurf100.c:18-23` | confirmed |
| Amiberry decodes FIFO data only at offsets 0x80–0xFF of each 256-byte page of 0x8800–0x8FFF; the low 0x80 of each page decode as registers. The driver therefore uses 0x8880/0x8C80 and 0x80-byte blocks, which works on the board and the model | Amiberry `ne2000.cpp:1810-1825` | model |
| Reset: read register 0x1F and write the value back, then wait for ISR bit 7 (RST); Linux allows 20 ms | Linux `ax88796.c:146-167` | confirmed (Linux); Amiberry resets on the read |
| GPOC (register 0x17) bit 6 PPDSET: 1 powers the PHY down. Linux writes 0 on this board | Linux `ax88796.c:75, 670`; `xsurf100.c` leaves `gpoc_val` 0 | confirmed (Linux); Amiberry ignores it |
| DCR 0x48 (byte transfers) while the PROM is read, 0x49 (word transfers, WTS) in operation | Linux `xsurf100.c:282`, `ax88796.c:669, 741`, `lib8390.c:1020-1022` | confirmed |
| RCR base 0x40, with AB (0x04) added in operation | Linux `xsurf100.c:283`, `8390.h:125` | confirmed (Linux). What bit 6 does on the AX88796B is **unconfirmed** (datasheet not read) |
| Station address: the AX88796B loads its EEPROM image into the PROM area; read 32 bytes by remote DMA in byte mode and take every second byte | Linux `ax88796.c:701-719` (programs a count of 6 and reads 32); this driver programs 32 and reads 32 | confirmed |
| Packet memory: 16 KB at 0x4000; TX from page 0x40, ring up to page 0x80; 12 TX pages hold two full frames | Linux `ax88796.c:72-73`, `8390.h:19` | confirmed |
| In word mode an odd TX count is rounded up to even | Linux `xsurf100.c:195` | confirmed |
| A remote-DMA write is complete when ISR RDC is set; Linux waits up to 20 ms, then resets and re-initialises | Linux `xsurf100.c` `xs100_block_output` | confirmed |
| Caches: on a 68030 in Zorro III mode the data cache must not be used for chip accesses; in Zorro II mode the 68030 cache is already bypassed for the card; on 68040/68060 the MMU marks the space non-cacheable | Maker | confirmed |

## X-Surf (the original card)

| Fact | Sources | Status |
|---|---|---|
| AutoConfig manufacturer 4626 (0x1212), product 23 (0x17), serial 0 | Maker; Linux `zorro8390.c:75`; Amiberry `expansion.cpp:6505-6512` | confirmed |
| Zorro II, 10 Mbit, BNC and twisted pair, 16 KB buffer memory | Maker | confirmed |
| Board size 64 KB | Amiberry; the maker's map ends at 0xFFFF | confirmed |
| Ethernet chip: the maker says "Realtek chipset". Amiberry models an RTL8019AS (plug-and-play resource data "REALTEK PLUG & PLAY ETHERNET CARD", chip ID bytes 0x50 0x70) | Maker; Amiberry `ne2000.cpp:1453-1468, 2111-2112` | the RTL8019AS part number is **model only** |
| ISA I/O space at board+0x8000–0x8FFF, addresses doubled: ISA port p is at 0x8000 + 2p, so ISA 0x300 is at 0x8600 | Maker; Linux uses 0x8600 with a 2-byte register stride (`zorro8390.c:46-76`) | confirmed |
| Access width: reads may be any size; the maker says writes should be word-wide only. Linux writes registers with byte writes | Maker vs Linux | **unconfirmed**: byte writes are used, as Linux does, and Amiberry implements them; there a word write writes two registers |
| board+0x007E: writing 0x80 drives ISA A11 high (adds 0x800 to ISA I/O addresses, which reaches the plug-and-play write-data port 0xA79); writing 0x00 restores it. Reading 0x007E can change A11, so a driver writes 0 back after any read. Bit 7 of a read is the IDE interrupt status | Maker; Amiberry `ne2000.cpp:1736-1744` (bit 7 of a write selects the upper ISA range) | confirmed |
| Ethernet interrupt status at board+0x0040, bits 7 and 5, always equal | Maker; Amiberry returns both bits (`ne2000.cpp:1749-1751`) | confirmed |
| IDE ports at 0xB000–0xBFFF and 0xD000–0xDFFF; IDE interrupt status at 0x007E bit 7; clock ports at 0xA001 and 0xC000; expansion port at 0x9000; ISA memory window at 0xE000. **This driver touches none of them**; it uses 0x0040, 0x007E (writes only, for plug-and-play) and 0x8000–0x8FFF | Maker | confirmed |
| Chip configuration: the maker does not say how the chip is configured. Linux does no plug-and-play and expects the chip at ISA 0x300. Amiberry requires ISA plug-and-play activation (initiation key, isolation, card number, I/O base, activate) before the chip answers | Linux `zorro8390.c`; Amiberry `ne2000.cpp:1757-1771` | **unconfirmed**. The driver probes ISA 0x300 first and runs the plug-and-play sequence only when no 8390 answers there |
| The chip's interrupt line through plug-and-play is not documented; Amiberry ignores the PnP IRQ register | Maker silent; Amiberry | **unconfirmed**: the interrupt self-test decides, else the driver polls |
| Data: 16-bit data port at ISA 0x310 (board+0x8620). The ring header's byte count arrives byte-swapped in a word read | Linux `zorro8390.c:48, 138` | confirmed |
| PROM read: byte mode, count 32, 16 byte pairs, every second byte kept; then DCR 0x49 | Linux `zorro8390.c:322-347` | confirmed |
| Packet memory as on the X-Surf-100: TX from page 0x40, ring to page 0x80 | Linux `zorro8390.c:64-65` | confirmed |

## The 8390 behaviour both cards share

These are DP8390 rules; Linux's `lib8390.c` implements them, and so does this driver.

| Rule | Where Linux shows it |
|---|---|
| **Initialisation order:** stop; DCR; clear the remote byte count; RCR monitor (0x20); TCR loopback (0x02); TPSR, PSTART, BNRY, PSTOP; clear ISR, mask IMR; page 1 station address and CURR; start; TCR normal; RCR on | `lib8390.c:1014-1072` |
| **Receive overrun:** note whether a transmit was in progress; stop; wait at least 1.6 ms (Linux 10 ms); clear the remote byte count; TCR loopback; start; drain the ring; acknowledge OVW; TCR normal; resend the frame if the transmit had neither completed nor failed | `lib8390.c:788-855` |
| **Counters:** on CNT read all three tally counters (frame alignment, CRC, missed). Reading clears them; an unread counter keeps CNT set | `lib8390.c:479-483` |
| **Transmit error:** acknowledge TXE; an aborted transmit (ABT or FIFO underrun) ends that frame like a completion, and the next frame is sent | `lib8390.c:533-577` |
| **Transmit timeout:** Linux allows 200 ms, then resets and re-initialises | `8390.h:116`, `lib8390.c:256-299` |
| **Receive:** CURR in page 1; the next frame is at BNRY+1. A header whose next-page pointer does not match the frame's length is a corrupt ring: resynchronise BNRY to CURR-1 and drop what was there. Valid lengths after the 4-byte header are 60–1518 bytes | `lib8390.c:659-786` |

## What the Amiberry model does not show

The model never raises a receive overrun, a counter interrupt or a transmit
error, and a transmit completes at the moment it is started
(`ne2000.cpp:356-361, 432-560`). It honours data-port reads past the
programmed count. It ignores GPOC, the AX88796B's own register bits and
the plug-and-play IRQ setting, and its plug-and-play resource-data reads
return 0 (`ne2000.cpp:1606-1640`). It keeps one network board per machine:
with an A2065 configured, an X-Surf is dropped (`cfgfile.cpp:7232-7260`).
The paths it cannot reach are covered by the host tests (`module/`), which
inject those events into a model 8390.
