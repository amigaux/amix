# host-altroot — host reproduction attempt for the `pkgadd -R` SIGSEGV

Diagnosis harness for `AMIX-PORT.md` open follow-up **item 0**: heirloom
`pkgadd -R <altroot>` SIGSEGVs on the box inside `averify()`'s `fix=1`
group check. Real-system (non-`-R`) installs are unaffected.

For three rounds (v15/v16/v17) the blocker was filed as
"host-unreproducible, needs a box run". This harness exists to make that
claim *falsifiable* — a "no crash" result is only meaningful if you can
prove the crashing code actually ran.

## Verdict (2026-07-19): NOT reproducible on the host

See "Evidence" below. The path was **proven to execute** and completed
clean.

## What previously made host runs vacuous

Four independent reasons the host had never executed the suspect code.
The harness removes all four.

1. **`-R` alone is not enough.** `libpkg/ncgrpw.c` `clgrnam()` /
   `clpwnam()` have their *entire body* inside
   `if ((instroot = get_install_root()) != NULL)`, then
   `fopen("<root>/etc/group")`. A fakeroot with no `etc/group` makes
   `clgrnam()` return `NULL` immediately, so
   `clgrnam -> dup_gr_ent` never runs.
   `tools/repo/repackage-stock.py` `install_test()` does exactly that
   (`os.makedirs(root)` then straight to `pkgadd -R`) — **that is the
   complete mechanical explanation for "host-unreproducible"**, and it
   needs no Amix-runtime magic.
   → **CONFIG B** seeds `<root>/etc/{passwd,group}` first.

2. **The host's `bin` group is memberless**, so `dup_gr_ent()`'s
   `gr_mem` duplication loop is skipped entirely. The box's group file
   has `bin::2:bin,daemon`.
   → both configs use the **real box fixtures**
   `../../compat/tests/amix-{passwd,group}.txt`, and the probe package
   is owned by multi-member groups only (`bin`, `sys`, `adm`).

3. **The box does not use glibc for these lookups.** `compat/` defines
   `getpwnam`/`getgrnam`/`fgetgrent`/`fgetpwent` as direct text parsers
   (the Amix libc-passwd sidestep, `AMIX-PORT.md` root cause 11).
   → the harness `LD_PRELOAD`s those parsers, **extracted from the
   current `compat/amixcompat.c`** so it can never test stale code.

4. **The shipped guard masks the failure.** `libpkg/verify.c` copies
   `group`/`owner` into terminated locals `gnam`/`onam` first.
   → build with `NOGUARD=1` to compile it out
   (`-DAMIX_NO_ATTR_GUARD`; diagnosis builds only).

## Running it

```sh
cd heirloom
SANITIZE=1 NOGUARD=1 ./build-host.sh
./tests/host-altroot/run.sh
```

Exit `0` = ran clean (no reproduction) · `1` = harness failed to
exercise the path (result would be vacuous — it says so) · `2` = a
sanitizer finding or a signal, i.e. **the bug reproduced**.

The harness builds its own throwaway `ALTRT` package with `pkgmk`, so it
depends on nothing gitignored (no tape extract, no `build/repo-staging`).

Both alternate-root shapes are run, because **it is not recorded
anywhere what the box's `-R` target actually contained** — and that
decides which code path the box took:

| | `<root>/etc/group` | Path taken |
|---|---|---|
| **CONFIG A** | absent | `clgrnam()` `fopen` fails → falls through to compat `getgrnam()` against the real `/etc/group` |
| **CONFIG B** | seeded | `clgrnam()` → `dup_gr_ent()` runs |

## Evidence (2026-07-19)

Host: x86-64 glibc, gcc 15, `-fsanitize=address,undefined`, guard
compiled out, compat parsers preloaded, real box fixtures.

Harness run — both configs: `rc=0`, **4 `averify` `fix=1` entries**,
3 `clgrnam` calls, 3 `dup_gr_ent` calls **all multi-member**, **0
sanitizer findings**.

