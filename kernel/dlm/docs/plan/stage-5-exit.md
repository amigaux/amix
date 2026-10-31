# Stage 5 — the exit ledger

80 §2 lists what stage 5 must prove: every row stage 4 carried, and every
medium of 50 built from the final packages and proven. 80 §3 lists what
it must not break: every disk named as the card-number gate of 30 §5.3
expects for its board set, safe mode included (spec 70 §4, S5-02), and
safe mode reaching a shell on every root controller and root filesystem.
This ledger gives, per line, the bytes of record and every row's result.
The stage closes in one commit, when no cell below is empty or pending.
A row's result is PASS or FAIL with its evidence (a Bench run id), or a
number for a measurement. The plan is `docs/plan/stage-5.md`.

Cells filled from 2026-10-29 on cite the Bench's run ids (N emulation, M
metal; the amix-kerntools commit that records them), the commits of the
other repositories, and the campaign record T-51 by date. A row done only in
part says which half is done and keeps the rest pending.

## 1. The bytes of record (the final packages, S5-40)

Every cell here stays pending until S5-40 freezes the 1.1 set. Where a
cell names a candidate, it is a candidate only: the catalog of record is
still fff860dc (amix-packages `build/kspace/repo/catalog.md5`), which
carries kern46m -61 and kern30m -22, and no catalog yet carries the
candidates (2026-10-31).

| What | k46 | k30 |
|---|---|---|
| kernel (no ufs and no s5; S5-10, S5-11) | pending; candidate 68060-261031-52 (the port 53ec472: unix c902f310, kabi 7f8c9ee0) | pending; candidate 68030-261031-63 (amix a0e2ab4: brel eda4dcdf, kabi fc3d99a7) |
| its core (`core/series`, `dlm_maximage`) | pending | pending |
| kernel package, with the ufs and s5 modules (S5-12) | pending; candidate kern46m k46.1.3.261031-52 (amix-packages b9edefc), in no catalog | pending; candidate kern30m k30.1.3.261031-63 (amix-packages 7854057), in no catalog |
| loader (boot2, its size under 28 672) | pending | pending |
| kbootset (S5-03, S5-15, S5-44) | pending | pending |
| modadmin (S5-03) | pending | pending |
| ABI kit (kabi 1.3, for Paula; S5-47) | pending: fff860dc carries dlmkit46 k46.1.2.261027-11, kabi 1.2; no 1.3 kit is minted | pending: dlmkit30 k30.1.2.261027-11, as k46 |
| Paula (paula46, paula30; the reason for kabi 1.3, C3-2 v2) | pending; fff860dc carries paula-k46 1.0.0-1 (kabi k46.1.3) | pending; fff860dc carries paula-k30 1.0.0-1 (kabi k30.1.3) |
| z3660scsi | pending | pending |
| A4091/A4092 | pending | pending |
| the A4000T 53C710 (S5-06) | pending | open question, not decided: fff860dc ships a4kt710-k30 1.0.0-1, but a4kt710 is unsupported in 030 mode, the A4000T's only k30 use (S5-16; 139b5b0, b7ce32b). Whether k30 ships it is open |
| Gayle IDE | pending | pending |
| ramdisk | pending | pending |
| ufs, s5 (S5-12) | pending; candidate ufs f4b9ab71 (-52); s5 — (S5-37) | pending; candidate ufs 3e2507e5, s5 1c9711b9 (-63) |
| cdfs | pending | pending |
| z3660eth, z3660rtg, monsw | pending | pending |
| apkg | pending | pending |
| the catalog of record (S5-40) | pending | the same |
| the media of record (disk and SD images, the floppy pair, the CD, the netinstall medium; S5-41) | pending | pending |

## 2. Wave 1

