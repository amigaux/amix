# AMIX-PORT.md — heirloom-pkgtools on Amiga Unix (Amix 2.1c, SVR4.0 m68k)

Port log and inventory for the cross build of this vendored
heirloom-pkgtools tree (aflat HEAD, pkgtools 1.12; `libpkgdb/` and
`libpkg/p12lib.[ch]` were deleted before vendoring).  Companion to
`../docs/design.md` §1 and `../docs/heirloom-pkgtools-dive.md`; validated
artifacts reused from `../research/heirloom/`.

## Status: SHIPPED (v1.1) — the heirloom engine is apkg's default

Bench-verified end-to-end 2026-07-05: full install chain + removals on
the live 28k-record DB through /usr/apkg/bin/pkgadd + pkgrm; eleven
root causes found and fixed across the campaign.  The detailed round
history is preserved further below ("Change inventory" onward); this
table is the executive summary.

| # | Root cause (bench-verified) | Fix (where) |
|---|---|---|
| 1 | Toolchain wrapper: gcc 2.7 switch dispatch assumes `.swbeg` = 4 bytes, GNU as emits 0 — every switch case entered 4 bytes late | corrected slurp-mode `.swbeg`→`.long` rule in `amix-cc` (the installed wrapper's own rule eats the trailing newline — upstreaming note below); dispatch invariant gated in build-amix.sh |
| 2 | Wrapper misses FLOAT compares: `fcmp` immediates rejected, reg-reg sense-inverted; reg-reg float ops need `.x` size | `amix-cc` fixups 1+2 (fcmp swap, `.x` rewrite) |
| 3 | MNTTAB/VFSTAB pointed at Linux paths (`/etc/mtab`); Amix mnttab is TEXT, not the sysroot header's binary format | `hdrs/sys/{mnttab,mntent,vfstab}.h` `__svr4__` branches; text `_getmntent` in mntinfo.c (validated against live bytes) |
| 4 | Native Amix cpio consumes CONCATENATED archives to EOF — datastream position destroyed after the first member | `ds_scan_cpio_archive()` newc boundary scanner + `esystem_bounded()` pipe-fed exact windows; `ds_skip` = pure lseek (dstream.c/runcmd.c, both platforms) |
| 5 | `ocfile()` preallocates contents+32MB (`CONTENTS_DELTA`) — instant ENOMEM under the 16MB soft data limit | proportional halving ladder (max(1MB, min(8MB, st_size)) → 512KB floor) + `amix_raise_rlimits()` soft→hard (bench: hard = unlimited) |
| 6 | `vfpSetSize()` corrupts `_vfpSize` on allocation failure → next smaller request "succeeds" with a NULL buffer → SIGSEGV | restore size on both failure branches (vfpops.c) |
| 7 | `srchcfile()` pinfo chains leaked per record over 28k-record scans (delmap/pkginfo reuse one cfent) → OOM "no memory for package information" | free non-matching records' chains (delmap.c, pkginfo.c); raw `exit(99)` → `quit(99)` (unlockinst now runs) |
| 8 | Lock lifecycle: leaked 20s alarms (lockinst/pkgWlock), unverified clean-completion record, wedged-lockfile hangs | `alarm(0)` on exit, verified/truncating unlockinst, unlink-and-retry recovery in both lock layers |
| 9 | `srchcfile()` skipped-range copy drops the final newline when the last line is a real record (`_vfpCurr` clamp) → records SPLICED on merge | `lastPos = px+1` fix (srchcfile.c); the tolerant-parsed spaced record itself is preserved verbatim |
| 10 | Inherited `SIGCHLD=SIG_IGN` (survives exec) makes every `waitpid()` fail ECHILD → all spawns "fail" | SIGCHLD reset to SIG_DFL in all spawn primitives (runcmd.c, pkgexecv.c) |
| 11 | **The flip-decider**: first `getpwnam()` SIGSEGVs inside the Amix libc passwd machinery (`_libc_malloc` fn-ptr internals; group path survives) | compat defines `getpwnam/getpwuid/getgrnam/getgrgid` as direct text parsers (preempt libc for all our objects); regression-tested against the REAL box `/etc/passwd`+`/etc/group` (compat/tests/, runs in every build-host.sh) |
| 12 | (2026-10-05, emulated LC060) gcc 2.7.2.3 emits the 64-bit-product `muls.l/mulu.l <ea>,%dH:%dL` for every divide/modulo by a constant and for `(u64)a*b`; the 68060 does not implement it (vector 61, Amix SIGKILLs). The published 1.12.0 engine (2026-07-05, pre-`984192a`) also carried 64-bit-dividend `divs.l` from the SGS `tdivs` mis-assembly — `installf -f` died in `HASH()` | The toolchain wrapper's `fix_asm` (gcc-cross-amix `2ab2b22`, rule 11; `amix-cc` runs it via the extracted `fix_asm`) turns each 64-bit multiply into an equivalent 16x16 `mulu.w` sequence: same `%dH:%dL`, every other register and X preserved, N/Z/V/C as the hardware leaves them. `amix-cc` keeps only the gate: a leftover 64-bit mul/div/`tdiv` fails the compile. `tools/repo/scan060.py` gates the APKG/APKGENG mints and the static build. APKGENG 1.12.2. (1.12.1 used an `amix-cc`-local copy of the rewrite that did **not** preserve X, contrary to what this row said: same results, X clobbered. Removed; 1.12.1 minted, never published, superseded.) NOTES.md 2026-10-05 |
| 13 | (2026-10-26, found on the box by the installer) `removef PKG -` (stdin path-list form) kept fgets' trailing newline on every line, so no path matched contents and nothing was removed, rc 0, silently. Upstream defect (OpenSolaris/heirloom); the argument form and installf's stdin form (strtok) were fine. Stock Amix ships no `removef` at all | `pkgcmds/installf/removef.c`: take the first `" \t\n"` token per line as installf does, skip blank lines. Host regression `tests/removef-stdin/run.sh` (2 of 3 paths via stdin, exactly those removed; fails on the unfixed source), run by build-host.sh step 6. APKGENG 1.12.4. NOTES.md 2026-10-26 |
| 14 | (2026-10-31, T-56 D1) A roll is not reproducible: pkgmap's modtime column is each file's mtime, the spool's modes follow the umask, each newc header carries the spool's inode and device, the builder's uid/gid and the wall clock, and members come in the filesystem's directory order; a default PSTAMP names the host | With `SOURCE_DATE_EPOCH` set (unset: as before; not a number: refused): `pkgmk` writes the epoch as every pkgmap modtime and default date (UTC; a default PSTAMP without the host's name) and sets every spool object to pkgmap's mode (0755/0644 when unlisted) and the epoch (`pkgcmds/pkgmk/main.c`); `pkgtrans -s` lists each archive's members through `LC_ALL=C sort` and rewrites every newc header in place: ino renumbered with hard links kept, uid/gid/dev 0, mtime the epoch, a directory's nlink 2 + its subdirectories (`libpkg/pkgtrans.c`, new `libpkg/dsepoch.c`). The bytes are build/pkg's dsroll path's (`dsnorm.py` finds nothing to change). Host test `tests/repro-roll/run.sh`, build-host.sh step 7 |

Plus hygiene fixed along the way: fpkgparam stack-underflow (empty
admin values), canonize/canonize_name overlapping strcpy (7 sites),
`environ=NULL` killing DS_DEBUG mid-run, pkginfo VERSION relaxation,
tolerant contents parser, cpio `-D` removal, de-OpenSSL, and the full
compat/ layer for gcc 2.7.2.3 + SVR4.0 libc.

### Open follow-ups (optional, non-blocking)
0. **`pkgadd -R <altroot>` SIGSEGV — RESOLVED 2026-07-20: a toolchain
   modulo miscompile in `nhash.c` `HASH()` (NOT an averify/clgrnam
   bug), now FIXED in the toolchain and VERIFIED on the box.**
   - **RESOLUTION (2026-07-20).** The `tdivs.l/tdivu.l` remainder-divide
     fixup shipped in the `m68k-cbm-sysv4-gcc` wrapper's `fix_asm`
     (gcc-cross-amix `984192a`): the SGS `tdivs`/`tdivu` mnemonics are
     rewritten to `divsl`/`divul`, which GNU as 2.8.1 encodes as the
     32-bit-dividend form (SIZE bit clear) with the remainder register
     intact.  The heirloom engine was rebuilt with the fixed toolchain
     (`build-amix.sh`; `amix-cc` picks up the fixup by extracting
     `fix_asm` at runtime) and re-deployed to `/usr/apkg` on the box.
     `HASH`'s divide now disassembles as `divsll %fp@(16),%d2,%d1`
     (ext word `1802` — SIZE=0, quotient %d1, remainder %d2) followed by
     `mov.l %d2,%d0`; a scan of the whole rebuilt engine finds only
     `divsll`/`divull` (4 + 6) and zero mis-assembled 64-bit
     `divsl`/`divul`.  On-box acceptance (`tests/altroot-repro/task0a.sh`
     plus a plain-×4 / seeded battery; running engine `pkgadd` sum -r
     15636, `pkginstall` 34368): plain empty-root `pkgadd -R` **4/4
     rc=0, zero cores** (was rc=1 + a 1 MB core every run); the full
     5-config task0a table is rc=0 across the board (`empty-plain` and
     `empty-ZZQQ1` flipped from crash to success); the DS_DEBUG arm and a
     seeded (`etc/passwd`+`etc/group`) alt-root are also rc=0; the
     alt-root install is genuine ("Installation of <APKG> was
     successful.", `<root>/var/sadm/pkg/APKG/*` + 13 contents records +
     `<root>/usr/apkg/bin/apkg`).  Real-system (non-`-R`) installs were
     already unaffected.  The `MERGPATH_OPT` `-O0` forcing of
     nhash/ncgrpw/verify (item 1) was never the cure and can be unwound.
   - **Mechanism.** `HASH()` `return (hv % hsz)` compiles (gcc.real
     `-S`) to the correct SGS `tdivs.l 12(%fp),%d2:%d1` (remainder→d2,
     quotient→d1) + `mov.l %d2,%d0`, but GNU as 2.8.1 mis-assembles it
     to `divs.l 12(%fp),%d1` — the **remainder register %d2 is
     dropped** — so `HASH` returns the stale `%d2` (garbage, often
     negative).  `add_cache()` then indexes `cp->bp[negative]`, a wild
     `Bucket *` outside the bucket array (read-only/foreign memory),
     and stores through it → SIGSEGV.  The THIRD
     gcc-2.7.2.3/binutils-2.8.1 anomaly after `.swbeg` and `fcmp`.
     Opt-level-independent: `%` wrong at -O0 AND -O (so the
     MERGPATH_OPT `-O0`-forcing of nhash/ncgrpw/verify never could fix
     it); `/` wrong at -O0, correct at -O.
   - **How found.** On-box: the crash DOES drop a core, at
     `<root>/var/sadm/install/core` (pkginstall's cwd — the earlier
     "silent, no core" looked in `/tmp`).  `adb` on the unstripped
     pkginstall named `add_cache` (nhash.c); the Cache/Item dump showed
     key=`sys\0`, keyl=4, hsz=151 (HASH must be 49) yet the bucket
     index was −106.  `mod_prog.c` proves `351 % 151` returns garbage
     on the box.  Reproduces on an EMPTY alt-root (no
     `<root>/etc/group`), where `clgrnam()`/`dup_gr_ent()` — v15–v17's
     target — is never entered.
   - **Independent corroboration.** Per-region DS_DEBUG bisection
     (`tests/altroot-repro/`, `per-region-dsdebug.patch`): of
     MAIN/MNT/LOCK/MERG/ESYS/CGR/DS, only **CGR** (cgrnam family +
     averify) suppresses the crash (4/4), naming the same cgrnam→cache
     path.  The suppression is code-path perturbation, not env layout
     (an unrelated `ZZQQ=1` does NOT suppress) — a Heisenbug that masks
     the wild store; the crash is real without any instrumentation.
   - **The fix was a TOOLCHAIN change (DONE — gcc-cross-amix `984192a`):**
     the SGS `tdivs.l/tdivu.l ea,Dr:Dq` remainder-divide is rewritten in
     the `m68k-cbm-sysv4-gcc` `fix_asm` (and picked up by `amix-cc` via
     runtime extraction) so GNU as keeps the remainder register (same
     class as the `.swbeg`/`fcmp` fixups).  Full box evidence + harnesses
     in `tests/altroot-repro/`; see the RESOLUTION note at the top of
     this item.
   Historical investigation (superseded by the above; kept for
   context — it localized to averify→cgrnam but mis-attributed the
   crash to the clgrnam/`dup_gr_ent` group path):
   - Root-caused a genuine latent defect and fixed it:
     `libpkg/ncgrpw.c` `dup_gr_ent()` built the duplicated member
     array `memp` but NEVER assigned `grp->gr_mem = memp` - the
     "duplicated" group kept `gr_mem` pointing at the volatile static
     storage of `getgrnam()`/`fgetgrent()` (clobbered by the next
     lookup) and leaked `memp`.  Now assigned; the cache holds a
     stable deep copy.
   - NOT yet confirmed as THE crash: the full -R flow is
     host-unreproducible (glibc and the compat shim both complete it
     cleanly).  The compat `fgetpwent`/`fgetgrent` parsers were
     fuzzed under ASAN (empty/malformed/no-newline/>64-member/
     >1024-char files) - all clean; `dup_gr_ent` + the shim was
     driven standalone against the real box fixtures - clean.  The
     one real asymmetry: the box's `bin::2:bin,daemon` exercises the
     member-copy path (2 members) that the host's memberless `bin`
     skips - now covered by the `gr_mem = memp` fix.
   - v16 box run (gr_mem fix + finer markers, `strings`-confirmed
     compiled in): averify prints its own `group check` line then
     SIGSEGV with **none** of the cgrnam-internal markers - so the
     crash is the averify->cgrnam handoff, BEFORE cgrnam's first
     statement.  Since `ainfo->mode` is read successfully just above
     (the `mode check`->`group check` markers both print), `ainfo`
     itself is a valid pointer and `ainfo->group` is a valid fixed
     ATRSIZ+1 array - so the fault is cgrnam's `strlen(nam)` (or the
     enter-marker `%s`) running off a **non-NUL-terminated group
     string** in that array (the `strcmp(group, BADGROUP)` just before
     only reads 1 byte, so it survives).
   - v17 instrumentation + guard shipped:
     * a bounded, read-only dump in averify prints `ainfo`/`&group`/
       `&owner` addresses and the raw ATRSIZ+1 bytes of both fields
       with their first-NUL position (safe: fixed arrays in a valid
       struct) - one box -R run shows whether the box's group field is
       a clean `bin\0...` (firstNUL=3, as on host) or unterminated
       garbage, and lets fix=0 (works) vs fix=1 (-R crash) be compared
       directly;
     * a defensive guard: the group/owner lookups now run from
       guaranteed-terminated local copies (`gnam`/`onam`, memcpy+force
       terminate; the `reperr` report args too), so a non-terminated
       field degrades a wild pointer walk into a clean "bad group/owner"
       warning instead of a SIGSEGV.  Does NOT write into `*ainfo`
       (which may be the corrupted object).  Host `-R` games install
       stays rc=0; the field dump shows clean `bin`/`games` on host, so
       the corruption is Amix-runtime-specific and the next box run's
       dump will localize its source (pkgmap parse vs -R relocation).
   - **v18 (2026-07-19) - host reproduction ATTEMPTED and FAILED, but
     the "host-unreproducible" claim is now explained and bounded.**
     Harness: `tests/host-altroot/` (self-contained, repeatable; see
     its README for the full evidence).  Four separate reasons the
     host had never executed the suspect code were removed at once:
     `<root>/etc/group` seeded (without it `clgrnam()` `fopen` fails
     and `clgrnam -> dup_gr_ent` NEVER RUNS - and
     `tools/repo/repackage-stock.py` `install_test()` does exactly
     that, `os.makedirs` straight into `pkgadd -R`, which alone
     accounts for every previous vacuous host run); real box
     passwd/group fixtures with multi-member groups; the box's own
     compat `fgetgrent`/`getgrnam` parsers `LD_PRELOAD`ed in place of
     glibc's; and the v17 `gnam`/`onam` guard compiled out
     (`NOGUARD=1` -> `-DAMIX_NO_ATTR_GUARD`).  Under ASan+UBSan
     (`SANITIZE=1`, new in `build-host.sh`/`mk.config.host`):
     **3588 `averify` `fix=1` entries and 66 `dup_gr_ent` calls per
     config across 5 stock packages, 30 multi-member, ZERO findings.**
     Both `-R` shapes were run, because nothing in this repo records
     whether the box's `-R` target had an `/etc/group` at all - if it
     did not, the box never entered `clgrnam()` and v15-v17 were
     chasing the wrong function.
   - **Two results that constrain the next round more than the
     negative does:**
     * **ASan cannot see this bug class here.**  The hypothesised
       overflow (`strcpy(ainfo->group, grp->gr_name)` past
       `group[65]` into `major`/`minor`) is *intra-object* - past a
       member but still inside `struct cfent`.  ASan puts no redzones
       between struct members, so a clean ASan run does NOT exonerate
       that mechanism.  Verified by fault injection: 65 non-NUL bytes
       written into `ainfo->group` produced no ASan finding at all.
     * **Host padding arrested the walk.**  That same injected fault
       did not SIGSEGV either - `strlen` returned exactly 65 and
       stopped in padding.  Measured host layout: `group` @77 (ends
       142), `major` @144 - **2 zero pad bytes** arrest the walk
       before `BADMAJOR`.
   - **v18a - the padding-asymmetry hypothesis is REFUTED (measured).**
     v18 *inferred* that gcc/m68k 2-aligns 32-bit scalars, putting
     `major` at 138 with zero padding, and concluded the host "cannot
     reproduce this by construction".  That was wrong.  Measured with
     the real toolchain (`m68k-cbm-sysv4-gcc`, GCC 2.7.2.3, target
     sysroot, heirloom's exact `struct ainfo`, `offsetof` emitted as
     initialized data): `sizeof`=148, `owner`@8, `group`@73 (ends
     138), `major`@140, `minor`@144, **PAD=2**.  Stable across
     `-O2`/`-O0`/bare/`-O`; only `-fpack-struct` gives PAD=0 (146,
     `major`@138), and `mk.config.amix:97` is `CFLAGS=-O` with
     `-fpack-struct` used nowhere in the tree - so **PAD=2 ships**.
     The inference missed because `major_t`/`minor_t` are `ulong_t`
     (sysroot `sys/types.h:60-61`) and this target 4-aligns 4-byte
     scalars, so 138 rounds up to 140.  **m68k and host have the SAME
     2 pad bytes** - there is no layout asymmetry, and "PAD=0 ->
     straight into 8x 0xFF" is not the mechanism on either platform.
     Layout is settled; do not re-measure it on the box.
   - **The padding-CONTENTS successor is also unsupported (static
     analysis only, not disproved on hardware).**  The `cfent` that
     `averify(fix=1)` sees on an install arrives via
     `pkginstall/instvol.c` as `ept = &(extlist[i]->cf_ent)`, and
     `libinst/pkgobjmap.c` `pkgobjmap()` does
     `memset(&map_entry, '\000', sizeof (struct cfent))` at the top of
     EVERY loop iteration and then
     `memcpy(ept, &map_entry, sizeof (struct cfent))` - a whole-struct
     copy that carries the zeroed padding into the arena slot, so the
     padding is deterministically zero regardless of how the arena was
     allocated.  Every field writer on that path is bounded and always
     terminates: `getstrvfp(..., ATRSIZ, ...)` (gpkgmap.c:832-841),
     `strlcpy` (gpkgmap.c:614-615), `getstr(..., sizeof(field), ...)`
     (srchcfile.c:1079-1081); the one unbounded `strcpy` on the path
     (`pkgdbmerg.c:1248,1256`) takes its source from `srchcfile`'s
     bounded `getstr`, so it is safe in practice.  If the box's
     padding really is non-zero, something OUTSIDE this path put it
     there - naming that is the open question.
   - **Latent unbounded writers found while tracing** (real defects,
     none can fire on the failing path - do not conflate with the
     crash): `libpkg/mappath.c:206` `mapvar()` is a completely
     unbounded in-place `getenv()` expansion
     (`while (*token) *varname++ = *token++;`) into a `char[65]`
     attribute field, reachable from `gpkgmap.c:850,857` and
     `pkgchk/ckentry.c:99,100` whenever a pkgmap owner/group is
     `$VAR` - but **0 of 28,919** pkgmap entries across all 27
     repackaged stock packages are parametric; `verify.c:893,940`
     `strcpy(ainfo->group, grp->gr_name)` unbounded from the group
     file (`setval`/`BADGROUP` branch only); `procmap.c:393,399`
     `strcpy` field->field; `pkgadm_special.c:299,300`
     `strncpy(dst, src, ATRSIZ+1)` into `char[65]` can leave it
     unterminated (not shipped - `pkgadm` is in neither build's
     SUBDIRS); `pkgdbmerg.c:772,775` unbounded but inside `#if 0`.
   - **Next box actions** (revised): (a) **record what the failing
     `-R` target actually contained**, specifically whether
     `<root>/etc/group` existed - nothing in this repo documents it,
     and with no `<root>/etc/group` `clgrnam()` returns NULL
     immediately, meaning v15-v17 instrumented a function the box
     never entered (it also decides whether a contents DB was present
     to drive pkgdbmerg); (b) dump the 2 padding bytes at
     `ainfo+138..139` next to the existing `group bytes=[...]
     firstNUL=` output for the faulting entry - non-zero padding
     supports the contents hypothesis, zero kills it; (c) capture that
     `group bytes=` dump itself, which separates "corrupt field" from
     "corrupt `ainfo` pointer".

1. **MERGPATH_OPT -O0 forcing — UNWOUND 2026-07-21 (was: cautious -O
   bisect).** pkgdbmerg/eptstat/listmgr/putcfile/verify/ncgrpw/nhash/
   snprintf were -O0-forced on Amix (MERGPATH_OPT/PKGDBMERG_OPT empty)
   as a codegen precaution from the v13/v14 rounds; the earlier note
   here blamed a "libc-side" fault and prescribed a per-file -O bisect.
   Item 0 settled it: the crash was NOT an -O miscompilation but the
   toolchain `tdivs.l/tdivu.l` remainder-divide defect (nhash.c HASH()),
   which is opt-level-INDEPENDENT — so -O0 never could have helped —
   now fixed in the `m68k-cbm-sysv4-gcc` wrapper (gcc-cross-amix
   `984192a`).  The forcing is therefore retired in one edit:
   `mk.config.amix` sets `MERGPATH_OPT=$(CFLAGS)` (mirroring
   mk.config.host:58) and all eight files build at -O.  **Re-verified on
   the box at -O** (rebuilt engine deployed to `/usr/apkg`; pre-unwind
   engine backed up to `/tmp/apkg-bak-preunwind`): plain empty-root
   `pkgadd -R` **4/4 rc=0, zero core**; full `task0a` battery **5/5
   rc=0** (empty-plain and empty-ZZQQ1 stay flipped from crash);
   genuine alt-root install ("Installation of <APKG> was successful.",
   13 APKG contents records, `<root>/usr/apkg/bin/apkg` 59202 B).
   objdump: nhash `HASH()` emits `divsll %d2,%d0,%d1` (ext word `1800`,
   SIZE=0, remainder direct in the `%d0` return reg); a whole-engine
   scan finds only `divsll`/`divull` and **zero** mis-assembled 64-bit
   `divsl`/`divul`.  snprintf `convert()`'s 64-bit `value % base` came
   out as a `__umoddi3` libcall (from `libamix.a`/`di_ops.c`, immune to
   the defect); its constant divides strength-reduce to `mulsl #magic`+
   `asr`.  The per-file rules and the MERGPATH_OPT/PKGDBMERG_OPT alias
   are kept only as a documented opt-level hook.
2. **apkg lock-clear workaround removal** (apkg side, not this tree):
   unlockinst/pkgWlock recovery makes it redundant — verify one bench
   cycle without it.
3. **Upstreaming to gcc-cross-amix**: the installed wrapper's
   `.swbeg` sed rule eats the record's trailing newline (needs the
   slurp-mode `/mg` form or `[ \t]*$`), and fix_asm lacks the fcmp
   swap + reg-reg `.x` rewrite (see "amix-cc" and the audit notes in
   the round history).  `amix-cc` masks both for this tree only.

