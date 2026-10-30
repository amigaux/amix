# The `full` set vs s5's 14-character names — decision brief

**Status: DECISION PENDING.** This document measures the problem and recommends
one option. Nothing in `sets.conf`, the catalogs or the packages has been
changed. Raised by `amix-installng` W6 (2026-08-12), when `cd-full` became the
first run ever to lay down all thirty packages and `gnusrc2` failed with `rc=2`.

> **UFS-only packages are exempt (2026-10-30).** Under the owner's decision P-35
> Option C, UFS is the only filesystem for new installs and s5 stays readable. A
> package whose pkginfo carries **`APKG_FSTYPE=ufs`** (the UFS-only mark,
> [design.md §2b](design.md)) may hold basenames over 14 bytes and names that
> share their first 14 bytes in one directory: apkg refuses it on s5 instead of
> letting s5 cut its names. The 14-byte rule below therefore binds only
> **unmarked** packages. `s5-collision-scan.py` names the marked packages it
> scans and reports a collision group made only of their objects as exempt (it
> does not fail `--fail-on-collision`); its counts and pinned constants are
> unchanged. The stock packages measured here are unmarked, and everything below
> about them still holds for a box that keeps an s5 root.

---

## 0. Executive summary

| | |
|---|--:|
| collision groups in `full` — **installng W6 reported** | 3 |
| collision groups in `full` — **actually** | **5** |
| colliding objects | **10** |
| minimum objects to drop for a clean `full` | **5** |

The W6 scan was **directory-blind**: it keyed groups on the truncated *basename*
alone, so the two `amixInitExt*` pairs that exist in **two** directories
(`WORK/` and `ZAPHOD/`) each collapsed into one row. Its three rows name the
right six *filenames*, but the fix is per-path, and there are ten paths.

**This matters operationally.** `docs/installer.md` proposes "exclude the four
files". Dropping four files leaves `ZAPHOD/` broken and `full` still
unattestable — the bench would burn another `cd-full` cycle to discover it.

**Recommendation: Option A** — drop five objects from two packages, re-mint only
those two, and attest `full` at **28,704 objects**. Four of the five drops are
provably zero-loss (byte-identical duplicates of a file that still ships); the
fifth costs one 16,896-byte build transcript.

---

## 1. What the colliding files actually are

Both packages are source archives, and **all ten objects are build droppings** —
artifacts of the 1991 packagers' own build trees that were swept into the
shipped tarballs. None is required to build or use anything.

### 1.1 `gnusrc2` — `/usr/src/pub/gnu/gcc_2.0/typescript.stage{1,2}`

Literal `script(1)` transcripts of the GCC 2.0 three-stage bootstrap, captured
on Commodore's build host `fishpond` in March 1992. First and last lines:

```
Script started on Fri Mar  6 08:25:59 1992      <- typescript.stage1
fishpond:1> gnumake CC=/usr/local/bin/gcc
...
script done on Fri Mar  6 10:59:59 1992

Script started on Fri Mar  6 16:53:52 1992      <- typescript.stage2
fishpond:1> gnumake CC=stage1/gcc D CFLAGS="-g -O4 -Bstage1/"
...
script done on Sat Mar  7 07:35:11 1992
```

The same directory also holds a plain `typescript` (the third session, `gnumake
stage2`, Mar 7) and six other GNU packages ship one each. `typescript` is 10
characters and never collides — **only the two `.stageN` files do**, because
both truncate to `typescript.sta`.

**Verdict: incidental cruft.** Historically mildly interesting, functionally
inert. This is the only place where a drop costs real information.

### 1.2 `X11r5src` — `amixInitExt{DMI,Mono}.{c,o}` in `WORK/` and `ZAPHOD/`

`/usr/x11r5/server/ddx/amix/` is the Amix X server DDX. Beside the real source
it ships two stale scratch copies, `WORK/` (Dec 31 1991) and `ZAPHOD/`
(Dec 24 1991), each carrying every `.c` **plus its compiled `.o`**, plus
`libamix.a`, plus `Makefile.bak`. The maintained tree — `amix/` itself, whose
`Makefile` is a month newer (Feb 20 1992) — contains **no `.o`, no `libamix.a`,
and no `amixInitExt*` at all.**

The `.c` files are not source. They are **build-time-generated intermediates**.
The shipped `Imakefile` says:

