# 30 — Module core

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §4 (root disk controllers and root filesystems as modules; filesystem separation on our line with Antti's base as the merge target), D-3 §8 (the core as a patch queue on ashnazag's MIT core; credit; kernel-side changes to the 040/060 port as merge requests), D-3 §3 (both lines)
- **Replaces:** P-28 D4/D7 (resident slot composed by `kbootset`) — root-class modules now arrive in the arena filled by our loader; P-28 D9 (two controllers in v1); P-28 D22 (filesystems static until the base separates them)
- **Keeps:** P-28 D1, D3, D16, D61

Paths are relative to the Amix project workspace. `MAP` =
`tmp/2026-10-22-modules-proposal/ashnazag-dlm-core-map.md`, `L1` =
`tmp/2026-10-14-modules-study/L1-dlm-internals.md`, `STUDY` =
`tmp/2026-10-14-modules-study/STUDY.md`, `L2` =
`tmp/2026-10-14-modules-study/L2-our-kernels.md`. Line references into the
upstream core are to the commit named in §1.

## 1. The adopted core and the patch queue

**Upstream.** The DLM core of kdedon's ashnazag project: six system calls,
an ELF relocatable loader, a kernel symbol block, character-device, STREAMS,
exec and hook linkages; about 3 200 lines of C in five files (`MAP` §0–§1).
It is spliced into the stock kernel by link-time symbol weakening, without
editing stock source (`MAP` §8), and is CPU-agnostic (it also links into a
stock 68030 kernel of another platform, `MAP` §8).

**Licence.** The core is MIT, "Copyright (c) 2026 kdedon", from upstream
commit `b736c59` (2026-10-14). Earlier commits of the project are GPL-2.0
(`MAP` §0). The queue's base is `b736c59` or a later MIT commit, never an
earlier one; every adopted file keeps its copyright line and the MIT notice.

**Shape in this repository.**

```
core/upstream.pin      upstream URL and commit id
core/upstream/         the MIT files we use, unmodified, with upstream's LICENSE
core/patches/NNNN-*.patch
core/series            patch order
core/README.md         what each patch does and whether it was offered upstream
```

Each patch is self-contained and named for what it does; a patch the author
takes upstream is dropped from the queue when the pin moves. The queue applies
to the same files on both CPU lines; line-specific code lives in
`core/plat/k30/` and `core/plat/k46/`, not in patches.

## 2. The patch queue

What the adopted core lacks for our use is mapped in `MAP` §10 and
`tmp/2026-10-22-modules-proposal/refute-ashnazag-dlm-init-claim.md`.

| # | Patch | Why |
|---|---|---|
| 1 | Platform split: move ashnazag-specific registrations (its guest majors 54–57, 59, `ds_modinit`, exec magic 0x150) out of `dlm_init` into its platform file | our kernels have none of them (`MAP` §6) |
| 2 | Arena load path: load a module from an in-memory image placed by the loader, relocate in place, never free it (`dlm_load_mem`) | the core reads only through the VFS and allocates every image (`MAP` §5); the ELF layer already reads through a callback (`dlm.h` read callback, `MAP` §10.1) |
| 3 | No-sleep mode before process 1: allocation failure returns an error instead of sleeping; no record sleeps | every core allocation is `KM_SLEEP` (`MAP` §5); a root-class load runs before processes exist (U1) |
| 4 | `.moddata` v2 parser, wrapper revision 2, kabi and compiler-pin checks | `20-module-format-and-abi.md` §2–§3 |
| 5 | Allowlisted symbol block (two tiers) replacing the full 160 KiB table | `20-…` §4 |
| 6 | Registries: majors, syscalls, filesystem names from the kit; refusal of a major already owned | `20-…` §6; the core and its zz9000 module both use major 49 |
| 7 | Block-device linkage (`bdevsw` rows) | the core refuses block drivers (`drv_bcount` must be 0, `MAP` §6); the RAM disk needs one |
| 8 | `sd_register`: disk controllers register into the sd layer (§5) | no HBA registration exists (`MAP` §6) |
| 9 | `vfs_register` and a grown `vfssw` (§6) | no filesystem linkage exists |
| 10 | `intr_attach` / `intr_detach` with INT2 and INT6 chains (§4) | interrupts are platform-static in upstream (`MAP` §6) |
| 11 | Halt pass: call each module's halt entry, newest first, before the kernel halts or reboots | the halt hook is declared and filled by the wrapper macros but never called (`MAP` §3) |
| 12 | `fmodsw`: refuse rather than truncate when the kernel has more stock rows than expected | upstream truncates `fmodcnt` to 11 (`MAP` §6); ours is exactly 11 today (`L2`:280) |
| 13 | Per-module range checks in `inimg`/`okptr` and the cdev entry check | a pointer inside `[stext,end)` is not proof it belongs to a module (`STUDY` §2.5, C2-F1) |
| 14 | Pin by default: no unload unless the module declares `unload=allowed` and every registration it made is tracked | upstream has no auto-unload daemon and unload paths that need care (`MAP` §5) |
| 15 | Structure offsets generated, not hard-coded: a probe object compiled against the licensed headers at build time produces the `cdevsw`/`streamtab`/`qinit` offsets | upstream hard-codes AMIX 2.1 layouts and its host test reuses the same macros (`MAP` §6) |
| 16 | `marc_root` and `marc_post` passes driven by the arena directory and the manifest (§3) | upstream has no load point before first open (`MAP` §10.4) |

