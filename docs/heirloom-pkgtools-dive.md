# Heirloom pkgtools (aflat mirror) — deep-dive findings

> *Historical — records how the 2026-07-04 direction was chosen. The engine was adopted, ported
> and shipped; the port log is [../heirloom/AMIX-PORT.md](../heirloom/AMIX-PORT.md) and current
> state is [../NOTES.md](../NOTES.md).*

**What:** source-level deep dive into `github.com/aflat/heirloom-pkgtools` — the open (CDDL) Sun
SVR4 `pkg` implementation — to decide whether Amix should adopt it, whether it fixes the
space-in-filename bug, and what else lurks in it.
**How:** source dive 2026-07-04 (5 topics, each independently re-verified).
All key claims verified **empirically on this Linux host**: the tree was **actually built** (three
independent build recipes), the real `srchcfile()` parser was compiled into a test harness and fed
Amix's exact corrupt factory record, and a full `pkgmk → pkgtrans → pkgadd → pkginfo → pkgrm`
lifecycle was exercised against an Amix-faithful fake `/var/sadm`.
Raw digest kept outside this tree. Reusable artifacts:
[`../research/heirloom/`](../research/heirloom/) (validated patches, harness, de-OpenSSL kit,
link-set inventories).
**Confidence:** ✅ = reproduced empirically here · 🟡 = code-read/inference · **BENCH** = needs the
WinUAE/real box.

---

## Headline answers

### Does it fix the space-in-filename bug? — **NO** ✅ (but we already built the fix)

Empirically proven twice, independently: feeding the exact factory record
(`/usr/x11r5/fonts/server/MacFS/TrueType Fonts f none 0444 …`) to Heirloom's parser and to the
built tools reproduces the stock failure — `pkgrm` aborts with the **byte-identical** message
(`bad read of contents file / pathname=/usr/x11r5/fonts/server/MacFS/TrueType / problem=unknown
ftype`, exit 99-class), `pkginfo -l` and `pkgchk` abort too. Same AT&T lineage, same tokenizer:
the pathname scan stops at the first space (`srchcfile.c:443-448`, `:694-708`), `F` of `Fonts`
hits the unknown-ftype default (`:832-841`).

Why this is still good news:

- **The failure is shallow and we own the source.** The dive produced and validated a **36-line
  "tolerant re-join" patch** to `libpkg/srchcfile.c` (`research/heirloom/contents-harness/tolerant.patch`):
  when the token after a pathname isn't a valid single-char ftype, the pathname is extended over it
  and the parse retried. It recovers the factory record **exactly** (path with the space, f, none,
  0444, x sys, size/cksum/mtime, npkgs=2) with zero regressions on valid records ✅. `libpkg` is
  statically linked into every tool, so one patch fixes `pkgrm`/`pkginfo`/`pkgchk`/`installf`/
  `removef` at once.
- **`pkgadd` is already safe on the corrupt DB** ✅: targeted merges pass the corrupt line through
  verbatim unless you install exactly the truncated path, and error paths abort before the temp
  file is committed — the DB can't be damaged by it.
- The parser is **resumable** (the stream is left positioned past a bad line ✅), so a
  skip-and-warn variant (~6–10 LOC × 5 consumer sites) or a **contents-fsck** tool (the dive's
  harness is ~80 % of one; est. 150–250 LOC total) are both easy alternates.
- Note the format itself can never *represent* a space (no quoting) — so the on-disk repair
  question (rename the `TrueType Fonts` file vs keep the tolerant parser) remains a policy choice.

### Should we go with it? — **Yes, for the SVR4-engine role, with a defined ~6-patch set.**

The dive strengthened the case on every axis that could be tested off-bench — **and** found three
concrete blockers nobody knew about (below). It did not change the strategic picture: the thin
remote/catalog client is still a separate deliverable this codebase doesn't provide.

---

## The good news (all empirical ✅)

- **It builds today, almost effortlessly.** Full tree on a 2026 Linux host (gcc 15): **3 small
  source fixes + 3 mk.config flag changes, 11.5 s build**, all 13 package commands + valtools link
  (`research/heirloom/host-build-fixes.patch`, `FIXLOG.txt`). Full lifecycle passes: `pkgmk` →
  `pkgtrans` round-trip (byte-identical; datastream embeds **070701 newc cpio at offset 512** —
  the Amix format) → `pkgadd -R` fakeroot → queries → `pkgrm`.
- **DB-write compatibility confirmed byte-for-byte.** The `contents` records Heirloom writes match
  the Amix factory grammar field-for-field per ftype (f/e/d/s tested). It *is* the same database
  code lineage — coexistence with the live `/var/sadm`, no migration.
