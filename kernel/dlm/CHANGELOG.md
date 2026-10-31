# Changelog

## 2026-10-31 — registry: c 48 for the random module (a8719fb)

c 48 goes to `random` (kernel/modules' random module: /dev/random 0, /dev/urandom 1). It is free in the stock tables
and in 68030-261031-63 and 68060-261031-52 (M-REG1 re-run). kbootset's table is regenerated, and C3-5 v19 gives the
short name `random` (random30/random46). The kernels compile the registry in, so the module loads only on cuts made
from a kit with this change.

## 2026-10-31 — kbootset -29 recipe: the package owns /dev/kinfo (0f60a0e)

kbootset's recipe moves to -29, its release-prep revision (P-38 D-g, not minted): -28's payload plus /dev/kinfo as
`c kinfo /dev/kinfo 53 0 0444 root sys`, in the class of its registry owner (C3-5 v18), CLASSES "none kinfo" (C2-4
v19). The installer writes the node until the media carry -29.

## 2026-10-31 — kernel/dlm/pkg: the port from AMIX_PORT_REPO (0e10fb2)

The recipes drop their sibling override and use dlm-src.sh's AMIX_CROSS_ENV and AMIX_PORT_REPO (38feabe); without
AMIX_PORT_REPO, a repository of their own is filled from port.pin's URL. dlmkit's pin carries its port commit's full
hash, which git needs to fetch it. The same datastreams as 3d867f9.

## 2026-10-31 — P-38 S3.3: dlm's kernel-space recipes move into kernel/dlm/pkg (3d867f9)

loader-amix, kbootset, modtools and dlmkit (dlmkit30/46) move in from amix-packages' recipes (bea8828). They are rolled
by build/pkg's harness through pkg/build.sh, make dist's kspace hook (`pkg <file> <sha256>` per datastream). Each
builds from a git archive of its pinned amix commit and verifies its outputs. Re-rolled here, the minted -11/-28/-9/-12
have the same payload and pkgmap payload rows; only the control files' stamps differ under the deterministic roll, so
these versions keep amix-packages' bytes and the 1.1 set takes new revisions at release prep (D-g).

## 2026-10-31 — P-38 S2.1: `make kit` writes build/kit.digests for the release lock (1632ee4)

tools/kitdigest.sh gives each kit two digests: `manifest`, the dlmkit package's pin, equal across rebuilds of one
commit, and `norev`, without kit.conf and NOTICE, equal across commits when the kit's bytes are. `make kit` writes them
to build/kit.digests (`kit <line> <kabi> <manifest> <norev> KIT_REV= PORT_REV=`), the format agreed with infra for
make dist and the lock. Two builds at 1632ee4 gave identical digests; make test 719/0.

## 2026-10-31 — stage-5 ledger: the owner's rulings on a4kt710-k30, S5-42, S5-32 and S5-44; the port pin (c9884ac, efcaafb)

a4kt710-k30 stays in the 1.1 set, accepted in emulation (the A4000T 53C710 in 030 mode). S5-42's acceptance is
installng's 9 current l11 cells plus a pre-installed-image cell on the final media; the prebuilt (P-35) and upgrade
(P-36) cells are retired. S5-32 ships pre-installed 68060 images made by a fresh install in emulation and proven by
contents (P-38 D-f). S5-44's J4 half is a fresh three-controller install on the A4000D in the batched metal session.
S5-47 notes the port pin's move to 0d37eb1 (amix 5910d09).

## 2026-10-31 — P-36 D-N21: `kbootset major -l`; a node's class is its module (3db6056, 9abb0f5)

`kbootset major -l` prints the whole major registry as `<module> c|b <n>` (C2-4 v18). Module packages put their device
nodes in a class named for the module, with no class script and listed in CLASSES, so amix-base's boot step can find
each node's module in the contents DB and re-create it at the registry's major (C3-5 v18 §1.2). The link.d major column
is optional for a registry module and required otherwise; aen keeps 18 (C3-6 v8). make test 719/0.

## 2026-10-31 — stage-5 ledger and plan: T-56 D3, the A4000T without Zorro cards (3116cbc, f772fee)

S5-21 is narrowed to the tower's cardless rows (CD boot on metal through the onboard 53C710, if a drive is fitted;
S5-18's metal half in 030 mode). Its A4092 rows are out of 1.1 on the tower and covered by the A4000D's M15-M18 and
M20 (amix-kerntools daff4dc). S5-07's A4092 beside the 710 is not for 1.1. The plan rows too.

## 2026-10-31 — P-36 W8: the kbootset package owns its boot scripts; C3-6 v7, C3-5 v17 (b165fd7, ce80a05, fa5efe0, 151803d)

kbootset/rc/kbnamelist and kbmarkgood become /etc/init.d scripts with the links S01kbnamelist and S99zkbootset, which
the installer used to write. They use amix-base's rc.subr when it is present (rc.conf kbnamelist=/kbmarkgood=, default
yes; status in rc.log) and make the same call of record otherwise (C2-4 v17 §16, kbootset(1M), tests/host/rcscripts.sh).
C3-6 v7 §1.8 is a network driver's DLPI checklist (P-36 §4.4) with what its package carries. C3-5 v17: amix-base's
/etc/inittab carries the dlm line, and modtools has no package scripts and is ESSENTIAL. make test 719/0.

## 2026-10-31 — the kit test leaves the kit tree unchanged (864e01b)

The kit test builds the sample in a copy against KIT and checks that each kit tree (entries, modes, SHA-256) is as
mkkit left it, so a tested kit stays mintable. 98/98 with the -52/-63 kernels; the old in-kit build fails the new
check. The main checkout's kit is rebuilt at 96720ad.

## 2026-10-31 — S5-47: the kabi-1.3 kits; modcheck --kernel (4976dac, 93d87ab)

modcheck.py --kernel KABI says whether a kit fits a kernel's sidecar (line, pin, kabi family/major/minor, abi= at the
same minor), with tests/host/kitkern.sh. The kabi-1.3 kits at 4976dac (port d0e8857) fit 68030-261031-63 (fc3d99a7)
and 68060-261031-52 (7f8c9ee0); Paula built with them passes modcheck as k30.1.3/k46.1.3 and binds to both
candidates' symbol blocks. Kit test 96/96 on the candidates; make test 719/0. The kit package mint is amix-packages'.

## 2026-10-31 — the stage-5 exit ledger brought up to date (a036761)

The candidate cuts 68060-261031-52 and 68030-261031-63, and kern46m -52 / kern30m -63, recorded as candidates, pending
until S5-40; new rows for Paula, S5-45 (PASS, host), S5-47 (the kabi-1.3 ABI kit) and S5-48 (the quirk 90/91/92 fixes,
with quirk 74 on k30, and their metal; reopens S5-41/42); stage-5.md's kabi note corrected (1.3 for Paula, no 1.3 kit
yet); P-35/P-36 marks on S5-32, S5-42 and S5-44; a4kt710-k30 left as an open question.

## 2026-10-30 — kbootset(1M) (4f854d9)

The manual page, for /opt/amix/man/1m/kbootset with whatis.d/kbootset: every subcommand of C2-4 v16, the gates, the
exit statuses and the files, in plain -man that the 1991 nroff formats (rendered on the emulator, row N161).

## 2026-10-30 — kbuild.sh flips the bytes it corrupts (cdd160a)

The test wrote a constant 'X'/'Y' over a random fixture kernel, a no-op one time in 256, so gate 1 passed (CI on
de0ec40 and 5e06e1a). It now complements each byte and checks it changed, at six sites; 200 runs, 0 failed.

## 2026-10-30 — kbootset major <module> (bf90a17)

`kbootset major <module>` prints the majors the compiled-in registry gives a module, one `c <n>`/`b <n>` line each
(z3660eth `c 51`, ramdisk `b 20`); an unknown name exits 1. It reads no store or kinfo, so it works on a static
kernel, in safe mode and on a medium boot. For the base system's rc_mknod (P-36 D-N21). C2-4 v16 §15;
tests/host/kmajor.sh; emulator N161 (k30) and N160 (k46 static -82).

## 2026-10-30 — store-roundtrip complements the byte it corrupts (9ce8f6d)

The test wrote a constant 0xff over random kernel data, so one run in 256 changed nothing and passed "corruption NOT
detected" (CI run 41099115013). It now complements the byte at lsstore's kernel offset (and in the CD kernel) and
checks exactly one byte changed. 200 looped runs, 0 failed.

## 2026-10-30 — mkkit builds from an archive of amix (39acfa7)

mkkit builds from an archive of amix (git archive, make dist), with or without a surrounding git repo: it no longer
takes the surrounding repo's commit or kernel/modules as amix's. Such kits record KIT_REV from the environment, else
unknown, and MONSW_REV=amix@<that>; checkout kits are unchanged. make test 719/0.

## Unreleased

## 2026-10-29 — README brought to the real state; the stage-5 exit ledger marks the rows done so far (93a1404, a816696, 2fee9ce)

README: the parts are built, the real layout, the toolchain pin's home on jusii/gcc-cross-amix. stage-5-exit.md: each done
row cites its run id or commit and date; partly done rows keep their pending halves. No kit bytes change.

## 2026-10-29 — The kit builds under LC_ALL=C; toolchain.pin names jusii/gcc-cross-amix (b4b73ed, 2aeb001)

exports is in the same (bytewise) order on every host; no other kit file changes beyond the revision lines; monsw and
ramdisk are unchanged. toolchain.pin's url is jusii/gcc-cross-amix, where 8949028 lives; the kit bytes do not read it.

## 2026-10-29 — mkstore's CD file-name buffer is sized for any id and module count (3c4a95c)

40 bytes, so the host build is clean under gcc 13 with fortify (CI on ubuntu-24.04); names and outputs unchanged, kit
bytes unchanged. make test 719 checks on ubuntu 24.04 and 26.04.

## 2026-10-29 — amixddi.h's two comments name kernel/dlm instead of amix-dlm (1e243b9)

The kit header changes in comments only; monsw 1f53a31b / 962709ca and ramdisk 5523d853 / 054467f6 are unchanged.

## 2026-10-29 — The prose names amix's directories (kernel/dlm, kernel/modules) instead of the old repositories amix-dlm and
amix-modules (765e4b0)

Citations of contracts, decisions and commits keep "amix-dlm"; the README says what it means. Kit docs change (README,
guide, ddi, C3-6, NOTICE, registry/majors comment); headers, mk, tools and sysroot are unchanged. make test 719 checks.

## 2026-10-29 — The ABI kit records the amix commit it was built from (KIT_REV, -dirty for uncommitted changes under kernel/; MONSW_REV amix@<commit>); sys/monsw.h comes from kernel/modules/include/sys/; no sibling-checkout defaults: GCA, G14 and PORT must be given and a missing one stops the build (4cb14c9)

Kits built before the move keep their amix-dlm KIT_REV, which resolves in amix too. boot1/boot2 unchanged (765915a7, da260a96); the kit matches the -61 record's except its revision lines.

## 2026-10-29 — Moved into the amix repository as kernel/dlm by a subtree merge of amix-dlm master 565de49 (696 commits, hashes kept); the tree is unchanged

## 2026-10-28 — C3-5 version 16: paula's short name (paula30 / paula46); a driver's own interface header may ship in its module package under /usr/include (0644 bin bin, the same bytes on both lines), as paula.h does (821d101)

## 2026-10-28 — Loaders: boot1's block and boot2's bounce buffer come from the boot partition's DosEnvec (de_BufMemType, MEMF_PUBLIC when 0; chip when de_Mask does not reach them or no boot node matches); boot2 reads whole blocks straight into a buffer the Mask allows, ≤32 KiB per transfer; the boot-device line names the buffer. For the A4000T, whose onboard 53C710 hangs on DMA into chip with the Z3660 fitted. boot2's self-relocation table is a byte a field (1126 → 583 bytes). boot1.img 765915a7, boot2.bin da260a96; spec 10 §3.1/§3.2 (39240c1, a6a1511, 053c417)

## 2026-10-28 — DDI minor 3 for the Paula module (C3-2 v2): AllocMem, FreeMem, displaytype, paula_busy, audio_nopen on both lines, kits k30.1.3/k46.1.3 (abi 18c0a1c9; 1.2 stays 2ab48658); a kernel lists only the names of its own kabi minor (mkksym -k, core patch 0046), so a 1.3 claim without the audio patch fails its gate; a module carries the highest minor it imports, never below 1.2 (R2 ufs still 62cc5250); c 54 paula in the registry and spec 20 §6 (box kbootset 0b9b8ec4); C3-6 v6: chained level-2 handlers cannot see CIA-A ICR bits (0edbd0f..36c407d)

## 2026-10-28 — plan: S5-16 root half passed on metal in 030 mode (b1f564f4, gen 6 68030-261027-20, c6d0s1); the second-card goal moves to Gayle IDE or emulation; a4kt710 recorded as unsupported in 030 mode (no NCR tag in the A3000 Kickstart, hidden $07 SIMMs, $DD0000 mapped to the emulated SDMAC); no core change (139b5b0)

