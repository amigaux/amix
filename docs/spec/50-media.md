# 50 — Media

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §2 (disk/SD images, the floppy pair on both lines and the CD-ROM boot and install; a Linux-style netinstall medium; no boot ROM and no netboot; tape a package source only; floppies never a package source and no floppy-only install; emulation runs the same bytes as metal), D-3 §3 (the 060 floppy pair is supported), D-3 §6 (every install medium is the rescue medium)
- **Replaces:** P-28's media table rows for the CD (package source only), the 060 floppy (bench only), the module floppy (P-28 D40) and the netinstall disk image as the only network form (P-28 D47)

Paths are relative to the Amix project workspace. `MP/` =
`tmp/2026-10-22-modules-proposal/`, `IN/` = `amix-installng/`.

## 1. Common rules

- **One composer for all media.** Every medium's boot store or CD boot tree is
  produced by the host `kbootset --image` from the same package files the
  catalog serves (`40-generations-and-composer.md` §3); media and installed
  boxes cannot drift.
- **One loader.** Every bootable medium boots our boot1/boot2
  (`10-boot-loader.md`); no 1.1 medium carries the stock loader.
- **Every install medium is a rescue medium.** Booting any medium offers
  install, upgrade install and repair. Repair mounts the target and runs the
  target's own `/sbin/kbootset -R /mnt` (status, rollback, next, check); if the
  target's copy is unusable, the medium's own `kbootset` is used.
- **Hashes for kernel space.** A medium that carries packages carries the
  catalog with the SHA-256 of every kernel-space package; signing is not in
  1.1 (D-3 §13; `60-signing-and-publishing.md`).
- **Same bytes in the emulator and on metal** (§7).

## 2. Disk and SD images

