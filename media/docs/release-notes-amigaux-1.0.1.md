# amigaux 1.0.1 — release notes (DRAFT, installer and K1 card part)

**amigaux 1.0.1** — Amiga UNIX 2.1 install kit for the Z3660 and classic Amigas, release 1.0.1 (card set and
media cut r7). It changes networking only; everything else is as in 1.0 (`docs/release-notes-amigaux-1.0.md`).

## Networking

- **Faster Ethernet:** every kernel raises the TCP receive queue limit from 4 KB to 16 KB; the Z3660 ethernet
  driver holds received frames while the stack is busy instead of dropping them; the Z3660 firmware gains a
  16-descriptor receive ring. FTP from host to Amiga goes from about 25–30 KB/s to 404 KB/s on the A4000T and
  328 KB/s on the A4000D, and from Amiga to host runs at 599 and 603 KB/s (100 Mbit/s full duplex).
- **Gigabit is opt-in:** add `eth_adv1000 YES` to `z3660cfg.txt` to advertise 1000BASE-T; the default stays 100
  because Amix receive throughput regresses at gigabit on this firmware.

## Firmware

- `Z3660.bin` is fork 1.0.1 (9994961A). `BOOT.BIN` (C96EAD03, the start-up loader) and `FAILSAFE.bin` (stock
  1.03 BETA 21, C0ADE49A) are unchanged from 1.0.
- Back to the 1.0 firmware: copy `hdf/rollback-C96EAD03.bin` (the card's exFAT partition) over `0:/Z3660.bin`, or
  delete `Z3660.bin`.

## Credits

These cover 1.0 as well; the 1.0 notes are frozen.

- **RTG desktop:** the Amix RTG driver is Ignacio Soriano's zz9000-amix (isoriano1968/zz9000-amix, MIT), adapted
  for the Z3660 in amix-z3660rtg; X11 from his x11r6.3-amix.
