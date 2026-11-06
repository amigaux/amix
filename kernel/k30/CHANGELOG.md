# Changelog

## 2026-11-06 — cut 68030-261106-72, kern30m k30.1.4.261106-72 (9c00380, f8878fa)

kvseg (the kernel's map space) is 8 MiB instead of 4. kmem_freepool and kmem_free wake large requests that had to wait. The swap guard limits an area to 16 x maxmem pages, keeps 1 MiB of kvseg free in one run, exempts the boot area, and lets swapadd answer re-adds, duplicates and overlaps itself. A denied access gives a signal or EFAULT instead of a fault taken for ever; tas and cas on a read-only page give SIGSEGV; a core dump leaves pages with no access as holes. IP's lower read queue mark is 0x10000, so the A2065 no longer drops frames under receive load. kabi k30.1.4 and abi unchanged. KNOWN-ISSUES.md (including a large file written at random offsets reading back wrong blocks once it outgrows the page cache; under investigation) and docs/swap-areas.md added.

## 2026-11-04 — kern30m k30.1.4.261103-71.2 (161e3e2)

Same cut and objects: the copyright file names the amix-distfiles copy of GCC 2.7.2.3's source first and GNU's site as the original.

## 2026-11-04 — kern30m k30.1.4.261103-71.1 (08092ce)

Same cut and objects: the copyright file names the libgcc routines linked in (__udivdi3, __umoddi3, __lshrdi3, __clz_tab), quotes libgcc2.c's exception, carries GCC 2.7.2.3's GPL-2 text and says where the source is. DESC no longer names an internal recipe or a cut path. build.sh takes a .<r> re-mint, as kern46m's does.

## 2026-11-03 — cut 68030-261103-71: the kmem readers' tables; kern30m -71 (71e9627, 31db77d)

The kernel keeps the inode tables the stock kmem readers name (inode, ifreelist, ifreeh, ufs_inode, inodeNINODE): build step 8i links them as the kernel's COMMONs and the carved ufs and s5 modules bind to them, so sar, sadc and timex -s work again on a carved kernel, and crash starts without a timestamp error with kbootset 1.1.0.261103-37's namelist (the sidecar asks for it). Sums: unix a21b0b56, brel 6a010bc5, kabi b7d28836, ufs 74f178ca, s5 0eb95df7; abi 18c0a1c9 unchanged; host builds and the container agree. kern30m k30.1.4.261103-71 packages it.

## 2026-11-02 — cut 68030-261102-70 (fee9393)

sdqueue runs a controller's queue function at sdspl or above (raise only), so a raw /dev/scsi command that is the first to the A3000 WD no longer kills the stock a3091 driver; kinfo and the port's rth1 (31edbc6) give the A1200's `A1200 IDE` motherboard id 2, as the A4000's Gayle port. kern30m k30.1.4.261102-70 packages it (1dea6b19).

## 2026-11-02 — cut 68030-261102-69 (d576c94)

-68's recipe from amix 46c269c with the module core's patch 0052, so the INT2/INT6 interrupt chains are not walked while no module has attached a handler. kabi k30.1.4 and abi 18c0a1c9 unchanged; the sidecar carries kbootset-min=1.1.0.261102-35. kern30m k30.1.4.261102-69 packages it (ad8f5af1).

## 2026-11-02 — driver contract: how the 68030 kernel maps the low 1 GiB (49d6c51)

The driver contract says how the 68030 kernel maps the low 1 GiB (one early-termination descriptor in the 4-entry root table; the TT registers off) and that a Zorro III board at or above VSECT1 needs sptalloc.

## 2026-11-01 — the sidecar carries the kbootset floor (77971fb)

The sidecar copies the module core's core/kbootset-min as kbootset-min= (C2-3 version 10), refusing anything but one line in the kbootset version form; recorded cuts keep their sidecars.

## 2026-11-01 — cut 68030-261101-68 and kern30m -68 (1ca4de2, 3e6037a, 88ad417)

- The toolchain pin comes from kernel/dlm/toolchain.pin; a module kernel stops if the kabi pin= is not the core's pin.
- Soft data and vmem limits are unlimited by default (stack stays 16 MB); --stock-proc-limits builds the old table.
- Cut 68030-261101-68 on gcc-cross-amix 33ebadc with module core 0051 (module majors from the booted manifest): unix 39dbbe3f, brel 679f8270, kabi 1b15e299 (k30.1.4, pin gcc-2.7.2.3-33ebadc). kern30m -68 (ebc9e866) needs kbootset -34 or later.

## 2026-11-01 — swapadd guard; cut 68030-261101-67

- swap -a of an area whose anon array finds no free run in kvseg now fails at once with ENOMEM ("swap: Not enough space", exit 2) instead of sleeping for ever; the boot-time add of the swap slice's tail no longer hangs. On by default; --no-swap-guard builds the previous kernel byte for byte (1dff121).
- Cut 68030-261101-67 and kern30m -67: -66's recipe with the guard and module core 0050; kabi k30.1.4 and abi unchanged. unix f81868da, brel d427c428, kern30m 53d57a18 (6be370b).

## 2026-10-31 — cut 68030-261031-66 with core patch 0049; kern30m -66 (b7d78d9)

-65's recipe from amix 3c3e353, whose core patch 0049 makes a first-use load never wait for memory and frees the
load's file copy before the load proper. kabi k30.1.4 and abi 18c0a1c9 unchanged; ufs and s5 stay kabi k30.1.2, boot
class. unix.brel 8eaa44c9 (1 539 048 B, +740 against -65), bss 346 560 (+32). kern30m k30.1.4.261031-66 = 4e48dd06,
1 888 256 B; host and container rolls are byte-identical.

## 2026-10-31 — cut 68030-261031-65, kabi k30.1.4 with core patch 0048; kern30m -65 (4eeb376, 29aeeb8)

-64's recipe from amix 74405ce, whose core patch 0048 loads a demand-class filesystem module at its first mount. The
kernel claims kabi k30.1.4; abi 18c0a1c9 is unchanged, and ufs and s5 stay kabi k30.1.2, boot class. unix.brel
41406ac1 (1 538 308 B, +1936 B against -64), bss 346 528 (+132). build-cross-kernel.sh and kabi-sidecar030.py take
k30.1.4. kern30m k30.1.4.261031-65 = 1c280a6f, 1 886 720 B; host and container rolls are byte-identical.

## 2026-10-31 — kabi-sidecar030.py labels pin= from amix's compiler pin (04c0b65, 9eb8d03)

tools/kabi-sidecar030.py takes the sidecar's pin= from AMIX_GCA_PIN when it is set and checks the installed wrapper
against amix-gcc-wrapper.sh at that commit, so a local compiler checkout that has moved on no longer relabels the
same compiler. Cuts -63 and -64 take it from 04c0b65 and reproduce all seven sums on the host and in the container.

## 2026-10-31 — comments, docs and package descriptions state facts without internal ids (24cf96d, e900c1c)

No binary change: cut -64 reproduces its seven sums with the edited build script. kern30m -64's description text
changed (unminted; payload identical).

## 2026-10-31 — kern30m -64 asks for kbootset -30 or later; -64 emulation acceptance complete (ce80e2c)

kern30m k30.1.3.261031-64 asks for kbootset -30 or later: kbootset's own registry must know c 48 random for a
generation to carry the random module. -64 is not minted, so its pkginfo changed in place (roll 777f259b). Emulation
acceptance of -64 passes: with a 68882, without an FPU, under the freeq trigger, and the random module (urandom
1 MiB in 0.55 s; the seed kept across a reboot).

## 2026-10-31 — build-cross-kernel.sh: no SIGPIPE races; each cut pins its own port and paula (89ebcf7, a1b9b6c, e27aae0)

The carve's build-id check no longer fails at random: `strings | grep -q` under pipefail died of SIGPIPE when grep
exited early (8 in 500 on -64's ufs); grep now reads strings through a process substitution (0 in 1000), and three
other early-exit pipes are made safe the same way. Each cut record names its own port and paula commits
(cuts/<id>/port.pin, paula.pin): -63 d0e8857/548d258, -64 0d37eb1/1b2736d, so moving kernel/port/port.pin leaves a
recorded cut's inputs alone. -63 and -64 reproduce their seven sums, on the host and in amix-toolchain:dist.

## 2026-10-31 — cut 68030-261031-64, the cut of record; kern30m -64 (1ac1a49)

-63's recipe from amix b391504; the module core's major registry carries c 48 random (a8719fb). kabi k30.1.3, abi
18c0a1c9. Sums reproduced on the host and twice in the container: unix 278d4d0f, unix.brel 03c4e122, unix.sym 0745df74,
kabi cf7c8a31, ufs 5938bb62, s5 7dcca81e. kern30m k30.1.3.261031-64 (8c217239…) packages it ("New in -64: the kernel
knows the random module's major (c 48)"); two rolls byte-identical. Emulation acceptance pending.

## 2026-10-31 — kern30m re-roots its carve objects (2bfd72d)

pkg/kernel-k30-m: the ufs and s5 carve rebuilds link their objects where the cut (K30M_SRC) and amix-system
(AMIX_SYSTEM) are now, after checking each Makefile's EXTRA= names the same object. A cut built in the container rolls
on the host and the other way round; kern30m stays 2a155ebd either way.

## 2026-10-31 — the kernel-k30 hook runs in make dist's container (2192470, 59e24b8, 6fe391a)

build-cross-kernel.sh's `cmp -l | wc -l` byte counts no longer take cmp's exit status under pipefail (diffutils 3.10 in
the container exits 1 where the host's 3.12 exits 0, which stopped the cut silently). kabi-sidecar030.py takes the
gcc-cross-amix pin from AMIX_GCA_PIN when the toolchain has no git. cuts/build.sh puts toolchain/m68k-gnu-bin first on
PATH. Cut -63's cut.sh takes those two files from 2192470; its seven sums are unchanged. In amix-toolchain:dist,
mounted as dist.sh does, the cut reproduces all seven -63 sums in 14 s.

## 2026-10-31 — cuts/build.sh, make dist's kernel-k30 hook (85f9c06)

Rebuilds the cut of record named in cuts/CURRENT (68030-261031-63) with its own cut.sh, on this checkout, with the
port and paula at kernel/port/port.pin and kernel/drivers/paula/paula.pin (fetched by hash), and refuses sums that
differ from the record's. The output goes to build/cuts/<build id>/, where kern30m reads it by default.
tools/cuts-selftest.sh checks that cuts/CURRENT and kern30m's pins agree. On the host, all seven -63 sums reproduce.

## 2026-10-31 — pkg/build.sh passes a recipe's exit 3 through (e777fdc)

kern30m exits 3 with a [MISSING] line naming make kernel-k30 when no cut output is present; with the cut,
the bytes are unchanged.

## 2026-10-31 — pkg/: the kern30m recipe moves in (82f8350)

The kern30m recipe (kernel-k30-m) moves in from amix-packages 450ba6a as make dist's kspace hook
pkg/build.sh, on build/pkg's harness with no sibling paths. Re-rolled, kern30m k30.1.3.261031-63 has the minted
payload, pkgmap payload rows, pkginfo and copyright; only the control stamps differ. Two runs byte-identical.

## 2026-10-31 — The 040/060 family tools, from amix-kerntools 989e30b (b52b4b8)

tools/: emit-family-chains, k0-gates, the rootdev and cputype stamps, check-chain-stamp, rootdev-assert, the
sddevsize and support-probe injectors, comaddr; contracts/: the shipped families (K060, KD060-Z), the svr4-sum
vectors, the scan060 set, the spl fixtures. k0-gates finds the port as $PORT and the toolchain as $GCA. The port's -51
cut reproduces with the tools taken from amix (KT unset), and k0-gates is ALL GREEN; make test runs the new selftests.

## 2026-10-31 — Cut 68030-261031-63, the freeq guard on (a0e2ab4)

cuts/68030-261031-63: from amix c1b7842 with the -56 recipe; the four defaults on (kzero, ufs tail zeroing, FPU
gate, freeq guard). unix 660e4d12, brel eda4dcdf, sym 9eae436f, kabi fc3d99a7 (k30.1.3, abi 18c0a1c9), ufs 3e2507e5,
s5 1c9711b9. cut.sh reproduces all seven. With a 68882, without an FPU and under the prngd trigger it passes in emulation.

## 2026-10-31 — STREAMS freeq guard (grimoire quirk 92), on by default (f4aef26, 6e8a7fe)

src/freeqguard030.c joins the final link; tools/freeqguard-retarget.py retargets every freeq relocation (qdetach,
strclose x2, stropen x2) to freeq_guarded, which takes the pair off the run and scan lists at spl7 and calls the
stock freeq. It closes stock qattach's undo of a failed open (qdetach clmode 0), which freed a queue still on qhead
(prngd + prngd-ctl: KERNEL FAULT from queuerun). --no-freeq-guard reproduces all six -56 sums. Test kernel
68030-261030-62 (not a cut) passes the quirk 90/91, FPU/FPU-less, ftx and smoke sets in emulation. 6e8a7fe: the
kzero check wants ufs_vptrunz on non-carved builds.

## 2026-10-30 — cut -56 reproduces at the port pin (613d7fc)

Cut 68030-261030-56 also reproduces, all seven sums, with the port at d0e8857 (kernel/port/port.pin): the port files the
recipe reads are unchanged from 88dcfc0. Cuts take the port at port.pin unless their README names another.

## 2026-10-30 — cut of record 68030-261030-56 (fe544a2)

The k30 module kernel, kabi k30.1.3 (abi 18c0a1c9), with kzero, ufs tail zeroing and the sendsig FPU gate.
cuts/68030-261030-56/ holds SHA256SUMS-68030-261030-56 (seven files), cut.sh (a git archive of amix 4fc583f's kernel/,
the -22 recipe, port 88dcfc0, amix-paula 548d258) and a README of its inputs; the bytes stay outside the repository in
build/cuts/. brel 14ad54ee, unix 759a928f, unix.sym 6ca52072, kabi da737229, ufs e2fb88fe, s5 b2086574, audio.c
1f43c5ff. cut.sh reproduces all seven sums of the emulator-tested build. Not yet accepted on hardware or published.

## 2026-10-30 — sendsig FPU gate (grimoire quirk 74), on by default (2a3e894)

src/fpugate030.s adds fpu_setup_gated, which returns at once when fpu_present is 0; tools/fpugate-sendsig.py retargets
the one relocation of sendsig's jsr fpu_setup to it (no .text byte moves; every other fpu_setup caller untouched). A
hard check runs after the link and after the dlm splice. --no-fpu-gate reproduces the previous kernel byte for byte. On
test kernel 68030-261030-55 (not a cut) an emulated 68030 without an FPU boots to multi-user and survives signals; the
stock kernel panics there at frestore (vector 0xB). Floating point without an FPU still dies with SIGSYS (quirk 31).

## 2026-10-30 — ufs tail zeroing (grimoire quirk 91), on by default (1be27f8); z3660eth in kernel/drivers (b3a90b8)

src/ufs_vptrunz.c wraps ufs_itrunc's call of pvn_vptrunc (the stock ufs object's reference renamed, four bytes in one
.strtab string): when a shrink to M cuts into a kept block past the direct blocks, it zeroes [M, end of the block)
through segkmap and writes it synchronously before the stock pvn_vptrunc runs, with the file's pages cached or not. A
hard check runs on the wrapped ufs object, the carved module and a base unix. --no-ufs-tailzero reproduces the previous
kernel byte for byte. Test kernel 68030-261030-54 (not a cut) regrows clean in 136/136 warm, remounted and cold runs.
amix-build selects the ethernet driver as z3660eth (kernel/drivers/z3660eth).

## 2026-10-30 — kzero fault catch (grimoire quirk 90), on by default (8b670ad)

src/kzero_nofault.s, the port's routine (k46-module b65b43d, same object bytes), joins the cross build's final link with
the stock kzero (= bzero) weakened in the work copy; a hard check wants one strong kzero away from bzero, kzr_magic and
the expected callers. --no-kzero reproduces all seven -22 sums. Test kernel 68030-261030-50 (not a cut) survives the
quirk-90 shrinks and the coreutils dd/cp and gtar --delete cases in emulation with data intact.

## 2026-10-30 — the 68030 cross cut; drivers from kernel/drivers (bc6cc64 … 18d2dce)

The host cross build of the 68030 kernel moved in as new commits: build-cross-kernel.sh, kernel-patches.conf and
kpatch-lib, fstypes.conf and fstype-lib, dlm-core-link with the halt and marc_root shims (a missing shim FAILs step 7),
elf2brel, mksym030, kinfo-cdevsw, the kabi sidecar, relsim, bootchain-verify and the boot-chain contract v1; stock
bases come from the AMIX_SYSTEM input. Drivers come from kernel/drivers (--drivers/AMIX_DRIVERS only as an override);
docs/driver-contract.md documents kernel-patches.conf. The -22 reference cut rebuilds byte-identically from amix alone:
unix 3a02c257, unix.brel 4b4aefc1, kabi 19c04ef0, ufs 64c99884, s5 f7a74b73. make -C kernel/k30 test runs the self-tests.

## 2026-10-30 — moved in from amix-kerntools (public part)

jusii/amix-kerntools release-master 578ff79 (5 commits) moved in by subtree merge after a filter-repo rewrite: a local tool
note dropped, AGENTS.md renamed docs/driver-contract.md, 578ff79 pruned as empty; 4 commits, old→new map in
docs/history-map.txt. privacy-check --all: 0 hits (was 3, class 2). The on-box build hub: amix-build, onbox-build, the
clean-kernel gate, relsim, checkunix; the k30 cross cut follows.
