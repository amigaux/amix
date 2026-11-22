# Changelog — kernel/drivers/xsurf

## 2026-11-22 — xsurf 1.0.0-5: xsf re-pinned for gcc14 276ef49 (38b920a9)

gcc14 276ef49 exports environ and _environ from every program, so /usr/sbin/xsf links 20 bytes longer (15088 bytes, a1c0485b; was 38a3bd99), the same code at shifted addresses, and make kspace refused it as unpinned. Package revision 1.0.0-5 of module 1.0.0-4 (module unchanged): xsurf30 6fd48f9c, xsurf46 a8cd1ba7, two rolls identical, the same bytes as on next.

## 2026-11-16 — xsurf 1.0.0-4 (fc943c76..5dfbb28f)

The driver follows the link: the X-Surf-100's link state, speed and duplex are read from the chip, a lost link is said once on the console, and transmit timeouts are noted with what the chip showed. The probe was reworked: a longer reset wait, registers tried by byte and then by word, a remote-DMA self-test, and a check that the registers answer; a board that fails is refused with the reason. The probe reads the station-address PROM through the board's data path, so a card whose registers answer only in the low half of a word is accepted. New: `xsf` is packaged (`/usr/sbin/xsf`, through `/dev/xsfctl`) and prints the board, the probe's readings, the link and the counters; pages xsurf(7) and xsf(1M). The packages carry `kbootset=` and need kbootset 1.1.0.261114-45 or later. Module 1.0.0-4 (k30 e8e7cd7a…, k46 b4e8316b…), packages xsurf30 1984592d…, xsurf46 5431d4df…. Host tests: 835, 152 and 53 checks. Run in emulation on the X-Surf-100 in Zorro III and II and on the X-Surf, on both lines, with strict-word, low-half, busy and fault rows, and as an upgrade on an installed 1.1.1; the README's Tested section lists the rows and what users reported from real cards.

## 2026-11-14 — xsurf 1.0.0-3 (8eedd1cd..31dc6f50)

Fix: `ifconfig xsf0` showed `flags=0<>`. The driver acknowledged the interface-flags ioctls (SIOCGIFFLAGS, SIOCSIFFLAGS) without the request record; it now returns the message as it came, as the stock ethernet driver does, and the interface shows `flags=23<UP,BROADCAST,NOTRAILERS>`. The transparent form of the two is refused with EINVAL. The other interface ioctls were checked and are unchanged (refused, as before). Host tests: 555 and 46 checks, with a new case for the interface ioctls. Module 1.0.0-3 (k30 eafad2d4…, k46 e01d1b13…), packages xsurf30/xsurf46 1.0.0-3. Run in emulation on the X-Surf-100 in Zorro III and II and on the X-Surf; the README's Tested section lists the checks (217e651d).

## 2026-11-14 — xsurf 1.0.0-2 (cdc1b584..1c6b4380)

The status record counts ack_retries; the console line prints the station address with leading zeros; userland/xsf.c, a status tool built on the box (not packaged); the README's Tested section comes from emulator runs on both lines: X-Surf-100 in Zorro II and III and the X-Surf, with interrupts and polled. Module 1.0.0-2, packages xsurf30/xsurf46 1.0.0-2. Not yet run on a real card.

## 2026-11-14 — new: xsurf 1.0.0-1, ethernet for the X-Surf-100 and the X-Surf (c9d090df..22e64df2)

A STREAMS/DLPI ethernet module (xsf0, xsf1; character major 56) for the Individual Computers X-Surf-100 (Zorro II and Zorro III) and X-Surf (Zorro II), on k30 and k46; packages xsurf-k30 / xsurf-k46 1.0.0-1 (xsurf30, xsurf46). A shared 8390 core with receive-overrun recovery, all three tally counters, transmit error and timeout restart, and delays timed by the CIA. Interrupts by default (intr=2): level 2 after a self-test in which the board raises the interrupt, polling when the test fails or interrupts stop (C3-6 version 12 §1.3); intr=0 polls. The X-Surf's ISA plug-and-play runs only when the chip is not at 0x300. Board facts with their sources are in docs/facts.md; the README lists what needs a real card. Host tests with a model DP8390 and fault injection: 487 and 46 checks. The packages need a kbootset with c 56 xsurf (1.1.0.261114-45 or later). Tested on the host only; not yet run in emulation or on a card.

Credits: the X-Surf-100 support follows ales9030's port, itself based on isoriano1968's Hydra AMIX driver.