Also run against the 27 repackaged stock packages
(`build/repo-staging/stock`, gitignored) — `games`, `core`, `lp`, `net`,
`text`, both configs: **3588 `averify fix=1` entries and 66
`dup_gr_ent` calls per config, 30 of them multi-member, zero sanitizer
findings.** `core`/`text` return rc=2 for the unrelated reason that a
non-root user cannot `mknod` device nodes or write some modes.

The only sanitizer output at all is `verify.c:333` "load of misaligned
address … for type 'long unsigned int'" — the pre-existing, upstream,
`LINTED`-annotated word-at-a-time checksum loop. Unrelated; the harness
filters it.

### The control: ASan cannot see this bug class here

A deliberately injected fault (fill `ainfo->group` with 65 non-NUL
bytes just before the group check) did **not** crash and did **not**
raise a sanitizer finding. It produced a clean `cgrnam returned NULL` →
"bad group" → `rc=2`.

Two things follow, and they matter more than the negative result:

- **ASan is structurally blind to it.** The hypothesised overflow
  (`strcpy(ainfo->group, grp->gr_name)` running past `group[65]` into
  `major`/`minor`) is an **intra-object** overflow — past a member but
  still inside `struct cfent`. ASan places no redzones between struct
  members, so neither the corrupting write nor the over-long `strlen`
  read is visible to it. A clean ASan run does **not** exonerate that
  mechanism.

- **Host padding arrests the walk.** The injected `strlen` returned
  exactly 65 — it stopped in the padding. Measured host layout:

  ```
  sizeof(struct ainfo)=160   group @77 (ends 142)   major @144
  PADDING between group[64] and major = 2 bytes
  ```

  Those 2 pad bytes were zero, so an unterminated `group` terminated
  harmlessly before it ever reached `major`/`minor`.

## REFUTED: the padding-asymmetry hypothesis

An earlier revision of this file *inferred* that gcc/m68k 2-aligns
32-bit scalars, putting `major` at 138 with **zero** padding, and
concluded the host "cannot reproduce this by construction". **That was
wrong.** Measured with the real toolchain
(`m68k-cbm-sysv4-gcc`, GCC 2.7.2.3, target sysroot, heirloom's exact
`struct ainfo`, `offsetof` emitted as initialized data so the compiler
answers rather than a running program):

```
sizeof(struct ainfo) = 148
offsetof(owner) =   8
offsetof(group) =  73     -> group[] ends at 138
offsetof(major) = 140
offsetof(minor) = 144
PAD between group[] end and major = 2
```

Stable across flag sets (layout is ABI, not optimization):

| flags | sizeof | owner | group | major | minor | PAD |
|---|---|---|---|---|---|---|
| `-O2` | 148 | 8 | 73 | 140 | 144 | **2** |
| `-O0` | 148 | 8 | 73 | 140 | 144 | **2** |
| *(bare)* | 148 | 8 | 73 | 140 | 144 | **2** |
| `-O` | 148 | 8 | 73 | 140 | 144 | **2** |
| `-O2 -fpack-struct` | 146 | 8 | 73 | 138 | 142 | 0 |

`mk.config.amix:97` is `CFLAGS=-O` and `-fpack-struct` appears nowhere
in the tree, so **PAD=2 is what ships**. Why the inference missed:
`major_t`/`minor_t` are `ulong_t` (sysroot `sys/types.h:60-61`) and
this target 4-aligns 4-byte scalars, so 138 rounds up to 140.

**m68k and the host have the same 2 pad bytes.** There is no layout
asymmetry, and "PAD=0 → straight into 8× `0xFF`" is not the mechanism
on either platform.

Re-runnable as `./ainfo-layout.sh` (prints host and m68k side by side;
asks the compiler, so no box and no m68k runtime are needed). Kept so
the next round cannot re-derive the same wrong inference.

## Also unsupported: the padding-*contents* hypothesis

The natural successor — same layout, but the 2 pad bytes hold garbage
on the box where they happened to be zero on the host — does not
survive tracing the actual allocation path either. **Static analysis
only; not disproved on hardware.**

