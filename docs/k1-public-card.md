# The public K1 card (the workspace's `cards/k1-public`)

The distributable Amix card for an A4000/A4000T with a Z3660 and a real 68060. The card
directory is gitignored (it holds the disk images); this file and `profiles/cards/k1-public.card`
are its tracked record. Publishing the card or any file on it is decided per artefact.

## Layout

- `fat/` = partition 1 (FAT32, the Z3660's `0:`): the firmware images.
- `exfat/` = partition 2 (exFAT, `1:`): `README.txt` (the user note), `z3660cfg.txt`, `presets/`,
  `kicks/` (the 68060 + SCSI-boot shims only; the user adds `kickstart.rom`),
  `hdf/` (k1-install, k1-unatt, k1-desktop-rtg, k1-blank200).
- `MANIFEST.sha256` covers every file of both partitions; `installng/` holds build logs and evidence.

**Gate:** `tools/card-audit.py ../cards/k1-public profiles/cards/k1-public.card` must PASS. It checks:
- the pinned firmware images, and their CRC32s cited in README.txt;
- the MANIFEST;
- REL-1: no Kickstart-sized file on the card;
- REL-2: the boot priorities;
- the kernel framed in each hdf.

It also runs `tools/sec1check.py` and `tools/fsdupcheck.py` on the hdfs.

## Firmware (r5): ships the fork, stock kept as the rollback (layout A')

The Z3660 loader starts `0:/Z3660.bin` if it exists, else `FAILSAFE.bin`, else `BOOT.BIN`
(Z3660 `docs/amix-firmware-facts.md` §3).

| file | image | crc32 |
|---|---|---|
| `BOOT.BIN` | fork 1.0 (its own FSBL) | C96EAD03 |
| `Z3660.bin` | fork 1.0 | C96EAD03 |
| `FAILSAFE.bin` | stock 1.03 BETA 21, byte-intact | C0ADE49A |

Why A' and not A: the Z3660 bench's A3 test found the fork failed 3 of 4 cold boots under the STOCK FSBL,
two at a new stop in the MMU/cache setup. Under its own FSBL it boots first time.

Rollback, two levels (README.txt):
- quick: delete `Z3660.bin`. The stock app then runs under the project's FSBL.
- full stock: copy `FAILSAFE.bin` over `BOOT.BIN`, then delete `Z3660.bin`.

`FIRMWARE_ACCEPTED` flips when the Z3660 bench reports the quick path cold-booting the bench OS (3 boots).
Wording: "ships with the project's firmware; stock firmware works with the caveats below". The caveats are
`kickstart 0` black-screening on a real CPU and the rare piscsi register race.

## Revisions

| rev | date | what |
|---|---|---|
| r1–r3 | 2026-10-02/03 | public profiles + dialog flavour (I2), static apkg on pkg.amigaux.org (I1), SEC-1 permissions |
| r4 | 2026-10-03 | REL-1 (MAPROM from the user's ROM, `kickstart 1`), REL-2 (installers boot pri 1); proven on both benches |
| r4.1–r4.7 | 2026-10-03 | docs only: troubleshooting (start stall, self-reset, post-fsck restart), MAC per machine, the unit-6 rule (Amix roots the disk at Z3660 unit 6; preset 3 after an install), clean shutdown + wait ≥ 10 s after the halt |
| r5 | 2026-10-04 | amigaux 1.0 candidate: O5 kernel KD060-Z r5 99d3caf9; root unit picked at install (u0-u5 chains, /stand/unix = the framed kernel, re-registered with APKG's installf); fork firmware 1.0 layout A'; presets 0/3 at scsi0. Cells U, A2, I, I-boot, M, M-boot green; card-audit PASS. Hdfs k1-install f645d75e, k1-unatt e1d71d8c, k1-desktop-rtg f708dbe9 (unit 0). |

**2026-10-03 — firmware candidate in, layout A chosen** (Z3660 firmware). The images are fork 1.0 `Z3660.bin` C96EAD03 (f267288c…, release-1.0-fw ee13c09) and stock `BOOT.BIN` = `FAILSAFE.bin` C0ADE49A (985c11e4…, upstream 1.03 BETA 21). Rollback: delete `Z3660.bin`. `FIRMWARE_ACCEPTED` stays PENDING until the fork runs under the stock FSBL on the A4000T. Open: cand 7 makes `kickstart 0` work on the fork, so the r4 REL-1 text ("not supported") and the `kickstart 1` presets need a decision.

**2026-10-03 — r5 kernel inputs and the cross-check.**
- O5 is KD060-Z r5 (kerntools f794d9a): c0-u6 99d3caf9 / D27DFAC1 / sum -r 55291 (ZS-04 + the sddevsize fix; KERNEL_SDDEVSIZE=fixed, so the 602 MB cap is lifted).
- The root unit is picked at install. kerntools' per-unit set is 59a60b2 (q415/PINS-c0-u0-u7.json).
- **Cross-check:** installng builds its per-unit chains by its own path (`tools/units-table.py` pins, checked against kerntools' `kernel-rootdev-stamp.py table`; `tools/build-unit-donors.sh` frames gated donors; `build-bootslice.py` extracts).
  - Those chains are byte-identical to kerntools' q415 bootslices for u0-u5 (their 2 MiB slice = our padded chain + zeros).
  - kerntools' PINS equal our unit table row by row.
- dumpdev: the stamp leaves it at c6d0s2 in every unit, which is INERT. The port proved AMIX 2.1 never writes a crash dump (sysdump is an empty stub; nothing references dumpdev/do_sysdump), so the per-unit stamp (b) was dropped. The chains stay as 59a60b2 (re-checked unchanged). Release notes: no crash dump; the console/serial panic text is the only record.

**2026-10-03 — decisions for the r5 cut.**
- Kickstart: the presets stay on `kickstart 1` + the user's ROM. README: "`kickstart 0` works with this card's firmware on a real CPU; on stock firmware it black-screens -- keep MAPROM" (survives a rollback). No preset pairs.
- Release name: **amigaux 1.0** -- "Amiga UNIX 2.1 install kit for the Z3660 and classic Amigas, release 1.0". It goes in the README headers and in `docs/release-notes-amigaux-1.0.md`. The card has no filesystem labels (make-card.sh), so the README headers are its label.
- REL-3: the MAC stays README-only (the r4.2 wording); no randomisation in 1.0.
- Layout A is confirmed (the stock FSBL fall-through checked at 50e98e0 and 25587f5). `FIRMWARE_ACCEPTED` flips on the Z3660 bench's A4000T step A3.
- The r5 `README.txt` and `z3660cfg.txt` are staged in the maintainer's notes.

**2026-10-03 — r5 prepared, not cut.** Inputs are pending: the O5 kernel (KD060-Z: ZS-04 + the sddevsize fix, from kerntools) and the O18 firmware (the Z3660 bench's 1.0 image, its layout and README text). `profiles/cards/k1-public.card` holds every pin as PENDING.

The cut, kernel first:
1. Re-author and populate both sources on the new kernel.
2. Re-install the desktop from the unattended source.
3. Fill the pins.
4. Write the firmware section, then the MANIFEST.
5. Run `card-audit`, `sec1check`, `fsdupcheck` and the emulator cells (install, unattended, dialog, desktop, public-flavour audit).

Metal re-acceptance on both benches follows via the Bench and Z3660 stations.

## 1.1 items (deferred from the r5 cut)

- **Trim the first-boot installf step:** about 130 s under emulation; two full rewrites of the 430 KB contents DB by
  APKG's installf. Register /stand/unix at install time instead, with a static installf (-R) on the medium.
- Write the final /etc/vfstab at install time; the run unit is known there. That ends the core package's s5
  placeholder that offline readers see before first boot.
- updbootpart: stamp or refuse by the vfstab unit, so a later kernel package keeps the install unit.
- The interactive picker never offers SCSI id 4 (the stock tape-id convention); decide whether the Z3660 line should.
- **Check the set's size against the root before the first pkgadd** (for 1.1, 2026-10-09; 1.0
  ships without it). Needed: the set's installed size, plus the largest package's datastream (pkgadd spools it
  under the target's /tmp), plus a margin for the contents-DB backup. Measured in cd-std-pub-r6
  (`20261009-cd-std-pub-r6d`): standard (17 packages, 60.8 MB raw) on the full disc's default plan for a 100 MB disk
  (78 MB ufs root) ran out of space in Xcore. The Xcore datastream (8,172,032 bytes) was spooling at the time, and
  the contents-DB backup needed 1658 blocks with 216 free. install.sh went on through Xbasic and olcore, then
  stopped ("base-OS install FAILED for package(s): Xcore") and left the disk unarmed. The largest datastream on the full disc is X11r5src (62,920,704 bytes).
- **Add the target's swap slice before mkfs** (re-cut). At 16 MB the miniroot panics in `mkfs_ufs` on a
  478 or 967 MB root ("swapinub: segu_fault() failed to swap in the u area", pubfull-512/1000 2026-10-09), because
  its only swap is /dev/fakeswap until section 2c, after mkfs. Parked patch with its test plan:
  the maintainer's notes (applies to `69cc46d`). 1.0 instead ships the A4000/030 config at
  64 MB (`69cc46d`).
- AmiPart (MIT RDB editor with a Linux CLI): reads our RDBs correctly, so it could serve as an independent INFO check
  in a host selftest. Its CLI cannot change a boot priority in place, and a delete/re-add drops UNIX_Boot's BootBlocks.
  Never use it to write Amix disks. See `docs/amipart-evaluation.md`.
- `CHAIN_DIR=` profile key: let a profile take the target boot chain from a directory outside `/cdrom/install`
  (today the bench R7 kit, `profiles/bench-a4000-gayle-R7row.profile`, does it with `../../r7/...` paths relative to
  `INST=/cdrom/install`). An install.sh change, so a new disc.
- **Check every medium kit in the preflight**, before the target is touched (Bench R7, 2026-10-11: `MONSW=34` on a
  disc without `/install/monsw` stopped install.sh about 2 h in; `X11KIT=rtg` without `/install/x11kit` would have
  stopped next). One check for each `$INST` kit the profile will read: monsw, x11kit, setclk, tz/MANIFEST, syslog,
  zenmac, firstboot as their keys require; updbootpart and admin always. Fail fast with the existing message; the late
  checks stay as a backstop. A silent skip would ship a Z3660 RTG box without /dev/monsw.
- **Refuse a target that is already mounted** (Bench R7: a re-run after a stop left /mnt mounted; mkfs ran under the
  live mount, then "Device busy"). The miniroot mnttab does not list it, so the check needs another probe.
- Mount the K1 source's root read-only while it installs. Today every install rewrites the source disk
  (z3660-11, 2026-10-10: 2,517 blocks, cylinder-group headers plus some file data), so a card's source images drift
  from their shipped hashes and every re-install runs on a modified source. Mapped (2026-10-11,
  the maintainer's notes): on the root only `/etc/mnttab` (install.sh's own seed line) and
  an empty `/usr/apkg/sadm/install/scripts` were added, plus metadata; the payload slice took atimes only; the
  package slice is untouched. A read-only root therefore needs a writable home for those two first (pkgadd and apkg
  open /etc/mnttab).
- firstboot §5b says "no repo host in profile (FB_REPO_HOST/FB_REPO_IP empty)" when only the address is empty (the
  public profiles by design). Say "no repo address for <host> -- skipping the hosts entry" instead.
- **A "minimal" choice on the full discs** (2026-10-11): the full CDs offer 1 standard (17
  packages), 2 everything (30), 3 custom. Add the minimal set the separate minimal discs install today (8 packages
  classic, 11 on the 060 line with X), which fits a 100 MB disk. Then 1.1 ships one CD per line (classic, 060 SD,
  060 A4092 root) and the minimal discs go. 1.0 is unchanged.
