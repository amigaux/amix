# Changelog

## Unreleased

## 2026-10-26 — stage-3 audit of the rows reported done; 30 §3 root-class context (f98c1ac, 4fea711)

Audit (docs/plan/stage-3-audit-2026-10-26.md): of 14 rows reported done, 7 are done (S3-01, 02, 04, 08, 09, 11, 15) and
7 half (S3-03 errnos/console lines/param forms; S3-05 drv_cmajor unchecked; S3-06 range checks not implemented, registrations
untracked; S3-07 devload vs C3-4; S3-10 no sample driver; S3-16 gate 6 misses ET_REL bss; S3-40 records). Seven kernel fixes
proposed for the final cut (patches 0018–0020). 30 §3: the sysinit path is boot class only; root-class modules load from the
arena in marc_root (no file I/O, floor init_tbl rules), U1 measures that context before stage 4 relies on it.

## 2026-10-26 — core patch 0017: boot-class modules load from the first sysinit entry (cf762a3..bcd6f0d)

S3-B5's panic (N50): the kernel's hook after vfs_mountroot read the module file in process 0 at IPL 7, where the file system
cannot bring a page in — U15's question, answered. Boot-class modules now load from /etc/inittab's first sysinit line via
`modadmin -B` (modadm MOD_C_POST, root only, once a boot; a second call is EBUSY); the hook loads nothing while interrupts
are masked and says so. C3-5 v3, spec 30 §3, U15 in 90, brief step 8, C2-4 §11. Harness 162/162 both kernels; 665 host
checks; box modadmin a206874d. The media need /sbin/modadmin and `dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1`.

## 2026-10-26 — core patch 0016: pin by default (31e5676)

The module core pins modules by default, as C3-1 §2 says: a module that does not declare unload=allowed is refused by
moduload with EBUSY (moduload(0) leaves it) and modstat reports it locked. Before this the key was parsed but not enforced,
so any idle module could be unloaded — S3-06 had been counted done with only its range-check half in place. State harness
160/160 both kernels; make core 119/119; 665 host checks. Not in the kernels re-cut on e86c9c4.

## 2026-10-26 — k46.1.0 fingerprint rewritten from the re-cut; abi= required at gate 2; C3-3 v4 (3ee2fe4, a28d5ab)

k46.1.0's reference is rewritten once from the re-cut KD060-Z: cputype's size went 0 → 4 and nothing else moved; it now
equals k30's (abi=7a90c7d9…). kbootset refuses a module kernel whose sidecar has no abi= (gate 2); s3-standin.sh requires
the key. C3-3 v4: abi= required, the k46.1.0 reference closed, equal fingerprints across lines expected (the kabi tag tells
the lines apart). Both re-cut kernels compose through the new gate. 665 host checks; make core 119/119; KIT_REV=a28d5ab.
Box kbootset 45909ae5.

## 2026-10-26 — modadmin for the box (S3-11); C2-4 version 8 (55722ef, cdf29fd)

The core's modadmin built with GCC 14, static like kbootset, its six system calls through the stock syscall(); core patch
0015 adds -k (a symbol's address: the kernel's exported names, then each loaded module's globals), -a (the symbol at an
address) and -p/-w (read or write longs at a symbol through /dev/kmem), so a module's tunables and counters are reached by
name. Box modadmin d94e5228 (68060-safe). C2-4 v8: module members in build, commit, media -R and status. New bench row S3-B6.

## 2026-10-26 — kbootset media composes the installed modules; kit LOCALIZE check (a64aee1, d6985be)

`kbootset media` (disk, floppy pair, CD) composes the installed module packages into the medium's pristine generation as
`build` does (gates 1–3, the parameters), writes the module and param records into the spec and copies the objects to the
root tree's /stand/gen/1/mod/ — S3-31's input. The kit's make fragment refuses LOCALIZE up front when its objcopy is missing,
naming the tool and the gcc14-cross-amix path. 665 host checks; kit-test 35/35; box kbootset 305345a3; KIT_REV=d6985be.

## 2026-10-26 — the kernel fingerprint abi= (C3-3 version 3) (9a45f1b, bd65e6b)

