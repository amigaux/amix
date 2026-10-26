# Changelog

## 2026-10-26 — S4-55, the first stage-4 media of record (0c3cc9f) — not published before 1.1

tools/l11-set.conf moves to the current set, every row the live catalog's (9e143d53): amix-dlm 4b7eb3d, kernel-k30-m -04 /
kernel-k46-m -61 (S4-20), loader-amix -6, kbootset -15, modtools -6, z3660eth -5, monsw -2, dlmkit -5, z3660rtg 1.1.0-1,
the m4 package, APKG 0.3.2, the syslog unit fixes. Media (tmp/2026-10-26-s4-55): install ISOs k30 992e6811, k46 6eeccf55;
CD-boot discs k30 8c9c5003, k46 8062eba5 (part 3's recipe, no --bootdev). Four cells PASS 9/9 (syslog unit 4/4); first boots
on all four disks: syslogd up, conslogging 1, the namelist bound, a kernel line after S70 filed in /var/log/bus-errors.

## 2026-10-26 — 1.1 media: the m4 package, not Cdev, carries syslogd's m4 (5be4268)

The base carries the stock-derived m4 package (amix-packagemanager b70500c) instead of the whole of Cdev for
/usr/ccs/bin/m4 (ISO −10.3 MB, root −10.2 MB against the Cdev form; +28 KB against no m4); install.sh takes m4 or Cdev in a
1.1 order and dies with neither; l11-set.conf gains a `stock-pkg` item (copied into staging, recorded with its sha256 in
INPUTS); the S3-45 set's superseded kbootset -14, z3660eth -2 and monsw -1 kept as rows of record. One cell per line PASS
9/9; first boots file kernel lines in /var/log/bus-errors on both lines (E937/E938).

## 2026-10-26 — 1.1 media: syslogd now files kernel and system messages (55d8e15)

The 2.1c syslogd reads /etc/syslog.conf through /usr/ccs/bin/m4 (stock Cdev) and filed nothing without it; every 1.1 medium
now installs Cdev (+10.4 MB on the disc, +10.3 MB installed), install.sh refuses a 1.1 order without it, and the bootstore
gate checks m4 and the conf rows ("the syslog unit"). Proven on both lines: after S70 a kernel line lands in
/var/log/bus-errors and on the console in syslogd's format. 1.0: standard/full/developer/x11 carry Cdev; minimal and
060-minimal do not (unchanged). Proposed for the packagemanager: m4 as a package of its own (23 KB, no compiler forced).

## 2026-10-26 — S3-45's medium: RTG-kit 1.1 profiles and cells; booting the install CD (0f73c0b..02fe6c4)

RTG-kit 1.1 profiles (bench-a4000-z3660-060-cd-l11-rtg, bench-a3000-a4091-l11-rtg) and matrix cells l11-k46-rtg / l11-k30-rtg:
z3660eth, monsw and z3660rtg 1.1.0-1 composed into the pristine generation with the X stack (Xcore, Xbasic, olcore) and the
RTG kit (/opt/amix/bin/{Xzz9000,startx-rtg,rtg-kbdback,zz9k_monsw}, /dev/zz9000 c 49 0); the l11 set takes rows of record
for superseded packages (tools/l11-rows-record.conf). Test disks tmp/2026-10-26-s3-45 (l11-k46-rtg.hdf ecebd6f6, l11-k30-rtg
86ae863a), both cells PASS 9/9; first boots: syslogd up, conslogging 1, `modadmin -l z3660rtg` loads with monsw as its
dependency on k46, -L captures the driver's lines. Docs: booting the 1.1 install CD — the installed disk boots first.

## 2026-10-26 — S3-31 media of record; the syslog unit trusts its pid file only for a running syslogd (513b9c4, cfcdb6a)

Media of record (tmp/2026-10-26-s3-31, SHA256SUMS fff4fd0d): amix21-install-l11-k30-s3-31.iso 98a88d43, -k46- 5ed3bbea;
set = dlm c6ad5bd, packagemanager 124c329, kbootset -14, modtools -5, loader-amix -5, kern30m/kern46m, z3660eth -2,
monsw -1, dlmkit -3, APKG 0.3.2; catalog rows = amix-packages' (3305d908). Four cells PASS 9/9; the record disks' first
boots run syslogd on every boot (pid margin zero: the stale file said 87 and syslogd got 87). The syslog unit (cfcdb6a,
after the record build; rides the next cut): start trusts /etc/syslog.pid only when `ps -p` shows a syslogd, else removes
it and starts; stop kills only a syslogd and removes the file; proven on both lines' real 2.1 sh (seven cases).

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
