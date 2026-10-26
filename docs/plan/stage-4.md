# Stage 4 — root as a module: work breakdown

- **Status:** plan, 2026-10-26
- **Source:**
  - `docs/spec/80-stages-and-proof.md` §2 stage 4 and §3;
  - `docs/spec/30-module-core.md` §2 (patches 2, 3, 7, 8, 11 and the
    `marc_root` half of 16), §3, §5, §7, §8;
  - `docs/spec/10-boot-loader.md` §5.3–§5.4 (the arena filled, the RAM-disk
    image) and §7.4 (safe mode);
  - `docs/spec/70-static-floor.md` §4 (safe mode);
  - `docs/spec/40-generations-and-composer.md` §3.1 (gates) and §7 (the
    upgrade install);
  - `docs/spec/50-media.md` §3–§5;
  - `docs/spec/90-measurements.md`, the stage-4 rows;
  - D-3 §2–§6 (`review/D-3-kernel-modules-grill-decisions.md`).
- **Exit gate (80 §2):** the 1.0 kernel families retire; one kernel image
  per CPU line.
- **Invariant carried forward (80 §3):** every disk is named as the
  card-number gate of 30 §5.3 expects for its board set. The static root
  controllers stay buildable until stage 4 exits, as the static network and
  graphics drivers did until stage 3 exited.

Stage 3 copied modules in after root was mounted. Stage 4 mounts root
through them: the loader places the root-class modules in the arena,
`marc_root` links them in process 0 before `vfs_mountroot`, and the disk
controllers register into a four-card sd layer. Stage 4 adds:
- the core's arena load path, no-sleep mode, `sd_register`, block-device
  linkage, the halt pass and `marc_root`;
- boot2 placing root-class modules and the RAM-disk image;
- `kbootset` composing root-class members, the board set and media
  generations that root on the RAM disk;
- z3660scsi, A4091/A4092, Gayle IDE and the `ramdisk` as root-class
  modules, and the A4000T onboard 53C710 when its driver exists;
- the kernels that carry no root controller, one per line, and the
  retirement of the 1.0 families.

**Order against stage 3.** Stage 3 closed on 2026-10-26
(`stage-3-exit.md`), so every item may start. Metal rows wait for the box
hand-overs through the orchestrator and for the two carries of §2.8.

**Stage 5 work started here.** 80 §2 proves the filesystems as modules and
every medium at stage 5. This plan starts what needs only stage-4 parts:
- the ufs/s5 carve (M-FS1) and `vfs_register`, on the host (§2.6);
- the media that boot to a RAM-disk root, on the emulator (§2.7).

Their proof rows stay stage 5's: 80 §2 and 90 are unchanged (Q4-1).

## 1. Conventions

As in `stage-3.md` §1: `S4-nn` for work, `C4-n` for an interface two
repositories agree before either builds on it (the orchestrator holds the
agreement); the owner is the repository the work lands in; class `host`,
`bench` or `metal`; estimates in working sessions of one station. The
toolchain split, the upstream pin and the patch-queue shape are stage 3's.

### 1.1 Constraints from stage 3's measurements

These are measured facts, not budgets to re-derive:
- **The `marc_root` context (U1, `docs/measurements/2026-10-26-u1.md`):**
  - level 7, the clock stopped, on both lines;
  - no sleep and no `timeout`;
  - `KM_NOSLEEP` only, at most 1 MiB per request (k30 refuses 2 MiB),
    every result checked;
  - no file I/O (U15): root-class bytes come from the arena only.
- **The interrupt self-test cannot run at `marc_root`** (C3-6 v4 §1.3):
  a root-class driver stays polled until a later process-context point
  (S4-05).
- **Process-context memory (U2, U4):** a copied module gets about
  320 KiB in total on k46 at 128 MB and 640 KiB on k30 at 64 MB, and one
  request at most 256 KiB / 512 KiB. A `KM_SLEEP` request above that never
  returns.
- **The module limit (C3-1 v4 §6):** image at most 256 KiB, file under
  256 KiB. The checker enforces it now. Core patch 0027 sets
  `dlm_maximage` from the first stage-4 cut (S4-20).
- **The k30 memory cap:** K030-U runs in at most 64 MiB, and boot2 caps
  k30 there (S3-43-7).
