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
| 17 | **Manifest-only loading.** Every load path — `modload`, dependency loads, `dlm_loadname`, and the first-open trampoline — resolves a module only as a member of the booted generation's manifest (the copy the loader placed in the arena, `10-boot-loader.md` §5.3), reads it from `/stand/gen/<id>/mod/`, and refuses it unless its SHA-256 matches the manifest; `modpath` no longer adds search directories. The only override is the **development-load** flag, set for one boot in the loader menu or by `kbootset next --devload`, carried in the loader record, and printed by the loader and by the kernel at boot and at every load it permits | upstream loads any file from `/etc/conf/mod.d` or a `modpath` directory through the VFS, unhashed (`MAP` §2, §5, §6). Members were checked against the catalog's SHA-256 when `kbootset` composed the generation (`60-signing-and-publishing.md` §3); with signing out of 1.1 (D-3 §13) this is integrity, not authenticity |

## 3. Load points

| Point | When | What loads | Source of bytes |
|---|---|---|---|
| `dmainit` (arm) | `startup()`, before `cred_init` and `init_tbl` (`STUDY` §2.2) | nothing; the core checks the symbol block and arms syscalls 64–69 only when `sysentsize` is 142 and the slots hold `nosys` (`MAP` §2) | — |
| `marc_root` (root class) | inside `rth1_mountroot`, before `rth1_apply` and therefore before `vfs_mountroot` (P-28 D3, D61) | every module in the arena directory: relocate in place, run `_load`; disk controllers call `sd_register`, filesystems call `vfs_register`; the RAM disk registers its block major | the arena, filled by the loader (`10-boot-loader.md` §5.3) |
| `rth1_apply` | extended (the driver line's own file) | sd's first open closes controller registration (`sdopen(0)`); then the loader record's **root selector** is applied: for an sd root, `rootdev` and the swap name are rewritten for cards 0–3 with the bit-7 encoding of §5.2; for a RAM-disk root, `rootdev` becomes block major 20 minor 0; for `swap none`, no swap device is configured (M-RD2). Without a loader record the 1.0 RTH1 behaviour is unchanged | — |
| `vfs_mountroot` | unchanged call | `rootfstype` is set from the loader record, so only the named type is tried (stock tries every row, s5 first, and reports the last errno, `grimoire-amix/docs/how-it-works/boot-process.md:312-332`) | — |
| `marc_post` (boot class) | from the first `sysinit` entry: `modadmin -B`, the modadm command `MOD_C_POST`, once a boot. U15 (S3-B5, 2026-10-26) found file loading in process 0 unsafe: the kernel's hook after `vfs_mountroot` runs with interrupts masked, and the module file's read faulted there. The hook now only says where the modules load (core patch 0017) | boot-class modules of the booted generation, SHA-256-checked against the arena copy of the manifest (patch 17) | `/stand/gen/<id>/mod/` on the root filesystem |
| first open (demand class) | on first open of a registered major | demand modules of the booted generation, SHA-256-checked (patch 17) | `/stand/gen/<id>/mod/` — the trampoline is redirected there from upstream's `/etc/conf/mod.d` |

In safe mode `marc_post` and demand loading are refused (`70-static-floor.md`
§4).

**The `sysinit` path is for the boot class only.** Root-class modules
(stage 4) cannot wait for init, because the root is mounted through them.
They keep `marc_root`, and that load point does not meet U15's wall: it
reads no file. boot2 has already placed their bytes in the arena (C3-4),
so the core only relocates and links them in memory, in process 0 inside
`rth1_mountroot`, with interrupts masked. Their `_load` therefore runs in
the context the floor's static drivers have in `init_tbl` today:
- no file I/O and no page fault: the code and data are in the arena or
  kmem, never behind the file system's mapping window;
- no sleep, and no `timeout`: the status register is at priority 7 and
  the clock stands still there (U1, 2026-10-26);
- allocation with `KM_NOSLEEP` only, each request at most 1 MiB (the k30
  line refuses 2 MiB there, U1), checked for failure;
- board probes polled, interrupts attached only after the self-test
  (§4), as now.

U1 measured that context (`docs/measurements/2026-10-26-u1.md`): the
same at `dmainit` and at the hook, on both lines. A
root-class driver that needs more than this context gives belongs to the
boot class, or loads its remainder from `_load`'s first open.

The `rth1_mountroot` hook is the driver line's own file on both lines,
already merged upstream unchanged as an opt-in pass; placing the `marc_root`
call before `rth1_apply` keeps both of its patch-check assertions true and
only adds an import to its relink pass (`tmp/2026-10-22-modules-proposal/refute-rth1-hook-ownership.md`;
`amix-040-060-port/src/rth1.c:210-215`).

## 4. Interrupt attachment

Today `int2_tbl` is a NULL-terminated table with no free entry — five
handlers on the 040/060 kernels (`L2`:247-248, asserted by
`patch_a3091_intr.py`), six in the 030 kit, which adds the Gayle IDE handler
(`amix-kerntools/work/cross-kernel-k030u-c6s1/usr/sys/master.d/kernel.c:190-197`)
— and no INT6 chain exists for Zorro boards: level 6 calls only the CIA-B
handler (`L2`:249). The core pass installs:

- an INT2 chain walker in the table's **last handler slot** (the entry before
  the NULL terminator, which stays): the handler it displaces is called first
  by the walker, the other static handlers stay where they are, and attached
  modules run after them;
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
| Minor encoding | unit = bits 0–2, card low bit = bit 3, slice = bits 4–6, card high bit = bit 7. The RTH1 kernel half today builds the root minor as `card << 3 | unit` with `SDCARDS 2` (`amix-040-060-port/src/rth1.c:31,99,195`), which for cards 2–3 would land in the slice bits; it moves to `(card & 1) << 3 | (card >> 1) << 7 | slice << 4 | unit` and loops over four cards |
| Drivers rebuilt for four cards | every array sized by `SDCARDS`: `sd` and `dd` (the disk layer), `ct` (tape), `a2091` and `a2090` (the floor WD33C93 drivers) (`tmp/2026-08-26-svr4-refs/amix-src/amiga/alien/{sd.h,sd.c,dd.c,ct.c,a2091.c,a2090.c}`), plus the RTH1 kernel half above. On the 030 line from the relink kit's source; on the 040/060 line as part of the base rebuild (§6) |
| Order | **one rule on both lines** (D-3 §11), by rank key, compacted over the controllers present: (1) Z3660 SCSI, (2) Zorro SCSI boards by board address, (3) the motherboard SCSI controller (A3000 WD33C93 or A4000T 53C710), (4) Gayle IDE — the 1.0 040/060 order extended. A box with one controller always has it as card 0, so the stock single-controller names (`c6d0` for a disk at SCSI id 6) are kept |
| Registration | `sd_register(queuefn, probefn, name, rankkey)` is accepted only before sd's first open; afterwards `EBUSY` and a console line. The floor's static controllers register through the same table |
| Rank keys | in the registry (`20-…` §6); a module's `rank` key in `.moddata` must match its class |
| Card-number gate | over the board sets of record (§5.3): see there (`80-stages-and-proof.md` §2, stage 4) |
| Change detection | the manifest records the board set; when the booted board set differs, the loader prints it and `kbootset check` warns that device names may have moved. The root itself is found by identity (RTH1/RTO1 rule), not by name |

