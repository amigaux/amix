# Stage 4 — the exit ledger

80 §2 lists what stage 4 must prove: root controllers, root filesystems
and every medium of 50 (changed after the freeze, 2026-10-26). 80 §3 lists
what it must not break: every disk is named as the card-number gate of
30 §5.3 expects for its board set, and safe mode reaches a shell on every
root controller and root filesystem. This ledger gives, per line, the
bytes of record and every row's result. The stage closes in one commit,
when no cell below is empty or pending. A row's result is PASS or FAIL
with its evidence (a Bench run id), or a number for a measurement. The
plan is `docs/plan/stage-4.md`. The rows carried to stage 5 (§6) are not
cells of this ledger.

**Closed 2026-10-27.** Every cell below has its result; kabi 1.2
closes with it (§8). The exit set is catalog 6e60a128 (amix-packages
082c1cd); the exit disc is rd1n (`amix21-install-l11-rd1n.iso`,
`942bad40…`: rd1m's images on catalog 6e60a128, loader -9 inside).

## 1. The bytes of record

| What | k46 | k30 |
|---|---|---|
| kernel (root-class, no root filesystem; S4-22, S4-23, S4-43) | kern46m -82, ET_REL, 2 443 217 bytes, `435f255f…`, build `68060-261027-82`, arena 0x60000, `abi=2ab48658…`; still links ufs and s5 (`rootfs=ufs,s5`): S4-43 carried to stage 5 (T-54 item 22, decided 2026-10-27) | kern30m -17, brel, 1 637 928 bytes, `bss=352196`, `3d2e4cb6…`, build `68030-261027-17`; `unix.sym` 187 948 bytes, `16efd917…`; as k46 (`rootfs=ufs,s5`) |
| its core (`core/series`, `dlm_maximage`) | `core/series` 0001–0044 at amix-dlm 178a47b, `dlm_maximage` 256 KiB (0027) | the same |
| kinfo | version 3 (C2-1; the port's KINFO.md) | version 3 |
| kernel package | `kernel-k46-m` / `kern46m` `k46.1.2.261027-82`, `35c63353…` | `kernel-k30-m` / `kern30m` `k30.1.2.261027-17`, `9a4f469f…` |
| loader (boot2, its size under 28 672) | `loader-amix` / `ldramix` 1.0.261025-9, loader version 3, `97668df4…`; boot2 28 658 bytes, `76346d9a…` (amix-dlm ea75578) | the same |
| kbootset | -20 (`1.1.0.261027-20`), amix-dlm 1da3474, box binary `b3e7b987…` | the same |
| modadmin | modtools 1.0.261026-6 | the same |
| ABI kit (DDI 1.2, `abi=2ab48658…` from 0572fcf) | `dlmkit46` k46.1.2.261027-11, amix-dlm c2dc7fb | `dlmkit30` k30.1.2.261027-11, c2dc7fb |
| z3660scsi | `z3660scsi-k46` / `zscsi46` 1.0.0-2 (ZS-06), `e8f2dfb2…` | `z3660scsi-k30` / `zscsi30` 1.0.0-2, `551aa151…` |
| A4091/A4092 | `a4091-k46` / `a409146` 1.0.0-5, `2960e5e8…` | `a4091-k30` / `a409130` 1.0.0-5, `e8b82eab…` |
| the A4000T 53C710 | no package: S4-33 carried to stage 5 (T-54 item 22, decided 2026-10-27) | — (no A4000T on this line) |
| Gayle IDE | `gayle-k46` / `gayle46` 1.1.0-2, `d7a5323e…` | `gayle-k30` / `gayle30` 1.1.0-2, `1736b0cc…` |
| ramdisk | `ramdisk-k46` 1.0.0-1, `95897d3a…` | `ramdisk-k30` 1.0.0-1, `d12c9948…` |
| ufs | no module package: S4-40 carried to stage 5 (T-54 item 22, decided 2026-10-27) | the same |
| s5 | no module package: S4-40 carried to stage 5 (T-54 item 22, decided 2026-10-27) | the same |
| cdfs | `cdfs-k46` 1.0.0-1, `a137d914…` | `cdfs-k30` 1.0.0-1, `71b0146c…` |
| z3660eth, z3660rtg, monsw (carried from stage 3) | `zeth46` 1.0.0-5 `bed922f5…`, `zrtg46` 1.1.0-1 `c78a5a88…`, `monsw46` 1.0.0-2 `92c81b4c…` (kabi k46.1.0) | `zeth30` 1.0.0-5 `6ff59e37…`, `zrtg30` 1.1.0-1 `50419282…`, `monsw30` 1.0.0-2 `387b5e44…` (k30.1.0) |
| apkg | 0.3.3, `d45c24c0…` (`APKG-0.3.3.pkg` `2237f523…`); APKGENG 1.12.4, `4433b3a1…` | the same |
| the media of record (disk and SD images, the floppy pair, the CD, the netinstall medium) | the CD: rd1n `942bad40…` (catalog 6e60a128, loader -9; rd1m `4e1f81e7`, installng 42b204b, before it); the floppy pair k46 `97ccee45…`/`9a8dd84a…`, k30 `9b711840…`/`a8341eb1…` (installng 8ee24ec, loader -9); the netinstall medium ni6 `888ce1cd…` (installng 92c605f, both lines); disk and SD images: none of record | as k46 |

## 2. The cuts and the first media (S4-20, S4-21, S4-55)

| Row | k46 | k30 |
|---|---|---|
| S4-20 the first cut: 0027/0028, the ZS-05 static drivers | built: -61, `cb2499f1…` | built: -04, `c0f69e0a…` |
| S4-21 the second cut: four-card sd/dd, `bdevsw` row 20 free | the port's cut; first four-card runs N103r (-77, amix-kerntools a169b76) and N106 (two cards ranked, `ced0`; 1653ea3) | **PASS** — N98/N99, the K030-U cut of record (amix-dlm a15104e, `--sd-cards 4`; amix-kerntools 1079741); C4-1 proofs N94–N96 (98ae2e0) |
| S4-55 the first stage-4 media, one cell | **PASS** — N101, CD boot on the first stage-4 disc | **PASS** — N100, CD boot (`8c9c5003`) |

## 2a. The first root-class boots (S4-72-1, S4-73)

| Row | k46 | k30 |
|---|---|---|
| a root reached through a module: z3660scsi placed by boot2 (loader version 3), linked in `marc_root`, the root mounted through it | **PASS** — N103r (`tmp/2026-10-26-s4-72-1/cell-r/N103`): kern46m -77, kabi `k46.1.2`; boot2 `module z3660scsi 12988 bytes`; `kbootset status` `module z3660scsi (root): loaded`; `/` on `c6d0s1` | **PASS** — N104r (`tmp/2026-10-26-s4-73/cell-r/N104`), S4-73: kern30m -12, kabi `k30.1.2`; the same lines; z3660scsi linked at 0x081098a0 in the arena; `/` on `c6d0s1` |

The rig's own verdict on both cells reads `FAIL (b1:lifecycle)`. That is
its stale-mark check (the slot's image carried an earlier run's
`/etc/rig-lifecycle.mark`, `want 'none'`), not the row: both boots
mounted their root through the module and the second boot read back the
first's mark. The first run, N103, failed on the arena's 8-mod-16
alignment (fixed in a829c44, C3-3 version 5).

## 3. The emulator rows (S4-72; 80 §2)

| Row | k46 | k30 |
|---|---|---|
| M-SD1, one row per emulated board set of record (30 §5.3), judged against its expectation; on k46 including the no-Z3660 sets (A3000 onboard alone and + A4091/A4092 (renamed: `c6d0` → `ced0`), A4091/A4092 alone, Gayle IDE + A4091/A4092, the A4000T 53C710 alone and + A4092) | **PASS** per set run: Z3660 alone N103r (a169b76); A4091 alone N105b (d1a2e3c); Z3660 + A4091, the A4091 `ced0`, N106 (1653ea3); Gayle alone N111, Gayle + Z3660 (Gayle `ced0`) N112, the A3000 WD beside the Z3660 N113 (a12120b); the A3000 WD alone N144; the WD + A4091, the A4091 card 0 and the WD root `ced0s1`, N145; Gayle + A4091, the root `ced0s1` from the root record, N147; the A4091 alone N149r (composed on the Z3660 first, N151) (amix-kerntools 0bf0e8b); each with `kbootset check` 0 problems and `cp`/`sync`/`cmp` clean. The A4000T 53C710 sets: no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) | **PASS** per set run: WD alone N95, A4091 alone N96 (static; 98ae2e0) and N109b (module; c326ccb); Z3660 alone N104r (52ae701), N108 (c326ccb); Gayle alone N117, Gayle + Z3660 N118, the WD + Z3660 N119 (a12120b); the WD + A4091 on the module kernel N146, Gayle + A4091 N148, the A4091 alone on the module kernel N150r (N152) (amix-kerntools 0bf0e8b) |
| M-FL2 safe mode on each root controller and root filesystem | **PASS** Gayle IDE, N116 (a12120b); the Z3660 root N139 (only z3660scsi loads), the A4091 root N149r, the WD root N144 and N145, each to a shell (amix-kerntools 0bf0e8b). On the WD + A4091 safe mode drops the A4091 (the WD has no module, so it carries no `safe=1`), and the WD is card 0 there: root `c6d0s1` by the mobo record, `ced0s1` in a normal boot (spec 70 §4; S4-67) | **PASS** Gayle IDE, N122; **PASS** the Z3660 root, N134 (`amix-boot: safe mode`; z3660scsi, `safe=1`, loaded; z3660eth not; root `c6d0s1`; boot 3 normal; amix-kerntools 0bf0e8b); **PASS** the A4091 root N150r, the WD root N146 (amix-kerntools 0bf0e8b); an s5 root: no s5-rooted k30 vehicle, carried with the s5 root set (T-54 item 22, decided 2026-10-27) |
| root on ufs as a module | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| root on s5 as a module | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| cdfs as a boot-class module (C4-6 §5) | **PASS** — N114b: `mount -F cdfs 0,5 /cdrom` through the module, file sums equal the ISO's (3510a8a) | **PASS** — N120b, the first module cdfs on k30 (-17 has no static one) |
| a damaged root module selects the menu | **PASS** — N141: L3 for generations 2 and 1, `amix-boot: nothing loaded`, the menu; N140, the module alone damaged: L3 (generation 2), the pristine generation 1 (kern46m -61) boots, the fallback (amix-kerntools 0bf0e8b) | **PASS** — N136: L3 for generations 4, 2 and 1 (z3660scsi's copy and the module-less generations' kernels damaged), `amix-boot: nothing loaded`, the menu; N135, z3660scsi alone damaged: L3 (generation 4), generation 2 boots, the fallback (amix-kerntools 0bf0e8b) |
| L5 arena overflow (a backstop: gate 4 refuses first); an unmatched root entry skipped silently by the core (L7 retired, C4-4 v3) | L5 at stage 3, N67 (6960e1a); **by root modules PASS** — N143, N143b on `l5.sh` at 113b103: `L5 arena overflow (generation 3)`, generation 2 to multi-user with z3660eth loaded, then `L8 trial not confirmed (generation 3)`; **the core's silent skip PASS** — N137: a4091 and z3660scsi placed by boot2, `dlm: 1 root module(s) linked` with no line for a4091, the root `c6d0s1` (amix-kerntools 0bf0e8b) | L5 at stage 3, N68; **by root modules PASS** — N142 (`tests/bench/s4-exit/l5.sh`): `the arena needs 408246 bytes, it has 393216`, `L5 arena overflow (generation 2)`, generation 1 to multi-user; boot 2 `L8 trial not confirmed (generation 2)`; rerun N142b on 113b103: `L5 arena overflow (generation 5)`, generation 4 with z3660eth loaded and the kernel's `bss=352196`, then L8; **the core's silent skip PASS** — N132 (amix-kerntools 0bf0e8b) |
| `sd_register` after sd's first open: `EBUSY` and a console line | **PASS** — N138: the core's and the probe's lines, the probe not linked (amix-kerntools 0bf0e8b) | **PASS** — N133 (`tests/bench/s4-exit/sdlate`): `sd: sdlate registered after the controllers closed`, `sdlate: sd_register -> 16, PASS: refused after sd's first open`, the probe not linked (amix-kerntools 0bf0e8b) |
| a failed root-class `_load` leaves the kernel as it was | **PASS** — N107: the probe module's `ENXIO` in the root pass, not linked, the boot continues (1653ea3); N113, gayle's silent `ENXIO` on an A3000 (a12120b) | **PASS** — N108 (c326ccb); N119 (a12120b) |
| the deferred self-test point (S4-05): Gayle IDE leaves polled | **PASS** — N111 (kern46m -80, `intr=1`: the READ VERIFY self-test passed, 32 755 interrupts, 0 spurious); repeated over three halt and reboot cycles (N115) and in safe mode (N116); amix-kerntools a12120b | **PASS** — N117 (kern30m -15: 27 706 interrupts); N121 (halt and reboot), N122 (safe mode); a12120b |

## 4. The media (S4-50–S4-56; 50)

| Row | k46 | k30 |
|---|---|---|
| S4-50 the installer on a RAM-disk root | **PASS** — l11-rd-k46 on rd1n, 9/9 (installng 8ee24ec, cells ae1437c/39ce8aa); before it l11-rd-k46 on rd1m (`4e1f81e7`, installng 42b204b; cell code ae1437c), 9/9; first shown on rd1h, E954 | **PASS** — l11-rd-k30 on rd1n, 9/9; before it l11-rd-k30 on rd1m, 9/9; rd1h E955 |
| S4-51 M-CD1 bench half: CD boot, install and rescue on the A4091 ROM | **PASS** CD boot and install (rd1n: l11-rd-k46, first boot E956 (n46): run level 2, generation 1 by the primary loader, kernel `68060-261027-82`, ufs on `zorro:144b:01`; on rd1m l11-rd-k46, E956 (m46)); rescue from the disc: no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) | **PASS** CD boot and install (rd1n: l11-rd-k30, first boot E957 (n30): run level 2, kernel `68030-261027-17`, ufs on `mobo:a3000-wd`; on rd1m E957 (m30)); rescue: no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| S4-52 the floppy pair: M-FP1 again (fit), boot, install, rescue | M-FP1 fit: 583 680 bytes free on volume 2 (installng d72d173); boot **PASS** on loader -9 — E958 (installng 8ee24ec; pair `97ccee45…`/`9a8dd84a…`, boot2 `76346d9a…`): the RAM-disk root, the install from the rd1m CD, fsck clean, halt pass 2 modules; on -8 it hung at L11 (Kickstart 3.2.1's change counter, fixed in boot2 ea75578); install **PASS** — l11-rd-fd-k46, 9/9 (installng 39ce8aa: the CD-boot cell with the pair as boot medium, each L11 request followed from the serial port); rescue from the pair: no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) | M-FP1 fit: 782 336 bytes free; boot **PASS** on -9 — E959 (pair `9b711840…`/`a8341eb1…`), as E958; install **PASS** — l11-rd-fd-k30, 9/9 (39ce8aa); rescue from the pair: no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| S4-53 the netinstall medium: form A or B, M-NET1c, M-NET1e, M-NET1f | form B; M-NET1c: kernel -82 deflated about 739 KB, root modules about 14 KB; **M-NET1e, M-NET1f PASS** — E960 (installng fefe74e; nettest1 `2aaf8f61`, image `9546e3d3`: aen0 up, ping by address and by hosts name through libnsl netdir); **M-NET1g PASS** — ni6 (`amix21-netinstall-ni6.iso`, `888ce1cd…`, 15 032 320 bytes, boot-only, both lines, catalog 6e60a128; image ufs `cd324d68…`, 5 MiB; generation ramdisk + z3660scsi + a4091 root): l11-ni-k46 9/9, the install over HTTP from a host mirror of the staged tree, one package at a time after the catalog gate; first boot E964 (nf46b); installng e0daf78..92c605f | form B; M-NET1c: -17 about 526 KB, modules about 8 KB; **PASS** — E961 (image `9639a556`); **M-NET1g PASS** — ni6 (image s5 `e6bb9b5b…`, 5 MiB; generation ramdisk + a4091 root): l11-ni-k30 9/9; first boot E965 (nf30b) |
| S4-54 the upgrade install, from a 1.1 disk and from a 1.0 disk | **PASS** — l11-k46-upg11 (from 1.1, E948), l11-k46-upg (from 1.0, E949); installng 74abe1f, 2026-10-26, on the pre-RAM-disk discs | **PASS** — l11-k30-upg (from 1.0, E950); 74abe1f |
| S4-56 disk and SD images with rescue; tape as a package source | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| S4-57 the generic 060 target, emulated: an A3000 with a 68060, an A4091 root and a ZZ9000 in Zorro II; an A4000 with a 68060, an A4092 or Gayle IDE root and a ZZ9000 in Zorro II; each from its pre-installed image through the first-boot dialog | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27); nearest: the A3000/060 image (installng 519d9f6, `74a1a00f…`) to X on the emulated ZZ9000, the WD as root | — (a 68060 target) |

## 5. The measurements (S4-70, S4-71; 90)

| Row | k46 | k30 |
|---|---|---|
| M-MOD1 again: the root set and the arena | -82's generation needs 53 996 of the arena's 393 216 bytes; the largest composable today (every controller, cdfs promoted) about 155 KB, 40 %; 0x60000 holds (`docs/measurements/2026-10-27-m-mod1-m-fl1.md`, amix-dlm 0927aae) | 3 010 bytes less than k46; 0x60000 holds |
| M-FL1 the floor kernel's size | kern46m -82: 2 443 217 bytes (text 1 099 764, data 530 448 of which the arena 393 216, bss 71 872), ufs and s5 still in; final after S4-43, carried to stage 5 (T-54 item 22, decided 2026-10-27) (0927aae) | kern30m -17: 1 637 928 bytes + bss 352 196, 78 016 below stage 3's; as k46 |
| M-FS1 the carve and the rebuilt base | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| U3 execution from `.data` through ITT0 (mapping) | **PASS** — every k46 root-class boot runs a module's code from the arena in `.data` through ITT0: z3660scsi on N103r first (a169b76), then N105b, N106, N111 | — (U3 is the 040/060 line's, 30 §8) |
| U12 `vfssw` walkers read `nfstype` live | **PASS** — N114b: a module filesystem mounted and listed by `mount` (3510a8a); no other walker exercised | **PASS** — N120b |
| M-RD1 the shortened `memory[]` region honoured | **PASS** — N123 (kern46m -81, disc rd1h 9b7348e3 on a blank target: the image at 0x9E00000, Total memory exactly 2 MiB lower than the same machine without a RAM disk; amix-kerntools e043755; first shown by installng bd1baf2, 29c1da8, 1ace7d5) | **PASS** — N124 (kern30m -16: the image at 0x7E00000, the same 2 MiB; e043755) |
| M-RD2 the root selector: sd cards 0–3, the RAM disk, `swap none` | **PASS** for the RAM disk — N123: `RTH1: root ramdisk (b 20,0) from the loader record, swap /dev/fakeswap, rootfstype ufs`, the install script to setup's interview, `swap -l` → `/dev/fakeswap 19,0`; e043755. The sd cards 0–3: the root rows of §2a and §6 | **PASS** for the RAM disk — N124 (rootfstype s5; the same lines); e043755 |
| M-HALT1, the bench half | **PASS** — the halt pass on N103r (a169b76), N105b (d1a2e3c), N106, N107 (1653ea3), N111, N115 (three halts; a12120b) | **PASS** — N104r (52ae701), N108, N109b (c326ccb), N110 (3134e55), N117, N121 (three halts) |

## 6. The plan's rows

| Row | Status |
|---|---|
| C4-1 … C4-6 the interfaces | **agreed**, at the exit: C4-1 v3, C4-2 v5, C4-3 v3, C4-4 v5, C4-5 v10, C4-6 v4 |
| S4-01 … S4-08 the core | built (core patches 0029–0044; state harness 260/260 on both kernels); their bench halves are rows above |
| S4-10 … S4-12 loader and `kbootset` | built: S4-10 (placement), S4-11 (the RAM-disk image, 4003c9f; boot2 at the exit 28 658 bytes, ea75578), S4-12 (composition); **M-RD1/M-RD2 PASS both lines** (N123, N124; amix-kerntools e043755) |
| S4-22, S4-23 the root-class kernels | **PASS** — k46 N103r (kern46m -77, a169b76); k30 N102 (3405b11), N104r (52ae701). Without ufs and s5 (S4-43): no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| S4-24 the 1.0 families retire | **PASS** (built): the static families (kernel-k30-u, kernel-k46-z, kernel-k46-zacd) are no longer built for 1.1 from the exit; rd1n and the floppy pairs carry only kern46m and kern30m, and installng's set lists no static kernel. Their rows leave the catalog at the first stage-5 catalog (a packages mint, the 1.0 rows kept under `superseded/`), so the exit catalog stays 6e60a128 |
| S4-25 packages | every row N103–N124 installs from the served catalogs through apkg's kernel-space transactions, the gates and package sums in each row; the exit set catalog 6e60a128 |
| S4-30 … S4-34 the root-class modules | S4-30 z3660scsi: **PASS** both lines (N103r, N104r, §2a). S4-31 the A4091/A4092: **PASS** both lines (N105/N105b, N106 on k46; N109/N109b on k30; E6b on -15, N110). **S4-32 Gayle IDE: PASS** both lines in emulation (amix-kerntools a12120b: N111a–N116 on kern46m -80, N117a–N122 on kern30m -15, gayle 1.1.0-1: the IDE root alone polled and with interrupts, the k46 interrupt path's first run with the READ VERIFY self-test passing, IDE + Z3660 with the IDE as card 1, the A3000 ECS row's silent ENXIO, the ATAPI slave, halt and reboot with interrupts, safe mode); the CD check of record (`mount -F cdfs`) with gayle 1.1.0-2: **PASS** N114b (k46), N120b (k30), catalog 92da8ce8, N117b (-17 console quiet); amix-kerntools 3510a8a; metal: carried to stage 5 with the A4000D's rows (T-54 item 20). S4-33 the A4000T 53C710: no run; carried to stage 5 (T-54 item 22, decided 2026-10-27). S4-34 the ramdisk: shown (rd1h, M-RD1/M-RD2) |
| S4-40 … S4-43 the filesystems and the kernels without them | no run; carried to stage 5 (T-54 item 22, decided 2026-10-27) |
| S4-62 the DDI 1.2 DMA providers | built: k46 (0e4c34f, 01024f5), k30 (e9665e6: the pool, the bounce, the force-bounce hook). **k46 PASS**: N105/N105b, the first A4091 root-class boot (kern46m -78, a4091 1.0.0-1; `cp` and `sync` clean through `dma_alloc` memory; amix-kerntools d1a2e3c), and N106, two root modules ranked with the A4091 root as card 1 (1653ea3). **k30 PASS**: N109/N109b (E6), a4091-k30 1.0.0-3 rooted on the A4091 alone on kern30m -14, the pool at 0x7FDF800, a raw read and `cp`/`sync` identical under `dma_forcebounce` 0 and 1; the entry-0 decode read live, the identity map cacheable (C4-5 v6 §5.3); amix-kerntools c326ccb. E6b (the pool-miss path), reachable only through `dma_forcefail`: **PASS** N110 on kern30m -15 (amix-kerntools 3134e55) |
| S4-63 C3-6 §1, the register-write rule | ZS-05's armed accesses on metal: the S4-74 k46 retry, `z3660_sig_ok` 1, `sig_fails` 0, root I/O clean on the real 060 (row M8r, amix-kerntools 9cd68b5); no emulator row |
| S4-71 the root context (C4-2 §2) | the probe and its row defined (c2dc7fb, `tests/bench/s4-71`). **k46 PASS**: N107 (kern46m -78; every call at level 7 with the clock stopped, `bprobe` of a decoded address 0 and of an unheld one 1, the fault caught; amix-kerntools 1653ea3): C4-2 §2's list stands on k46. **k30 PASS**: N108 (kern30m -14; every call at level 7, the fault caught, and `dma: pool 128 KiB at 0x7FDF800` on the console; amix-kerntools c326ccb): C4-2 §2's list stands on both lines |
| S4-73 exit row | **PASS** k30 — N104r (§2a) |
| S4-74 metal: the A4000D and the cardless A4000T (root controllers, M-A4T1, M-DMA1, M-HALT1, U3's cache half, root filesystems, M-FP2, M-NET1g) | M-S474a, k46 metal (the A4000T, real 060, kern46m -81 + z3660scsi-k46 1.0.0-1): boots 1–2 PASS (loader version 3 and the zscsi root record composed on the real 060); boot 3 PANIC, the unarmed module (`swapconf lookupname /dev/dsk/c6d0s2 failed - error 20`, a stale 060 data cache; C4-2 version 4 §1.1); **M-S474a PASS** with ZS-06: generation 3 = kern46m -82 + z3660scsi-k46 1.0.0-2 composed on the box (`dlm: 1 root module(s) linked`, `RTH1: root c6d0s1 from the root record`, no swapconf panic, generation 3 good and the default, multi-user; `z3660_cache` 0x3c from `cputype`, `z3660_push_n` 7 914 at login and 2.5 M after the I/O; `cp`/`sync` twice identical, `kbootset check` 0 problems, a 32 MiB raw read twice identical, halt pass 2); L8 on metal: the loader retired the panicked generation 2 and fell back to generation 1; the first attempt is row M8 (amix-kerntools 3510a8a), the retry row M8r (9cd68b5). M-DMA1 in part and M-HALT1 on metal with it (`dlm: halt pass: 2 module(s) stopped`), the ufs root on metal. **M-S474b PASS** (k30, the A4000T's Z3660 in UAE_030_MMU, firmware golden: Z3660.bin CRC-32 9994961A, BOOT.bin 1.03 BETA 21): the static UZ bootstrap to multi-user (row M9), then the module generation kern30m -17 + z3660scsi-k30 1.0.0-2 + z3660eth-k30, composed in emulation from catalog 6e60a128 with kbootset -20 and loader -9 (N130), booted root-class with the network (row M10): 1 root module linked, 101 kernel symbols, `cp`/`sync` twice identical, the unmounted store read twice identical, `kbootset check` 0 problems, zscsi `sig_ok` 1 and every fault counter 0, kinfo `k30.1.2` build `68030-261027-17` VERDICT OK, halt pass 2 modules; amix-kerntools 9cd68b5. Known in 030 mode, carried to stage 5 (S4-65, S4-66): the Z3660 is no AutoConfig board there (kinfo card 0 `zorro:0000:00` at 0x10000000, registered through `mobo:z3660-window`), so the root record's `id=144b0100` matched no card and RTH1 fell back to the built-in `c6d0s1`, the same disk by coincidence; and with all fast memory at the Z3660's bind the 030 DMA provider finds no pool (`dma: no memory a bus master reaches`), which z3660scsi does not need. Carried to stage 5: the A4000D's rows (the box is held by the AmigaOS workspace; T-54 item 20), M-A4T1, U3's cache half, the s5 root on metal (it follows the s5 carve, item 22), M-FP2. M-NET1g is S4-53's cell (§4) |
| the build-pass arms audit (C4-2 version 4 §1.1): each module against the arms its static driver's build passes applied (the port's `f4arms`, W-D7, `sddevsize`) | **k46 done (the port, read-only): one loss, ZS-06.** `f4arms --cache` (`z3660_cache` = 60) is the only pass that writes into a driver's own global, and the only arm a module lost (z3660scsi). Carried: Model B through the kit's headers (modcheck's page-geometry scan for the static `check_page_geometry` gate), a4091's `A4091_KVA`/`A4091_D42` (D42 → the DDI DMA), Gayle's `IDE_NBPP=4096 IDE_CACHE=1`, z3660eth's and monsw's parameters; z3660rtg differs only by `ZZ9K_NO_BUILTINFONT` (a feature, routed to its repo); the kernel-side passes are in the module chain unchanged. **k30 done (the Bench, read-only): none.** The line has no `f4arms` equivalent: no pass in `cut.sh`, `build-cross-kernel.sh` or `dlm-core-link.sh` writes into a driver's own global or compiles a driver with a driver-specific flag (plain `CFLAGS_K`; the only stamp is kinfo's build id). z3660scsi: `z3660_cache` 0 static and module, right for the Z3660's emulated 030 (the dd.c ordering patch stays in every kern30m). a4091: the static driver ran without D42; the module's D42 through the core is an addition. cdfs: same sources plus `-DCDFS_MODULE`. z3660eth, z3660rtg, monsw were never static on k30. **The gayle module's polled default noted:** the static k30 driver ran interrupt-driven (`ideintr` in `int2_tbl`); the module ships `intr=0`, `param intr=1` arms INT2 through `intr_attach` and the self-test (row 1 proved it on both lines). A performance default, not a correctness loss; shipping `intr=1` on k30 is the owner's call at the 1.1 gate (T-54) |

## 7. Open at the exit (2026-10-27)

Not cells of this ledger; each is written where it is worked.
- **M11**: one black cold start on the A4000T, 2026-10-27 06:17, with no
  console line. It came before boot2's first I/O, so it was not the
  loader. Not reproduced (amix-kerntools 9cd68b5).
- **030 mode on the Z3660** (M-S474b): the root record matches no card,
  and RTH1 falls back (S4-65); there is no DMA pool for a bus master
  (S4-66).
- **A RAM-disk floppy pair in one swap** (S4-64).
- **Safe mode keeps the card numbers** (S4-67; spec 70 §4): on the WD +
  A4091 set the safe root is `c6d0s1`, `ced0s1` in a normal boot.
- **A double panic after a correct root refusal** (N149/N150): with no
  root controller, `vfs_mountroot` fails with errno 6, and the panic
  path's sync then faults in `ufs_update` (+0x58: k46 0x0807dc64, k30
  0x0707dc64). Stock code; the port's, stage 5.
- **Caught bus timeouts on an A4000 without a Z3660** (N149r/N150r): 22
  at 0x10002008–0x10002244 in a normal boot, none in safe mode. They are
  the z3660eth and z3660scsi probes of the 030-mode window; the driver
  repos make them quieter or cheaper.
- **The static kernel families' catalog rows** leave at the first stage-5
  catalog (S4-24).
- **The carries** of §8.

## 8. kabi 1.2 closes with the stage

**Closed with the stage, 2026-10-27.** The final 1.2 text is
`abi=2ab48658…` (0572fcf), carried by the re-cut of record (kern46m -82,
kern30m -17); `abi/k46/abi-k46.1.2.txt`, `abi/k30/abi-k30.1.2.txt` and
the 1.2 names of `ddi.list` are frozen from this commit. The next name
or fingerprint line is 1.3.

kabi 1.2 (k30.1.2, k46.1.2) is the stage-4 minor. **It closes when stage
4 exits**, in the exit commit: from then `abi/<line>/abi-<line>.1.2.txt`
and the 1.2 names of `ddi.list` are frozen, and any DDI name added or
fingerprint line changed after it is **1.3**. Until the exit, 1.2 takes
the stage's additions, and kernels cut on an earlier 1.2 text carry its
hash: `fea18182…` for the 1.2 cuts before 0572fcf (kern46m -77, -78;
kern30m -12, -13; the 1.1 cuts -71 and -10 had the same text), and
`2ab48658…` from 0572fcf (kern46m -79, kern30m -14 and later). A module
built for 1.2 loads on any 1.2 kernel whose symbol block has the names it
imports; the exit's re-cut of record carries the final 1.2 text.

**Carried to stage 5, not cells here (Q4-5):** S4-60, the 030 line on the
1.1 release firmware; S4-61, the A4000T's Zorro-dependent rows after its
repair (an A4092 root, CD boot on metal, the second bus), with the
A4091/A4092 module's metal and M-DMA1 rows. **Carried at the exit:** the
A4000D's metal rows (T-54 item 20), M-A4T1, U3's cache half, M-FP2; and
(T-54 item 22, decided 2026-10-27) the filesystems as modules and the kernels
without them (S4-40 … S4-43, M-FS1, the s5 root on metal), the A4000T
53C710 (S4-33), the media rows with no run (rescue from the CD and from the
floppy pair, S4-56, S4-57). With the netinstall medium: the raw RDB
image, zen0 in the miniroot, and a netinstall from a public host.
