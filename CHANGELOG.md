# Changelog

## 2026-10-21 … 2026-10-26 — r7 (1.0.1) pins and the 1.1 media with kernel modules (d180fcf..513b9c4)

r7: profiles repointed to the cut r7 kernels, cards and configs pinned (Z3660.bin 9994961A), the 1.0.1 ISOs named, notes
draft with credits. 1.1 (S2/S3 of the module campaign): the 1.1 disk layout with the kernel package and the kbootset store,
upgrade install of an installed disk (incl. the k46 line), kbootset retry and create --force (C2-4 v5/v6), updbootpart shim
and kbootset in the repair menu, mark-good from the last rc2 script, kernel-space records by pkginst (C2-2 v4), kbootset and
loader-amix as apkg packages, APKG 0.3.0 → 0.3.2 installed and gated; build-iso --cd-boot masters the A4091/A4092 bootable
CD; build-l11-inputs reads the media set from tools/l11-set.conf and says whether a CD boot tree exists. S3-31: the 1.1 media
carry kernel modules — the module kernel, modtools -5 and the module packages (z3660eth, monsw) in one apkg transaction, the
dlm inittab line checked, modules composed into the pristine generation, the stale /stand/unix removed and S01kbnamelist laid
(C2-4 v9 §12), S99zen for the z3660eth module; the bootstore gate checks modules, inittab, S99zen (bench address mapped) and
the namelist; set = kbootset -14, modtools -5, loader-amix -5, kern30m/kern46m, zeth, monsw, dlmkit -3; four s3dry2 cells PASS.

## 2026-10-14 — the 68060 matrix cells are an emulated LC060 (f1871f5)

docs/installer.md defines the 060 cells as no FPU plus trapping of unimplemented integer instructions, proven live in the
guest, and why it matters for the add-on packages.

## 1.0 — 2026-10-13 (initial public release)

The source of the amigaux 1.0 install media for Amiga UNIX (Amix) 2.1, release candidate r6e (accepted
2026-10-11). The bytes and the evidence they were accepted on: `docs/releases/1.0.md`. What users see:
`docs/release-notes-amigaux-1.0.md`.

- **Media builders:** the K1 SD card for a Z3660 with a real 68060 (installers, a ready-installed RTG desktop, a
  blank target); the 060 install CDs (the system on the Z3660 SD card, or on a disk behind an A4092); the classic
  68030 kit (boot floppy, root floppy, install CD); the full-set discs; empty target disks; emulator configs for an
  A3000 and an A4000/030 (`configs/public/`).
- **Installer:** a profile-driven driver (`src/installer/install.sh`) behind the stock-style interview
  (`src/installer/setup.sh`); package sets standard (17 packages) and everything (30); the target disk chosen at
  install; a 10 MiB boot slice at the end of the disk; the swap slice added before mkfs; a first-boot dialog for
  name, network, time zone, package repository and passwords. Package engine APKGENG 1.12.3 and APKG 0.2.3.
- **Kernels on the media:** one per driver family (KD060-Z, KD060-ZA, KD060-ZA-CD, K030-U, K030-U-FD), from the
  amix-kerntools build. The root follows the disk the machine booted from.
- **Checks:** `tools/run-checks.sh`, `tools/installer-selftest.py`, `tools/install-matrix.sh` (unattended installs
  in Amiberry, gated on attested installed-tree digests), `tools/card-audit.py`.
- **Bench network:** profiles and configs name the bench with documentation addresses (RFC 5737) and `example.net`;
  a bench maps them to its own values in `bench/local.env` (template `bench/local.env.example`).
- **RTG kit:** the published amix-z3660rtg x11 kit (KIT.sha256 `afd7068c`: startx-rtg `5ec6a2fa`, xinitrc-rtg
  `8f867980`) differs from the files on the 1.0 media (KIT.sha256 `8beaa7bf`: startx-rtg `e948dbf4`, xinitrc-rtg
  `69f6b68c`) in comments only.

Developed since 2026-06-22 in a private repository; commit ids in the docs refer to that history. The public
history starts here.