The text: sorted lines `data <name> <st_size>` for each DDI data name plus `offs <NAME> <value>` from the probe's dlm_offs.h;
abi= is its SHA-256, in the sidecar only. tools/mkabi.py checks a kernel against abi/<line>/abi-<kabi>.txt, naming what moved
and the tag change it needs (brief step 9; it writes the sidecar's abi= at step 11). References from the cut kernels: k46.1.0
04b52092…, k30.1.0 7a90c7d9… (10 data lines, 19 offsets). The kit ships mkabi.py, the reference, the probe and mkoffs;
kbootset refuses a malformed abi= at gate 2. make core 119/119, kit-test 33/33, 665 host checks. KIT_REV=bd65e6b.

## 2026-10-26 — kbootset composes module members (S3-16); bench row S3-B5 (a71a875, 2410287)

`build` takes every module object under /etc/conf/mod.d (unless modreg disables it) through gates 1–3 (record; kabi
family/major/minor, compiler pin, core-tier build, parameters normalized to C3-1 §3; match= on boot class, registered
majors= on demand class, depend closure, no root class), copies them to /stand/gen/<id>/mod/ and writes module and param
records in depend order; `commit` re-verifies; `status` marks members loaded or not from kinfo. 665 host checks; host
rehearsal with the real z3660eth members on both cut kernels. S3-B5 = the first module generation (z3660eth alone),
tests/bench/s3-modpkg.sh. Box kbootset 8cb4c157. Owed: media builds composing modules (S3-31's pristine generation).

## 2026-10-26 — kit: per-line MODOUT and objects, COMMON warning by prefix, clean guard (d197198)

A build's objects and module live under build/<line> and rebuild when the kit changes, so one module directory builds for
both kits; the COMMON warning names only symbols outside the module's own names; clean refuses MODOUT=.; modcheck names a
missing scan060/objdump in one line. C3-6 §2: z3660eth's _load may return ENOMEM, if_detach only with an _unload. kit-test
31/31; kits rebuilt, KIT_REV=d197198.

## 2026-10-26 — kernel printf formats %d %x %s only; kit fixes (2c62201, c722e41)

The module core prints only the formats the 1992 kernel printf has: the arena line reads "modules from generation N's manifest"
again (patch 0009 %ld → %d with a cast; patch 0006 %c → %s). tools/prfcheck.py in make test and make core refuses any other
conversion in kernel-side code; make core 115/115. Kit: a Master without $cpu gets the line's default (DEFCPU, MODCPU
override); a kit built from uncommitted inputs labels itself -dirty; the guide covers DEPS and the modfix message,
LOCALIZE_OBJCOPY, the "amiga/console/…" include form and where the %.o rule looks. Kits rebuilt: KIT_REV=c722e41.

## 2026-10-26 — the ABI kit (S3-10) (8c9172d, 418ead5)

`make kit` builds a kit per line: the module core's headers, sys/amixddi.h (DDI v1; the stock sysroot already has a sys/ddi.h
with the same guard), the stock headers from the pinned sysroot (k46 with the port's 4 KiB immu.h/param.h), a linkable stock
Sun font built at kit time by tools/sunfont.py (font bytes in .data, not .text), mkmod (core patch 0014), modfix, modcheck.py,
mk/module.mk, sample/hello, ddi.md and writing-a-module.md. modcheck scans a PROGBITS copy (binutils 2.8.1 cannot read a
type-13 .moddata) and fails an empty scan; DDI_CPUTYPE reads cputype as the long it is. `make kit-test` 29/29, the sample
loads against both module kernels' symbol blocks. Nothing stock is tracked. Owed: the probe module and the abi= fingerprint.

## 2026-10-26 — C3-6 v2 takes z3660eth's findings; C3-1/C3-5 v2 param value forms; 10 §7.2 L9; 40 gate 5 (609ccc7, ce94b5c)

C3-6: the STREAMS row is zeros except d_str; z3660eth_int6/int2 are the handlers, attached at first open after the software
EXTER self-test (INTREQ 0xa000); param intrl2; ZZ_CONFIG_DISABLE acknowledges and masks; the kit's k46 immu.h/param.h are the
port's 4 KiB forms. C3-1/C3-5 v2: every param value is normalized (bool exactly 0 or 1; kbootset accepts 0/1, yes/no,
true/false, on/off and refuses the rest at gate 2 — lands with S3-16). Spec 10 §7.2: a trial refused before it starts (L9,
like L1/L2/L3/L6/L14) spends its attempt. Spec 40 gate 5: a 4 MiB store holds a module generation only beside a deflated
generation 1. Bench rows: RECNAME in s3-standin.sh, arena line before the symbol count, the rc2 hook's line is the one of
record, S3-B4 checked through kinfo offset 84.

## 2026-10-26 — C3-6 version 2: the console hook's cp is the console (3d809d7)

A hook takes only writes where cp->screen == displayedscreen (C3-2's row and patch 0011's comment say the same); _halt is
void; z3660rtg's _unload calls monsw_unregister, the module is built without ZZ9K_NO_BUILTINFONT with builtinfont made local,
ENABLE equals REDIRECT and the hook takes VT writes by design, params blit:bool:1 and maxarea:int; a weak undefined symbol is
allowed (§1.6).

## 2026-10-26 — C3-6: what a driver changes to become a module (e511cdf..4834304)

C3-6 agreed, version 1: the wrapper and _load/_unload/_halt; majors from .moddata; intr_attach with polled as the default and
the level-6 rule (no spl masks level 6, so a level-6 handler acknowledges, masks and flags, and calls no DDI function; the
work runs at level 4 or below); cons_hook_set; device windows without a DMA interface; allowlisted symbols only; the kit.
Checklists for z3660eth (boot, unload=never, if_attach, param intr), z3660rtg (demand, depend=monsw, cons_hook with the
displayedscreen check, one module with a run-time probe, unload=allowed) and monsw (demand, unload=never, param config).
Brief step 8 names KINFO_DLM. Plan rows S3-25/S3-26 follow DDI v1 without dma_*.

## 2026-10-26 — C3-3 v2; brief and C2-1 take the cut findings; stage-3 boot rows (7ee4c59..edd9599)

C3-3 version 2: a stage-3 module kernel writes root=/rootfs=, and the first root-class module in a generation is the stage-4
trigger for gate 3. The kernel brief takes the S3-20/S3-21 findings: post-link steps after the last size-changing step,
RTH1_DLM, the splice derived from the core's own definitions, the layout rule (.text, .rodata, .data, no padding), addresses
only from nm. C2-1 caps the module list at 32 and says when it is fresh. 40's gate 5 notes the module kernel's store size
(4 MiB holds one static plus one module generation). New bench rows S3-B1–B4 and tests/bench/s3-standin.sh, rehearsed on the
host with both cut kernels bound by the loader's relocator at two addresses.

## 2026-10-26 — Loader version 2; kbootset sidecar v5 (9febccf..124b86c)