**The 030 line (D-3 §11).** 1.0's 030 kernels numbered controllers by
board address, so the A3000 onboard controller (0xDD0000) and the Gayle IDE
(0xDD2020) sorted before any Zorro board. 1.1 uses the one rule above on both
lines: an A3000 with a Zorro SCSI board, or an IDE box with a Zorro SCSI
board, numbers the Zorro board card 0 and is renamed relative to 1.0. This is
accepted because every 1.0 box reinstalls (D-3 §5) and one rule serves the
installer, the composer, the card-number gate and the documentation.

Adding a higher-ranked controller later moves the names of
lower-ranked ones (the compacted order); the alternative of a fixed card per
controller class was considered and set aside because it gives the commonest
single-controller machines non-stock names and has no slot for a second
Zorro SCSI board. The root is found by identity regardless (§3).

### 5.3 Board sets of record and the card-number gate

A *board set of record* is a combination of disk controllers the project
supports and tests: on the 040/060 line Z3660 alone; Z3660 + A4091/A4092;
Z3660 + Gayle IDE; Z3660 + A4092 + Gayle IDE; Z3660 + A4000T 53C710; Z3660 +
A4000T 53C710 + A4092 (+ Gayle IDE); Gayle IDE alone; on the 030 line A3000
onboard alone; A3000 onboard + A4091; A4091 alone; A2091 alone; Gayle IDE
alone; Gayle IDE + A4091. The list is kept with the measurement rows (M-SD1)
and grows only by adding rows.

The stage-4 gate judges each set against one of three expectations:

1. **Order unchanged from 1.0** (every one- and two-controller set whose 1.0
   order the contract keeps): every disk has its 1.0 name.
2. **Accepted changes** (two-controller sets whose order the contract
   changes): on the 030 line, A3000 onboard + Zorro SCSI and Gayle IDE +
   Zorro SCSI (D-3 §11); the new names are listed per set in the measurement
   record and in the release notes.
3. **Three and four controllers** (1.0 dropped the third controller): judged
   against the contract's expected names, not against 1.0.

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
- **040/060 line:** the kernel is the stock binary, overridden and
  byte-patched, kept as one relocatable object with its full symbol table and
  relocations (`amix-kerntools/docs/040-kernel-line.md:10-22`); ufs and s5
  live inside it and no separate 4 KiB-page ufs/s5 objects exist (`L2`
  §2.5). **Our line rebuilds the 040/060 base so the 1.1 image carries no
  ufs/s5 bytes** (D-3 §4): the ufs and s5 code and data are carved out of the
  base object, with their relocations, into two relocatable objects that
  become the k46 `ufs` and `s5` modules, and the base is relinked without
  them. Feasibility (self-contained symbol ranges and relocations) is
  measured (M-FS1). Antti reviews the rebuilt base; he does not deliver it
  (OQ-30.4).
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