```
ObjectFromSpecialSource(amixInitExtMono,../mi/miinitext,-UPEXEXT)
ObjectFromSpecialSource(amixInitExtDMI,../mi/miinitext,-UPEXEXT)
```

which expands in the generated `Makefile` to:

```make
amixInitExtDMI.c:  ../mi/miinitext.c
	$(RM) $@
	$(LN) $? $@
...
clean::
	$(RM) amixInitExtDMI.c
```

— i.e. `make` creates them from `../mi/miinitext.c` and `make clean` deletes
them. Confirmed by content:

| object | md5 | note |
|---|---|---|
| `mi/miinitext.c` | `98aeee4fe3f5b3ea7265594df55819a8` | the real source, ships in the same package |
| `WORK/amixInitExtDMI.c` | `98aeee4fe3f5b3ea7265594df55819a8` | **byte-identical copy** |
| `WORK/amixInitExtMono.c` | `98aeee4fe3f5b3ea7265594df55819a8` | **byte-identical copy** |
| `ZAPHOD/amixInitExtDMI.c` | — | a **symlink** to `../mi/miinitext.c` |
| `ZAPHOD/amixInitExtMono.c` | — | a **symlink** to `../mi/miinitext.c` |
| `WORK`/`ZAPHOD` `amixInitExtDMI.o` | `7b9d25f47a323fedd1a1e31c6199cfe8` | identical in both dirs |
| `WORK`/`ZAPHOD` `amixInitExtMono.o` | `dfb44d2981e919185478f5ae8649ee9f` | identical in both dirs |

**Verdict: incidental cruft, and the `.c` side is zero-loss to drop** — its
bytes ship anyway as `mi/miinitext.c`, and `make` regenerates it on demand.

### 1.3 The five groups, enumerated

| # | directory | truncates to | members (ftype) | package |
|---|---|---|---|---|
| 1 | `/usr/src/pub/gnu/gcc_2.0` | `typescript.sta` | `typescript.stage1` (f), `typescript.stage2` (f) | `gnusrc2` |
| 2 | `.../ddx/amix/WORK` | `amixInitExtDMI` | `amixInitExtDMI.c` (f), `amixInitExtDMI.o` (f) | `X11r5src` |
| 3 | `.../ddx/amix/WORK` | `amixInitExtMon` | `amixInitExtMono.c` (f), `amixInitExtMono.o` (f) | `X11r5src` |
| 4 | `.../ddx/amix/ZAPHOD` | `amixInitExtDMI` | `amixInitExtDMI.c` (**s**), `amixInitExtDMI.o` (f) | `X11r5src` |
| 5 | `.../ddx/amix/ZAPHOD` | `amixInitExtMon` | `amixInitExtMono.c` (**s**), `amixInitExtMono.o` (f) | `X11r5src` |

Groups 4 and 5 are the ones W6 missed. They are *symlink vs regular file* — the
nastier shape, since the two objects are not even the same type.

---

## 2. Why it fails, exactly

`heirloom/pkgcmds/pkginstall/cppath.c` `write_file()`:

```c
if (access(a_file, F_OK) == 0) {
        len = snprintf(loc_link, sizeof (loc_link), "%sXXXXXX", a_file);
        ...
        fd = mkstemp(loc_link);
        if (fd == -1) {
                progerr(ERR_MKTEMP, loc_link, errno, strerror(errno));
```

Installing `typescript.stage2` after `typescript.stage1`:

1. `access()` succeeds — the dirent `typescript.sta` is already there.
2. pkgadd therefore takes the *transparent replace* path and builds the
   template `.../typescript.stage2XXXXXX` — basename **23 characters**.
3. s5 truncates that to `typescript.sta`. **Every one of `mkstemp`'s candidate
   names truncates to the same dirent**, which exists, so each `O_EXCL` create
   returns `EEXIST` and `mkstemp` fails.
4. `ERR_MKTEMP` fires. The `<>` in the bench log is `mkstemp` having emptied the
   template on failure — the fingerprint of exactly this path.

The verification error that precedes it is the same collision seen from the
other side: `stage2`'s bytes are sitting in `stage1`'s dirent, so the size/cksum
check against `stage1`'s pkgmap line fails (`20540/22542` expected — stage1's
declaration; `16896/52794` actual — stage2's).

### 2.1 The general rule this exposes

The template is `basename + "XXXXXX"`. On a 14-character filesystem:

| `len(basename)` | X's surviving truncation | consequence |
|---|--:|---|
| ≤ 8 | 6 | normal |
| 9 – 13 | 5 … 1 | reduced entropy, still works |
| **≥ 14** | **0** | template ≡ the file being replaced ⇒ **guaranteed `EEXIST`** |

**On s5, heirloom pkgadd cannot overwrite an existing file whose basename is ≥ 14
characters.** In the `full` set that is **572 distinct objects**; in `minimal`
and `standard` it includes real, shipped files — `/usr/apkg/doc/OPENSOLARIS.LICENSE`,
`/usr/apkg/bin/amix-sadm-migrate`, `/etc/inet/network-config`,
`/usr/lib/libsockhost.so`, and ~130 in `sysadm`/`man`/`terminfo`.

**Fresh installs are safe, and that is provable, not lucky.** The branch is only
entered when the target already exists. Across all thirty packages there are 109
paths declared by more than one package, but **94 are directories** (which take
the `mkdir` path, not `write_file`) and **all 15 shared non-directories have
basenames of 3–8 characters** — zero at risk. That is precisely why
`minimal`/`standard`/`developer`/`x11` attested clean.

It bites on **re-install and upgrade** — i.e. `apkg upgrade` over an installed
box. That is a live defect for this repo, independent of the `full` decision,
and is filed as a follow-up rather than folded into it.