- **Rigorously C89.** Zero `//` comments, zero mixed declarations under
  `-Wdeclaration-after-statement`, zero inline; exactly **one** C99 construct in the built set (a
  never-invoked variadic macro in `libspmizones/spmizones_api.h:225` that gcc 2.7's cpp would still
  reject — 1-line fix). 68k-safe: no endianness code, ILP32-clean, sparc32 heritage.
- **The OpenSSL "requirement" is gone.** Proven kit: 17 stub headers + a 32-line `nokeystore.c`
  (`research/heirloom/de-openssl/`) — builds and passes the lifecycle with zero OpenSSL. The
  SSLeay-licensed `p12lib.c/h` is never linked and can be deleted outright.
- **The porting bill is short and bounded:** ~700–800 lines of new code, of which ~500 is a
  vendored public-domain C89 `snprintf`/`vsnprintf` (needs C99 return semantics + `%lld` — the
  probe idiom `vsnprintf(bfr, 1, …)` is used); an LFS64→plain mapping (`#define stat64 stat` etc.,
  12 files, **plus `O_LARGEFILE 0` — 6 uses the first census missed**); `strcasecmp`, `fnmatch`
  (2 files), `libintl.h` identity stubs (~100 files unblocked), tiny wchar fallback; cpio `-D`
  flag dropped at **three** sites (`dstream.c:499,673,720` — verifier caught the third; `-icdumD`
  breaks any non-Solaris cpio, proven); `mk.config.amix` is a single file (the build system has
  **no** target machinery — makefiles are literally `cat mk.config Makefile.mk`; CC isn't even
  set); `scriptvfy.l` pre-generated with host flex (verified gnu89-clean; only pkgchk/pkgmk need
  it).
- **Estimated effort: 2–4 part-time weeks** to bench-tested core tools; binaries ~100–300 KB each
  on m68k, ~1.5–2 MB for the full suite. (gcc 2.7.2.3 itself is the one thing no host test can
  exercise — bench-dependent.)

## The new blockers: the VERSION trio ✅ (matters more than the space bug)

All 31 Amix factory packages have **no `VERSION`** in their pkginfo files — and this 2007-Solaris
lineage *requires* it in three places:

1. **`pkginfo` listing aborts on the factory DB**: `report()` demands NAME/ARCH/VERSION/CATEGORY
   non-empty and kills the whole listing — `ERROR: pkginfo file is corrupt or missing`
   (`pkgcmds/pkginfo/pkginfo.c:369-376`). So unpatched Heirloom `pkginfo` is *worse* on the
   factory DB than stock.
2. **`pkgadd` refuses VERSION-less packages** (`pkginstall/pkgenv.c:115-118`) — factory media
   can't be reinstalled through it.
3. **`pkginstall` SEGFAULTS on upgrade-over-VERSION-less** (`getinst.c:120-123`, NULL `strcmp`) —
   the exact "upgrade a factory package" flow crashes; and the crash is **silent at the pkgadd
   level** (child dies, pkgadd prints nothing, rc=1) — an unexplained no-op to the user.

`pkgrm` and `pkgparam` on VERSION-less packages work fine ✅. Fixes are trivial either way: three
<10-line C89 patches, **or** a one-time DB migration appending `VERSION=` to the 31 factory
pkginfo files (expected invisible to stock tools since pkginfo is a tolerant param soup — **BENCH**
verify once). The migration also fits our catalog design, which wants versions to exist anyway.

## Other notes worth knowing

- **Base on aflat HEAD, not the 070227 tarball.** aflat's import is Gunnar's **2009 CVS state
  (pkgtools 1.12)** — strictly newer than the 070227 release: adds flex support in `scriptvfy.l`,
  `libadm/getopt.c`, valtools + 13 man pages, a contents-merge `'?'` owner/group fix, and libpkgdb
  (vendored SQLite) already delinked. Then revert exactly two CentOS hacks (the hardcoded RedHat
  include in `libadm/Makefile.mk:2`, the `-m32` flags in mk.config) — and note aflat fixed the
  cpio `-D` only on the *write* side; the read side is still broken (our 1-line fix is validated).
- **Immediate zero-code win:** `man/` ships the complete CDDL-licensed SVR4 packaging man set
  (pkgadd.1m … pkginfo.5, pkgmap.5, prototype.5, depend.5) — Amix has **no** pkg man pages at all.
  Redistributable standalone regardless of the port decision.