## 2026-10-28 — docs/plan/s5-12-packaging.md: the k46 inputs of record are the ufs-guard cut 68060-261028-51 (port 87b8a88, core 7b07bce; ufs.mod rebuilt byte-identical with the kit at c614e0b), version k46.1.2.261028-51 (6f020a5)

## 2026-10-28 — plan: S5-13's k46 small-block row is now "a block-under-page ufs is refused at mount, EINVAL" (port 87b8a88; the crafted 2 KiB ufs panicked k46 in the stock getapage assertion); S5-37 notes getapage's PAGESIZE/2 arm; the next k46 cut takes ufs-exp.k46 6636b27e (6c62e87)

## 2026-10-28 — spec 10 §9: L4 goes on to the next generation like L2, as boot2 does; only missing work memory for boot2 itself ends the boot (spec text only) (f8a0da5)

## 2026-10-28 — C2-4 v15: after a boot the loader fell back from the default, mark-good verifies the default and marks it bad when its bytes are damaged (intact members keep it; a spent trial and the pristine generation are not judged); box kbootset 3c18c3b5 (-23 candidate); spec 10 §9: L3 names the generation and the progress line before it names the member (boot2 has 14 bytes free) (7925b96, df7124b, c614e0b)

## 2026-10-28 — docs/plan/s5-12-packaging.md: the k46 inputs of record are the re-cut 68060-261028-50 (core 7b07bce), replacing -91; version k46.1.2.261028-50 (6b1b055)

## 2026-10-28 — core/plat: the module core takes the kernel's build id without the stamp's leading blank, so a k46 kernel loads its core-tier ufs module (the S5-13 EBADVER; every k46 kernel so far carries " 68060-…"); t_plat tests the port's real format (7b07bce)

## 2026-10-27 — C4-1 v7: `pkgchk core` is quiet on /dev, not as a whole; the S5-44 ledger row likewise (cc3e43e, a9542a3)

## 2026-10-27 — kbootset: a disk store's root record keeps a core-tier module's tier=/build=, copied verbatim as C3-5 §3 says (informational; the core decides from .moddata) (e8254e5)

## 2026-10-27 — the S5-12 recipe pinned at the packaging cuts 68030-261027-20 and 68060-261027-91 (rth1=2, no rootfs=; the modules rebuild byte-identical with the kit at HEAD); M-FL1 re-checked there, sizes within 641 bytes, conclusions unchanged (943b6fd)

## 2026-10-27 — C2-4 v14: `kbootset status` in a safe boot names the safe set it keeps (from Bench N160); S5-46: C4-1 v6 §5.2 / C2-3 v9, a motherboard controller's record names it by its kinfo id (`sd id=0000000N base=0`, no mobo flag, no loader change), RTH1 matches it and no longer matches a mobo record to the Z3660 window, kernels say `rth1=2`, and kbootset rewrites an old mobo root record only for such a kernel (9c99818, 3f12419, c87fb1b, 698d8c1, c7d69cf, e013b67)

## 2026-10-27 — S5-15 (amix-dlm half): kbootset writes a root/swap record on any Z3660 card as `sd id=144b0100 base=00000000`, takes the window's key as zorro:144b:01, and card_of() picks a motherboard card by the disk with a slice at AXL1's start, the boot device's name breaking a tie; S5-14: M-FS1's host half and M-FL1 at the cuts -18 and -66 (k30 109 240 bytes less memory than -17; k46 36 634 bytes of file, 5 768 of memory) (8941879, 12739c1)

## 2026-10-27 — kbootset's namelist lookup takes the global, never a file static (the k30 cut -18 carries delay as three statics and the global); C2-3 v8: a cut's kernel package carries the ufs/s5 core-tier modules, and its version must sort above the line's kernel of record; the S5-12 packaging recipe docs/plan/s5-12-packaging.md (0735e4d, b8a23e5, 7e9ad63)

## 2026-10-27 — S5-45: `kbootset media --disk --ramdisk` writes the netinstall raw image's store (gated as media --cd; read-only, members raw; the same bytes as mkstore -r on its spec), C2-4 v13 §13; C4-3 v4 §1: a RAM-disk image serves one generation id, and a shared image for a two-line medium is not in stage 5 (d4d8f1c, eb31c79, c2f406d)

## 2026-10-27 — S5-44: C4-1 v5 §2.4, a four-card root holds c0-c1f d0 s0-s7 and no d1 nodes, whatever the board set; C2-4 v12 §14 `kbootset nodes` (commit runs it on the running box, check reports it); plan row S5-44 (gate, blocks S5-41) and installng's recipe docs/plan/s5-44-disk-nodes.md (6c82415, 4046392, ebcdb80)

## 2026-10-27 — modcheck: a COMMON symbol named in the module tier's allowlist is no longer warned as a private copy, since the core binds it to the kernel's definition (the carved ufs's rootvp) (445c12e)

## 2026-10-27 — the k46 ufs module passes modcheck's page scan with no waiver (the port's fsobj-patch.py object with its module-only conversions); plan S5-37 (s5 on k46 carried, no k46 s5 module) and a 2 KiB-block ufs row in S5-13 (ec1202f)

## 2026-10-27 — C4-1 v4 agreed (the port, amix-kerntools): k30's kinfo030.c keys an unmatched card at 0x10000000 as id 4 by its base; plan S5-15: kbootset's card_of() picks among motherboard cards by the boot disk's partition start (975c329, c5f6865)

## 2026-10-27 — k30 DMA with no reachable memory: dma_alloc gives 0 and bounces miss; C4-5 v11 §5.4 refuses the board, no chip fallback (S5-18 host half) (2a4e4e1, 921bd93)

## 2026-10-27 — abi/k46/core.list from the port's patched ufs/s5 objects (100 names, the same as k30's); carve.py corelist --skip, wrap --pageshift-ok (bf10683)

## 2026-10-27 — safe mode can load the boot modules the owner marks with a `safe` line in modreg.local.d (S5-09) (484cdd2, 14cd7b9, 8eee6dd)

Core patch 0045; kbootset writes safe=1 on their boot records; C4-4 v7, C3-5 v15; spec 70 §4. A Z3660 box's NIC opts in for a
reachable rescue; the default stays network-less.

## 2026-10-27 — C4-1 v4, agreed by the port and kerntools: the Z3660 is one controller in either mode (S5-08) (4f24e59, b2b3cff)

kinfo reports the 030-mode window card as motherboard id 4; kbootset composes any Z3660 card as id=144b0100 base 0; RTH1 matches
144b0100 against the AutoConfig board or the window base, exactly one such card. The code is S5-15.

## 2026-10-27 — kbootset: a medium's spec lists the RAM-disk image after the root modules, in boot2's read order, so a floppy pair asks for volume 2 once per boot instead of three times (S5-05) (28fb5a1)

## 2026-10-27 — C3-5 v14: a4kt710's short name (a4kt71030 / a4kt71046); kit module.mk tracks every file a module's source reads (c9ef1b0, ad84eb8)

The .d comes from -E's line markers, since the pinned gcc 2.7.2.3 wrapper passes no -M/-MD, so an included .c or a module header
rebuilds its object.

## 2026-10-27 — tools/carve.py: ufs and s5 wrapped as core-tier boot modules on k30 (S5-04, k30 half) (d6b4381)

vfs_register; s5 after inoinit; a probe=1 parameter for S4-71's init halves. abi/k30/core.list written from the carve (100 names:
74 functions, 26 data; rootvp stays in the base). ufs 56 636 B, s5 39 964 B, modcheck ok (k30.1.2, boot, tier core).

## 2026-10-27 — plan: S5-09, a network in safe mode, opted in per box (a `safe` line in modreg.local.d marks a boot-class module safe=1); the default stays network-less (452c245)

## 2026-10-27 — Makefile: every box object and link depends on build/box/toolchain.id, the sha256 of the GCC 14 files amix-packages pins (2d2288f)

Correction to S5-01's entry: the cf461e3 box build is kbootset 143cc1d8 (not 2c3570a3, a mixed build that kept three objects of
the previous compiler); modadmin f51c98d6 stands.

## 2026-10-27 — C4-2 v6: the A4000T onboard 53C710's gate is the running Kickstart's "NCR scsi.device" cold-start tag (§8.1), with a `declared` override; no loader bytes, no DDI name (69ad13d)

## 2026-10-27 — kbootset: the safe set keeps the card numbers (S5-02; C4-4 v6, C3-5 v13); box binaries on gcc14-cross-amix cf461e3 (S5-01) (74b3e79, 4442c76)

The safe set also takes every controller module ranked at or before the root's class, so safe mode keeps the normal boot's card
numbers (skipped on a ramdisk root). kbootset 2c3570a3, modadmin f51c98d6, built on cf461e3; make test 692/0.

## 2026-10-27 — stage 5 opens (4d4d7a1, docs/plan/stage-5.md): the carried rows and release acceptance with S5 ids; its exit ledger skeleton (docs/plan/stage-5-exit.md)

## 2026-10-27 — STAGE 4 CLOSES (2db99e1, docs/plan/stage-4-exit.md)

Every ledger cell has its result on the exit set, catalog 6e60a128 (kern46m -82, kern30m -17, kbootset -20, loader -9). Media of
record: CD rd1n, the floppy pairs on -9, netinstall ni6. kabi 1.2 is frozen (abi=2ab48658); the next DDI name is 1.3. Carried to
stage 5: S4-60, S4-61, the A4000D's rows, T-54 item 22's set (the fs carve, S4-33) and the netinstall extras.

## 2026-10-27 — spec 70 §4 (after freeze): safe mode names only the controllers it loads; on the WD + A4091 set the safe root is c6d0s1, ced0s1 normally (N145/N146). Plan: S4-67 (stage 5), kbootset marks safe=1 on the modules of every controller ranked before the root's (0e9a604, ba26d53)

## 2026-10-27 — bench: l5.sh keeps the box's generation id, the trial at id + 1 (the core loads boot modules from the booted generation's directory only) (113b103)

## 2026-10-27 — bench: l5.sh writes a brel kernel's bss= from its sidecar (N142's boot2 had assumed 512 KiB); the damaged-module recipe also damages the module-less generations' kernels (N136) (08c0592, 06893b1)

## 2026-10-27 — plan: S4-65/S4-66 (stage 5), the Z3660's root record and the 030 DMA pool in 030 mode (M-S474b); bench: the stage-4 exit batch's recipes; measurements: M-MOD1 again and M-FL1 at the exit (94d23a3, 8c57d7f, 0927aae)

Exit-batch recipes: a damaged root module, L5 by root modules (tests/bench/s4-exit/l5.sh), the core's silent skip of an unmatched
root entry, the sdlate probe for sd_register's EBUSY. M-MOD1: -82's generation uses 53 996 of 393 216 arena bytes; the largest
composable set about 155 KB. M-FL1: -82 2 443 217 B, -17 1 637 928 B + bss (ufs and s5 still in; final after S4-43).

## 2026-10-27 — plan: S4-64 (stage 5), a RAM-disk floppy pair booted with one swap instead of three (mkstore lays the modules before the image) (2fedd77)

## 2026-10-27 — boot2: the floppy pair's volume-2 prompt (L11) re-reads every 4 s as well as on a disk-change count (ea75578)

A trackdisk that does not count the swap (Kickstart 3.2.1 under amiberry, E958/E959) no longer leaves it waiting for ever.
b2medium -f models the unmoving counter: the old loop hangs on the real pairs, the new one passes nine cases. 28 658 bytes.

## 2026-10-27 — kbootset gate 2 checks build= against the kernel's own build id; C3-3 v8 (093b2a7, 8eb826c)

buildid on k46, kinfo_buildid through unix.sym on k30, leading blanks ignored; a kernel without the symbol is unchecked. Passes
on kern46m -82 and kern30m -17 as staged; refuses a wrong build= on both (rc 4). kimports.sh gains the case. For kbootset -20.

## 2026-10-27 — the exit ledger's arms audit closed on both lines (363a11d): k46 one loss (ZS-06), k30 none; the gayle module's polled default noted

## 2026-10-27 — C4-2 v5 (the mechanism: a dirty copyback line written back over the ARM's data; push before); C4-5 v10 §6 (piscsi is not a Zorro bus master — keeps its own maintenance)

## 2026-10-27 — the exit ledger's arms-audit row: k46 done (one loss, ZS-06), k30 pending (d585e10)

## 2026-10-27 — C4-2 v4 §1.1: a module replacing a static driver carries every build-pass arm; the ledger's M-S474a line and the arms audit row

The S4-74 finding as the example: f4arms' z3660_cache = 60 on every static k46 z3660scsi, the module kept 0 → a stale 060 data
cache → the swapconf panic; emulators need 0; the fix is ZS-06. Audit row: z3660scsi ✗; a4091, gayle, z3660eth, z3660rtg, monsw
to check. kernel-build in the build record comes straight from the sidecar's build=; the -79 sidecar says 68060-… where the kernel's
own buildid reads 68040-… (the CPU prefix): the sidecar writer's, with a gate-2 belt possible once the strings agree.

## 2026-10-27 — the exit ledger marks M-RD1/M-RD2 PASS on both lines (N123/N124, kerntools e043755)

