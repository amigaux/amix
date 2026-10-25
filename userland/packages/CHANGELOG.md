# Changelog

Commit hashes cited in entries dated before 2026-10-13 refer to the pre-public development
history, which the maintainer keeps; they are provenance, not links into this repository's history.

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
