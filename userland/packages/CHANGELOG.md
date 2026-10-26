# Changelog

Commit hashes cited in entries dated before 2026-10-13 refer to the pre-public development
history, which the maintainer keeps; they are provenance, not links into this repository's history.

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
