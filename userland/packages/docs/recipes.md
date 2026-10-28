# recipes/ — one directory per port

Plan and package selection: [`../ROADMAP.md`](../ROADMAP.md) · machine-readable entries:
[`../registry/`](../registry/) · the constraints every recipe inherits:
[`../PORTING.md`](../PORTING.md).

## What is here

| Recipe | Package | Status |
|---|---|---|
| [`libamixcompat/`](libamixcompat/) | `acompat` 0.1 — the missing-libc shim | **published** 2026-09-15 (`/usr/local`); 0.1-2 re-mint staged |
| [`patch/`](patch/) | `patch` 2.5.9 — GNU patch | **published** 2026-09-15 (`/usr/local`); 2.5.9-2 re-mint staged |
| [`zlib/`](zlib/) | `zlib` 1.2.13 — the deflate/inflate library (static) | **published** 2026-09-15 (`/opt/amix`); 1.2.13-2 re-mint staged |
| [`gzip/`](gzip/) | `gzip` 1.3.12 — the `.gz` compressor | **published** 2026-09-15 (`/opt/amix`); 1.3.12-2 re-mint staged |
| [`grep/`](grep/) | `grep` 2.5.1a — recursive/color GNU grep | **published** 2026-09-15; 2.5.1a-2 (68060-clean) published 2026-09-26 (`/opt/amix`) |
| [`less/`](less/) | `less` 704 — the backward-scrolling pager | **published** 2026-09-15 (`/opt/amix`); 704-2 re-mint staged |
| [`tar/`](tar/) | `gtar` 1.14 (catalog name `tar`) — GNU tar, base-256 aware; the first D3 package | **published** 2026-09-26 (`/opt/amix`); 1.14-2 re-mint staged |
| [`make/`](make/) | `make` 3.81 — GNU make | **published** 2026-09-26 (`/opt/amix`); 3.81-2 re-mint staged |
| [`amix-benchmark/`](amix-benchmark/) | `amixbench` 1.3 (catalog name `amix-benchmark`) — the amix-bench suite | **published** 2026-09-16 (`/opt/amix`) |
| [`kernel-k46/`](kernel-k46/) | `kernel-k46-z` / `kernel-k46-zacd` — stage-2 static 040/060 kernels (brel + sidecar); kernel-space recipes overview in its README | minted 2026-10-25; **retired** (S4-24), out of the catalog since 2026-10-27 (S5-34), datastreams in `build/kspace/superseded/static-1.0/` |
| [`kernel-k30-u/`](kernel-k30-u/) | `kernel-k30-u` — the K030-U with kinfo (build 68030-261026-01), unix + kabi verbatim | minted 2026-10-26; **retired** (S4-24), out of the catalog since 2026-10-27 (S5-34), datastreams in `build/kspace/superseded/static-1.0/` |
| [`kernel-k30/`](kernel-k30/) | the r7 K030-U stand-in | **superseded** by `kernel-k30-u/`, never shipped |
| [`kernel-k46-m/`](kernel-k46-m/) | `kernel-k46-m` (`kern46m`) — the 040/060 module kernel (build 68060-261028-51, kabi k46.1.2, ET_REL; no built-in ufs/s5, rth1=2; core amix-dlm 7b07bce), unix + kabi verbatim, and the cut's ufs core-tier module at `/etc/conf/mod.d/ufs` (C2-3 v8 sec 1; no k46 s5, S5-37) | -51 (port 87b8a88: the ufs module refuses a ufs with blocks under 4 KiB at mount, EINVAL, where -50 mounted a 2 KiB-block ufs and panicked in ufs_getapage; carries the release notes) minted 2026-10-28, proven by the Bench in emulation (-82/-50 → -51 with kbootset -23), in the catalog of record `b1f564f4` since 2026-10-28 04:34, not published; -50 (the S5-13 re-cut: -91's core kept the stamp's blank and refused its own ufs) in the record `6f0c1701` 03:19–04:34, never published; -91 never published |
| [`kernel-k30-m/`](kernel-k30-m/) | `kernel-k30-m` (`kern30m`) — the 030 module kernel (build 68030-261027-20, kabi k30.1.2, brel; no static A4091/Gayle drivers or cdfs, no built-in ufs/s5, rth1=2; rth1 RAM-disk root, swap /dev/fakeswap), unix + kabi + unix.sym verbatim, and the cut's ufs and s5 core-tier modules at `/etc/conf/mod.d` (C2-3 v8 sec 1) | -20 (S5-12) minted 2026-10-27, in the catalog of record since 2026-10-27 19:48 (`915e09f3` on), not published |
| [`z3660eth/`](z3660eth/) | `z3660eth-k30` / `z3660eth-k46` (`zeth30`/`zeth46`) — the Z3660 ethernet module of each line, `/etc/conf/mod.d` + `modreg.d` (C3-5 v4) | minted 2026-10-26, staged, not published |
| [`z3660rtg/`](z3660rtg/) | `z3660rtg-k30` / `z3660rtg-k46` (`zrtg30`/`zrtg46`) — the Z3660 RTG module of each line; `depend=monsw`, composable once a monsw package exists | minted 2026-10-26, staged, not published |
| [`z3660scsi/`](z3660scsi/) | `z3660scsi-k30` / `z3660scsi-k46` (`zscsi30`/`zscsi46`) — the Z3660 SCSI driver (piscsi mailbox), a root-class module of each line (kabi 1.2); the data-cache arm set at load from the CPU type (`param cache=` overrides; k30 always 0) | 1.0.0-2 (amix-z3660scsi 209bdd2) minted 2026-10-27, staged, not published |
| [`ramdisk/`](ramdisk/) | `ramdisk-k30` / `ramdisk-k46` (`ramdisk30`/`ramdisk46`) — the RAM disk, a root-class module of each line (kabi 1.2), with its `/dev/dsk/ram0`–`ram2` block nodes | minted 2026-10-26, staged 2026-10-26 (packagemanager abfaaac), not published |
| [`a4091/`](a4091/) | `a4091-k30` / `a4091-k46` (`a409130`/`a409146`) — the A4091/A4092/A4770 SCSI driver, a root-class module of each line (kabi 1.2, DDI 1.2 DMA; k30 through the core's 030 provider, kern30m -14 or later; -13 drove the A4091 itself, -14 does not) | 1.0.0-5 (amix-a4091 5044872) minted 2026-10-27, staged, not published |
| [`a4kt710/`](a4kt710/) | `a4kt710-k30` / `a4kt710-k46` (`a4kt71030`/`a4kt71046`) — the A4000T onboard NCR 53C710, amix-a4091's second module target: root class, `mobo:a4000t-710`, rank `mobo` (kabi 1.2, DDI 1.2 DMA); `_load` touches nothing under `0xDD0000` without the Kickstart's `NCR scsi.device` tag (C4-2 v6 §8.1; `param declared=0` in `modreg.local.d` disables it); built here from a git archive of the pinned commit | 1.0.0-1 (amix-a4091 a74708e) minted 2026-10-27, staged, not published |
| [`gayle/`](gayle/) | `gayle-k30` / `gayle-k46` (`gayle30`/`gayle46`) — the A4000 Gayle IDE driver, a root-class module of each line (kabi 1.2), interrupt I/O by default after a boot self-test (`param intr=0` in `modreg.local.d` selects polled); kern30m -13 drove the Gayle itself, -14 does not; a page-crossing request counted, printed only with `param debug=1`; must not ship before amix-dlm's root-context check passes | 1.1.0-3 (amix-gayle-ide b2935fc) minted 2026-10-27, staged, not published |
| [`cdfs/`](cdfs/) | `cdfs-k30` / `cdfs-k46` (`cdfs30`/`cdfs46`) — the read-only CD filesystem (ISO 9660, Joliet, Rock Ridge, UDF, HFS), a boot-class module of each line (kabi 1.2, `match=always`, `fs=cdfs`), promoted to a root record on a cdfs-rooted generation; needs kern46m -79 / kern30m -14 or later (the filesystem names) | 1.0.0-1 (amix-cdfs fd6cad8) minted 2026-10-27, staged, not published |
| [`loader-amix/`](loader-amix/) | `loader-amix` — boot1 + boot2 + `ldrinfo`, loader version 3 | -9 (amix-dlm ea75578) minted 2026-10-27, staged, not published |
| [`kbootset/`](kbootset/) | `kbootset` — `/sbin/kbootset`, static, GCC 14 (gcc14-cross-amix cf461e3, checked against `common/gcc14-pin.sh`) | -23 (amix-dlm e089c2a: C2-4 v15, mark-good marks a refused default bad when its bytes are damaged) minted 2026-10-28, proven by the Bench in emulation (members verify; upgrades alone), in the catalog of record `b1f564f4` since 2026-10-28 04:34, not published; its DESC carries the kernels' release notes (below); -22 (1308c0b) in the records up to `6f0c1701`; upgrade kern30m -20 and kern46m -50 together with -22 or later (an old mobo root record on a 030-mode Z3660 is rewritten only from -22 on) |
| [`modtools/`](modtools/) | `modtools` — `/sbin/modadmin`, the module administrator, static, GCC 14; postinstall/preremove keep its `modadmin -B` line first among `/etc/inittab`'s sysinit entries; GCC 14 cf461e3 as kbootset | -7 (amix-dlm 4442c76; 1308c0b and e089c2a build the same modadmin, f51c98d6) minted 2026-10-27, staged, not published |
| [`dlmkit/`](dlmkit/) | `dlmkit30` / `dlmkit46` — the amix-dlm ABI kit of each kernel line (`make kit`, manifest-pinned) under `/usr/dlm/kit/<line>/`, under the kit's own names (all within s5's 14 bytes since -2) | -11 (amix-dlm c2dc7fb, kabi 1.2) minted 2026-10-27, staged, not published |
| [`common/`](common/) | the shared harness — not a package | |

