# Changelog — kernel/drivers/xsurf

## 2026-11-14 — xsurf 1.0.0-2 (cdc1b584..1c6b4380)

The status record counts ack_retries; the console line prints the station address with leading zeros; userland/xsf.c, a status tool built on the box (not packaged); the README's Tested section comes from emulator runs on both lines: X-Surf-100 in Zorro II and III and the X-Surf, with interrupts and polled. Module 1.0.0-2, packages xsurf30/xsurf46 1.0.0-2. Not yet run on a real card.

## 2026-11-14 — new: xsurf 1.0.0-1, ethernet for the X-Surf-100 and the X-Surf (c9d090df..22e64df2)

A STREAMS/DLPI ethernet module (xsf0, xsf1; character major 56) for the Individual Computers X-Surf-100 (Zorro II and Zorro III) and X-Surf (Zorro II), on k30 and k46; packages xsurf-k30 / xsurf-k46 1.0.0-1 (xsurf30, xsurf46). A shared 8390 core with receive-overrun recovery, all three tally counters, transmit error and timeout restart, and delays timed by the CIA. Interrupts by default (intr=2): level 2 after a self-test in which the board raises the interrupt, polling when the test fails or interrupts stop (C3-6 version 12 §1.3); intr=0 polls. The X-Surf's ISA plug-and-play runs only when the chip is not at 0x300. Board facts with their sources are in docs/facts.md; the README lists what needs a real card. Host tests with a model DP8390 and fault injection: 487 and 46 checks. The packages need a kbootset with c 56 xsurf (1.1.0.261114-45 or later). Tested on the host only; not yet run in emulation or on a card.

Credits: the X-Surf-100 support follows ales9030's port, itself based on isoriano1968's Hydra AMIX driver.
