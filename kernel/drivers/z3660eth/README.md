# z3660eth — native AMIX ethernet driver for the Z3660

A native **Commodore Amiga Unix (AMIX, SVR4.0, m68k 68030) STREAMS/DLPI ethernet
driver** for the **Z3660 accelerator's onboard ethernet** — the network analogue
of the [`z3660scsi`](../z3660scsi) SCSI driver. It is **not** NIC emulation: the
Z3660 firmware already moves whole ethernet frames between the 68k guest and the
Zynq GEM (for AmigaOS's SANA-II `Z3660Net.device`); this driver speaks that same
firmware mailbox and presents it to AMIX as a DLPI Style‑1 connectionless
ethernet provider bound up by `slink` + `ifconfig`.

The full design + the source‑grounded scoping (protocol contract, cache‑coherency
analysis, INT6 finding, phased plan) lives in
[`docs/ETHERNET-SCOPING.md`](docs/ETHERNET-SCOPING.md), with the supporting
evidence dossier in [`docs/ETHERNET-SCOPING-evidence.md`](docs/ETHERNET-SCOPING-evidence.md).

## Scope / responsibility

This directory, `kernel/drivers/z3660eth` of the amix monorepo (formerly the repo
`amix-z3660net`), is **the AMIX ethernet driver (`z3660eth`) for the Z3660, plus its
design docs, and nothing else.** Its siblings: SCSI driver → [`z3660scsi`](../z3660scsi);
firmware / 68k-emulator → [`Z3660-amix`](https://github.com/jusii/Z3660-amix), the Z3660
firmware fork, which stays its own repository; build harness + golden image + host-ops →
amix's [`kernel/k30`](../../k30) build hub. The full map is in
[`kernel/k30/REPOS.md`](../../k30/REPOS.md).

Compilation and kernel integration are handled by the `kernel/k30` build hub, which
reads this directory's `driver.conf`. This directory carries only the driver source,
its `driver.conf`, the loadable-module form, the userland bring-up, and the design docs.

## Building

The kernel build goes through `kernel/k30`'s harness: bring up your Amix box (real
hardware, or your own WinUAE/Amiberry config with an a2065 NIC on tap0), then

```sh
(cd ../../k30 && ./amix-build z3660eth)                     # the net driver alone
(cd ../../k30 && ./amix-build a4091 z3660scsi z3660eth)     # combined kernel
```

`BUILD.md` is the manual procedure the harness automates.

The loadable module ([`module/`](module/Makefile)) builds inside amix against
[`kernel/dlm`](../../dlm)'s ABI kit: build the kit there (`make kit`, see
[`toolchain/README.md`](../../../toolchain/README.md)), then run `make -C module` here,
`make -C module test` for the host test of its parameter parser, and
`bash tools/patch-selftest.sh` for the on-box patch scripts' host battery.
`DLM=` or `KIT_k30=`/`KIT_k46=` point at a kit elsewhere.

`z3660eth` registers at **cdevsw major 51** (renumbered from 48 on 2026-07-30 —
48 turned out to be contested; see `BUILD.md` §2(b)), and its device node is
`/dev/zen0` = `mknod /dev/zen0 c 51 0`. Those are the two integration facts
another driver author or a packager needs first.

## Status — ✅ WORKS ON REAL HARDWARE (2026-06-21)

AMIX has full bidirectional TCP/IP over `zen0` on a real **A4000 + Z3660**:
`zen0` UP @ `192.0.2.39`; laptop→box flood ping **40/40, 0% loss**; box pings
both the laptop and the gateway; `telnet`/`ftp` over `zen0` work; `netstat -in`
shows **0 input errors, 0 output errors, 0 collisions**; sustained FTP throughput
**~185 KiB/s** (stable across runs). GEM MAC `00:80:51:01:02:03`.

The **only** real-HW blocker was an **INT6 interrupt storm**: the firmware raises
Amiga INT6 on every received frame, but AMIX has no level-6 ethernet handler, so
the LAN's ARP broadcasts storm the box into a hard lock. Fix = the driver writes
`ZZ_CONFIG_DISABLE` so the firmware never raises INT6; RX is serviced by the bounded
poll/drain callout instead (commit `028c8d2`). No firmware change was needed, and
no cache maintenance was required either (the 030 data cache is transparent to the
eth DDR windows here). The `Z3660ETH_CACHE_FLUSH` `#ifdef` that once held that
maintenance is gone: 040/060 maintenance and an attach-time cache-inhibit assert
are now compiled in always and gated at run time by `z3660eth_cache`, whose
default 0 keeps every 040/060 opcode unreachable on the shipping images — see
`docs/BLIZZARD-F3.md`.

## Bringing it up on a real box → [`docs/ZEN0-BRINGUP.md`](docs/ZEN0-BRINGUP.md)

**★ Under the Amix-interop Z3660 firmware fork, Amix's stock `aen` ethernet driver
can never work — `zen0` is the only path.** `aen` hunts Commodore/A2065 board id
`0x02020070`; the firmware presents every emulated autoconfig board as manufacturer
`0x144B` and has A2065 emulation commented out of its embedded UAE core. A
manufacturer id is not settable by any `autoconfig_*` key, so no configuration
reaches this. Corollary worth the several hours it cost: *"that box networks on
`aen0`"* is a fact about **that box's firmware build** and never transfers across a
firmware boundary.

