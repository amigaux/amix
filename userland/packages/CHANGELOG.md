# Changelog

Commit hashes cited in entries dated before 2026-10-13 refer to the pre-public development
history, which the maintainer keeps; they are provenance, not links into this repository's history.

## 2026-10-31 — INDEX lists amix-base 1.0-5 (725ebc2)

INDEX.md regenerated; it lists amix-base 1.0-5.

## 2026-10-31 — INDEX and conf list dhcp-client and amix-base 1.0-3 (2bee88d)

INDEX.md and conf/{names,cats,deps,sets}.conf regenerated: they list dhcp-client 1.0-1 (dhcpc, network, set base,
depends on amix-base) and amix-base 1.0-3, from userland/base/pkg. 15 packages.

## 2026-10-31 — INDEX and conf list amix-base (92efd91)

INDEX.md and conf/{names,cats,sets}.conf regenerated with the multi-root pkgmeta; they list amix-base (amxbase, system,
set base) from userland/base/pkg. 14 packages.

## 2026-10-30 — patch names /usr/bin/patch in SYSTEM_PATHS (3799b4a)

Ready for build/pkg's SYSTEM_PATHS check; pkginfo, INDEX.md and the package are unchanged, so no revision bump.

## 2026-10-30 — pkg-smoke runs the older recipes' smoke tests (2e08db2)

pkg-smoke runs each smoke.sh where it expects to run (beside its fixtures for gzip, grep, less, make, patch and tar),
builds host fixtures with tests/mkfixture.py and brings out.tar home; tar's new host half reads the box's archive
with the host tar. All 13 current revisions install, check, smoke and remove cleanly in one E1 run.

## 2026-10-30 — man pages in /opt/amix/man with whatis.d; 13 revisions (7feb82c..102cd9e)

Every package's pages move to /opt/amix/man/<sect>/<name> with whatis.d/<PKG> (tools/manpages.sh, docs/man-pages.md,
the contract shared with userland/base): grep -8, gzip -8, less -8, make -8, patch -7, gtar -9, zlib -8, acompat -8,
amixbch14 1.3-5, bzip2 -3, diffutil -3, rsync -2, coreutil -4. New pages tar(1), acompat(3) with nine aliases,
acompat-test(1), zlib-test(1), amix-bench-g14(1); bunzip2/bzcat/bzip2recover aliases. less -8 ships the troff
sources (-7 shipped pre-formatted pages). All 129 pages render through E1's stock nroff; other payload files are
unchanged. amix-benchmark-gcc14 refuses a home path or build host in its payload (abebb49); pkg-smoke installs and
checks a package without a smoke test (d41d0bb).

## 2026-10-30 — §10.9 categories as new revisions; amix-benchmark-gcc14 converted; pkg-smoke from out/pkg (12c7e08 … 6ab6a35)

gzip 1.3.12-7 and gtar 1.14-8 file under archive, zlib 1.2.13-7 and acompat 0.1-7 under library (acompat's
description names libamixcompat); payloads identical to the previous revisions except acompat's embedded version
string. amix-benchmark-gcc14 converted (1.3-4 unchanged). pkg-smoke stages from out/pkg. All built on the container
gcc14 pin; the other gcc14 packages rebuild byte-identical there and keep their revisions. Not published.

## 2026-10-30 — the recipes converted to the §10.9 shape (20c8a84 … 0be17e7)

Docs for the amix home; $COMMON paths for the amix harness. grep, gzip, less, make, zlib (STYLE=hooks), tar, patch and
acompat (directory renamed from libamixcompat so the catalog name stays acompat) take package.sh and hooks, each proven
against its recorded build: payload sha256 and modes equal, pkginfo byte-identical, pkgmap equal with the build-time
mtimes masked, .a files equal member by member. diffutils, bzip2, coreutils and rsync re-proven. amix-benchmark's
sources are in src/ (from kerntools, byte-identical, scanned); the published period amixbench 1.3 stays built outside
amix. No revision changed; nothing published.

## 2026-10-30 — moved into amix userland/packages; INDEX.md and conf fragments (5649328, d2ee2b1)

amix-packages master 5cc0e5d moved in by a filter-repo rewrite (197 commits kept, 61 pruned; map in
docs/history-map.txt); the registry, roadmap, publish records, kernel-space and held recipes stay in the old repo; the
shared harness is build/pkg/common. pkgmeta generates INDEX.md and conf/{names,cats,deps,sets}.conf from the recipes.

## 2026-10-30 — prngd 0.9.29 recipe, held on a kernel bug (cc61d24)

Built and gated; stock pkgadd/pkgchk/pkgrm rc 0. Amix AF_UNIX fix: DONT_CHMOD_SOCKET honoured (chmod on a bound
socket's FIFO makes connect fail ENOTSOCK). prngd traffic while it gathers panics the stock k30 kernel in queuerun (a
deferred STREAMS put through a garbage qi_putp); the kernel fix is routed. Not published.

## 2026-10-30 — kernel-k30-m k30.1.3.261030-56 (611ddc5, 547e801)

The k30 station's cut 68030-261030-56 from amix 4fc583f with kzero (quirk 90), ufs tail zeroing (quirk 91; the ufs
module from the cut's qz/ufs.exp) and the sendsig FPU gate (quirk 74). kabi k30.1.3 unchanged. Both fs modules rebuild
byte-equal. 1883136 bytes, md5 aa9714d9. dlm-src.sh builds kits from an amix commit. Not published.

## 2026-10-30 — no bench addresses in tracked files (43408a8)

Docs and tests use TEST-NET-1 (192.0.2.1); the smoke harnesses take the guest and bridge from rig-slot.sh env, with no
literal default. privacy-check --tree HEAD: 0 hits. perl smoke 53/53 and rsync pkg-smoke re-run PASS.

## 2026-10-30 — perl 5.8.9 recipe, roll held on the s5/UFS decision (5f1ac42, d07b517, eeac483, 931b691)

Configure measured on the box, GCC 14 cross build with a host perl, stock libm.a (owner) with matherr as shipped.
E1: perl core suite 227/231 scripts (68673 tests), smoke 53/53. amix-decls.h prototypes (socketpair, netdb
set/end*ent, munmap, isnan, _sysconf); scan060-g14 sizes mask- and entry-bounded switch tables (self-test 19/19);
pkgbuild.sh STYLE=hooks. No .pkg rolled; not published.

## 2026-10-30 — quirk 90 worked around in the landed packages (cad15e4, 97bbcf1, cbd8c25)

The stock-kernel ftruncate panic (grimoire quirk 90) reached dd seek=, sparse cp/mv/install and tar -b 1 --delete on E1.
recipes/common/amix-ftruncate.c: a strong ftruncate that cuts block-aligned and rewrites the tail. coreutil 5.2.1-3
links it in all 86 programs; copy.c writes the trailing NUL instead of write+ftruncate (patch 08); stat sizes without a
run-time %llu (patch 09). gtar 1.14-7: gnulib's F_FREESP path cuts aligned. E1: coreutils smoke 102/102 (d418b45e),
gcc14-smoke PASS with X4 (gtar 44e79c67). The published period gtar 1.14-2 keeps the hazard. Not published.

## 2026-10-30 — rsync 3.1.3; seteuid/setegid declared; pkg-smoke host side (0814dda, 3676e4a, e7ac916)

rsync 3.1.3-1 (gcc14, /opt/amix, protocol 31, bundled zlib/popt/getaddrinfo). Patch 01 works around a stock-kernel
panic (ftruncate shrinking a file past its direct blocks inside its last block, grimoire quirk 90): --inplace cuts at
the block boundary and rewrites the tail. Patch 02 parses dotted quads before gethostbyname, which AMIX's fails on.
Daemon defaults to nobody/nobody. E1 golden 030 against the host's rsync 3.4.1: smoke 44/44; pkg 192e5bbe / 685568 B.
amix-decls.h declares seteuid/setegid; pkg-smoke runs an optional per-package tests/host.sh. Not published.

## 2026-10-30 — gcc14 re-pinned to amigaux/gcc14-cross-amix b51ff39; the gcc14 set re-minted (a6b124c, d53600f)

Public pin b51ff39: cc1 unchanged (9635f67e); libgcc and libamixc99 rebuilt under -mno-strict-align (specs 45f46859
adds the default). Every package object is byte-identical to the cf461e3 build; a relink with the old runtime reproduces
the old executables, so every new byte is runtime. One name = one byte set, so all twelve take a new revision: acompat
0.1-6, zlib 1.2.13-6, gzip 1.3.12-6, patch 2.5.9-6, gtar 1.14-6, grep 2.5.1a-7, less 704-7, make 3.81-7,
amix-benchmark-gcc14 1.3-4, diffutils 2.8.1-2, bzip2 1.0.8-2, coreutils 5.2.1-2. E1 gcc14-smoke PASS (all checks EQUAL,
dhry 151514/s, paranoia 24/24); pkg-smoke diffutils 24/24, bzip2 23/23, coreutils 95/95. Not published.

## 2026-10-29 — coreutils 5.2.1; MAKE_CFLAGS and a NEEDED-aware undef gate (c728391, 53707ec, d512466, c62ec2f)

coreutil 5.2.1-1 (gcc14, /opt/amix): 86 programs + groups incl. md5sum/sha1sum, no libm; date -u fixed for AMIX libc
writing into the TZ string; E1 smoke 95/95, stock pkgadd/pkgchk/pkgrm clean; pkg 81300da8 / 3567104 B. pkgbuild.sh gains
MAKE_CFLAGS and an undef gate over every NEEDED object; amix-decls.h declares getrlimit/setrlimit; scan060-g14.py sizes
cmpa-bounded switch tables (self-test 18/18). Not published.

## 2026-10-29 — bzip2 1.0.8; the interim driver is recipes/common/pkgbuild.sh with STYLE=make (3810e35, 343a4b5, 702b57c)

bzip2 1.0.8-1 (gcc14, /opt/amix, category archive): bzip2recover's 64-bit offsets formatted by hand, Bourne-shell bzgrep
and bzdiff, the -v report out of line so compression runs no FPU instruction (FPU-less LC040/LC060). E1 smoke 23/23 with
upstream's test vectors; stock pkgadd/pkgchk/pkgrm clean; pkg 65e99c40 / 221696 B. amix-decls.h declares fchmod. 343a4b5
builds only with 702b57c's STYLE=make. Not published; cats.conf needs archive and utility before a publish.

## 2026-10-29 — diffutils 2.8.1, the first package in the §10.9 shape (ac02f0f, 209d712, 61a4761)

diffutil 2.8.1-1 (gcc14, /opt/amix), built by the interim driver recipes/common/style-configure.sh with the on-box
smoke runner tools/pkg-smoke; E1 smoke 24/24, stock pkgadd/pkgchk/pkgrm clean; pkg 2fed5ef9 / 213504 B. scan060-g14.py
keeps no stale unsized-table verdict after a re-sync, self-test 17/17. Not published.

## 2026-10-29 — gcc14 re-pinned to the compiler rebuilt from cf461e3 (e42cb91)

AMIX_GCC14_PINS: cc1 9635f67e, libgcc.a e7efa6e6, libamixc99.a 0dd88b3a (were d4933e78, 5d814507, c73ccc17); specs
unchanged. The rebuilt compiler's generated code is byte-identical to the old one's (105/105 objects); the hashes differ
only by embedded paths, DWARF and ar timestamps. Gate 16/16. No package re-mint.

## 2026-10-29 — recipes find their inputs in the new workspace (b5f765b, a0ff4ef)