boot2 checks a module kernel's identity record (AXK1) against the manifest (L14 on a mismatch) and fills the arena's AXA1
directory and manifest copy; L5 gives the bytes needed and available. The "amix-boot: " prefix is printed in one place
(con_say), saving 308 B: image 27020 + table 1080, bss 1380, 272 B under the 28 KiB gate. b2check 538 relocations at two
binds. kbootset reads sidecar v5 (ident=; arena=/ident=/loader-min=2 together), writes the manifest's arena and ident records,
gate 4 checks the manifest copy fits the arena; loader version 2 is the default of kbootset and mkstore (store.h). 665 host
checks. Spec change after freeze: 10 gains the ident record and L14 (C3-3).

## 2026-10-26 — §1 of the kernel brief complete: core/plat, mkident, patch 0013, M-REG1 fix, dry-run answers (771fe15..db0abef)

core/plat (amiga.c: AXL1 safe/devload, build id, board matcher; per-line line.c: k46 buildid, k30 kinfo_buildid and cputype),
host-tested. tools/mkident.py (AXK1 and the arena: --asm/--fill/--check). Core patch 0013: 4-byte symbol block, strong hooksw,
no weak plat_dmainit default, dlm_kinfo_list() for kinfo's module list. M-REG1 counts a cdevsw row filled at boot (major 51 is
z3660eth's at run time on the static Z families; record corrected). The gate rehearses the brief's whole step 7 on both
kernels: nothing stubbed, no weak symbol, 12/12 at both binds; `make core` 114/114. The brief answers the port's dry run
(§3a): 4-byte alignment, .rodata fold, chain order, kinfo kabi and module list.

## 2026-10-26 — DDI v1 decisions applied; module core patch 0012: intr_attach (2cb274e, 1257dd9)

DDI v1 (C3-2, abi lists 80/78 names, review draft, brief): dma_alloc/free/prepare/complete removed (stage-4 design with the
port; the port's dma_prepare/complete stay kernel-internal); displayedscreen added (data, read-only); spl5–7 raise to level 4
only, so no spl masks level 6 and an INT6 driver masks at its board. Patch 0012: intr_attach/intr_detach — a level-2 chain
walk in int2_tbl's last handler slot calls the displaced handler first; a level-6 chain sits behind a wrapper at the stock
aciabintr (weakened, __amix_aciabintr; p6int is its only caller); every handler is called every time, claims counted; chains
change at IPL 7. Harness 154/154; gate 12/12 with intr_* linked for real.

## 2026-10-26 — module core patch 0011: the DDI providers spl, if_attach, cons_hook; C3-5 agreed (887981b..cde866e)

spl0–7/splx as functions identical to <sys/inline.h> (spl5–7 raise to level 4 under FAST_INTERRUPTS, so no spl masks INT6);
if_attach/if_detach on the stock ifstats list at IPL 7; cons_hook_set/clear through a wrapper at the stock scrcon_put (both
VT writes and the printf funnel), which the kernel build weakens and keeps as __amix_scrcon_put. With these linked for real
the ksym gate is 12/12 on both kernels. C3-5 agreed, version 1. Kernel brief: the scrcon_put splice, libgcc.a and
devkvmap040.o on k46, cputype from core/plat on k30.

## 2026-10-26 — module core patch 0010: marc_post; contract C3-5; the S3-20/S3-21 kernel brief (1038d5f..23d0bc1)

dlm_marc_post() registers the demand-class majors from the booted manifest, then loads the boot-class records in manifest
order unless match= names no board here (the platform's matcher), one console line each; in safe mode nothing loads and every
other load is refused; a member's param records reach its _load as one string. Contract C3-5, the module package and the
manifest's module record (agreed on the report: match=/majors=/depend=/tier=+build= copied verbatim from .moddata, gate 3
refusals, no GMF1 or loader-min change, order and reporting through kinfo). docs/plan/stage-3-kernel-brief.md: the 11 build
steps, the providers per kernel and the acceptance for the first module kernels. Harness 146/146 both lines.

## 2026-10-26 — module core patch 0009: manifest-only loading and development load (9d1528b)

Every load (modload, dependency, dlm_loadname, first open) resolves a module only as a member of the manifest the loader
booted: the bytes come from its path=, read once, checked against its sha256=, and that copy is what loads; anything else is
EPERM with a console line. The manifest is the loader's verbatim copy in the arena, found through AXK1 and checked at dmainit
(C3-4); with no valid arena no module loads that boot. The development-load flag (from AXL1) lets an off-manifest module load
and says so each time. New dlm_arena.c; sha256.o and crc32.o from loader/common in the core. 104/104, harness 140/140.

## 2026-10-26 — module core patches 0006–0008: major registry, fmodsw kept whole, measured layouts (27b471e..95657b0)

DDI v1 review draft gains the module-interface row (as C3-2; still unsent). Patch 0006: a module's majors= must be registered
to it (abi/registry/majors: c 49 z3660rtg, c 51 z3660eth, c 52 monsw, c 53 kinfo, b 20 ramdisk; tools/mkreg; ECONFIG
otherwise). Patch 0007: fmodsw keeps every stock row, never truncates (more than the table holds panics at dmainit; not
host-testable, read-verified). Patch 0008: the structure layouts the core reads are measured by the kernel's compiler from the
kernel's headers (dlmoffs.c, tools/mkoffs); all 19 equal upstream's values on the 2.1 sysroot. `make core` 104/104, harness
129/129, both lines.

## 2026-10-26 — module core patch 0005: the allowlisted symbol block (C3-2); DDI v1 lists; the gate (a0fb839, f7b5596)

Kernel symbol block version 2, generated before the final link from the allowlist (mkksym -a) with the values as relocations
bound by the loader; mkksym -f fills sizes; st_other is the tier, core-tier names resolve only for core-tier modules;
dlm_init checks the block against dlm_ksym_space. abi/k46 and abi/k30 ddi.list (DDI v1: 83 / 79 names) and core.list.
tools/ksymgate.py binds the kernel twice with the loader's own relocator and checks every name (12/12 both binds).
C3-2 correction: the module interface (mod_*ops, mod_hold, mod_rele; provider the core) belongs to DDI v1. `make core`
103/103 both lines; dlm.o data 165 KB → 1.9 KB.

## 2026-10-26 — module core patches 0002–0004: platform split, .moddata v2 (C3-1), ENOLOAD (58b42fb..dbc3d74)

Patch 0002 takes ashnazag's guest registrations out of dlm_init (30 §2 patch 1); plat_dmainit is the platform's place.
Patch 0003 brings .moddata version 2 and wrapper revision 2: every C3-1 key checked, the module checked against the kernel
(name, kabi family/major/minor, compiler pin, core-tier build id), root class refused until the arena path; mkmod writes v2,
modfix checks it; dlmconf.c takes DLM_KABI/DLM_PIN from the kernel build. Patch 0004: non-module files are refused with
ENOLOAD (C3-1 §4). M-CORE1 87/87 on both lines; state harness 124/124; dlm.o text 28 268 B.

## 2026-10-26 — stage 3 begins: the module core imported, patch 0001, M-CORE1 (becf104..9626629)

core/: kdedon's MIT DLM core (ashnazag kernel/dlm at b736c59) imported unmodified with upstream's LICENSE, the base of the
patch queue; patch 0001 makes the trampolines' hold volatile across longjmp (GCC 15 -O kept it in a register; GCC 2.7.2.3 did
not). M-CORE1 closed on both lines: `make core` runs upstream's host tests on our toolchains against KD060-Z and K030-U, 87
checks pass (mkmod 4/4, oracle 7/7 byte-identical, error paths 29/29, state harness 105/105 per kernel).