**Kernel-space catalog of record** (gitignored, staged, not published): `build/kspace/repo/`,
catalog `b1f564f4` since 2026-10-28 04:34 — the candidate root `build/kspace/candidate-b1f564f4`
promoted after the Bench proved it in emulation (k46 -82 → -51 and -50 → -51, k30 -17 → -20, each
with kbootset -23 in one transaction and each booting on the ufs module with check 0; -23's mark-good
marks a damaged refused default bad and keeps an intact one; kbootset -23 upgrades alone; -51's ufs
refuses a 2 KiB-block ufs at mount, EINVAL, and the box stays up): `6f0c1701` with kbootset -22 → -23
and kernel-k46-m -50 → -51 (the ufs mount guard), every other row and datastream byte-identical.
`6f0c1701` (`915e09f3` with kernel-k46-m -91 → -50, the S5-13 re-cut the Bench proved in S5-13) is
`repo-20261028-0434`. A replaced root is kept byte-identical under
`build/kspace/superseded/repo-<YYYYMMDD-HHMM>/`: `915e09f3` (the S5-12 set: kernel-k30-m -20 and
kernel-k46-m -91, the cuts without built-in ufs/s5, whose kernel packages carry the filesystem
modules, and kbootset -22; every other row as in `64d37aaa`, no module rows for ufs/s5) is
`repo-20261028-0319`, `64d37aaa` (`b2a0e874` plus a4kt710-k30/-k46 1.0.0-1, S5-06) is
`repo-20261027-1948`, `b2a0e874` (the first stage-5 catalog: kbootset -21, modtools -7, no static
1.0 family — kernel-k30-u, kernel-k46-z, kernel-k46-zacd left it, S5-34, datastreams in
`build/kspace/superseded/static-1.0/`) `repo-20261027-1353`, `b198e9e2` (the stage-4 exit set plus
gayle-k30/-k46 1.1.0-3) `repo-20261027-1344`, the stage-4 exit set (`6e60a128`)
`repo-20261027-1329`. No next root and no candidate root is staged; the never-promoted candidate
`059c7c53` (`6f0c1701` with kbootset -23 only, superseded by `b1f564f4`) is withdrawn to
`build/kspace/withdrawn-20261028/candidate-059c7c53` (every datastream it held is in `6f0c1701` or
`b1f564f4`). The promotion's before/after manifests are in `build/kspace/promote-b1f564f4/`.
`tools/kspace-roundtrip.sh` regenerates the newest set's catalog from `build/kspace/pkg/` and requires
it equal byte for byte to the staged root's (`KSPACE_ROOT`, else the next root, else the one
candidate root, else the catalog of record), runs the stage-2 static-kernel rows from a second source
that adds the static datastreams, the S5-12 R5 upgrades (`apkg upgrade kbootset <kernel>`, one
transaction) from `64d37aaa`'s kernels, from `915e09f3`'s and from `6f0c1701`'s, all three kept in
`build/kspace/superseded/` (`KSPACE_RECORD_ROOTS` to move them; a line whose kernel is the staged
root's is skipped): k46 -82, -91 and -50 → -51, k30 -17 → -20, each with kbootset -23; and R6, which
upgrades kbootset alone (-22 → -23) over a root installed from the previous record `6f0c1701`
(`KSPACE_CUR_ROOT`) when the staged root's kbootset is newer. The record's run is
`build/kspace/rt-record-b1f564f4.log`; the earlier runs (kern46m -50) are in
`build/kspace/rt-record-6f0c1701c.log` and `rt-cand-059c7c53-onever.log`.

**One version, one set of bytes.** A datastream in the catalog of record is never re-rolled at its
version. The kernel release notes added 2026-10-28 (upgrade together with kbootset -22 or later; on
k46, s5 no longer mounts, S5-37) are in `kernel-k30-m/pkginfo` and `kernel-k46-m/pkginfo`, so the
NEXT cut of each line (a new version) carries them -- kern46m -51 is the first, with one more line
(a ufs with blocks under 4 KiB is refused at mount on the 68040/68060 line); the shipped kern30m -20
and kern46m -50 keep their record text, and kbootset -23's DESC carries the notes until then. Re-running those two recipes
at -20 / -50 would write different bytes under the same version: do not. The text re-rolls made by
cfcfe78 (and its candidate `9c670fb4`, and that commit's first -23 datastream) are withdrawn to
`build/kspace/withdrawn-20261028/`, outside every path a recipe or the round trip reads.
Enforced since 2026-10-28 by `common/onever.sh` (`onever.py`): both roll functions (`amix_pkgroll`,
`amix_kpkgroll`, so every recipe) roll into the work dir and install the datastream at its output
path only if its pkginst + version is listed in no kspace root (`build/kspace/repo`, `next/repo`,
`candidate-*`, `superseded/repo-*`; `AMIX_ONEVER_ROOTS` replaces the list) or is listed there with
these very bytes; otherwise the roll is refused and the datastream already at the output path is
left as it was. A roll is not bit-reproducible (the newc headers carry the spool's inode numbers),
so in practice a listed version is never rolled again. `sh tools/onever-selftest.sh` proves it.

**BATCH-1 (zlib, gzip, grep, less)** install under **`/opt/amix`** (`COEXISTENCE.md`, ROADMAP D11),
not the `/usr/local` the two Wave-0 recipes above still use — each batch-1 recipe exports
`AMIX_PREFIX=/opt/amix` before sourcing `amix-env.sh`, whose default is still the old `/usr/local`
(moving that default, and the `patch`/`libamixcompat` re-mint, is the separate prefix follow-up). So
the `/usr/local` sections below describe the two earlier recipes; the four batch-1 prototypes emit
no path outside `/opt/amix`, declare `/opt` as the one shared parent, and add no `/usr/bin` symlink.

All six were built, rolled to `.pkg`, installed with the **stock** `pkgadd` on the emulated golden
030, exercised, and removed again. The pipeline works end to end; what each recipe learned doing it
is in its own README, and the constraints it corrected are in `PORTING.md`.

## The shared harness — `common/`

Sourced by every recipe so none re-derives a flag and none can bypass the wrapper.

| File | What it is |
|---|---|
| `amix-env.sh` | The one place a recipe learns what "build for Amix" means: `CC`/`AR`/`NM`/`OBJDUMP`, the standard flags, the sysroot, the host pkgtools, the shared prefix. Refuses if `CC` resolves to `gcc.real`. |
| `fetch.sh` | Checksum-verified fetch. Knows *how* to verify a digest; never knows what any digest should be — that lives in each recipe's own `pin.sh`. Verifies before extract, always. |
| `pkgroll.sh` | `pkgmk` + `pkgtrans` with five gates: PKG name ≤ 9 chars, `ARCH=Amiga`, the **s5 14-byte** basename/collision scan, `070701` magic at offset 512, and a round-trip unpack. |
| `kmodpkg.sh` | One module package (amix-dlm C3-5 v4 sec 1) per line: the driver repository's object verbatim at `/etc/conf/mod.d/<name>`, the recipe's `modreg` at `/etc/conf/modreg.d/<name>`, `module/VERSION` (or `KM_VERSION_FILE`, a repository's second module) checked, the ABI kit's `modcheck.py` (k46: the 68060 scan), rolled by `amix_kpkgroll`. |
| `kfsmod.sh` | The filesystem modules a kernel package carries (amix-dlm C2-3 v8 sec 1): the pin, the kit's `modcheck`, `.moddata` (`tier=core`, `class=boot`, `fs=`, the line's kabi, `build=` the cut's own), and a rebuild from the cut's carve sources byte-equal to the pinned object (S5-12 R2). Since kern46m -50 (S5-13) also `amix_kcore_strips` (the cut's core is the pin and contains amix-dlm 7b07bce, the first core that skips the stamp's leading blank) and `amix_kbuildid3` (`kbuildid.py`: the core's rule over the shipped bytes — the image's buildid without leading blanks == the sidecar's `build=` == each module's `.moddata build=`); `sh tools/kbuildid-selftest.sh` proves both refuse (-91's ufs against the -50 kernel, the -91 cut's core 76f83d8). |
| `kpkgroll.sh` | The kernel-space roll (kernel and loader packages, amix-dlm C2-3): `pkgroll.sh`'s name/arch/s5/newc gates, a pure-files gate (f/d class none only), a byte-for-byte payload round trip, no userland 68060 gate; `amix_kstage_sidecar` restates a sidecar's `size=`/`sha256=` for the brel form shipped. |
| `dlm-src.sh` | Builds amix-dlm artefacts (boot1, boot2, kbootset, modadmin, the ABI kits) from a pinned commit: `git archive` into `build/kspace/src/`, amix-dlm's own Makefile (`make kit` labelled with the pinned commit through a git shim); the sibling checkout is only read. Before a box binary (kbootset, modadmin) it proves the GCC 14 prefix is the pinned one (`gcc14-pin.sh`) and rebuilds `build/box` when it was built by another. |
| `gcc14-pin.sh` | The gcc14-cross-amix identity: the pinned commit, the sha256 of cc1/libgcc.a/libamixc99.a/specs, the return-value ABI self-check. Sourced by `gcc14-env.sh` (TOOLCHAIN=gcc14 recipes) and `dlm-src.sh` (box binaries). |
| `gates.sh` | The object-code gates: **D4** (no register/memory-source 64-bit `MUL.L`, no 64-bit-dividend `DIV.L` — classified by **encoding**, and self-tested on a probe before any pass is trusted; see the note below), "is it really an m68k SVR4 ELF", the undefined-symbol listing, and the no-imported-assembly check. |
| `amix-pwgr.c` | **D3**: `getpwnam`/`getpwuid`/`getgrnam`/`getgrgid` as direct `/etc/passwd`/`/etc/group` parsers, linked as a plain object into any executable that maps uid↔name, so the stock libc's first-call `getpwnam` crash is never reached. MIT (this repo). |
| `amix-cpp` | A C preprocessor for autoconf's `CPP`. Still used by every recipe so far — see the trap below and the 2026-08-29 fix note that follows it. |

`amix-env.sh` resolves the two sibling repositories it needs — `../gcc-cross-amix` for the toolchain
and `../amix-packagemanager` for the Heirloom `pkgmk`/`pkgtrans` — **relative to this checkout**, so
a clone works wherever the workspace layout holds rather than only in one developer's tree. Override
either with `AMIX_CROSS_ENV` / `AMIX_PKGMGR`, or the checkout root itself with `AMIX_REPO_ROOT`; a
sibling that is missing fails loudly with the path it looked for.

### ★ The trap that makes `amix-cpp` exist

`m68k-cbm-sysv4-gcc -E` **did not** preprocess. The wrapper had cases for `-c` and `-S`; `-E` fell
through to its "unrecognised dash argument is an ld flag" branch, so it **linked** the file and
exited 0 with a linker complaint on stderr. Autoconf rejected `$CC -E` and fell back to **`/lib/cpp`,
the build host's preprocessor** — after which every `AC_CHECK_HEADER` presence test read the *host's*
`/usr/include`, and autoconf 2.5x resolves a presence/usability disagreement by *trusting the
preprocessor*. `patch` got `HAVE_WCHAR_H 1` for a header Amix does not have. That one failed loudly;
the same mechanism sets `HAVE_*` for anything that merely looks present on a modern Linux host, and
most of those fail quietly.

**★ FIXED 2026-08-29** (`gcc-cross-amix` 3c2d272): the wrapper now dispatches `-E` to the real
compiler with its own target include path, exactly as `-S` was already dispatched, so
`m68k-cbm-sysv4-gcc -E` preprocesses correctly and autoconf no longer falls back to the host's
`/lib/cpp`. The trap above is kept in full because it is the reason `amix-cpp` exists and it
explains why every recipe so far still passes it as `CPP`: `amix-cpp` calls `gcc.real -E` directly
with the sysroot include path added by hand, which is exactly what the wrapper now does internally
— it was never broken by the wrapper's old defect and is not made redundant by the fix, so nothing
here needs to change. A *new* recipe may pass `$CC` directly as `CPP` instead.

### ★ The D4 gate could not fire until 2026-09-26

It grepped `objdump -d` for `mulu.l …,%dH:%dL`. binutils 2.8.1's objdump prints MIT syntax —
`mulul %fp@(12),%d1,%d2`, no dot, no colon — so the pattern never matched and every package
reported "D4 ok" whatever it contained. The gate now classifies each `MUL.L`/`DIV.L` from its
opword and extension word (bit 10 = the 64-bit form; opword `0x4c3c` = the `#imm` source the
kernel's vector-61 handler emulates), and `amix_gate_d4_selftest` must see it reject a probe
before a build may trust a pass. Re-scanned under the real gate: the published `grep` 2.5.1a
**fails** (two register/memory-source multiplies in gnulib's `strtoull`/`xstrtoumax`); the other
published packages and the `amix-benchmark` binaries pass. The fix for a failing site is to route
the product through libgcc's `__muldi3` (built from 32-bit multiplies only) — ROADMAP D4's
"build the TU `-m68000`" does not work here, because this `libgcc.a` has no
`__mulsi3`/`__divsi3`/`__udivsi3`/`__umodsi3`.

### ★ 2026-10-05: D4 is strict — no 64-bit multiply in any form

The `#imm` source form the gate used to allow is what gcc 2.7.2.3 emits for every divide or modulo
by a constant, and a 68060 traps it like the others (Amix SIGKILLs; the release ships nothing that
leans on kernel emulation). The cure is the toolchain's: gcc-cross-amix `2ab2b22` fix_asm rule 11
rewrites each 64-bit multiply into 16x16 `mulu.w` partial products. `amix-env.sh` refuses
`AMIX_MUL64=keep` and sets `AMIX_SCAN060=1` (the wrapper scans each object it compiles);
`amix_gate_d4` fails on any 64-bit `MUL.L`/`DIV.L`, `movep`, `cmp2`/`chk2`/`cas2`, with three
scanners: the awk one, the toolchain's `m68k-cbm-sysv4-scan060` (run with a modern
`m68k-linux-gnu-objdump`: binutils 2.8.1 prints a linked binary's `0x8000xxxx` addresses
sign-extended, the scanner then misses every switch table and reports table words as `movep`) and
`../amix-packagemanager/tools/repo/scan060.py` (the scanner of record for linked files and `.pkg`;
it does not open `ar` archives). `amix_pkgroll` runs the gate over the whole staged payload before
`pkgmk` and `scan060.py` over the rolled datastream after, and checks pkginfo `VERSION` against the
datastream name. `sh tools/gate060-selftest.sh` proves every layer rejects an unsafe artifact.
The `__muldi3` routing in `grep`/`tar` patches stays (harmless, and still correct).

### ★ Two wrapper link rules, both silent when broken

1. **An archive named on the command line lands *before* the objects.** The wrapper collects
   `foo.a` while parsing, then *appends* the objects it compiles from `.c` sources, so
   `gcc prog.c libfoo.a` links as `libfoo.a prog.o` — single-pass `ld` extracts nothing and every
   symbol in the archive comes back undefined. Use `-L`/`-l`, which land after the objects.
2. **Any explicit `-l` suppresses the implicit libc.** The wrapper defaults to `libs=(c)` only when
   *no* `-l` was given, so `-lacompat` alone drops libc entirely — and the first casualties are
   `crt1.o`'s own `atexit`/`exit`/`_environ`, which makes it look like a broken toolchain rather
   than a missing flag. **Always end the library list with `-lc`**, including in a configure-filled
   `LIBS=`.

## Layout

One subdirectory per tool, named for its registry entry (`recipes/<name>/`, matching
`registry/<name>.yaml`'s `recipe:` field). Each holds four things, per [`CONTRIBUTING.md`](../CONTRIBUTING.md):

| Piece | What it is |
|---|---|
| **Source pin** | Upstream URL **plus a sha256**, verified **before** extraction. Never a vendored source tree in git — fetch at build time. `../amix-040-060-port/tools/netbsd-pin.sh` is the established family pattern to imitate. |
| **Patches** | Unified diffs applied in a stated order. Each patch's reason belongs in a comment or a per-patch note — a patch nobody can explain is a patch nobody can rebase. |
| **Build script** | The entry point. Sets `CC=m68k-cbm-sysv4-gcc` **explicitly** (unset, you silently get gcc 1.4.2) plus the standard flags and sysroot, so no recipe re-derives them and none can bypass the wrapper. |
| **`pkginfo` / `prototype`** | Authored, not generated. `PKG` name **≤ 9 characters** or stock `pkgadd` silently drops the package; `ARCH=Amiga`, never `m68k`. `pkgproto` silently omits symlinks, so a generated prototype is a starting point at best. |

Everything a build produces — source tarballs and `.pkg` artifacts alike — lands under the
gitignored `build/`. Git tracks recipes and docs only.

### How an authored prototype stays free of host paths

The obvious prototype line is
`f none /usr/local/bin/patch=/home/…/build/dest/usr/local/bin/patch`, and it makes the file
*generated*, because half of it is one developer's home directory. `pkgroll.sh` runs
**`pkgmk -r <destroot>`**, which resolves each prototype path against the staged tree instead — so
what is committed is exactly the package's installed layout and nothing about anybody's machine.

### Why the two Wave-0 recipes sit at `/usr/local`

**Superseded as policy.** The shared prefix is `/opt/amix` (`../COEXISTENCE.md` §1, ROADMAP D11).
What follows is the reasoning that put `libamixcompat` and `patch` there before that policy was
settled, kept because those two packages are still minted at `/usr/local`.

Not a convention borrowed from elsewhere: **the stock Amix PATH already begins with it**
(measured on the box) —

    PATH=/usr/local/bin:/usr/bin:/usr/ccs/bin:/sbin:/usr/sbin:/etc:/usr/ucb:/usr/amiga/bin:
         /usr/public/bin:/usr/hosts

so a package installed there takes precedence over `/usr/public/bin` without displacing anything,
and `/usr/local` plus `/usr/local/bin` already exist on a stock root (dated Nov 1991). `/usr/apkg`
is taken by the package manager's own parallel prefix.

### ★ Symlink targets must be ABSOLUTE

Measured on the box, same `.pkg`, same admin file, only the engine differing:

| engine | result |
|---|---|
| stock `/usr/sbin/pkgadd` | `/usr/bin/patch -> /../local/bin/patch` — **dangling** |
| heirloom `/usr/apkg/bin/pkgadd` | `/usr/bin/patch -> ../local/bin/patch` — correct |

The pkgmap line was byte-identical in both runs, so this is an **engine defect**: stock `pkgadd`
prepends the install root to a *relative* symlink target, and reports "Installation was successful"
either way. A package shipped from this repo must survive a bare box, where the only engine is the
stock one — so relative targets are not available to us. The cost is `pkgadd -R` correctness, which
is the right trade for a developer tool; stock `core` uses absolute targets for the same reason
(`s none /usr/bin/uname=/sbin/uname`).

## The two rules that make recipes hand-written

Both are argued in full in `PORTING.md §5`; they are restated here because they are what this
directory's shape encodes.

1. **Automate the recipe. Never automate the porting.** Checksum-verified fetch, the shared build
   harness, the `.pkg` rolling and the bench smoke loop are all mechanical. The decisions inside a
   recipe — which version, which cached `ac_cv_*` answer, which patch — are not, and a wrong cached
   answer is a *silent* miscompile.
2. **Verify the encoding, never the exit status.** The family law. A build that exits 0 proves
   nothing on this toolchain: `fcmp` operand order, SGS `#`-as-comment, and constant-folded FP all
   produce clean exits and wrong binaries. Every recipe ends in an `objdump -d` gate, including the
   060 lane's `mulu.l`/`muls.l` `Dh:Dl` check (`ROADMAP.md` D4).
