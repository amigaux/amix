# Stage 3 — modules: work breakdown

- **Status:** plan, 2026-10-26
- **Source:**
  - `docs/spec/80-stages-and-proof.md` §2 stage 3 and §3;
  - `docs/spec/20-module-format-and-abi.md`;
  - `docs/spec/30-module-core.md`;
  - `docs/spec/10-boot-loader.md` §5.2–§5.3 (identity, arena) and §7.4
    (development load);
  - `docs/spec/40-generations-and-composer.md` §3 (gates);
  - `docs/spec/90-measurements.md` §3, the stage-3 rows.
- **Exit gate (80 §2):** the network and graphics drivers ship only as
  modules; no regression against the static drivers' throughput figures.
- **Invariant carried forward (80 §3):** a module that fails to load leaves
  the kernel as it was; the static drivers it replaces stay buildable until
  stage 3 exits.

Stage 3 brings the first loadable modules: the network and graphics drivers,
copied from the root filesystem after root is mounted. Nothing before root is
a module yet. The root controllers, the root filesystems, the RAM disk and
the `marc_root` pass are stage 4 and stage 5. Stage 3 adds:
- the module core, a patch queue on kdedon's MIT DLM core (ashnazag
  project);
- the kernel layout every later module kernel keeps: the arena in `.data`,
  the allowlisted symbol block, the identity record and the kabi tag
  `k30.1.0` / `k46.1.0`;
- the ABI kit;
- `marc_post` and demand loading, with manifest-only loading and the
  development-load override;
- the composer and loader side of module members;
- z3660eth, z3660rtg and the monitor switch as modules.

**Order against stage 2.** As stage 2 did, the host-side items start now:
they need only the frozen specification and the agreed C3 interfaces. Every
stage-3 bench row waits for stage 2's exit on the emulator. Every stage-3
metal row waits for S2-47 (80 §1).

## 1. Conventions

As in `stage-2.md` §1:
- **ID** `S3-nn` for work, `C3-n` for an interface two repositories agree
  before either builds on it. The orchestrator holds that agreement.
- **Owner** is the repository the work lands in.
- **Class:** `host`, `bench` (the emulator) or `metal`.
- **Estimate** in working sessions of one station.

**Toolchain.** Everything in kernel space is built by the pinned
gcc-cross-amix (GCC 2.7.2.3, binutils 2.8.1), with the 060-safe rewrite:
- the core;
- every module;
- the kernel passes;
- the loader.