## Results

**Amix cross build** (`./build-amix.sh`) — all priority-1/2/3 binaries
build and link with zero errors, m68k SVR4 ELF, `DT_NEEDED` =
`/usr/lib/libc.so.1` only (verified with `objdump -p`; the dangling-
DT_NEEDED SIGKILL trap does not apply).  Stripped sizes:

| binary | KB | | binary | KB |
|---|---|---|---|---|
| pkginfo | 155 | | pkgchk | 207 |
| pkgparam | 142 | | pkgmk | 175 |
| pkgtrans | 118 | | pkgproto | 51 |
| pkgadd (+pkgask link) | 210 | | pkginstall (sadm helper) | 335 |
| pkgrm | 176 | | pkgremove (sadm helper) | 237 |
| installf (+removef link) | 145 | | | |

Output: `build-amix/bin/` (user tools, deploy to `/usr/apkg/bin`) and
`build-amix/sadm-helpers/` (pkginstall/pkgremove, deploy to
`/usr/apkg/sadm/install/bin` — the compiled-in `SADMDIR` is the
**parallel** `/usr/apkg/sadm`; stock `/usr/sadm` is never touched).
`VSADMDIR=/var/sadm` (shared DB), `BINDIR=/usr/bin` (compiled-in exec
path for the native cpio/rm/rmdir/nawk).