[`docs/ZEN0-BRINGUP.md`](docs/ZEN0-BRINGUP.md) is the field-proven runbook — the
evidence for the above, the five-command manual bring-up (verified first try on real
68LC060 metal, 2026-09-09), the three identity files (and why `setuname -n` is *not*
one of them), and a triage section for telling which path a box is on.

**Configuring `zen0`.** A box brings `zen0` up at boot through the one network set-up
every interface shares (amix `userland/base`): one line in `/etc/inet/interfaces`, for
example

```
zen0    static  192.0.2.39/24  gw 192.0.2.1
```

or `zen0 dhcp`. `ifup` (run by `inetinit` at boot, or by hand as `ifup zen0`) finds the
driver through its vendor entry `/etc/inet/link.d/z3660eth` ([`link.d/z3660eth`](link.d/z3660eth)
here: interface prefix `zen`, node prefix `/dev/zen`, first unit 0, static-kernel major 51),
makes `/dev/zen0` if it is missing, links it under IP and ARP once, and applies the line.
The z3660eth package ships that entry and the node; the major on a module kernel comes
from the module registry (`kbootset major z3660eth`). The file formats are in
`interfaces(4)` and `link.d(4)`.

## Layout
- `src/z3660eth.c` — the driver (STREAMS/DLPI skeleton adapted from the stock
  `aen`/`hydra` drivers; chip layer replaced by the Z3660 mailbox).
- `src/z3660eth.h` — register map + frame‑window layout + kernel structs (every
  offset verified against `z3660-drivers/common/z3660_regs.h` and the firmware
  `Z3660/src/{ethernet.c,memorymap.h,rtg/rtg.c}`).
- `src/z3660ethuser.h` — user‑facing ioctls + status struct (no kernel types).
- `src/Makefile` — installed as `/usr/sys/amiga/driver/z3660eth/Makefile`.
- `module/` — the loadable-module form (`-DZ3660ETH_MODULE`) built with
  the dlm ABI kit (amix `kernel/dlm`): `Makefile` (`make -C module`, one module per kernel
  line) and `Master` (its `.moddata` keys, one for both lines); BUILD.md §9,
  NOTES.md
  "Module form".
- `driver.conf` — the `net` stanza consumed by `amix-build`.
- `link.d/z3660eth` — the driver's `/etc/inet/link.d` entry (link.d(4)), shipped
  by the package for `ifup`.
- `userland/` — `zen.c` (the `zen` presence and status tool) and `bringup.sh`, the
  manual interface bring‑up for the bench.
- `tools/` — the two fail‑closed on‑box patch scripts (`patch-kernel.sh` claims
  the cdevsw row, `patch-makefile.sh` the driver `OBJ` list) plus
  `patch-selftest.sh`, their benchless host‑side fixture battery.
- `BUILD.md` — the exact on‑box build + kernel‑integration steps (the manual
  procedure that `kernel/k30` automates).
- `docs/ZEN0-BRINGUP.md` — the field-proven bring-up runbook: why `aen` can never
  work under this firmware, the five-command sequence, persistence through
  `/etc/inet/interfaces`, the identity files, and how to tell which path a box is on.
- `docs/BLIZZARD-F3.md` — the cache-coherence pre-registration and its round-2
  result: why the 030 needs no maintenance and how the 040/060 gate works.
- `CHANGELOG.md` — what changed, when, and against which commit.

## How it works (one paragraph)
Discovery mirrors `z3660.c`: `autocon(0x144B0001)`, else (AGA only) the fixed combo
base `0x10000000`, verified via the firmware MAC register. When the whole window
lies below `VSECT1` (`0x40000000`) the physical base is used as the kernel VA
directly — AMIX's section‑0 early‑termination identity map, no `sptalloc`; only a
board at or above `VSECT1` takes the `sptalloc` arm, which the 040/060 cache work
declares unsupported with a live data cache. The board's eth
registers sit in the RTG register page (`board+0x104..0x1A8`); TX frames stage at
`board+0x07EE0000`, the RX backlog ring at `board+0x07ED0000` (32×2048, 4‑byte
`[len][serial]` header). **TX** copies the frame to the TX window and writes the
length to `ZZ_ETH_TX` (synchronous, ~1 ms, no completion IRQ). **RX** is drained
by re‑reading `ZZ_ETH_RX_ADDR`, breaking on the serial sentinel, and strobing
`ZZ_ETH_RX` per slot. The firmware raises RX as Amiga **INT6/EXTER**, for which
AMIX has no driver hook — so RX is drained from a **clock‑level `timeout()` poll
callout** by default (`z3660ethintr()` exists for a future interrupt path).

## License
MIT — see [`LICENSE`](LICENSE). The STREAMS/DLPI scaffolding was originally adapted
from Commodore's stock AMIX `aen`/`hydra` drivers; the MIT grant covers this directory's
own work. AMIX itself (SVR4.0) is proprietary — you need a licensed AMIX system and a
Z3660 accelerator to build and run this driver.

### Trademarks
The wording Amiga Corporation asked us to carry:

This project and its developers are not affiliated with, endorsed by, or sponsored by
Amiga Corporation. Amiga is a registered trademark of Amiga Corporation.

AmigaOS and Amiga UNIX are trademarks of their respective owners, and UNIX is a
registered trademark of The Open Group. See [`NOTICE`](NOTICE).