k46 cuts are read from amix-040-060-port/build/cuts, k30 cuts from amix-kerntools/build/cuts (kernel-k46, -k46-m,
-k30, -k30-u, -k30-m, kbuildid-selftest, kspace-roundtrip). z3660rtg's check-only monsw dependency points at the
retired stand-in's new name (pins aa7aace6, bf902e40 unchanged). dlm-src.sh reads dlm and modules from the amix
monorepo; pre-move commits archive to identical trees. 34/34 pins verified, round trip 253/0; no pinned bytes changed.

## 2026-10-28 — the kspace catalog of record is fff860dc (b1f564f4 + kern30m k30.1.3.261028-22, kern46m k46.1.3.261028-61, kbootset -24, loader-amix -10, paula-k30/-k46 1.0.0-1), proven by the Bench in emulation (kerntools 82f7da2); b1f564f4 kept at superseded/repo-20261028-1602; round trip 253/253 with upgrades from all four superseded roots (7292a37) — not published

## 2026-10-28 — candidate kernel-space root fff860dc (b1f564f4 + the kabi 1.3 set), not promoted, not published: kern30m k30.1.3.261028-22, kern46m k46.1.3.261028-61 (/dev/paula support, bounded /dev/audio open), kbootset 1.1.0.261028-24 (box 0b9b8ec4, c 54 paula in kreg), loader-amix 1.0.261025-10 (boot1 765915a7, boot2 da260a96: DMA buffers by the partition's DosEnvec), paula-k30/-k46 1.0.0-1 added; modtools -7 kept; round trip 253/253 including upgrades from 64d37aaa, 915e09f3, 6f0c1701 and b1f564f4 (5972993)

## 2026-10-28 — paula-k30 / paula-k46 1.0.0-1 (pkginst paula30 / paula46): isoriano's /dev/paula (MIT) as a demand-class module of each line (kabi 1.3, c 54), objects amix-paula 548d258 (k30 147844b4, k46 d2c7d8f4); ships /dev/paula c 54 0 0666 and /usr/include/paula.h; kmodpkg.sh gains optional KM_FILES. paula30 fc0b4516, paula46 dd332b02; not in any catalog. The Bench's ramdisk refusal is apkg 0.3.2 on the box: ramdisk-k30/-k46 need APKG 0.3.3 (d14d36d, c048863)

## 2026-10-28 — the kspace catalog of record is b1f564f4 (6f0c1701 + kbootset -23 + kern46m -51), proven by the Bench in emulation; 6f0c1701 kept at superseded/repo-20261028-0434, candidate 059c7c53 withdrawn; R5 runs from all three superseded roots, R6 from 6f0c1701; round trip 212/212 (3060b1f) — not published

## 2026-10-28 — kern46m k46.1.2.261028-51 from the k46 cut 68060-261028-51 (port 87b8a88: the ufs module refuses a ufs with blocks under 4 KiB at mount, EINVAL, where -50 mounted it and panicked in ufs_getapage); core 7b07bce and abi 2ab48658 unchanged; pins unix 0fda887c, kabi 03208ab3, ufs.mod 62cc5250, ufs-exp.k46 6636b27e; first k46 cut with the release notes; candidate root b1f564f4 = 059c7c53 with kern46m -50 → -51, not promoted; round trip 212/212 (dd5359e) — not published

## 2026-10-28 — the kspace catalog of record is 6f0c1701 (the candidate proven by the Bench's S5-13), 915e09f3 kept at superseded/repo-20261028-0319; R5 runs from both superseded roots (4ef0aec)

## 2026-10-28 — kbootset -23 (1.1.0.261028-23) from amix-dlm e089c2a: C2-4 v15, mark-good marks a refused default bad when its bytes are damaged; box 3c18c3b5, modtools -7 kept; its DESC carries the kernel release notes (upgrade with kbootset -22 or later; s5 no longer mounts on the 68040/68060 line, S5-37); candidate root 059c7c53 = 6f0c1701 + kbootset -23 only, not promoted; round trip R6 (kbootset alone) (cfcfe78, 53fed43)

## 2026-10-28 — the kern30m/kern46m recipes carry the release notes for each line's next cut; the shipped -20 and -50 are never re-rolled (cfcfe78's text re-rolls withdrawn, never promoted); one-version guard recipes/common/onever.sh: a roll never rewrites a version a kspace root lists with other bytes (selftest 6/6) (cfcfe78, 53fed43, 371807c)

## 2026-10-28 — kern46m k46.1.2.261028-50 from the re-cut 68060-261028-50 (module core amix-dlm 7b07bce; -91's core refused its own ufs, S5-13); new gates: the cut's core contains 7b07bce, and image buildid (blanks stripped) == sidecar build= == ufs build= (kbuildid-selftest 10/10); candidate kernel-space root 6f0c1701 (915e09f3 with -91 → -50), not promoted; round trip 202/202 (363e1b9) — not published

## 2026-10-27 — kbootset 1.1.0.261027-22 from amix-dlm 1308c0b (box 37e78d88; modtools -7 kept, modadmin byte-identical), and the S5-12 next root promoted as the kernel-space catalog of record 915e09f3, 64d37aaa kept at superseded/repo-20261027-1948 (f9b0f08); round trip 198/198 — not published

## 2026-10-27 — kern30m k30.1.2.261027-20 and kern46m k46.1.2.261027-91: the kernel packages carry their cut's ufs (and on k30 s5) core-tier modules (S5-12, amix-dlm recipe 59f1a28) (9302dc9); next root catalog 2e7ee51a, round trip 197/197 — not published

## 2026-10-27 — GCC 14 userland built -mno-strict-align (owner decision 2026-10-27): acompat 0.1-5, zlib 1.2.13-5, gzip 1.3.12-5, patch 2.5.9-5, gtar 1.14-5, grep 2.5.1a-6, less 704-6, make 3.81-6, amix-benchmark-gcc14 1.3-3 (5a4ba57, 67a5674); one flag location, the pin check refuses a build without it; 42/42 EQUAL on the 030 and the 060; next root catalog 8c6a3b4c — not published

## 2026-10-27 — a4kt710-k30 / a4kt710-k46 1.0.0-1 (pkginst a4kt71030 / a4kt71046), the A4000T onboard NCR 53C710 root-class module (a3a287e); catalog 64d37aaa, round trip 172/172 — not published