- **The arena (M-MOD1):** 0x60000 (384 KiB) on both lines, twice the
  root set of about 191 KB (k30) and 196 KB (k46) with ufs, s5 and cdfs
  in it. Stage 5 re-derives it from the carved k46 objects.
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
| C4-1 | **`sd_register` and the four-card contract** (30 §5.2): <br>– `sd_register(queuefn, probefn, name, rankkey)`, accepted only before sd's first open, then `EBUSY`; <br>– the rank keys in the registry and the `.moddata` `rank` key; <br>– the minor encoding (card high bit = bit 7) and the names `c10`–`c1f`; <br>– the compacted order on both lines (D-3 §11); <br>– the board set recorded in the manifest | amix-040-060-port (the sd patch, the RTH1 kernel half), amix-kerntools (`sd.c.in`), amix-z3660scsi, amix-a4091, amix-gayle-ide, amix-installng (the tools that assume one hex digit) | S4-03, S4-21, S4-22, S4-30–S4-33 | 0.75 |
| C4-2 | **The root-class driver form**, a version bump of C3-6: <br>– `_load` in the `marc_root` context of §1.1; <br>– `match` and `rank` keys; <br>– polled until the deferred self-test (S4-05); <br>– `_halt` required for a board that can write memory (M-HALT1); <br>– the floor's `scsi.o` layer as the A4091's base; <br>– a checklist per driver for z3660scsi, A4091/A4092, Gayle IDE and the ramdisk | the four driver owners (amix-z3660scsi, amix-a4091, amix-gayle-ide, amix-modules) | S4-30–S4-34 | 0.75 |
| C4-3 | **The RAM-disk hand-off** (10 §5.4, 30 §7): <br>– the manifest's `ramdisk` member, `root ramdisk` and `swap none`; <br>– boot2 shortens `bootinfo.memory[]` by the image rounded to 64 KiB; <br>– the loader record's `ramdisk_addr`/`ramdisk_size` (already in `AXL1`); <br>– the root selector for block major 20 minor 0 | amix-modules (ramdisk), amix-040-060-port and amix-kerntools (the kernel half), amix-installng (the media) | S4-11, S4-21, S4-22, S4-34, S4-50 | 0.5 |
| C4-4 | **The arena filled** (C3-4, unchanged layout): <br>– selection by match key (`zorro:MMMM:PP` against the ConfigDev list, `mobo:<name>`, `always`); <br>– the flags matched / forced / safe-mode member; <br>– CRC-32 per member checked by the core; <br>– L7 when no root module matches. A version bump of C3-4 only if a field changes | the core and the loader (both amix-dlm); amix-kerntools for the sidecar | S4-04, S4-10 | 0.25 |

### 2.2 The module core (amix-dlm, `core/`)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-01 | **Patch 2, the arena load path** (`dlm_load_mem`): relocate in place from the arena, never free, no file read; the image limit of 0027 applies | amix-dlm | host | C4-4 | S4-04 | 1 |
| S4-02 | **Patch 3, no-sleep mode before process 1**: every core allocation on the root path is `KM_NOSLEEP`, at most 1 MiB, and a failure returns an error and leaves the kernel as it was (U1) | amix-dlm | host | — | S4-04 | 0.75 |
| S4-03 | **Patch 8, `sd_register`** (C4-1): the registration table, the rank sort, `EBUSY` after sd's first open with a console line; the floor's WD33C93 controllers register through the same table | amix-dlm | host | C4-1 | S4-21, S4-22, S4-30–S4-33 | 1 |
| S4-04 | **Patch 16, the `marc_root` half**: <br>– walk the arena directory in `depend` order; <br>– check each member's CRC-32 against the directory; <br>– parameters from the manifest's `param` records; <br>– in safe mode only the safe-mode members; <br>– a damaged or failing root module: a console line, and boot falls back to the menu (80 §2) | amix-dlm | host | S4-01, S4-02, C4-4 | S4-21, S4-22, S4-72 | 1.25 |
| S4-05 | **The deferred self-test point**: a core pass from the first `sysinit` entry (`MOD_C_POST`, process context, level 0) that calls each root-class module's late entry once, so it can attach its interrupt, run the self-test and leave polled mode (C3-6 v4 §1.3, Q4-2). Gayle IDE is its first user | amix-dlm | host | S4-04, C4-2 | S4-32 | 0.5 |
| S4-06 | **Patch 7, block-device linkage**: `bdevsw` rows from `.moddata` (`majors=b:<n>`), refusal of a row already owned; the ramdisk's `b 20` | amix-dlm | host | — | S4-34 | 0.75 |
| S4-07 | **Patch 11, the halt pass**: each module's `_halt`, newest first, before halt and reboot (M-HALT1); OQ-30.5's `shutdown -i0` crash on the 040/060 base checked first | amix-dlm; amix-040-060-port for OQ-30.5 | host + bench | — | S4-31, S4-71 | 0.75 |
| S4-08 | **The core's host tests**: the state harness over arena loads, the no-sleep failure paths, `sd_register` order and `EBUSY`, a CRC mismatch, safe-mode selection, the halt order | amix-dlm | host | S4-01–S4-07 | S4-20 | 1 |