Every stage-4 emulation row now passes on both lines; §7 lists what the exit commit waits for: installng's CD-boot install cell,
the Gayle CD-check reruns on 92da8ce8, S4-74 on metal. The exit set is catalog 92da8ce8 (-81/-17 the re-cut of record unless
metal changes something); the exit commit closes kabi 1.2 per §8.

## 2026-10-27 — ddi.md: the libgcc helpers' provider; the core harness forces them too

__udivdi3, __umoddi3, __lshrdi3 are provided by libgcc and forced into the module kernel's link by the builder (kerntools on
k30, the port's relink on k46 — which already -u's them and gets a second belt from ksym.o's references), not kernel source symbols;
k30's static cdfs had pulled them until -17. The harness forces from libgcc only those a base lacks, on both lines; 260/260.

## 2026-10-27 — the ledger's Gayle self-test cell cites N111/N117 (and N115/N116, N121/N122)

## 2026-10-27 — the exit ledger marks S4-32 (Gayle IDE) PASS on both lines in emulation; S4-30…S4-34 per module

kerntools a12120b: the six Gayle rows incl. the first k46 interrupt run (the READ VERIFY self-test); §3's deferred self-test point
PASS; the CD check with 1.1.0-2 and metal pending. z3660scsi and A4091 PASS both lines; the 53C710 pending; the ramdisk shown.

## 2026-10-27 — the exit ledger shows M-RD1 and M-RD2 on both lines (installng rd1h on kern46m -81 / kern30m -16)

§5 M-RD1 (the image at 0x9E00000 / 0x7E00000, Available memory 2 MiB below Total) and M-RD2 (the RTH1 ramdisk line, fakeswap,
rootfstype ufs on k46 / s5 on k30, to the interview) with installng's hashes; the Bench's formal rows pending (§7).

## 2026-10-27 — C4-6 v4: the media's miniroot is s5 on k30 and ufs on k46

s5 is broken under the 4 KiB-page line (ls -l and /etc/sioc bus errors on the k46 s5 RAM-disk root, rd1g), as every k46 miniroot
so far has shown; k46 media use --rootfs ufs and promote ufs, k30 media promote s5 with ufs boot class; cdfs boot class on both.
Spec 30 §6 and the S4-40 plan aligned (whether k46 ships an s5 module at all is a question before the carve).

## 2026-10-27 — C4-3 v3: `swap none` = /dev/fakeswap

The RTH1 half sets swapfile.bo_name to "/dev/fakeswap" (the stock dummy disk, b 19,0, every I/O fails, nothing paged — the 1.0
floppy medium's swap); without swapadd anon_resv refuses every reservation and the first fork panics (08-25), and stock swapconf
with the default name panics on a medium without the node (rd1e). The installer adds the target's slice and deletes the fake;
the miniroot carries the node. M-RD2: "swap none boots on /dev/fakeswap to multi-user".

## 2026-10-27 — dma_forcefail is a self-clearing count; C4-5 v9

N > 0 refuses the next N bounces, one off the count each, clearing itself at 0 (set 1 for E6b's exact "noreach +1"); a reachable or
dma_alloc segment never touches it. Reason recorded (N110: 321 misses for one on a Z3660-bound box). 22 k30 DMA checks.

## 2026-10-27 — C4-3 v2: `swap none` means swapconf runs with no device and looks nothing up

§3: the stock swapconf would otherwise look up swapfile.bo_name, a disk node the medium lacks, and panic (rd1e: "swapconf
lookupname failed - error 2"); the system runs from the RAM disk without swap and the installer configures swap later with
`swap -a`. The kernel half of the fix is the port's.

## 2026-10-27 — core patch 0044: block rows as the stock fix_swtbls leaves the switch (rd1's "row 20 is in use") (80e3da7)

At boot the stock fix_swtbls puts gen_strategy (the breakup) over every bdevsw row without D_NOBRKUP, saving d_strategy in
shadowbsw — so an empty row 20 reads as used at run time and 0031's bempty refused the ramdisk (ECONFIG 168). bempty now knows the
breakup shape; a module's row goes in as fix_swtbls would (shadowbsw behind gen_strategy, or direct with D_NOBRKUP); a failed
load restores both tables; the harness applies fix_swtbls to its switch. 260/260 on both kernels. amix-modules unchanged. The
second gap is the kernels' RTH1 half: rth1.c never reads AXL1's root selector (+60, kind 2 = ramdisk → rootdev makedev(20, 0),
swap none) — the port's and kerntools' change; next cuts kern46m -80 / kern30m -15.

## 2026-10-27 — the exit ledger marks S4-71 k30 PASS (N108) and the A4091 rows k30 PASS (N109/N109b)

Both now pass on both lines (kerntools c326ccb); the entry-0 decode recorded; E6b remains, on kern30m -15 through dma_forcefail.

## 2026-10-27 — the k30 force-bounce hook leaves dma_alloc memory unbounced (N109's phantom NO SENSE); C4-5 v8

reached() first asks allocated(pa, n) — in pool mode inside the pool (dma_alloc areas and live bounces), in heap mode inside one
of ≤ 16 tracked dma_alloc blocks — and such a segment is never bounced, hook or not, as C4-5 §2.2 promises. The hook had bounced
the a4091's chip-written status line and copied stale bytes back; production was never affected. Harness 257/257, 20 k30 DMA checks.
Rides into kern30m -15 with dma_forcefail.

## 2026-10-27 — the k30 DMA provider's `dma_forcefail` test hook; C4-5 v7

While nonzero every prepare that would bounce misses (dma_addr 0); a reachable segment is untouched; with dma_forcebounce also
set every segment misses. Both hooks documented as test-only kernel globals set through /dev/kmem; N109's measurement recorded.
The only way to reach a driver's no-arm path from the box (raw I/O is page-split, GSIO ≤ 64 KiB). Harness 257/257, 17 k30 DMA
checks. Rides into kern30m -15.

## 2026-10-27 — C4-5 v6: the entry-0 decode (N109b) — k30's identity map is cacheable; the read-after-complete rule permanent

§5.3 closed with the four root-table entries: entry 0 `0x7fff0319 0x00000000` (early termination, VA 0–1 GiB → PA 0, CI clear),
entries 2/3 `0x7fff0341` (CI set); the pool measured at 0x07fdf800 / 0x20000. §5.4: on k30 read what the device wrote into
dma_alloc memory only after dma_complete, permanently; ddi.md's dma_complete row says so. No code change.

## 2026-10-27 — the exit ledger marks S4-71 k46 and the A4091 root rows PASS

§6 S4-71 k46 PASS (N107, kerntools 1653ea3); §6 S4-62 k46 PASS (N105/N105b d1a2e3c, N106 1653ea3); §7 lists only the k30
halves (N108, N109/N109b pending).

## 2026-10-27 — kbootset: a module with an absent depend= is left to gate 3's message (fa7a4ab)

The import check skips a module whose depend= names a module the generation lacks, so gate 3's "module X depends on Y, which is
not in the generation" fires instead of "needs a newer kernel cut". kimports.sh has the case. For kbootset -19.

## 2026-10-27 — kbootset gate 2: every module import exported by the kernel's ksym block; C3-3 v7; 40 §3.1, §7 (101e9a3…3360c7e)

gates() lifts the kernel's KSYM v2 block through the sidecar's ksym= (binding a copy with the loader's ax_rel); each module's
undefined globals must be exported by the block at the module's tier or defined by a depend= module, else gate 2 refuses with the
missing names ("it needs a newer kernel cut"); a sidecar whose ksym= names no block is refused; static kernels unchecked. No
.moddata key: module bytes unchanged. tests/host/kimports.sh (synthetic kernel + modules); make test 692 + new; on real bytes
cdfs-k30 is refused on kern30m -13 and cdfs-k46 builds on -79. Spec 40 §7's surviving configuration replaced by S4-54's text
(OQ-40.1 answered, amix-installng 74abe1f). Rides in kbootset -18.

## 2026-10-27 — S4-40 plan: the port's corrected k46 ranges; the carve is stage 5's first kernel item (7c6b109)

The k46 ranges come from the base's STT_FILE markers (ufs .text 0x76e54–0x83290, s5 0x6c3c0–0x75750, plus local .bss), never
from constants; the carve runs on the port's patched b-new before the chain (the 4 KiB-page patches lie inside the ranges; later
relocation-free branches forbid a later carve). k46 imports 118 stock globals and 26 COMMONs (core.list per line); shared COMMONs
stay the kernel's. crash/pstat/sar need a module-aware namelist. Both lines in one wave at stage 5 (kerntools ½ day, port 1–1.5
sessions, the risk in the boot rows).

## 2026-10-27 — C3-3 v6: root= and rootfs= list only what is linked in (the S4-40 k30 calls)

kerntools' K1–K4 all yes (exact-line edits: OPT_SUBEXP, the two vfssw rows, inoinit; tunables stay via master.d; no boot-time
consumer; modules beside unix.brel, stock bodies hash-checked). Calls: the vfssw rows are deleted, not placeholders (k30's
vfsinit calls every row's init); a carved kernel omits rootfs= so a generation without the module fails gate 3, not at mount.

## 2026-10-27 — C4-6 v3: filesystem modules boot class, the rootfs promoted; 30 §6 aligned (a382c41, f2438a6, f50afd8)

One rule for ufs, s5 and cdfs: "a filesystem module is boot class; the generation's rootfs is promoted to a root record"; cdfs is
promoted only on a medium that roots on the CD itself (none in 1.1); the 1.1 media root on the s5 RAM disk; _load safe in both
contexts (S4-71). §5 covers the class choice for all three. The S4-40 plan records A1–A3. Scheduling: the carve is stage 5's
first kernel item unless P1–P3/K1–K2 return "clean exact-line edits", in which case k30 may go first as one re-cut.

## 2026-10-27 — S4-40's plan: ufs and s5 as boot-class filesystem modules promoted by rootfs (2d95b99)

docs/plan/s4-40-ufs-s5-carve.md, plan only. Measured: ufs .text 50 236 / .data 1 004 (13 COMMONs), s5 37 776 / 380; a clean
separation on k30 (only filesys.o's vfssw rows and kernel.o's inoinit reference them); contiguous ranges in the k46 base;
rootvp stays the kernel's (core tier). Core tier = 99 names (abi/<line>/core.list). Both fs= modules boot class, match=always,
promoted by rootfs (core 0043), tier=core, shipped in the kernel package; k30: drop the objects, 13 → 11 vfssw rows, no
inoinit; k46: carve by ranges (tools/carve.py), relink, drop patch_cdfs_vfssw.py. S4-71 halves via probe=1. Budgets: ~80 KB of
the 393 KB arena for the largest root set; the kernel loses ~89 KB of text. Questions A1–A3 (orchestrator), P1–P4, K1–K4.

## 2026-10-27 — the stage-4 exit ledger refreshed; kabi 1.2's closing rule (1b9aa1a)

§2a: S4-72-1 (N103r, kern46m -77) and S4-73 (N104r, kern30m -12) PASS — the rig's `FAIL (b1:lifecycle)` is its stale-mark
check on a reused disk, by design; N103's first-run arena fault fixed by a829c44. §1: DDI 1.2, abi 2ab48658. §6: C4-1…C4-6
agreed; S4-01…08, S4-10/11/12, S4-62's providers built; S4-71 defined. §7: S4-71 both lines (gates gayle), the A4091 rows,
the k30 module rows on -14, cdfs S4-42, M-RD1/M-RD2, the metal cells and S4-74, the stage-5 carries. §8: 1.2 closes in the
stage-4 exit commit; earlier cuts keep their text's hash (fea18182 → 2ab48658 from 0572fcf); the exit's re-cut carries the final text.

## 2026-10-27 — S4-71: the root-context probe module rprobe and its Bench row (c2dc7fb)

tests/bench/s4-71/rprobe.c: a root-class module (match=always) whose _load runs in marc_root and reports each call's value,
level and whether lbolt moved — a 2 000 000-iteration spin, bprobe(0xdff004) and bprobe(0x7fff0000), autocon, sptalloc +
VPOSR read + sptfree, dev_kvmap/dev_kvunmap on k46, kmem_alloc/kmem_free — then `rprobe: PASS: every call returned at level 7
with the clock stopped` or FAIL; returns ENXIO (never linked). Row: any kabi-1.2 kernel, loader v3, kbootset ≥ 33ea0c7, a
stand-in package; a FAIL moves that call to the deferred list for that line (C4-2 §3); the Gayle module ships only after the
bprobe line passes on both lines. modcheck ok k30 (1268 B) / k46 (1400 B). ddi.md: sptalloc's fourth argument.

## 2026-10-27 — C3-5 v12 cdfs row; modcheck per-function page-shift waivers (27ea6e3, 8fc87de)

`cdfs | cdfs | cdfs30 / cdfs46`, no majors. modcheck -w FUNC,… / module.mk PAGESHIFT_OK: a `moveq #11` + lsrl/asrl pair is
waived only inside the named functions (static ones included, by objdump's labels), counted and named in the ok line; a named
function with no such shift is refused; the waiver lives in the module's Makefile, so the object's bytes do not change. The cdfs
k46 object checks ok with its seven CD-sector functions waived. kit-test 0 failed. Kit at 8fc87de (a dlmkit re-mint after -10).

## 2026-10-27 — promotion: the rootfs's boot-class module as a root record (core 0043); C4-4 v5 §1.3, C3-5 v11 (5d3d988, 33ea0c7)

kbootset reads fs=; a class=boot module whose fs= equals the generation's rootfs gets root treatment (km_tail, bss=, a root
record placed by boot2, safe=1); on any other generation it stays a boot record. Core 0043: md_check links an arena module of
boot class only when the manifest's `rootfs <fs>` is its fs=. Harness 257/257; make test 692/0; kit-test 0 failed; boot2
unchanged (28 646 / 28 420). **Pin 33ea0c7** for dlmkit -10, loader-amix -8, kbootset -17, kern46m -79, kern30m -14
(abi= 2ab48658, 98 added offs lines; the k30 cut carries the 030 DMA provider and needs boot2 ≥ 4003c9f on the box).

## 2026-10-27 — core patch 0042: the filesystem layouts in the fingerprint; the 1.2 texts (0572fcf)

dlmoffs probes the sizes and the fields cdfs reads of vfs, vnode, vattr, uio/iovec, dirent, statvfs, mounta, fid and sdcom;
abi-k30/k46.1.2.txt carry them: abi= 2ab48658 on both lines (was fea18182). Every 1.2 kernel minted before this needs a re-cut.
dma_complete without ownership is harmless on both providers (cmpl_noprep), so a driver may complete after a refused arm.

## 2026-10-27 — S4-62 piece 2: the 030 DMA provider; C4-5 v5 dma_addr 0 = do not arm (e9665e6, 20f2c8c)

core/plat/k30: at dmainit the pool is the top 128 KiB of the largest fast memory[] region in 0x00200000–0x08000000 not holding
the kernel (boot2's one-page-short clause exposes it under a Z3660 bind); no such region with the kernel below 0x08000000 =
heap mode, nothing bounced; otherwise DMA off, said on the console. prepare bounces any segment outside that window from a
line-granular free-extent pool (TO_DEVICE copied in); complete clears the 030 data cache (CACR CD) for FROM_DEVICE and copies
back; `dma_forcebounce` is the test hook. C4-5 v5: on k30 dma_addr returns 0 for an unreachable segment with no bounce — the
driver fails the transfer, never arms. 16 host checks; harness 255/255; make test 692/0; kit-test 0 failed. Reaches a box with
kern30m -14+ and boot2 at 4003c9f+.

## 2026-10-27 — the cdfs answers: kit sd.h four-card; 13 DDI names; C3-1 v5; C4-1 v3 §3.2; cdfs boot class (a8efd99…2ba7fd4)

The kit's sd.h now carries SDCARDS 4 and the four-card sdcard() decode (kerntools' two exact-line edits, refused if absent).
DDI 1.2 adds sdqueue, sdopen, vn_rele, copyinstr, getudev and fs_nosys/setfl/frlock/poll/pathconf/cmp/rwlock/rwunlock on both
lines (all T in both stock bases; fingerprint unchanged). C3-1 v5: fs= required of every vfs_register caller. C4-1 v3 §3.2: a
controller calls cp->intr at level 4 or below. The plan rows (S4-42, S4-72, exit) say cdfs is boot class on disk. Needs
dlmkit -10; cdfs's first kernel is a re-cut at bc1c511+. Open: the vfs/vnode ABI texts (changes the 1.2 fingerprint; with the
next re-cut wave) and the one-object/two-class rule (promotion recommended). Harness 255/255; kit-test 0 failed.

## 2026-10-27 — S4-11: boot2 places the RAM-disk image; ax_memcap a page short; C4-3 agreed (4295d81, 4003c9f, ee77481)

boot2 claims the image in place at the top of the kernel's region (exec AllocAbs, 64 KiB aligned, above the kernel's end),
ends memory[] below it, writes AXL1 116/120 and the ramdisk root selector; the claim is freed on a CRC failure; rootsel.kind
initialised. ax_memcap ends the region under the bind base one 2 KiB page short (10 §3.2; the k30 DMA pool relies on it).
kbootset media --ramdisk defaults to root ramdisk, swap none (ramdisk safe=1). Budget: the code-only hunt found 112 file bytes
(packed L table, shared L4 and `needs` lines), items 3–5 228 (L texts ≤ 20 chars, terser menu key line, three lines); file
28 646 / image+bss 28 420 of 28 672 (26 / 252 left). make test 692/0; b2test, cdboot, cross pass. Placement proof = M-RD1/M-RD2.

