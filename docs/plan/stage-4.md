# Stage 4 — root, filesystems and media: work breakdown

- **Status:** plan, 2026-10-26; the owner's nine answers settled the same
  day (§4)
- **Source:**
  - `docs/spec/80-stages-and-proof.md` §2 stage 4 and §3 (changed after
    the freeze, 2026-10-26: the filesystems and the media's proof are
    stage 4's);
  - `docs/spec/30-module-core.md` §2 (patches 2, 3, 7, 8, 9, 11 and the
    `marc_root` half of 16), §3, §5–§8;
  - `docs/spec/10-boot-loader.md` §5.3–§5.4 (the arena filled, the RAM-disk
    image) and §7.4 (safe mode);
  - `docs/spec/70-static-floor.md` §4 (safe mode);
  - `docs/spec/40-generations-and-composer.md` §3.1 (gates) and §7 (the
    upgrade install);
  - `docs/spec/50-media.md`, every medium;
  - `docs/spec/90-measurements.md`, the stage-4 rows;
  - D-3 §2–§6 (`review/D-3-kernel-modules-grill-decisions.md`).
- **Exit gate (80 §2):** the 1.0 kernel families retire; one kernel image
  per CPU line; the kernel image contains no root filesystem; every medium
  of 50 built and proven.
- **Invariant carried forward (80 §3):** every disk is named as the
  card-number gate of 30 §5.3 expects for its board set; safe mode still
  reaches a shell on every root controller and root filesystem. The static
  root controllers and filesystems stay buildable until stage 4 exits, as
  the static network and graphics drivers did until stage 3 exited.

Stage 3 copied modules in after root was mounted. Stage 4 mounts root
through them: the loader places the root-class modules in the arena,
`marc_root` links them in process 0 before `vfs_mountroot`, the disk
controllers register into a four-card sd layer and the root filesystem
registers into a grown `vfssw`. Stage 4 adds:
- the core's arena load path, no-sleep mode, `sd_register`, block-device
  and filesystem linkage, the halt pass and `marc_root`;
- boot2 placing root-class modules and the RAM-disk image;
- `kbootset` composing root-class members, the board set and media
  generations that root on the RAM disk;
- z3660scsi, A4091/A4092, Gayle IDE, the A4000T onboard 53C710 and the
  `ramdisk` as root-class modules;
- ufs, s5 and cdfs as modules, and the kernels that carry no root
  controller and no root filesystem, one per line;
- every medium of 50 proven: disk and SD images, the floppy pair, the
  CD, the netinstall medium, the upgrade install.

**Order against stage 3.** Stage 3 closed on 2026-10-26
(`stage-3-exit.md`), so every item may start. Metal rows wait for the box
hand-overs through the orchestrator. The carries of §2.8 go to stage 5 and
do not gate this exit (Q4-5).

## 1. Conventions

As in `stage-3.md` §1: `S4-nn` for work, `C4-n` for an interface two
repositories agree before either builds on it (the orchestrator holds the
agreement); the owner is the repository the work lands in; class `host`,
`bench` or `metal`; estimates in working sessions of one station. The
toolchain split, the upstream pin and the patch-queue shape are stage 3's.
Stock code (ufs, s5, the sd layer) is built into `build/`, never tracked.

### 1.1 Constraints from stage 3's measurements

These are measured facts, not budgets to re-derive:
- **The `marc_root` context (U1, `docs/measurements/2026-10-26-u1.md`):**
  - level 7, the clock stopped, on both lines;
  - no sleep and no `timeout`;
  - `KM_NOSLEEP` only, at most 1 MiB per request (k30 refuses 2 MiB),
    every result checked;
  - no file I/O (U15): root-class bytes come from the arena only.
- **The interrupt self-test cannot run at `marc_root`** (C3-6 v4 §1.3):
  a root-class driver stays polled until the core's pass at the first
  `sysinit` entry (S4-05, Q4-2).
- **Process-context memory (U2, U4):** a copied module gets about
  320 KiB in total on k46 at 128 MB and 640 KiB on k30 at 64 MB, and one
  request at most 256 KiB / 512 KiB. A `KM_SLEEP` request above that never
  returns.
- **The module limit (C3-1 v4 §6):** image at most 256 KiB, file under
  256 KiB. The checker enforces it; core patch 0027 sets `dlm_maximage`
  in the first stage-4 cut (S4-20).
- **The k30 memory cap:** K030-U runs in at most 64 MiB, and boot2 caps
  k30 there (S3-43-7).
- **The arena (M-MOD1):** 0x60000 (384 KiB) on both lines, twice the
  root set of about 191 KB (k30) and 196 KB (k46) with ufs, s5 and cdfs
  in it. S4-70 re-derives it from the carved k46 objects.
- **boot2's room (`docs/measurements/2026-10-26-boot2-headroom.md`):**
  516 bytes left under the 28 672-byte gate. Root-class placement and the
  RAM-disk member must fit. That note's savings come in its order, and
  the gate never moves (S3-15's rule).
- **A STREAMS open runs at level 4** (C3-6 v4 §1.3).
- **Z3660 board registers (80 OQ-80.7):** back-to-back writes can land
  at two registers. z3660scsi ZS-05 (9ceada6) and z3660eth 1.0.0-5
  (c5f7a46) arm every access. The rule enters C3-6 after the proving boot
  (S4-63).

## 2. Work breakdown

### 2.1 Interfaces to agree first (drafts by amix-dlm)

| ID | Interface | Agreed with | Needed by | Est. |
|---|---|---|---|---|
| C4-1 | **`sd_register` and the four-card contract** (30 §5.2): <br>– `sd_register(queuefn, probefn, name, rankkey)`, accepted only before sd's first open, then `EBUSY`; <br>– the rank keys in the registry and the `.moddata` `rank` key; <br>– the minor encoding (card high bit = bit 7) and the names `c10`–`c1f`; <br>– the compacted order on both lines (D-3 §11); <br>– the board set recorded in the manifest | amix-040-060-port (the sd patch, the RTH1 kernel half), amix-kerntools (`sd.c.in`), amix-z3660scsi, amix-a4091, amix-gayle-ide, amix-installng (the tools that assume one hex digit) | S4-03, S4-21–S4-23, S4-30–S4-33 | 0.75 |
| C4-2 | **The root-class driver form**, its own contract beside C3-6 (`docs/contracts/C4-2-root-class-driver.md`): <br>– `_load` in the `marc_root` context of §1.1; <br>– `match` and `rank` keys; <br>– the late entry the core calls at the first `sysinit` entry (S4-05), polled until then; <br>– `_halt` required for a board that can write memory (M-HALT1); <br>– the floor's `scsi.o` layer as the 53C710 drivers' base; <br>– a checklist per driver for z3660scsi, A4091/A4092, the A4000T 53C710, Gayle IDE and the ramdisk | the driver owners (amix-z3660scsi, amix-a4091, amix-gayle-ide, amix-modules) | S4-30–S4-34 | 0.75 |
| C4-3 | **The RAM-disk hand-off** (10 §5.4, 30 §7): <br>– the manifest's `ramdisk` member, `root ramdisk` and `swap none`; <br>– boot2 shortens `bootinfo.memory[]` by the image rounded to 64 KiB; <br>– the loader record's `ramdisk_addr`/`ramdisk_size` (already in `AXL1`); <br>– the root selector for block major 20 minor 0 | amix-modules (ramdisk), amix-040-060-port and amix-kerntools (the kernel half), amix-installng (the media) | S4-11, S4-21–S4-23, S4-34, S4-50 | 0.5 |
| C4-4 | **The arena filled** (C3-4, unchanged layout): <br>– boot2 places every root record, the core evaluates `match=` (version 3); <br>– the flags placed / forced / safe-mode member, the safe set from `safe=1`; <br>– CRC-32 per member checked by the core; <br>– L7 retired. A version bump of C3-4 only if a field changes | the core and the loader (both amix-dlm); amix-kerntools for the sidecar | S4-04, S4-10 | 0.25 |
| C4-5 | **DDI v1.1, the DMA interface** (Q4-6, 80 OQ-80.5), a version bump of C3-2: the port's `dma_prepare`/`dma_complete` shape on both lines; the k46 provider is the port's; the k30 provider bounces through motherboard RAM, because Zorro DMA cannot reach the Z3660's DDR where boot2 binds the kernel; boot2's bind rule unchanged; C3-6 §1.5's "no DMA interface" lifted for v1.1 | amix-040-060-port, amix-a4091 | S4-31, S4-33, S4-62 | 0.5 |
| C4-6 | **The filesystem module form** (30 §6): `vfs_register`, the grown `vfssw` in `.data`, `nfstype` read live (U12), `rootfstype` from the loader record, the filesystem-init hook that takes s5's `inoinit` | amix-cdfs, amix-040-060-port, amix-kerntools | S4-41–S4-43 | 0.5 |

### 2.2 The module core (amix-dlm, `core/`)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-01 | **Patch 2, the arena load path** (`dlm_load_mem`): relocate in place from the arena, never free, no file read; the image limit of 0027 applies | amix-dlm | host | C4-4 | S4-04 | 1 |
| S4-02 | **Patch 3, no-sleep mode before process 1**: every core allocation on the root path is `KM_NOSLEEP`, at most 1 MiB, and a failure returns an error and leaves the kernel as it was (U1) | amix-dlm | host | — | S4-04 | 0.75 |
| S4-03 | **Patch 8, `sd_register`** (C4-1): the registration table, the rank sort, `EBUSY` after sd's first open with a console line; the floor's WD33C93 controllers register through the same table | amix-dlm | host | C4-1 | S4-22, S4-23, S4-30–S4-33 | 1 |
| S4-04 | **Patch 16, the `marc_root` half**: <br>– walk the arena directory in `depend` order; <br>– check each member's CRC-32 against the directory; <br>– parameters from the manifest's `param` records; <br>– in safe mode only the safe-mode members; <br>– a damaged or failing root module: a console line, and boot falls back to the menu (80 §2) | amix-dlm | host | S4-01, S4-02, C4-4 | S4-22, S4-23, S4-72 | 1.25 |
| S4-05 | **The deferred self-test point** (Q4-2): a core pass from the first `sysinit` entry (`MOD_C_POST`, process context, level 0) that calls each root-class module's late entry once, so it can attach its interrupt, run the self-test and leave polled mode (C3-6 v4 §1.3). Gayle IDE is its first user | amix-dlm | host | S4-04, C4-2 | S4-31–S4-33 | 0.5 |
| S4-06 | **Patch 7, block-device linkage**: `bdevsw` rows from `.moddata` (`majors=b:<n>`), refusal of a row already owned; the ramdisk's `b 20` | amix-dlm | host | — | S4-34 | 0.75 |
| S4-07 | **Patch 11, the halt pass**: each module's `_halt`, newest first, before halt and reboot (M-HALT1); OQ-30.5's `shutdown -i0` crash on the 040/060 base checked first | amix-dlm; amix-040-060-port for OQ-30.5 | host + bench | — | S4-31, S4-33, S4-71 | 0.75 |
| S4-08 | **The core's host tests**: the state harness over arena loads, the no-sleep failure paths, `sd_register` order and `EBUSY`, a CRC mismatch, safe-mode selection, the halt order, `vfs_register` | amix-dlm | host | S4-01–S4-07, S4-41 | S4-22, S4-23 | 1 |

### 2.3 Loader and `kbootset` (amix-dlm)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-10 | **boot2 places root-class modules** (10 §5.3): <br>– lift the refusal of a root-class member; <br>– place every root record (C4-4 v3), selecting none; <br>– write the directory and each member decompressed, 16-byte aligned, with its `bss=` tail; <br>– L5 on overflow; <br>– safe mode places only the `safe=1` records (70 §4). <br>Measured before the code was written: the file gate binds, 316 left (`docs/measurements/2026-10-26-boot2-headroom.md` §5) | amix-dlm | host + bench | C4-4 | S4-22, S4-23, S4-72 | 1.25 |
| S4-11 | **boot2 and `amix-cdboot` place the RAM-disk image** (C4-3): inflate to the top of the largest fast region, shorten `memory[]`, fill the loader record; lift the refusal of a `ramdisk` member | amix-dlm | host + bench | C4-3, S4-10 | S4-50, S4-51 | 0.75 |
| S4-12 | **`kbootset` with root-class members**: <br>– compose root-class packages into the generation; <br>– gate 3: the root disk's controller has its module (or is on the floor), and so does the root filesystem; <br>– gate 4 counts the whole root set (files and `bss=` tails) against the arena (C4-4 v3); <br>– `safe=1` on the safe set's records, from kinfo's card table; <br>– the board set recorded in the manifest, and `check` warns when the booted set differs (30 §5.2); <br>– the safe-mode flags; <br>– `media --cd/--floppy` with a `ramdisk` member, `root ramdisk`, `swap none` | amix-dlm | host | C4-1, C4-3, C4-4 | S4-72, S4-50–S4-52 | 1.5 |

### 2.4 Kernels and packages

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-20 | **The first stage-4 kernel cut, on both lines**: core patches 0027 (`dlm_maximage` 256 KiB) and 0028; the ZS-05 static drivers in the families still built (z3660scsi 9ceada6, z3660eth c5f7a46). No stage-4 core patch. **Done**: k30 -04 `c0f69e0a…`, k46 -61 `cb2499f1…` | amix-040-060-port (k46), amix-kerntools (k30) | host + bench | — | S4-55 | done |
| S4-21 | **The second stage-4 cut**: <br>– four-card sd and dd naming (C4-1's minor encoding, the names `c10`–`c1f`): on k46 by the port's in-place patch, now (Q4-3), as a merge request to the port; on k30 `sd.c.in`, dd, ct, a2091 and a2090 for four cards; <br>– the RTH1 kernel half over four cards; <br>– `bdevsw` row 20 freed: the stock `ram` entry out of the switch on k46, its bytes left until S4-43's rebuild (Q4-4); the stock `ram` out of `kernel.c` on k30; <br>– the stage-4 core patches landed by then | amix-040-060-port (k46), amix-kerntools (k30) | host + bench | C4-1 | S4-22, S4-23, S4-34 | 1.25 |
| S4-22 | **The k46 root-class kernel**: <br>– `marc_root` called in `rth1_mountroot` before `rth1_apply` (30 §3); <br>– the root selector: sd, RAM disk, `swap none` (M-RD2); <br>– z3660scsi, the A4091 driver and the Gayle IDE glue not linked in. <br>The port's gates pass. Offered as a merge request (80 §4) | amix-040-060-port | host + bench | C4-3, S4-03, S4-04, S4-06, S4-08, S4-10, S4-21 | S4-25, S4-43, S4-72 | 1.5 |
| S4-23 | **The k30 root-class kernel**: the same from the relink kit; the Gayle IDE handler out of `int2_tbl`. The K030-UZ measurement kernel retires when this one roots on piscsi on the emulator | amix-kerntools | host + bench | as S4-22 | S4-25, S4-43, S4-72 | 1.25 |
| S4-24 | **The 1.0 families retire**: one kernel image per line on every 1.1 medium. The static families stay buildable until the exit, then are no longer built for 1.1 | amix-kerntools, amix-040-060-port | host | S4-73 | stage exit | 0.5 |
| S4-25 | **Packages**: <br>– the root-class kernels with sidecar v2; <br>– root-class module packages for z3660scsi, A4091/A4092, the A4000T 53C710, Gayle IDE, ramdisk, ufs, s5 and cdfs (role `module`, C3-5); <br>– the kit with C4-2's, C4-5's and C4-6's headers (`dlmkit` next revision) | amix-packages | host | S4-22, S4-23, S4-30–S4-34, S4-42, S4-43 | S4-72, S4-73 | 1.25 |

### 2.5 Root-class modules

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-30 | **z3660scsi as a root-class module** (C4-2): rank 1; the piscsi mailbox polled and synchronous; ZS-05's armed accesses; both lines. The 030 line's metal is on the 1.1 release firmware (S4-60, carried) | amix-z3660scsi | host + bench | C4-1, C4-2, S4-03 | S4-25 | 1 |
| S4-31 | **A4091/A4092 as a root-class module**: rank 2; on the floor's `scsi.o`; SCRIPTS polled until the deferred self-test (S4-05); `_halt` stops SCRIPTS (M-HALT1); cache and DMA through DDI v1.1 (C4-5) on both lines | amix-a4091 | host + bench | C4-1, C4-2, C4-5, S4-03, S4-05, S4-07 | S4-25 | 1.5 |
| S4-32 | **Gayle IDE as a root-class module**: the `mobo:gayle` positive-ID probe; rank 4; polled at `marc_root`, `intr_attach` on INT2 at the deferred point (S4-05) instead of its own interrupt-table search; the ATAPI CD as a package source (`amix-gayle-ide/docs/module-form.md`). Its IDE-rooted K030 family retires into it. The outside-module ask (80 OQ-80.4) follows our tested integration | amix-gayle-ide | host + bench | C4-1, C4-2, S4-03, S4-05 | S4-25 | 1.5 |
| S4-33 | **The A4000T onboard 53C710 driver, written in stage 4** (Q4-7, 80 OQ-80.2): the A4091 driver's chip code re-targeted, as a second target in amix-a4091 (Q4-7); the gated `mobo` probe that never touches the window ungated (M-A4T1); rank 3; on the floor's `scsi.o`; DMA through C4-5; `_halt` stops SCRIPTS. It is the cardless tower's only SCSI root path | amix-a4091 (confirmed, 2026-10-26) | host + bench (where the emulator models the controller) + metal | C4-1, C4-2, C4-5, S4-03, S4-05, S4-07 | S4-25, S4-74 | 2 |
| S4-34 | **The `ramdisk` module** (30 §7): block major 20 (registry `b 20`); unit 0 presents the loader's image by physical address and is never allocated or freed; units 1–2 are kmem scratch disks, as the stock driver's, with requests within U4's limit; writable | amix-modules | host + bench | C4-3, S4-06, S4-21 | S4-25, S4-50 | 0.75 |

### 2.6 Filesystems as modules

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-40 | **M-FS1, the carve**: ufs and s5 carved from the 040/060 base object with their relocations, symbol ranges checked self-contained; on the k30 line the relink kit separates them (30 §6); Antti reviews the method (30 OQ-30.4) | amix-dlm (the carve tool), amix-040-060-port | host | C4-6 | S4-43 | 2 |
| S4-41 | **Patch 9, `vfs_register` and a grown `vfssw`** (C4-6): the table into `.data`, every reference retargeted, `nfstype` raised; U12's walkers listed on the host; `rootfstype` from the loader record | amix-dlm | host | C4-6 | S4-08, S4-42, S4-43 | 1 |
| S4-42 | **cdfs as a module**: demand class on disk-rooted boxes, root class on the CD (50 §4), against the kit (69 KB image, within C3-1 §6) | amix-cdfs | host + bench | S4-41 | S4-25, S4-51 | 1 |
| S4-43 | **The kernels without root filesystems**: the 040/060 base relinked without ufs, s5 and the stock `ram` bytes (Q4-4), passing the port's gates; the k30 kernel without ufs, s5 and `ram`; the ufs and s5 modules per line, s5 filling the filesystem-init hook | amix-040-060-port (k46), amix-kerntools (k30) | host + bench | S4-22, S4-23, S4-40, S4-41 | S4-25, S4-72 | 2 |

### 2.7 Media and the installer

Every medium of 50 is proven in stage 4 (Q4-1): M-CD1 (its A4092 metal
half is carried, §2.8), M-FP1 and M-FP2 again, M-NET1c–g, and the rescue
on each.

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-50 | **The compressed miniroot on a RAM-disk root**: the installer's miniroot deflated as the `ramdisk` member; a generation with `root ramdisk` and `swap none`; the installer starts from it on the emulator, both lines (M-RD1, M-RD2) | amix-installng | bench | S4-11, S4-12, S4-34 | S4-51–S4-53 | 1 |
| S4-51 | **The CD installer** (M-CD1, bench half): CD-booted, RAM-disk-rooted, the successor of S3-31 part 3's disk-rooted cell (`stage-3-cd-boot.md`); cdfs, root class on this medium, mounts the disc as the package source; install and rescue from the disc | amix-installng | bench | S4-42, S4-50 | S4-73 | 1 |
| S4-52 | **The floppy pair on both lines** (M-FP1 again, M-FP2): the RAM-disk profile with kernel, root modules and miniroot across both volumes (50 §3), the fd0-root profile as the fallback; installs from the CD, a source disk or tape; the metal boot on both lines | amix-installng (metal rows by the Bench station) | bench + metal | S4-50 | S4-73, S4-74 | 1.25 |
| S4-53 | **The netinstall medium** (50 §5, D-3 §2): DV-1's margins re-measured, first against the stage-3 kernels of record, then against the root-class kernels without root filesystems (M-NET1c), with `kbootset` and the installer's netinstall additions; M-NET1e against the smallest machine per line; M-NET1f again; M-NET1g on metal. Below a 5 % margin the medium becomes form B (D-3 §12) | amix-installng (rows by the Bench station) | host + bench + metal | S4-50 | S4-73, S4-74 | 1.75 |
| S4-54 | **The upgrade install's survivors** (40 §7, 40 OQ-40.1; Q4-8): the known set from the first-boot dialog's list; captured to a checksummed archive on the swap slice, restored, verified before the first boot; from a 1.1 disk (s4 kept) and a 1.0 disk (re-laid). P-29's conffile policy is grilled separately and gates nothing here | amix-installng | host + bench | — | S4-73 | 1.5 |
| S4-55 | **The first stage-4 media** (Q4-9): the next media cut from the stage-3 set (loader -6, kbootset -15, modtools -6, dlmkit -5, zeth -5, monsw -2, m4, the syslog unit fixes) on S4-20's kernels, and the CD discs; one cell per line. In progress (catalog `9e143d53…`). Not published before 1.1 (D-3 §8) | amix-installng, amix-packages | bench | S4-20 | S4-50 | 0.75 |
| S4-56 | **Disk and SD images, and tape** (50 §2, §6): the installed images built from the root-class kernels and modules, with rescue; tape as a package source behind a boot medium (M-TAPE1–4 carried from stage 2) | amix-installng | bench | S4-25, S4-54 | S4-73 | 0.75 |

### 2.8 Carried to stage 5 (Q4-5)

These do not gate stage 4's exit. They wait for the owner's repair and
firmware sessions, and stage 5 proves them (80 §2).

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-60 | **The 030 line on metal, on a 1.1 release firmware** (80 OQ-80.6): the amix-main 030 work merged with the 1.0 line, built for metal. Then stage 3's M7 again (z3660eth on K030), then z3660scsi as a root-class module on the k30 kernel | Z3660 (firmware); the Bench station (rows) | metal | the owner's firmware session | stage 5 | 2 |
| S4-61 | **The A4000T's Zorro-dependent rows, after its expansion-bus repair (EAD_12/13)**: an A4092 root on the tower, CD boot on metal (M-CD1's metal half), the second bus; and the A4091/A4092 root module's metal and its M-DMA1 on any box with a working Zorro bus (the tower after its repair, or a negotiated A4000D window; Amix, 2026-10-26). The module itself is proven on the emulator in stage 4 (S4-31). The tower's cardless rows are stage 4's (S4-74) | the Bench station; the repair is the owner's | metal | the repair | stage 5 | 1 |

### 2.9 Other carries and the C3-6 rule

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-62 | **The DDI v1.1 DMA providers** (C4-5): the k46 provider over the port's `dma_prepare`/`dma_complete`, the k30 provider bouncing through motherboard RAM; the core's host tests over both | amix-dlm (`core/plat/`) | host + bench | C4-5 | S4-31, S4-33 | 1 |
| S4-63 | **The register-write rule in C3-6 §1** (80 OQ-80.7), version 5, from the proving boot's per-event table | amix-dlm | host | the proving boot | C4-2 | 0.25 |

### 2.10 Measurements and rows

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-70 | **Host measurements**: M-MOD1 again over the real root-class objects, and whether the arena's 0x60000 still holds; boot2's size after S4-10/S4-11; **M-FL1**, the floor kernel size per line | amix-dlm | host | S4-10, S4-11, S4-30–S4-34, S4-43 | S4-72 | 0.5 |
| S4-71 | **Bench measurements**: U3 (execution from `.data` through ITT0, the mapping half); M-RD1; M-RD2; U12 on the box; M-HALT1, the bench half; the root context: `autocon`, `bprobe`, `sptalloc`/`sptfree` and on k46 `dev_kvmap` return at level 7 with the clock stopped, on both lines, from a root-class probe module (C4-2 §2) | amix-dlm (rows by the Bench station) | bench | S4-07, S4-22, S4-23, S4-34, S4-43 | S4-72 | 1 |
| S4-72 | **80's stage-4 emulator rows**: <br>– **M-SD1**: the card-number gate over every emulated board set of record (30 §5.3), each judged against its expectation; <br>– **M-FL2**: safe mode on each root controller and root filesystem; <br>– root on ufs and on s5 as modules; cdfs as a demand module; <br>– a damaged root module selects the menu; <br>– L5 (arena overflow) and an unmatched entry skipped by the core; <br>– `sd_register` after first open refused; <br>– a failed root-class `_load` leaves the kernel as it was | amix-dlm (rows by the Bench station) | bench | S4-04, S4-10, S4-12, S4-22, S4-23, S4-25, S4-43 | S4-73 | 2.5 |
| S4-73 | **Exit row**: on each line, a box rooted through a root-class controller module and a root filesystem module on each emulated controller, installed by the installer, upgraded with apkg, rolled back, booted in safe mode; every medium of §2.7 built with one kernel image per line, booted, installed from and rescued with | amix-dlm (rows by the Bench station) | bench | S4-72, S4-51–S4-56 | S4-24, S4-74 | 1.5 |
| S4-74 | **Metal** (80 §2), on the boxes as they are: <br>– the A4000D: z3660scsi and Gayle IDE roots as modules, cold boots; <br>– the cardless A4000T (Q4-5): z3660scsi, the onboard 53C710 (S4-33) and Gayle IDE roots, cold boots; **M-A4T1**; <br>– **M-DMA1**, cache and DMA per HBA on those boxes; <br>– M-HALT1 and U3's cache half; <br>– root filesystem modules on both boxes; <br>– the floppy pair (M-FP2) and the netinstall medium (M-NET1g) on metal | amix-dlm, the driver repos (via the lab registry; the A4000D in a window negotiated with its holder) | metal | S4-52, S4-53, S4-73 | stage exit | 2.5 |

## 3. Critical path and totals

`C4-1/C4-4 → S4-01/S4-02 → S4-04 → S4-08 → S4-22/S4-23 → S4-43 →
S4-25 → S4-72 → S4-73 → S4-74`.

Feeding it in parallel:
- the first stage-4 media (S4-55), on S4-20's kernels, now;
- boot2's placement (S4-10, S4-11) and `kbootset` (S4-12);
- the root-class modules (S4-30–S4-34) before the packages (S4-25);
- C4-6, S4-41 and S4-40 before S4-43, the kernels without root
  filesystems;
- `sd_register` (S4-03), C4-2 and C4-5 before the driver ports;
- the RAM-disk chain (C4-3, S4-06, S4-11, S4-34) and then the media
  rows of §2.7;
- the second cut (S4-21), which needs only C4-1.

The first items outside amix-dlm on the path are **S4-21** and **S4-22**
(the port's in-place four-card patch and the k46 root-class kernel). The
interfaces the other repositories wait for are C4-1 (the kernel builders
and the driver owners), C4-2 and C4-5 (the driver owners) and C4-6
(cdfs and the kernel builders).

Estimate:
- interfaces: about 3.25 sessions;
- the core: about 7;
- loader and `kbootset`: about 3.5;
- kernels and packages: about 5.75 (other repositories);
- the root-class modules: about 6.75 (driver repositories);
- filesystems: about 6;
- media and the installer: about 8;
- measurements and rows: about 8;
- the DMA providers and the C3-6 rule: about 1.25;
- carried to stage 5: about 3.

## 4. Decisions (the owner, 2026-10-26)

| ID | Decision |
|---|---|
| Q4-1 | **Pull in:** the root filesystems (ufs, s5, cdfs as modules) and the proof of every install medium are stage 4's; stage 4 exits on root controllers, filesystems and every medium proven (80 §2 changed after the freeze) |
| Q4-2 | **A core pass at the first `sysinit` entry**, level 0, runs root-class drivers' interrupt self-tests; they are polled until then (S4-05) |
| Q4-3 | **The k46 four-card sd/dd naming in place now**, as a merge request to the port (S4-21) |
| Q4-4 | **The stage-4 cut frees `bdevsw` row 20**: the stock `ram` entry leaves the switch, its bytes leave with the base rebuild (S4-21, S4-43) |
| Q4-5 | **Do not wait:** the tower runs stage 4's cardless rows as it is; its Zorro-dependent rows (an A4092 root, CD boot on metal, the second bus) and the 030 metal on the release firmware carry to stage 5, and stage 4 exits without them (§2.8) |
| Q4-6 | **DDI v1.1 DMA** in the port's `dma_prepare`/`dma_complete` shape, the 030 provider bouncing through motherboard RAM (C4-5, S4-62) |
| Q4-7 | **Write the A4000T onboard 53C710 driver in stage 4** as a normal row (S4-33). Home: amix-a4091 (confirmed by the orchestrator), as a second target of its driver, because the chip, the SCRIPTS and the gotcha catalogue are shared and only the probe, window, interrupt and clock differ (M-MOD1 already sizes it as the A4091 driver) |
| Q4-8 | **Proceed** with the known survivor set (the first-boot dialog's list); P-29's conffile policy is grilled separately (S4-54) |
| Q4-9 | **Yes:** the first stage-4 media build now (S4-55) |

## 5. Not in stage 4

- The carried rows of §2.8 (stage 5).
- Stage 5's acceptance: every medium rebuilt from the final packages and
  proven again (80 §2).
- Signing: suspended by D-3 §13.
- The exit ledger is `stage-4-exit.md`.
