# 00 — Overview

- **Status:** draft (S0), 2026-10-25
- **Implements:** the S0 specification for loadable kernel modules in Amix 1.1, against the project's release decisions of 2026-10-25 (decision record D-3, items 1–9)

## 1. What this specification is

Amix 1.1 gets loadable kernel modules on both CPU lines (68030; 68040/68060)
and on every install medium: our own boot loader reads a *generation* — a
kernel plus the modules the root disk needs — as separate files; the module
core (a patch queue on kdedon's MIT DLM core) loads root-class modules before
root is mounted and everything else after; the composer `kbootset` builds,
commits and rolls back generations behind fail-closed gates; packages carry
kernel space under one offline signing key. The decision record behind it
(D-3) takes nine decisions; this directory turns each into a design that can
be built and proven. No code is part of S0.

Where D-3 and the earlier proposal P-28 differ, D-3 wins; each file names the
P-28 decisions it replaces or keeps. P-24 and P-28 remain the research record.

### Reading order

| File | Area |
|---|---|
| `10-boot-loader.md` | boot1, boot2, the boot store, ISO9660, the manifest, the arena, the menu, failure messages |
| `20-module-format-and-abi.md` | object formats, `.moddata` v2, kabi, the compiler pin, exported symbols, the ABI kit, registries |
| `30-module-core.md` | the adopted core and its patch queue, load points, interrupts, the four-card sd contract, filesystems as modules, the RAM disk |
| `40-generations-and-composer.md` | the 1.1 disk layout, generations, `kbootset`, `kinfo`, apkg integration, the upgrade install |
| `50-media.md` | disk/SD images, floppy pair, CD-ROM, netinstall, tape, emulation |
| `60-signing-and-publishing.md` | the key, what is signed and checked, offline media, the public catalog |
| `70-static-floor.md` | the compiled-in set and why each member is there |
| `80-stages-and-proof.md` | the proof order inside 1.1, collaboration asks |
| `90-measurements.md` | every measurement, its evidence class and the stage that needs it |

### Sources

Facts are cited by path, relative to the Amix project workspace — the
directory that holds this repository beside its sibling repositories
(amix-kerntools, amix-installng, amix-packagemanager, amix-040-060-port,
amix-gayle-ide, amix-cdfs, grimoire-amix and others), the project's review
records (`review/`) and its research notes (`tmp/2026-10-22-modules-proposal/`,
`tmp/2026-10-14-modules-study/`). Some of those are not yet public; the paths
are given so every fact can be traced. Anything not established by a cited
source is an open question below, never a fact. Stock Commodore material is
described and referenced, never reproduced.

## 2. Traceability: D-3 item → specification

| D-3 | Decision (short) | Implemented in |
|---|---|---|
| 1 | Own the boot loader: boot1/boot2 from our source and toolchain; manifest; kernel and root-class modules as separate files; 2048-byte CD blocks; menu and rollback key; tested like a driver; stock loader kept on the early-startup route and 1.0 media until proven; the in-kernel slot retired | **10** (all); 40 §3 (`loader-install`), §5; 80 §2 stage 1; 90 §1 |
| 2 | Media: disk/SD, floppy pair (both lines), CD-ROM boot and install; netinstall medium (floppy pair if it fits, else small disk + CD image), packages over HTTP; no boot ROM, no netboot; tape a source only; floppies never a source; emulation = same bytes as metal | **50** (all); 10 §4; 70 §2 (floppy, tape on the floor); 90 §5 |
| 3 | Both CPU lines first-class: same loader, core, lifecycle, media; the 060 floppy pair supported | 10 §8; 20 §1, §3; 30 §1, §5; 50 §3; 70 §1; **80** §2 |
| 4 | Controllers and filesystems are modules; the static floor fixed; filesystem separation on our line, Antti's base the merge target | **30** §5, §6; **70**; 20 §2, §6 |
| 5 | 1.0 boxes reinstall; in-place upgrades from 1.1 on; upgrade install keeps a data slice and restores the surviving configuration; a layout that never needs a re-lay | **40** §2.1, §7 |
| 6 | Rescue and rollback: two kept generations + pristine; good only after a full multi-user boot; menu key or mouse button, one-shot previous, safe mode; every install medium a rescue medium; one boot slice per disk | 10 §4.2, §7; **40** §1–§3; 70 §4; 50 §1 |
| 7 | Publishing and trust: kernel space in the public catalog, marked; one offline key; public key in installer and client; unsigned kernel space refused; second key only by decision; ABI kit published | **60**; 40 §6; 20 §5 |
| 8 | One 1.1; proof order (loader → lifecycle on static kernels → modules → root as a module); code in amix-dlm, recipes in driver repos, kernel changes as merge requests; asks to Antti, ashnazag, Emre | **80**; 30 §1; repository README |
| 9 | Toolchain split: kernel space on gcc-cross-amix (GCC 2.7.2.3, `m68k-cbm-sysv4`), pinned by the ABI kit; GCC 14 for userland only | 20 §3.2; 10 §3.3; 40 §3 (`kbootset` is userland); 30 §1 |

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

  apkg 0.3 (signed catalog, kernel space in a hidden block) ─► trigger ─► kbootset build/commit
  kbootset: gates ─► write extents ─► read back ─► flip control block (the commit point)
```

## 4. Open questions, collected

Owner proposals: **us** = this project's maintainers; **Antti** = Antti
Sokero, the 68040/68060 port; **ashnazag** = kdedon, author of the adopted DLM
core; **Emre** = Emre Bastuz, author of the Gayle IDE driver; **owner** = a
decision reserved to the project owner.

| ID | Question (short) | Proposed owner |
|---|---|---|
| OQ-10.1 | What the strap does with a bootblock's return value (Z3660 ROM chain answered by M-LD3: alert and reset; other ROMs open) | us |
| OQ-10.2 | Which bootblock header fields the strap checks on a `UNI\0` partition | us |
| OQ-10.3 | Strap and a 2048-byte CD node; ROM 42.39 vs the reference mounter | us |
| OQ-10.4 | boot2 screen output: graphics.library or an Intuition screen | us |
| OQ-10.5 | Clear CACR.CABC on 68060 hand-off | us; Antti (kernel side) |
| OQ-10.6 | Is a UFS reader ever needed | us |
| OQ-10.7 | Any kernel consumer misreading a filled `keystates[]` | us |
| OQ-10.8 | Kernel memory sizing with a shortened `memory[]` region | us |
| OQ-10.9 | **CD boot mechanism:** A, RDB-style CD with boot blocks; B, loader started from the disc's AmigaDOS startup (recommended) | owner |
| OQ-20.2 | One k46 ABI for 68040 and 68060, or two families | us; Antti |
| OQ-20.4 | DDI v1 list and contracts; review | us; Antti reviews |
| OQ-20.5 | A shared major/syscall registry with ashnazag | ashnazag |
| OQ-30.1 | Is a no-sleep mode needed at `dmainit` or only at `marc_root` | us |
| OQ-30.2 | **030 card order:** K, keep the 1.0 address order (recommended); R, one rule on both lines | owner |
| OQ-30.3 | The A4000T onboard 53C710 driver and its gated probe in time for 1.1 | us |
| OQ-30.4 | Review of the 040/060 base rebuilt without ufs/s5 | us build; Antti reviews |
| OQ-30.5 | The 040/060 halt path before the halt pass | Antti; us |
| OQ-30.6 | Which core patches go upstream | ashnazag |
| OQ-30.7 | Re-check upstream's `rth1.c` before the merge request | us |
| OQ-40.1 | The exact surviving-configuration set (P-29) | us |
| OQ-40.2 | Data slice default size and mount point | us |
| OQ-40.3 | A rescue RAM-disk generation in every boot store | us |
| OQ-40.4 | Stock `pkgadd` on `/stand` conflicts and overwrite orphans | us |
| OQ-40.5 | Checksum contract version 2 for generations (P-28 D23 re-scoped) | us |
| OQ-40.6 | Swap slice size cap for the configuration archive | us |
| OQ-40.7 | The 1024 MiB filesystem limit before the layout freezes | us |
| OQ-50.1 | Floppy profile per line: RAM-disk or fd0 root | us |
| OQ-50.2 | Netinstall: form A (floppy pair, trimmed engine) chosen by M-NET1a/b; confirm the ≥ 5 % margin after M-NET1c/d and `kbootset`, else form B | us |
| OQ-50.3 | Can the Z3660 firmware's floppy emulation boot the pair | us |
| OQ-50.4 | Which 030 machines can boot the CD | us |
| OQ-50.5 | Tape device nodes on card 1 | us |
| OQ-50.6 | One real tape drive row | Antti |
| OQ-50.7 | One ISO for both lines (proposed) or one per line | us |
| OQ-60.1 | Signature scheme and file format (Ed25519, minisign/signify layout proposed) | us; owner holds the key |
| OQ-60.2 | Second key by a repository-fetched statement (proposed: no) | owner |
| OQ-60.3 | Signed userland packages from 1.1 on | owner |
| OQ-60.4 | Hash and signature tools on the box for administrators | us |
| OQ-70.1 | Can the root filesystems leave the 040/060 kernel (symbol surface) | us; Antti reviews |
| OQ-70.2 | Boot-time consumers of ufs inside the base in safe mode | us |
| OQ-70.3 | Is the inet stack separable (recorded, not required) | us |
| OQ-80.1 | Metal evidence for the 030 line | us; Antti |
| OQ-80.2 | The A4000T 53C710 driver for stage 4, else a release note | us |
| OQ-80.3 | Throughput baselines for stage 3 | us |
| OQ-80.4 | Gayle IDE as the first outside module: module form, `intr_attach`, rank key, ATAPI route | Emre |

Closed in the review pass (T-52): OQ-20.1 (stock headers are published in the ABI kit, D-3 §7) and OQ-20.3 (z3660eth matches 144b:01).

## 5. Measurements

Every measurement, with its evidence class (bench or metal, P-28 D51) and the
stage that needs it, is in `90-measurements.md`.

**S0 freeze condition — met 2026-10-25.** The specification freezes when
every stage-0 measurement is closed: **M-NET1a and M-NET1b** (the netinstall
miniroot's raw and compressed size; D-3 §2 says the netinstall fit is
"measured in S0"). Both are closed
(`docs/measurements/2026-10-25-m-net1.md`): with the installer engine trimmed
to what the installer calls, miniroot plus a deflated kernel fills two DD
volumes with 16.1 % (k30) and 13.0 % (k46) to spare, so form A is chosen
(`50-media.md` §5.1, OQ-50.2 narrowed).

**Deviation DV-1 (for the owner to approve).** The rest of the netinstall fit
— M-NET1c (compressed floor kernel and root modules), M-NET1d (store overhead
per volume), M-NET1e (RAM at boot), M-NET1f (inet in a miniroot), M-NET1g
(HTTP from the miniroot) — cannot close in S0: c–e depend on the 1.1 floor
kernel and the store format, f and g on a running miniroot. They are scheduled
in stages 1–5 (`90-measurements.md` §5), and they confirm or overturn the form-A choice made in S0 (OQ-50.2).

**Owner decisions open at the freeze:** OQ-10.9 (CD mechanism), OQ-30.2 (030
card order), DV-1, OQ-60.2, OQ-60.3. The first measurements after the freeze
are the stage-1 loader items (M-LD1–M-LD9, M-EMU1).

## 6. P-28 decisions and where they went

| P-28 | Fate |
|---|---|
| D1, D3, D5, D6, D8, D10, D12, D14, D16, D18, D19/D55, D24, D27, D43, D45, D46, D51, D59, D61, D63 | kept (cited where used) |
| D2, D7, D20, D57 (slot inside the kernel; slot format; slot capacity) | replaced: our loader fills an arena; capacity rule kept for the arena (10 §5.3) |
| D4 | kept in substance: root class resident (arena), the rest copied |
| D9 | replaced: four controllers in 1.1; 030 order is OQ-30.2 (30 §5) |
| D11, D54, D60 | kept, adapted to the loader record (40 §2.2, §5) |
| D13, D30, D48 | settled by D-3 §7 (60): kernel space in the public signed catalog; the ABI kit publishes the stock headers too (20 §5, 60 §6) |
| D15, D32, D56 | retired: one boot slice per disk; 1.0 boxes reinstall |
| D17, D37, D38, D39, D40 | replaced: floppy pair supported on both lines, store-based, profile by measurement (50 §3) |
| D21, D25, D49, D52, D53 | replaced by the proof order of 80 and D-3 §3 |
| D22, D26, D28 | replaced by D-3 §4: our line rebuilds the 040/060 base without ufs/s5 (70, 30 §6) |
| D23 | re-scoped: checksum contract version 2 (OQ-40.5) |
| D29, D33 | replaced: safe mode chosen in the loader and passed in the loader record (10 §6–§7) |
| D31, D34, D35, D36, D62 | replaced: host `kbootset --image` composes every medium; the installer runs `kbootset -R` (40 §3, 50 §1) |
| D41, D42, D44 | replaced: the CD boots; the mechanism is OQ-10.9 (10 §4.4, 50 §4) |
| D47 | replaced: netinstall medium (50 §5) |
| D50 | kept as stage-1 prerequisite M-EMU1 |
| D58 | settled: `kinfo` major 53 proposed (20 §6) |