## 2026-10-27 — k46 dma_alloc through the DTT0 alias (C4-5 v4); C3-5 v10 package names (01024f5, 9075fb2, ebc52f9)

The k46 heap lies above 0x40000000 (vtop(va) != va; the port's D42 walk), so bbd20b6's dma_alloc returned 0 on every k46
kernel. Now: kmem_alloc(len + 20), every page vtop'd, the run contiguous and below 0x40000000 or freed; the returned pointer is
the physical address (DTT0, cache-inhibited); the heap VA kept in a header for dma_free; the block pushed and invalidated by
physical line at alloc and free via the port's prepare/complete FROM_DEVICE. 10 host checks; harness 255/255; make test 692/0.
kern46m must pin 9075fb2 or later; kern30m -13 and dlmkit -9 at bbd20b6 unaffected. C3-5 v10: `z3660scsi | zscsi | zscsi30 /
zscsi46` (as minted) and `a4091 | a4091 | a409130 / a409146`.

## 2026-10-27 — C3-5 v9 (gayle row); C3-6 v5 (self-test by a real command) (3511139)

C3-5 §1.1 `gayle | gayle | gayle30 / gayle46`, no device nodes (sd owns the disk majors). C3-6 §1.3: a board whose pending
state software cannot set self-tests with a real command that interrupts and moves no data (the A4000 Gayle IDE: READ VERIFY,
one sector, one-tick rounds). The gayle-ide §7 answers: all seven accepted; `param intr=1` lives in /etc/conf/modreg.d/gayle.

## 2026-10-27 — S4-62 piece 1: the five DMA names in DDI 1.2; the k46 provider half; C4-5 v3 dma_addr(r, pa) (0e4c34f, bbd20b6)

dma_prepare/dma_complete (k46: the port's dma_cache040.s, exported), dma_addr, dma_alloc, dma_free in DDI 1.2 on both lines.
k46 provider (core/plat/k46): dma_addr = pa; dma_alloc = kmem_alloc KM_NOSLEEP, 16-aligned, ≤ 64 KiB, kept only if
identity-mapped below 0x40000000 (else freed, 0). k30 placeholder (§5.4): alloc 0, prepare -1, until piece 2. C4-5 v3:
dma_addr takes pa, because the port's dma_prepare stores no pa on a miss (a still-owned segment leaves the earlier one's).
Harness 255/255 (+8 k46 DMA checks); kit-test 0 failed (+ the five-name modcheck case); make test 692/0. Kit at bbd20b6.

## 2026-10-26 — kbootset: a `--root ramdisk` generation marks the ramdisk module safe=1 (57b3832)

C4-4 v4 §2 and C4-3 §1 already said it; kbuild.c's safe-set loop now adds the root-class module owning b:20 (plus its depend
closure) when the facts' root record is ramdisk. Disk roots unchanged. make test 692/0 with two new kbuild.sh cases.

## 2026-10-26 — mkident: dlm_arena back to .balign 4; .data stays 4-aligned (a32fc10, 8bbe731)