Stock Amix has a RAM disk: `ram.c`, block major 20, three units whose memory
is `kmem_alloc`ed at first open and freed at last close (stock
`tmp/2026-08-26-svr4-refs/amix-src/amiga/driver/ram.c:18,47,66`;
`master.d/kernel.c:307` there). It cannot present a pre-loaded image, and it
is not on the D-3 §4 floor.

1.1 replaces it with our `ramdisk` root-class module **on the same block
major 20**: unit 0 presents the image the loader placed
(`10-boot-loader.md` §5.4), mapped by its physical address from the loader
record and never allocated or freed; units 1–2 keep the stock behaviour
(kmem-backed scratch disks). The stock `ram` driver leaves the base (on the
040/060 line with the base rebuild of §6). Writable (the miniroot needs a
writable `/tmp`); contents are lost at power-off. P-6's premise that "Amix
has no RAM-disk driver" is corrected here: it has one, but not one that can
root on a loaded image (`review/P-6-compressed-miniroot-ramdisk.md`).

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
- **Kernel virtual space (U2, 2026-10-26):** copied modules consume the
  fixed kernel map shared with page structures and u-areas
  (`grimoire-amix/docs/how-it-works/ram-ceiling.md:86-110`). In process
  context after multi-user a module gets about 320 KiB in total on k46
  at 128 MB and 640 KiB on k30 at 64 MB (64 KiB `KM_NOSLEEP` pieces;
  `docs/measurements/2026-10-26-u2.md`).
  - A load from a file (`modload`, a demand-class first open) holds the
    core's working set at once, all `KM_SLEEP`: the file rounded up to a
    power of two, the symbol tables, the image and the module's table.
    That is about 57 KB for z3660eth, 67 KB for z3660rtg and 232 KB for
    a cdfs-sized module.
  - A module loaded in process context keeps that working set well
    under k46's total. A load past the total waits instead of failing,
    as U4's `KM_SLEEP` request did. C3-1 §6's 256 KiB is a ceiling, not
    a budget: a module at it cannot load this way on k46.
  - A larger module is boot class (the first `sysinit` entry, before
    multi-user) or root class (stage 4, from the arena: no kmem for its
    file or image). The totals there are not measured; U1's single
    `KM_NOSLEEP` requests of 1 MiB (k30) and 2 MiB (k46) succeed at
    `dmainit` and the hook.
- **Large requests (U4, 2026-10-26):** in process context after multi-user
  one kmem request gives at most 256 KiB on k46 at 128 MB and 512 KiB on
  k30 at 64 MB. A `KM_SLEEP` request above that sleeps forever.
  - A module's requests are at most 256 KiB each, on both lines. A larger
    need is split.
  - `KM_SLEEP` is only for requests up to 256 KiB, and every `KM_NOSLEEP`
    request is checked.
  - Root-class `_load` at boot keeps its own rule (§3, U1: `KM_NOSLEEP`,
    at most 1 MiB).
  - The core's own allocations for a module grow with its size and are
    `KM_SLEEP`. So the module's image is at most 256 KiB and its file is
    under 256 KiB (C3-1 §6, version 4; it was 2 MiB). The kit's checker
    refuses a larger module at build time. Core patch 0027 sets
    `dlm_maximage` to 256 KiB from the next kernel cut. C3-1 §6 records
    the way past the limit, which no planned module needs (cdfs, the
    largest, has an image of about 69 KB).

## 9. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-30.1 | Is a no-sleep mode strictly needed at `dmainit` on our base, or only at `marc_root` (U1)? | us |
| OQ-30.3 | The A4000T onboard 53C710 driver and its gated probe: does it exist in time for 1.1 (`amix-kerntools/docs/k0-families.md:1190-1195`)? | us |
| OQ-30.4 | Antti's review of the rebuilt 040/060 base without ufs/s5 (carving method, gates, acceptance record per his `docs/ACCEPTANCE.md`). | us build; Antti reviews |
| OQ-30.5 | Does the halt path, known to crash on `shutdown -i0` on the 040/060 base (`amix-040-060-port/README.md`), need fixing before the halt pass can be proven? | Antti; us |
| OQ-30.6 | Does ashnazag's author want the patches (arena path, no-sleep mode, `.moddata` v2, halt pass, `fmodsw` refusal, allowlist mode, shared registry) offered upstream? | ashnazag |
| OQ-30.7 | Upstream's `rth1.c` copy is byte-identical today; re-check before the merge request. | us |

## 10. Measurements

U1 (state at `dmainit` and at the hook), U2 (kernel VA at 128 MB), U3
(execution from `.data`), U12 (`vfssw` walkers and `nfstype`), U15 (file
loading in process 0), M-REG1, M-CORE1 (upstream host tests on our
toolchain), M-SD1 (card-number gate over board sets), M-FS1 (ufs/s5 carved
from the 040/060 base), M-RD2 (root selector), M-SIG3 (manifest-only
loading) — `90-measurements.md`.
