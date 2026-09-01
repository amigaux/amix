# Amix on the A4091 — a Zorro III SCSI driver for Amiga UNIX

A native SCSI driver and a universal, auto-detecting kernel that let **Amiga UNIX (Amix —
Commodore's SVR4.0 port to the 68030 Amiga)** drive — and **boot from** — the **Commodore A4091**,
a **Zorro III** SCSI-2 host adapter built on the **NCR/Symbios 53C710**. The same driver also binds
the modern 53C710 boards that reuse the A4091 design — the **A4092** and the **A4770** (SCSI.ME,
AutoConfig manufacturer `0xc0de`).

Amix shipped with no 53C710 driver and is documented as **Zorro II only**. This project closes both
gaps: the A4091 is now a first-class, auto-detected SCSI controller that coexists with the stock
A2090/A2091/A3000 drivers, and Amix boots with **root, swap and filesystem entirely on an A4091** —
which is what a real **Amiga A4000** needs, since the A4000 has no built-in SCSI at all.

> Status: **proven in emulation (Amiberry) on both an A3000 (ECS) and an A4000 (AGA) profile, from one
> kernel binary.** Real-hardware validation is the remaining open item. Confidence tags (✅ reproduced /
> 🟡 emulation-only) are used below.

---

## What works

- ✅ **A 53C710 block driver for Amix** ([`src/a4091-wr.c`](src/a4091-wr.c)) — table-indirect SCRIPTS,
  one program that does both `READ(10)` and `WRITE(10)` by dispatching on the live SCSI bus phase. The
  A4091 disk is a fully usable Amix filesystem: `mkfs ufs` + `mount`, files persist, end to end.
- ✅ **Boot with root on the A4091** — root (read/write), swap, multi-user, networking, with the A3000's
  own SCSI switched off. Boots to login in ~160 s including fsck.
- ✅ **One universal kernel for both machines** — the same binary auto-detects the hardware: an A3000
  boots on its own WD33C93 SCSI with the A4091 coexisting as a second card, and an A4000 + A4091 boots
  with root on the A4091. Detection is a **chipset gate + WD33C93 probe** in `autocon()`
  ([`src/kernel-patches/support.c.patch`](src/kernel-patches/support.c.patch)), not a hardcoded
  assumption.
- ✅ **SCSI tape read, including the short read at a filemark** — a target that ends `DATA_IN` early
  used to look like a "SCSI timeout" mid-`MOVE`. The SCRIPTS now take the phase-mismatch interrupt,
  read the residual (DBC), drain the SIOP FIFO and re-dispatch to collect STATUS + MSG_IN, so the
  `ct` tape driver gets the real target status and the short byte count and runs its normal REQUEST
  SENSE / File-Mark / EOF handling. A full multi-package install from tape completes with zero a4091
  I/O errors.
- ✅ **CD / optical passthrough** — `gsioctl()` bounced every `/dev/scsi` GSIO transfer through a
  single 1 KB static buffer and rejected anything larger, so a 2048-byte CD-ROM block could not pass
  at all. [`src/kernel-patches/scsi.c.patch`](src/kernel-patches/scsi.c.patch) grows it to 64 KB
  (static kernel BSS, no allocation path). This is what unblocked the companion `amix-cdfs` optical
  filesystem, which reads a genuine Rock Ridge CD through the A4091 byte-exact — including a
  102000-byte, 50-sector transfer in one call.
- ✅ **Two fixes to Amix's *own* WD33C93 drivers**, both latent since **stock**:
  [`a3091.c.patch`](src/kernel-patches/a3091.c.patch) (A3000 internal SCSI) and
  [`a2091.c.patch`](src/kernel-patches/a2091.c.patch) (the A2091/A590 card it is templated on). The
  chip-memory DMA bounce kept its buffer pointer and byte count in *shared* state while both drivers
  run a multi-target disconnect/reselect DFA — a reselect between two active targets could copy one
  unit's bounce buffer back over another unit's memory (stray write → `hat_pt2ptdat` panic /
  `User BUS ERROR`); the bounce state is now per-unit, beside the per-unit saved transfer count. And
  a unit resumed from reselect was left linked on the start queue, so the next `startany()`
  dereferenced a drained entry → NULL `comhead` → wild DMA. Like the boot-breaker below, these bite
  *anyone* running Amix on an A3000 or an A2091 — A4091 or not.
- 🟡 **A4092 and A4770 boards as well as the A4091** — [`driver.conf`](driver.conf) registers all
  three AutoConfig identities (A4091 `0x0202/0x54`, A4092 `0xc0de/1`, A4770 `0xc0de/2`) against the
  same `a4091queue`, and `a4091map()` maps each board from the base the `sd` layer recorded for that
  card rather than a hardcoded address — so several 53C710 boards can be driven at the same time.
  Code path and identities only: **no A4092 or A4770 hardware has been tested.**
- ✅ **A fix for the kernel "boot-breaker"** — relinking the Amix kernel hits an intermittent (~70%)
  `ld` write corruption that Guru-Meditates the relocator (`D245`). The build harness (in the companion
  **amix-kerntools** repo) defeats it by relinking until the output checksum is stable. This bug bites
  *anyone* who relinks the Amix kernel, A4091 or not.

---

## Why it was hard

- **The Zorro III gap.** The A4091 lives at physical `0x40000000`, which falls in the unmapped gap
  between the 68030's two transparent-translation windows — so a stock Zorro II driver simply can't
  reach its registers. The driver page-maps the board with `sptalloc()` instead. DMA still lands in
  low RAM, so bus-mastering is unaffected.
- **No 53C710 driver, no debugger.** The driver is built **natively on the box** (no cross-compiler),
  with a K&R-friendly SVR4 `cc`, no `nm`/`dis`/`dump`, and a big-endian ILP32 ABI.
- **The relocator was a red herring twice over.** The `D245` Guru looked like a poll-loop bug, then a
  relocator bug; it was actually a random file-write corruption. And the "can't boot from A4091" panic
  looked like an early-boot driver problem; it was actually a device-dispatch bug — a *phantom* A3000
  SCSI hardcoded whenever RAM > 7 MB stole card 0 and the root read went to non-existent hardware.

---

## Repository layout

| Path | What |
|---|---|
| [`src/a4091-wr.c`](src/a4091-wr.c) | The production 53C710 READ+WRITE driver. |
| [`src/a4091-detection.c`](src/a4091-detection.c), `src/a4091*.c` | The detection milestone and the incremental driver variants / on-box probes (`memread.c`, `makebigfile.c`, …). |
| [`src/kernel-patches/`](src/kernel-patches/) | Four substantive shared-kernel edits, shipped as **diffs** against stock Amix: `support.c.patch` (A3000-vs-A4000 auto-detection → `amiga/kernel/support.c`); `scsi.c.patch` (enlarge the `/dev/scsi` GSIO passthrough bounce buffer 1 KB → 64 KB so a 2048-byte CD block / multi-sector chunk can pass → `amiga/alien/scsi.c`); `a3091.c.patch` (A3000 internal-SCSI super-DMAC — per-unit chip-memory DMA bounce, closing cross-unit reselect aliasing, plus the start-queue lifecycle repair → `amiga/alien/a3091.c`); and `a2091.c.patch` (the identical pair of fixes on the A2091/A590 template the A3000 driver derives from → `amiga/alien/a2091.c`, build-validated only). **The last two fix latent defects in stock Amix itself** and matter to any A3000 or A2091 owner, A4091 or not. The `sd.c` `scsicard[]` rows, `sdcardbase()` and the `alien` Makefile `OBJ` entries are **generated by `amix-kerntools` from [`driver.conf`](driver.conf)** — this repo does not ship them. |
| [`reference/scripts/`](reference/scripts/) | The NCR 53C710 SCRIPTS assembler source the driver runs (`inq.ss`, `inq-wr.ss`) and their assembled output. |
| [`reference/a4091-study.md`](reference/a4091-study.md) | Archived 2026-06 research notes on the 53C710 (register map, init sequence, SCRIPTS encodings, ROM/build tooling), written against the early detection prototype and superseded by `src/a4091-wr.c`; kept for its derivations and its citations into `a4091-software` and NetBSD `siop`. |
| [`driver.conf`](driver.conf) | The three AutoConfig identities the driver binds (A4091, A4092, A4770), consumed by the build harness. |
| [`tools/`](tools/) | Host-side test tooling: `bisect-boot.sh`, `gsio-test.sh`, `gsio-wtest.sh`, `measure-corruption.sh`, `parse_rdb.py`. |
| [`docs/`](docs/) | The 53C710 register / SCRIPTS reference. |
| `*.uae` | Sample Amiberry configs for the A3000/ECS, A4000/AGA and build environments (edit the placeholder paths). |
| `hdf/`, `tmp/`, `build/`, ROMs | **git-ignored** — proprietary disk images, ROMs and scratch (see Legal). |

The build harness, clean-gate, the FTP/telnet bridges and the golden build image live in the companion
**[amix-kerntools](https://github.com/jusii/amix-kerntools)** repo; the host network bridge lives in
**[grimoire-amix](https://github.com/jusii/grimoire-amix)**. Clone them as siblings of this repo.

---

## Build & run (emulation)

You need a working Amix 2.1 install in **Amiberry**, the A4091 autoboot ROM, and a spare hardfile for
the A4091 disk. (None of these are in this repo — see Legal.) The companion
[amix-kerntools](https://github.com/jusii/amix-kerntools) and
[grimoire-amix](https://github.com/jusii/grimoire-amix) repos provide the harness; clone them as
siblings of this repo and `set AMIX_HOST`/`AMIX_USER`/`AMIX_PASS` for your box.

1. **Reach the box.** Files go over FTP (Amix is NFSv2-only):
   `../amix-kerntools/tools/amixsync.py push <file>` (the path is the sibling clone). Commands go over
   scripted telnet: `../grimoire-amix/tools/host-net/amixsh.py '<cmd>'`.
2. **Install the driver + patch** into your Amix source tree:
   - Push the driver as the `alien` source:
     `amixsync.py push src/a4091-wr.c /usr/sys/amiga/alien/a4091.c`
   - Apply the auto-detection patch (idempotent — Amix 2.1 is a single frozen version, so it applies
     cleanly; re-applying is detected and skipped):
     ```sh
     cd /usr/sys && patch -p0 < support.c.patch     # amiga/kernel/support.c
     ```
   - The `amix-kerntools` harness reads [`driver.conf`](driver.conf) and **generates** the
     `amiga/alien/sd.c` registration rows + `sdcardbase()` and the `alien` Makefile `OBJ` entries —
     you do not write those by hand.
3. **Build a clean kernel** — never trust a single `make`; the `amix-kerntools` clean-gate relinks until
   the output checksum recurs (== the clean kernel) to defeat the `D245` boot-breaker.
4. **Install onto a throwaway/clone disk's boot partition** — *never* `make install` onto your working
   disk:
   ```sh
   cd /stand
   ( cat boot1.boot; ./makeiblk boot2.boot; cat boot2.boot; ./makeiblk unix; cat unix ) \
     | dd conv=sync of=/dev/dsk/c8d0s3
   ```
5. **Boot.** Use `amix-a4091-boot-aga.uae` (A4000/AGA + a Kickstart 3.0 A4000 ROM) for the
   root-on-A4091 case, or `amix-dbg.uae` (A3000/ECS) for the A3000 + A4091-coexists case. (Edit the
   placeholder paths in the `.uae` first.)

> ⚠️ A corrupt kernel written to a boot partition bricks that disk. Always clean-gate the build, keep a
> backup HDF, and install onto a clone. The working disk is never touched by the dev loop.

---

## Status

| | Emulation (Amiberry) | Real hardware |
|---|---|---|
| A4091 disk read/write, UFS filesystem | ✅ | 🟡 pending |
| Boot with root on the A4091 (A4000-style) | ✅ | 🟡 pending |
| A3000 + A4091 coexisting (root on A3000) | ✅ | 🟡 pending |
| One universal auto-detecting kernel | ✅ | 🟡 pending |
| CD / optical read through the `/dev/scsi` GSIO passthrough | ✅ | 🟡 pending |
| SCSI tape read, incl. the short read at a filemark | ✅ | 🟡 pending |
| A3000 internal SCSI: concurrent multi-target I/O | ✅ | 🟡 pending |
| A4092 / A4770 boards | 🟡 code path only | 🟡 no hardware |

The chipset gate reads VPOSR (always-present, bus-safe) and skips the A3000 SCSI probe entirely on an
A4000. Where the gate *does* let the probe run, it is a **two-register anti-alias** test: write `0x55`
to WD33C93 register 0x02 and `0xAA` to register 0x03 through the shared data port, then re-select
register 0x02 and read it back. A real chip keeps the two registers distinct; an emulator's
per-address open-bus latch returns only its own last write, which is why the earlier single-register
0x55/0xAA test always self-confirmed and synthesized a phantom A3000 that stole card 0. The hardening
removes that false positive and nothing else — on metal the outcome is unchanged. What emulation
still cannot stand in for is the completion timing of a *physical* (non-instant) disk, so the probe
and the driver's completion path can only be fully trusted once run on a real A3000 and a real
A4000 + A4091.

---

## Legal

Amix, its HDF/ADF disk images, Kickstart ROMs and manuals are **proprietary Commodore software**
(abandonware, not licensed for redistribution) and are **not** included here — the relevant paths are
git-ignored. You must supply your own legally-obtained copies. The kernel changes are shipped as
**patches** against the stock Amix source, so this repo contains only the original contribution, not
Commodore/AT&T source. The A4091 autoboot ROM and the `ncr53cxxx` SCRIPTS assembler come from the
open-source [a4091-software](https://github.com/A4091/a4091-software) project.

The original code in this repository (driver, patches, tooling, SCRIPTS) is the author's own work and is
released under the **MIT License** — see [`LICENSE`](LICENSE).

## Credits

By Jussi Alanärä. AI tooling — **Claude Code** — was used throughout to investigate, build and verify
this work. Built on the reverse-engineering and documentation efforts of the Amiga Unix community and
the a4091-software project.