The record rounds the arena (C3-3 v5), so the directive added nothing and a .data alignment above 4 could open a text/data
gap the loader does not expect (the port's finding). The core harness checks .data stays 4-aligned in ident.o and the spliced
kernel; the arena stays 16-aligned in the image (KD060-Z 0x0012f0f0, K030-U 0x001091b0). Kit at 8bbe731, content unchanged.

## 2026-10-26 — C3-5 v8: the ramdisk package row; block-driver nodes in /dev/dsk (b5791e9)

§1.1 `ramdisk | ramdisk | ramdisk30 / ramdisk46`; §1.2 device nodes ship as pkgmap entries, block nodes in /dev/dsk,
/dev/rdsk only with a character row (the ramdisk: /dev/dsk/ram0–2, b 20 0–2, 0600 root root). Documentation only.

## 2026-10-26 — S4-72-1 N103: the module arena 16-aligned in the image; gate 4 (a829c44, 239b4a7, 49239b1)

Core 0034 checks a root module's ABSOLUTE 16-alignment; boot2 places it 16-aligned relative to the arena, whose image
offset (.text + .rodata + dlm_arena's .data offset, back to back) was 8 mod 16 on both minted kernels — `.balign 16` alone
would not fix it. mkident --asm makes dlm_arena capacity + 16 bytes; --fill writes AXK1 +40 and arena= as the first
16-aligned offset inside it; --check refuses any other (C3-3 v5). kbootset gate 4 refuses a root set on a misaligned arena
(40 §3.1). Harness 255/255 (KD060-Z arena 0x0012f100, K030-U 0x001091c0); make test 692/0; kit-test 0 failed; kit at
49239b1. The port's kabi-sidecar.py:101 and kerntools' kabi-sidecar030.py:142 must accept the rounded offset.

## 2026-10-26 — m-reg1.py reads a module kernel's stock nfstype as __amix_nfstype (63d33c4)

The core's nfstype is 0 in .data until dmainit copies the stock count; the reader prefers __amix_nfstype when present.
Stock kernels read as before (13 on k30, 12 on k46).

## 2026-10-26 — kabi 1.2 opened, 1.1 closed (42411c4, fc4ee89)

The set taken from the minted kernels' KSYM blocks (kern46m -71: 82 names, has sd_register + root_defer; kern30m -10: 79,
has sd_register only). 1.2 on both lines: iodone, ramdisk_image, vfs_register, the C4-5 DMA calls when listed; k30 only:
root_defer. 1.1 closed = sd_register (both) + root_defer (k46). abi-*.1.2.txt identical to 1.1 (abi= fea18182; functions only).
Kits now k30.1.2 / k46.1.2; C4-2 v3, C4-5 v2, C4-6 v2, C4-3 carry the minors. Kernel re-cuts must tag kabi 1.2 (mkident,
sidecar, DLM_KABI). ramdisk builds ok on both 1.2 kits (k30 5523d853, k46 054467f6). Harness 255/255; kit-test 0 failed;
make test 692/0.

## 2026-10-26 — S4-41 vfs_register; C4-6 and C4-5 agreed; iodone; block-only modcheck (5c9ee3b…9c0cd10)

S4-41: vfs_register and the grown vfssw (core 0040): the core owns vfssw[stock+4] and nfstype, copied at dmainit from
__amix_vfssw/__amix_nfstype (a module kernel cut must weaken and alias both, as execsw/fmodsw); fs= on the module record,
mkmod writes $fs; ENOSPC at stock+4. C4-6 agreed: init called as vfsinit calls it (row, index), result unread, unload=allowed
refused. DDI: iodone (func 1, both lines); amixddi.h gives VSECT1/phystokv on k46 under #ifndef. modcheck accepts block-only
drivers and checks b: majors against majors= and the registry (core 0041 comment). 10 §3.2: ax_memcap ends the touching
region one page short (coded with S4-11). C4-5 agreed: §5 shape (b), the k30 pool from memory outside the main store;
no bounce when the main store is below 0x08000000; promised to 32-bit Zorro III masters only. State harness 255/255;
make test 692/0; kit-test 86/0; ramdisk builds ok on both lines, hashes unchanged.

## 2026-10-26 — C4-5 amended from the stations' readings; C4-2 v2, the A4770 key (a2e9a0b, 3233b48)

C4-5: one arm site (the A4091's DSA-table data address, taken by dma_addr after prepare; the A3091's two stay stock on
k46); k46 dma_alloc is kernel memory under the DTT0 identity map (Zorro III bus masters reach it, metal-proven by the
A4092 root rows); k30 bounces 16-byte aligned and line-rounded; a module's chip-visible statics (~1.3 KiB for the A4091)
move to one dma_alloc area. Waits only on §5 (the k30 pool's origin, kerntools). C4-2 v2: the A4091 row gains
zorro:c0de:02 (A4770, untested on hardware); the A4091 is synchronous and polled in v1, INT2 via root_defer later;
per-card arrays a constant 4; the A4092 needs the unsigned-autocon fix in every K family.

## 2026-10-26 — 30 §6 cdfs boot class; S4-72-1's measured failure line; C4-5 draft, DDI v1.1 DMA (477d583, 1714b41, 64268c5)

C4-5 (agreed apart from §5): dma_prepare/dma_complete and struct dma_rec adopted unchanged from the port's
DMA040-SERVICE-RECORD and amix-a4091's D42-CALL-SHAPE; providers = the port's dma_cache040.s on k46 and the core's on k30
(prepare bounces a segment a Zorro bus master cannot reach through a pool; complete copies back); one added call
`dma_addr(r)` (pa on k46, the bounce address on k30); `dma_alloc(len, &pa)`/`dma_free` for SCRIPTS and buffers (16-aligned,
≤ 64 KiB, no sleep). Open §5: where k30's pool comes from — (a) boot2 reserving it (AXL1 v2, a dmapool record) or (b) the
K030-U kernel's memory sizing reserving a reachable range at dmainit — kerntools answers from the relink kit. S4-72-1's
failure guide carries the measured line on -71 with no root module (RTH1 "built in (controller not present)" → the panic
→ the L8 fallback). 30 §6: cdfs boot class on a disk-rooted box.

## 2026-10-26 — C4-6 draft: the filesystem module form (7982391)

ufs and s5: class root, match=always, fs=, core tier with the kernel's build=, pinned (s5's _load calls inoinit); cdfs: DDI
tier, pinned, root class on the CD medium and boot class on a disk-rooted box (the stock mount path has no load-by-type hook,
so demand class would need stock mount changes; spec 30 §6's word changes after freeze). The kernel build renames the stock
vfssw/nfstype at the splice as it does execsw; the core owns vfssw[stock + 4] in .data with a live nfstype and copies the
stock rows at dmainit (U12 checks the walkers read nfstype live). `vfs_register(name, init, ops, flag)`, a DDI name of minor 1
from a root- or boot-class _load: EINVAL (name ≠ fs=, ops 0, outside a _load), EEXIST (two drivers for one type), ENOSPC;
init once at level 7 in marc_root (S4-71 confirms the stock inits return there). The core tier (core.list, ~112/108 names)
is written by the carve (S4-40). rootfstype from the loader record. Agreed with the three choices.

## 2026-10-26 — Core patch 0039: ramdisk_image, the RAM-disk image for its module (c2ed79c)

`int ramdisk_image(unsigned long *paddr, unsigned long *size)`, a DDI name of minor 1 (any context): core/plat/amiga.c keeps
the image's physical address and size from AXL1 (offsets 116, 120) and hands them to the ramdisk module, ENOENT without an
image. Harness 245/245; plat 11 checks; the kit rebuilt at c2ed79c. C4-3's text is final for the ramdisk module's port.

## 2026-10-26 — Kit README: a DDI function leaves abi.txt as it is; C4-3 draft, the RAM-disk hand-off (6f1c775, 1724dc2)

abi.txt covers the DDI's data names with sizes and the layouts the core reads, not function names; a function added to
ddi.list records the minor it entered and the kabi rule binds a caller to that minor. C4-3 draft (agreed): the manifest's
`ramdisk miniroot <size> at=|file= [z=deflate] crc32=` with `root ramdisk`, `swap none`, `rootfs`, the ramdisk root-class
module (match=always, b:20, safe=1) written only for a medium's generation (--ramdisk); boot2 inflates the image to the top
of the largest usable fast region (below 0x40000000, on k30 within the 64 MiB cap), 64 KiB aligned, shortening that
memory[] entry, AXL1 offsets 116/120, L4 when kernel + arena + image do not fit; the kernel honours the shortened entry, the
RTH1 half sets rootdev b 20/0, no swap, rootfstype after marc_root linked the ramdisk; the module gets the image through a
new DDI name `ramdisk_image(&paddr, &size)` (minor 1, root context), unit 0 maps it as a board window, units 1–2 are kmem
scratch disks within U4's limit, no _halt. build/kit rebuilt at HEAD after every kit-affecting commit from now on.

## 2026-10-26 — Loader version 3; two drivers on one board refused; the kit makes root-class modules (ec99e40..ba2bcee)

AX_LOADER_VERSION 3; kbootset raises loader-min to 3 on a generation with a root-class record and gate 7 refuses it on a
store whose loader is older (spec 10 §5.1, 40 §3.1); the banner reads `amix-boot 3:` / `amix-cdboot 3:`. C4-4 v4 §4.1, three
layers against two drivers on one board: kbootset's gate 3 refuses a root module for a controller the kernel's sidecar
root= names; core patch 0037 has marc_root skip one before its _load, the kernel naming its built-in root controllers in
`dlm_static_root` (written by `mkident.py --asm LINE KABI CAP ROOT`, "" when omitted); the port's sd guard is the last
line. The kit: core patch 0038 has mkmod write `$rank`; modcheck accepts class=root (match= required, no unload=allowed,
only b: majors and only on root, rank one of z3660/zorro/mobo/ide, the in-place layout). S4-71 records the root context's
measured shape; the S4-72-1 recipe gets the version-3 banner, gate 7 and the static-driver refusal as its first expected line
on a kernel that still links z3660scsi. make test 692; harness 243/243; kit-test accepts a root module and six refusals.

## 2026-10-26 — Core patch 0036 root_defer; C4-2 agreed; the S4-72-1 recipe (6813501, 1e6c56d, 4dc0e8b)

`root_defer(fn, arg)`: only from a root-class module's _load in the root pass; up to 8 calls, run once each in order by
dlm_marc_run at the first sysinit entry before any boot-class load, in safe mode too; fn's nonzero return printed, the
module stays linked; EINVAL outside the pass, ENOSPC on a ninth, a failed load's calls swept; a DDI name of minor 1. Harness
241/241 both kernels; dlm.o 13de7929. C4-2 agreed (version 1). Bench recipe S4-72-1: the first root-class boot, z3660scsi on
k46 (inputs, vehicle, four boots with the expected console lines, a failure guide, the next cells); s3-modpkg.sh takes
KABI=k46.1.1 for stage-4 modules. Decided: LOADER_VERSION 3 for S4-10's boot2 and `loader-min 3` on any generation with a
root-class record, so kbootset's gate 7 refuses an older loader at compose time instead of boot2 falling back at L9.

## 2026-10-26 — kbootset composes root-class modules (S4-12, b4297bd)

On a module kernel, root-class modules become store members beside the kernel: `module <name> root <size> at= crc32=
sha256= bss=<km_tail> match= [depend=] [safe=1]`, root class first in depend order; the safe set = the module whose match=
names --rootdev, the --rootfs module and their dependencies. Gate 3's closure moves after the modules (boot/root controllers
and the root filesystem are the kernel's own or a root module's); root rules: match= required, unload=allowed refused, a
root module depends only on root modules, a block major only on a root module (the ramdisk's b:20 composes), root class
refused on a kernel without an arena. Gate 4 counts the directory, the manifest copy and every root module 16-aligned with
its bss tail against the capacity. "Nothing to commit" compares root members too. Media carry mkstore's root lines.
make test 692 + kbuild sections ok. Not run end to end on the emulator until the root-class kernels (S4-72 is the check).
Remaining: the board set from kinfo's list at build (C4-1 §5) — later; two-digit names already right (c%lx of 8×card+unit).

## 2026-10-26 — Spec 30 §5.3: the no-Z3660 060 board sets; C4-1 version 2 (bef0ccd)

30 §5.3 gains the 040/060 sets without a Z3660 (S4-57): A3000 onboard alone; A3000 onboard + A4091/A4092; A4091/A4092
alone; Gayle IDE + A4091/A4092 (unchanged: 1.0's IDE glue key 0xfffffff0 sorted it last, as class 4 does); A4000T 53C710
alone and + A4092 (sets with a controller 1.0 did not drive). Expectation 2 gains k46's A3000 onboard + Zorro SCSI (1.0
put the WD at 0xDD0000 first; c6d0 becomes ced0, D-3 §11). C4-1 v2: §4.3's "not a set of record" replaced by the accepted
k46 rename; §6 lists it; S4-72 M-SD1 and the ledger name the added sets.

## 2026-10-26 — Stage 4 plan: S4-57, the generic 060 target (a2829f6)

An A3000 or A4000 with a third-party 68060 and no Z3660, root on an A4091/A4092, the A3000 onboard SCSI or Gayle IDE, a
ZZ9000 in Zorro II mode as RTG; proven under emulation, delivered as pre-installed disk images through the first-boot
dialog; release notes per accelerator "proven under emulation; reported working by <tester>"; CyberVision PPC graphics and
the CyberStorm UW-SCSI out of scope. Exposed: an A3000 with a third-party 060 runs the k46 line WITH an A3000 WD, so C4-1
§4.3's "no set of record" sentence is wrong for k46 and spec 30 §5.3's 040/060 board sets lack every no-Z3660 set — the
A3000 WD behind a Zorro board is an accepted rename on both lines (D-3 §11), to be written in (C4-1 v2, 30 §5.3).

## 2026-10-26 — C4-4 v3, C3-5 v7, boot2 savings 1–2, S4-10 placement, core patch 0035 (d7d1cd7..a51089b)

C4-4 v3: boot2 places every root record (in safe mode the `safe=1` set, flag 0x4 from it) and never evaluates match=; the
core matches at marc_root; kbootset's gate 4 checks the whole set (files + bss tails) against the capacity so L5 is a
backstop; boot2 writes no parameter strings (the core reads params from the manifest copy); L7 retired; the accepted cost
(a few hundred KB more read per boot from a disk store) recorded, S4-70 the arena check. C3-5 v7: `safe=1` on the safe
set's records; match= read by marc_root. boot2 savings with nothing changed on the console: rel.c's notes only for b2link
(138 B), the loader build of manifest.c skipping boards/cpu/created/param (176 B). S4-10: boot2 lays the directory, the
manifest copy and each root module 16-aligned, CRC-checked, with its zeroed bss= tail, then L5; "module %s %u bytes" per
module; amix-cdboot shares it. File 28 526 (146 left), image + bss 28 312 (360 left). Core patch 0035: marc_root reads
match= and checks it with marc_post's matcher, skipping an unmatched entry silently (harness 233/233; dlm.o 1fb106c4).
Not yet run on the emulator: boot2's placement needs root records (S4-12); S4-72's rows are the check.

## 2026-10-26 — boot2 headroom: the file gate binds (316 left); S4-10 measured (661ca4e)

b2link gates two figures: the file (image + self-relocation table), 28 356 → 316 left, and image + bss, 28 156 → 516 left;
new code grows the table too, so the file gate binds. S4-10 measured as C4-4 v2 lays it out: boot2 evaluating match= per
zorro key costs +744 (428 over the gate); boot2 placing every root record with match= left to the core costs +448 (132 over);
reading bss= is free. C4-4 v2 §2's safe-mode rule cannot be done in boot2: a motherboard root record carries no controller id,
so boot2 cannot tell an A3000 WD, Gayle and the 53C710 apart — kbootset can, from kinfo's card table.

## 2026-10-26 — C4-2 draft: what a root-class driver changes (24e1ae1)

Its own contract beside C3-6 (which still governs every module). `.moddata`: class=root, match required, rank for disk
controllers, unload=never, depend only on root modules, sections that run in place (alignment ≤ 16). `_load` in the root pass
(level 7, clock stopped): no sleep or wait, KM_NOSLEEP ≤ 1 MiB checked, no file I/O, polled probes; 0 = linked, ENXIO = no
board (silent); allowed names = every *any* DDI name, kmem NOSLEEP, sd_register, root_defer, and four *proc* names the static
root drivers use in init_tbl today (autocon, bprobe, sptalloc/sptfree, dev_kvmap on k46) — S4-71 confirms them on both lines
with a probe module before any port ships. `root_defer(fn, arg)`: a new DDI name (minor 1; S4-05), up to 8 calls run once
each at the first sysinit entry in process context at level 0 before any boot-class load — intr_attach, self-test and enable
live there, polled until then; the calls run in safe mode too. sd_register per board with its class. `_halt` from dlm_halt.
DMA only through C4-5. A row per driver (z3660scsi, A4091/A4092, the 53C710, Gayle, ramdisk) with match, rank, interrupt path.

## 2026-10-26 — Core patch 0034: marc_root, the arena's root modules linked (S4-04, 82cc554)

`dlm_marc_root()`, the kernel's hook in rth1_mountroot before rth1_apply (C4-4 §4): walks the arena directory in order in
no-sleep mode, re-takes each entry's CRC-32 ("damaged; not linked" on changed bytes), requires the manifest copy's root record
with that name and crc32= (taking its bss=), then dlm_load_mem; ENXIO silent, other errors one line; safe mode links flag-0x4
members only; no arena or no root entries = nothing (safe on any module kernel, not for static families); it must run before
sd's first open so sd_register's entries land before dlm_sd_close. dlm_arena_init keeps the arena's address; dlm_crc32 gives
the loader's CRC-32; a file off 16 has its own console line. Harness 231/231 both kernels; dlm.o 446c81cd.

## 2026-10-26 — C2-3 v7: sidecar keys are read by name (fadc007)

Their order carries no meaning (the S4-21 k46 sidecar places sdcards= before root=; fine). The S4-21 k46 cut of record
(5a7028c0) checks abi=fea18182 with mkabi --check and no cputype note; the fc6ae88f thread is closed.

## 2026-10-26 — C2-3 v7: sdcards= in the kernel sidecar; kbootset km_tail (cbba08f, 60e7eb1, 3b74296)

C2-3 version 7: `sdcards=` = the sd cards the kernel was built for, absent = 2; the S4-21 kernels write 4; written by the
kernel build's sidecar tools (a sidecar from before is re-stamped, not the kernel), passed through by amix-packages, read by
the installer from /stand/kNN/kabi before making nodes or naming a disk; never inferred from the kabi minor. kbootset
km_tail computes a root module's `bss=` by core patch 0033's layout (make test 692/692). C3-5 v6's text: `bss=` counts every
COMMON (an upper bound). S4-12's record writing (at=, bss=, crc32=, placement, gate 6, the board set, safe-mode flags, media
with a ramdisk member, two-digit card names) follows S4-04.

## 2026-10-26 — C4-4 v2 and C3-5 v6 (bss= on root records); core patch 0033, the arena load path (88c7618, bc1dc58, 68623c8)

C4-4 version 2 (agreed): boot2 reserves each root module's `bss=` zeroed tail behind its file (file end rounded up to 16)
and counts it for L5; the core runs the PROGBITS in place and lays NOBITS and COMMON into the tail, one span per module
(spec 10 §5.3 follows). C3-5 version 6: `bss=` on root records, written by kbootset by the core's layout rules, even when
0. Core patch 0033 (S4-01): `dlm_load_mem(name, p, len, bss)` — in-place layout (each PROGBITS at a file offset that is a
multiple of its alignment ≤ 16, else ENOLOAD; over the reserve → "its bss is over the reserved %d"), nothing allocated or
freed for the image, root class only from the arena and only root class there, a dependency must already be linked.
Harness 222/222 both kernels; fingerprints unchanged; dlm.o 2e7ca0c8. The CRC-32 re-check and membership check are the
marc_root walker's (S4-04).

## 2026-10-26 — Core patch 0032: sd_register, C4-1's registration (S4-03, a15104e)

`sd_register(queuefn, c, base, name, rank)`: a root-class controller registers each board from its _load; the entries wait
in the core's table of four until sd's first open takes them (`dlm_sd_close`), later registrations are EBUSY; the rank must
equal the module's `.moddata` `rank=` class (z3660/zorro/mobo/ide; unknown = ECONFIG); a fifth is ENOSPC; a failed _load's
entries are swept. DDI name of minor 1 (a new "root" context). Harness 214/214 both kernels; the 1.1 fingerprints unchanged;
dlm.o 4d0f4815. S4-21's cut of record takes the core at a15104e on both lines with the sd seam (dlm_sd_close in sd's init,
inert until a root-class module exists) — no third cut.

