# Changelog

## 2026-10-31 — pkg/: the kern30m recipe moves in (82f8350)

The kern30m recipe (kernel-k30-m) moves in from amix-packages 450ba6a (P-38 S3.3) as make dist's kspace hook
pkg/build.sh, on build/pkg's harness with no sibling paths. Re-rolled, kern30m k30.1.3.261031-63 has the minted
payload, pkgmap payload rows, pkginfo and copyright; only the control stamps differ (D-g). Two runs byte-identical.

## 2026-10-31 — The 040/060 family tools, from amix-kerntools 989e30b (b52b4b8)

tools/: emit-family-chains, k0-gates, the rootdev and cputype stamps, check-chain-stamp, rootdev-assert, the
sddevsize and support-probe injectors, comaddr; contracts/: the shipped families (K060, KD060-Z), the svr4-sum
vectors, the scan060 set, the spl fixtures. k0-gates finds the port as $PORT and the toolchain as $GCA. The port's -51
cut reproduces with the tools taken from amix (KT unset), and k0-gates is ALL GREEN; make test runs the new selftests.

## 2026-10-31 — Cut 68030-261031-63, the freeq guard on (a0e2ab4)

cuts/68030-261031-63: from amix c1b7842 with the -56 recipe; the four defaults on (kzero, ufs tail zeroing, FPU
gate, freeq guard). unix 660e4d12, brel eda4dcdf, sym 9eae436f, kabi fc3d99a7 (k30.1.3, abi 18c0a1c9), ufs 3e2507e5,
s5 1c9711b9. cut.sh reproduces all seven. C1 (68882), C0 (no FPU) and the prngd trigger pass in emulation.

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

jusii/amix-kerntools release-master 578ff79 (5 commits) moved in by subtree merge after a filter-repo rewrite: CLAUDE.md
dropped, AGENTS.md renamed docs/driver-contract.md, 578ff79 pruned as empty; 4 commits, old→new map in
docs/history-map.txt. privacy-check --all: 0 hits (was 3, class 2). The on-box build hub: amix-build, onbox-build, the
clean-kernel gate, relsim, checkunix; the k30 cross cut follows.