### 2.3 Loader and `kbootset` (amix-dlm)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-10 | **boot2 places root-class modules** (10 §5.3): <br>– lift the refusal of a root-class member; <br>– select by match key (C4-4); <br>– write the directory and each member decompressed, 16-byte aligned; <br>– L5 on overflow, L7 when nothing matches; <br>– safe mode places only the root controller's and the root filesystem's modules (70 §4). <br>Measured against the 516 bytes before the code is written (§1.1) | amix-dlm | host + bench | C4-4 | S4-21, S4-22, S4-72 | 1.25 |
| S4-11 | **boot2 and `amix-cdboot` place the RAM-disk image** (C4-3): inflate to the top of the largest fast region, shorten `memory[]`, fill the loader record; lift the refusal of a `ramdisk` member | amix-dlm | host + bench | C4-3, S4-10 | S4-50, S4-51 | 0.75 |
| S4-12 | **`kbootset` with root-class members**: <br>– compose root-class packages into the generation; <br>– gate 3: the root disk's controller has its module (or is on the floor), and so does the root filesystem; <br>– gate 6 counts the root set against the arena; <br>– the board set recorded in the manifest, and `check` warns when the booted set differs (30 §5.2); <br>– the safe-mode flags; <br>– `media --cd/--floppy` with a `ramdisk` member, `root ramdisk`, `swap none` | amix-dlm | host | C4-1, C4-3, C4-4 | S4-72, S4-50–S4-52 | 1.5 |

### 2.4 Kernels and packages

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-20 | **The first stage-4 kernel cut, on both lines**: <br>– core patches 0027 (`dlm_maximage` 256 KiB) and 0028; <br>– the ZS-05 static drivers in the families still built: z3660scsi 9ceada6, z3660eth c5f7a46 (static objects k30 c9370806, k46 37185507). <br>It carries no stage-4 core patch. It is the kernel the first stage-4 media boot (S4-55) | amix-040-060-port (k46), amix-kerntools (k30) | host + bench | — | S4-55 | 0.75 |
| S4-21 | **The k46 root-class kernel**: <br>– `marc_root` called in `rth1_mountroot` before `rth1_apply` (30 §3); <br>– the RTH1 kernel half with four cards and the root selector: sd, RAM disk, `swap none` (M-RD2); <br>– sd and dd for four cards by the port's in-place patch (Q4-3); <br>– `bdevsw` row 20 freed for the ramdisk (Q4-4); <br>– z3660scsi, the A4091 driver and the Gayle IDE glue not linked in. <br>The port's gates pass. Offered as a merge request (80 §4) | amix-040-060-port | host + bench | C4-1, C4-3, S4-03, S4-04, S4-06 | S4-24, S4-72 | 2 |
| S4-22 | **The k30 root-class kernel**: the same from the relink kit; `sd.c.in`, dd, ct, a2091 and a2090 for four cards; the stock `ram` out of `kernel.c`; the Gayle IDE handler out of `int2_tbl`. The K030-UZ measurement kernel retires when this one roots on piscsi on the emulator | amix-kerntools | host + bench | as S4-21 | S4-24, S4-72 | 1.5 |
| S4-23 | **The 1.0 families retire**: one kernel image per line on every 1.1 medium. The static families stay buildable until the exit, then are no longer built for 1.1 | amix-kerntools, amix-040-060-port | host | S4-73 | stage exit | 0.5 |
| S4-24 | **Packages**: <br>– the root-class kernels with sidecar v2; <br>– root-class module packages for z3660scsi, A4091/A4092, Gayle IDE and ramdisk (role `module`, C3-5, class `root`); <br>– the kit with C4-2's headers (`dlmkit` next revision) | amix-packages | host | S4-21, S4-22, S4-30–S4-34 | S4-72, S4-73 | 1 |