## 2026-10-26 — Core patches 0030 (the halt pass) and 0031 (block rows); kabi k46.1.1 / k30.1.1 (3e4c3a0, 99a61ea, 1aba361)

0030 (S4-07): `int dlm_halt(void)` runs each settled module's halt entry newest first, once; the kernel calls it from mdboot
before haltsys/rtnfirm for A_SHUTDOWN/A_REBOOT only (spec 30 §2 patch 11; OQ-30.5 answered: no crash). 0031 (S4-06): a pinned
driver's registered b: majors fill empty bdevsw rows; block-only allowed; a block row that cannot link puts the character rows
back; a failed load restores the row. The measured bdevsw layout (DRV_BDEVSW, DRV_BMAJOR, BD_NFN, BD_FLAG) opens the stage-4
kabi minor: abi-k46.1.1 and abi-k30.1.1, both fea18182 (identical texts; run.sh prints fc6ae88f for the -61 k46 base,
compared with cputype size 0); the kit moves to 1.1. Harness 206/206 both kernels; kit-test and
make test clean; dlm.o 8918560f. **No dlmkit mint from 1aba361 until S4-21's 1.1 kernels exist** (a 1.1 kit's modules are
refused by 1.0 kernels); dlmkit -5 stays the kit for 1.0. For S4-21: row 20's stock ram entry becomes bempty (every routine
nodev, flag 0).

## 2026-10-26 — Core patch 0029: no-sleep mode for the root pass (S4-02, 7f0613e)

dlm_nosleep makes dlm_zalloc ask KM_NOSLEEP and refuse requests over 1 MiB (U1's rule); every load-path allocation is
checked and ENOMEM leaves the kernel as it was (kmem bytes and blocks exactly as before, loaded count unchanged); a module
another load holds is EBUSY instead of a wait. Nothing changes outside the mode. State harness 197/197 on both kernels; the
fingerprint unchanged (7a90c7d9). dlm.o b55f0b12; rides the second cut S4-21. Stage 4's ABI additions (bdevsw layout names
for S4-06, sd_register, vfs_register, DDI v1.1 DMA) open one kabi minor, k46.1.1 / k30.1.1, with S4-06.

## 2026-10-26 — C4-1 agreed (version 1); C4-4 draft: the arena filled (6c78656, cc5cbc3)

C4-4: boot2 places every `module … root` record whose match holds, in manifest order (`zorro:` against
bootinfo.autocon[], `mobo:` always with the module's gated probe deciding in _load, `always`); kbootset writes the records
in depend order, the core links in directory order; flag 0x2 "forced" reserved. A CRC-32 mismatch on a module is L3 then as
L2 (next generation, then the menu); L5 on overflow. Safe mode places only the root controller's module (from the `root`
record), the `rootfs` module and their depend closure, flag 0x4. L7: no root controller on the floor or placed — print the
boards and boot anyway. At marc_root the core re-checks the CRC-32 ("root module %s damaged; not linked"), membership,
relocates in place, _loads; ENXIO silent, other errors print and unlink after undoing registrations. AXA1 stays C3-4 v1.

## 2026-10-26 — C4-1 draft: sd_register and the four-card contract (323ace9, 0bd8508, b74484d)