## 3. Load points

| Point | When | What loads | Source of bytes |
|---|---|---|---|
| `dmainit` (arm) | `startup()`, before `cred_init` and `init_tbl` (`STUDY` §2.2) | nothing; the core checks the symbol block and arms syscalls 64–69 only when `sysentsize` is 142 and the slots hold `nosys` (`MAP` §2) | — |
| `marc_root` (root class) | inside `rth1_mountroot`, before `rth1_apply` and therefore before `vfs_mountroot` (P-28 D3, D61) | every module in the arena directory: relocate in place, run `_load`; disk controllers call `sd_register`, filesystems call `vfs_register`; the RAM disk registers its block major | the arena, filled by the loader (`10-boot-loader.md` §5.3) |
| `rth1_apply` | unchanged | sd's first open closes controller registration (`sdopen(0)`) | — |
| `vfs_mountroot` | unchanged call | `rootfstype` is set from the loader record, so only the named type is tried (stock tries every row, s5 first, and reports the last errno, `grimoire-amix/docs/how-it-works/boot-process.md:312-332`) | — |
| `marc_post` (boot class) | after `vfs_mountroot` returns, in process 0, or from the first `sysinit` entry if file loading in process 0 proves unsafe (U15) | boot-class modules of the booted generation, SHA-256-checked against the manifest | `/stand/gen/<id>/mod/` on the root filesystem |
| first open (demand class) | on first open of a registered major | demand modules, SHA-256-checked | same directory |

In safe mode `marc_post` and demand loading are refused (`70-static-floor.md`
§4).

The `rth1_mountroot` hook is the driver line's own file on both lines,
already merged upstream unchanged as an opt-in pass; placing the `marc_root`
call before `rth1_apply` keeps both of its patch-check assertions true and
only adds an import to its relink pass (`tmp/2026-10-22-modules-proposal/refute-rth1-hook-ownership.md`;
`amix-040-060-port/src/rth1.c:210-215`).

## 4. Interrupt attachment

Today `int2_tbl` holds five handlers and a NULL and no INT6 chain exists for
Zorro boards: level 6 calls only the CIA-B handler (`L2`, `ttrap.s` reading).
The core pass installs:

- an INT2 chain walker in the table's last slot; static handlers stay where
  they are, attached modules run after them;
- an INT6 chain called after the CIA-B handler.

`intr_attach(level, handler, arg, name)` adds to a chain; `intr_detach`
removes. A handler returns whether it claimed the interrupt. A module that
cannot attach (or whose self-test of the attached handler fails) runs polled,
which stays the default for any driver that has a polled mode (Gayle IDE,
`amix-gayle-ide/docs/module-form.md`; z3660eth, P-28 risk 14). Attachment
during `marc_root` is allowed; enabling the board's interrupt waits until the
handler's self-test passes.

## 5. The sd card-number contract