| Row | k46 | k30 |
|---|---|---|
| S5-01 kbootset and modadmin on cf461e3: the box build's tests | **PASS** 2026-10-27: the box build and its tests on cf461e3 (74b3e79, 4442c76); minted as kbootset -21 / modtools -7 (catalog b2a0e874) | the same |
| S5-02 safe mode keeps the card numbers: the `kbuild` host case | **PASS** 2026-10-27: the `kbuild` host case (74b3e79, 4442c76; C4-4 v6, C3-5 v13) | the same |
| S5-03 kbootset -21, modtools -7; the WD + A4091 safe boot names the root `ced0s1` | **PASS** N160, catalog 64d37aaa (2026-10-27, amix-kerntools 677c65e) | **PASS** N161 (as N160) |
| S5-04 `tools/carve.py`: the host round trip | **PASS** 2026-10-27: the port's module-only 4 KiB ufs conversion and the -66 cut (S5-11); `abi/k46/core.list` (bf10683) | **PASS** 2026-10-27: ufs and s5 wrapped as core-tier modules, round trip (d6b4381) |
| S5-05 the floppy pair in one swap: `b2medium` and a re-cut pair | **PASS** 2026-10-27: `b2medium` (28fb5a1); amix-installng's re-cut pair asks for volume 2 once (T-51 15:0x) | **PASS** as k46 |
| S5-06 the A4000T 53C710 module: host and emulation | **PASS** the root alone N162, beside the Z3660 N163, composed on a Z3660 root N162c; on an A4000 it stays out of the way N164 (2026-10-27, amix-kerntools 677c65e; k30 the same, N165c-N168) | — |
| S5-07 M-A4T1 on the A4000T, its M-SD1 sets | **PASS** but one set: a M31, b and M-DMA1 M32 (2026-10-27, amix-kerntools f01f316); c, the 710 as root, M33 FAIL (the 710 into chip memory), closed by M50 3/3 with loader-amix -10 (2026-10-28, 497f117). The A4092 beside it: pending (S5-21) | — |
| S5-08 C4-1 / C4-4: the root record of a board that is not AutoConfig'd | **agreed** 2026-10-27: C4-1 v4, by the port and amix-kerntools (4f24e59, b2b3cff) | the same |
| S5-09 a network in safe mode, opted in: a safe boot with z3660eth marked `safe` brings zen0 up; without the mark, none | host half done 2026-10-27 (484cdd2, 14cd7b9, 8eee6dd; kbootset -22); the safe boot: pending | as k46 |

## 3. Wave 2: the filesystems leave the kernel

| Row | k46 | k30 |
|---|---|---|
| S5-10, S5-11 the cuts without ufs and s5 | **PASS** 2026-10-27: -66 (the port abc6080); the packaging cuts since: -91, -50 (the core's build-id fix), -51 (the ufs mount guard), -61 (kabi 1.3); the candidates since: 68060-261030-51 (quirks 90 and 91; the port 57ade8b), 68060-261031-52 (quirk 92; 53ec472), S5-48 | **PASS** 2026-10-27: -18 (amix-kerntools afde1fd); the packaging cut -20 (224b285, N170c), then -22 (kabi 1.3); the cuts since: 68030-261030-56 (quirks 90, 91 and 74; amix fe544a2), 68030-261031-63 (quirk 92; a0e2ab4), S5-48 |
| S5-12 the kernel packages carry ufs and s5; `core.list` | **PASS** 2026-10-27: amix-packages mints -91 with ufs, round trip 197/197 (T-51 19:3x); re-minted on -50 (catalog 6f0c1701, 2026-10-28); `core.list` bf10683 | **PASS** 2026-10-27: -20 with ufs and s5, as k46; `core.list` d6b4381 |
| root on ufs as a module | **PASS** N191u on -50, candidate 6f0c1701; N191x from -91 (2026-10-28, amix-kerntools 8951642). -91 itself refused its ufs, N181u (the build id, 7b07bce) | **PASS** N180u on -20 (2026-10-28, 8951642) |
| root on s5 as a module | — (no k46 s5 module, S5-37) | **PASS** N185r (2026-10-28, 8951642) |
| a 2 KiB-block ufs on k46: mount, `mmap` and page I/O through the converted `ufs_allocmap`/`ufs_freemap` | re-scoped 2026-10-28 to "refused at mount, EINVAL, the box stays up" (plan 6c62e87): stock mkfs makes no such disk (N195k); a crafted one panicked -50 (N199p) and the static -82 alike (N199c). **PASS** as re-scoped on test cut -51, N205g (2026-10-28, amix-kerntools f7ebcbd) | — (k30 runs that disk, N199d) |
| safe mode on a ufs root and on an s5 root | **PASS** on ufs, N193s (2026-10-28, 8951642); s5: — (S5-37) | **PASS** on ufs N183s, on s5 N185r (2026-10-28, 8951642) |
| a damaged ufs module selects the menu | **PASS** N196d: the loader refuses the generation and boots the previous good one (L3, spec 10 §9); kbootset -23 then marks it bad itself, N203d (2026-10-28, 8951642, f7ebcbd) | **PASS** N186d, as k46; kbootset -23 N202d, its negative case N204m |
| S4-71's init halves: ufs and s5 in the root pass and at the first `sysinit` | **PASS** ufs, N192p (2026-10-28, 8951642) | **PASS** N182p |
| U12 with a mount of each type | **PASS** ufs, N194m; s5 refused by design (S5-37) (2026-10-28, 8951642) | **PASS** ufs and s5, N184m |
| S5-14 M-FS1 and M-FL1, final (`docs/measurements/2026-10-27-m-fs1-m-fl1.md`; re-check at the S5-15 cuts, §4; M-FS1's boot half is S5-13's) | -66: file 2 411 588, 36 634 under its control; memory 5 768 less (the carve stays zeroed in place); ufs 56 636 | -18: file 1 534 496, `bss=346388`; 109 240 bytes less than -17; ufs 56 636, s5 39 961 |
| S5-15 the 030-mode root record: `kbootset` -22 and z3660scsi | — (030 mode) | **PASS** 2026-10-27: kbootset's half 8941879, kinfo030 id 4 (amix-kerntools b747094), the port's RTH1; the record composed and read back N170c, booted on metal M34 (f01f316) |
| S5-46 a motherboard controller's record by its id: the cuts with `rth1=2`, `kbootset` -22; a Gayle root beside the Z3660 window (A4000, 030 mode) and a 53C710 root beside Gayle (A4000T) mount by the record, not the built-in root | host halves done 2026-10-27 (kbootset -22; the port's -91; amix-kerntools 224b285); the A4000T boot: pending | host halves as k46; the A4000 boot in 030 mode: pending |