- **Honest subset math** (from linker maps, `research/heirloom/linksets/`): `removef` alone = the
  installf binary, 56 files / 21.7 kLOC / ~150 KB — genuinely cheap. But `pkgask` = pkgadd +
  the `pkginstall` helper it execs → the "missing tools" build is really **3 binaries / 59.4 kLOC**.
  Full replacement suite = 135 files / 75.9 kLOC / ~2 MB.
- **Deployment landmines** (all avoidable): stock `make install` would overwrite
  `/usr/sadm/install/bin` (where stock SVR4.0 keeps *its* backends) and the factory
  `/var/sadm/install/admin/default` — build with a parallel `SADMDIR` and never install the
  Solaris-style admin default; `pkginstall` **writes into a string literal** if
  `/usr/sadm/install/scripts` is missing (SIGSEGV — pre-create it); `pkgremove` hard-requires
  `/var/sadm/pkg/<pkg>/install/` to exist (**BENCH**: check all 31; `mkdir` fixes).
- **Heirloom appends a `# Last modified by …` comment trailer to `contents` on every write.** Its
  own parser skips `#` lines; **whether stock 1992 srchcfile does is the single most important
  bench test** before mixing toolsets on one DB — if stock chokes, one Heirloom write makes the DB
  unreadable by stock tools (trailer suppression is a trivial patch if so).
- **Latent bugs to patch while in there** (this codebase is sprintf-into-fixed-buffer style):
  `libadm/pkginfo.c:285` `char path[128]` overflows on `-R` prefixes >~105 chars (silent stack
  smash on Amix — no fortify); `reperr()` 1-byte static overflow aborts long `pkgchk` runs;
  a double-free in the datastream error path; `pkgops.c:1354` pointer-vs-char assert typo.
- **Benign/neutral:** admin(4) keywords are a superset (unknown ones only warn; all-`ask` Amix
  default file works ✅); no ARCH-vs-uname gate anywhere (ARCH=Amiga never checked against uname);
  CAS scripts are bundled and Bourne-clean (`${var:-}` only — **BENCH** for the 1992 sh), missing
  CAS falls back to built-in copy ✅; datastream header/toc byte-compatible, no SIGNATURE member
  ever emitted in the non-keystore build ✅.
- **License:** 242-ish CDDL files + 1 shipping Caldera-BSD header (`libadm/regexp.h`); the only
  SSLeay files (p12lib) are deletable; ~20 small files (Gunnar's shims, build files) carry no
  license text — note in the repo's licensing README. Public repo must carry both LICENSE files
  and keep CDDL headers intact. Clean for our boundary — this is the open OpenSolaris code.

## Bench checklist (ordered; decides the remaining unknowns)

1. Stock tools' tolerance of `#` comment lines in `contents` (append one to a copy; run stock
   `pkginfo -l`) — decides the trailer patch.
2. `ls -ld /var/sadm/pkg/*/install` — pkgremove's hard requirement.
3. Native cpio probe: `-icdum -C 512` accepted; `-oc` emits 070701; Heirloom↔stock datastream
   cross-read.
4. Add `VERSION=` to one factory pkginfo copy → stock `pkginfo -l`/`pkgrm` still fine?
5. Run the contents harness (host-side) against the **real** 27k-line contents file — enumerate
   *all* bad records, old-style lines, `=`-in-name paths (the parser silently mis-splits those 🟡).
6. First cross-built binaries: `pkginfo`/`pkgparam`/`pkgtrans` (read-only set) against a COPY of
   `/var/sadm`; then the writing set; request/CAS scripts under the 1992 `/bin/sh`.

## Verdict

**Adopt-with-patch-set, in the engine role.** Heirloom is exactly what we hoped: the genuine SVR4
implementation, C89, byte-compatible with the live DB, buildable, with the missing
`removef`/`pkgask` and the man pages — and now with a validated fix for the very bug that broke
Amix packaging, which the stock binaries can never receive. It is *not* a remote package manager
(the catalog client remains our Phase-1 build), and it is *not* a drop-in: the known patch set is
~6 items (tolerant parser 36 lines; VERSION trio <30 lines or a 31-file DB migration; cpio `-D` ×3;
trailer decision; plus the buffer-bug hygiene), all small, all identified, most already written and
validated in `research/heirloom/`. Effort to bench-tested core tools: 2–4 part-time weeks, gated
only by the gcc 2.7.2.3 cross build and the bench checklist above.

## Sources / provenance

Dive run 2026-07-04 on the aflat clone (HEAD bfc8d02; history unshallowed; pristine 070227
SourceForge tarball diffed). Built trees, harnesses, fake-root fixtures and full per-claim
verification (CONFIRMED/REFUTED + file:line) were digested outside this tree; durable artifacts
copied to `../research/heirloom/`.