The pin id goes into the kabi sidecar and each module's `cc` key
(20 §3.2). The user-side tools (`modadmin`, the syscall stubs' library) are
userland and use GCC 14 (D-3 §9).

**Upstream.** The core's MIT base is upstream commit `b736c59` (2026-10-14)
or a later MIT commit, never an earlier one (30 §1). The reference clone is
the workspace's `tmp/2026-10-14-fellow-repos/ashnazag`, read-only. Its
checked-out `main` is older, GPL-2.0, so read the base with
`git show b736c59:<path>`. The tree is surveyed in
`tmp/2026-10-22-modules-proposal/ashnazag-dlm-core-map.md`. Upstream also
carries a `zz9000` and an `ne` module (`kernel/amiga/mod/`), a reference for
the wrapper shape of a cdev driver with `mmap` and of a STREAMS ethernet
driver.

## 2. Work breakdown

### 2.1 Interfaces to agree first (drafts by amix-dlm)

| ID | Interface | Agreed with | Needed by | Est. |
|---|---|---|---|---|
| C3-1 | **The module object and `.moddata` v2** (20 §1.1, §2): the ELF rules; `MD2\0` and the key list; the wrapper revision 2; the name rule; what `modfix` writes; the refusals (a zero match key, an unknown `!` key, `SHT_REL`, a relocation type outside the list, an image over 2 MiB) | the driver repos (amix-z3660net, amix-z3660rtg, the monsw owner), amix-gayle-ide for stage 4 | S3-03, S3-10, S3-25–S3-27 | 0.5 |
| C3-2 | **The exported-symbol table and DDI v1** (20 §4): the symbol block's layout in `.data`; the allowlist file per line and tier; the DDI v1 names and their written contracts (context, spl, memory class, errors); the providers the core links where a kernel lacks one; the post-link gate. Antti reviews the DDI before the kit is frozen (OQ-20.4, D-3 §8) | amix-040-060-port (review), amix-kerntools | S3-04, S3-10, S3-20, S3-21 | 0.75 |
| C3-3 | **The module kernel's identity and sidecar v2** (10 §5.2–§5.3, 20 §3.1). The identity record (magic, kabi string, build id) and its offset; the arena's offset and capacity; the symbol block's fingerprint; the kabi tag `k30.1.0` / `k46.1.0`. A version bump of C2-3 | amix-040-060-port, amix-kerntools, amix-packages | S3-15, S3-16, S3-20, S3-21 | 0.25 |
| C3-4 | **The arena directory and manifest copy** (10 §5.3), between the loader and the core. `AXA1`: count, then per module its name, offset, length, class, CRC-32, flags and parameter string. Then the verbatim manifest the loader booted. Stage 3 writes zero root modules; the layout is the one stage 4 fills | the core (amix-dlm); amix-040-060-port and amix-kerntools reserve it | S3-07, S3-15 | 0.25 |
| C3-5 | **The per-module manifest entry and the module package**. Manifest: `module <name> boot|demand <size> path=/stand/gen/<id>/mod/<name> sha256=…`, plus `param <module>.<name>=<value>` and the `depend` closure. Package: role `module`, `/etc/conf/mod.d/<name>`, `/etc/conf/modreg.d/<name>` (class and parameter defaults, 40 §2.2). Catalog entry: the module's kabi and pin (bumps of C2-2 and C2-3 where fields are added) | amix-packages, amix-packagemanager, amix-installng | S3-16, S3-22, S3-30 | 0.5 |
| C3-6 | **What a driver changes to become a module**: <br>– the wrapper and its `_load`/`_unload`/`_halt`; <br>– registration of its majors from `.moddata` instead of a `cdevsw` row or an `init_tbl` entry; <br>– `intr_attach` instead of patching `int2_tbl` or the INT6 path, with polled mode kept as the default where the driver has one; <br>– `cons_hook_set` instead of the `c1.c`/`displayedscreen` patch; <br>– DMA and mailbox memory from `dma_alloc` only, never virtual = physical; <br>– only allowlisted symbols, checked by the kit's checker; <br>– built with the kit's make fragment. <br>A checklist per driver for z3660eth, z3660rtg and monsw | the three driver owners | S3-25–S3-27 | 0.5 |

### 2.2 The module core (amix-dlm, `core/`)

The patch numbers are 30 §2's. Patches 2 (arena load path), 3 (no-sleep
mode), 7 (block devices), 8 (`sd_register`), 9 (`vfs_register`), 11 (halt
pass) and the `marc_root` half of 16 are stage 4 and 5, except where U1
forces 3 earlier (S3-40).

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S3-01 | **Import and host tests**: `core/upstream.pin` (`b736c59`), `core/upstream/` with the MIT files unmodified and upstream's LICENSE, an empty `core/series`, `core/README.md`, the credit line (D-3 §8). Upstream's host harnesses (relocation oracle against the cross linker, error paths, state harness) built with our toolchain: **M-CORE1** | amix-dlm | host | — | S3-02–S3-09 | 1 |
| S3-02 | **Patch 1, platform split**: ashnazag's registrations (guest majors 54–57 and 59, `ds_modinit`, exec magic 0x150) out of `dlm_init`; `core/plat/k30/`, `core/plat/k46/` | amix-dlm | host | S3-01 | S3-20, S3-21 | 0.5 |
| S3-03 | **Patch 4, `.moddata` v2**: the parser, wrapper revision 2, refusal of a revision-1 module (`EBADVER`), the kabi family/major/minor rule and the compiler-pin check, the key rules of C3-1 | amix-dlm | host | C3-1, S3-01 | S3-10, S3-43 | 0.75 |
| S3-04 | **Patch 5, the allowlisted symbol block**: two tiers replacing the 160 KiB full table; `mkksym` in allowlist mode; the providers the core links (libgcc `__udivdi3`/`__umoddi3`/`__lshrdi3`, `spl0`…`spl7`/`splx` as functions, `dev_kvmap` where a kernel lacks it); the post-link gate that every allowlisted name is defined in every kernel built. The DDI tier first; the core tier's names are listed but first used in stage 5 | amix-dlm | host | C3-2, S3-01 | S3-10, S3-20, S3-21 | 1.5 |
| S3-05 | **Patches 6, 12, 15**: registries from the kit (majors, syscalls) with refusal of a major already owned; `fmodsw` refuses rather than truncates; the `cdevsw`/`streamtab`/`qinit` offsets generated from a probe object compiled against the pinned sysroot's headers, never hard-coded | amix-dlm | host | S3-01, M-REG1 (S3-40) | S3-20, S3-21, S3-25 | 1 |
| S3-06 | **Patches 13, 14**: per-module range checks in `inimg`/`okptr` and the cdev entry check; pin by default (no unload unless `unload=allowed` and every registration is tracked) | amix-dlm | host | S3-01 | S3-43 | 0.75 |
| S3-07 | **Patch 17, manifest-only loading**: `modload`, dependency loads, `dlm_loadname` and the first-open trampoline resolve a module only as a member of the arena's manifest copy (C3-4), read it from `/stand/gen/<id>/mod/` and check its SHA-256 (the loader's `loader/common/sha256.c`, C89, built by the kernel compiler); `modpath` adds nothing. The development-load flag from the loader record lifts it, printed at boot and at every load it permits. The flag is already set by boot2's menu (`d`) and `kbootset next devload` | amix-dlm | host | C3-4, S3-01 | S3-08, S3-43 | 1.25 |
| S3-08 | **Patch 16, `marc_post`** (boot class): after `vfs_mountroot` returns, in process 0, or from the first `sysinit` entry if U15 says so; boot-class members of the booted manifest, in `depend` order, parameters passed from the manifest's `param` records; refused in safe mode (70 §4) | amix-dlm | host | S3-07 | S3-20, S3-21, S3-25 | 0.75 |
| S3-09 | **Patch 10, `intr_attach`/`intr_detach`**: the INT2 chain walker in `int2_tbl`'s last handler slot, an INT6 chain after the CIA-B handler, claim/decline returns, the self-test before a board's interrupt is enabled, polled fallback (30 §4) | amix-dlm | host | S3-01 | S3-25, S3-44 | 1 |
| S3-10 | **The ABI kit** (`abi/`, 20 §5): <br>– headers `mod.h`, `moddefs.h`, `ksym.h`, `ddi.h` (DDI v1 contracts); <br>– tools `mkmod`, `modfix`, the `.moddata` v2 writer, and the checker (format, relocation types, undefined symbols against the allowlist, the 68060 scan, as gcc14-cross-amix's `tools/check-68060-safe.py` does for userland); <br>– the make fragment; <br>– a probe module (the fingerprint) and a sample driver module; <br>– `docs/abi/` (contracts, "writing a module"). <br>The kit build copies the stock headers from the pinned sysroot into the artefact; none is tracked here | amix-dlm | host | C3-1, C3-2, S3-03, S3-04 | S3-22, S3-25–S3-27 | 2 |
| S3-11 | **User side**: the six syscall stubs and `modadmin` (load, unload, status), built with GCC 14 like `kbootset`, part of the base set's `kbootset` package or a `modtools` package | amix-dlm | host | S3-01 | S3-22, S3-43 | 0.5 |

### 2.3 Loader and `kbootset` (amix-dlm)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S3-15 | **boot2, loader version 2**: <br>– the identity record checked at the sidecar's offset (10 §5.2); <br>– the arena directory (zero root modules in stage 3) and the manifest copy written into the arena after relocation; <br>– L5 on overflow; <br>– a generation with an `arena` line needs `loader-min 2`. <br>boot2 has 872 bytes left under its 28 KiB gate (image + bss 27 800 of 28 672), so the size is measured before the code is written. If it does not fit, the menu or the message table gives way, not the gate | amix-dlm | host + bench | C3-3, C3-4 | S3-16, S3-43 | 1 |
| S3-16 | **`kbootset` with module members**: <br>– `build` composes module packages into `/stand/gen/<id>/mod/` and writes `module` and `param` records; <br>– the `depend` closure; <br>– gate 2 for modules (family, major, minor ≤ the kernel's, pin); <br>– gate 6 counts kernel + `bss=` + arena; <br>– the sidecar v2 read (`arena`, identity); <br>– parameter defaults from `modreg.d`, overrides validated against the module's `param` declarations; <br>– `check` hashes the module files in `/stand/gen` against the manifest; <br>– `status` lists the booted generation's modules and, from `kinfo`, the loaded ones (C2-1's loaded-module field, empty until now) | amix-dlm | host | C3-3, C3-5, S3-15 | S3-31, S3-43, S3-45 | 2 |

### 2.4 Module kernels and packages

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S3-20 | **The k46 module kernel**: <br>– the core overlaid on our line's base by symbol weakening (core map §8); <br>– `dmainit` arms the syscalls; <br>– the arena's zero block in `.data`, sized by M-MOD1; <br>– the symbol block, the identity record, kabi `k46.1.0`; <br>– the static z3660eth and zz9000 not linked in. <br>The port's relocation and page-geometry gates must pass (U16). The static families stay buildable. Built on our line, offered as a merge request (80 §4) | amix-040-060-port | host + bench | C3-2, C3-3, S3-02, S3-04, S3-05, S3-08, S3-40 | S3-22, S3-25, S3-26, S3-43 | 2 |
| S3-21 | **The k30 module kernel**: the same from the relink kit; the `brel` form must carry the symbol block's ~1000 R_68K_32 relocations (M-ABI2); kabi `k30.1.0` | amix-kerntools | host + bench | as S3-20 | S3-22, S3-43 | 1.5 |
| S3-22 | **Packages**: <br>– the module kernels with sidecar v2; <br>– the module packages z3660eth, z3660rtg and monsw (role `module`, C3-5); <br>– the ABI kit package per line; <br>– `modadmin`. <br>Catalogued in the kernel-space block | amix-packages | host | C3-5, S3-10, S3-11, S3-20, S3-21, S3-25–S3-27 | S3-31, S3-45 | 1 |

### 2.5 The first copied modules

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S3-25 | **z3660eth as a module** (C3-6): <br>– the wrapper; <br>– the STREAMS-driver linkage on major 51, registered from `.moddata`; <br>– mailbox and frame buffers from `dma_alloc`; <br>– polled RX by default, with interrupt receive through `intr_attach` on INT6 as the measured option (M-INT1); <br>– boot class. <br>The static form stays buildable until the exit. The board runs both lines' kernels, so one module per line | amix-z3660net | host + bench | C3-1, C3-6, S3-09, S3-10, S3-20 | S3-22, S3-45 | 1.5 |
| S3-26 | **z3660rtg as a module** (C3-6): <br>– the wrapper; <br>– the cdev linkage on major 49 with `d_mmap`; <br>– the `init_tbl` work moved into `_load`; <br>– the console hook through `cons_hook_set`; <br>– both targets (ZZ9000, Z3660); <br>– demand class, loaded on first open of `/dev/zz9000`; <br>– `depend=monsw`. <br>The static form stays buildable until the exit | amix-z3660rtg | host + bench | C3-1, C3-6, S3-10, S3-20, S3-27 | S3-22, S3-45 | 1.5 |
| S3-27 | **monsw as a module** (P-8): the card-independent `/dev/monsw` on major 52; `monsw_set`/`register`/`unregister`/`lastclose` exported to other modules through the module symbol table, not the kernel's allowlist; demand class | amix-z3660rtg until the owner decides P-8 question (c) | host + bench | C3-1, C3-6, S3-10 | S3-26 | 1 |

### 2.6 apkg and the installer

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S3-30 | **Module packages in apkg**: role `module` through the kernel-space path (SHA-256, record, trigger); pre-flight on kabi family/major, minor ≤ the installed kernel's, and the pin | amix-packagemanager | host + bench | C3-5 | S3-45 | 0.5 |
| S3-31 | **The installer**: the pristine generation from the module kernel and its boot- and demand-class modules; `/etc/conf/mod.d` and `modreg.d`; the rc steps that stay (`S99zen`'s `slink`, `/etc/monsw`) | amix-installng | bench | S3-16, S3-22 | S3-45 | 0.75 |

### 2.7 Measurements and rows

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S3-40 | **Host measurements over the built kernels, before the module kernels are fixed**: <br>– **M-REG1**: majors, empty rows, `sysentsize` 142 and slots 64–69 `nosys`, `fmodcnt`, structure offsets; <br>– **M-ABI1**: the 68040 vs 68060 export diff, which decides OQ-20.2; <br>– **M-ABI2**: `brel` with the symbol block; <br>– **M-MOD1**: the root-class set's sizes from today's static driver objects, giving the arena capacity = 2 × the set rounded to 64 KiB; <br>– **U5**: `execsw`/`fmodsw`/`vfssw` references symbol-relative; <br>– **U16**: the port's checks with the arena's zero block | amix-dlm (reads amix-kerntools and amix-040-060-port outputs) | host | — | S3-05, S3-20, S3-21 | 1 |
| S3-41 | **Bench measurements on the first module kernel**: <br>– **U1**: the status register and kmem state at `dmainit`, which answers OQ-30.1 and whether patch 3 moves into stage 3; <br>– **U2**: kernel virtual space for copied modules at 128 MB; <br>– **U4**: large kmem requests through `sptalloc`; <br>– **U15**: file loading in process 0 | amix-dlm (rows by the Bench station) | bench | S3-20 | S3-08 (U15), S3-43 | 1 |
| S3-43 | **80's stage-3 emulator rows**: <br>– load; <br>– unload refusal (pinned) and the allowed unload; <br>– dependency (monsw before z3660rtg); <br>– kabi refusal (family, major, minor above the kernel's, pin); <br>– bad-object refusal (`SHT_REL`, a type outside the list, a zero match key, a name over 14, revision 1, a symbol outside the allowlist); <br>– 128 MB machines; <br>– the relocation oracle against the cross linker; <br>– **M-SIG3**: a file not in the manifest, or with another SHA-256, refused at `modload`, at dependency load and at first open; development load lifts it and is printed; <br>– a failed `_load` leaves the kernel as it was (80 §3) | amix-dlm (rows by the Bench station) | bench | S3-03, S3-06, S3-07, S3-15, S3-16, S3-20 | S3-45 | 1.5 |
| S3-44 | **M-INT1, bench half**: the INT2 and INT6 chain logic, polled fallback. The emulated board raises no INT6, so interrupt receive is metal | amix-dlm (rows by the Bench station) | bench | S3-09, S3-25 | S3-46 | 0.5 |
| S3-45 | **Exit row**: a box whose network and graphics come only from modules, installed by the installer and upgraded with apkg. zen0 up with telnet and ftp; X on the RTG (the emulator's ZZ9000 model); the monitor switch; rollback to the previous generation still works | amix-dlm (rows by the Bench station) | bench | S3-16, S3-22, S3-25–S3-27, S3-30, S3-31, S3-43 | S3-46 | 0.5 |
| S3-46 | **Metal**: <br>– z3660eth and z3660rtg as modules on both boxes; <br>– interrupt attachment on metal (M-INT1); <br>– **M-THR1**: throughput as modules against the static figures of record (z3660eth's sustained FTP, about 185 KiB/s; the RTG blitter's per-operation cost); <br>– the 030 line's metal: z3660eth on a K030 kernel on the Z3660 in 68030 mode (Q3-4) | amix-dlm, the driver repos (via the lab registry) | metal | S3-44, S3-45 | stage exit | 1.5 |

## 3. Critical path and totals

`C3-1/C3-2/C3-3/C3-4 → S3-01 → S3-03/S3-04 → S3-07 → S3-08 → S3-20 → S3-25/S3-26 → S3-22 → S3-45 → S3-46`.

Feeding it in parallel:
- the host measurements S3-40 (M-REG1, M-ABI1/2, M-MOD1, U5, U16) before
  S3-05 and S3-20, because they size the arena and confirm the syscall and
  major rows;
- the ABI kit S3-10 before the driver ports S3-25–S3-27;
- the loader and `kbootset` side S3-15/S3-16, then the installer S3-31;
- the k30 kernel S3-21 beside S3-20.

Unlike stage 2, the path runs through amix-dlm until the module kernel:
the core, the kit and the composer come first. The first item outside
amix-dlm on the path is **S3-20** (the k46 module kernel,
amix-040-060-port). The interfaces the other repositories wait for are C3-1
(driver owners), C3-2 (the port's review) and C3-3 (kernel builders).

Estimate:
- interfaces: about 2.75 sessions;
- the core: about 11;
- loader and `kbootset`: about 3;
- module kernels and packages: about 4.5 (other repositories);
- the three modules: about 4 (driver repositories);
- apkg and the installer: about 1.25;
- measurements and rows: about 6.

## 4. Open questions for this plan

| ID | Question | Proposed owner |
|---|---|---|
| Q3-1 | **Settled** (orchestrator, 2026-10-26): `intr_attach` is built in stage 3 for the copied modules (S3-09), and stage 4 reuses it for the root controllers. 80 §2 changed after the freeze to say so | — |
| Q3-2 | Which repository holds monsw (P-8 question (c))? The owner decides. Until then S3-27 is planned where monsw lives today, amix-z3660rtg, and stays movable | owner |
| Q3-3 | Is one k46 ABI right for the 68040 and the 68060 (OQ-20.2)? M-ABI1 (S3-40) decides before the family is fixed in S3-20 | us; Antti |
| Q3-4 | **Settled** (orchestrator, 2026-10-26): z3660eth on a K030 kernel, on the Z3660 in 68030 mode, is the 030 line's metal. It is the only real 68030 with an MMU on the benches (the A4000D's 68EC030 has none), so OQ-80.1 closes that way for this stage | — |
| Q3-5 | Do we offer the patches upstream (OQ-30.6)? Upstream's zz9000 module also takes major 49 (OQ-20.5). Neither blocks the plan | ashnazag; us |

## 5. Not in stage 3

- `marc_root`, root-class modules in the arena, the arena load path
  (patch 2), the no-sleep mode (patch 3, unless U1 moves it), `sd_register`
  and the four-card contract, the halt pass, the RAM disk, safe mode's
  root-controller member (stage 4).
- The filesystems as modules, the core tier's first users, the 040/060
  base without ufs/s5 (stage 5).
- Signing: suspended by D-3 §13.