Minor bits: unit 0–2, card low bit 3, slice 4–6, card high bit 7; names in hex c0–cf and c10–c1f for cards 2–3 (card×8 +
target, as today); four rank classes (z3660, zorro, mobo, ide) then base; EBUSY after sd's first open. Spec 30 §5.2:
sd_register(queuefn, c, base, name, rank), no probe function (a module probes in its _load); a2091/a2090 need no four-card
rebuild; spec 20 §6's registry row names the classes. The 1.0 order fact (an answering A3000 WD ahead of the Z3660) cannot
occur on an A4000 — not a set of record. The plan records the A4092's metal rows as stage-5 carries and S4-33 in amix-a4091.
Same wave as S4-21: installng's and kerntools' one-digit tools (the port's ENUMERATION.md §D); kbootset's name forming.

## 2026-10-26 — Stage 4 re-scoped by the owner's nine answers (288ac3d, d350bc2)

Spec 80 §2: stage 4 = "Root, filesystems and media" (root controllers, ufs/s5/cdfs as modules, every medium of spec 50
proven); stage 5 = "Carried metal and release acceptance" (the 030 line on the release firmware, the tower's Zorro-dependent
rows, every medium rebuilt from the final packages; a carried row that changes a shipped byte re-proves every medium carrying
it). §4 settles Q4-1…Q4-9 one line each: filesystems and media in; the self-test pass at the first sysinit entry; the
four-card naming now as a merge request; row 20 freed in the second cut S4-21 (the stock ram's bytes leave in S4-43); no wait
for the carried metal; DDI v1.1 DMA (C4-5) with an 030 bounce; the A4000T 53C710 written in stage 4 (S4-33, in amix-a4091);
the known survivor set (S4-54); the first media now (S4-55). New: C4-5, C4-6, S4-21–S4-25, S4-40–S4-43, S4-56.

## 2026-10-26 — Stage 4 plan (69423ed)

docs/plan/stage-4.md: interfaces C4-1–C4-4, rows S4-01–S4-74 (root-class modules and the arena-only load path, boot2 root
placement, kbootset; z3660scsi, A4091/A4092, Gayle IDE, ramdisk, the A4000T 710 contingent; the root filesystems ufs/s5/cdfs
started here and proven at stage 5 per 80 §2; the compressed miniroot, netinstall, the CD installer, the floppy pair, the
upgrade survivors; the first stage-4 cut with core 0027/0028 and the ZS-05 static drivers; the first stage-4 media; the
carries: 030 metal on the 1.1 release firmware, the tower's rows, OQ-80.5, the C3-6 register-write rule), constraints taken as
measured (U1/U15/U2/U4, 256 KiB, the k30 64 MiB cap, the arena, boot2's 516 B, level 4, ZS-05), nine owner questions in §4
with recommendations; docs/plan/stage-4-exit.md skeleton. No spec change.

## 2026-10-26 — Stage 3 closed (6f38d2e)

S3-46 metal on the A4000D (amix-kerntools ee06634, M3–M7): M3 polled PASS, M5 INT6 on zeth 1.0.0-4 PASS (0 % loss over
6000 pings + FTP), M6 rtg + monsw PASS; M4 INT6 on zeth 1.0.0-3 FAIL (attachment passed, receive under load failed — the RX
ring wedge, fixed in -4); M7 k30 in 030 emulation mode unproven on metal (golden firmware line), not a module failure.
M-THR1: no regression (FTP 277–489 push, 497–582 pull KiB/s against ~185; RTG 69.7 µs per op against 76). Carried into
stage 4: 030 metal on the 1.1 release firmware (OQ-80.6) and the A4000T's rows after its expansion-bus repair. Findings
noted: M4's 30 lost directory entries and M3's unplanned stall, both followed up by the tripwire proving boot.

## 2026-10-26 — Exit ledger: S3-46 progress on the A4000D; 030 mode to stage 4; OQ-80.6/80.7 (0d7777c, 21d506c)

k46: INT6 attachment on metal PASS (221 counted); the interrupt-mode flood failure is a z3660eth defect (the RX ring wedged
at the sentinel, fixed in 1.0.0-4, retest pending) plus a firmware backlog race (fixed in the Z3660 fork, unflashed); polled
zen0 PASS (2000/2000 at 5 ms); M-THR1 PASS as modules: FTP push up to 352 and pull up to 582 KiB/s against ~185, RTG 69.7 µs
per op against 76, 186.6 µs per ioctl against ~200, 5.4 µs per register write against ~7; rtg + monsw PASS. k30 in
UAE_030_MMU: "030 emulation mode unproven on metal (golden firmware line)" — the 9994961A core1 double-faults early
Kickstart (31 attempts, two A3000 ROMs); carried into stage 4 on a 1.1 release firmware (spec 80 OQ-80.6: the amix-main +
1.0 merge built for metal). OQ-80.7: a spacer between back-to-back Z3660 register writes (the FPGA's address capture); its
C3-6 rule waits for the proving boot. OQ-80.3 answered; the overview indexes OQ-80.5–80.7.

## 2026-10-26 — Exit ledger: S3-44-3 and S3-45 PASS; S3-46 on the A4000D (85b7026, baabf5c)

S3-44-3 PASS on both lines with z3660eth 1.0.0-3 (N90, N91; the level-4 STREAMS open explained 1.0.0-2, intrl2=0 confirmed
it). S3-45, the exit row, PASS on both lines (N88–N92): network and graphics from modules, the monitor switch, an apkg
upgrade of module packages building and committing generation 2, rollback; a monsw-only upgrade with identical objects
correctly commits nothing. S3-46's exit evidence is the A4000D: every stage-3 module is the Z3660 card's, the same in either
box; the A4000T's rows (its onboard 53C710 and expansion bus) open stage 4's metal after its EAD_12/13 repair (spec 80 §2,
plan S3-46). README: on a 1.1 install syslogd files nothing until the install ships /usr/ccs/bin/m4; -L is the record.

## 2026-10-26 — C3-6 v4 §1.3: the interrupt level each driver entry runs at (d7af4b8, 937a373, 32ca41f)

_load/_unload of a boot- or demand-class module: level 0; a character d_open: the opener's level (spec_open writes no SR);
a STREAMS open: level 4 under the stock qattach (SR 0x2400; the trampoline leaves it), so a level-2 self-test half needs
one-tick timeout/sleep rounds (z3660eth 1.0.0-3's way) or runs at _load; root class at marc_root: level 7 with the clock
stopped (U1), no self-test there — attach, test and enable at a later process-context point, polled until then (the
gayle-ide module form's stage-4 case). Core patch 0028: the fact in dlm_str_open's comment (dlm.o b808cb52 unchanged).
The guide (§4) notes it, and that a driver without a read entry answers ENODEV, as monsw does.

## 2026-10-26 — Exit ledger: S3-44-1 and -2 PASS; -3 open (93c5e2d)

N86/N87: software interrupts reach both chains at once (0 spins), the level-6 claimer and counter counts are equal; a full
level-6 chain refuses the ninth handler with 168 and z3660eth falls back to polled; monsw's open is silent and loads it, a
read gives ENODEV by design. S3-44-3 open: the likely cause (kernel of record) is that a STREAMS open runs at IPL 4, so
z3660eth's software self-test can take the level-6 half but its level-2 half stays pending until the open returns —
z3660net's to fix; `intrl2=0` with intr=6 is the cheap confirmation.

## 2026-10-26 — Exit ledger: CD cell k46 PASS; K030-UZ and N84 (f25775f)

S3-31 part 3 k46 PASS (N85c); part 3 closed on both lines. S3-46's k30 instrument K030-UZ (a measurement kernel, retiring in
stage 4 with the root-class z3660scsi) recorded; its piscsi root proven on the emulator (N84). S3-44, S3-45, S3-46 remain.

## 2026-10-26 — S3-31 part 3, k30: PASS; the installed disk keeps boot priority 2 (73f218f, f6c770b)

The CD-booted, disk-rooted cell passes on k30 (N83c): amix-cdboot's line, the kernel at 0x04000000, the root record,
multi-user from the disk, the read-only-medium lines, the store byte-identical. An installed disk keeps boot priority 2;
the disc's node only ties it and the disk wins the tie, so a disc left in the drive never takes over a box. The CD is chosen
in the Kickstart early-startup menu or by lowering the disk's priority below 2 (stage-3-cd-boot.md §5, spec 50 §4 Rescue).

## 2026-10-26 — S3-44 rows, ledger gates restated, CD gate 3, namelist 0644, C3-5 v5, modcheck warning (f7eff90..5491d61)

S3-44's bench rows (README S3-44; probes t44intr and t44fill): the chains on the kernels of record, a full chain with
z3660eth's polled fallback ("zen: level-6 attach failed (errno 168); polled"), z3660eth 1.0.0-2 with intr=6 — no z3660net
build owed. Exit ledger: S3-27 done (monsw30/46 1.0.0-1 from amix-modules c0386d9); S3-31's box run done (installng's media
of record); S3-44/S3-45/S3-46 gates restated (none owner-gated); S3-46's k30 row on a bench variant kernel, the 1.1 record =
stage 4's root-class z3660scsi. kbootset: on `media --cd`/`--floppy` gate 3 checks only the root controller and filesystem
(C2-4 v11 §13, spec 40 §3.1; a --bootdev is noted and unused); `namelist` writes /stand/unix 0644 whatever the umask; box
kbootset d44f6a32 (→ kbootset -15). Spec 80: OQ-80.1 (030 metal), OQ-80.5 (an A4091 root on an 030 Z3660 needs a bounce or a
motherboard bind). C3-5 v5 §1.3: no rc script trusts a pid from an earlier boot (the stock syslogd case, zero margin).
modcheck warns when a demand-class load's working set passes 160 KiB (kit-test 64/64). monsw's ENODEV is the read (no
d_read: nodev), not the open — one Bench check confirms.

## 2026-10-26 — U2 answered; the process-context total (0bacad5, 52b903c)

N81 (k46 at 128 MB) / N82 (k30 at 64 MB): in process context after multi-user a module gets 320 KiB (320–383) resp.
640 KiB (640–703) of KVA in total with KM_NOSLEEP. Spec 30 §8: the working set of a load from a file (file buffer rounded
to a power of two, tables, image, module table — all at once, all KM_SLEEP; monsw ~15 KB, z3660eth ~57 KB, z3660rtg ~67 KB,
a cdfs-sized module ~232 KB, a module at the limit > 512 KiB) stays well under k46's total; C3-1's 256 KiB is a ceiling,
not a budget; larger modules are boot or root class (arena: no kmem for file or image). Spec 90 U2 answered. Exit ledger:
the S3-43 rows of record (N65–N76) and U2.

## 2026-10-26 — README: the stale syslog.pid as the conslogging 0 cause (340cfcb)

"conslogging 0 and no syslogd in ps" names its likely cause: the stock /etc/init.d/syslogd trusts a stale /etc/syslog.pid,
and the dlm sysinit line plus S01kbnamelist shift the early pids onto a live process (both together, 6/6 on the k46
vehicle; the installer's unit is fixed in amix-installng). No shipped script runs -K. No repair recipe: unverified.

## 2026-10-26 — Exit ledger: core patch 0027 rides the stage-4 kernel cut (ada916c)

The kernels of record keep dlm_maximage 2 MiB; the kit's modcheck guards every module meanwhile; a stage-3 re-cut would
force a third remaster of the media of record.

## 2026-10-26 — C3-1 v4: a module's image at most 256 KiB, its file under 256 KiB (07689e6, 1082c0c, 2ee5916)

From U4: the core's own KM_SLEEP allocations grow with the module (ten call sites, C3-1 §6: lf_hashload's buffer ×2,
ld_sh, ld_secoff, ld_syms, ld_str, ld_ls, oh.b, ld_tab, m_alloc), so a module much over 256 KiB would hang modload as
u4big did. The file limit comes beside the image limit because lf_hashload reads the whole file into one buffer doubled
up to dlm_maximage (cdfs: 97 611-byte file for a 69 080-byte image). §6 records the way past the limit (pieced KM_NOSLEEP),
not planned work. The kit's modcheck refuses a larger module at build time. Core patch 0027: dlm_maximage 256 KiB at the
next kernel cut, an oversized file is ENOLOAD "its file is over the limit" (before, a silent ENOMEM); dlm.o 77f1ef80 →
b808cb52; the kernels of record keep 2 MiB until then. kit-test: five edited-module refusal cases never ran (edit() wrote
into unmade directories and skipped without a failure) — revived, 62/62 both lines; printf for the \0 text. Module guide
§6 "Size and memory". Kit at KIT_REV 2ee5916 = the HEAD for dlmkit -4. Producers today: 18.8 / 30.8 / 5.2 / 97.6 KB files.

## 2026-10-26 — U4 answered; kmem requests at most 256 KiB; kit.conf fix (fca6140, 6c3b581, 134731f)

U4 (N79 k46 at 128 MB, N80 k30 at 64 MB): after multi-user one kmem request gives 256 KiB on k46 and 512 KiB on k30
(the fixed 4 MiB kernel map shared with page[] and the u-areas; page[] grows with RAM), and a KM_SLEEP request above
that never returns. Spec 30 §8 and C3-6 §1: a module's requests are at most 256 KiB each, KM_SLEEP only up to that,
every KM_NOSLEEP checked, larger buffers from pieces; root-class _load at boot keeps U1's rule. U2's probe takes 64 KiB
chunks (k46 fc7d439c, k30 34c32892) and runs in a boot of its own. README: -L's conslogging word tells the vehicle from
the kernel. mkkit: MONSW_REV is `repo@commit` (a space broke every `. kit.conf`; kits from 6492c3b..c6c9d02 affected,
the staged dlmkit -3 at c6ad5bd is not). kit-test 50/50.

## 2026-10-26 — README S3-41: U2/U4 need a generation with the arena (4041e80)

The S3-41 U2/U4 generation must carry the arena (l14.spec's form with the kernel's own arena and ident, or build's):
development load widens what may load but does not replace the manifest, so a noarena generation refuses every load
("no booted manifest, so no module loads this boot"). `modadmin -K` first on a box without a console logger.

## 2026-10-26 — modadmin -K keeps kernel messages in putbuf too (662de06)

Core patch 0026: `modadmin -K` (root) sets prt_where's PRW_BUF bit through the namelist and /dev/kmem, so every kernel,
core and module message is also kept in putbuf on a box with no console logger. Background: after boot printf stores into
putbuf only through the console logger (consbuf → log driver → logcons); the k46 vehicle has none registered (conslogging
0), so its run-time lines went to the console VT and were kept nowhere — the k46 S3-43 gap, a vehicle difference, not the
port kernel. README: when -K is needed, once per boot after S01kbnamelist, the console keeps every line, the 2000-byte ring
wraps (read `-L | tail` after each action), a line can appear twice more on a box with a logger. dlm.o unchanged; box
modadmin 0518fb28. Rides the next modtools mint.

## 2026-10-26 — spec 10 §7.3: a one-shot request boots the default (8e0b17a)

A one-shot request takes its boot ahead of a pending trial, and devload and safe requests boot the default generation,
never the trial (select.c's design: a diagnostic boot of the known-good default must not spend a new generation's one
attempt); a loader on trial also boots the default and consumes the request. Mark a new generation good before
`kbootset next devload`. README U2/U4 sequencing (the Bench's two void S3-41 tries).

## 2026-10-26 — U1 answered: root-class context at boot (806768d, b2930e4)

N77 (k46 5c4fad37) / N78 (k30 ce689ab4): at dmainit and at the rth1_mountroot hook both lines run at priority 7 (sr 0x2704
and 0x2700 are the same state, the low nibble is condition codes) with the clock stopped, so KM_SLEEP, sleeping and
timeouts are unsafe there; KM_NOSLEEP gives 1 MiB on both lines (k30 refuses 2 MiB at 64 MB; k46 gives 2 MiB at 128 MB).
Spec 30 §3 (after freeze): a root-class _load allocates KM_NOSLEEP only, at most 1 MiB per request, each checked; more comes
in pieces or later from process context. Spec 90's U1 row answered, exit ledger §4 filled, docs/measurements/2026-10-26-u1.md.
README U2/U4: `kbootset next devload` only once the installed loader is accepted (a loader on trial boots the default
generation and spends the one-shot).

## 2026-10-26 — modadmin -L prints the message buffer's words first (d834597)

Core patch 0025: `modadmin -L` starts with one line of the ring's words (putbufsz, putbufwpos, putbufrpos, conslogging,
prt_where), each read by lseek on /dev/kmem (a `dd skip` into kmem reads its way there from 0 and hangs the box). The ring
is printed from the byte after putbufwpos (the stock printf stores after a pre-increment; before, the newest byte came
first), text only: the log driver's logcons copies strlog data blocks with their header bytes into putbuf, and a cmn_err
line enters twice (xprintf and the log copy). dlm.o unchanged; box modadmin eeea43b3. Written for the k46 run-time-line gap
(S3-43): the code and initial data of the five putbuf functions are byte-identical on k46 and k30, so the words decide it.

## 2026-10-26 — boot2 gets 516 bytes of headroom back (aad576f, ea90332)

ax_ctl_pick parses the control block's copy A into the caller's structure and keeps one 488-byte scratch instead of two
(boot2's bss 1380 → 892; the struct is undefined on AX_ENONE and every caller stops there). boot2 28356 B, 344b8e07, 516 B
under the 28 KiB gate; nothing on the console changes. docs/measurements/2026-10-26-boot2-headroom.md records the per-part
sizes, the ranked next savings (free ones first) and every quote of the two messages shortened in 001b04a. Not packaged:
loader-amix -6 waits for the next loader change with a reason of its own.

## 2026-10-26 — boot2: a k30 kernel gets at most 64 MiB of fast memory; Z3 RAM is never kernel memory (001b04a, b7a1148)

ax_memcap caps the fast region holding a k30 bind address at base + 64 MiB in bootinfo.memory[] and empties a region touching
it from below (the stock support.c joins touching regions into the main store; over ~64 MB the 2 KiB-page kernel never starts
— N70, N75); the L4 fit check uses the capped room; k46 untouched. Spec 10 §3 and 40 gate 6: either line's kernel uses its
bind region only, so Zorro III RAM is never kernel memory. README: S3-43-8's kinfo expectation, new S3-43-9 (k30 in a 128 MB
bank), S3-43-7 and U2 in the CPU board's bank. boot2 28 392 B (6147ab3b) fills its gate exactly — 0 bytes left: the next
loader change must give bytes back first. 683 host checks; amix-cdboot rebuilt from the same core.

## 2026-10-26 — C3-5 §1.3 the 2.1 sh's while-read and probe facts; kit NOTICE from MONSW_REV (32587ae, c6c9d02)

A while-read loop strips trailing blanks on the 1991 sh, so it is never a byte-exact copy (cat or dd and a size check are);
installng's probe list of what the 2.1 sh does with redirections is recorded. The kit NOTICE names sys/monsw.h's origin from
MONSW_REV (amix-modules c0386d9, MIT); kit rebuilt at c6c9d02.

## 2026-10-26 — C3-5 §1.3 the script rule as enforced; C2-2 §2; kit.conf MONSW_REV (6492c3b, dc54ff4)

C3-5 §1.3 states the package-script rule as amix-packages' gate enforces it (sh builtins plus mv, cat, ls, dd, expr behind
test -x, refusing without; read only in a child with one redirection; the forbidden constructs; cat/dd copy, a size check
before every mv; proven on the 2.1 sh). C2-2 §2: a module record has a file line per plain file (the object and its modreg.d
file), none for the device node. kit.conf records MONSW_REV (the repository and commit of sys/monsw.h); the kit is rebuilt at
dc54ff4 with monsw.h from amix-modules b954ce9 (KIT_REV dc54ff4, PORT_REV ebe8dfd).

## 2026-10-26 — kbootset -14 deflates on the box; modadmin -L reads the kernel's message buffer; README fixes (9f175bf..7e731f9)

kbootset -14: its own raw deflate (kdeflate.c: fixed Huffman, LZ77 with hash chains, one byte of lazy matching) where zlib is
absent, so `--spec z=deflate` stores the member deflated on the box (-58: 2 431 362 → 834 032 B; K030-U 1 715 944 → 636 890;
both inflate through the loader's inflate; before, the null hook stored raw silently and gate 5 refused). Core patch 0024
(user side only, dlm.o unchanged): `modadmin -L` prints the kernel's message buffer (putbuf/putbufsz/putbufwpos through
/stand/unix and /dev/kmem, oldest first) — the read path for run-time lines of record, which the console does not show after
boot. README: where each line of record is read; S3-43-4's spec line takes bss= and z=deflate. mkkit takes sys/monsw.h from
amix-modules/include/sys/. 677 host checks; box kbootset 9acb9add, modadmin 7329e183.

## 2026-10-26 — monsw's home is amix-modules; kbootset -13: a boot from a read-only medium (e319d85..b6b4b87)

monsw lives in amix-modules (plan S3-27, Q3-2 settled; C3-6 §4; the kit ships include/sys/monsw.h — interface headers of
generic modules ship with the kit, versioned with their module; registry: b 20 ramdisk's home is amix-modules). kbootset -13:
on a boot from a read-only medium (AXL1 flag 0x08 — the CD, the floppy pair — with no boot node) mark-good marks nothing,
retry does nothing, status says the medium booted and marks none of the store's generations as booted, and the namelist comes
from the line's installed kernel when its build id is kinfo's (else "no namelist: booted from a read-only medium whose kernel
… is not the one installed here", exit 3). C2-4 v10 §13; 10 §6 names the AXL1 flag bits. Plan S3-31 and the exit ledger
carry part 3 as decided. Box kbootset e56172b6; KIT_REV=b6b4b87 (PORT_REV ebe8dfd).

## 2026-10-26 — C3-5 §1.3 the 2.1 sh's read; C2-2 §2 device nodes; the CD boot tree recipe (9000802, 42dd80d)

C3-5 §1.3: never re-read a file through `exec <file` — the 1991 sh's read keeps its buffer across the redirection and
continues where the previous read stopped (modtools -3 wiped /etc/inittab that way); one redirection per pass; scripts are
proven on the 2.1 sh. C2-2 §2: a module package's device node gets no `file` line in the record. docs/plan/stage-3-cd-boot.md:
the CD boot tree recipe per line (`kbootset media --cd`, `mkstore -C TREE -x amix-cdboot`, Startup-Sequence → SYS:BOOT/
amix-cdboot), what is unproven (the whole CD path has never run on any box), the emulator needs (an A4091 ROM with the
ODFileSystem profile), and the first cell: a disk-rooted generation booted from the CD; the installer CD (RAM-disk root) waits
for stage 4's ramdisk module.

## 2026-10-26 — boot2 binds the kernel only below 0x40000000; ledger and README updates (92d2924..d51fb2c)

A kernel bound in Zorro III expansion memory never starts (S3-43-7, N69/N70): the kernels identity-map the low 1 GiB and keep
syssegs and the sptalloc arena at virtual 0x40040000–0x40440000, so text at 0x40000000 is unmapped or overlapped once
translation is on. boot2 clips every region at AX_IDMAP_TOP = 0x40000000 (the stock bind.c had no such limit); with no fast
memory below it: "no fast memory below 0x40000000 to run the kernel in", L4, the next generation. Loader version stays 2
(manifest untouched); boot2 28 136 B (e36c1c55), 236 B under the gate; amix-cdboot rebuilt from the same core.c. Spec 10 §3
states the rule; 40 gate 6 is an estimate counting all fast memory, L4 is the binding check. README S3-43-8 is the row.
Exit ledger §2: all twelve B rows pass; README carries the sweep's three deviations. make test 671 checks.

## 2026-10-26 — S3-41 recipes (U1 by -DDLM_U1, U2/U4 probes); core patch 0023; the stage-3 exit ledger (1ca60a0..377866f)

U1 (the process-0 load context) is measured by a -DDLM_U1 build of each kernel of record: core patch 0023 prints at the end
of dlm_init and at the hook the SR, u_procp, whether the clock ticks, and five KM_NOSLEEP allocations up to 2 MiB; without
the flag dlm.o is byte-identical. U2 and U4 by the probe modules u2kva and u4big (tests/bench/s3-41/mkprobes.sh, built with
the kit, development load at 128 MB). 90 names the recipes; U15 stands answered. docs/plan/stage-3-exit.md: the bytes of
record per line and every row's result; plan Q3-2 records monsw, z3660rtg's dependency and the metal rows as open.

## 2026-10-26 — C2-2 §2.1 as apkg 0.3.1; C3-5 §1.2 device nodes; the S3-43 hand-over (47941d0, 568b9ac, cb64436)

C2-2 §2.1 follows apkg 0.3.1 (`apkg recover` finishes a cut; the readings confirmed). C3-5 §1.2: a driver module's package
ships the device nodes of its majors as pkgmap device entries (z3660eth /dev/zen0 c 51 0), no script; S99zen does the network
plumbing. tests/bench/s3-43/handover.sh writes one line's inputs for the acceptance sweep: the module set (tree/, s43/), the
checker's and host loader's verdicts, l14.spec, l5.img sized to the vehicle's boot slice (gen 1 good + gen 2 on trial with a
64-byte arena), SHA256SUMS; L5's line of record is "the arena needs 337 bytes, it has 64" on k46 and 367 on k30.

## 2026-10-26 — C2-2 v5 one kernel package per line; the stage-3 mint's package conventions (0d49ddd, 2a9cd81)

C2-2 v5 §2.1: installing a kernel package replaces the line's other kernel package in the same transaction (pre-flight of
every installed module record against the new kernel; pkgrm and record of the old one before pkgadd and record of the new;
one trigger; recover finishes a cut; two existing records of one line refuse) — apkg 0.3.1. Conventions: a kernel catalog
row carries line/kabi/pin from the sidecar and kbootset reads the rest from the installed sidecar; a module row takes
kabi/pin from .moddata and has no depend= (gate 3 enforces dependencies); file= under base/; module packages CATEGORY
system with mod.d/modreg.d files and modes as minted, modreg.local.d never shipped; K030-U's version is k30.1.0.261026-01;
an ET_REL kernel needs no bss= or sym=.

## 2026-10-26 — kbootset reads unix.sym as ET_EXEC by section name; L5 as L2; C2-3 kernel names (9763024, bb088bb)

kbootset reads unix.sym as an ET_EXEC whose st_value is the address with the kernel bound at 0 (no section base added) and
tells its NOBITS sections apart by name — before, every NOBITS section counted as bss and rodata/data read as 0 (the symbol
values were right; the k30 layout check compares only text). s3-standin.sh carries the sidecar's sym= file and record line.
Spec 10 §9: L5 is handled as L2. C2-3 v6: the unix.sym form (ET_EXEC, st_value = value at bind 0, section symbols move by
the bind, SHN_ABS constant but etext/edata/end); module kernel packages kernel-k46-m/kern46m and kernel-k30-m/kern30m,
version <kabi>.<yymmdd>-<nn> from the build id. The k30 S3-43 set rebuilt from the s3-21e .etrel. Box kbootset cd02b817.

## 2026-10-26 — S01kbnamelist; C3-5 module/VERSION; the S3-43 recipes and the rule-breaking module set (e024b55, 8be28b8)

C2-4 §12: the early rc2 script is S01kbnamelist (rc2 runs S* in byte order; S02PRESERVE would sort before S02kbnamelist).
C3-5 §1.1: a module repo records its package version in module/VERSION (z3660eth 1.0.0-1, z3660rtg 1.1.0-1). The S3-B5
z3660eth hashes are final (kit e84878e). tests/bench/s3-43: mkset.sh builds the module set with the line's kit — stand-ins
monsw and z3660rtg, t43boot/t43leak/t43fail/t43rel, t43ext, and ten rule-breakers each refused for exactly its rule (the six
load-time ones with C3-1 §4's errnos through the staged host loader); boot2.sh writes the L14 spec and an L5 store image;
oracle.sh compares t43rel's bytes in box memory with the host loader's image; README rows S3-43-1..7.

## 2026-10-26 — kbootset -12: the booted kernel's namelist; C3-5 v4; the shipping kit (cf49440..e84878e)

`kbootset namelist` writes /stand/unix, the booted kernel's namelist, as an ELF32 ET_EXEC whose symbols carry this boot's
addresses: kinfo v2 and v3 read, refusal on a layout mismatch against kinfo's bootdata (status 3 with the reason, the file
untouched), written as a new file renamed into place (a hard-linked 2.1_unix survives), run from mark-good on every boot and
from /etc/rc2.d/S02kbnamelist; status reports current, stale, missing or none. Verified against the kernels' own symbol
blocks at two binds on both lines; the k30 brel through unix.sym (`nlmake <etrel> 0 unix.sym`). C3-5 v4: module package
names (<name>-<line>, pkginst zeth30/zeth46, zrtg30/46, monsw30/46; the module's own version), package scripts use sh
builtins plus mv only. C2-4 v9: S02kbnamelist after S01MOUNTFSYS; §11 no copy step on the box. C3-3 §4: abi= required only
with arena=. C2-1 table fixed. Box kbootset 4a09a6dd. Kits rebuilt clean: KIT_REV=e84878e, PORT_REV=617c64e.

## 2026-10-26 — the booted kernel's namelist: C2-1 v3, C2-3 v6, 40 §4.2, C2-4 v9 §12; C3-6 v3; kit names (d9558a6..41a382d)

The stock netstat, ifconfig and crash nlist /stand/unix, which on a 1.1 disk is a hard link to the stock 2.1 kernel. C2-1 v3:
kinfo carries the loader's bootdata block at 536 (40 bytes, bootinfo 0x650–0x677 verbatim), the module count moves to 576 and
the list to 580 (length ≤ 1604); flag 0x8 when bootdata's text vaddr differs from stext; readers accept v2 and v3. C2-3 v6: a
brel ships /stand/k30/unix.sym (ELF32 .symtab/.strtab, values bound at 0) with a sidecar `sym=` line. 40 §4.2 / C2-4 v9 §12:
`kbootset namelist` writes an ELF32 ET_EXEC namelist (symbols at bind + layout offset) as a new file renamed onto /stand/unix
when the content differs; mark-good writes it on every boot and an early rc2 call too; retry writes none (the root is not yet
repaired); the installer removes the stock /stand/unix and /unix and installs the rc2 call. C3-6 v3: _unload always exists and
runs on a failed load. Kit: every name within 14 bytes (abi.txt, docs/guide.md, C3-n.md), mkkit refuses longer; PORT_REV on
k46; the S3-22 row fixed (/usr/dlm/kit/<line>/, version scheme, extra/development, host-side container). kit-test 50/50.

## 2026-10-26 — core patches 0021–0022; the audit's non-kernel follow-ups (0481f30..2168509)

Patch 0022: a driver loaded at boot or by modload registers its own registry majors at install (dlm_sreg for d_str,
dlm_creg otherwise) — the first module boot's error 22; a demand-class STREAMS driver gets a console refusal (error 168).
The harness now builds dlm_str.c and dlm_ddi.c with host stand-ins and covers the boot-class character and STREAMS drivers,
the demand STREAMS refusal, the ifstats backstop with the module's link first/middle/last after a failed _load and a
forgetful _unload, and "_load attached but the linkage failed". Patch 0021: harness cases for the audit's untested branches.
Kit: modcheck checks drv_cmajor and COMMONs. make test checks libmod.c's syscall numbers against the core. Records: U16,
M-ABI2 with the block, M-CORE1 through 0021. Harness 191/191 both kernels; make core 124/124.

## 2026-10-26 — the final cut's base: kbootset gate 6 ET_REL bss; make core guards (6b2d669, f5ce731)

kbootset's memory gate counts an ET_REL kernel's bss (its NOBITS sections and COMMONs, aligned as rel.c lays them out) as
well as a brel's bss= (the re-cut KD060-Z: 284 172 B). make core fails when an allowlisted name has no provider and checks
core/plat's warnings; make test checks core/upstream/ against core/upstream.sha256 (48 files). core/series 0001–0020 as at
314c2aa. make core 124/124; 665 host checks. Box kbootset 013fe25f (-11), modadmin a206874d (modtools); KIT_REV=f5ce731.

## 2026-10-26 — core patch 0020: registration backstop; C3-1 §4 refusals (314c2aa)

After every _unload and after a failed _load, any interrupt handler, network interface or console hook still pointing into the
module is removed and named on the console. A section type outside the list and an image over the limit are ENOLOAD; each
refusal prints one line naming the module and the rule; parameter defaults must be in C3-1 §3's forms; .moddata word 0 must
be a single R_68K_32 with addend 0. The real modules are unaffected. Harness 175/175 both kernels; make core 123/123; 665 host
checks. Audit items §1.3 and §1.5 — the audit's kernel items are complete.

## 2026-10-26 — core patch 0019: code pointers in kernel text or the image; registry majors (dafa9c0)

A switch entry or STREAMS routine must be 0, kernel text [stext, etext) or the module's own image (kernel data and the arena
refused); a qinit's module_info and module_stat must be in the image; every character major a module registers or installs
at must be registered to it in the major registry (ECONFIG; a row held by another module is ECONFIG, C3-1 §4). The real
modules are unaffected (own-image routines, majors 51/49/52 registered to their names). Harness 169/169 both kernels; make
core 119/119; 665 host checks. Audit items §1.2 and §1.4.

## 2026-10-26 — core patch 0018: development load as C3-4 says; paths under /stand/gen (b633b3a)

With no booted manifest nothing loads, even under development load; under development load a manifest member loads from
its path= without the SHA-256 check and says so on the console; a member whose path= is not /stand/gen/<booted id>/mod/<name>
is refused. The state harness boots an empty generation at startup instead of relying on the removed behaviour. Harness
166/166 both kernels; make core 119/119; 665 host checks. Audit items §1.1 and §1.6.

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
