# 00 — Overview

- **Status:** draft (S0), 2026-10-25
- **Implements:** the S0 specification for loadable kernel modules in Amix 1.1, against the project's release decisions of 2026-10-25 (§2, items 1–9)

## 1. What this specification is

Amix 1.1 gets loadable kernel modules on both CPU lines (68030; 68040/68060)
and on every install medium: our own boot loader reads a *generation* — a
kernel plus the modules the root disk needs — as separate files; the module
core (a patch queue on kdedon's MIT DLM core) loads root-class modules before
root is mounted and everything else after; the composer `kbootset` builds,
commits and rolls back generations behind fail-closed gates; packages carry
kernel space with a SHA-256 per package (signing is not in 1.1, decision 13
in §2). Nine release decisions are behind it, and four more were taken after
the freeze (§2); this directory turns each into a design that can be built
and proven. No code is part of S0.

Where the release decisions differ from the earlier design proposal, the
release decisions win; §6 lists what became of the earlier proposal's choices.

### Reading order

| File | Area |
|---|---|
| `10-boot-loader.md` | boot1, boot2, the boot store, ISO9660, the manifest, the arena, the menu, failure messages |
| `20-module-format-and-abi.md` | object formats, `.moddata` v2, kabi, the compiler pin, exported symbols, the ABI kit, registries |
| `30-module-core.md` | the adopted core and its patch queue, load points, interrupts, the four-card sd contract, filesystems as modules, the RAM disk |
| `40-generations-and-composer.md` | the 1.1 disk layout, generations, `kbootset`, `kinfo`, apkg integration, the upgrade install |
| `50-media.md` | disk/SD images, floppy pair, CD-ROM, netinstall, tape, emulation |
| `60-signing-and-publishing.md` | integrity in 1.1, the signature hook, the deferred signing design, offline media, the public catalog |
| `70-static-floor.md` | the compiled-in set and why each member is there |
| `80-stages-and-proof.md` | the proof order inside 1.1, collaboration asks |
| `90-measurements.md` | every measurement, its evidence class and the stage that needs it |

### Sources

Facts are cited by path. A path that does not start in this repository
names one of its sibling projects (amix-kerntools, amix-installng,
amix-packagemanager, amix-040-060-port, amix-gayle-ide, amix-cdfs,
grimoire-amix and others). Some of those are not yet public; the paths are
given so every fact can be traced. Facts that came from the project's
research notes and bench runs are stated where they are used. Anything not
established by a cited source is an open question below, never a fact. Stock Commodore material is
described and referenced, never reproduced.

## 2. Traceability: release decision → specification

| # | Decision (short) | Implemented in |
|---|---|---|
| 1 | Own the boot loader: boot1/boot2 from our source and toolchain; manifest; kernel and root-class modules as separate files; 2048-byte CD blocks; menu and rollback key; tested like a driver; stock loader kept on the early-startup route and 1.0 media until proven; the in-kernel slot retired | **10** (all); 40 §3 (`loader-install`), §5; 80 §2 stage 1; 90 §1 |
| 2 | Media: disk/SD, floppy pair (both lines), CD-ROM boot and install; netinstall medium (floppy pair if it fits, else small disk + CD image), packages over HTTP; no boot ROM, no netboot; tape a source only; floppies never a source; emulation = same bytes as metal | **50** (all); 10 §4; 70 §2 (floppy, tape on the floor); 90 §5 |
| 3 | Both CPU lines first-class: same loader, core, lifecycle, media; the 060 floppy pair supported | 10 §8; 20 §1, §3; 30 §1, §5; 50 §3; 70 §1; **80** §2 |
| 4 | Controllers and filesystems are modules; the static floor fixed; filesystem separation on our line, Antti's base the merge target | **30** §5, §6; **70**; 20 §2, §6 |
| 5 | 1.0 boxes reinstall; in-place upgrades from 1.1 on; upgrade install keeps a data slice and restores the surviving configuration; a layout that never needs a re-lay | **40** §2.1, §7 |
| 6 | Rescue and rollback: two kept generations + pristine; good only after a full multi-user boot; menu key or mouse button, one-shot previous, safe mode; every install medium a rescue medium; one boot slice per disk | 10 §4.2, §7; **40** §1–§3; 70 §4; 50 §1 |
| 7 | Publishing and trust: kernel space in the public catalog, marked; one offline key; public key in installer and client; unsigned kernel space refused; second key only by decision; ABI kit published — **signing suspended for 1.1 by item 13** | **60**; 40 §6; 20 §5 |
| 8 | One 1.1; proof order (loader → lifecycle on static kernels → modules → root as a module); code in amix-dlm, recipes in driver repos, kernel changes as merge requests; asks to Antti, ashnazag, Emre | **80**; 30 §1; repository README |
| 9 | Toolchain split: kernel space on gcc-cross-amix (GCC 2.7.2.3, `m68k-cbm-sysv4`), pinned by the ABI kit; GCC 14 for userland only | 20 §3.2; 10 §3.3; 40 §3 (`kbootset` is userland); 30 §1 |
| 10 | (after the freeze) CD boot: a standard ISO9660 disc, AmigaDOS from the ROM's CD filesystem, boot2 as an AmigaDOS program started by its startup-sequence; RDB-style disc rejected | **10** §4.4; 50 §4; 90 M-LD2 |
| 11 | (after the freeze) Disk numbering: compacted rank on both lines (Z3660, Zorro boards, motherboard controller, IDE); 030 boxes with two controllers renamed relative to 1.0, accepted | **30** §5.2–§5.3; 90 M-SD1 |
| 12 | (after the freeze) DV-1 approved: the build-dependent netinstall contributions are confirmed in stage 1 as they exist; below a 5 % margin the netinstall medium becomes form B | **50** §5.1; 00 §5; 90 M-NET1c–g |
| 13 | (after the freeze) Signing out of 1.1: no catalog signature, no key, no refusal of unsigned kernel space; integrity by per-package SHA-256; a verification hook in the catalog format, apkg and kbootset; OQ-60.2/60.3 moot | **60**; 40 §3.1, §6; 50 §1; 30 §2 patch 17; 80 §2; 90 M-SIG1 |

## 3. The design in one page

```
Kickstart strap ─► boot1 (1 KB) ─► boot2 (≤ 28 KiB, self-relocating, ours)
                                     │ reads: boot store (disk/SD/floppy) or ISO9660 (CD)
                                     │ picks: default / trial once / one-shot / menu / safe mode
                                     ▼
            manifest ─► kernel (relocated) + root-class modules into the kernel's arena
                        (+ RAM-disk image for CD / floppy / netinstall)
                                     │ bootinfo: RTH1 record + loader record AXL1
                                     ▼
   dmainit: arm ─► marc_root (in rth1_mountroot): relocate arena modules, sd_register,
                   vfs_register ─► rth1_apply ─► vfs_mountroot(rootfstype from manifest)
              ─► marc_post: boot-class modules from /stand/gen/<id>/mod (SHA-256 checked)
              ─► rc ─► kbootset mark-good at the end of run level 2

  apkg 0.3 (catalog with SHA-256, kernel space in a hidden block) ─► trigger ─► kbootset build/commit
  kbootset: gates ─► write extents ─► read back ─► flip control block (the commit point)
```

## 4. Open questions, collected

Who answers: **us** = this project's maintainers; **Antti** = Antti
Sokero, the 68040/68060 port; **ashnazag** = kdedon, author of the adopted DLM
core; **Emre** = Emre Bastuz, author of the Gayle IDE driver.

| ID | Question (short) | Proposed answerer |
|---|---|---|
| OQ-10.1 | What the strap does with a bootblock's return value (Z3660 ROM chain answered by M-LD3: alert and reset; other ROMs open) | us |
| OQ-10.2 | Which bootblock header fields the strap checks on a `UNI\0` partition | us |
| OQ-10.3 | Strap and a 2048-byte CD node; ROM 42.39 vs the reference mounter | us |
| OQ-10.4 | boot2 screen output: graphics.library or an Intuition screen | us |
| OQ-10.5 | Clear CACR.CABC on 68060 hand-off | us; Antti (kernel side) |
| OQ-10.6 | Is a UFS reader ever needed | us |
| OQ-10.7 | Any kernel consumer misreading a filled `keystates[]` | us |
| OQ-10.8 | Kernel memory sizing with a shortened `memory[]` region | us |
| OQ-20.2 | One k46 ABI for 68040 and 68060, or two families | us; Antti |
| OQ-20.4 | DDI v1 list and contracts; review | us; Antti reviews |
| OQ-20.5 | A shared major/syscall registry with ashnazag | ashnazag |
| OQ-30.1 | Is a no-sleep mode needed at `dmainit` or only at `marc_root` | us |
| OQ-30.3 | The A4000T onboard 53C710 driver and its gated probe in time for 1.1 (settled: written in stage 4) | us |
| OQ-30.4 | Review of the 040/060 base rebuilt without ufs/s5 | us build; Antti reviews |
| OQ-30.5 | The 040/060 halt path before the halt pass (answered: no crash; the pass hooks mdboot) | Antti; us |
| OQ-30.6 | Which core patches go upstream | ashnazag |
| OQ-30.7 | Re-check upstream's `rth1.c` before the merge request | us |
| OQ-40.1 | The exact surviving-configuration set | us |
| OQ-40.2 | Data slice default size and mount point | us |
| OQ-40.3 | A rescue RAM-disk generation in every boot store | us |
| OQ-40.4 | Stock `pkgadd` on `/stand` conflicts and overwrite orphans | us |
| OQ-40.5 | Checksum contract version 2 for generations — **closed** by `docs/contracts/C2-5-checksum-v2.md` | us |
| OQ-40.6 | Swap slice size cap for the configuration archive | us |
| OQ-40.7 | The 1024 MiB filesystem limit before the layout freezes | us |
| OQ-50.1 | Floppy profile per line: RAM-disk or fd0 root | us |
| OQ-50.2 | Netinstall: form A (floppy pair, trimmed engine) chosen by M-NET1a/b; confirm the ≥ 5 % margin after M-NET1c/d and `kbootset`, else form B | us |
| OQ-50.3 | Can the Z3660 firmware's floppy emulation boot the pair | us |
| OQ-50.5 | Tape device nodes on card 1 | us |
| OQ-50.6 | One real tape drive row | Antti |
| OQ-50.7 | One ISO for both lines (proposed) or one per line | us |
| OQ-60.1 | For the release that adds signing: scheme and file format (Ed25519, minisign/signify layout proposed) | us; the project holds the one offline key |
| OQ-60.4 | Hashing tools on the box for administrators | us |
| OQ-70.1 | Can the root filesystems leave the 040/060 kernel (symbol surface) | us; Antti reviews |
| OQ-70.2 | Boot-time consumers of ufs inside the base in safe mode | us |
| OQ-70.3 | Is the inet stack separable (recorded, not required) | us |
| OQ-80.1 | Metal evidence for the 030 line | us; Antti |
| OQ-80.2 | The A4000T 53C710 driver for stage 4 (settled: written in stage 4) | us |
| OQ-80.3 | Throughput baselines for stage 3 (answered 2026-10-26) | us |
| OQ-80.4 | Gayle IDE as the first outside module: module form, `intr_attach`, rank key, ATAPI route | Emre |
| OQ-80.5 | An A4091 root on an 030 Z3660 box: a bounce buffer or the kernel bound in motherboard RAM (settled: DDI v1.1 DMA, the 030 provider bounces) | us; amix-a4091 |
| OQ-80.6 | A 1.1 Z3660 release firmware that runs the 68030 MMU mode on metal | Z3660 |
| OQ-80.7 | A spacer between back-to-back Z3660 register writes, for every driver | Z3660; the driver repos |

Closed in the specification review: OQ-20.1 (stock headers are published in the ABI kit, decision 7) and OQ-20.3 (z3660eth matches 144b:01). Closed after the freeze: OQ-60.2 and OQ-60.3 (moot, decision 13), OQ-30.2 (decision 11), OQ-10.9 (decision 10) and with it OQ-50.4 (the CD boots where the boot ROM has a CD filesystem; other machines use the floppy pair).

## 5. Measurements

Every measurement, with its evidence class (bench or metal) and the
stage that needs it, is in `90-measurements.md`.

**S0 freeze condition — met 2026-10-25.** The specification freezes when
every stage-0 measurement is closed: **M-NET1a and M-NET1b** (the netinstall
miniroot's raw and compressed size; release decision 2 has the netinstall
fit "measured in S0"). Both are closed
(`docs/measurements/2026-10-25-m-net1.md`): with the installer engine trimmed
to what the installer calls, miniroot plus a deflated kernel fills two DD
volumes with 16.1 % (k30) and 13.0 % (k46) to spare, so form A is chosen
(`50-media.md` §5.1, OQ-50.2 narrowed).

**Deviation DV-1 (accepted after the freeze, decision 12).** The rest of the netinstall fit
— M-NET1c (compressed floor kernel and root modules), M-NET1d (store overhead
per volume), M-NET1e (RAM at boot), M-NET1f (inet in a miniroot), M-NET1g
(HTTP from the miniroot) — cannot close in S0: c–e depend on the 1.1 floor
kernel and the store format, f and g on a running miniroot. They are scheduled
in stages 1–5 (`90-measurements.md` §5) and confirm or overturn the form-A choice made in S0 (OQ-50.2): if they take the margin below 5 %, the netinstall medium becomes the small disk + CD image (form B).

**Decisions open at the freeze:** none left. OQ-10.9 (CD mechanism),
OQ-30.2 (030 card order) and DV-1 were decided as decisions 10–12 (§2); signing was
taken out of 1.1 (decision 13), which makes OQ-60.2 and OQ-60.3 moot. The first measurements after the freeze
are the stage-1 loader items (M-LD1–M-LD9, M-EMU1).

## 6. The earlier proposal's choices and where they went

| Earlier choice | Fate |
|---|---|
| The adopted MIT core as a named patch queue; the load points (`dmainit` arms, the root class inside `rth1_mountroot`, the boot class after root); one kabi per family; the allowlisted symbol table and DDI v1; `.moddata` v2; syscalls 64–69; kernel space in a hidden `#ext kpkg 1` catalog block; `bootset=auto`; modules pinned by default; module recipes in the driver repos; one previous kabi kept served; `kinfo` in every kernel; FPE never a module; no blind CD probing; tape a package source only, and its proof order; bench or metal per measurement; streaming installs from media; the mountroot hook ours; kernel-space atomicity | kept (cited where used) |
| A slot inside the kernel image, its own slot format and a measured slot capacity | replaced: our loader fills an arena; capacity rule kept for the arena (10 §5.3) |
| Resident only for the root class, copied for everything else | kept in substance: root class resident (arena), the rest copied |
| Two controllers in a fixed order, four-card naming later | replaced: four controllers in 1.1, one compacted rank order on both lines (decision 11; 30 §5) |
| Kernels in `/stand/k0x0` with `kbootset` replacing `updbootpart`; a generation marked good late, `updbootpart` retired; `kbootset` finding the boot disk from RTH1 | kept, adapted to the loader record (40 §2.2, §5) |
| Kernel space through the private package gate; signing-key custody and the ABI kit's stock headers; the net module class and timing | settled by decisions 7 and 13 (60): kernel space in the public catalog with SHA-256, signing deferred past 1.1; the ABI kit publishes the stock headers too (20 §5, 60 §8) |
| A second boot slice on new installs; legacy 2 MiB boot slices | retired: one boot slice per disk; 1.0 boxes reinstall |
| Floppy delivery measured first, with its budget, ladder, a bench-only 060 pair and a module floppy | replaced: floppy pair supported on both lines, store-based, profile by measurement (50 §3) |
| The earlier stage order, the k46 ship condition, one kernel line, the root device as a module, the 030 line static | replaced by the proof order of 80 and decision 3 |
| Root filesystems static until the collaborator's base separates them; the static floor; one CPU line per root filesystem | replaced by decision 4: our line rebuilds the 040/060 base without ufs/s5 (70, 30 §6) |
| An amended checksum contract for composed generations | re-scoped: checksum contract version 2 (OQ-40.5) |
| Safe mode by the mouse button at the hook, the flag an RTO1 bit | replaced: safe mode chosen in the loader and passed in the loader record (10 §6–§7) |
| The rescue core in 1.1, media sizing, what the installer writes, who owns the composer, one install boot image per line | replaced: host `kbootset --image` composes every medium; the installer runs `kbootset -R` (40 §3, 50 §1) |
| No bootable CD in 1.1; kernel space on the CD as packages; extra CD routes | replaced: the CD boots, with boot2 as an AmigaDOS program (decision 10; 10 §4.4, 50 §4) |
| Network: HTTP from the package repository | replaced: netinstall medium (50 §5) |
| The bench shape (the emulated board advertises its boot ROM) | kept as stage-1 prerequisite M-EMU1 |
| `kinfo`'s major assigned from the registry | settled: `kinfo` major 53 proposed (20 §6) |
