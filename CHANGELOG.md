# Changelog

## 2026-10-27 — S4-52 (a): the RAM-disk floppy pair per line (4a95d3e, d72d173); (b) blocked on boot2's L11

tools/lib/ramdisk-media.sh: the RAM-disk media's shared staging (rd1m's tree rebuilds byte-identical). tools/build-ramdisk-floppy.sh
--line k46|k30: the pair via kbootset media --floppy (volume 2 free: k46 583 680 B, k30 782 336 B). Booting the pair (E958/E959):
boot2 v3 prints `L11 insert boot volume 2 of 2` and never takes volume 2 (13 min, no message), on either line; the control
(kerntools' N25b, boot2 v1, the same rig) takes it — a boot2 regression after 6d76671, routed to amix-dlm.

## 2026-10-27 — l11-set: catalog 61181d33 — the stage-4 exit medium rd1m 4e1f81e7 (42b204b)

kbootset -20 (dlm 1da3474, the build= gate ran on both generations), kern46m -82, z3660scsi 1.0.0-2 on the rd1k set; same images.
The CD-boot cells 9/9 and the first boots PASS on both lines (E956 k46 on -82 with z3660scsi 1.0.0-2 as the root module; E957
k30 on -17). S4-52 budget measured on real floppy pairs: the RAM-disk profile fits both lines with ~570 KiB (k46) / ~764 KiB
(k30) free on volume 2; each extra MiB of image costs ~200 KB deflated.

## 2026-10-27 — the 1.1 install path end to end: CDBOOT cells l11-rd-k46 / l11-rd-k30 PASS 9/9, first boots PASS (18693e2…ae1437c); rd1k 88d5212a

install-matrix CDBOOT mode (the disc on the A4091 CD, a blank target, an evidence floppy inserted after power-on, the interactive
operator flow with BASE.<line> by kinfo); both cells 9/9 on rd1k (catalog 92da8ce8), the installed disks first-boot to run-level 2
(E956 k46 on -81, E957 k30 on -17). Found and fixed on the way: the interview sized 1.1 disks with the 1.0 boot slice (root [159]
on 200 MB vs install.sh's 105 ceiling) — audit V now covers 1.1; the four-card label "disk e (ced0: card 1, SCSI id 6)"; modadmin -B
once per boot. tools/build-ramdisk-cd.sh is the tracked composer (stages each line, k46 ufs / k30 s5, mkstore -C); build-l11-inputs
builds amix-cdboot and the host apkg. l11-set on 92da8ce8. Note for kerntools: k30 counts illegal=2 at first boot.

## 2026-10-27 — the RAM-disk installer medium boots to the interview on both lines: rd1h 9b7348e3 (bd1baf2, 29c1da8, 1ace7d5)

miniroot: the profile runs /sbin/modadmin -B when present (the miniroot's own init reads no inittab), so the boot-class cdfs
loads. tools/build-ramdisk-miniroot.sh: the 2 MiB RAM-disk root image, s5 on k30 and ufs on k46 (s5 bus-errors on 4 KiB pages),
/sbin resolved inside the image (the stock /sbin → /bin symlink had sent modadmin to the golden box), /dev/kinfo, the boot-class
module copies, gated read-back (modadmin bytes, fakeswap b 19,0, kinfo c 53,0). l11-set: catalog 8e99705e (kern30m -16, kern46m
-81, kbootset -19, a4091 1.0.0-4). E954 (k46) and E955 (k30): `RTH1: root ramdisk (b 20,0) …, swap /dev/fakeswap, rootfstype
ufs|s5`, the install script, cdfs loaded (k46), the CD found, the interview up with BASE.<line>'s target. A full install from the
disc is not yet run. Noise: k30 -16 has cdfs built in (the boot module reports EEXIST); a4091-k30 prints "A4091 slow:" traces.

## 2026-10-27 — setup: one disc, two lines — BASE.k30 / BASE.k46 chosen by the kernel's kinfo line (926067f)

build-install-iso.sh writes /install/profiles/BASE.k30 and BASE.k46 (the first --profile of each line, by INSTALL_CPU); setup.sh
with no argument reads the running kernel's line from /dev/kinfo (KIF1 magic, the C2-1 line long) and picks BASE.<line>, falling
back to BASE (no kinfo, bad magic, no per-line file); a typed profile still overrides. uname -m cannot tell the lines apart.
Four new interview selftest cases. The RAM-disk miniroot gains the /dev/kinfo node (c 53 0); disc rd1c 578e05f3 carries it.

## 2026-10-27 — the 1.1 set moves to the RAM-disk medium's inputs, catalog cdcbff84 (ee1ca6d)

l11-set.conf: dlm 9079989, apkg abfaaac, APKG 0.3.3, APKGENG 1.12.4 (new `apkgeng-pkg` item), kbootset -18, loader-amix -8,
kern30m -14, kern46m -79, modtools -6, zeth/monsw/zrtg, ramdisk, z3660scsi, a4091 1.0.0-3, gayle, cdfs, dlmkit -11. The k46
profiles install z3660scsi as a root-class module (kern46m -79 has no static Z3660 SCSI); the bootstore gate checks a root-class
store member (crc32/sha256, lsstore, kbootset check). Floppy-booted disk-rooted cells l11-k30/l11-k46 9/9; first boots E952
(k46: z3660scsi root loaded) and E953 (k30: rooted on the WD) PASS; C4-1's §4d d1→c1x swap ran live (sdcards=4). Next: the
2 MiB s5 miniroot per line, then the CD-booted RAM-disk-rooted cell.

## 2026-10-27 — S4-58: the interview offers the upgrade install (37422a4)

On a 1.1 medium a chosen disk that holds Amix (slice 1 UNIX_Root + slice 2 UNIX_Swap; 1.1 by the store magic, s4 by UNIX_Data)
gets 1) upgrade 2) erase and install afresh 3) stop (default 1), with what is kept and not kept and /home's size measured on the
old root (LOST when it exceeds the swap slice less 1 MiB); an upgrade asks no sizes and keeps the old configuration (no dialog).
Cell l11-k46-upg-ia PASS 9/9 through the interview; selftests cover the offer's four shapes.