The `cfent` that `averify(fix=1)` sees on a `pkgadd` install arrives
via `pkginstall/instvol.c` as `ept = &(extlist[i]->cf_ent)`, and
`extlist` is built in `libinst/pkgobjmap.c` `pkgobjmap()`:

```c
struct cfent *ept, map_entry;
...
(void) memset(&map_entry, '\000', sizeof (struct cfent));   /* zeroes padding */
n = gpkgmapvfp(&map_entry, vfp);
...
ept = &(ext->cf_ent);
(void) memcpy(ept, &map_entry, sizeof (struct cfent));      /* copies padding */
```

`memset` zeroes the whole `cfent` — padding included — at the top of
**every** loop iteration, and the whole-struct `memcpy` carries those
zero pad bytes into the arena slot. So the padding is deterministically
zero regardless of how the arena itself was allocated.

Every field writer on that path is bounded and always NUL-terminates:

| site | mechanism | verdict |
|---|---|---|
| `gpkgmap.c:832-841` `getstrvfp(..., ATRSIZ, ...)` | `len < n` → copy+NUL, else `n-1`+NUL | bounded |
| `gpkgmap.c:614-615` | `strlcpy` with `sizeof` | bounded |
| `srchcfile.c:1079-1081` `getstr(..., sizeof(field), ...)` | same shape | bounded |
| `pkgdbmerg.c:1248,1256` `strcpy(el_ent…group, cf_ent…group)` | unbounded **but** source comes from `srchcfile` `getstr`, always terminated | safe in practice |

So: if the box's padding really is non-zero, something outside this
path put it there — and naming that is the open question.

### Latent unbounded writers found while tracing (NOT this crash)

Worth fixing on their own merits; none can fire on the failing path.

- **`libpkg/mappath.c:206` `mapvar()`** — a completely unbounded
  in-place expansion: `while (*token) *varname++ = *token++;` where
  `token` is an arbitrary-length `getenv()` value and `varname` is a
  `char[65]` attribute field. Reachable from `gpkgmap.c:850,857` and
  `pkgchk/ckentry.c:99,100` whenever a pkgmap owner/group is `$VAR`.
  **Cannot be this crash:** across all 27 repackaged stock packages,
  **0 of 28,919 pkgmap entries** have a parametric owner or group.
- `libpkg/verify.c:893,940` — `strcpy(ainfo->group, grp->gr_name)`,
  unbounded from the group file; only in the `setval`/`BADGROUP`
  branch. Box group names are short.
- `libinst/procmap.c:393,399` — `strcpy` field→field, safe only while
  the source is terminated.
- `pkgcmds/pkgadm/pkgadm_special.c:299,300` —
  `strncpy(dst, src, ATRSIZ+1)` into `char[65]` can leave it
  **unterminated**. Not shipped: `pkgadm` is in neither
  `build-host.sh` nor `build-amix.sh` `SUBDIRS`.
- `libinst/pkgdbmerg.c:772,775` — unbounded, but inside `#if 0`.

## What to run on the box next

1. **Record what the failing `-R` target actually contained** —
   specifically whether `<root>/etc/group` existed. **Nothing in this
   repo documents it**, and it decides which function the box was even
   in: with no `<root>/etc/group`, `clgrnam()` returns `NULL`
   immediately and v15–v17 were instrumenting a function the box never
   entered. It also decides whether a contents DB was present to drive
   `pkgdbmerg` at all. This is the highest-value unknown.
2. **Dump the 2 padding bytes** at `ainfo+138..139` alongside the
   existing `group bytes=[...] firstNUL=` output, for the faulting
   entry. That directly discriminates the padding-contents hypothesis:
   non-zero padding supports it, zero padding kills it.
3. Capture the existing `DS_DEBUG(averify): group bytes=[...]
   firstNUL=` dump for the faulting entry — it separates "corrupt
   field" from "corrupt `ainfo` pointer".

**Layout is settled — do not spend box time re-measuring it.**