### 2.5 Root-class modules

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-30 | **z3660scsi as a root-class module** (C4-2): rank 1; the piscsi mailbox polled and synchronous; ZS-05's armed accesses; both lines. The 030 line's metal is on the 1.1 release firmware (S4-60) | amix-z3660scsi | host + bench | C4-1, C4-2, S4-03 | S4-24 | 1 |
| S4-31 | **A4091/A4092 as a root-class module**: rank 2; on the floor's `scsi.o`; SCRIPTS polled until the deferred self-test; `_halt` stops SCRIPTS (M-HALT1); cache and DMA per line (k46 through the port's `dma_prepare`/`dma_complete`; k30 per OQ-80.5, S4-62) | amix-a4091 | host + bench | C4-1, C4-2, S4-03, S4-07 | S4-24 | 1.5 |
| S4-32 | **Gayle IDE as a root-class module**: the `mobo:gayle` positive-ID probe; rank 4; polled at `marc_root`, `intr_attach` on INT2 at the deferred point (S4-05) instead of its own interrupt-table search; the ATAPI CD as a package source (`amix-gayle-ide/docs/module-form.md`). Its IDE-rooted K030 family retires into it. The outside-module ask (80 OQ-80.4) follows our tested integration | amix-gayle-ide | host + bench | C4-1, C4-2, S4-03, S4-05 | S4-24 | 1.5 |
| S4-33 | **The A4000T onboard 53C710**, when its driver exists (80 OQ-80.2, 30 OQ-30.3): a gated `mobo` probe that never touches the window ungated (M-A4T1); rank 3. If no driver exists by the exit, stage 4 exits without it and the release notes say so | its driver's repository (none yet; Q4-7) | host + metal | C4-1, C4-2, S4-61 | — | contingent |
| S4-34 | **The `ramdisk` module** (30 §7): block major 20 (registry `b 20`); unit 0 presents the loader's image by physical address and is never allocated or freed; units 1–2 are kmem scratch disks, as the stock driver's, with requests within U4's limit; writable | amix-modules | host + bench | C4-3, S4-06 | S4-50 | 0.75 |

### 2.6 Filesystems (started here, proven in stage 5)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-40 | **M-FS1, the host half**: ufs and s5 carved from the 040/060 base object with their relocations, symbol ranges checked self-contained, the base relinked without them; Antti reviews the method (30 OQ-30.4). On the k30 line the relink kit separates them already (30 §6) | amix-dlm, amix-040-060-port | host | — | stage 5 | 2 |
| S4-41 | **Patch 9, `vfs_register` and a grown `vfssw`**: the table into `.data`, every reference retargeted, `nfstype` raised; U12's walkers listed on the host; `rootfstype` from the loader record | amix-dlm | host | — | S4-42, stage 5 | 1 |
| S4-42 | **cdfs as a demand module** on disk-rooted boxes, against the kit (69 KB image, within C3-1 §6) | amix-cdfs | host + bench | S4-41 | S4-51, stage 5 | 1 |

### 2.7 Media and the installer