**Host build** (`./build-host.sh`) — same tree, gcc -std=gnu89, all 11
binaries; smoke-tested end to end: `pkgmk` toy package → `pkgtrans`
datastream → **member magic 070701 (newc) verified at offset 512**
(stock Amix pkgadd accepts only newc; GNU cpio's `-oc` would emit odc,
so the compiled-in BINDIR points at `build-host/bindir/cpio`, the
SVR4→GNU translating wrapper in `hostshims/cpio`) → `pkginfo -d` →
stream→dir round trip byte-identical → **patched-behavior smoke**: the
real corrupt factory `contents` record (space in pathname) parses, and
a VERSION-less factory-style package lists as `VERSION: (none)`.

## How to build

```sh
# Amix (m68k) — sources gcc-cross-amix env.sh itself if needed:
./build-amix.sh          # override toolchain env: AMIX_CROSS_ENV=...

# Linux host:
./build-host.sh
```

Both scripts replicate the stock build scheme — each subdirectory's
`Makefile` is generated as `{TOPDIR=<abs>; mk.config.{amix,host};
<dir>/Makefile.mk}` concatenated — then clean **all** dirs, build all
dirs (two passes: the pkgcmds `clean` targets also delete
`../../version/version.o`), collect and verify binaries.  The two
builds share the tree and cannot run interleaved; their outputs
(`build-amix/`, `build-host/`) coexist.

## Static-link variant — `build-amix-static.sh` (Installer-NG W5.0)

`./build-amix-static.sh` emits the **CD-resident installer engine
subset** as **fully static** m68k SVR4 ELF executables:

```
build-amix-static/bin/          apkg  pkgadd  pkgtrans  pkginfo  pkgchk
                                contents-fsck
build-amix-static/sadm-helpers/ pkginstall
```

(`apkg` is the **FILE+RAW-only** static variant — `-DAPKG_NO_HTTP`, `http.c`
excluded; see the apkg paragraph below.  `contents-fsck` was added as of
**W6.4a** so the installer driver can run a contents-DB integrity **check**
as an install step on the freshly-installed target — see the
contents-fsck paragraph below.)

**Why static (E4 probe, 2026-07-22).** The stock install miniroot
(`amix-installng .../amix_21_root.adf`) cannot host the dynamically-
linked engine: it carries **no `libnsl.so`**, and its `libc.so.1` is a
**different build** from the golden 2.1c one — and on Amix `libc.so.1`
**is** the `PT_INTERP` (the runtime linker is embedded in libc), so
`LD_LIBRARY_PATH` provably cannot redirect it.  Static linking bundles
everything, removes the libc-build skew, and drops `PT_INTERP`
entirely.

**Mechanism — an *additional* variant, the shared build is untouched.**
The compile step is identical to `build-amix.sh`; only the **link**
differs.  So `build-amix-static.sh` runs `build-amix.sh` to produce the
compiled objects, the four heirloom archives and `libamix.a`, then
**re-links** the CD subset with `m68k-cbm-sysv4-ld` directly (the
ld-direct pattern `src/apkg` already uses), swapping the shared libc for
the static `usr/ccs/lib/libc.a` and adding `values-Xt.o`.  `values-Xt.o`
defines `_lib_version` (the C library-mode global the compiler driver
normally injects): `libc.so.1` **exports** it so the shared build never
names it, but `libc.a` members only **reference** it, so a static link
must pull it in.  `-Xt` is the traditional SVR4.0 default library mode.
`build-amix/` and its shared outputs are **byte-unchanged** (verified by
md5 before/after a static run).  `SKIP_DYNAMIC=1` reuses an existing
`build-amix.sh` tree for fast iteration.

**Evidence per binary** (host `readelf` — ELF parsing is target-agnostic
— cross `objdump -p`; the cross toolchain ships no `readelf`):

| binary | ELF | type | PT_INTERP | DT_NEEDED | bytes (stripped) |
|---|---|---|---|---|---|
| apkg | m68k MSB SVR4 | `EXEC` | 0 | 0 (no dynamic section) | 46880 |
| pkgadd | m68k MSB SVR4 | `EXEC` | 0 | 0 (no dynamic section) | 266024 |
| pkgtrans | m68k MSB SVR4 | `EXEC` | 0 | 0 | 171604 |
| pkginfo | m68k MSB SVR4 | `EXEC` | 0 | 0 | 209316 |
| pkgchk | m68k MSB SVR4 | `EXEC` | 0 | 0 | 264308 |
| contents-fsck | m68k MSB SVR4 | `EXEC` | 0 | 0 | 29468 |
| pkginstall | m68k MSB SVR4 | `EXEC` | 0 | 0 | 399676 |

`apkg`'s extra proof (`nm` over the unstripped static link): **zero**
undefined symbols, and **none** of `setnetconfig`/`getnetconfig`/
`endnetconfig`/`gethostbyname`/`socket`/`http_get` present anywhere — the
socket/netconfig path is compiled out, not merely unresolved.