### 5.1 Today

The stock sd layer keeps two controller slots (`SDCARDS 2`), one card bit in
the minor (bits: unit 0–2, card 3, slice 4–6; bit 7 unused), names disks
`c<card*8+unit>` in hexadecimal, sorts controllers by rank, and drops a third
with `sd: too many controllers`
(`tmp/2026-10-22-modules-proposal/refute-sdcards-ide-card-shift.md`;
`grimoire-amix/docs/drivers/kernel-composition.md`). On the 040/060 line the
rank is a fixed order: Z3660, then Zorro boards by address, then Gayle IDE
(rank key 0xfffffff0, `amix-040-060-port/src/ide_sd_glue040.s:17-24`); on the
030 line it is the board address, so the IDE (0xDD2020) sorts first. sd
registers lazily on first open; `rth1_apply` forces that open, so
registration closes there.

### 5.2 1.1: four controllers

D-3 §4 makes four root controllers modules (z3660scsi, A4091/A4092, Gayle
IDE, the A4000T onboard 53C710), beside the floor's WD33C93 controllers
(A3000 onboard, A2091). A box can carry three or four of them; two slots are
not enough.

| Rule | Content |
|---|---|
| Cards | four: minor bit 7 becomes the card's high bit; cards 0–1 keep today's minor numbers (`STUDY` §2.6) |
| Names | `c<card*8+unit>` in hexadecimal as today: cards 0–1 → `c0`–`cf`, cards 2–3 → `c10`–`c1f`; every tool that assumes one hex digit (`updbootpart`, the installer, `/etc/devnm` readers, the RTH1 kernel half's one-byte `bo_name` rewrite) moves to the general form |
| Order | **one rule on both lines**, by rank key, compacted over the controllers present: (1) Z3660 SCSI, (2) Zorro SCSI boards by board address, (3) the motherboard SCSI controller (A3000 WD33C93 or A4000T 53C710), (4) Gayle IDE. A box with one controller always has it as card 0, so the stock single-controller names (`c6d0` for a disk at SCSI id 6) are kept; the 1.0 040/060 names for two controllers are kept |
| Registration | `sd_register(queuefn, probefn, name, rankkey)` is accepted only before sd's first open; afterwards `EBUSY` and a console line. The floor's static controllers register through the same table |
| Rank keys | in the registry (`20-…` §6); a module's `rank` key in `.moddata` must match its class |
| Equivalence gate | for every board set of record, a module kernel names every disk exactly as the stage-1 static kernel built for that board set (`80-stages-and-proof.md` §2, stage 4) |
| Change detection | the manifest records the board set; when the booted board set differs, the loader prints it and `kbootset check` warns that device names may have moved. The root itself is found by identity (RTH1/RTO1 rule), not by name |

Trade-off recorded: with compacted order, adding a higher-ranked controller
moves the names of lower-ranked ones (an IDE-rooted box gains a Zorro SCSI
board: the IDE moves from card 0 to card 1). The alternative — a fixed card
per controller class — never moves names but gives the commonest single-
controller machines (A3000 alone, IDE alone) non-stock names and has no slot
for a second Zorro SCSI board. The compacted order is proposed; the choice is
OQ-30.2. On the 030 line the address order goes away: the IDE no longer
sorts first, and an A3000 with its onboard controller plus a Zorro SCSI board
now numbers the Zorro board card 0. This changes 1.0 names for such 030
boxes, which reinstall anyway (D-3 §5); whether the stock A3000UX convention
(onboard controller first) should instead outrank Zorro boards is part of
OQ-30.2.

The sd layer is a stock binary on the 040/060 line, patched in place, and
generated source on the 030 line (`amix-kerntools/templates/sd.c.in`, per
`L2`); the four-card change is a merge request to the 040/060 port.

## 6. Filesystems as modules

- **Targets:** ufs, s5 and cdfs become root-class (or demand-class, for
  cdfs on disk-rooted boxes) modules on both lines (D-3 §4).
- **030 line:** the relink kit separates cleanly — ufs has 82 globals and
  only `ufsinit` is referenced from outside (the `vfssw` row); s5 has 53 and
  is referenced through `s5init` and `inoinit` (`init_tbl`) (`L2` §2.5). The
  `inoinit` call becomes a filesystem-init hook the s5 module fills.
- **040/060 line:** the kernel is the fully linked stock binary; ufs and s5
  bytes are inside it (`L2` §2.5). Separation on our line means the base no
  longer registers its own ufs/s5 rows, and the modules (built from the same
  relocatable objects of the base) register instead; removing the dead bytes
  from the image needs the base rebuilt from relocatable parts, which is
  Antti's line (OQ-30.4).
- **`vfssw`:** 12 rows on 040, 13 on 030, no free row; on the 040 line cdfs
  today takes the RFS row by relocation retarget
  (`amix-040-060-port/src/patch_cdfs_vfssw.py:1-30`). The core grows the
  table into `.data`, retargets every reference, and raises `nfstype`; every
  walker of `vfssw` must read `nfstype` live (U12).
- **Root filesystem type:** from the manifest via the loader record; the
  kernel sets `rootfstype` (empty today, asserted empty by the stamper,
  `amix-kerntools/contracts/bootchain-v1.json:332-342`).
- **Merge target:** the separation is built on our line first; it is offered
  to Antti's base once stage 5 is proven, as passes he can take unchanged
  (D-3 §8).

## 7. The RAM disk

A root-class module (`ramdisk`, block major 21 and character major 54
proposed) presenting the image the loader placed (`10-boot-loader.md` §5.4)
as a disk. It maps the image by its physical address from the loader record,
never allocates it, and refuses to attach if the record is absent. Writable
(the miniroot needs a writable `/tmp`); contents are lost at power-off. The
RAM-disk driver is new code on both lines; no RAM disk exists in Amix today
(`review/P-6-compressed-miniroot-ramdisk.md`).

## 8. Memory classes

- **Arena (root class):** inside the kernel's `.data`; on the 040/060 line
  executed through ITT0 and accessed through DTT0 as cache-inhibited, as
  today's static drivers are (`STUDY` §2.3). Executing from `.data` through
  ITT0 is measured (U3).
- **Copied modules (boot and demand class):** ordinary kmem, copy-back
  cacheable; such modules get DMA memory only from `dma_alloc` and never
  assume virtual = physical (`STUDY` §2.3). After relocation the core
  publishes code with a full cache push (`cpusha bc`, plus CACR.CABC on the
  68060).
- **Kernel virtual space:** copied modules consume the fixed kernel map
  shared with page structures and u-areas; at 128 MB of RAM the headroom is
  measured (U2; `grimoire-amix/docs/how-it-works/ram-ceiling.md:86-110`).

## 9. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-30.1 | Is a no-sleep mode strictly needed at `dmainit` on our base, or only at `marc_root` (U1)? | us |
| OQ-30.2 | Compacted rank order (proposed) or fixed card per controller class for the four-card contract. | us; Antti reviews (sd is his binary on k46) |
| OQ-30.3 | The A4000T onboard 53C710 driver and its gated probe: does it exist in time for 1.1 (`amix-kerntools/docs/k0-families.md:1190-1195`)? | us |
| OQ-30.4 | Can Antti's base be rebuilt so ufs/s5 bytes leave the 040/060 image, or does 1.1 ship them dead in the image? | Antti |
| OQ-30.5 | Does the halt path, known to crash on `shutdown -i0` on the 040/060 base (`amix-040-060-port/README.md`), need fixing before the halt pass can be proven? | Antti; us |
| OQ-30.6 | Does ashnazag's author want the patches (arena path, no-sleep mode, `.moddata` v2, halt pass, `fmodsw` refusal, allowlist mode, shared registry) offered upstream? | ashnazag |
| OQ-30.7 | Upstream's `rth1.c` copy is byte-identical today; re-check before the merge request. | us |

## 10. Measurements

U1 (state at `dmainit` and at the hook), U2 (kernel VA at 128 MB), U3
(execution from `.data`), U12 (`vfssw` walkers and `nfstype`), U15 (file
loading in process 0), M-REG1, M-CORE1 (upstream host tests on our
toolchain), M-SD1 (equivalence over board sets) — `90-measurements.md`.