The media's proof rows are stage 5's (M-CD1, M-FP1/M-FP2 again, M-NET1c–g).
Stage 4 builds them as their parts arrive and runs their bench cells.

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-50 | **The compressed miniroot on a RAM-disk root**: the installer's miniroot deflated as the `ramdisk` member; a generation with `root ramdisk` and `swap none`; the installer starts from it on the emulator, both lines (M-RD1, M-RD2) | amix-installng | bench | S4-11, S4-12, S4-34 | S4-51–S4-53 | 1 |
| S4-51 | **The CD installer**: CD-booted, RAM-disk-rooted, the successor of S3-31 part 3's disk-rooted cell (`stage-3-cd-boot.md`); cdfs, a root-class member on this medium (50 §4), mounts the disc as the package source | amix-installng | bench | S4-42, S4-50 | stage 5 (M-CD1) | 1 |
| S4-52 | **The floppy pair on both lines**: the RAM-disk profile with kernel, root modules and miniroot across both volumes (50 §3), the fd0-root profile as the fallback; installs from the CD, a source disk or tape | amix-installng | bench | S4-50 | stage 5 (M-FP1/M-FP2) | 1 |
| S4-53 | **The netinstall medium** (50 §5, D-3 §2): DV-1's margins re-measured, first against the stage-3 kernels of record, then against the root-class kernels (M-NET1c), with `kbootset` and the installer's netinstall additions; M-NET1e against the smallest machine per line; M-NET1f/g. Below a 5 % margin the medium becomes form B (D-3 §12) | amix-installng (rows by the Bench station) | host + bench | S4-50 | stage 5 | 1.5 |
| S4-54 | **The upgrade install's survivors** (40 §7, P-29, 40 OQ-40.1): the surviving set fixed from the first-boot dialog's list; captured to a checksummed archive on the swap slice, restored, verified before the first boot; from a 1.1 disk (s4 kept) and a 1.0 disk (re-laid) | amix-installng | host + bench | Q4-8 | stage 5 | 1.5 |
| S4-55 | **The first stage-4 media**: the next media cut from the stage-3 set: loader -6, kbootset -15, modtools -6, dlmkit -5, zeth -5, monsw -2, m4, and the syslog unit fixes, on S4-20's kernels; one cell per line. Not published before 1.1 (D-3 §8) | amix-installng, amix-packages | bench | S4-20 | S4-50 | 0.75 |