## 2026-10-27 — S4-54, the upgrade install's survivors (74abe1f)

The installer puts the saved configuration in place at the end of the install (from the archive's own cpio entries) and checks
every file's sum on the new root; FB_UPGRADED=y makes the first boot leave them alone (S17upgrade is a guard; no dialog on an
upgrade). The dialog's choices in package-owned files (syslog, A2024, keymap, X colour, Netnews) are kept as states and set again;
firstboot.conf kept as .prev. Password aging survives only behind setclk's plausibility gate, else cleared with a console line.
Cells l11-k46-512 and l11-k46-upg11 (1.1 → 1.1, s4 kept) added; all four upgrade cells 9/9; first boots E948/E949/E950 PASS as the
old box. Spec 40 §7 text proposed to amix-dlm.

## 2026-10-26 — public-a3000-060-wd-r6 and cell a3000-060-img: a pre-installed 1.0.1 image for an A3000 + 68060 (519d9f6) — not published

The r7 KD060-Z (68060-261021-80) rooted on the onboard WD at id 6 (c6d0s1), the standard set (17 packages, m4 for syslogd)
and the RTG X11 kit for a ZZ9000 in Zorro II mode; the first-boot dialog armed, root without a password until the dialog
sets one. Mastered with the HEAD installer on the r7 pins (carries cfcdb6a and d384553). Install cell PASS 9/9; a copy
booted on an emulated A3000/ECS + 68060 + ZZ9000_Z2 through firstboot to login and OpenLook on the RTG. Image
amix-1.0.1-a3000-060-wd.img 1,048,576,000 B sha256 74a1a00f, README and evidence in tmp/2026-10-26-a3000-060-image/.
Finding: the 060 kernels' W-D7 registers the WD only on ECS, never under AGA. Not run on real hardware.

## 2026-10-26 — C4-1, the installer's half of the four-card sd contract (f526af4, d384553, e989926)

Controller numbers c0–cf and c10–c1f (minor bit 7 for cards 2–3), host ids unit 7 of each card, the 1.1 root record's unit
N mod 8 (a real bug once the WD is ced0); a four-card kernel (its sidecar's sdcards=4, read by l11.sh) has its first boot
swap core's 256 d1 nodes for the c10–c1f nodes (removef per id / installf, pkgchk core quiet; proven on the real 2.1 sh);
the first boot names the root as the running kernel does (`/etc/devnm /`), so vfstab, swap and the atdevs gate follow the
kernel; ROOT_RECORD_DISK stays card 0 and says why; a CD-boot 1.1 disc under a four-card install kernel gets the class-order
names appended to its staged profiles (tools/sdnames.py reads sdcards from a datastream, a sidecar or a chain MANIFEST.json;
SD_BOARDS/CD_HBA in the six 1.1 profiles). Regression on the S4-55 set PASS both lines.

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