| | |
|---|---|
| Forms | raw RDB images: Z3660 SD hard-file images, ZuluSCSI images, Gayle CompactFlash, real SCSI disks. Raw only; the Z3660 boots nothing from VHD (`amix-images/README.md:21-24`) |
| Products | an install image per line (the "K1" family of 1.0, `IN/docs/k1-public-card.md`); an unattended-install variant; a ready-to-run desktop image; the netinstall disk image (§5) |
| Layout | installed-disk layout of `40-generations-and-composer.md` §2.1 for ready-to-run images; install images carry a UFS miniroot slice, swap, the boot store, and the package payload (raw source slice and its catalog, as 1.0, `IN/docs/installer.md:1228-1231`) |
| Boot | Kickstart (or the Z3660's boot ROM, the A4091 ROM, Kickstart's own IDE boot) offers the `UNI\0` partition; our boot1/boot2 boot a generation from the store; root by identity (RTH1/RTO1 rule). The A4092 ROM 42.39 offers no Amix partition, so a root behind the A4092 boots from a boot-only disk on another controller carrying the root record (`grimoire-amix/docs/how-it-works/boot-process.md:204-222`) |
| Install | the installer lays the 1.1 layout, installs packages from the payload (streaming `-R`), then `kbootset -R /mnt build/commit` writes the pristine generation |
| Rescue | boot the install image, choose repair |
| Limits carried from 1.0 | filesystems under 1024 MiB (`mkfs_ufs` fails at 65 536 cylinders); the boot slice must end below 4 GiB (the loader's 32-bit offsets); a real 68060 is power-cycled, never rebooted in software (`IN/docs/releases/1.0.md:265-301`) |

## 3. The floppy pair (both lines)

| | 030 line | 040/060 line |
|---|---|---|
| Today (1.0) | published: boot ADF with the stock bootblock and loader and an LZW `brel` kernel (K030-U-FD: 1 266 585 B → 735 353 B compressed of an 890 880 B budget); root ADF = 880-block s5 miniroot with 46 free 1 KB blocks (`IN/docs/universal-bootfloppy.md:42-63`; `IN/docs/miniroot.md:105-110`) | built, not published: KD060-FD 874 819 B of 890 880 B (about 16 KB free); UFS root ADF with 63 KB free; emulator cell passed 10/10; floppy-rooted boot never run on metal (`amix-kerntools/docs/k0-families.md:871-898`; `IN/docs/miniroot.md:467-502`) |
| 1.1 | supported medium | supported medium (D-3 §3) |

**Content.** Volume 1 starts with boot1, the store header and boot2; the
store spans both volumes (`10-boot-loader.md` §4.3). The generation holds the
kernel, the root-class modules for the controllers the medium supports, and —
in the RAM-disk profile — a compressed miniroot with the installer.

**Profiles** (decided by M-FP1/M-FP2):

- *RAM-disk profile (proposed):* kernel + modules + compressed miniroot in
  the store across both volumes; root = RAM disk. Removes the floppy-rooted
  boot (untested on 060 metal) and compresses the miniroot.
- *fd0-root profile (fallback):* volume 1 = store (kernel + modules), volume 2
  = the miniroot filesystem rooted on `fd0` as in 1.0.

**Install.** The floppy pair boots the installer, which then needs a package
source: the CD, a raw source disk, the network (if the miniroot carries the
network userland, §5) or a tape (§6). Floppies are never a package source and
there is no floppy-only install (D-3 §2).

**Rescue.** Boot the pair, choose repair.

**Budget of record.** 890 880 bytes of payload per DD volume after the
1.0 prefix is the figure both 1.0 framers enforce; a second figure
(748 544 B) in the kerntools notes has no recorded origin
(`MP/CLAIMS.md` C21). Our store format changes the prefix (boot2 ≤ 28 KiB),
so the 1.1 budget is recomputed from the store layout, not inherited.

## 4. The CD-ROM

| | |
|---|---|
| Today (1.0) | ISO9660 with Rock Ridge, 2048-byte sectors, `/catalog`, `/pkgs/{stock,base}`, `/install/…`; System Identifier deliberately blank so the CD never outranks the hard disk; never a boot device — the 060 route boots an install hard-file image on the Z3660 SD and reads the CD through cdfs (`IN/docs/install-iso.md:7-33`; `MP/02-medium-cdrom-design.md:9-34`) |
| 1.1 | **bootable** (D-3 §2, §10): the boot ROM's CD filesystem boots AmigaDOS from the disc and its startup-sequence starts the loader (`10-boot-loader.md` §4.4) |
| Layout | ISO9660, System Identifier `AMIGA BOOT`; `S/Startup-Sequence` runs `amix-cdboot`; `/BOOT/K30/` and `/BOOT/K46/` hold a read-only control file and the generation files (kernel, root-class modules including cdfs and the RAM disk, compressed miniroot); `/catalog`, `/pkgs/{stock,base,kernel}` |
| Boot | ROM boots AmigaDOS from the disc → `amix-cdboot` picks the line by CPU → kernel + root-class modules + RAM-disk miniroot; cdfs (root class on this medium) mounts the disc as the package source |
| Requirement | a boot ROM with a CD filesystem (A4091, A4092); other machines boot the floppy pair and install from the CD |
| Install | packages from the disc through apkg's file source, kernel space from `/pkgs/kernel`, each checked against the catalog's SHA-256 |
| Rescue | boot the CD, choose repair. An installed disk keeps boot priority 2, which the disc's node only ties, and on the tie the disk boots. So the CD is chosen in the Kickstart early-startup menu (both mouse buttons at power-on), or by lowering the disk's priority below 2. A disc left in the drive never takes over a box |
| Other routes kept | the Z3660 ISO slot (an ISO on the SD presented as a CD unit; slot number must equal the SCSI id, `MP/02-medium-cdrom-design.md:173`); booting an install hard-file image and reading the CD (the 1.0 route) for machines whose CD sits behind a controller with no CD boot |
| Not bootable | an ATAPI CD on the Gayle IDE (no source says any Kickstart boots Amix from it; it stays a package source); a CD on a controller whose ROM offers no CD node |
| Hazards kept in the design | a second cdfs mount on an absent unit panics — probe by inquiry, then mount once (P-28 D43); a 512-byte read of a CD through the A4092 wedges the bus — only cdfs opens CD units (`MP/02-medium-cdrom-design.md:40-42`) |

The bootable profile sets `AMIGA BOOT`; an image meant to sit in a drive
while the box boots from disk keeps the System Identifier blank. The first
measurement of this medium is M-LD2.

## 5. The netinstall medium

D-3 §2: a minimal kernel plus a miniroot with the network userland and the
installer, on its own small medium; packages over HTTP from
`pkg.amigaux.org`. No boot ROM, no netboot.

| | |
|---|---|
| Content | a generation with the floor kernel (the A2065 is on the floor), the root-class modules for the medium's controllers, z3660eth as a boot-class module, and a compressed RAM-disk miniroot containing: the installer, the network userland (STREAMS link setup, `ifconfig`, `route`, `ping`), the socket and name-service libraries the HTTP client needs, apkg with its HTTP source, `kbootset`, the public key |
| Form A — floppy pair | the floppy-pair RAM-disk profile (§3) with the network miniroot, **if it fits** (M-NET1a–g, §5.1) |
| Form B — small disk image + CD image | if form A does not fit: a raw RDB image (Z3660 SD, ZuluSCSI, CompactFlash) and a small bootable ISO, both carrying the same generation |
| Network setup | address, netmask, gateway and name server asked at the interview (no DHCP client in 1.0's miniroot; a hosts-file line as fallback, P-28 D47) |
| Gate | before any disk write beyond partitioning: reach the repository and read its catalog |
| Install | `apkg -R /mnt` streaming install of the chosen set, then `kbootset -R /mnt build/commit` |
| Rescue | the same medium, repair mode, with the option to re-fetch kernel space |
| Transport figures | 37–54 KB/s on metal with the stock TCP window; the r7 kernels carry a larger window, rate to be measured; minimal set about 26 MB, full set about 300 MB (`MP/medium-network.md:76-79`) |

### 5.1 What must be measured to decide form A

The network userland is `slink` 30 516, `ifconfig` 58 700, `route` 44 140,
`ping` 21 320, `libnsl.so` 236 040, `libsocket.so` 54 032, `strcf` 2 522
bytes plus `libc.so.1` (206 876 B, the shared C library and runtime linker
every one of them names; already on both 1.0 root floppies) and the HTTP
apkg (66 736 B stripped); no static `libnsl.a` exists, so the HTTP client is
dynamic (`docs/measurements/2026-10-25-m-net1.md`). None of it fits either
1.0 root ADF (46 KB and 63 KB free). Form A therefore depends on compression
and on the RAM-disk root. Measure:

1. **M-NET1a** — the miniroot's uncompressed size with installer + network
   userland + apkg + `kbootset` + public key, per line, after stripping.
2. **M-NET1b** — its deflate-compressed size (no ratio for binaries and
   libraries is recorded; the kernel's LZW ratio is about 0.58,
   `MP/medium-floppy-design.md:77`).
3. **M-NET1c** — the compressed kernel + root-class modules per line under
   the 1.1 floor (no root filesystem or controllers linked in).
4. **M-NET1d** — the store's fixed overhead per volume (boot1, header,
   boot2 ≤ 28 KiB, control file) → usable bytes per DD volume.
5. **M-NET1e** — RAM needed at boot: kernel + arena + decompressed miniroot
   + the loader's working memory, against the smallest supported machine of
   each line.
6. **M-NET1f** — whether a single-user miniroot can run the inet STREAMS
   stack at all (U-N1; never tried, `MP/CLAIMS.md` C22) — an emulator row on a
   static kernel first.
7. **M-NET1g** — HTTP throughput and inactivity timeouts from the miniroot
   (U-N2, U-N8).

Form A ships if (1+2) + (3) + (4) fit two volumes with a margin of at least
5 % and (5) fits the smallest machine; otherwise form B.

**Result of M-NET1a/b (2026-10-25, `docs/measurements/2026-10-25-m-net1.md`).**
Against two volumes at the budget of record (2 × 890 880 = 1 781 760 B),
with the 1.0 floppy kernels deflate-compressed standing in for M-NET1c:

| Line | Installer engine | Miniroot raw (a) | Deflated (b) | + kernel | Margin |
|---|---|---|---|---|---|
| k30 | as on the 1.0 CD | 3 265 054 | 1 228 315 | 1 762 535 | +1.1 % — fails the 5 % rule |
| k30 | trimmed | 2 562 866 | 959 940 | 1 494 160 | **+16.1 %** |
| k46 | as on the 1.0 CD | 3 170 783 | 1 192 293 | 1 817 732 | −2.0 % — does not fit |
| k46 | trimmed | 2 468 595 | 924 595 | 1 550 034 | **+13.0 %** |

"Trimmed" drops the engine tools the installer never calls (`pkgchk`,
`pkgtrans`, `pkginfo`, the static no-HTTP `apkg`). **Form A — the floppy
pair with the trimmed engine — is chosen.** Not yet in the numbers and to
come out of the margin: `kbootset`, the 1.1 store overhead per volume
(M-NET1d), the netinstall additions to the installer, and the difference
between the 1.0 floppy kernels and the 1.1 floor kernel plus root modules
(M-NET1c). Form B stays the fallback if those take the margin below 5 %.

**Result of M-FP1 (static) and M-NET1d (2026-10-25,
`docs/measurements/2026-10-25-m-fp1.md`).** Real pairs written by
`mkstore -f` with the static floppy kernels and the trimmed miniroot: a pair
holds 870 400 + 899 072 usable bytes. k30 fits with 270 336 B free
(**15.3 %**) and k46 with 212 992 B free (**12.0 %**). Each deflated miniroot
is larger than one volume, so it runs on from volume 1 into volume 2
(`10-boot-loader.md` §4.3). `kbootset`, the installer's netinstall
additions and M-NET1c still come out of these margins.

**When.** D-3 §2 says the fit is "measured in S0". M-NET1a and M-NET1b are a
host computation over today's binaries and were **stage 0, the S0 freeze
condition**; they are closed (above).
M-NET1c–g cannot close in S0 — c and d depend on the 1.1 floor kernel and
the store format, e on both, f and g need a running miniroot — and are
recorded as **deviation DV-1** from D-3 §2, approved by the owner (D-3 §12):
they are confirmed in stage 1 as they exist, and if they take the margin below
5 % the netinstall medium becomes form B (`00-overview.md` §5).

## 6. Tape

| | |
|---|---|
| Role | a package source behind a boot medium (the floppy pair, a disk image, the CD); never boots (D-3 §2) |
| Today | the stock distribution tape (a cpio stream at SCSI id 4, read by the stock installer only); our installer's tape row was retired (`IN/docs/installer.md:257`); no tape built by us (`MP/tape-medium-design.md:18-21`) |
| Driver | `ct` on the floor (`70-static-floor.md`); positionless fixed-block I/O, no seek, a close mid-file spaces to the next filemark (`MP/refute-tape-seof-raw-claim.md`) |
| Format | TAPE1: 512-byte records, a filemark after each file; file 0 catalog (with the hidden kernel-space block), file 1 checksums (and the signature file once signing exists, D-3 §13), file 2 installer tools, files 3…N one package each, kernel space last (`MP/tape-medium-design.md:155-176`) |
| Reader | a sequential `tape:` source in apkg 0.3: stage every package in tape order, verify, then install |
| Devices | the tape must be reachable on an sd card with device nodes for it; new nodes for a tape on card 1 (A4092 on the 060 line) are proposed (`MP/tape-medium-design.md:146-147,180-184`) |
| Proof | emulator rows first (stock tape image, then TAPE1), then an emulated tape behind the A4092 on metal, then one real drive at a collaborator (P-28 D46) |

## 7. Emulation

| | |
|---|---|
| Rule | the emulator boots the same image files that metal boots |
| Emulator | the project's Amiberry fork: A3000 WD SCSI, A4091 with its real ROM, the A4000T onboard 53C710 model, Gayle IDE and ATAPI, the Z3660 SCSI board, A2065, SCSI tape (`MP/medium-emulation.md:7-23`; `grimoire-amix/docs/getting-started/emulation-amiberry.md`). WinUAE covers the 030 shape only |
| Z3660 boot | the fork serves the Z3660 boot ROM but leaves DIAGVALID clear, so the emulated board offers no boot node; an autoboot option advertises it but was never exercised (`MP/refute-z3660-no-boot-rom.md`). Enabling and proving it is a stage-1 prerequisite so emulator rows boot the Z3660 like metal (M-EMU1) |
| Lifecycle rows | a row that keeps one vehicle image across boots (the 1.0 matrix re-copies the vehicle, which would discard a `kbootset` write, `MP/medium-emulation.md:50`) |
| What the emulator cannot prove | interrupts from the emulated Z3660 network board, copy-back cache and DMA behaviour, 68040 bus-error frames, the HID converters (`MP/medium-emulation.md:13-23`) — those are metal rows (`90-measurements.md`) |

## 8. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-50.1 | Floppy profile: RAM-disk or fd0 root, per line (M-FP1/M-FP2). | us |
| OQ-50.2 | Narrowed by M-NET1a/b: form A (trimmed engine) chosen; confirm the margin stays ≥ 5 % once M-NET1c, M-NET1d, `kbootset` and the installer's network additions are known, else form B (§5.1). | us |
| OQ-50.3 | Whether the Z3660 firmware's floppy emulation can boot the floppy pair (no record). | us |
| OQ-50.5 | Tape device nodes on card 1 and their names. | us |
| OQ-50.6 | One real tape drive row (a collaborator's A3000 has one at SCSI id 4, `amix-040-060-port/docs/REALHW-ISSUE54-CLASSIFY-260829-07.md:74`). | Antti |
| OQ-50.7 | Whether one CD image carries both lines' generations within one ISO (proposed) or one ISO per line. | us |

## 9. Measurements

M-FP1, M-FP2, M-NET1a–g, M-LD2, M-EMU1, M-CD1, M-TAPE1…4 —
`90-measurements.md`.