## 2026-10-26 — stage 2's exit met on the emulator; C2-4 v7: commit no-op and `commit --again` (db91add..f43fe08)

S2-46 passes on k30 (row N45, the installer's v10 disk): stage 2's exit gate is met on the emulator on both lines; the metal
rows S1-26, S1-27 and S2-47 stay open for the owner's bench time. kbootset commit writes nothing when the built generation
equals the default (compared through the loader's parser: members by size and SHA-256, the facts, the parameters) and says
"the default generation M already has these members; nothing to commit"; `commit --again` commits it all the same (a repair,
a row). C2-4 version 7; apkg needs no change. Bench recipes use `commit --again` where a row needs an equal generation.
Box kbootset a2970b2000e6c505.

## 2026-10-26 — M-GEN5 closed on both lines; M-GEN3 N=7 on k30; ledger k30 cells (44f7c49, f486028)

k30 row N43: the unit-5 trial panics at mountroot (errno 30 = EROFS, the last vfssw row's errno; k46 reports 89) and L8 falls
back to the pristine generation, end state exact. M-GEN3's N=7 cell passes on k30 (N44: the trial boots through the fsck
reboot, the rc2 hook marks it good). Ledger: k30 lifecycle and power-cut cells; S2-46 k30 waits for the installer's v10 disk
(kbootset and loader-amix as packages); the `-f install` variant is supporting evidence only.

## 2026-10-26 — sha256.c reverted: the restructured round is slower on the 030 (fb77acd, 16f2bde)

Hashbench run 2 on the cycle-exact 25 MHz 68030: the restructured round ran at 237 KiB/s with GCC 2.7.2.3 (was 534) and 176
with GCC 14 -O2 (was 270); host instruction counts did not predict the 68030. Reverted to the shifting round; GCC 14's factor
of two on it stands as accepted cost; any later attempt is designed against the bench, hashbench per candidate first. The
no-kinfo fixes stay.

## 2026-10-26 — ledger k46 complete; SHA-256 restructured; kbootset without kinfo; C2-4 §9; k30 recipes (8b42bcc..6c69125)

Exit ledger: M-UPG1 k46 passed, the k46 column complete. Hashbench run 1: GCC 14's SHA-256 at half GCC 2.7.2.3's rate on
the 030 (codegen, not I/O). sha256.c restructured: the full schedule first, eight renamed rounds per pass, nothing shifted —
42–45 instructions per round instead of 102 under both compilers; correct against hashlib. kbootset without kinfo: retry
exits 0 quietly (C2-4 §7), mark-good refuses with status 3 and names --booted. C2-4 §9: the end-of-rc2 mark-good hook. Bench
recipes for the k30 line (S2-46, S2-41 with K030-IDE as the bad trial, one S2-42 cell); they need an l11-k30 disk whose
pristine kernel is kernel-k30-u. hashbench tool untouched; hashbench re-run pending.

## 2026-10-26 — C3-1..C3-4 agreed; S3-40 host half; DDI v1 for review (a1c7678..de519de)

C3-1..C3-4 agreed (version 1). S3-40 host half over the ten kernels of record: one k46 ABI for 68040 and 68060 (the two
kernels differ in one byte, OQ-20.2 closed), every registry value confirmed (sysent 142 with 64–69 free, cdevsw 70 rows,
majors 51 and 53 free everywhere), the switch tables movable (U5), elf2brel carries the symbol block (M-ABI2), arena
capacity 0x60000 on both lines (M-MOD1; a module kernel is 384 KiB larger raw, a 64 MiB store still holds ~28). 20 §2 gains
tier and build; major 53 confirmed free. docs/abi/ddi-v1-review.md: the stage-3 export list, self-contained, for the
collaborator's review.

## 2026-10-26 — M-GEN2 record; stage-3 answers; contract drafts C3-1..C3-4 (b5570bc..a71d221)

M-GEN2 bench half: a k30 commit 16.7 s (median; 11.2 s CPU) and check 16.0 s on the cycle-exact 25 MHz 68030; the GCC 14 box
binary hashes at about a third of the loader's C rate (cause unmeasured, queued). s2-standin.sh takes a brel's bss. 80 §2:
intr_attach is built in stage 3 and reused by stage 4 (spec change after freeze). Stage-3 plan: Q3-1/Q3-4 settled, monsw
planned in amix-z3660rtg until P-8 (c). Contract drafts for agreement: C3-1 module object and .moddata v2 (MD2), C3-2 the
allowlisted symbol block generated before the final link with loader-relocated addresses + DDI v1, C3-3 the AXK1 identity
record and sidecar v5 (loader code L14), C3-4 the AXA1 arena directory and manifest copy.

## 2026-10-26 — stage-3 plan: the module core (aca2460; ledger 737df5a, db58c28)

docs/plan/stage-3.md: work breakdown for the module core as a patch queue on kdedon's MIT core b736c59, the ABI kit, module
kernels with the arena and the allowlisted symbol block, the composer and loader side (AXA1 + the manifest copy),
z3660eth/z3660rtg/monsw as the first copied modules, the measurements, and interface drafts C3-1 to C3-6. Exit ledger: the
installer's citations; M-UPG1 k30 cites the upgbox first boot, k46 open.

## 2026-10-26 — stage-2 bench records and the exit ledger (deea18c..eb8f006)

S2-46 record: a box upgraded and rolled back with apkg alone (k46); the first run's journal failure kept as the finding
behind d64bad7. M-GEN5 closed on the bench for k46: a trial that cannot mount its root panics and reboots by itself and the
loader falls back to the good default (L8) on the same boot; recipe matched to the machine. M-GEN2 bench recipe (timed
commits per line). Stage-2 plan §4: the exit ledger — one line per 80 §2 emulator item with k46/k30 columns and the record
for each, including apkg's SHA-256 refusal row (altered byte and altered catalog hash both refused, rc 3, nothing written).

## 2026-10-26 — kbootset makes the journal's directories (S2-46); M-GEN5 recipe (cb82bff..d64bad7)

kbootset makes the journal's missing directories (0755) whenever it writes the journal, named with --journal (apkg's form)
or default — the exit row's trigger failed with "cannot write the journal" on a box that had never run kbootset (C2-4 §2
wording, no version bump). M-GEN5 recipe: `mark-bad 2` before the bad trial on a 4 MiB vehicle (collect frees nothing of
the kept set); spec change after freeze 40 §2.1: boot slices under the 64 MiB store boot but do not hold the kept set.