## 4. Wave 3: carried metal

| Row | k46 | k30 |
|---|---|---|
| S5-16 the A4000T in 030 mode: the root record matches the window board | — | the root half **PASS** M35: gen 6 = 68030-261027-20, root `c6d0s1` by the window board's record, check 0 (2026-10-28, amix-kerntools 2f73c69). The second card: a4kt710 is unsupported in 030 mode (139b5b0); on Gayle IDE or in emulation: pending |
| S5-17 the s5 root on metal, and safe mode with it | — | **PASS** M36, multi-user, cp and sync, check clean; safe mode M37 to "The system is ready" (its check not run: no network in safe mode) (2026-10-28, 2f73c69) |
| S5-18 the 030 DMA pool with no reachable memory: C4-5, host cases | — | **PASS** host cases 2026-10-27 (2a4e4e1, 921bd93; C4-5 v11 §5.4); the metal half is S5-21's |
| S5-20 the 030 line on the release firmware: M7, z3660scsi root | — | pending (the A4000D's 030 mode still reset-loops, M19, 2026-10-27, daff4dc) |
| S5-21 the A4000T after its repair: an A4092 root, CD boot on metal, the second bus, the A4091/A4092 module's metal, M-DMA1, S5-18's metal half | pending | pending |
| S5-22 the A4000D: z3660scsi and Gayle IDE roots, cold boots, M-HALT1 | **PASS** 2026-10-27 (amix-kerntools daff4dc): z3660scsi root cold boot M14; M-HALT1 M15; Gayle IDE root M26; Gayle in interrupt mode M20-M25, three halt and cold-boot cycles M22 | pending (the D's 030 mode reset-loops, M19; with S5-20) |
| S5-23 U3's cache half; M-FP2 | pending | pending |

## 5. The media

| Row | k46 | k30 |
|---|---|---|
| S5-30 rescue from the CD and from the floppy pair | pending | pending |
| S5-31 disk and SD images with rescue; tape as a package source | pending | pending |
| S5-32 the generic 060 target, from its pre-installed images | pending, and no route: under P-35 (decided 2026-10-30, ufs the only install target) amix-installng 37fbe0e retired all eleven `PREBUILT=1` cells, which mounted an s5 root minted host-side. Whether the row becomes fresh installs on the 060 targets or keeps pre-installed images built on ufs is open | — (a 68060 target) |
| S5-33 the raw RDB image, zen0 in the miniroot, a netinstall from a public host | zen0 in the miniroot and the raw RDB image pass in emulation (amix-installng ni7, 2026-10-27; re-cut ni9 on b1f564f4, install cells 10/10, 2026-10-28); a netinstall from a public host and metal: pending | as k46 |
| S5-34 the static kernel families out of the catalog | **PASS** 2026-10-27: catalog of record b2a0e874 (amix-packages; T-51 13:5x) | the same |
| S5-44 the disk nodes of cards 2 and 3: J4's root brought to the set by `kbootset` -22's commit, `check` clean, `pkgchk core` quiet on `/dev` (the rest of core's editable files are not this row's); a fresh install on a three-controller set names the card-2 disks with no hand-made node | kbootset's half 2026-10-27 (6c82415, 4046392); amix-installng's first boot calls `kbootset nodes`, CD rd1p and ni8 leave all four cards' nodes on every installed target (T-51 22:0x). J4's root and the three-controller install: pending (Z3660 + A4092 + Gayle, J4's set). P-36 (1.1 supports clean installs only) retired the upgrade install (amix-installng dad1b57, e046859); J4's half is a 1.1 root updated by apkg, not an upgrade from 1.0, so P-36 does not retire it by itself. Whether it still runs, or the fresh three-controller install stands in for it, is open | as k46; the three-controller install: pending (a k30 set with a card 2) |
| S5-45 `kbootset media --disk --ramdisk`: the netinstall raw image's store | **PASS** 2026-10-27, host: amix eb31c79 (C2-4 v13 and C4-3 v4, d4d8f1c); host only, the box kbootset unchanged | the same |

## 6. Rows added after the plan opened

| Row | k46 | k30 |
|---|---|---|
| S5-47 the kabi-1.3 ABI kit: dlmkit46 and dlmkit30 at kabi 1.3 (abi 18c0a1c9), minted for S5-40 | pending: the kernels and Paula are kabi 1.3, the catalog of record and the media carry the 1.2 kit (c2dc7fb) | pending, as k46 |
| S5-48 the stock-defect fixes in the cuts: kzero's fault catch (quirk 90), ufs tail zeroing (quirk 91), the STREAMS freeq guard (quirk 92); on k30 also the sendsig FPU gate (quirk 74) | in the candidate 68060-261031-52 (53ec472). Metal: quirk 90 **PASS** on the A4000T's 68060, test kernel 68060-261030-50 (M51, amix-kerntools d5430cb; the port 574cea1); quirk 91 emulation only (the port ISSUE-108); quirk 92 guarded in emulation, its save not yet seen on k46 (ISSUE-109). The candidate on metal: pending | in the candidate 68030-261031-63 (a0e2ab4). Metal: quirks 90 and 91 on the A4000T in k30 mode, test kernel 68030-261030-54, qzeval 68/68 (M52, amix-kerntools d38cae5), ftx not proven; quirks 74 and 92 emulation only. The candidate on metal: pending |

S5-48 changes shipped kernel and ufs bytes, so by 80 §3 it reopens S5-41
and S5-42 for every medium that carries those kernels.

## 7. Release acceptance

| Row | k46 | k30 |
|---|---|---|
| S5-40 the final packages, one catalog | pending | the same |
| S5-41 every medium of 50 rebuilt from them | pending; reopened by S5-48's kernel and ufs bytes (80 §3) | pending, as k46 |
| S5-42 stage 4's media rows again on the rebuilt media | pending. P-35 and P-36 retired the prebuilt cells (amix-installng 37fbe0e) and the upgrade cells (dad1b57); P-36's fresh install over a 1.0 disk is l11-k46-reinstall-ia (9fb44ac). Which of stage 4's media rows remain is open | pending, as k46 |

## 8. Not cells of this ledger

S5-35 (the panic path after a failed root mount, the port) and S5-36 (the
Z3660 window probes, the driver repositories) are written where they are
worked.