> **FIXED 2026-08-14 in the engine** (`heirloom/pkgcmds/pkginstall/cppath.c`,
> new `temp_template()`): the template now uses at most 8 bytes of the target
> basename plus the six X's, so the X's survive truncation instead of being
> eaten, and the temporary still lands in the target's own directory for the
> `rename(2)`. Red/green regression in `heirloom/tests/s5-14char/` (24 checks,
> an LD_PRELOAD s5 simulator; the upstream template must still fail with the
> bench's `<>` fingerprint). Rationale and limits: `heirloom/AMIX-PORT.md`,
> "s5 14-character names". This removes the ERR_MKTEMP failure — it does
> **not** remove the aliasing of two distinct names onto one dirent, which is
> what the rest of this document decides. **The deployed `/usr/apkg` engine on
> the box predates the fix**; it lands with the next APKGENG mint.

---

## 3. Reproducing the scan

W6's scan was ad-hoc and left no tool — only prose. The algorithm below
reproduces every number in this document from the published `.pkg` files, and
**is now implemented as `tools/repo/s5-collision-scan.py`** (2026-08-14):

```
python3 tools/repo/s5-collision-scan.py --check -s full <local-mirror-of-the-repo>
```

re-derives all seven pinned quantities from the datastreams and fails if any
of them moves; `-s <set>` predicts any set's object count (§3.1); its own
regression case is `tools/repo/tests/run-tests.sh` T17, whose synthetic
fixtures contain both shapes the basename-only key gets wrong (a merged pair
and an invented one).

1. For each package, take the pkgmap out of the datastream: skip the 512-byte
   header block, read the first cpio archive (`dd bs=512 skip=1 … | cpio -idm`).
2. Parse each pkgmap line: optional leading part number, then `<ftype> <class>
   <path>`. For `s`/`l`, the path is the part before `=`. **Skip `i` lines** —
   those are control files and never enter the target tree.
3. **Object universe** = distinct paths, all ftypes.
   **Truncation universe** = the same, minus `b`/`c`/`p` (device nodes and
   pipes, which s5 stores as dirents but which W6's count excluded).
4. Group by **`(dirname, basename[:14])`**. A group with more than one distinct
   path is a collision. *Keying on `basename[:14]` alone is the W6 bug.*

Regression constants for the thirty published packages:

| quantity | value |
|---|--:|
| truncation universe (matches W6's "distinct paths") | **27,876** |
| basenames > 14 characters | **147** (W6 said 152 — unreconciled, see §7) |
| basenames ≥ 14 characters | 572 |
| **collision groups, keyed per directory** | **5** |
| collision groups, keyed on basename alone (the W6 bug) | 3 |
| object universe (= the contents-DB object count) | **28,709** |

### 3.1 The object count is computable host-side

W6 believed the installed object count could only come off the guest, and put
the pkgmap-sum over-count at 1.6–1.7 %. In fact the relationship is exact:

> **contents-DB object count = number of distinct paths across the set's
> pkgmaps** (all ftypes, `i` excluded).

Verified against all four attested references, with no residual:

| set | distinct pkgmap paths | attested objects | Δ |
|---|--:|--:|--:|
| `minimal` | 4,859 | 4,859 | 0 |
| `standard` | 11,012 | 11,012 | 0 |
| `developer` | 11,497 | 11,497 | 0 |
| `x11` | 11,546 | 11,546 | 0 |

W6's "Σ pkgmap objects" figures are the *entry* counts plus one `i` line per
package (4,929 + 8 = 4,937; 11,187 + 17 = 11,204) — so both numbers reconcile,
and the gap between them is pure de-duplication of shared directories.

**Consequence: the object count of any proposed `full` can be predicted exactly
before a bench run.** The md5 digest still requires the guest, because it is a
function of pkgadd's merged contents DB and the target name service.

---

## 4. The options

Loss figures are against `full` = 28,709 objects / 276.1 MiB of payload.

| | option | objects lost | payload lost | re-mint | bench | verdict |
|---|---|--:|--:|---|---|---|
| **A** | drop the colliding objects | **5** (0.017 %) | 21,536 B (0.007 %) | 2 pkgs | 1 × `cd-full` | **recommended** |
| B | drop `gnusrc2` + `X11r5src` from `full` | 6,521 (22.7 %) | 93.6 MiB (33.9 %) | none | 1 × `cd-full` | rejected |
| C | accept known losses | — | — | none | — | **not available** |
| D | rename the colliding files | 0 | 0 | 2 pkgs | 1 × `cd-full` | rejected |

### A — drop the colliding objects

`repackage-stock.py` already has the mechanism: `write_prototype()` skips any
member in `excluded_set`, so the object leaves the prototype and `pkgmk` never
sees it — absent from both pkgmap and payload. Today that set is populated
*structurally* (paths containing whitespace, `=` or `$`, which `prototype(5)`
cannot represent — this is how `MacFS/TrueType Fonts` is already dropped
tape-wide). Option A adds an **authored** exclusion list alongside it, in the
same style as `deps.conf` / `cats.conf` / `sets.conf`.

### B — drop the two packages

`full` stops meaning "everything we ship" while losing a third of the
distribution and the two largest packages on the tape. It also does not make the
underlying content installable — it hides it. Rejected.

### C — accept known losses

**This option does not exist as described.** "Last-write-wins with a manifest
note" presumes pkgadd tolerates the overwrite. It does not: the bench shows
`Installation of <gnusrc2> partially failed`, `rc=2`, and `install.sh: WARNING:
FAIL gnusrc2`. A set that reports FAIL twice cannot be attested, and a
partially-installed package leaves the contents DB in a state no digest should
be minted from. Rejected on evidence.

### D — rename

Format-legal — `pkgadd` does not care what a file is called, so 1991
compatibility is intact — and it costs the same re-mint as A. It is rejected on
two other grounds:

1. **Fidelity.** This project's value is faithful repackaging. Shipping
   `typescript.st2`, a filename Commodore never wrote, is a worse lie than
   shipping 29 of 30 transcripts and saying so.
2. **It does not work for the X11 pairs.** The `.c` is regenerated by `make`
   under its canonical name. Renaming the shipped copy leaves a dead file *and*
   the collision returns the moment anyone builds.

---

## 5. The recommendation

**Option A, dropping exactly five objects**, chosen per group as "the member
that is recoverable from what remains":

| group | drop | why it costs nothing |
|---|---|---|
| 1 | `/usr/src/pub/gnu/gcc_2.0/typescript.stage2` | *costs 16,896 B* — the one real loss. `stage1` survives and stays readable (see below). |
| 2 | `.../WORK/amixInitExtDMI.c` | byte-identical to `mi/miinitext.c`, which still ships; `make` regenerates it |
| 3 | `.../WORK/amixInitExtMono.c` | as above |
| 4 | `.../ZAPHOD/amixInitExtDMI.c` | a symlink to `mi/miinitext.c`, which still ships |
| 5 | `.../ZAPHOD/amixInitExtMono.c` | as above |

Dropping the `.c` side rather than the `.o` side is a single stateable rule —
*drop the generated intermediate, keep the artifact that is not reconstructible*
— and it leaves both compiled objects present in both directories.

The surviving `typescript.stage1` lands on disk as the dirent `typescript.sta`
and remains fully accessible, because the s5 kernel truncates on **lookup** as
well as on create — the same round-trip that makes the other 146 over-long names
harmless.

Simulated and verified: **collision groups 5 → 0**, objects 28,709 → **28,704**.

### 5.1 Exactly what changes where

| file | change |
|---|---|
| `tools/repo/excludes.conf` *(new)* | five paths + rationale, in `deps.conf` style |
| `tools/repo/repackage-stock.py` | read it; union into the existing `excluded_set`; report authored vs structural exclusions separately in `--scan` |
| `tools/repo/tests/run-tests.sh` | a case asserting the five paths are absent from the two pkgmaps, and a scan asserting `full` has zero collision groups |
| `pkgs/stock/gnusrc2-2.1.pkg`, `pkgs/stock/X11r5src-2.1.pkg` | re-minted (`--only gnusrc2,X11r5src`) |
| the catalog | 2 of 30 md5/size fields move ⇒ new `catalog.md5` (was `edeba578b73fc892f3c8c5ede603aca7`) |
| `docs/design.md`, `NOTES.md` | record the exclusion mechanism |

**Blast radius is contained, and this is the strongest argument for A.**
`gnusrc2` and `X11r5src` are named in no set but `full` (`sets.conf:69`), so the
attested digests for `minimal`, `standard`, `developer` and `x11` **do not
move**. The other 28 packages are not re-minted and keep their published md5s.

One caveat on re-minting: `pkgmk` stamps `PSTAMP=<host><timestamp>` into
`pkginfo`, so a re-mint is *never* byte-reproducible. This costs nothing here
(the content is changing anyway) but it is why the re-mint must be scoped with
`--only` — re-minting all 27 would churn 27 published md5s for no reason.
`PSTAMP` does not perturb the attested digest: `pkginfo` is an `i` object and
`i` objects are not recorded in the contents DB (which is exactly why the §3.1
identity holds with `i` excluded).

### 5.2 The attestation flow

1. Land the exclusion + re-mint the two packages; regenerate and publish the
   catalog.
2. Re-master the `cd-full` medium.
3. Run `install-matrix.sh --cell cd-full --attest-set`. **Predicted object count
   28,704** — if the run reports anything else, stop: the harness or the
   exclusion is wrong, not the prediction.
4. Record the measured digest in **both** `tools/install-matrix.sh` `SET_REFS`
   *and* `tools/build-install-iso.sh` `ATTESTED_SETS` — `installer-selftest`
   audit X4 cross-checks them bidirectionally and fails on either alone.

Both files are in `amix-installng`; this repo owns steps 1–2 only.

---

## 6. Two things this decision does not fix

**The X11R5 amix server cannot be built on s5 as shipped.** `make` in
`.../ddx/amix/` creates `amixInitExtDMI.c` and then `amixInitExtDMI.o` in the
same directory — both truncate to `amixInitExtDMI`. This is intrinsic to the
Imakefile and hits the *maintained* directory, not just the scratch copies. No
packaging decision can fix it; the workaround is a longer-named filesystem or a
patched Imakefile, and it should be documented rather than silently shipped.

**UFS exists on Amix 2.1 and would dissolve this entire problem class.** The
`core` package ships the full ufs userland (`/usr/lib/fs/ufs/{mkfs,fsck,mount,
tunefs,ufsdump,ufsrestore,…}`) and `conf` ships the kernel side —
`/usr/sys/fs/ufs` (relink objects + `exp`) and `/usr/sys/master.d/ufs`. UFS has
255-character names and no 65,535-inode ceiling, so it would retire this
collision, W6's `firstboot.conf.new` case, the RAW payload rename gate, the
inode ceiling, *and* §2.1's upgrade defect at once.

**This is a flag, not a recommendation.** Whether the shipped install kernels
actually carry ufs in their `vfssw`, and whether the boot chain can carry a ufs
root, are unverified here and belong to `amix-kerntools` / `amix-installng`. The
s5-only installer was a locked user decision. It is recorded because the cost of
*not* knowing ufs was on the table is higher than the cost of asking.

---

## 7. Open discrepancy

W6 counted **152** over-long basenames; this scan counts **147** over the
identical 27,876-path universe (which reproduces exactly, so the input sets
agree). Neither counting variant tried here — entries vs distinct paths, with or
without link sources, with or without `i` lines — yields 152. The gap does not
affect the decision: over-long names that do not collide are harmless by the
lookup-truncation round-trip. It is recorded so nobody treats 152 as
reproducible.