## 2026-10-26 — kbootset create zeroes and refuses; status prints the set id (C2-4 v6) (29e2c9f, 8ccee80)

`create` refuses a slice that already holds a boot store or a DOS bootblock (status 3) and with --force zeroes the first
64 KiB first, so nothing of an earlier chain survives; `media --disk` takes --force too. `status` prints `store-id: <8 hex>`
(the header's set id, as /etc/default/bootset records it) so the installer need not recompute it. 660 host checks.

## 2026-10-26 — kbootset retry: the fsck-repair reboot does not spend a trial (8f50dad..d5d4203; also 9632232, 42e9fb1, 4cae4f2)

M-GEN3 on the rig: every power-cut point (before steps 1, 2, 4, 5, 7) leaves a booting generation. Finding at the cut after
the commit point: the stock /sbin/bcheckrc always reboots after a root fsck repair, and that reboot spent the trial's single
try-once attempt. Fix (spec change after freeze 10 §7; C2-4 v5 §7): bcheckrc calls `kbootset retry` before each uadmin that
follows a root repair; if the booted generation is the trial on its attempt, the attempt is given back (at most twice per
trial, counted in the generation's flags), so a root that never stays clean still ends in L8 after three tries; retry writes
only the control block. Loader unchanged. Also: vehicles carry a brel's bss=; mkstore stores raw when deflate does not help;
make box checks for 040/060-only FPU forms; kbootset executes FPU instructions (FPE in the floor). 658 host checks.

## 2026-10-26 — a brel kernel's bss; contracts C2-3 v4, C2-2 v4; the exit row (84315bb..bf7f93f)

The brel format has no bss (elf2brel writes text+rodata+data and relocations only), so boot2's room check undercounted a
brel kernel by 270–345 KB. Fix: the manifest's kernel record carries bss= for a brel (spec change after freeze 10 §5.1);
boot2 adds it before the room check (512 KiB assumed with a printed line when absent); kbootset reads bss= from the sidecar,
refuses a brel without it (gate 2), counts it in gate 6 and writes it on the manifest. boot2's self-relocation table moved to
16-bit offsets (27 434 B, 1 238 B margin; b2check on the real boot2 at two bases in every make all). C2-3 v4: the kernel
build writes the sidecar for the form it ships (size/sha256 of that file, bss= from the ELF); C2-2 v4: the install record
file is /var/apkg/kpkg/<pkginst> (s5 14-char names). S2-46 exit row written with the S2-12 packages. 640 host checks.

## 2026-10-26 — /dev/kinfo: made by the installer, and by kbootset when missing (fb9c1ce..a96427d)

M-GEN3 power-cut rows in the rig's cut shape (holds before steps 1, 2, 4, 5, 7); kbootset creates /var/kbootset for its
default journal. C2-3 v3 §1: the kernel package does not carry /dev/kinfo (a device node is not a pure file); the installer
and the upgrade install make it (c 53 0, 0444, root:sys). C2-4 v4 §2: on the running box kbootset makes /dev/kinfo when it
is missing and says so; when it cannot, the facts come from /etc/default/bootset and the options. Box build uses mknod with
makedevice(53, 0).

## 2026-10-26 — stage-2 records and row recipes (64a9881, 47abc38)

M-GEN1 (stage 2): a static generation is 1.26–1.27 MB (k30 brel), 1.93–2.08 MB (k46 ET_REL) or 1.41–1.52 MB (k46 brel)
raw plus one manifest extent; a 64 MiB store holds ≥ 32, the 1.0 10 MiB slice five ET_REL k46 generations. M-GEN4: kbootset
one GCC 14 static binary for both lines, 119 388 B stripped. M-SIG2 bench half: SHA-256 540 KiB/s on the 25 MHz 030 model,
kbootset check of a k46 generation about 3.8 s. tests/bench/s2-standin.sh: a stand-in kernel package + apkg record until
S2-12. README "Stage 2": the M-GEN5 lifecycle row (seven boots), the M-GEN3 power-cut rows (hold at steps 1, 2, 4, 5, 7) and
the exit row (apkg upgrade → trigger → power-cycle → mark-good → rollback).

## 2026-10-26 — kbootset on the running box (S2-06); C2-4 v3 (efb7629, c7b7319)

Without --image/--dev kbootset reads /dev/kinfo (C2-1 v2, checked), finds the boot store (bootset's store= when the slice
still carries store-id=; else the loader record's boot device through kinfo's card table, the disk's RDB and the partition at
AXL1's start; else a scan of every disk for exactly one UNI\0 store), gate 9 (two UNI\0 slices on the boot disk) and gate 8
(no or several candidates), writes store=/store-id= back, takes the box facts from options, then kinfo, then bootset; the
journal defaults to <root>/var/kbootset/journal; mark-good defaults --booted to AXL1's generation. C2-4 v3: §2 the box
form, §6 /etc/default/bootset. tests/host/kbox.sh on a real RDB image with synthesized kinfo records, checked field by field
against the port's real record. 109 680 B text.

## 2026-10-26 — chip-only refusal; contracts C2-2/C2-4 v2; M-LD5 and M-LD8 closed (cba01a4..9b87bef)

boot2 never binds the kernel in chip memory: no fast region, or a kernel larger than the largest one, is L4 with a line
saying which; the control blocks move into the work area (spec change after freeze 10 §3.2). C2-2 v2: optional pkginst=
and offset=. C2-4 v2: bootset= read from <target>/etc/default/bootset (absent = auto, unknown = manual); the box form and
default journal pending S2-06. kbootset gate 1 ignores apkg's <name>.new temporaries and refuses a path named by two records
(apkg 0.3 review). M-LD5 bench half closed 24/24; M-LD8 closed: inflate 5.5/7.6 s from fast RAM, a deflated floppy reaches
the kernel prompt in 18 s against the LZW loader's 31 s. 629 host checks; boot2 28 164 B.

## 2026-10-26 — boot2 runs from fast memory; metal recipes (042a408..50bed35)

boot2's start-up stub copies image + relocation table into a MEMF_FAST block and relocates there; a chip-only machine runs
in place and says so once on serial. Device reads stay in the chip bounce buffer; members are read, inflated, checked and
relocated from fast code (M-LD8: chip-RAM execution cost 7× on inflate, 25× on CRC-32). Spec change after freeze 10 §3.2.
Vehicle scripts fix SOURCE_DATE_EPOCH so bench and metal run the same bytes; tests/bench/README.md "Metal" lists the
S1-26/S1-27 rows; m-ld1.sh adds the M-LD3 vehicle (only boot2 damaged → B3, stop). boot2 27 716 B (560 B under the gate).

## 2026-10-26 — kbootset check and media builds (S2-05, S2-04) (a3a6795, 25b8b60)

kbootset check re-reads every member in the store (inflated where deflated) against the manifest's CRC-32 and SHA-256,
the boot/demand files under the root, and the default generation against the installed kernel package; never writes,
exits 1 on a problem (C2-5's second reader). status notes a pending trial, the next-boot request and low free space.
kbootset media builds a new medium's pristine generation from the packages under -R with every gate run: --disk (raw,
own core), --floppy (pair, deflated) and --cd (tree, raw) through mkstore's engine compiled into the host kbootset, so
media and the test tool share one writer. mkstore writes sha256= on every member. Box binary has no media code.

## 2026-10-26 — kbootset build and the gates (S2-03); M-LD4 bench half (654a324, 831975e)

kbootset build composes the next generation into /stand/gen/<id>/ from the kernel package (C2-3 sidecar) and apkg's
records (C2-2), running gates 1 hash, 2 kabi/pin, 3 closure (a static kernel's built-in root controllers and filesystems
against the boot/root controllers and root fs), 6 memory, 7 loader version and 10 line; commit re-runs the gates on the
files as they are and refuses a stale build. Every refusal exits 4, names the gate and leaves the store byte-identical
(tests/host/kbuild.sh provokes each). Box build 103 004 B stripped. Gates 8/9 come with kinfo (S2-06); root-class modules
are stage 3. M-LD4 bench half closed: the loader's writes read back 12/12 on A3000 WD, Gayle, A4091 030 and 060.

## 2026-10-26 — kbootset box build with GCC 14 (S2-07); contracts agreed v1 (37ec6be..5eae3e6)

Contracts C2-1 to C2-5 agreed (version 1, settlements recorded). Spec change after freeze: rollback reaches the pristine
generation when there is no older good one; OQ-40.5 closed by C2-5. `make box` builds kbootset for the box with GCC 14,
statically linked by hand (the driver's specs ignore -static), 70 496 B stripped, one binary for both lines, 68060-checked,
FPU-free on its paths, plus a C89 compile check on gcc-cross-amix. tests/bench/kbootset-smoke{,-host}.sh: the box/host
smoke run (identical stores and output prove the box binary computes what the host does). Emulator run pending.

## 2026-10-26 — kbootset host core and state machine; contracts C2-1..C2-5 (3afa802..3c159ba)

kbootset over any byte device (kbootset/ks.c): create, commit (pristine first, then trial), mark-good (also a loader on
trial), rollback (down to pristine), next, mark-bad, collect, loader-install; every write read back; the kept-set rule;
gate 5 (store space) writes nothing; journal recovery. Command line (kbootset/kbootset.c) on images and raw slices, exit
codes 0–4, commit step markers and KBOOTSET_HOLD for power-cut rows (every single or torn write survives: the store still
boots by the loader's own rules). The control block records the last generation id issued (spec change 10 §4.2).
docs/contracts/: C2-1 kinfo record, C2-2 kpkg catalog block and install record, C2-3 kernel/loader package layout and kabi
sidecar, C2-4 kbootset as a called program, C2-5 checksum contract v2 — agreed by the orchestrator 2026-10-25 evening.
624 host checks. boot2 27 540 B.

## 2026-10-26 — table-driven inflate; raw where there is room; no SHA-256 in the loader (cd56b88, eaba2d1)

M-LD7 bench half closed: the loader checks CRC-32 only (SHA-256 costs 2.3–3.75 s per kernel on a 25 MHz 68030). M-LD8:
the bit-at-a-time inflate (45–53 KiB/s on the 030, ~290 instructions per literal) is replaced by a table-driven decoder
(9-bit lookup, ~35 instructions per literal; 3.0× on the host, estimated 6–10× on the 030; 3 000 zlib streams and both 1.0
floppy kernels inflate identical). axtime-chip times code in chip RAM as boot2 runs. Spec changes after freeze: 10 §5.1 no
SHA-256 in the loader; 10 §5.5 and 40 §3.2 members raw in disk stores and on the CD, deflated only where a generation must
fit (floppy pair, netinstall); 10 §4.4 the ROM CD filesystem facts; 80 §7 the media-track rows gate the media, not stage 2.
boot2 27 528 B (752 B under the gate).

## 2026-10-25 — L11 disk change fixed; reproducible stores; stage-2 plan (c0c8f93..62a6b66)

boot2's L11 volume change waits for trackdisk's change counter (or a key), clears the track buffer before re-reading, keeps
the motor off while waiting and says each refusal once per disk change (rig rows N25b/N26b: the old code re-read the cached
track of volume 1 three times a second). mkstore honours SOURCE_DATE_EPOCH (byte-identical rebuilds) and writes
BOOT/amix-cdboot mode 0755. docs/plan/stage-2.md: the work breakdown for lifecycle and rollback on static kernels, with the
five cross-repo interfaces C2-1..C2-5. boot2 26 788 B.

## 2026-10-25 — axtime and the bench inputs for M-LD4/M-LD5 (656d155, 72c9fc4)

SHA-256 in loader/common (FIPS 180-4 vectors; not linked into boot2). axtime, an AmigaDOS tool, times the loader's
CRC-32, SHA-256 and inflate with the E-clock (M-LD7/M-LD8 via tools/measure/m-ld7.sh). mkstore -T (loader trial) and -n
(one-shot request); lsstore shows tally and attempts; axsim replays the loader's write rules over boots. tests/bench/ holds
the row builders, schedules and expected results for M-LD4, M-LD5 and the DF0 pair (S1-21, S1-22, S1-27). The AmigaDOS
entry stub adstart.s is shared by amix-cdboot and axtime. 518 host checks; boot2 unchanged.

## 2026-10-25 — amix-cdboot (S1-C2) and the floppy pair (S1-24) (42476b7..12c70f5)

boot2 split into a shared core plus media (store, CD). amix-cdboot: boot2 as an AmigaDOS load file (b2link -h) reading
/BOOT/K30|K46 through dos.library; manifest file= members; mkstore -C / lsstore -C write and verify the CD tree. Floppy
pairs: an extent may continue on the next volume and the manifest sits ahead of its members, so a pair boots with one disk
change (the deflated miniroot is larger than one volume); M-FP1 (static) and M-NET1d closed: k30 fits with 14.8 %, k46
with 11.8 % (trimmed engine). Spec changes after freeze: 10 §4.3 and §4.4. 313 host checks; boot2 26 556 B. The bench rows
N19–N26 need a re-run on this boot2 before stage exit.

## 2026-10-25 — S1-19 defects: AGA display state at hand-off, boot device name (301b836, 3b404c7)

boot2 restores the display state the 1992 console expects before it starts the kernel: a null copper list and FMODE,
BPLCON3, BPLCON4 at their power-on values (the AGA console garbling on rig row N21: the stock console programs only
OCS/ECS registers and the loader's Intuition screen had left AGA fetch modes behind). The loader banner prints the boot
device's name instead of an io_Unit pointer and the loader record's unit is the real unit. mkstore gains -c serial|screen|both
and -m <tenths>. boot2 26 008 B. Confirmation run on the rig pending.

## 2026-10-25 — spec changes after freeze for D-3 §10–13 (0acd5c6..5d2bcd6)

§10 the CD boots boot2 as an AmigaDOS program (amix-cdboot; manifest file= members; needs a boot ROM with a CD filesystem);
§11 one compacted disk numbering on both lines; §12 deviation DV-1 approved (below 5 % margin → form B); §13 signing out of 1.1:
60 rewritten as integrity, signing and publishing (1.1 = per-package hash; an optional #ksig catalog line, an apkg verify step
recording "unverified", a verified= field and a future require-signature policy keep the hook). boot2's development-load message
matches the spec (boot2 25 852 B). Fact recorded: today's catalog carries MD5 + size; SHA-256 entries are new in apkg 0.3.

## 2026-10-25 — boot1 stops on failure (3081ee1)

boot1 stops with a message on the serial port instead of returning failure to the strap: on the Z3660 boot ROM chain a
failure return raised AN_BootError and reset the machine about every 14 s, and a reset loop can leave a real 68060 dead until
a power cycle (M-LD3 bench half, from the S1-16 run). Spec change after freeze: 10 §3.1 step 6, failure rows B1/B3, the menu's
r key; OQ-10.1 narrowed to the other boot ROMs. boot1 884 of 1008 bytes. Also d1782bd: assembler comments no longer read as
line markers (binaries unchanged).

## 2026-10-25 — loader stage 1, items S1-07..S1-15 (c4893cf..fd64097)

Raw deflate decoder; generation selection (try-once, one-shot requests, fallback order); kernel relocator for ET_REL, brel and
ET_EXEC with the stock binding rules, bounds-checked; bootinfo, RTH1/RTO1 and AXL1 builders; boot2 linked at 0 and
self-relocating (b2link); boot2 itself (CPU probe, store reads through a chip bounce buffer, manifest, inflate, relocation,
bootinfo with the RTH1 boot-node walk, 68030 and 68040/060 hand-off); menu with rollback key, safe-mode and development-load
toggles, screen and serial console, keyboard, mouse and serial input; multi-volume floppy stores; mkstore stores members
deflated and builds packed floppy pairs. boot2 25 824 B + 2 336 bss of 28 672. 308 host checks; the real 1.0 floppy kernels
inflate byte-identical; the relocator matches kerntools' elf2brel on three real kernels. Nothing has run on an Amiga yet.

## 2026-10-25 — stage 1 plan and the first loader code (f4081f5..b029dbe)

Stage 1 plan (docs/plan/stage-1.md: 28 items plus 3 that wait for the CD fork, each with owner repo, evidence class, what
it blocks and an estimate). Toolchain pin with a presence check (gcc-cross-amix 8949028: GCC 2.7.2.3, binutils 2.8.1);
shared C89 store-format, CRC-32 and GMF1 manifest code with 94 host checks; boot1 in position-independent assembly,
784 of 1008 bytes, under a build gate on size and relocations, framed so the stock 1992 bootblock also passes the gate;
mkstore/lsstore host tools with a store round-trip test. Spec change after freeze: boot1 reports failures on the serial
port only (screen output needs graphics.library, which does not fit in 1 KB). boot1 not yet run on any Amiga (S1-19).

## 2026-10-25 — M-NET1a/b measured; S0 frozen (4d9c5e6..2506516)

Netinstall miniroot (installer + network userland + HTTP apkg): 2 562 866 B (k30) / 2 468 595 B (k46) raw, 959 940 B /
924 595 B deflated with the unused engine tools dropped; with a deflated kernel a floppy pair keeps 16.1 % / 13.0 % margin,
so netinstall form A (floppy pair) is chosen. Record in docs/measurements/, script tools/measure/m-net1.py. S0 freeze
condition met; the specification is frozen at this commit (orchestrator, 2026-10-25).

## 2026-10-25 — S0 revised after review T-52 (f4d1b1f..026215c)

CD boot written as two options for the owner (RDB-style disc, or a loader started from the disc's AmigaDOS startup);
boot1 counts loader-trial attempts in a tally block; the loader record gains root and swap selectors (RAM-disk root on
block major 20, replacing stock ram.c); the kernel loads only modules of the booted manifest, a development override is
printed at boot; the core tier exports bdevsw/vfssw/nfstype; Z3660 keys corrected to 144b:01; four-card minor encoding and
the drivers to rebuild listed, board sets of record and the card-number gate defined; our line rebuilds the 040/060 base
without ufs/s5; the ABI kit publishes the stock headers (built from the pinned sysroot, never tracked); S0 freezes on
M-NET1a/b, deviation DV-1 recorded.

## 2026-10-25 — bootstrap and the S0 specification (ce351f8..5cd25a7)

Repository bootstrapped (MIT licence, README, docs layout). S0 specification for Amix 1.1 loadable kernel modules in
docs/spec/: our own boot loader (boot1/boot2, boot store, ISO9660, generation manifest, module arena, menu, rollback,
safe mode, try-once), .moddata v2 and the kabi rule with the pinned kernel-space toolchain, the ashnazag DLM core as a
patch queue, the four-controller sd contract, filesystems as modules, generations and kbootset, the 1.1 disk layout and
the upgrade install, media (disk/SD, floppy pair on both lines, bootable CD, netinstall, tape, emulation), signing, the
static floor, the proof stages and the measurement list.