### 2.8 Carried from stage 3

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-60 | **The 030 line on metal, on a 1.1 release firmware** (80 OQ-80.6): the amix-main 030 work merged with the 1.0 line, built for metal. Then stage 3's M7 again (z3660eth on K030), then z3660scsi as a root-class module on the k30 kernel | Z3660 (firmware); the Bench station (rows) | metal | — | S4-74 | 2 |
| S4-61 | **The A4000T's rows after its expansion-bus repair (EAD_12/13)**: stage 3's S3-46 rows on the tower first, then its stage-4 rows (M-A4T1, the tower's board sets in M-SD1, A4091/A4092 cold boots) | the Bench station; the repair is the owner's | metal | the repair | S4-33, S4-74 | 1 |
| S4-62 | **The A4091's DMA reach on the 030 line** (80 OQ-80.5): Zorro DMA cannot reach the Z3660's DDR, and boot2 binds the kernel there. Settled before M-DMA1's A4091 rows (Q4-6) | amix-dlm; amix-a4091 | host | Q4-6 | S4-31, S4-74 | 0.75 |
| S4-63 | **The register-write rule in C3-6 §1** (80 OQ-80.7), version 5, from the proving boot's per-event table | amix-dlm | host | the proving boot | C4-2 | 0.25 |

### 2.9 Measurements and rows

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S4-70 | **Host measurements**: M-MOD1 again over the real root-class objects, and whether the arena's 0x60000 still holds; boot2's size after S4-10/S4-11; the kernels' sizes without root controllers (M-FL1, preliminary) | amix-dlm | host | S4-10, S4-11, S4-21, S4-22, S4-30–S4-34 | S4-72 | 0.5 |
| S4-71 | **Bench measurements**: U3 (execution from `.data` through ITT0, the mapping half); M-RD1; M-RD2; M-HALT1, the bench half | amix-dlm (rows by the Bench station) | bench | S4-07, S4-21, S4-22, S4-34 | S4-72 | 1 |
| S4-72 | **80's stage-4 emulator rows**: <br>– **M-SD1**: the card-number gate over every emulated board set of record (30 §5.3), each judged against its expectation; <br>– **M-FL2**: safe mode on each root controller; <br>– a damaged root module selects the menu; <br>– L5 (arena overflow) and L7 (nothing matched); <br>– `sd_register` after first open refused; <br>– a failed root-class `_load` leaves the kernel as it was | amix-dlm (rows by the Bench station) | bench | S4-04, S4-10, S4-12, S4-21, S4-22, S4-24 | S4-73 | 2 |
| S4-73 | **Exit row**: on each line, a box rooted through a root-class module on each emulated controller, installed by the installer, upgraded with apkg, rolled back, booted in safe mode; the media built with one kernel image per line | amix-dlm (rows by the Bench station) | bench | S4-72, S4-55 | S4-23, S4-74 | 1 |
| S4-74 | **Metal** (80 §2): <br>– each root controller as a module, cold boots on both boxes; <br>– **M-A4T1**, the A4000T probe gate; <br>– **M-DMA1**, cache and DMA per HBA; <br>– M-HALT1 and U3's cache half on metal; <br>– the 030 line on the 1.1 release firmware (S4-60) | amix-dlm, the driver repos (via the lab registry) | metal | S4-60, S4-61, S4-73 | stage exit | 2.5 |

## 3. Critical path and totals

`C4-1/C4-4 → S4-01/S4-02 → S4-04 → S4-10 → S4-21/S4-22 → S4-30–S4-34 →
S4-24 → S4-72 → S4-73 → S4-74`.

Feeding it in parallel:
- the first stage-4 cut and media (S4-20, S4-55), which need no stage-4
  code and start now;
- `sd_register` (S4-03) and C4-2 before the driver ports;
- the RAM-disk chain (C4-3, S4-06, S4-11, S4-34) and then the media
  cells of §2.7;
- the stage-5 work of §2.6;
- the carries of §2.8, which gate only the metal row S4-74.

The first item outside amix-dlm on the path is **S4-21** (the k46
root-class kernel, amix-040-060-port). The interfaces the other
repositories wait for are C4-1 (the kernel builders and the driver
owners) and C4-2 (the driver owners).

Estimate:
- interfaces: about 2.25 sessions;
- the core: about 7;
- loader and `kbootset`: about 3.5;
- kernels and packages: about 5.75 (other repositories);
- the root-class modules: about 4.75, plus the 53C710 if it exists;
- the stage-5 work started here: about 4;
- media and the installer: about 6.75;
- measurements and rows: about 7;
- the carries: about 4.

## 4. Open questions for the owner

One line each, with the recommendation first.

| ID | Question | Recommendation |
|---|---|---|
| Q4-1 | Do the filesystems as modules and the media proof move into stage 4, or stay stage 5's (80 §2)? | Keep 80 §2: start them here (§2.6, §2.7), prove them at stage 5; no spec change |
| Q4-2 | Where does a root-class driver run its interrupt self-test, since `marc_root` is at level 7 with the clock stopped? | A core pass at the first `sysinit` entry (S4-05), level 0; the driver is polled until then |
| Q4-3 | Do sd and dd get four cards on k46 by the port's in-place patch in stage 4, or wait for stage 5's base rebuild? | In place in stage 4, because the card-number gate is stage 4's; a merge request to the port |
| Q4-4 | The stock `ram` driver owns block major 20 in the k46 base until stage 5's rebuild. How does the ramdisk module get it? | The stage-4 k46 cut frees `bdevsw` row 20; the stock bytes leave with the rebuild |
| Q4-5 | Does stage 4's exit wait for the 030 metal on the 1.1 release firmware and for the A4000T's repair? | Yes for the firmware: one image per line cannot retire the K030 families unproven on metal (D-3 §3). Yes for the tower's controller rows, because 80 §2 names both boxes |
| Q4-6 | The A4091 on an 030 Z3660 box (80 OQ-80.5): a bounce buffer, or the kernel bound in motherboard RAM? | A DDI v1.1 DMA interface in the port's `dma_prepare`/`dma_complete` shape on both lines, whose k30 provider bounces through motherboard RAM; boot2's bind rule unchanged |
| Q4-7 | Who writes the A4000T onboard 53C710 driver, and does stage 4 exit without it? | Exit without it, with a release note (80 OQ-80.2), unless a driver exists by the tower's repair |
| Q4-8 | Does the upgrade install wait for P-29's grill? | No: fix the survivor set from the first-boot dialog's list now (40 OQ-40.1); grill P-29's conffile policy on its own, not as a stage-4 gate |
| Q4-9 | Is the first stage-4 media cut (S4-55) built now, before any root-class module exists? | Yes, as the base the root-class cells build on; nothing published before 1.1 |

## 5. Not in stage 4

- Root on ufs and s5 as modules, the 040/060 base without ufs/s5, the
  core tier's first users (stage 5; §2.6 starts the host half).
- The media proof on every medium of 50 (stage 5; §2.7 builds them).
- Signing: suspended by D-3 §13.
- The exit ledger is `stage-4-exit.md`.