Static binaries are larger than the shared set (they inline the libc
members that were previously resolved from `libc.so.1`); CD space is a
non-issue at 285 MiB used of 650.  The `divsll`-only health check is
run over **our compiled objects** (the `.o` that feed the link, plus
`libamix`'s `di_ops`) — a whole-binary scan would false-positive on the
vendor `libc.a` members a static link legitimately pulls in (those carry
real 64-bit `divsl`/`divul`, pre-assembled by the original SGS
toolchain); our code is clean (`divsll`×3, `divull`×8, zero bare
`divsl`/`divul`).  The new `apkg` objects (under `build-amix-static/
obj-apkg/`, skipped by that find) are scanned separately: they carry no
64-bit divide helper at all (no modulo/`/` on a `long long` in the
FILE/RAW path), so zero `divsl`/`divul` **and** zero `divsll`/`divull`.
The `contents-fsck` object (under `build-amix-static/obj-cfsck/`, likewise
skipped by the find) is scanned the same way: it is a pure text parser
that does no division at all, so zero of both forms.

**`apkg` in the static set — the blocker and how it was resolved
(option 1, 2026-07-22).** The heirloom engine uses no sockets, so it
links fully static against `libc.a` alone.  `apkg` did **not**: its SVR4
`socket()` path (`libsocket.a`) transitively needs libnsl's
**netconfig(3N)** trio (`setnetconfig`/`getnetconfig`/`endnetconfig`) —
those three symbols were the *only* unresolved references in an
otherwise-complete static `apkg` link (everything else, incl.
`gethostbyname`, resolves in `libsocket.a` + `libc.a`).  **No static
`libnsl.a` exists anywhere in the Amix 2.1 distribution** (the install
tape ships `libnsl.so` only; the cross sysroot and the golden images
likewise).  So static linking alone did **not** free `apkg` from libnsl
the way it frees the engine.

**Chosen: option 1 — the STATIC `apkg` drops the HTTP backend.**
`src/apkg/source.c` already classifies the `repo=` string into
HTTP/FILE/RAW with **no heuristics**, so the clean cut was there: the
static variant compiles `-DAPKG_NO_HTTP` with `http.c` excluded from the
link, which removes the socket → netconfig dependency **entirely** — the
static `apkg` links against `libc.a` alone, exactly like the engine
(`nm`: zero undefined symbols, none of the netconfig trio / `gethostbyname`
/ `socket` present).  An `http://` repo handed to this build **fails
closed** at `source.c` `src_open` ("http: not available in the
static/install build …") — it is never misclassified as another backend
and never falls through.  FILE (`file:///path`) and RAW (`raw:<device>`)
— the only media a CD install uses — are **byte-for-byte** the shared
build's (the FILE/RAW code in `source.c` is outside the `#ifdef`;
host-side parity proven in `src/apkg/tests/nohttp-variant.sh`).  The
source seam is minimal: one `#ifdef APKG_NO_HTTP` around the `http://`
registration in `src_open`, and `#ifndef APKG_NO_HTTP` around the two
`SRC_HTTP` switch arms (`src_fetch`/`src_stage`) whose only content is
the `http_get` calls.  **Rationale in one line:** no static `libnsl.a`
exists, and the install miniroot has no network stack anyway, so HTTP is
dead weight on the CD — while the **dynamic** `apkg` (`src/apkg` `make
amix`, deployed to `/usr/apkg`) is UNAFFECTED and keeps full HTTP.

The two options NOT taken, recorded for the future:
2. **Static `netconfig(3N)` reader in `compat/`** (parse `/etc/netconfig`),
   following this tree's provide-what-libc-lacks pattern — **this is the
   path if a static+HTTP `apkg` is ever wanted**.  Retains HTTP; ~150
   lines C89; needs on-box socket validation.  Not needed for the CD
   installer (no network there), so deferred.
3. **Obtain a real static `libnsl.a`** — infeasible: Amix shipped libnsl
   shared-only; not on the tape, sysroot, or images, and no libnsl
   source is available.

**`contents-fsck` in the static set (W6.4a, 2026-07-23).**  Our own C89
contents(4) DB checker (`src/contents-fsck/contents-fsck.c`) is added to
the CD-resident set so the installer driver can run a **contents-DB
integrity check as an install step** on the freshly-installed target —
"contents-fsck-clean DB as an install step, not a nicety".  Unlike `apkg`
it needed **no** decision or source change: it is a single libc-only
source (static buffers, **no `malloc`**, no sockets, no libnsl), so it
links fully static exactly like the engine — `crt1`+`crti`+`values-Xt` +
the one object + `libc.a` + `crtn`, no heirloom libs.  It is compiled with
the **same** `m68k-cbm-sysv4-gcc` wrapper the engine set uses (so it
inherits the `.swbeg` + `tdivs` asm fixes), then `ld`-linked directly.
`nm -u` on the unstripped link is **empty** (zero undefined symbols).
This build is **independent of** the tool's own `src/contents-fsck`
Makefile `amix` target (which self-builds via `asmfix.pl`); both produce a
fully-static binary, but the CD set standardizes on the wrapper recipe.

**Installer invocation — CHECK-ONLY, fail-closed.**  The install-step form
is the tool's **default report mode** (no `-r`):

```
contents-fsck /a/var/sadm/install/contents        # /a = the freshly-installed root
```

Exit-status contract (from `contents-fsck.c`: `EXIT_CLEAN`/`EXIT_DIRTY`/
`EXIT_ERROR`):

| exit | meaning | installer driver action |
|---|---|---|
| **0** | DB verified **clean**, zero findings | proceed |
| **1** | findings (unparseable / spaced / sort / dup records) | **FAIL the install** |
| **2** | error (cannot open/read the file, bad usage) | **FAIL the install** |

The driver must treat **any non-zero** as fatal (fail closed): a fresh
install's contents DB is machine-generated by our own `pkgadd`/`pkginstall`
and **must** verify clean — a finding means the install is wrong, not that
the DB needs repairing.  Report mode **never modifies** the input.  The
repair modes (`-r`, and the strip form `-r -s`) stay a **post-migration
tool for the corrupt factory DB**, NOT an install step — the installer only
ever runs the check form above.

**W5.3 consumption note.** The Installer-NG **W5.3 ISO re-master** pulls
its CD-resident engine set from this tree —
`heirloom/build-amix-static/bin/{apkg,pkgadd,pkgtrans,pkginfo,pkgchk,contents-fsck}`
plus `heirloom/build-amix-static/sadm-helpers/pkginstall` — and places
`pkginstall` at `/install/bin/pkginstall` on the disc (mounted `/cdrom`
→ `/cdrom/install/bin/pkginstall`, the shim convention the miniroot's
`build-miniroot.sh` compiles in).  `apkg` joins that set as of
2026-07-22; the CD-side `apkg.conf` must point `repo=` at a `file://` or
`raw:` source (an `http://` repo would fail closed).  As of **METAL-FIX.3**
(2026-07-24) the static `apkg` is **46880 B**, `sum -r` **37448**, md5
`fbe2acc888980b2eef77feabb72915e9` (was 46464 B / `sum -r` 40275 before the
fix) — the re-master pulls it by name, so it consumes the rebuilt binary
directly (no pinned sum to bump on the installng side).  The change: the
child pkgadd's stdin is now redirected to `/dev/null` so a pkgadd that
prompts on an error path gets EOF and **aborts non-zero** instead of
hanging the install forever (`src/apkg/install.c` `run_cmd`); this is the
binary the RAW/metal install path (`install.sh` → `apkg install`) runs, so
rebuilding it is what carries the fail-fast onto the disc.  `contents-fsck`
joins as of **W6.4a** (2026-07-23): the re-master pulls
`build-amix-static/bin/contents-fsck` (static, 29468 B, `sum -r` 23366,
md5 `43684b68e8143af94a78f8bf194bd4b2`) onto the disc, and the installer
driver runs it **check-only** on the freshly-installed target
(`contents-fsck /a/var/sadm/install/contents`, non-zero → fail the
install; see the contents-fsck paragraph above).  On-box smoke of the
static `apkg` (the `http://` refusal, and a `file://`/`raw:` install
under the miniroot), and of the `contents-fsck` install-step check, is
owed to the follow-up installng wave — the host build + host tests are
green, but nothing here ran on the guest.  (The consumer-side convention
lives in `amix-installng`: `docs/miniroot.md`, `miniroot/miniroot.proto`,
`tools/build-miniroot.sh` — those must be updated to add `apkg` and
`contents-fsck` to the pulled set and to add the check-only install step.)

## Toolchain quirks (cross) and their workarounds

The `m68k-cbm-sysv4-gcc` driver is a **bash wrapper** around
`gcc.real -S` + asm fixups + `as`.  Five load-bearing consequences:

1. **`-I $AMIX_SYSROOT/usr/include` is force-prepended** before all
   user flags — and the real sysroot contains the stock SVR4.0 pkg
   headers (`pkgstrct.h`, `pkginfo.h`, `pkgdev.h`, `pkglocs.h`,
   `pkgtrans.h`, ...), which would shadow heirloom's `hdrs/` copies
   (different struct layouts!).  → `build-amix.sh` generates a
   **shadow sysroot** (`build-amix/sysroot`) that symlinks every real
   header EXCEPT any name heirloom provides in `hdrs/` or `hdrs/sys/`,
   and exports `AMIX_SYSROOT` pointing at it (usr/lib and usr/ccs pass
   through to the real sysroot; `AMIX_CRT_DIR` stays real).
2. **`-include` is not passed through** (unknown flags become ld
   flags), so `compat/amixcompat.h` cannot be force-included from the
   command line.  → the shadow sysroot's `stdio.h`, `stdlib.h`,
   `string.h`, `ctype.h` and `sys/types.h` are generated **wrapper
   headers** that chain to the real header and then include
   `compat/amixcompat.h`.  `sys/signal.h` is also wrapped, defining
   `_POSIX_SOURCE` for that one header only (see quirk 5).
3. **No libgcc.a exists** anywhere in the toolchain, but gcc 2.7 emits
   libcalls for 64-bit divide/modulo/shift and double↔long long
   (`__udivdi3`, `__umoddi3`, `__divdi3`, `__moddi3`, `__ashldi3`,
   `__lshrdi3`, `__ashrdi3`, `__fixdfdi`, `__floatdidf`,
   `__floatdisf`, ... — enumerated empirically).  Also, the wrapper
   links libc **only when no `-l` flags are present**, and resolves
   `-l` names to absolute paths itself.  → `compat/di_ops.c` (original
   MIT implementation, 32-bit-halves arithmetic only — no recursion)
   is built into `build-amix/lib/libamix.a`, together with `getutx.o`,
   `getut.o`, `truncate.o` **extracted from the static SVR4.0
   `libc.a`** (the shared libc.so.1 lacks the `getutx*()` family that
   pkginstall's run-level check calls; member closure verified).
   `LIBS=-L$(TOPDIR)/build-amix/lib -lamix -lc` in mk.config.amix.
4. **Floating-point compares miscompile through the wrapper**: gcc
   prints the SUN operand order (`fcmp.d %fp0,&imm`, condition =
   first − second) while binutils-2.8.1 gas encodes the Motorola order
   (`FCMP <ea>,FPn` = FPn − <ea>) — immediate forms are rejected
   outright ("operands mismatch"), register-register forms assemble
   **sense-inverted**.  Reg-reg float ops with `.s/.d` size
   (`fsgldiv.s %fp0,%fp2`) are also rejected (gas wants `.x`).
   → `amix-cc` (CC in mk.config.amix) reproduces the wrapper's compile
   flow, applies the wrapper's own `fix_asm` (extracted from the
   installed wrapper **at runtime**, so wrapper fixes propagate
   automatically) and adds the two float fixups.
   **Switch-dispatch (.swbeg) fix**: the on-box-diagnosed root cause
   of the earlier "inverted comparisons" was gcc 2.7's switch dispatch
   assuming the SGS `.swbeg` directive occupies 4 bytes while GNU as
   emits 0 — every switch case was entered 4 bytes late, branching on
   stale flags.  The toolchain wrapper was patched to replace
   `.swbeg &N` with a 4-byte `.long N` filler — but the INSTALLED
   wrapper's rule is broken: it runs under line-by-line `perl -p`
   where the trailing `\s*$` also consumes the NEWLINE, merging
   `.long N` with the following jump-table label (gas: "Rest of line
   ignored"), so any dense-switch file (e.g. libadm/ckdate.c) fails to
   assemble through the raw wrapper.  `amix-cc` therefore applies the
   CORRECT slurp-mode `/mg` rule (byte-identical to the validated
   `src/contents-fsck/tools/asmfix.pl` one, which preserves the
   newline) as Fixup 0, *before* the extracted `fix_asm` — after which
   the wrapper's broken rule matches nothing.  `build-amix.sh`
   verifies the dispatch invariant (kat-verify.sh pattern: every
   `movew %pc@(A,...)` table fetch is followed by `jmp %pc@(B,...)`
   with A == B) on pkginfo/pkgadd/pkginstall: 13+12+44 dispatch
   pairs, 0 mismatched.
5. **SVR4.0 headers hide declarations from ANSI compilers**: most
   POSIX/XPG declarations sit behind
   `#if __STDC__ == 0 || defined(_POSIX_SOURCE) || defined(_XOPEN_SOURCE)`
   and gcc defines `__STDC__=1`.  → `-D_XOPEN_SOURCE` in CPPFLAGS
   (additive-only in these headers), a localized `_POSIX_SOURCE` in the
   shadow `sys/signal.h` wrapper (for `sigset_t`/`struct sigaction`),
   and explicit declarations in `amixcompat.h` for the rest (strdup,
   sigset family, getopt globals, PATH_MAX/MAX_INPUT/... constants).
6. **The binutils-2.8.1 cross `ar` aborts** ("buffer overflow
   detected") under modern glibc fortify.  → host `ar`/`ranlib` write
   the same portable `!<arch>` format + symbol index; GNU ld 2.8.1
   reads them fine (verified across all five libraries + final links).

## compat/ shim inventory (Amix build only; host build uses none)

| file | contents | origin/license |
|---|---|---|
| `amixcompat.h` | rpl_snprintf/rpl_vsnprintf mapping + config for the vendored snprintf; LFS64→plain mapping (`stat64`→`stat`, `fstat64`, `lstat64`, `statvfs64`, `fstatvfs64`, `readdir64`, `dirent64`, `fsblkcnt64_t`, `fsfilcnt64_t`, `O_LARGEFILE 0`); missing types (`ssize_t`, `blkcnt_t`, `fsblkcnt_t`, `fsfilcnt_t`); hidden limits (`PATH_MAX` etc.); `MAP_FAILED`, `SA_RESTART`, `NSIG`; `#define environ _environ` (libc exports only `_environ`); `#define vfork fork`; `bzero/bcopy/bcmp` macros; declarations for every shim below + `strdup`, sigset family, getopt globals; `dirfd()` macro (`dd_fd`) | new, MIT |
| `amixcompat.c` | strcasecmp, strncasecmp, mkstemp (mktemp+O_EXCL retry), isblank, iswspace/iswprint/iswalpha/iswdigit/wcwidth (byte-locale fallbacks), gethostname (uname), localtime_r, getpagesize (sysconf), madvise (no-op), memalign (=malloc; only user free()s the result), pwrite (lseek save/restore), ftruncate (fcntl F_FREESP / zero-byte-write grow), atoll, strtoull, strtok_r, basename, realpath (chdir/getcwd; final-component symlink not chased), fgetpwent/fgetgrent (colon parsers; declared by Amix headers but absent from libc) | new, MIT |
| `di_ops.c` | 64-bit integer helpers with libgcc names (see quirk 3); double conversions avoid unsigned↔double (gcc emits gas-rejected `fcmp.d &imm` sequences) by splitting into signed 16-bit pieces | new, MIT (original, not GPL libgcc code) |
| `snprintf.c` | C99-semantics snprintf/vsnprintf incl. `%lld` | vendored, Patrick Powell / Holger Weiss lineage (permissive, header kept); configured via `HAVE_*` in amixcompat.h; float paths forced to plain `double` (`HAVE_LONG_DOUBLE 0`) |
| `fnmatch.c`, `fnmatch.h`, `charclass.h` | POSIX fnmatch | vendored from openssh-portable openbsd-compat (BSD/ISC/public domain, headers kept); only edit: OpenSSH `includes.h`/`HAVE_FNMATCH` wrapper removed (marked) |
| `libintl.h` | identity gettext/dgettext/dcgettext/textdomain/bindtextdomain macros | new, MIT |
| `wchar.h`, `wctype.h` | wchar_t via stdlib.h, `wint_t`, `WEOF`, isw*/wcwidth declarations | new, MIT |
| `strings.h` | → string.h | new, MIT |
| `alloca.h` | `alloca` → `__builtin_alloca` | new, MIT |
| `inttypes.h` | fixed-width typedefs for `hdrs/sys/dklabel.h`/`vtoc.h` | new, MIT |

Compat objects `snprintf.o amixcompat.o fnmatch.o` are compiled into
**libadm.a** via `COMPATOBJ` (set only in mk.config.amix; the host
build's COMPATOBJ is empty).  `libamix.a` (di_ops + static-libc
members) is assembled by build-amix.sh.

Also: `libpkgdb/sqlite.h` — stub declaration header (MIT) so
`libgendb/genericdb.c` compiles; the linker maps in
`research/heirloom/linksets/` prove genericdb.o is never pulled into
any binary (the deleted vendored SQLite is never needed).

## Source-change inventory (patch set)

All Amix-behavior changes are marked `AMIX PORT` in the code.

**Validated dive patches applied:**
- `libpkg/srchcfile.c:780-816` — tolerant re-join parser
  (`research/heirloom/contents-harness/tolerant.patch`, applied with
  `patch -p1`; result byte-identical to the validated
  `srchcfile_tolerant.c`).  Fixes the space-in-pathname corrupt-record
  abort in every consumer (pkginfo/pkgrm/pkgchk/installf/removef).
- `libpkg/dstream.c:499,673,720` — cpio `-icdumD`→`-icdum`,
  `-ictD`→`-ict` (SVR4.0 cpio has no `-D`).
- `libpkg/Makefile.mk` — `keystore.o security.o pkgweb.o` removed from
  OBJ; `nokeystore.o` added.  `libpkg/nokeystore.c` copied from
  `research/heirloom/de-openssl/`, extended with the symbols the link
  actually demanded: `set_passphrase_prompt`, `set_passphrase_passarg`,
  `pkg_passphrase_cb` (fail cleanly), `path_valid` (logic verbatim from
  the removed pkgweb.c) and `strip_port` (returns 0).  `sslstub/`
  (17 stub OpenSSL headers) copied from research and used by BOTH
  builds — no OpenSSL anywhere.
- `libinst/scriptvfy.c` — pre-generated flex scanner copied from
  `research/heirloom/de-openssl/scriptvfy-pregen.c`; `yywrap()`
  appended so neither lex nor libl/libfl is needed;
  `libinst/Makefile.mk` scriptvfy.l rule and clean entry removed, and an
  empty `scriptvfy.c: ;` rule added so make's built-in `%.c: %.l` never
  regenerates it (a checkout that left the .l newer re-ran lex and broke
  the link, CI 2026-10-30); scriptvfy.l carries the same `yywrap()`;
  `-L$(CCSDIR)/lib -ll` removed from 13 pkgcmds/valtools Makefile.mk.

**VERSION trio (factory packages have no VERSION):**
- `pkgcmds/pkginfo/pkginfo.c:370` — report() no longer requires
  VERSION; `:474,:500` — prints `(none)` when absent (both -x and -l
  formats).
- `pkgcmds/pkginstall/getinst.c:121` — NULL-guard `info[i].version`
  (and arch) in the same-instance compare; fixes the silent SEGFAULT
  on upgrade-over-VERSION-less.
- (pkgadd's add-time VERSION requirement in pkgenv.c is intentionally
  KEPT — catalog packages have VERSION per design.md.)

**Bug hygiene:**
- `libadm/pkginfo.c:286` — svr4info() `path[128]/line[128]` →
  `PATH_MAX` + snprintf/sizeof-bounded fgets (silent stack smash with
  install roots > ~105 chars).
- `libpkg/verify.c:114` — reperr() off-by-one (`sizeof-n` → `sizeof-n-1`
  after the appended `\n`); one-byte static overflow aborted long
  pkgchk runs.
- `libinst/pkgops.c:1354` — `assert(a_rootPath != '\0')` pointer/char
  typo → `assert(*a_rootPath != '\0')`.
- `pkgcmds/pkginstall/check.c:553+` — ckdirs(): mkpath() writes into
  its argument; get_PKGADM()/PKGSCR/get_PKGLOC() can be string
  literals → copied to the local PATH_MAX buffer first (SIGSEGV when
  the directory was missing).

**contents DB fidelity (APKGENG 1.12.3, 2026-10-06; NOTES.md 2026-10-06):**
- `pkgcmds/pkginstall/instvol.c` `endofclass()` — for a class with a
  class action script, an `e`/`v` object whose `finalck()` passed has the
  size, cksum and mtime that `finalck()` re-read from disk (contchg -1 →
  `BADCONT`) copied into the contents entry before `putcvfpfile()`.
  Upstream (and stock SVR4.0 pkginstall, disassembled) wrote the entry
  merged from the pkgmap, so a file the script kept failed a plain
  pkgchk.  `f` objects keep the pkgmap's values.
- `pkgcmds/installf/installf.c` — a pathname containing a space, tab or
  newline is refused (`ERR_WSPATH`): contents(4) has no quoting, and the
  record would be unreadable to the stock tools and to installf -f.  The
  tolerant readers are unchanged.
- `pkgcmds/installf/removef.c` — the stdin form (`removef PKG -`) takes
  the first white-space delimited token of each line, like installf's
  stdin form; upstream kept fgets' newline and matched nothing
  (2026-10-26, root cause 13).

**Install-miniroot mnttab robustness (Installer-NG W5.5a, bench 2026-07-23):**
- `libinst/mntinfo.c` `get_mntinfo()` — synthesize a "/" root entry when
  the mount table lacks one, instead of the fatal `ERR_MNT_NOROOT`
  ("get_mntinfo() identified <X> as root file system instead of </>").
  SVR4 `get_mntinfo()` asserts that the shortest-named mount entry is the
  root "/", i.e. that `/etc/mnttab` records the root filesystem; every
  normally-booted SVR4 system does, so **on real hardware the new branch
  is never entered and behaviour is unchanged.** The Amix *install
  miniroot* is the exception: its `/etc/mount` is a bare `mount(2)`
  wrapper that writes NO mnttab entry, and its boot never registers "/",
  so after the driver mounts the `-R` target and the CD, `/etc/mnttab`
  holds only the cdfs `/cdrom` line. The stock code then mis-identified
  `/cdrom` as root and aborted the ENTIRE base-OS datastream install,
  installing nothing. **Bench-confirmed 2026-07-23** (A3000+A4091,
  miniroot, `w54c` ISO): `pkgadd -R /mnt -n -a <adm> -d core-2.1.pkg core`
  printed the ERR_MNT_NOROOT line and left `/mnt/var/sadm/pkg` empty;
  appending a `/dev/root / s5 rw 0` line to `/etc/mnttab` made the SAME
  invocation install core rc=0 (complete `pkginfo`/`install`/`save`). The
  fix synthesizes exactly that entry (root is, by definition, always
  mounted — the process runs out of it), so an explicit `-R` install is
  no longer vetoed by a sparse/incomplete host mnttab.
  - Test hook: `get_mntinfo()` honours `$PKG_MNTTAB` as the mount-table
    path (falls back to the compiled-in `MOUNT_TABLE`), in the same
    env-gated spirit as the `DS_DEBUG` traces. NEVER set on the box, so
    the shipped tools read the real table unchanged; the host suite uses
    it to drive controlled fixtures (real `/etc/mtab` always has "/", so
    the fix is otherwise unreachable from a host build).
  - Regression: `tests/mntinfo-robustness/{test-mntinfo.c,run.sh}` — a
    standalone driver linked against the host `libinst` calls the real
    `get_mntinfo()` against a sparse fixture (→0, synthesized), a normal
    one (→0, unchanged) and an unreadable one (→1, fail-closed), and
    asserts `pkgadd` on a missing datastream exits non-zero. Verified the
    driver actually exercises the fix by rebuilding libinst with the
    synthesize block removed (override kept): the sparse case then
    returns 1, the bug.
  - Exit-status note (the "processes nothing, exits 0" fail-open): the
    engine's install path already fails CLOSED — `pkginstall`/`pkgremove`
    `quit(99)` and `installf` `exit(1)` on a get_mntinfo failure, so
    `pkgadd` (via `ckreturn(99)` → `failflag`) exits non-zero; on-box
    `pkgadd -d <missing>.pkg` returns 99. The one caller that *tolerates*
    a get_mntinfo failure is `pkgchk` (`if (get_mntinfo(...)) map_client
    = 0;`, an intentional "verify without client mapping" — it exited 0
    while printing the scary ERR_MNT_NOROOT). This robustness fix removes
    that spurious failure at the source, so no caller emits it.

**Install-miniroot mnttab robustness, part 2 — a MISSING mount table
(Installer-NG METAL-FIX.1, bench 2026-07-23):**
- `libinst/mntinfo.c` `get_mntinfo()` — extend the W5.5a fix (above) to the
  case where `/etc/mnttab` is **absent entirely**, not merely sparse. W5.5a
  synthesizes "/" when the table is present but lacks a root line; that
  synthesize sits *after* the `setmntent()` open, so it is unreachable when
  the open itself fails. On the first **RAW** (`raw:<slice>`) metal install
  (A4000+Z3660, A4091, 2026-07-23) everything ran green through seed +
  `apkg update` + all 8 SRC_RAW package reads, then `pkgadd` died with
  `unable to open mount table (/etc/mnttab): No such file or directory` and
  made "No changes ... ". The miniroot ships **no** `/etc/mnttab`
  (`miniroot.proto` has no entry) and the RAW path's `/etc/mount` is a bare
  `mount(2)` wrapper that writes none, so on fresh media `open()` returns
  ENOENT before W5.5a can act.
  - Why the bench RAW acceptance passed anyway (state contamination, not a
    real pass): the reused root **floppy** carried an `/etc/mnttab` left over
    from cdfs-helper mounts in earlier CD-arm waves, so the file was *present*
    (sparse) and the W5.5a branch handled it. Fresh media has no such file.
  - Fix: when `setmntent()` fails with **ENOENT specifically**, treat the
    table as empty and synthesize the root via the same
    `/dev/root / s5 rw 0` construct W5.5a uses (now factored into the shared
    `synthesize_root()` helper so the two paths cannot drift). **Every other
    open error (EACCES, EIO, ...) still fails CLOSED exactly as before** — the
    widening is ENOENT-only, so a normally-booted SVR4 system (which always
    has a readable `/etc/mnttab`) never takes the branch; it is install-media
    only. `$PKG_MNTTAB` is honoured in the new branch too (same test hook).
  - Regression: `tests/mntinfo-robustness/` grows to **5/5**. New case
    "missing mnttab file (ENOENT) -> root synthesized -> rc 0"; the existing
    "unreadable -> fail closed (rc 1)" fixture was switched from a *missing*
    file to a **`chmod 000` (EACCES)** file, because a missing file now
    legitimately synthesizes — the semantics split is the point. Proven
    load-bearing: with the ENOENT branch reverted (fail-closed for all
    errors), the missing-file case flips to rc 1.
  - Belt-and-suspenders (owned by amix-installng, added independently): the
    install driver also seeds `/etc/mnttab` with the literal `/dev/root / s5
    rw 0` line before invoking `pkgadd` on every source arm, so a stock
    (unpatched) engine would survive too. The two fixes are complementary;
    neither depends on the other.

**s5 14-character names — pkgadd could never OVERWRITE a file whose basename
is ≥ 14 characters (2026-08-14):**
- `pkgcmds/pkginstall/cppath.c` `write_file()` — the mkstemp(3) template was
  `<target-path>` + `"XXXXXX"`. Amix's root filesystem is s5, which truncates
  every directory-entry name to **14 bytes on create and on lookup**, so for a
  target whose basename is already ≥ 14 characters *every* candidate name
  mkstemp can generate truncates back onto the dirent being replaced: each
  `O_CREAT|O_EXCL` create returns EEXIST, mkstemp gives up, and pkgadd dies
  with `ERR_MKTEMP`. The empty `<>` in the failure message is mktemp having
  blanked the template — the fingerprint of exactly this path, and what the
  amix-installng W6 `cd-full` bench log showed.
  - **Scope: an upgrade/re-install defect, not a fresh-install one.** The
    branch is entered only when the target already exists (`access(F_OK)`).
    Fresh installs are provably safe — of the 109 paths declared by more than
    one package, 94 are directories (the `mkdir` path, not `write_file`) and
    all 15 shared non-directories have 3–8-character basenames — which is why
    `minimal`/`standard`/`developer`/`x11` attested clean. What it broke is
    `apkg upgrade` / re-install over an installed box: **572 objects of the
    `full` set**, including shipped files as ordinary as
    `/usr/apkg/doc/OPENSOLARIS.LICENSE`, `/usr/apkg/bin/amix-sadm-migrate` and
    `/etc/inet/network-config`. Measured in
    `../docs/s5-14char-collisions.md` §2.1.
  - **Fix**: `temp_template()` composes the template with at most
    `AMIX_TMPL_STEM` (8) bytes of the target basename plus the six X's, i.e. a
    template basename of at most `AMIX_S5_NAME_MAX` (14) bytes, so the X's are
    the part that SURVIVES truncation instead of the part that is eaten. The
    temporary stays in the **target's own directory** — non-negotiable, since
    `cppath()` finishes with `rename(temp, target)`, atomic only within one
    filesystem, and that is what makes replacing a running binary safe. A
    basename of ≤ 8 characters yields byte-for-byte upstream's template.
  - **Collision safety**: the entropy is unchanged (the same six X's); only
    the template's *distinctness* drops, and a taken candidate was never fatal
    — `compat/amixcompat.c`'s SVR4-mktemp-based `mkstemp()` (the one that runs
    on the box) restores the pristine template and retries up to ten times on
    EEXIST, and mktemp's per-process pid component keeps concurrent pkgadds
    apart.
  - The cap is **unconditional**, not conditioned on
    `pathconf(_PC_NAME_MAX)`: a 14-byte temporary name is valid on every
    filesystem, the name is cosmetic (it exists for the duration of one copy;
    only a `rename` failure ever exposes it, in `$PKGADM/textbusy`), and
    asking a 1991 libc would make the fix silently inoperative if that libc
    answered wrongly. `AMIX_S5_NAME_MAX` is the knob if a longer-named
    filesystem (ufs) ever becomes the target.
  - Also fail-closed: a template that does not fit `PATH_MAX` is now an error
    return. Upstream reported it and then ran `mkstemp()` on the truncated
    remains, which can only create — or clobber — the wrong path.
  - **What this does NOT fix**: two *different* names that alias to one dirent
    (`typescript.stage1` / `typescript.stage2`) still share that dirent; the
    second write wins and pkgadd's own size/cksum verification reports the
    loss. That is the packaging-side decision in
    `../docs/s5-14char-collisions.md` (Option A, 5 objects), not a code bug.
  - Regression: `tests/s5-14char/{run.sh,test-cppath.c,s5sim.c}` — 24 checks,
    **red/green**. `s5sim.so` (LD_PRELOAD) gives one directory tree s5's
    naming semantics (every component truncated to 14 bytes on create AND
    lookup) and supplies the box's own mktemp-based `mkstemp()` — glibc's
    reaches the kernel through internal calls LD_PRELOAD cannot interpose, and
    the box does not use glibc's anyway. The suite builds the **real**
    `cppath.c` twice: with `-DAMIX_NO_S5_TEMPLATE_CAP` (upstream template) it
    must reproduce the bench failure including the `<>` fingerprint; as
    shipped it must succeed and leave no temporary behind. Short basenames,
    the relative-path (`./`) branch, and a normal 255-character filesystem are
    covered too.

**C89 / SVR4.0 compilability (new in this port):**
- `libspmizones/spmizones_api.h:225` — C99 variadic macro
  `z_ExecCmdList(a,b,c,d,...)` (rejected by gcc 2.7 cpp) → old-style
  `extern int z_ExecCmdList();` (no callers exist in the tree).
- `libpkg/keystore.h:53`, `libgendb/genericdb.h:55` — boolean_t
  typedef guarded for `__svr4__` (SVR4.0 sys/types.h defines it as
  enum constants; `#ifndef B_TRUE` cannot see that).
- `hdrs/pkgstrct.h:47` — major_t/minor_t typedefs guarded for
  `__svr4__` (already in sys/types.h).
- `hdrs/sys/dklabel.h:47` — uchar_t/ushort_t/ulong_t typedefs guarded
  for `__svr4__` (already in sys/types.h).
- `libpkg/pkglib.h:50` — explicit `<stddef.h>`/`<stdarg.h>` (came in
  implicitly via real OpenSSL headers before).
- `libinst/mntinfo.c:1467` — Amix `_getmntent()`: SVR4.0 has no
  getmntent() in libc.  The live Amix 2.1c `/etc/mnttab` is PLAIN
  TEXT (od -c verified on the box): tab-separated
  `special mountp fstype mntopts time` records — NOT the old SysV
  binary format the sysroot `<mnttab.h>` still describes (a first,
  binary parser misparsed every entry and broke pkgremove's root-fs
  match).  The text parser is unit-tested against the exact on-box
  bytes.  Linux host keeps the original `<mntent.h>` branch.
- `hdrs/sys/mnttab.h`, `hdrs/sys/mntent.h`, `hdrs/sys/vfstab.h` —
  MNTTAB/VFSTAB point at `/etc/mnttab` and `/etc/vfstab` on
  `__svr4__` (the non-sun defaults were the LINUX paths `/etc/mtab`
  and `/etc/fstab`; the mount-table open is unconditional in
  pkginstall/pkgchk, so the first on-box run aborted with "unable to
  open mount table </etc/mtab>" — first real on-box failure, fixed
  and verified baked-in with strings(1): pkginstall/pkgchk reference
  only /etc/mnttab + /etc/vfstab).  The three headers must stay
  mutually identical (all included by mntinfo.c).
- `libpkg/verify.c:48` — `<sys/sysmacros.h>` include made
  unconditional (macro-only makedev/major/minor on Amix; glibc 2.28+
  needs it too — FIXLOG[4] generalized).

**Host-build fixes (from research/heirloom, made conditional):**
- `libadm/getpass.c:44` — `__linux__` uses POSIX termios (glibc
  removed stropts.h/termio.h); the SVR4 termio/ioctl form is kept for
  Amix (native).  From host-build-fixes.patch, made conditional.
- `-std=gnu89 -fcommon`, no `-m32` → `mk.config.host` (FIXLOG [0][2][5]).
- `pkgcmds/pkgremove/main.c` (rmclass) — a package directory that still
  holds entries is "not empty" for `ENOTEMPTY` as well as `EEXIST`.
  SVR4 rmdir(2) returns EEXIST, Linux ENOTEMPTY, so on the host a
  directory kept non-empty (a conffile r.conffile kept, P-36) failed the
  pkgrm "partially" and left the package "partially installed".  No
  change on Amix, where rmdir gives EEXIST (2026-10-30).
- `libadm/Makefile.mk` — hardcoded RedHat `-I/usr/lib/x86_64-redhat-
  linux5E/include` deleted; `$(COMPATOBJ)` + compat build rules added.

## Deviations from the plan

- `-include amixcompat.h` was impossible (wrapper limitation) →
  shadow-sysroot wrapper headers instead (same effect, documented
  above).  This also solved the worse problem of the sysroot's stock
  SVR4 pkg headers shadowing `hdrs/`.
- The compat archive is named `libamix.a`, not `libgcc.a`, because it
  also carries the static-libc utmpx members; linked as `-lamix -lc`.
- `amix-cc` CC shim (not in the plan): required for the float-compare
  assembler fixups; also future-proofs against the pending wrapper
  `fix_asm` correction.
- `pkgname`, `pkgscripts` (cmdexec + CAS scripts), `valtools` and
  `man` are NOT in the Amix build set (priority-1/2/3 binaries only).
  The CAS scripts under `pkgcmds/pkgscripts/*.in` are sed-generated
  text; add `pkgcmds/pkgscripts` to SUBDIRS when needed.
- getpass()/getpassphrase() in libadm compile but reference
  flockfile/funlockfile (absent from Amix libc); harmless — nothing
  in the built set links getpass.o (only the deleted pkgweb.c used it).

## Known risks for on-box testing (bench items)

1. **RESOLVED — switch dispatch (.swbeg)**: the toolchain wrapper fix
   landed and the tree was fully rebuilt through it; the dispatch
   invariant is machine-checked on every build (see quirk 4).  Note
   for the toolchain repo: the installed wrapper's own swbeg rule
   still eats the newline (use `[ \t]*$` or the slurp-mode `/mg`
   form); amix-cc masks this for the heirloom build only.
2. **FPU**: `__HAVE_68881__` codegen; the float paths (snprintf
   formatting, nblk/dockspace arithmetic, di_ops conversions) execute
   68881/68882 instructions.  On the Z3660's 68060 these need the
   kernel 68060 support (FPSP) for unimplemented instructions;
   real-A3000/A4000-with-6888x unaffected.
3. **mnttab parsing** (`mntinfo.c`): text parser matching the real
   on-box format (validated against the live file's exact bytes:
   3 entries incl. root `/`).  `/etc/vfstab` is read only if present
   (access(R_OK)-guarded, non-fatal).
   Runtime-path audit of the rest of the built set: `/etc/dfs/fstypes`
   missing → isdir.c falls back to a built-in nfs/autofs/cachefs
   list; `/proc/self/fd` in closefrom.c has a getrlimit/fcntl
   fallback, and the pkgadd/pkgrm `/proc/self/fd/%d` sites are all in
   zone-only functions (dead code: `z_zones_are_implemented()` is the
   constant-0 stub); `/etc/labelit` (getvol.c) is reached only in
   removable-volume flows, not datastream installs.
4. **Run-level check** (`pkginstall` ckrunlevel): uses getutx* from
   the static libc against `/var/adm/utmpx`.  If Amix does not
   maintain utmpx, the check fails ONLY when the admin file does not
   say `runlevel=nocheck` and ISTATES is set — our planned admin file
   says nocheck.
5. **contents trailer**: heirloom appends `# Last modified by ...`
   comment lines to `/var/sadm/install/contents` on every write;
   whether stock 1992 srchcfile tolerates `#` lines is bench item #1
   from the dive (unchanged by this port).
6. **realpath shim** does not resolve a symlink in the final path
   component (directory components are fully resolved).
7. **pkgchk's narrower internal buffer** (FIXLOG[8], unidentified
   site) was not found/fixed; short paths on Amix make it latent.
8. Warnings: the cross build emits ~75 warnings (mostly
   pointer-from-int in old-style code and harmless redefinitions);
   none affect the ILP32 target.

**Datastream robustness (on-box diagnosed):**
- `libpkg/dstream.c` — `ds_scan_cpio_archive()`: walks the newc
  (070701/070702) member headers from the current stream offset to
  TRAILER!!! and returns the archive length (rounded to the -C 512
  block padding), restoring the offset.  Used at all three cpio spawn
  sites: the native Amix SVR4.0 cpio does NOT stop at the first
  TRAILER!!! — it consumes CONCATENATED archives until EOF (on-box
  ds-repro trace: the ds_init metadata pass left the stream at EOF,
  so every part read failed with "Unexpected end-of-archive").
  `ds_init`/`ds_next` now feed the child exactly one archive through
  `esystem_bounded()` (below); `ds_skip` skips unwanted archives with
  a pure lseek (no cpio child at all).  Unseekable/non-newc streams
  fall back to the legacy unbounded behavior.  Active on BOTH builds
  (GNU cpio versions differ in trailer behavior too); host-verified:
  single- and two-package streams, skip+extract byte-identical.
- `libpkg/runcmd.c` — `esystem_bounded(cmd, ifd, nbytes)`: esystem()
  variant that pipes exactly nbytes from ifd into the child's stdin
  (SIGPIPE-safe: if the child stops reading early the remainder is
  lseek'ed/drained so ifd always ends at the archive boundary).
- `libpkg/vfpops.c` vfpSetSize() — **state corruption on allocation
  failure** (upstream latent bug, exposed by the allocation ladder
  below): `_vfpSize` was updated to the NEW size before malloc/
  realloc; on failure it stayed there, so a subsequent SMALLER
  vfpSetSize call took the "not larger than current" early exit and
  returned SUCCESS with `_vfpStart` still NULL — the temporary
  contents image then SIGSEGVs on first use (the on-box pkgremove
  crash right after lockinst).  Fixed: `_vfpSize` restored on both
  failure branches.  Regression-proven on host under `ulimit -v`:
  32 MB rung FAIL (size correctly back to 0) -> 8 MB rung allocates
  for real -> image write succeeds.
- `libinst/ocfile.c` — the temporary contents image was allocated at
  `st_size + CONTENTS_DELTA` = contents + **32 MB** up front: instant
  ENOMEM under the Amix per-process data limit (~12-16 MB) even
  though the contents file is 2.3 MB — and a flat step-down ladder
  proved still too greedy (a successful 8 MB rung starved the
  subsequent package-info allocations on the box).  The headroom is
  now PROPORTIONAL to the DB: first rung
  `max(512KB, min(32MB, st_size + 256KB))` (≈2.5 MB headroom / ≈5 MB
  total image for the Amix DB), halved on failure down to a 512 KB
  floor, then a clean error.  vfp overflow stays cleanly detected via
  _vfpOverflow/EFBIG, so a too-small window fails an install safely
  rather than corrupting.  Host-regressed at the on-box DB scale
  (2.4 MB synthetic contents under ulimit -v: proportional rung
  fails, halved rung allocates, image write succeeds).
  Additionally ocfile()/socfile() call `amix_raise_rlimits()`
  (compat/amixcompat.c, Amix build only): best-effort
  getrlimit/setrlimit soft->hard raise of RLIMIT_DATA and
  RLIMIT_VMEM (SVID3 rlimits, present in the SVR4.0 libc - verified),
  failures silently ignored; frees the whole memory-budget problem
  class for every DB-writing tool when the hard limit allows.
- `compat/amixcompat.c` getpagesize(): result sanity-checked (power
  of two in [512,64K], else 4096) since it feeds vfp size rounding.

**Signal machinery (quit(3) "user request" investigation):**
- Audit results: `sigsend()` has NO callers in the tree (the compat
  kill()-fallback is never exercised); pkgremove/pkgrm wire ONLY
  SIGINT and SIGHUP to `trap()` -> `quit(3)`; `pkgexecv()` (the
  front-end spawn primitive) returns 3 whenever the PARENT counts a
  SIGINT/SIGHUP while waiting - and the front-end's quit(3) prints
  the IDENTICAL "terminated due to user request" message, so the
  reporting process is ambiguous without the traces below.
- `libinst/lockinst.c` + `libinst/ocfile.c` pkgWlock() — **alarm
  leak fixed**: both arm `signal(SIGALRM, do_alarm); alarm(20)` for
  their lockf retry loop and ended with `signal(SIGALRM, SIG_IGN)`
  but WITHOUT `alarm(0)` - a live 20-second timer kept ticking into
  the rest of the process (benign only while the disposition stays
  SIG_IGN; on SVR4 signal() is unreliable-reset, so any later
  re-arming of SIGALRM races with default-action death).  Both now
  cancel the timer first.
- DS_DEBUG now also traces (pid-tagged, flushed): `trap()` signal
  number + `quit()` retcode/errno in pkgrm, pkgremove, pkgadd AND
  pkginstall; `pkgexecv()` parent-side signal counts (sig_trap) and
  the child-status decode (rawstatus/sig_received/exit_no);
  `lockinst` acquire/fail with place, `lockupd` place transitions,
  `unlockinst`, and `pkgWlock` lock/fail.  One traced
  `DS_DEBUG=1 pkgrm ...` run identifies which process dies, from
  which signal, at which lock state.

**Hardening round (background task; re-enables the heirloom engine
as apkg default in v1.1):**
- `libpkg/srchcfile.c` — **record-splice corruption fixed** (upstream
  latent): in the skipped-range copy, `lastPos` was taken from the
  clamped `_vfpCurr` (vfpIncCurrPtrBy stops at the LAST data byte),
  so when the last line of the contents file was a real record its
  trailing newline was dropped and the next entry written was SPLICED
  onto it (minimal repro: 78-byte 2-record file copied as 77 bytes;
  a full merge produced "...X11R5/usr/zzz d none..." on one line).
  Normally masked because a comment trailer is the last line; a
  contents-fsck-repaired DB (comments stripped) exposes it - the
  likely mechanism behind the on-box "self-healed"/vanished records.
  The tolerantly-parsed spaced record itself is PRESERVED verbatim
  through merges (host-verified in both before/after-insert
  geometries) - the dive finding stands.
- `libpkg/runcmd.c` + `libpkg/pkgexecv.c` — **inherited
  SIGCHLD=SIG_IGN immunization**: a calling process with SIGCHLD set
  to SIG_IGN (classic zombie-avoidance; survives exec) made every
  heirloom waitpid() fail with ECHILD - every spawned cpio/script
  "failed" (host-reproduced with a hostile parent; matches the
  "sequential engine invocations from one parent fail" on-box class).
  All spawn primitives now reset SIGCHLD to SIG_DFL before forking.
- `pkgcmds/pkgremove/delmap.c` — **pinfo-chain leak fixed** (the
  on-box "no memory for package information" OOM): srchcfile callocs
  a fresh pinfo chain per record; the loop reuses one cfent for all
  28k+ records, orphaning every chain.  Freed for non-matching
  records (safe: eptstat makes no pool insertions when the package
  is not referenced).  Host-regressed: pkgrm on a 2.4 MB DB under
  ulimit that previously died silently now completes (rc=0).
  Also: the raw `exit(99)` in the srchcfile-error branch (silent, no
  unlockinst -> bogus stale-lock records) is now `quit(99)`.
  Same leak fixed in `pkgcmds/pkginfo/pkginfo.c` (whole-DB scan).
  KNOWN REMAINING: installf/dofinal.c and pkgchk share the pattern
  (chains can contain eptstat pool nodes there; needs a more careful
  fix - documented follow-up).
- `libinst/lockinst.c` + `libinst/ocfile.c` — **lock lifecycle**:
  unlockinst's clean-completion record is verified (falls back to
  truncating the lock file - read as clean - if the write fails);
  lockinst() and pkgWlock() get a second acquisition attempt after
  UNLINKING and recreating a wedged lock file (fresh inode, clean
  kernel record-lock state - automates the manual "delete
  .pkg.lock" bench workaround; skipped when the recorded holder pid
  is alive), with messages on every path.  apkg's temporary
  client-side lock-clear workaround can be removed once this build
  is deployed.
- `pkgcmds/{pkgremove,pkginstall}/main.c` — **DS_DEBUG survives
  `environ = NULL`**: the environment reset made getenv() return
  NULL mid-run, silently disabling all tracing beyond that point
  (this misled the on-box diagnosis; "no trace" did not mean "not
  executed").  The flag is latched and re-injected via putparam.
  Also: first-executable-statement "alive" traces in
  pkgadd/pkginstall/pkgremove main() discriminate died-before-main
  (exec/loader level) from early-main crashes; quit() traces now
  include warnflag/failflag; ocfile ladder rungs, rlimit
  before/after values and vfpOpen backing choice (mmap/malloc) are
  traced.
- `libinst/ocfile.c` ladder rework: first rung
  `max(1MB, min(8MB, st_size))` halved to a 512 KB floor (a
  SUCCESSFUL oversized rung starved the rest of the tool);
  `amix_raise_rlimits()` prints before/after values under DS_DEBUG
  so the on-box hard cap is measurable (if the hard cap is the
  kernel maxdsiz, the /etc/master.d tunable is the recovery path).

**Sequential-pkgadd SEGV round (pkginstall #2, crash after pkgmap
open):**
- Host replication of the EXACT on-box conditions (the real
  DEMOLIB/AMIXDEMO packages from build/repo-staging, the exact
  pre-run-1 DB derived from the on-box post-run-1 contents, the apkg
  admin file, hostile parent): the full lifecycle PASSES on host and
  is **AddressSanitizer-clean end to end** after fixing the two real
  memory bugs ASAN found:
  - `libadm/pkgparam.c` fpkgparam() — stack-buffer-UNDERFLOW: the
    trailing-whitespace trim evaluated `isspace(*(copy-1))` BEFORE
    the remaining-length check, reading below `buffer` on every
    EMPTY value (e.g. the "mail=" admin line) - and walking further
    down if the out-of-bounds byte looked like white space.  Fired
    in every pkgadd admin parse.
  - `libpkg/canonize.c` (4 sites) + `libadm/pkgparam.c`
    canonize_name (3 sites) — in-place "./"/"../"//" removal used
    strcpy() with OVERLAPPING ranges (UB; outcome depends on the
    libc strcpy implementation and the path bytes of the package
    being processed - `isreloc()->canonize()` runs EXACTLY in the
    crash window).  Replaced with a defined-behavior left-shift
    helper.  (The Amix shared-libc strcpy disassembles as a forward
    byte loop, so this one is a correctness fix more than a proven
    crash cause.)
- The residual box crash (pkginstall #2 between the pkgmap open and
  the "preinstall" lockupd = inside sortmap: pkgobjmap parse or
  pkgdbmerg merge) could NOT be reproduced host-side; DS_DEBUG now
  carries surgical phase markers - sortmap (pkgobjmap start/done,
  pkgdbmerg start/done) and pkgdbmerg (every 2000th srchcfile call +
  the copy-rest transition) - so one traced box run pinpoints the
  function and record neighborhood if it persists with this build.

**pkginstall #2 residual (v12 narrowing):**
- v12 box trace: dies between "sortmap: calling pkgdbmerg" and any
  merge-internal output; host-ASAN is clean on identical data.
- `libinst/pkgdbmerg.o` is now compiled **without optimization** on
  the Amix build (`PKGDBMERG_OPT=` in mk.config.amix, explicit rule
  in libinst/Makefile.mk; the host keeps full optimization) - the
  gcc 2.7.2.3 -O codegen discriminator.  If the box completes with
  this build, shipping pkgdbmerg at -O0 is the permanent workaround.
- Fixup-hazard audit of the -O pkgdbmerg assembly: 80 cmp.b/cmp.l
  lines - every operand shape swaps into a valid, semantically
  correct Motorola form; 2 .swbeg (covered by the corrected fixup +
  the dispatch gate); no fcmp/cmpa/cmpm forms; the Gunnar "#if 0"
  region is inert.  Nothing implicates the asm fixups in this file.
- Granular DS_DEBUG markers now bracket the merge: pkgdbmerg ENTER
  (extlist count, map/tmp buffer geometry, notify interval), every
  srchcfile call for the first 50 (+ every 2000th) with target AND
  return value, do_like_ent/do_new_ent decisions, and an
  async-signal-safe "notice: FIRED" marker in the 60-second progress
  alarm handler (it interrupts the merge on slow machines - a fire
  right before the crash would implicate it; it never fires on the
  fast host).  The last marker printed names the exact crash site:
  call-without-return = inside srchcfile; after ENTER only = merge
  prologue; FIRED = the notifier.

**v13 narrowing (crash inside do_like_ent for the single-owner
/usr/apkg/demo row; the 3-owner /usr/apkg row succeeded just before):**
- The whole helper set on the do_like_ent path is now compiled
  without optimization on the Amix target via **MERGPATH_OPT** (empty
  in mk.config.amix = -O0; full CFLAGS on host): `libinst/eptstat.c`
  (pinfo chain edit), `libinst/listmgr.c` (the bl_* block-list
  allocator eptstat draws pool pinfos from), `libpkg/putcfile.c`
  (record re-serialization via output()) and `libpkg/verify.c`
  (averify/cverify used by set_change on existing objects).
  PKGDBMERG_OPT remains as an alias for pkgdbmerg.c itself.
  Perf note: verify.c at -O0 slows install-time checksumming on the
  box; acceptable, and reversible per-file once the culprit is known.
- Asm-fixup audit of all four helpers at -O: zero .swbeg, zero
  fcmp/cmpa/cmpm, every cmp.b/w/l operand shape swaps into a valid
  Motorola form.  The fixup pipeline remains unimplicated.
- DS_DEBUG now brackets do_like_ent's sub-steps: "eptstat DUP_ENTRY"
  / "eptstat done (pkgpinfo/otherstoo/npkgs)" / "merg" / "merg done"
  / "set_change (averify/cverify)" / "set_change done" / "second
  eptstat cluster done; output" / "output done" / "returning".
  If the next box run still crashes, the last marker names the
  faulting helper file directly (all of which are already -O0 in
  this build - so a persisting crash would point past codegen, at
  which point the named helper gets single-stepped scrutiny).

**v14 narrowing (crash inside set_change -> averify for the fresh
/usr/apkg/demo row):**
- The suspected port-introduced reperr() fix was byte-audited: the
  arithmetic is correct (n bytes + newline + NUL leaves
  sizeof-(n+1) = the patched ptln).  The forced-mismatch report path
  (chmod-skewed directory so averify emits ERR_PERM/group/owner
  reports) is AddressSanitizer-clean on host.
- First-invocation analysis: /usr/apkg (attributes intact) exercises
  NO reperr formatting and NO group/owner lookups; the mismatching
  /usr/apkg/demo triggers the process's FIRST cgrnam()/cpwnam() -
  which initialize the ncgrpw.c name cache and nhash.c hash tables -
  and the first rpl_vsnprintf %04o conversion.  Those files were the
  last -O code reachable from the crash site: **MERGPATH_OPT now
  also covers libpkg/ncgrpw.c, libpkg/nhash.c and the vendored
  compat/snprintf.c** (all -O0 on the Amix build).
- averify is now stage-marked under DS_DEBUG: enter(path/ftype/fix),
  "mode check", a bracket around reperr ERR_PERM, "group check
  (cgrnam/cgrgid)", "owner check (cpwnam/cpwuid)", "statvfs", exit
  (retcode).  If the next box run still crashes, the last stage
  names the exact call; with everything on the path at -O0 a
  persisting crash is a C-level/libc-level fault in the named stage
  (e.g. Amix getgrnam/getgrgid behavior differences).

**v15 kill shot (first cpwnam() -> Amix libc getpwnam() SIGSEGV):**
- Mechanism analysis: interposition/symbol-collision was RULED OUT -
  disassembly shows Amix libc's getpwnam/getgrnam call their internal
  helpers with direct pc-relative bsrl (not preemptible), and the
  shims (fgetpwent & co) are neither referenced nor definable inside
  those paths.  libc's passwd/group internals allocate through the
  global function-pointer indirection _libc_malloc/_libc_free (the
  SVR4 allocator-redirect mechanism), and the passwd-side "entry"
  record handling (36-byte expand via those pointers) dies in our
  process where the group side survives; the exact libc-internal
  fault is not further debuggable off-box.
- Fix (mnttab-style sidestep, at the strongest interposition point):
  **compat/amixcompat.c now DEFINES getpwnam/getpwuid/getgrnam/
  getgrgid** as direct /etc/passwd + /etc/group text parsers built on
  the existing fgetpwent/fgetgrent shims.  An executable's global
  definitions preempt shared-library exports for every object in the
  build, so ALL callers are covered uniformly (ncgrpw.c's cached
  cpwnam/cgrnam/cpwuid/cgrgid, libadm ckuid/ckgid, pkginstall
  reqexec) - verified with nm on the linked pkginstall (all four
  symbols T).  libc semantics preserved: static storage, NULL when
  not found.  Amix build only (host uses glibc).
- Unit-tested on host against SVR4-format passwd/group samples
  (lookups by name and id, member lists, empty fields, misses).
  Known limitation: NIS "+/-" entries are treated as ordinary lines
  (no compat lookup falls through to NIS); irrelevant on the bench.
- Why the group check survived (coordinator q3): cgrnam and cpwnam
  are symmetric in ncgrpw.c (clgrnam/clpwnam are inert without -R);
  the divergence was wholly inside the libc passwd machinery, which
  the sidestep now bypasses entirely.

## Debug aids (in the tree, runtime-gated)

- **`DS_DEBUG=1`** environment variable: traces the whole datastream
  read path to stderr — `ds_init` header reads/toc, `ds_findpkg`/
  `ds_skip`/`ds_next` state and stream offsets, and every `esystem()`
  child spawn in runcmd.c (exact command, stdin fd offset, peek at
  the next 16 bytes, raw+decoded wait status, and the child's
  captured stderr file on failure — normally discarded).  Compiled
  into both builds, zero-cost when unset.
- **`build-amix/probe-early`** (source `probe-early.c`): on-box probe
  for the early pkgremove flow, four phases with flushed markers:
  (A) mnttab text parse with a compiled-in copy of the parser,
  (B) real `get_mntinfo()`, (C) real `ocfile()` against the live DB
  (temp image is memory-only; DB lock taken and released),
  (D) sanity-write into the temp image.  Exit 0 = all pass, 10+N =
  phase N failed cleanly.  Run: `DS_DEBUG=1 probe-early 2>&1`.
  DS_DEBUG now also traces `_getmntent` entries, `get_mntinfo`
  progress and each ocfile allocation-ladder rung outcome, so
  `DS_DEBUG=1 pkgremove ...` shows the same flow inside the real tool.
- **`build-amix/ds-repro`** (source `ds-repro.c`): standalone m68k
  reproducer for the on-box datastream/cpio interaction.  Runs three
  experiments — (1) cpio with a regular-file stdin at offset 512
  (heirloom's esystem geometry), (2) cpio fed the same bytes through
  a pipe (the known-working `dd | cpio` geometry), (3) the exact
  pkgtrans flow through the real libpkg (`ds_findpkg`/`ds_getpkg`).
  Exit mask: 1=rawfd, 2=pipe, 4=heirloom failed.  Run as
  `DS_DEBUG=1 ds-repro <stream.pkg> <PKGINST> 2>trace`.

## Licensing

CDDL headers intact in all modified files (changes marked `AMIX PORT`).
New compat/shim files, `libpkg/dsepoch.c` and the `tests/` scripts are MIT
(Jussi Alanärä).  Vendored files keep
their original headers: snprintf.c (Powell/Weiss permissive),
fnmatch.c/fnmatch.h/charclass.h (BSD/ISC/public domain, OpenBSD via
openssh-portable).  `compat/di_ops.c` is an original implementation,
NOT derived from GNU libgcc.  `getutx.o/getut.o/truncate.o` inside
`build-amix/lib/libamix.a` are extracted at build time from the
PROPRIETARY Amix libc.a in the local sysroot — they are a build
product (never committed) and their binaries run only on Amix itself,
same standing as linking against libc.so.1.