mobo:a4000t-710, rank mobo, kabi 1.2; it does nothing unless the running Kickstart's "NCR scsi.device" tag is present (C4-2 v6
§8.1); `param declared=0` in modreg.local.d disables it. Built from a git archive of amix-a4091 a74708e with kit ca8b352: objects
k46 95bebecb, k30 e65b4f7d (the sibling's working-tree objects were stale and lacked the gate). a4kt71030 ab19897d / 27648 B,
a4kt71046 77c997e3 / 30208 B. b2a0e874 kept at superseded/repo-20261027-1353. kmodpkg.sh gains an optional KM_VERSION_FILE.

## 2026-10-27 — kbootset 1.1.0.261027-21 and modtools 1.0.261027-7 from amix-dlm 4442c76; the static 1.0 kernels leave the kernel-space catalog (S5-03, S5-34) (2b6ba70, d52fdee); catalog b2a0e874, round trip 162/162 — not published

kbootset -21 brings S5-02 (the safe set keeps the card numbers; C4-4 v6, C3-5 v13). Both built on gcc14-cross-amix cf461e3 and
checked against the pins and the return-value ABI (new recipes/common/gcc14-pin.sh, run by dlm-src.sh before any box build).
/sbin/kbootset 143cc1d8 (e8250e37 / 202240 B), /sbin/modadmin f51c98d6 (0867b623 / 59904 B). kernel-k30-u, -k46-z, -k46-zacd
leave the catalog (datastreams kept in superseded/static-1.0/); b198e9e2 kept byte-identical at superseded/repo-20261027-1344.

## 2026-10-27 — kernel-space catalog of record promoted to b198e9e2 (3028b37): the stage-4 exit set + gayle-k30/-k46 1.1.0-3; the exit root 6e60a128 kept byte-identical at superseded/repo-20261027-1329; round trip 159/159 — not published

## 2026-10-27 — GCC 14 userland re-minted on gcc14-cross-amix cf461e3: acompat 0.1-4, zlib 1.2.13-4, gzip 1.3.12-4, patch 2.5.9-4, gtar 1.14-4, grep 2.5.1a-5, less 704-5, make 3.81-5, amix-benchmark-gcc14 1.3-2 (de9d3b7..e64a8ee) — not published

cf461e3 fixes the return-value ABI: pointers in %a0 and %d0, every struct in memory through %a0 (AMIX cc, gcc 2.7, libc div()).
gcc14-env.sh pins the toolchain and checks the ABI from the compiler's own -S output on every build (gate-gcc14-selftest 14/14).
Smoke on E1 (030+68882) and N6 (060): 42/42 EQUAL; period-compiled callers of the GCC 14 zlib/acompat archives now get correct
pointers; a GCC 14 div()/ldiv() test passes 6/6. tar drops its sys/mkdev.h patch. The zlib/acompat hold is lifted. The -3 builds
and amixbch14 1.3 are superseded and never published.

## 2026-10-27 — gayle-k30/-k46 1.1.0-3 (124c578): interrupt I/O by default; round trip 159/159 — not published

From amix-gayle-ide b2935fc (owner decision T-54 item 21: `param intr=0` in modreg.local.d selects polled), kit c2dc7fb; objects
k30 e465bb12 / k46 5c8d7d64, rebuilt byte-identical. gayle30 5870d595 / 29696 B, gayle46 d3c55cf8 / 31232 B. The exit catalog
6e60a128 is unchanged; the next-catalog root build/kspace/next/repo (b198e9e2) differs from it only in the two gayle rows.

## 2026-10-27 — GCC 14 userland: acompat 0.1-3, zlib 1.2.13-3, gzip 1.3.12-3, patch 2.5.9-3, gtar 1.14-3, amix-benchmark-gcc14 1.3 (5c871e1..8ffb88b) — not published

TOOLCHAIN=gcc14 (-m68020-60) builds the remaining userland recipes as revision -3; the period recipes are unchanged (byte-identical
rebuilds). Smoke: 42 period-vs-gcc14 tests EQUAL on E1 (030+68882) and N6 (060). New amix-benchmark-gcc14 (PKG amixbch14, command
amix-bench-g14) installs beside amix-benchmark with no shared file and names its compiler. scan060-g14 sizes %fp-indexed and
memory-bounded switch tables. HOLD zlib -3 and acompat -3: GCC 14 returns pointers in %d0 only (SVR4 uses %a0 too), so their
archives hand garbage pointers to period-compiled callers — re-mint after the toolchain fix.

## 2026-10-27 — loader-amix 1.0.261025-9 from amix-dlm ea75578 (082c1cd); round trip 159/159 — not published

boot2 L11: the volume-2 prompt re-reads every 4 s when the disk-change counter does not move. boot2 28658 B, sha256 76346d9a;
boot1 unchanged (c6c380ee); still loader version 3. md5 73f362ab / 35840 B; replaces -8. Catalog 6e60a128 (the -8 root at
superseded/repo-20261027-0800).

## 2026-10-27 — kbootset 1.1.0.261027-20 (fd25bc0); round trip 159/159 — not published

From amix-dlm 1da3474 (093b2a7): gate 2 checks the sidecar's build= against the kernel's own build id (buildid on k46,
kinfo_buildid via unix.sym on k30, leading blanks ignored). /sbin/kbootset b3e7b987; md5 e18dd5f2 / 200704 B. boot1/boot2/
modadmin unchanged. Catalog 61181d33 (the -19 root at superseded/repo-20261027-0649; fd25bc0's body names 0646, a copy of the
round-trip root with the same catalog). Round trip 159/159 with two negative build= rows.

## 2026-10-27 — z3660scsi-k30/-k46 1.0.0-2 (7401d53), kern46m k46.1.2.261027-82 (d8ee54b); round trip 157/157 — not published

z3660scsi 1.0.0-2 (amix-z3660scsi 209bdd2, ZS-06: the module arms its data cache from cputype at _load, `param=cache:int:-1:-1:60`,
always 0 on k30 — the S4-74 metal fix): objects k30 2c9e3803 / k46 21754e70 (7468 B image), now kabi 1.2; md5 51ff85c2 / 6808c875.
kbootset writes no param token, so the cputype default runs. kern46m -82 (port fcaffcd STAMP_BUILDID_CPU=60, dlm 178a47b): the
image's .data buildid " 68060-261027-82" = the sidecar's build= (build.sh checks it); unix 435f255f, arena 0x0012c500, abi 2ab48658,
103 names; md5 97bc0e8a / 2480128 B; the stamper lands as src/stamp_buildid.real.py beside the KT-41 shim. Catalog 6a4b8caa.

## 2026-10-27 — kern30m k30.1.2.261027-17 (65b98db), gayle-k30/-k46 1.1.0-2 (6bc9f94); round trip 157/157 — not published

kern30m -17 (kerntools 865d357 --no-fstypes, dlm 54e04bd, port d33608d): the static cdfs gone (cdfs-k30 is the only cdfs on k30, as
on k46); the libgcc helpers linked by -u; brel 3d2e4cb6 (1637928 B), ET_REL 86590a5c, sidecar 90182cfb: kabi k30.1.2, arena
0x000f6640, abi 2ab48658, root= the three stock rows, rootfs ufs,s5; the 101 names identical to -16's; no cdfs symbols; the
copyright drops amix-cdfs/LICENSE. Pkg md5 326435f5 / 1848320 B. gayle 1.1.0-2 (d49ad04: the page-crossing note a counter):
objects k30 a237589d (11948 B), k46 3476bba0 (12732 B); md5 8405263d / 63bd269d. Catalog 92da8ce8. Round trip 157/157.

## 2026-10-27 — a4091-k30/-k46 1.0.0-5 (1238713); round trip 157/157 — not published

From amix-a4091 5044872 (a selection timeout is silent, counted in seltimeout — no more "A4091 slow" flood on the installer's bus
scan); objects k30 6a6b6b3c (4532 B), k46 8655e87a (5524 B), kit c2dc7fb; md5 9c0eae11 / e277608d. Catalog 7c886e7b (-4 root at
superseded/repo-20261027-0413). Round trip 157/157.

## 2026-10-27 — kern30m k30.1.2.261027-16 (d8742bf); round trip 157/157 — not published

kerntools f0bbd76 cut on dlm 8b35eb4 (core 0044 + the dma_forcefail self-clearing count) and port d33608d (rth1: swap none on a
RAM-disk root names /dev/fakeswap): brel 009c2a11 (1714772 B), ET_REL 3df85847, sidecar 7b3775a8: kabi k30.1.2, arena 0x00107430,
abi 2ab48658, root= the three stock rows; 101 names; the seam; "/dev/fakeswap" in the image; three checks pass. Pkg md5 e1a1f2f9 /
1936896 B. Catalog 8e99705e (-15 root at superseded/repo-20261027-0351). Round trip 157/157.

## 2026-10-27 — kern46m k46.1.2.261027-81 (746a916); round trip 157/157 — not published

Port d33608d (rth1: swap none on a RAM-disk root names /dev/fakeswap, the stock dummy disk b 19,0, so the kernel can fork and the
installer's `swap -a` finds it), dlm 178a47b: unix baf7ac43 (2443217 B), arena 0x0012c500, abi 2ab48658, 103 names; "/dev/fakeswap"
in the image; md5 c5e9d5d5 / 2480128 B. Catalog 88b88546 (-80 root at superseded/repo-20261027-0346). Round trip 157/157.

## 2026-10-27 — kern30m k30.1.2.261027-15 (1df034c); round trip 157/157 — not published

kerntools f0bbd76 cut on dlm 178a47b (core 0044; the k30 DMA test hooks dma_forcefail + the force-bounce exemption) + port 0e1f294
(rth1 bb6eaf6: AXL1's RAM-disk root selector and rootfstype). brel 3e3b1c52 (1714644 B), ET_REL 4ff85b29, sidecar 223aff5b:
kabi k30.1.2, arena 0x001073c0, abi 2ab48658, root= the three stock rows; 101 names; the seam and the RTH1 ramdisk string present;
three checks pass. Pkg md5 ec791154 / 1936384 B. Catalog f821411e (-14 root at superseded/repo-20261027-0326). Round trip 157/157.

## 2026-10-27 — kern46m k46.1.2.261027-80 (78abe7a), a4091 1.0.0-4 (077a4ce), kbootset -19 (8fdaada); round trip 157/157 — not published

kern46m -80 (port 0e1f294: rth1 bb6eaf6 = AXL1's root selector, RAM-disk root b 20,0, swap none, rootfstype from the record;
d941cd2 = the FAILEXIT print behind krnx_fail_print; dlm 178a47b core 0001–0044): unix e48ae543 (2443113 B), arena 0x0012c4c0,
abi 2ab48658, 103 names; the RTH1 ramdisk string present; md5 0b4d3927 / 2480128 B. a4091 1.0.0-4 (e35f811; the WRITE/TUR sync over
a clear line): objects 69929d09 / 3d8cc066; md5 c4c3fa8e / 41741dad. kbootset -19 (fa7a4ab: an absent depend= is gate 3's):
/sbin/kbootset f537493d; md5 1c72b446 / 199168 B; boot2/boot1/modadmin unchanged. Catalog c4e3f098. Round trip 157/157.
The RAM-disk root branch is proven on the host only; installng's rd1 medium is the boot.

## 2026-10-27 — kbootset 1.1.0.261027-18 from amix-dlm d227dbf (0ccddf5); round trip 157/157 — not published

Gate 2 checks every module's imports against the kernel's symbol block (ksym=, C3-3 v7): a module importing a name the kernel
does not export is refused at compose time with the names. /sbin/kbootset a9e4f923; md5 2df10f91 / 199168 B. boot2 and modadmin
unchanged (no loader/modtools mint). Catalog cdcbff84 (-17 root at superseded/repo-20261027-0118). Round trip 157/157: z3660rtg
without monsw is now refused at gate 2 (its monsw imports) instead of gate 3; new negative row: cdfs-k30 on kern30m -13 refused
with its 13 missing names. Wording issue for dlm: a missing depend= module gets "it needs a newer kernel cut".

## 2026-10-27 — kern30m k30.1.2.261027-14 (41e04ad), a4091-k30/-k46 1.0.0-3 (c23cfdd); round trip 156/156 — not published

kern30m -14 (kerntools d1a2e3c --no-scsi-drivers --object-absent, dlm 33ea0c7): the static A4091/A4092/A4770 and Gayle IDE
drivers dropped; brel 9a4f0792 (1713708 B), ET_REL 31db0f56, sidecar 81bc23d1: kabi k30.1.2, arena 0x001070f0, abi 2ab48658,
root= mobo:a3000-wd,zorro:0202:01,zorro:0202:03, rootfs=ufs,s5; 101 names (+13 fs names); the seam relocation present; three
checks pass. Copyright keeps amix-a4091's LICENSE/NOTICE (its four stock-file patches still apply), drops amix-gayle-ide. Pkg
md5 6d092318 / 1934848 B; needs loader-amix -8. a4091 1.0.0-3 (2151d03): k46 54405c68, k30 as -2; md5 e349031d / 0e915d89.
Catalog e8d72a59 (22 rows). Round trip 156/156: on k30 a4091 and gayle now compose as root records (safe=1 under their rootdev).

## 2026-10-27 — dlmkit -11 (f5fe10a), kern46m k46.1.2.261027-79 (047a038), a4091 1.0.0-2 (e4af9d5), cdfs-k30/-k46 1.0.0-1 (626e1a5); round trip 152/152 — not published

dlmkit -11 (c2dc7fb: modcheck -w / PAGESHIFT_OK; k30 a1de94e6, k46 7fb3de45; abi 2ab48658). kern46m -79 (port 1d1a566, dlm
33ea0c7 core 0001–0043): unix 23d4be39 (2442248 B), arena 0x0012c2e0, abi 2ab48658, 103 names; md5 df1fc408 / 2479104 B. a4091
1.0.0-2 (db230fa; C4-5 v5): objects adbc4e47 / ef8cd0dc; md5 c8896f98 / 0722bdfb. cdfs-k30/-k46 1.0.0-1 (fd6cad8; boot class,
match=always, fs=cdfs; objects 3038f6fd / 2808fcd9): md5 7f22ff7d / 860f5202, 110592 B; kmodpkg passes KM_PAGESHIFT_OK as -w.
Catalog 9027569f (22 kernel-space rows). Round trip 152/152: cdfs composes as boot on a disk root and PROMOTED (`root … safe=1`)
with --rootfs cdfs. Known: kbootset does not check a module's imports against the kernel's symbol block (cdfs-k30 composes on -13).

## 2026-10-27 — dlmkit -10, loader-amix -8, kbootset -17 from amix-dlm 33ea0c7 (bb947aa, 8e5c4d3, 14f4a65) — not published

dlmkit30 k30.1.2.261027-10 (md5 d654b658 / 4082688 B, manifest c883c4fd) and dlmkit46 (280595b9 / 4099584 B, 749b19b8; PORT_REV
12d416c): sd.h SDCARDS 4 + the four-card decode, the 13 filesystem names at minor 2, abi.txt 2ab48658 both lines, the k30 DMA
NOTICE updated; ramdisk, gayle and a4091 modules check ok (a4091 db230fa's objects differ from the 1.0.0-1 pins by its own v5
source, not the kit). loader-amix -8: boot2 28646 B 61b3feb0 (S4-11), boot1 unchanged, version 3; md5 8dc2c216. kbootset -17:
fs= promotion, --ramdisk defaults, gate 4; /sbin/kbootset 527b8d59; md5 63573f93 / 195072 B. modadmin unchanged (no modtools
mint). Catalog a9018242 (roots at superseded/repo-20261027-0048/-0049/-0050). Round trip 142/142 with host kbootset 33ea0c7.

## 2026-10-27 — kern46m k46.1.2.261027-78 (7be39e3); a4091-k30/-k46 1.0.0-1 (3e42e94) and gayle-k30/-k46 1.1.0-1 (f14c0e7) staged; round trip 142/142 — not published

kern46m -78: cut in build/kspace/cut-k46m from the port's recipe (port 9ead75f, dlm 4acd4a6 = C4-5 v4 dma_alloc through DTT0,
base 284154a3, no z3660 pass); equals the port's -53 but the id digits. unix abc709f5 (2441362 B), sidecar 2dd0e6cf: kabi
k46.1.2, arena 0x0012c210, 90 symbols, abi fea18182. Both sidecar checks pass. Pkg md5 abf76e6f / 2478080 B. a4091 (78cf019)
and gayle (6e3d811) objects as pinned under kits bbd20b6 and 4acd4a6; md5 a409130 50b2de4f, a409146 055a905b, gayle30
f4768c8e, gayle46 ca71699c; no device nodes. Catalog 94f5d0a1 (20 kernel-space rows). On k30 gate 3 refuses both modules while
kern30m's root= names their boards. gayle ships only after S4-71's bprobe row (publication gate).

## 2026-10-27 — kern30m k30.1.2.261026-13, the five DMA names in the k30 kernel (6b689e0); the k46 kit's port headers pinned by archive (db9f1e5) — not published

kern30m -13 (kerntools fcbc007 on dlm bbd20b6): -12 plus dma_prepare/complete/addr/alloc/free in the 88-name symbol block
(k30 provider a placeholder); seam unchanged (one relocation against dlm_sd_close). brel 689b2c4f, ET_REL 95c6ed17, sidecar
ff957937: kabi k30.1.2, arena 0x00109550, abi fea18182. Both sidecar checks pass. Pkg md5 5688536c / 1947136 B; staged catalog
256c7544 (-12 root at superseded/repo-20261027-0017). Round trip 126/126; gates PASS. dlmkit: mkkit reads the k46 port
headers from a git archive of DK_K46_PORT_COMMIT=12d416c, so PORT_REV no longer follows the live port HEAD; the -9 rebuild
reproduces both manifests (0e4c7208, c0b64ee4). kmodpkg.sh still stamps the live port HEAD for modcheck kits (no pin involved).

## 2026-10-27 — dlmkit -9 from amix-dlm bbd20b6: the DMA names in DDI 1.2 (a7f30fb) — not published

dlmkit30 k30.1.2.261027-9 (md5 ecea42d0 / 4071936 B, manifest 0e4c7208) and dlmkit46 k46.1.2.261027-9 (a55964ac / 4088832 B,
c0b64ee4; PORT_REV 12d416c): dma_prepare/complete/addr/alloc/free at minor 2 on both lines (S4-62 piece 1, C4-5 v3); the k30
provider a placeholder (NOTICE). The ramdisk builds byte-identical against them. Staged catalog b82f7901 (-8 root at
superseded/repo-20261027-0013). Round trip 126/126; gates PASS. modtools and loader-amix need no re-mint at bbd20b6.

## 2026-10-26 — kern30m k30.1.2.261026-12, the k30 kernel with the sd seam restored (2fe11d2) — not published

-11 with sd.c calling the core's dlm_sd_close again (C4-1 §3; -10/-11 lost it to kerntools' pipefail defect, 44caef7): the
seam proven by `U dlm_sd_close` in sd.o and one R_68K_32 relocation in the ET_REL (-11 had none). brel 2ba846c2 (1726044 B),
ET_REL fba7cb6d, sidecar 40d23f37: kabi k30.1.2, arena 0x001094a0, abi fea18182. kabi-sidecar030 and mkident --check pass.
Pkg md5 a8f4276c / 1947136 B; staged catalog 06f12015 (-11 root at superseded/repo-20261026-2349). Round trip 126/126; gates PASS.

## 2026-10-26 — ramdisk-k30/-k46 1.0.0-1 staged; round trip on packagemanager abfaaac, 126/126 (3211350) — not published

packagemanager abfaaac accepts the `b none /dev/dsk/<node>` entries (C3-5 v8 §1.2). ramdisk30/46 (md5 edc26b2b / 9e5b1024,
kabi 1.2) staged in base/ beside zscsi30/46; names.conf ramdisk30/46 → ramdisk-k30/-k46. Staged catalog 65324000 (16
kernel-space; 5a441729 root at superseded/repo-20261026-2312). Round trip 114 → 126: dry run, -R install (contents carries
the three `b 20 0–2 0600 root root` lines, no /dev/rdsk), build, commit, check; kbootset composes `module ramdisk root 4630
… bss=816 match=always` on both lines — no safe=1 (safe = the root controller's and rootfs modules only; a RAM-disk-rooted
medium needs C4-2/C4-4 to know the ramdisk, an amix-dlm question). The box needs APKG 0.3.3 to install them.

## 2026-10-26 — kern30m k30.1.2.261026-11, the kabi 1.2 k30 kernel with the 16-aligned arena (f7f1e18) — not published

K030-U build 68030-261026-11 (kerntools bf221f3 cut on dlm 49239b1, core 0001–0041): -10 plus iodone, ramdisk_image,
vfs_register, root_defer and the arena at capacity + 16. brel 50996217 (1725952 B, bss 352904), ET_REL 53b17fae, sidecar
60314796: kabi k30.1.2, arena 0x00109450, abi fea18182, sdcards 4. kabi-sidecar030 and mkident --check pass; build.sh
refuses a non-16-aligned arena. Pkg md5 d2c4e422 / 1946112 B; staged catalog 5a441729 (-10 root at
superseded/repo-20261026-2305). Round trip 114/114; gates PASS.

## 2026-10-26 — kern46m k46.1.2.261026-77, the kabi 1.2 k46 kernel with the 16-aligned arena (fddf560); ramdisk-k30/-k46 1.0.0-1 minted, not staged (7379df6) — not published

kern46m: cut in amix-packages (build/kspace/cut-k46m, the port's S4-22c recipe) from port 12d416c + dlm 49239b1 + base
284154a3, no z3660 pass; identical to the port's -75 dry build but the build-id byte (-72…-76 were taken, so -77).
unix e85d4371 (2440473 B), sidecar 0ca10470: kabi k46.1.2, arena 0x0012c050, abi fea18182, sdcards 4, root= dlm_static_root.
kabi-sidecar.py and mkident --check pass; build.sh refuses a non-16-aligned arena. Pkg md5 4c37a341 / 2477056 B; staged
catalog 8034952e (-71 root at superseded/repo-20261026-2257); round trip 114/114; gates PASS.
ramdisk30/46 1.0.0-1 (objects 5523d853 / 054467f6, md5 edc26b2b / 9e5b1024, 14336 B, /dev/dsk/ram0–2 b 20 0–2): kpkgroll
accepts `b` entries, but gen-catalog 124c329 and apkg refuse them (C3-5 v8 §1.2 support is a packagemanager change) — unstaged.

## 2026-10-26 — dlmkit -8 from amix-dlm 49239b1, the first kabi 1.2 kits (7175792) — not published

dlmkit30 k30.1.2.261026-8 (md5 06d332e8 / 4068864 B, manifest f04242ed) and dlmkit46 k46.1.2.261026-8 (e098de2e /
4086272 B, a6ce6e30; PORT_REV 12d416c): iodone, ramdisk_image, vfs_register minor 2 on both lines, root_defer minor 2 on
k30; block-only modcheck; VSECT1/phystokv on k46. The ramdisk (amix-modules dc433b6) builds against the staged kits
byte-identical (5523d853 / 054467f6). Staged catalog ef345e73 (-7 root at superseded/repo-20261026-2248). Round trip 114/114;
gates PASS. modtools and loader-amix need no re-mint (boot1/boot2/modadmin byte-identical at 49239b1). Known: the k46 kit's
PORT_REV stamps the live port HEAD, so a rebuild fails its pin whenever the port moves — pin a git archive (follow-up).

## 2026-10-26 — kbootset 1.1.0.261026-16 from amix-dlm f340556; round trip 114/114 on kern46m -71 (c1e18c0, 78fac35) — not published

kbootset -16 (kbootset code as 05f700a): composes root-class modules as root records (`module <name> root … bss= match=
safe=1`, S4-12); a generation carrying one gets loader-min 3 (AX_LOADER_ROOT, gate 7); gate 3 refuses a root module for a
controller the kernel's root= already names. /sbin/kbootset 98c04c09, datastream md5 101453b3 / 194048 B, sha256 1351983f;
replaces -15. Staged catalog 51bf05f4 (-15 root at superseded/repo-20261026-2213). Round-trip fixture: k46-m stages 1–3
boot from mobo:a3000-wd as k30-m does (kern46m -71 no longer links z3660scsi); stage 4 keeps the Z3660 facts and composes
the zscsi46 root record. Host kbootset f340556; 114/114 rc 0; both gate selftests PASS.

## 2026-10-26 — kern46m k46.1.1.261026-71, the k46 root-class kernel without static z3660scsi (1c23b76) — not published

KD060-Z module kernel 68060-261026-71 (port afc8d09, amix-dlm 05f700a core 0001–0038): -69 without the z3660 pass
(`build-m.sh` skips it unless Z3660=1). root= mobo:a3000-wd,zorro:0202:01,zorro:0202:03 = dlm_static_root; the Z3660
root comes from the zscsi46 root module. unix 8d146e9e (2438117 B), sidecar aff218e1, abi= fea18182, sdcards=4,
ksymgate 12/12; package md5 353d8aa4 / 2474496 B. Catalog 6979e980 (the -69 root kept at superseded/repo-20261026-2208).
Round trip 107/114: the 7 FAILs are the script booting k46-m stages 1–3 from zorro:144b:01 before zscsi46 exists
(gate 3 rightly refuses); fixture fix (mobo boot/root for stages 1–3, as k30-m's F30) is the follow-up.

## 2026-10-26 — z3660scsi-k30/-k46 1.0.0-1, the first root-class module packages (3b12add, e9ef38b) — not published

From amix-z3660scsi 2f4183b (module form beff392), built with dlmkit -7 (amix-dlm 05f700a). PKG zscsi30/zscsi46, kabi
k30.1.1 / k46.1.1, class root, match=zorro:144b:01,mobo:z3660-window, rank=z3660, unload=never; no majors and no device
nodes (sd owns the disk majors): payload /etc/conf/mod.d/z3660scsi + modreg. Objects 14b165ad (k30), 21577308 (k46), 12988 B;
modcheck ok 6764 B. md5 841fce7b / 06f7e84f, 22528 B each. Staged catalog c17b4b8e. The round trip goes 106 → 113 with the
host kbootset at 05f700a: on kern30m -10 (its root= has no Z3660) the root record composes (`module z3660scsi root 12988 …
bss=156 match=… safe=1`) and commits as a store member; on kern46m -69 gate 3 refuses it ("which the kernel drives itself"),
as expected until the -71 kernel. Gates PASS.

## 2026-10-26 — dlmkit -7 (root-class kits) and loader-amix -7 (loader version 3) from amix-dlm 05f700a (59fbfca, 4cf39c7) — not published

dlmkit30/46 -7 (KIT_REV 05f700a, core 0001–0038): mkmod writes rank=, modcheck accepts class=root with its rules, the DDI
list gains root_defer; abi texts unchanged (fea18182); kit-test 74/74 (a root module accepted, six refusals). md5 8ca86960 /
4064256 B and d1cb76e2 / 4081664 B; replace -6. loader-amix -7: loader version 3 (banner `amix-boot 3:`), which root-class
generations need; boot2 28526 B a151a252, boot1 unchanged; ldrinfo version=3, catalog loader=3; md5 fb71911c / 35840 B;
replaces -6. Staged catalog b4865981; round trip 106/106 (loader 3 laid, the m kernels' loader-min 2 satisfied); gates PASS.

## 2026-10-26 — kern30m k30.1.1.261026-10, the S4-23 k30 root-class kernel (6e5bb14) — not published

K030-U build 68030-261026-10 (kerntools 3405b11) on amix-dlm 4c1acd0 (core 0001–0035, marc_root live): -08's content plus
the root pass. brel 1c837598 (1722768 B), unix.sym 3c9c6e74, sidecar c4476f3c, abi= fea18182, sdcards=4; ksymgate 12/12.
md5 d733de8c / 1942528 B. The staged root carries -10 beside kern46m -69 (catalog 10d591cb); the -08 root at
superseded/repo-20261026-2144. Round trip 106/106; gates PASS. The S4-23 cut has no top-level sidecar copy (the recipe cmp
is a no-op; the sidecar stays sha-pinned) — kerntools' cut script may restore it.

## 2026-10-26 — kern46m k46.1.1.261026-69, the S4-22 k46 root-class kernel (27240b0) — not published

KD060-Z module kernel build 68060-261026-69 (port k46-module ab91c80) on amix-dlm 4c1acd0 (core 0001–0035): -65's content
plus the root pass (the arena load path, dlm_marc_root, match= at marc_root); z3660scsi 86e6cd7. unix e3a049fc (2447964 B),
sidecar 415c52ba, abi= fea18182, sdcards=4; ksymgate 12/12. md5 41a469f0 / 2485248 B. -65 stays in build/kspace/pkg; the
staged root carries -69 (catalog da231aed); the -65 root at superseded/repo-20261026-2141. Round trip 106/106 (nothing in
it exercises the root pass — that is S4-72's); gates PASS.

## 2026-10-26 — dlmkit -6 from amix-dlm 96205b6, the first kabi 1.1 kits (b4c6eb6) — not published

dlmkit30 k30.1.1.261026-6.96205b6 and dlmkit46 k46.1.1.261026-6.96205b6 (KIT_REV 96205b6, core 0001–0035): abi.txt =
abi-k30.1.1 / abi-k46.1.1 (fea18182 both); MONSW_REV amix-modules@c0386d9; k46 records PORT_REV a0f86be; the sample module
carries kabi=k30.1.1 / k46.1.1 and passes modcheck; kit-test 64/64 with the sample loading against the 1.1 kernels of record
(k30 ET_REL 0fe57802, k46 5a7028c0). md5 9d87eb78 / 4060672 B and 07183c3c / 4078080 B; supersede -5. Staged catalog
2d52a62b; round trip 106/106 (the staged modules are still kabi 1.0 and compose on the 1.1 kernels); gates PASS. No
round-trip case yet for "a 1.1-kit module refused by a 1.0 kernel".

## 2026-10-26 — kern30m k30.1.1.261026-08, the S4-21 k30 module kernel of record (6db5e5c) — not published

The first k30 kernel at kabi k30.1.1: K030-U build 68030-261026-08 (kerntools 1079741) on amix-dlm a15104e (core
0001–0032), the four-card sd layer with the dlm_sd_close seam, the dlm_halt hook, bdevsw row 20 freed. brel 9e823641
(1720256 B), unix.sym 027060cc, sidecar d009be9b, abi= fea18182 (= abi-k30.1.1.txt), sdcards=4 passed through; ksymgate
12/12. md5 6c606993 / 1939968 B. -04 stays in build/kspace/pkg (the S4-55 media); the staged root carries -08 (catalog
008d58f0); the -04 root at superseded/repo-20261026-2108. Round trip 106/106 with the 1.0 modules composing; gates PASS.

## 2026-10-26 — kern46m k46.1.1.261026-65, the S4-21 k46 module kernel of record (11fe968) — not published

The first kernel at kabi k46.1.1: KD060-Z module kernel build 68060-261026-65 (port k46-module aebb759) on amix-dlm a15104e
(core 0001–0032): the four-card sd layer, the halt hook, the sd seam, bdevsw row 20 freed; z3660scsi 86e6cd7. unix 5a7028c0
(2444800 B), sidecar 3a47087a, abi= fea18182 (= abi-k46.1.1.txt), sdcards=4 passed through; ksymgate 12/12. build.sh checks
abi= against the pinned kabi's reference text and the sdcards= key. md5 d3f33e75 / 2481664 B. -61 stays in build/kspace/pkg
(the S4-55 media); the staged root carries -65 (catalog 1db2567a); the -61 root at superseded/repo-20261026-2052. Round trip
106/106 with the kabi-1.0 modules composing on the 1.1 kernel; gates PASS.

## 2026-10-26 — kern30m k30.1.0.261026-04, the S4-20 module kernel (ddb6f14) — not published

The first stage-4 k30 cut: K030-U build 68030-261026-04 (kerntools 39fd8dd) with amix-dlm 4b7eb3d (core 0001–0028,
dlm_maximage 256 KiB), no driver change. brel c0f69e0a (1716016 B, bss 349324), unix.sym d9991e90, sidecar 21c63f07, abi=
unchanged 7a90c7d9; ksymgate 12/12. md5 8f70f34a / 1935360 B. The recipe reads the cut's layout (u/usr/sys, kabi-u) and
checks its SHA256SUMS. -01 stays in build/kspace/pkg for the stage-3 media; the staged root carries -04 (catalog 9e143d53);
the previous root kept at superseded/repo-20261026-1906 (6b003630). Round trip 106/106; gates PASS.

## 2026-10-26 — kern46m k46.1.0.261026-61, the S4-20 module kernel (2834c79) — not published

The first stage-4 k46 cut: KD060-Z module kernel build 68060-261026-61 (port k46-module 13dc9f3) with amix-dlm 4b7eb3d
(core 0001–0028, dlm_maximage 256 KiB) and amix-z3660scsi 86e6cd7 (ZS-05). unix cb2499f1 (2433820 B), sidecar 9a85b329,
abi= unchanged 7a90c7d9; ksymgate 12/12. md5 0fdca621 / 2470912 B. -58 stays in build/kspace/pkg (the stage-3 media of
record use it); the staged root carries -61 (catalog 6b003630); the -58 root kept at superseded/repo-20261026-1848
(47584f25). Round trip 106/106; gates PASS.

## 2026-10-26 — z3660eth-k30/-k46 1.0.0-5 (0a37c09) — not published

From amix-z3660net c5f7a46: every board register access in the module armed against the Z3660 address-capture race (ZS-05).
Objects k30 022c012b, k46 ca3a2b05 (19751 B file, 13537 B image). zeth30 md5 6c88d4f7, zeth46 4a641610, 29184 B each. The
-4 datastreams stay in build/kspace/pkg; the staged root carries -5 (catalog 47584f25); the -4 root is kept at
build/kspace/superseded/repo-20261026-1744 (086eac4d). Round trip 106/106; gates PASS.

## 2026-10-26 — z3660eth-k30/-k46 1.0.0-4 (09cdd8d) — not published

From amix-z3660net 2a15a4c: in intr=6 mode the module's RX ring resyncs past a wedged sentinel (the metal S3-46 stall).
Objects k30 8d0e75f0, k46 a928fd2b (19379 B file, 13177 B image); /dev/zen0 as before. zeth30 md5 5404d3e3, zeth46
a9e30900, 28672 B each. The -3 datastreams stay in build/kspace/pkg; the staged root carries -4 (catalog 086eac4d); the -3
root is kept at build/kspace/superseded/repo-20261026-1652 (ad04c5bc). Round trip 106/106; gates PASS.

## 2026-10-26 — z3660eth-k30/-k46 1.0.0-3 (0247012) — not published

From amix-z3660net 3e6b696: the module's intr=6 interrupt self-test now works inside the IPL-4 STREAMS open. Objects k30
abf530d7, k46 9dfe0294 (18984 B file, 12945 B image); kit e84878e; /dev/zen0 c 51 0 as in -2. zeth30 md5 a8608c3e, zeth46
bff54223, 28160 B each. The -2 datastreams stay in build/kspace/pkg (upgrade-from); the staged root carries -3 (catalog
ad04c5bc); the -2 root is kept at build/kspace/superseded/repo-20261026-1507 (fde1018e). Round trip 106/106; gates PASS.

## 2026-10-26 — monsw-k30/-k46 1.0.0-2 (d059277) — not published

A package revision for S3-45's `apkg upgrade` row, from amix-modules b0f75a4: module/VERSION 1.0.0-2, README facts; objects
unchanged (k30 01a40342, k46 2c2760e9; kit c6ad5bd). monsw30 md5 d345e3d1, monsw46 b7367ae7, 14336 B each. The 1.0.0-1
datastreams stay in build/kspace/pkg; catalog v1 cannot carry two versions of one name, so the staged root carries -2
(fde1018e) and the -1 root is kept at build/kspace/superseded/repo-20261026-1426 (6bdb0969) as the upgrade row's "from"
root. Round trip 106/106; both gate selftests PASS.

## 2026-10-26 — kbootset -15, dlmkit -5 from amix-dlm 594731b (2e58723..904e209) — not published

kbootset 1.1.0.261025-15: in `media --cd`/`--floppy` gate 3 checks only the root controller (C2-4 v11 §13), `namelist`
writes /stand/unix 0644 whatever the umask; /sbin/kbootset d44f6a32 = dlm's box build; md5 4531c633 / 188416 B (supersedes
-14). dlmkit30/46 -5 (KIT_REV 594731b): modcheck warns when a demand-class module's load working set passes 160 KiB, guide
updated; MONSW_REV amix-modules@c0386d9, kit.conf sources in sh; md5 bf551763 / 4057600 B, e868d694 / 4074496 B; kit-test
64/64. Staged catalog regenerated in the wave (6bdb0969, three rows); round trip 106/106; both gate selftests PASS.

## 2026-10-26 — dlmkit -4, modtools -6, loader-amix -6 from amix-dlm 2233745 (bf15f58..8ac06af) — not published

dlmkit30/46 -4 (KIT_REV 2233745): kit.conf's MONSW_REV is `amix-modules@c0386d9` and sources in sh (build.sh checks both);
sys/monsw.h from a pinned archive of amix-modules c0386d9 (dlm-src.sh's amix_dlm_kit takes the commit and answers mkkit's git
questions for it); modcheck enforces C3-1 v4 (image ≤ 256 KiB, file < 256 KiB). md5 64b1657b / 4056064 B, b8e477bc /
4072960 B. modtools -6: modadmin 0518fb28 with core patches 0025 (-L prints the buffer's words first) and 0026 (-K keeps
kernel messages in putbuf); -5's inittab scripts unchanged; md5 d191106f / 59904 B. loader-amix -6: boot2 28356 B 344b8e07,
boot1 unchanged, loader version 2; md5 446410f6 / 35328 B. Superseded -3/-5/-5 moved aside; staged catalog regenerated in
the same wave (ba0e1c8c, four rows changed); round trip 106/106; both gate selftests PASS.

## 2026-10-26 — loader-amix -5 (4a9d646) — not published

loader-amix 1.0.261025-5 from amix-dlm 26492cf: boot2 001b04a gives a k30 kernel at most 64 MiB of fast memory, and
Zorro III RAM is never kernel memory. boot2 28392 B, 6147ab3b; boot1 unchanged (c6c380ee, 1024 B). Loader version 2,
catalog loader=2. Datastream md5 f70310d1 / 35328 B (supersedes -4, never staged). Round trip 106/106 on packagemanager
124c329. Staged kernel-space catalog regenerated with -5 (build/kspace/repo, md5 3305d908).

## 2026-10-26 — kbootset -14, modtools -5, dlmkit -3 at c6ad5bd, monsw-k30/-k46 1.0.0-1 (38f9193..5ecf509) — not published

kbootset -14 from amix-dlm c6ad5bd: deflates on the box with its own encoder so `--spec z=deflate` works; /sbin/kbootset
9acb9add; md5 e30da9aa / 187904 B (supersedes -13, never staged). modtools -5: modadmin 7329e183 (core patch 0024,
`modadmin -L` prints the kernel's message buffer) with -4's inittab scripts unchanged; md5 c7ae85e0 / 59904 B. dlmkit30/46 -3
re-pinned to KIT_REV c6ad5bd (monsw.h from amix-modules). New monsw-k30/-k46 1.0.0-1 (monsw30/monsw46) from amix-modules
c0386d9: /etc/conf/mod.d/monsw (k30 01a40342, k46 2c2760e9), a comments-only modreg, /dev/monsw c 52 0 as a device entry;
with monsw installed z3660rtg passes gate 3 on both lines. Round trip 106/106; staged catalog md5 2cdf52ae.

## 2026-10-26 — modtools -4 (inittab scripts safe on the 1991 sh), loader-amix -4, z3660eth 1.0.0-2 with /dev/zen0, kbootset -13, dlmkit -3 (2676d36..22efd2f) — not published

modtools -3's postinstall wiped /etc/inittab on Amix 2.1: that sh's `read` keeps its input buffer across `exec <file`. In -4
the script's own shell never runs `read` — each read is in a child (a backquote or a redirected while-read) with one
redirection; no exec, no IFS change; cat and dd copy the bytes (the line goes after an initdefault line 1, else first);
preremove cuts a line-1/line-2 dlm line out with dd; a size check refuses before every mv; cat, ls, dd and expr (all on the
miniroot) are required. On core's inittab the result equals the installer's expected file (md5 7c952cc3). build.sh rejects
the forbidden constructs. modadmin unchanged (a206874d); datastream 48be0b90 / 59392 B. loader-amix -4: boot2 e36c1c55 (binds
below 0x40000000), loader=2. z3660eth-k30/-k46 1.0.0-2: /dev/zen0 c 51 0 as a pkgmap device entry, objects unchanged. kbootset
-13: e56172b6 (read-only-medium boot). dlmkit30/46 -3 at b6b4b87: sys/monsw.h; k46 PORT_REV ebe8dfd. Round trip on
packagemanager 124c329: 102/102; catalog md5 d3bca155.

## 2026-10-26 — kernel licence audit; kpkgroll device entries for module packages (96eaf7a, d5ffff2) — not published

Every kernel package's copyright carries the licence of each repository its cut links (pin.sh lists them by sha256):
kernel-k46-z adds amix-z3660scsi, amix-z3660net, amix-z3660rtg and amix-kerntools; kernel-k46-zacd those plus amix-a4091
(LICENSE + NOTICE, the NetBSD SCRIPTS notice) and amix-cdfs; kernel-k46-m amix-z3660scsi + amix-kerntools; kernel-k30-u/-m
amix-a4091's NOTICE + amix-kerntools. All seven kernel datastreams re-rolled at the same version with unchanged payloads
(kern30u -1 91b7e592, -2 e607d185, kern30m 99d2e65b, kern46z -2 ff8b110e, -3 0fe41f72, kern46zcd b7cca1a3, kern46m c4bde0b6;
superseded/kernel-licence-audit/). kpkgroll lets a module package carry `c none /dev/…` entries (C3-5 §1.2). Round trip
95/95; catalog md5 d2142883. zeth -2 waits for gen-catalog/apkg to accept device entries and for module/VERSION 1.0.0-2.

## 2026-10-26 — kspace round trip on gen-catalog fc49df7; k30 kernels ship amix-z3660scsi's licence (2c5f833, 6da5ce2) — not published

The round trip uses amix-packagemanager fc49df7 (apkg 0.3.1; gen-catalog writes the role=module rows) and requires those rows to
equal the ones it computes from .moddata (95/95; the two old checks became one; catalog byte-identical). kernel-k30-u -2 and
kernel-k30-m ship amix-z3660scsi's MIT LICENSE (the cuts link the driver); payloads unchanged, re-rolled: kern30u -2 md5
8676db46, kern30m f45c545d; catalog md5 e7ca13f4. kern30u -1 (installng's pristine) still lacks it.

## 2026-10-26 — stage-3 mint: kbootset -12, dlmkit -2, module kernels kernel-k46-m/kernel-k30-m, module packages z3660eth/z3660rtg (16cb27c..50b4ed1) — not published

kbootset -12 from amix-dlm af363be: `kbootset namelist` writes /stand/unix; unix.sym read per C2-3 v6 §2.1; /sbin/kbootset
cd02b817 (174012 B) = dlm's box build; md5 67e8916c / 179712 B. dlmkit30/46 -2 from e84878e: every kit name within 14 bytes
(no renames), PORT_REV=617c64e; manifests k30 a8ce9b9d, k46 dcc2c522. New recipes: kernel-k46-m / kern46m k46.1.0.261026-58
(ET_REL 8459eaee, sidecar verbatim; abi= = the reference, ksymgate 12/12); kernel-k30-m / kern30m k30.1.0.261026-01 (brel
3fb1aa50, bss=349324, /stand/k30/unix.sym 4012b09b = sym=); z3660eth-k30/-k46 (zeth30/46 1.0.0-1) and z3660rtg-k30/-k46
(zrtg30/46 1.1.0-1): /etc/conf/mod.d/<name> verbatim + a comment-only modreg.d file, no scripts, modcheck ok. Round trip
composes both module kernels and z3660eth on both lines: 96/96. gen-catalog 72f6a72 writes no module rows yet (the round
trip writes them); z3660rtg composes only once monsw exists.

## 2026-10-26 — modtools 1.0.261026-3: pure-sh inittab scripts for the install miniroot (a080191) — not published

Same /sbin/modadmin as -2 (a206874d). postinstall and preremove are pure Bourne sh per C3-5 v4 §1.2: builtins plus mv, with
/usr/bin/cat, chgrp and rm used only behind `test -x`; -2 failed on the miniroot ("awk: not found" → pkgadd failed, the
install stopped). Behaviour unchanged (the dlm line first, once; preremove idempotent); a rewrite is a temp file in /etc
renamed with mv (0664; group sys where chgrp exists — on the miniroot the group stays root, fixed at first boot). build.sh
refuses bare external commands and unguarded absolute ones. Round trip under the miniroot's tools only: 62/62; differential
fuzz against -2's logic: 0 mismatches. Datastream md5 065b4c34 / 56320 B.

## 2026-10-26 — kbootset -11, modtools -2, ABI kit packages dlmkit30/dlmkit46 (amix-dlm f5ce731) (0c6a4a4..c2c5d3d) — not published

kbootset -11: /sbin/kbootset 013fe25f (= dlm's box build); gate 2 needs abi= on a module kernel, gate 6 counts an ET_REL
kernel's bss. modtools -2: /sbin/modadmin a206874d with -B; postinstall makes `dlm::sysinit:/sbin/modadmin -B …` the first
sysinit entry of /etc/inittab (idempotent), preremove takes it out (C3-5 v3 §5). New recipe dlmkit: `make kit` in the pinned
export, each kit pinned by a manifest digest; dlmkit30 k30.1.0.261026-1.f5ce731 (1065 files) and dlmkit46 k46.1.0.261026-1.f5ce731
(1069 files) install under /usr/dlm/kit/<line>/ (proposed convention); five names over s5's 14 bytes renamed, listed in
S5NAMES; the kit sample builds with each kit as installed. Round trip 54/54. Datastream md5s move per roll; payloads do not.

## 2026-10-26 — kbootset -10 and modtools 1.0.261026-1 from amix-dlm 42df482 (02fa3a2, a2bec2d) — not published

kbootset -10: `kbootset media` composes the installed module packages into the medium's pristine generation; /sbin/kbootset
305345a3 (159988 B) byte-equal to dlm's box build; datastream md5 893fb434 / 165888 B; pkgmap unchanged (/var/kbootset).
modtools -1 (new userland recipe, S3-11): /sbin/modadmin d94e5228 (GCC 14 static, byte-equal to dlm's box build; 68060-safe),
no catalog dependency, no kernel-space record; datastream md5 34cd0e5a / 50176 B; copyright carries kdedon's MIT and
amix-dlm's MIT. Round trip at 42df482 with a modtools row and install: 41/41.

## 2026-10-26 — kbootset -9 from amix-dlm a71a875 (449c1ef) — not published

S3-16: kbootset composes module members through gates 1–3, writes module and param records, `status` shows which members are
loaded. /sbin/kbootset 8cb4c157 (158828 B), byte-equal to dlm's box build; datastream md5 7bb5cea7 / 164352 B; pkgmap as
before with /var/kbootset. Round trip at a71a875: 39/39. Note: the pkgmap's copyright/pkginfo mtimes are build-time, so a
rebuild changes the datastream md5 but not the binary (true since -8).

## 2026-10-26 — loader-amix -3 and kbootset -8 from amix-dlm 124b86c (1832319, e4fd3f4) — not published

Loader version 2: boot2 28100 B (c7bff405) checks a module kernel's AXK1 against the manifest (L14) and fills the arena's
AXA1; boot1 unchanged (c6c380ee); ldrinfo version=2 → catalog loader=2; ldramix -3 datastream 35328 B md5 f59b9e33.
kbootset -8 reads sidecar v5 and lays stores at loader version 2 by default; /sbin/kbootset 05c1d40f (= dlm's box build),
datastream 142336 B md5 52f6b90a, /var/kbootset in the pkgmap. Round trip takes the loader version from ldrinfo: 39/39.

## 2026-10-26 — kbootset -7 from amix-dlm f43fe08 (f25ccc2) — not published

C2-4 version 7: `kbootset commit` writes nothing when the built generation equals the default; `commit --again` writes it
anyway. /sbin/kbootset a2970b20 (135772 B, GCC 14 static), datastream kbootset-1.1.0.261025-7.pkg md5 c5d552f5 / 141312 B,
pkgmap as -6 (/var/kbootset included). Round trip's host kbootset now at f43fe08: 39/39. Staged, not published.

## 2026-10-26 — kern30u -2 and kern46z -3: upgrade targets with identical payloads (711ef91, 0b27fd6) — not published

kernel-k30-u 1.1.0.261026.01-2 and kernel-k46-z 1.1.0.261025.51-3 carry the same unix and kabi as the revision before them
(diff -r of the unpacked trees empty; only NAME, VERSION, PSTAMP differ); the 1.1 install disks carry -1 / -2 as their
pristine kernels, so the exit row's `apkg upgrade` needs a higher revision. The previous revisions stay staged. The round
trip installs the previous revision first and upgrades to the new one on both lines: 39/39.

## 2026-10-26 — kbootset -6 from amix-dlm fb77acd (a48aa2c) — not published

/sbin/kbootset 870d4752: the original SHA-256 round restored (the -5 restructure was slower on the 030) with the no-kinfo
fixes kept. Same pkgmap. Round trip pinned to fb77acd: 37/37. Kernel-space set: kern30u -1, kern46z -2, kern46zcd -2,
ldramix -2, kbootset -6.

## 2026-10-26 — kbootset -5 from amix-dlm 6c69125 (5c6706a) — not published

/sbin/kbootset 6b76c54c: the restructured SHA-256 round (about 2× on the 030) and the no-kinfo fixes. Same pkgmap as -4.
Round trip pinned to 6c69125: 37/37 on both lines. Kernel-space set: kern30u -1, kern46z -2, kern46zcd -2, ldramix -2,
kbootset -5.

## 2026-10-26 — kernel-k30-u 1.1.0.261026.01-1: the K030-U with kinfo (c5019ae, 06253b6) — not published

The K030-U that amix-kerntools cut with kinfo (build 68030-261026-01): /stand/k30/unix (brel dfa6a1d1) and the kernel
build's sidecar (bss=344916) copied verbatim into a pure-files package; the recipe checks the inputs (elf2brel reproduces the
brel; bss-tail = the relocator's figure). The r7 stand-in is superseded (refuses to build unless KERNEL_K30_STANDIN=1, never
catalogued). The round trip runs the 030 line beside k46 on its own root and store: 37/37, incl. gate 3 refusing a Z3660
root for K030-U. Kernel-space set: kern30u -1, kern46z -2, kern46zcd -2, ldramix -2, kbootset -4.

## 2026-10-26 — kbootset -4 from amix-dlm d64bad7 (83a0f1f, f96e552) — not published

/sbin/kbootset 9cf75c1c creates the journal's directories itself; the package also ships /var/kbootset (d none 0755 root sys),
the directory apkg's trigger points the journal at (the stage-2 exit row found it missing on a fresh box). Supersedes -3.
The round trip pins d64bad7, no longer creates /var/kbootset itself and checks the pkgmap entry and the installed
directory: 25/25. Current sets for the owner's publish decision: kern46z -2, kern46zcd -2, ldramix -2, kbootset -4;
grep/less/make -4.

## 2026-10-25 (night) — kbootset -3 from amix-dlm db0ef3a (c9eb388) — not published

kbootset 1.1.0.261025-3 carries /sbin/kbootset f4a6632b (the `retry` verb, C2-4 v5), reproducible from a git archive of
db0ef3a; supersedes -2. The round trip pins kbootset to db0ef3a, 23/23. Proposed set for the owner's publish decision:
kern46z -2, kern46zcd -2, ldramix -2, kbootset -3, grep/less/make -4.

## 2026-10-25 (night) — gcc14 revision -4 on -m68020-60; kernel-space packages -2 with bss= (87d6dc8..4c35db0) — not published

TOOLCHAIN=gcc14 defaults to -m68020-60; the FPU gate fails any fs*/fd* form (040/060-only, absent on a 68881/68882) in every
ELF and archive of a payload and names the symbol — it caught the toolchain's own runtime (libamixc99 amix_vsnprintf, libgcc
__floatundidf) before the gcc14 station rebuilt it for 68020-60. grep, less, make re-minted as -4 on the rebuilt runtime:
20/20 EQUAL with the period builds on E1 (030) and N6 (060). Kernel-space -2 (C2-3 v4): the conversion step writes the
shipped-form sidecar with bss= (KD060-Z 283 469, ZA-CD 284 945, K030-U 344 918, measured twice); loader-amix and kbootset -2
from amix-dlm 1230e8b (boot2 27 434 B); round trip on apkg 72f6a72 + kbootset 1230e8b 23/23 incl. the bss= negative.

## 2026-10-25 (night) — S2-12 kernel-space packages; gcc14 phase-2 smoke (9e54df8..a8f45d2) — minted, not published

kernel-k46-z 1.1.0.261025.51 and kernel-k46-zacd 1.1.0.261025.52: the port's KD060 kernels as brel (27 % smaller; axrel proves
both forms bind to the same image), sidecar verbatim except size=/sha256= restated for the shipped form; kernel-k30-u is a
stand-in, never catalogued. loader-amix 1.0.261025 (/stand/loader/{boot1,boot2,ldrinfo}, loader version 1) and kbootset
1.1.0.261025 (/sbin/kbootset, userland), built from amix-dlm fb9c1ce. recipes/common/kpkgroll.sh (pure-files roll),
dlm-src.sh; tools/kspace-roundtrip.sh: gen-catalog → apkg 0.3 -R → kbootset build/commit/check, 20/20, with gate-1 and
gate-2 refusals. gcc14 phase 2 (tools/gcc14-smoke/): grep and less byte-equal to the period builds on E1 and N6; make dies on
the 030+68882 with -mcpu=68060 FPU forms and matches with -m68020-60 — see tmp/2026-10-25-gcc14-eval/PHASE2.md.

## 2026-10-25 — TOOLCHAIN=gcc14 selector and gates; grep, less, make recipes ported (414de4a, b8985c1)

A selectable GCC 14 toolchain (Antti's gcc14-cross-amix, userland only per D-3 §9) beside the period default:
recipes/common/gcc14-env.sh with the switch items (SVR4/unix predefines, prototypes, hard-float), gates for DT_NEEDED bare
names, 68060 safety and the libc %lld printf defect (tools/gate-gcc14-selftest.sh, 10 checks). grep, less and make build with
TOOLCHAIN=gcc14 (one source patch for less). Emulator proof of the three packages and PHASE2.md still to come (the run was
stopped mid-way); nothing published.

## 2026-10-13 — initial public release (github.com/jusii/amix-packages)

Published from a fresh root: the recipes, the 68060 gate and its selftest, the registry and the docs as they
stood on 2026-10-13. LICENSE MIT; NOTICE lists the licences of the packaged programs and carries Amiga
Corporation's wording. Hashes cited above refer to the private development history.

## 2026-10-05 — 68060 re-mint of seven add-on packages, staged, not published (7942bb1..0109c8f)

A strict, permanent 68060 gate: any 64-bit MUL.L/DIV.L, MOVEP, CMP2, CHK2 or CAS2 fails the build, on every
file and archive, on the staged payload and on the rolled datastream (three scanners; selftest 10/10).
Re-minted through gcc-cross-amix 2ab2b22 as package revision -2: acompat 0.1-2, zlib 1.2.13-2, patch 2.5.9-2,
gzip 1.3.12-2, less 704-2, gtar 1.14-2, make 3.81-2; only the translation units that had sites changed.
grep 2.5.1a-2 and amix-benchmark 1.3 are clean and unchanged. tools/qemu060: old versus new site objects under
qemu-m68k as a 68020 and a 68060, 15 cases PASS. Staged at build/staging-060-20261005.

## 2026-09-26 — batch-2 PUBLISHED: grep 2.5.1a-2 (the LC060 fix), tar 1.14, make 3.81 (6139e66, d3502d3, 712e71a, 7cd0f88)

The published grep 2.5.1a carried two 64-bit MUL.L (gnulib strtoull/xstrtoumax on the -A/-B/-C/-m
path) that SIGKILL on the 68LC060; the shared D4 gate had been vacuous (0df1e71 fixed it). grep is
re-minted as 2.5.1a-2 from the D4-clean recipe (3559855), bench-proven on the emulated golden 030
including -A/-B/-C/-m, and published with tar 1.14 (PKG gtar, catalog name tar) and make 3.81 —
served catalog md5 20308547…, 41 entries; the old grep-2.5.1a.pkg stays served but decatalogued.
Registry carries the published blocks; the repo status notes say BATCH-1 client E2E done, batch-2
staged then published. Still owed: a D4 behavioural check of grep/tar/make on the LC060 itself.

## 2026-09-26 — batch-2 minted (tar 1.14, make 3.81); the D4 gate could not fire; BATCH-1 client E2E; MIT licence (02a962c, 3892a4b, 0df1e71, 3559855, dc34d0b, 9a4dd46, bc7e4bf)

amix-benchmark registry dates relabelled 2026-09-20 → 2026-09-16 (ledger clock drift). LICENSE: MIT,
copyright 2026 Jussi Alanärä, for this repo's own content only (libamixcompat BSD-2, recipe patches follow
their upstream, packaged programs keep their own). The D4 gate grepped for a mnemonic binutils 2.8.1
never prints; it now classifies MUL.L/DIV.L by opword and extension word, allows only the
vector-61-emulated #imm form, and self-tests first. tar 1.14: D3 via recipes/common/amix-pwgr.c with
a dynamic link kept, an lstat static-header-wrapper trap caught, 7 patches. make 3.81: -D_POSIX_SOURCE
+ a config.h.in patch, jobserver on, -l stubbed. Both bench-proven (stock pkgadd, smoke, apkg client
round trip against a local staging catalog). BATCH-1 client E2E: acompat, patch, zlib, gzip, grep and
less all PASS with apkg 0.2 on the emulated golden 030 against a byte-identical mirror of the live
catalog. Traps recorded: gcc-cross libgcc lacks the 68000 SI helpers (no -m68000 escape); the wrapper
passes -include to ld; heirloom pkgremove takes 5–10 host minutes on the emulated 030 and dies to
amixrun's SIGHUP unless run under nohup; a bench disk's /var/sadm/install/contents came back garbled
after apkg install/remove runs (kept as evidence, cause open).

## 2026-09-16 — amix-benchmark: our own suite minted as `amixbench` 1.1 → 1.2 → 1.3, PUBLISHED, client E2E on the real LC060 (02938c7, 7c6d72a, d29ebde, e34b6f2, ea302fb)

New recipe `recipes/amix-benchmark` (our own suite, outside the 23-package roadmap): catalog name
`amix-benchmark`, SVR4 pkginst `amixbench` (the 9-character limit), `/opt/amix`, category utility, no deps;
the m68k binaries + `runbench.sh`, BUILD-INFO, generated PROVENANCE, man page and fieldkit README ship
VERBATIM (unstripped) from the amix-kerntools fieldkit, sha256-pinned in `pin.sh`, DT_NEEDED libc.so.1 only;
offline `tests/smoke.sh`. 1.1: packaging metal-proven on the real 68LC060 A4000D but the no-arg suite stopped
after fpu.dhry — the driver's `matrix_rows | while read` pipe was drained by the benchmark children. 1.2:
re-mint at fieldkit 1.2 (`</dev/null` on all children; binaries unchanged). 1.3: `whet` dropped — it
statically defines libm from the sysroot's `/usr/ccs/lib/libm.a` (Commodore/AT&T object code; 1.2 never
reached the catalog); smoke step 7 refuses any binary defining libm.a symbols. PUBLISHED via
the packagemanager's `publish.sh`: `extra/amixbench-1.3.pkg`, md5 8f055b9d…, 132608 B, catalog 38 → 39.
Client E2E PASS on a fresh v7.1.4 install on the real LC060: `apkg update` → `install amix-benchmark`
(catalog name ≠ pkginst, resolved) → 69,953 dhry/s → remove clean; the bounded default suite completes on
soft-FPU metal in 369 s. Date note: the registry's "2026-09-20" labels are the ledger's clock drift — the
real date is 2026-09-16 (relabelled in a follow-up commit). The licensing bar that removed `whet` was
lifted on 2026-09-23; a 1.4 with whet follows the kerntools fieldkit re-mint.

## 2026-09-15 — the four review follow-ups closed (6586963)

PORTING.md:40's RAM citation repointed to the packagemanager's current RAM notes and the
drifted `llms-full.txt` citation dropped; `registry/rsync.yaml` no longer claims two binding floors
(INTEROP is the hard floor, MEMORY a non-binding consideration); ROADMAP §7 and `registry/x11r63lib.yaml`
close the x11 sizing question (no per-package byte cap exists; the ~6 MB split is a low-RAM courtesy).

## 2026-09-16 — the 16 MB RAM ceiling retracted from the porting docs and the registry (ce22af0)

PORTING.md, ROADMAP.md, the registry rationales and one source comment no longer state a 16 MB Fast-RAM
ceiling: the measured envelope is 64 MB on the stock 030 bench rig and 128 MB on real 040/060 silicon
(amix-kerntools `docs/ram-limits-reconciliation.md`); `version.chosen` untouched everywhere, INDEX.md
regenerated identically. Review follow-ups still open: PORTING.md:40's pointer into the packagemanager's
notes now lands on the wrong paragraph (RAM text moved to lines 160–196), a drifted llms-full.txt line
citation, the rsync.yaml "two floors" lead, and ROADMAP §7's deferred x11 sizing question (answer: no
per-package byte cap exists).
## 2026-09-15 — BATCH-1 published: registry, catalog-layout docs and the overtaken prefix decision (f6d2584)

Recorded, post-publish, what `../amix-packagemanager/tools/repo/publish.sh` did: six registry entries
(`acompat`, `patch`, `zlib`, `gzip`, `grep`, `less`) move `packaged` → `published`, each with a
`published:` block (date, catalog file under `pkgs/extra/`, md5, size — catalog 32 → 38). `registry/README.md`
documents the field and fixes `libamixcompat`'s `catalog_name` to `acompat`; `INDEX.md` regenerated. The
stale `/pkgs/<category>/…` wording corrected to the provenance-grouped layout (`pkgs/<set>/…`); `cats.conf`
was not staged with this publish. `COEXISTENCE.md` §7 and `ROADMAP.md` record honestly that the `/opt/amix`
prefix blessing was still open when BATCH-1 published (`patch`/`acompat` under `/usr/local`, the other four
under `/opt/amix` — now a live catalog fact). Client E2E for the six: pending on the metal. Reviewed and
landed 2026-09-16.


## 2026-09-15 — publish target moved: the LAN-only host retired, pkg.amigaux.org is canonical (c3cbbe6)

The family package repository moved off its former LAN-only host to the publicly reachable
`pkg.amigaux.org` (catalog at `/catalog`, packages under `/pkgs/<category>/…`), served plain HTTP for
the HTTP/1.0 `apkg` client. The repo's publish-target notes, `PORTING.md`'s transfer-laws entry and
`ROADMAP.md`'s publish-BATCH-1 status now point at the new host and cite
`../amix-packagemanager/tools/repo/publish.sh` (`PUBLISH_DEST` set by the maintainer,
`PUBLISH_URL=http://pkg.amigaux.org`) as the manual publish path. BATCH-1 published there 2026-09-15.


## 2026-09-14 — the graphics lane decided: X11R6.3 and Mesa 3.1 (5284e08, aed07fd)

- `isoriano1968/x11r6.3-amix` (the `Xzz9000` server) and `isoriano1968/mesa-amix` (Mesa 3.1) will
  be packaged for the catalog. `ROADMAP.md` gains D12 — the lane builds NATIVELY on the box: the
  cross wrapper has no `-shared`/`-G` path and bakes host paths into `DT_NEEDED` (only `libc.so.1`
  carries a SONAME on this target), and X11R6.3 needs imake/makedepend/bdftopcf/mkfontdir/rgb to
  *run* on the target — plus a §7 sizing the seven-package split (x11r63lib/srv/cli/f75/f1c/dev +
  mesa31, ≈26 MB estimated, ≈1.3× stock X11R4's measured 19.8 MB). X7 (native GCC 2.7.2.3 — stock
  `cdev` ships 1.4.2) and X8 (ZZ9000 kernel driver on the bench) recorded as open prerequisites.
  `registry/` gains the seven `candidate` entries (tier 5, difficulty H); `INDEX.md` regenerated
  (23 → 30). Not before 2026-09-19.
- `PORTING.md` and `recipes/README.md` corrected: the `$CC -E` preprocessing trap was fixed in
  `gcc-cross-amix` 3c2d272 (2026-08-29); marked historical in place, `amix-cpp` kept.


## 2026-09-01 — docs currency and harness hygiene after BATCH-1 (0fd63c9..eccc7ff)

- README rewritten as a front page that describes the repo as it is (six ports, the harness, the
  registry) rather than as it was on day one; the plan documents brought up to what was actually built.
- `PORTING.md` folds in the four traps BATCH-1 paid for and brings section 8 to six ports.
- Harness resolves the sibling repos relative to the checkout, not to `$HOME`.
- X3 closed: the registry's categories are agreed, not proposed; `registry/INDEX.md` regenerated.
- Reviewed and landed 2026-09-14.


## 2026-08-30 — BATCH-1: the first four real tools ship (zlib, gzip, grep, less) (88d45df..1330aa3)

Four ports built cross, rolled to `.pkg`, and bench-proven end to end on the emulated golden 030:
stock `/usr/sbin/pkgadd` (exit 0) → exercised by absolute path → `pkgchk` 0 → gzip+grep `pkgrm`
clean, one transcript. All install under `/opt/amix`, coexisting with stock (grep never touches
`/usr/bin/grep`); all four D4-clean (no LC060 64-bit-multiply hazard).

- **zlib 1.2.13** — first library on the line; static `libz.a`; the recipe compiles the objects so
  `gzprintf` keeps the secure `vsnprintf` path (asserted via `nm`).
- **gzip 1.3.12** — the first `.gz` on the box; self-contained (no libamixcompat), `match.S`
  disabled (SGS-assembler hazard).
- **grep 2.5.1a** — `-r`/`-o`/`--color`; bundled regex forced; `strcasecmp` from libamixcompat.
- **less 704** — a 2026 pager on 1992 SVR4 via `regcmp` (libgen) + the termcap API (`-DUSE_TERMCAP`);
  self-contained.
- Corrections folded to the registry: gzip/less link zero libamixcompat symbols (`depends.build`
  → []); gzip license GPL-3.0 → GPL-2.0-or-later. All four registry entries `status: packaged`
  with the real verification block.

Publication remains out of scope here (a separate, manual step). Cross-repo: gcc-cross-amix's wrapper puts
`-I<sysroot>/usr/include` ahead of a package's own `-I./lib`, silently defeating gnulib header
replacement (bit gzip; will bite coreutils/diffutils/tar) — a fourth wrapper fix for the gcc-cross
reconciliation.

## 2026-08-30 — Wave-0/1 kickoff: coexistence policy, stock audit, first-batch pick (2467986)

- **`COEXISTENCE.md` (+ ROADMAP D11): install under a shared `/opt/amix` prefix**
  (`--prefix=/opt/amix`, one `{bin,lib,man,share}`). `/usr/local` is reserved for the user's own
  hand-built binaries — packaged and non-packaged software stay in separate trees; never overwrite
  a stock-owned file; supersede stock by PATH `/usr/local/bin:/opt/amix/bin:/usr/bin:/bin`; port a
  tool only if it adds value over stock. `/opt` is SVR4's own location for add-on packages (cf.
  OpenCSW `/opt/csw`, Solaris freeware `/opt/sfw`).
- **Real `pkgadd` path-conflict behaviour recorded** (traced in the heirloom engine source): the
  stock admin default `conflict=ask` prompts, `nocheck` overwrites (co-owning the file), `quit`
  aborts — so `/opt/amix` (a tree no stock package owns) sidesteps the whole conflict class.
- **Stock-userland audit** for every Wave-0/1 tool, from real `amix-packagemanager` data: `core`
  ships `make`/`tar`/`grep`/`diff`/`compress`; `gzip`/`less`/`bzip2`/`rsync`/`zlib` are absent from
  `core`; `public/bin` = bash/elm/gcc/gdb; `patch` is Larry Wall 12u4. A `coexistence:` block is
  now on all 12 Wave-0/1 registry entries.
- **`BATCH-1.md`: first batch = zlib 1.2.13, then gzip 1.3.12 / grep 2.5.1a / less 704.**
- ROADMAP X3 (category taxonomy) resolved on the packagemanager side (`utility`/`editor` groups
  declared, `extra` set carries this repo's userland).

## 2026-08-28 — the line runs end to end: libamixcompat 0.1 and GNU patch 2.5.9 (df5b665..3ea58f1)

The first two packages built, rolled to SVR4 `.pkg` datastreams, installed with the **stock**
`pkgadd` on the emulated golden 030, exercised and removed. Publishing remains a separate
manual step, untouched here; X3 (category taxonomy) stays open — a local pkgadd from a
datastream needs no catalog. Both packages sit at `CATEGORY=development` (an existing group).

- **`acompat` 0.1** — first-party C89 shim, the blocker 17 of 23 registry entries carry.
  snprintf/vsnprintf written out (SVR4.0 printf has no `ll` modifier — `%llu` desynchronises
  varargs), float conversions delegated to libc's sprintf, `%n` deliberately unimplemented.
  5167-case host differential against glibc (0 failures) before any m68k instruction; shipped
  `acompat-test` reports 48/48 on the box.
- **`patch` 2.5.9** — fetch-pinned, cross-configured, no upstream patches. Correction landed:
  Amix is NOT patch-less — the stock `public` package ships Larry Wall patch 12u4 (1990); 2.5.9
  supersedes it.
- **Five corrections the bench forced into the plan** (none of PORTING.md's predicted-hardest
  actually was): `$CC -E` does not preprocess (autoconf silently used the host `/lib/cpp` →
  wrong `HAVE_*` — fixed by `recipes/common/amix-cpp`); the `__STDC__` gate is THREE keys, and
  `-D_POSIX_SOURCE` (which the guide warned against) is the one that works for patch; stock
  `pkgadd` corrupts a relative symlink target and reports success (targets now absolute);
  `environ` and one-argument `_abi_gettimeofday` join the library-dependent symbol set.
- Three silent `gcc-cross-amix` wrapper bugs found and routed around in `recipes/common/`
  (fixes belong upstream): `-E` unimplemented, a named archive placed before objects, and an
  explicit `-l` suppressing the implicit libc.

## 2026-08-28 — the repo opens: PORTING.md, the roadmap, and a 23-package registry (fe63c45..4c867e7)

- **Bootstrap** (fe63c45): role, edges (amix-packagemanager is the .pkg/catalog authority,
  gcc-cross-amix the toolchain), the (then LAN-only) package host as the manual publish target,
  recipes-in-git / fetch-at-build conventions.
- **PORTING.md** (6abf255): the standing constraints guide, probe-verified against the real
  cross toolchain rather than distilled from prose — the wrapper IS the compiler (`-S`
  bypasses all six fix_asm repairs), the `__STDC__` header gate proven (131 headers,
  sigaction incomplete in the ANSI view), the libc surface inventoried by nm (no
  snprintf/vsnprintf/realpath/getpagesize — and gcc 2.7 implicitly declares them anyway),
  SVR4 /proc is 37 PIOC ioctls, and corrections to the brief it was given: config.sub knows
  m68k-cbm-sysv4; the PKG name limit is 9 chars and truncates silently; stock Amix REQUIRES
  an FPU — printing a float dies SIGSYS on FPU-less parts (the family's FPE kernel is what
  makes LC060 boxes viable targets). 16 claims carry explicit UNVERIFIED tags.
- **ROADMAP.md** (ce80a86): the three-jobs framing (re-mint proven Amix builds / modernise
  ssh+TLS / port what's missing), Waves 0–4, ten standing decisions D1–D10 (LAN-proxy
  everything; link -lcurses; static + in-executable getpwnam; the 060 objdump mulu.l gate;
  never autoreconf — the gnulib wall is the boundary), six cross-repo dependencies X1–X6.
- **registry/** (f175c48): 23 candidate packages, schema projecting into the
  packagemanager's live catalog format, mandatory cpu_lanes with the 060 gate, shared
  blocker ids (SHIM-SNPRINTF appears in 17 of 23 — libamixcompat is objectively first),
  generated INDEX.md. **recipes/** convention (4c867e7). No .pkg minting until the X3
  category-taxonomy decision lands with the packagemanager side.
