# Design: engine port, apkg client, fsck, migration, repo tools

Working spec for the deliverables in [requirements.md](requirements.md). Bench facts it builds on:
[NOTES.md Session 3](../NOTES.md). Target: Amix 2.1c (SVR4.0 m68k), gcc 2.7.2.3 (gnu89), pre-POSIX
`/bin/sh`, BSD sockets via `-lsocket -lnsl`, native cpio `-c` = 070701, plain HTTP only.

## Source tree

```
heirloom/            vendored SVR4 pkg engine + Amix port (mk.config.amix, compat/, sslstub/)
src/apkg/            the remote catalog client (C89, fresh, MIT)
src/contents-fsck/   standalone contents DB checker/repairer (C89, fresh, MIT)
tools/migrate/       one-time /var/sadm migration script (pre-POSIX sh)
tools/repo/          host-side catalog generator + publisher (python3/sh, runs on Linux)
docs/                design docs & findings
research/            dive artifacts (read-only reference)
```

Toolchain: `. <gcc-cross-amix>/build/env.sh` → `m68k-cbm-sysv4-gcc`
(sysroot already populated). Host builds use plain `gcc -std=gnu89` for parity testing.

## 1. Heirloom engine port (`heirloom/`)

Cross-build the trimmed suite for Amix. Target binaries (priority order):
1. Read/transport set: `pkginfo pkgparam pkgtrans` (+libs)
2. Write set: `pkgadd`+`pkgask`, `pkgrm`, `installf`+`removef`, helpers `pkginstall`, `pkgremove`
3. Nice-to-have: `pkgchk`, `pkgmk`, `pkgproto`, valtools; man pages ship regardless

Patch set (all validated in the dive; artifacts under `research/heirloom/`):
- **tolerant parser** (`libpkg/srchcfile.c`, 36-line re-join — spaces in pathnames parse correctly;
  validated 0 errors over the real 28,644-record DB)
- **VERSION relaxation**: keep pkgadd's add-time requirement (catalog pkgs have VERSION), but
  (a) `pkginfo.c` report(): missing VERSION → print `(none)` instead of aborting the listing,
  (b) `getinst.c:120` NULL-guard (upgrade-over-VERSION-less segfault)
- **cpio**: drop `D` from `-icdumD`/`-ictD` (dstream.c:499,673,720) — hygiene (bench tolerates -D)
- **de-OpenSSL**: sslstub headers + nokeystore.c replacing keystore.o/security.o (recipe proven);
  delete `pkgweb.c` web-install paths that need it or stub minimal symbols
- **bug hygiene**: pkginfo.c:285 `path[128]`→bigger+snprintf; verify.c reperr off-by-one;
  fixpath.c mkpath string-literal write (pre-create dirs anyway); pkgops.c:1354 assert typo;
  spmizones_api.h:225 C99 variadic macro → plain macro
- **build**: `mk.config.amix` (CC=m68k-cbm-sysv4-gcc, BINDIR=/usr/bin, SADMDIR=/usr/sadm,
  VSADMDIR=/var/sadm, LIBS=-lsocket -lnsl where needed); delete redhat -I in libadm/Makefile.mk;
  pre-generated `scriptvfy.c` (flex, host) so no lex needed; compat/ shim library:
  snprintf/vsnprintf (C99 return + %lld), LFS64 mapping (stat64 etc. + `O_LARGEFILE 0`),
  strcasecmp/strncasecmp, fnmatch (BSD), libintl.h identity stubs, wchar mini-shim, mkstemp if
  missing, dirfd macro
- Install layout on Amix: binaries under **/usr/apkg/bin** + helpers under
  **/usr/apkg/sadm/install/bin** (parallel SADMDIR — never overwrite stock /usr/sadm/install/bin
  or the factory admin file). `/var/sadm` stays the shared DB.

Acceptance: on the guest — `pkginfo -l` against the live DB (with corrupt line present) lists all
31 packages; `pkgtrans` datastream↔directory round-trip interoperates with stock; `pkgadd` then
`pkgrm` of a test package leaves `contents` byte-sane and stock tools still working.

## 2. apkg — the remote client (`src/apkg/`)

Single C89 binary, MIT, ~2–3k LOC, links `-lsocket -lnsl`. Verbs:

```
apkg update                  fetch <repo>/catalog -> /var/apkg/catalog (tmp+rename)
apkg list [installed|all]    catalog entries, with installed-version column
apkg search <substr>         case-insensitive match on name|description
apkg info <name>             full catalog entry + installed state
apkg download <name>         fetch <repo>/pkgs/<filename> into cache, md5-verify
apkg install <name>...       resolve deps (recursive, topological) -> download -> pkgadd each
apkg upgrade <name>          if catalog version > installed: download, pkgrm old, pkgadd new
apkg remove <name>           pkgrm wrapper
apkg version                 client version
Options: -n dry-run, -f force (reinstall same version), -v verbose, -c <conffile>
```

- **Config** `/etc/apkg.conf` (plain `key=value`, `#` comments):
  `repo=http://pkg.amigaux.org` · `cachedir=/var/apkg/cache` · `pkgadd=/usr/apkg/bin/pkgadd`
  (fallback `/usr/sbin/pkgadd`) · `admin=/var/apkg/admin` · the nine fetch keys · the three
  resolver keys (`nameserver`, `dns_timeout`, `dns_retries`)
- **Catalog format v1** — pipe-delimited text, `#` comments, one package per line:
  `name|version|pkginst|filename|md5|size|deps|category|description[|offset]`
  deps = comma-separated `name`s or `none`. No pipes in any field; spaces allowed only in
  description. Header line `#apkg-catalog 1` required. The 10th field, `offset`, is **optional**:
  a decimal byte offset the RAW source (below) addresses the package by; a 9-field line (every
  HTTP/FILE catalog) leaves it unset and the RAW source fails closed on such an entry.
- **Extension blocks** — a line beginning with `#` is a *comment* in catalog v1, skipped by every
  conforming parser (`src/apkg/catalog.c` has skipped them since the first apkg commit `4992a67`,
  so every binary ever built tolerates them). On that basis the generator may append, as a
  **trailer after all entry lines**, one or more extension blocks: a header line
  `#ext <name> <version>` followed by that extension's `#<name> <key> <value>` lines. One exists
  today — `isize`: `#ext isize 1`, then one `#isize <catalog-name> <bytes>` line per package in
  entry order, giving the **installed size in bytes**, summed from the package's pkgmap(4) sized
  objects (ftypes `f`/`v`/`e` plus `i`). Blocks are **opt-in** (`gen-catalog.py --isize`; without
  the flag the catalog is byte-for-byte what it always was) and invisible to a v1 field parser, so
  they need no format-version bump and cost no field. A second one, `fstype` (section 2b), lists the
  UFS-only packages; it is not opt-in but appears only when a package is marked. (Historical note: opt-in was load-bearing
  while a non-conforming consumer existed — `amix-installng`'s `isocheck.parse_catalog` originally
  did not skip `#` lines. That parser conforms since installng W3b, 2026-08-11, and the ISO path
  now passes `--isize`; no known non-conforming consumer remains.) A package whose pkgmap cannot be summed gets
  **no** `#isize` line at all (plus a stderr warning): **absence means unknown, never zero** — a
  consumer must treat a missing line as "unknown", not as "free". The figure is a payload byte
  sum, **not** the s5 on-disk footprint (1 KB blocks + indirect blocks + directories): measured
  against the Amix 2.1 tape index the sums run ~0.92 of the tape's own block accounting (~1.08×
  the other way), so a free-space consumer should budget **~1.10×**, not the bare sum.
- **Version compare**: split on `.`/`-`; numeric segments compare numerically, else strcmp;
  missing segments = 0. (Documented, used by upgrade + install skip.)
- **Installed state**: `/var/sadm/pkg/<pkginst>/pkginfo` exists → installed; VERSION= read from it
  (post-migration it exists; absent → "unversioned").
- **HTTP**: hand-rolled HTTP/1.0 GET, `Host:` header (virtual host!), `Connection: close`,
  follows one 301/302, times out (alarm()), streams to file, supports `http://host[:port]/path`.
- **Name resolution** (`src/apkg/dns.c`): stock Amix has **no resolver** — `gethostbyname` reads
  `/etc/inet/hosts` and nothing else, `resolv.conf` is inert — and the repository is a name-based
  virtual host, so on a stock box "no resolver" means "no repository" until a hosts line is
  hand-written. apkg resolves in three steps: IPv4 literal, then the host database
  (`gethostbyname`, unchanged), then its own **stub resolver** — one UDP A query per attempt,
  recursion requested, no EDNS, no cache, no search list, no TCP fallback, no `resolv.conf`,
  CNAME chain followed, TTLs ignored. Nameservers come from `nameserver=` in apkg.conf
  (repeatable, tried in order, **empty by default** = hosts file only), with `dns_timeout=` (5 s
  per attempt) and `dns_retries=` (2 per server). Hosts-first is deliberate: a box that resolves
  today cannot regress, and a hand-written line is never shadowed. Replies are validated hard
  (transaction id, QR/opcode, the echoed question, backwards-only compression pointers, every
  offset bounds-checked, class IN + rdlength 4 for an A) and anything else is discarded in favour
  of the next attempt/nameserver. It answers **apkg's own lookups only** — telnet/ftp still read
  the hosts file. Compiled only into the HTTP-capable build; `-DAPKG_NO_HTTP` drops it with
  http.c and the file `#ifdef`s itself out as well.
- **md5**: vendored public-domain implementation (Colin Plumb), big-endian-correct.
- **.Z transparency**: filename ends `.Z` → pipe through native `zcat` before pkgadd.
- **admin file** shipped at `/var/apkg/admin`: `instance=quit`, all checks `nocheck`, `action=nocheck`,
  `mail=`; install runs `pkgadd -n -a /var/apkg/admin -d <file> <pkginst>`.
- Exit codes: 0 ok, 1 usage/config, 2 network, 3 verify (also a malformed `APKG_FSTYPE`), 4 pkgadd/pkgrm failure, 5 dep cycle/missing (and the kernel-space pre-flight, and a UFS-only package on another filesystem, section 2b), 6 kbootset error (status 1/2, or not runnable), 7 kbootset refusal (status 3/4). Kernel space (apkg 0.3): NOTES.md 2026-10-25.
- Host-testable: builds with `gcc -std=gnu89` on Linux (sockets are portable); tests run against
  `python3 -m http.server` + a fake pkgadd shim.

### 2a. Package sources (Wave 3, `src/apkg/source.{c,h}`)

The `repo=` string is classified **explicitly** (no heuristics) into one of three sources; the
rest of apkg is source-agnostic. Classification lives in `src_open`; `http.c` stays an
HTTP-only client (its `http://`-only URL rejection is *correct* once classification moved up):

| `repo=` form | source | catalog fetch (`src_fetch`) | package stage (`src_stage`) |
|---|---|---|---|
| `http://host/path` | HTTP | GET `<repo>/catalog` | download → cache → md5 (`ephemeral`) |
| `file:///cdrom` or `/cdrom` | FILE | copy `<dir>/catalog` | plain `.pkg`: md5-verify **in place**, hand pkgadd the medium (no cache copy); `.pkg.Z`: zcat to cache |
| `raw:/dev/rdsk/...` | RAW | read fixed metadata region at offset 0 | `dd` the catalog's byte offset → cache → md5 |
| anything else | — | hard error (fail closed) | — |

`src_stage` is driven by **read cost**: a mounted `.pkg` is verified and installed in place (one
read, not three); a downloaded or `dd`'d datastream is cached. The "verify everything before
mutating anything" invariant is unchanged: `cmd_install` stages + md5-verifies **all** entries
before the first `pkgadd`.

The **RAW slice is self-describing**: a fixed metadata region at the front (catalog at 0,
`catalog.md5` at 32768, both NUL-padded) then package datastreams at 512-aligned offsets the
catalog records. `gen-catalog.py --raw` lays this out and packs a `raw.img`; the constants are
shared with `source.h`. This is what a tape / raw install slice looks like.

**`APKG_ROOT` vs `-R` — independent and composable.** `APKG_ROOT` (env) is the *client's* root
and prefixes only the compiled-in defaults (config, cache, engine paths). `-R <target>` (new) is
the *install target* root: it prefixes only the "is it installed?" DB (`/var/sadm/pkg`) and is
passed through to `pkgadd -R` — it deliberately does **not** move the engine (which runs from the
miniroot/CD and installs *into* the target; prefixing it would be the classic bootstrap bug).
The engine argv is byte-identical to before when `-R` is unset, and grows `-R <target>` when set.

### 2b. The filesystem a package needs: `APKG_FSTYPE` (UFS-only packages)

The owner's decision P-35 Option C (2026-10-30): UFS is the only filesystem for new installs, and
s5 stays readable. s5 cuts every directory entry at 14 bytes, so a package may now carry longer
file names if it says so; apkg then refuses it on s5. This section is the interface between the
packages' build (amix-packages `pkgroll`, which sets the mark) and this repository (apkg, which
enforces it, and the repo tools, which carry and report it).

**The mark.** One pkginfo(4) parameter in the package's own `pkginfo`:

```
APKG_FSTYPE=ufs
```

- **Value:** a comma-separated list of filesystem type names, as `statvfs(2)` `f_basetype` gives
  them (`ufs`, `s5`, `nfs`, ...). Each name is 1 to 15 characters of `[a-z0-9]` (`FSTYPSZ` is
  16); no spaces in the list (blanks around the value and one pair of quotes are tolerated, as
  for any pkginfo value). Today the packages emit exactly one value: **`ufs`**. A list such as
  `ufs,nfs` is valid, for a later package that is fine on either.
- **Meaning:** the package installs only onto a filesystem of one of the listed types. Absent
  means no requirement: the package installs anywhere, exactly as every package did before.
- **When a package carries it** (the rule for `pkgroll`): a package with **any object whose
  basename is over 14 bytes** carries `APKG_FSTYPE=ufs`. A package without one may leave it out,
  and then it must still pass the s5 rule (no basename over 14 bytes, no two names in one
  directory sharing their first 14 bytes). A marked package is exempt from the s5 rule: long
  names and 14-byte collisions are allowed in it (`docs/s5-14char-collisions.md` §0).
- **Where it lives:** the datastream's first archive, `<PKG>/pkginfo`, beside `APKG_DEPS` and
  `APKG_DESC`. The installed copy lands in `/var/sadm/pkg/<PKG>/pkginfo` like every other
  parameter.

**Every pkgadd ignores it.** An unknown pkginfo parameter is legal in pkginfo(4); stock and
heirloom pkgadd only export it to the install scripts' environment (a marked package has none).
So a marked package installs with stock `pkgadd -d` on a UFS root, unchanged, and our packages
already ship such parameters (`APKG_DESC` in every APKG/APKGENG since the first mint). The host
heirloom pkgadd installing a marked package is tested (`tools/repo/tests/run-tests.sh` T28). A
`pkgadd` by hand checks nothing: on s5 it installs the package with truncated names, as it
always would have.

**apkg's check** (`src/apkg/fsreq.c`, `fs_check()`). For `install` and `upgrade`, in the staging
phase (after the package is staged and verified, before the first `pkgadd` of the
transaction), apkg reads the staged datastream's `pkginfo`. Unmarked: nothing changes. Marked:

1. The value must be a well-formed list, else the package is refused, **exit 3**:
   `apkg: <name>: refused: APKG_FSTYPE=<value> is not a list of filesystem types`.
2. The directories checked are those of every pkgmap(4) object whose basename is over 14 bytes
   (relative pkgmap paths under `BASEDIR`; `i` lines are not objects), under the install target
   (`-R`). A package with no such object is checked at its install base, `<target><BASEDIR>`
   (`BASEDIR` from the same pkginfo, `/` when absent). Checking where the long names go, rather
   than `BASEDIR`, is what lets a perl-shaped package (`BASEDIR=/`, files under `/opt/amix`)
   install on an s5 root whose `/opt` is a mounted UFS slice.
3. Each directory is checked by its **nearest existing ancestor** (a directory the package
   creates lands on its parent's filesystem), `statvfs()` `f_basetype`. A type not in the list
   refuses the package, **exit 5**, before anything is installed, with one line:
   `apkg: perl: refused: it installs only on ufs, and /opt/amix/lib/perl5 is on s5, which cuts
   file names at 14 bytes`.

One refusal stops the whole transaction: in a dependency closure, nothing is added. An upgrade
refused this way leaves the installed version as it is. `-f` does not override the check. With
`-n` the check runs whenever the datastream is already readable (a mounted medium in place, a
cached download); a not-yet-downloaded HTTP package is checked on the real run. A file that is
not a readable datastream has no pkginfo to read, so pkgadd judges it, as it always has. The
host build has no `f_basetype` (Linux): there the type comes from the test-only environment
variable `APKG_TEST_FSTYPE` (`<dir>=<type>,...`, the longest matching directory wins) and is
`unknown` otherwise; the box build has no such variable.

**The catalog.** `gen-catalog.py` validates the mark exactly as apkg does (a malformed value
SKIPs the package) and, when any package is marked, lists them after the entries (after `--isize`,
before the kernel-space block):

```
#ext fstype 1
#fstype <catalog-name> <types>
```

Every line starts with `#`, so every catalog v1 reader skips it: apkg 0.1, 0.2.3 and 0.3.3 were
run against such a catalog and update, list and install as before (NOTES.md 2026-10-30). A
staging root without a marked package gives a byte-identical catalog. Nothing reads the trailer
yet: it is there for a reader that decides before fetching (an installer offering packages for a
target, a later apkg checking before a download). apkg's check needs no catalog support and
works from any source, FILE and RAW included.

**What an old client does.** apkg 0.1 to 0.3.3 do not read the mark: on s5 they install a marked
package with truncated names. The refusal reaches a box with the first APKG minted from this
source.

## 3. contents-fsck (`src/contents-fsck/`)

Standalone single-file C89 (no heirloom deps; own parser implementing the contents(4) grammar with
the tolerant re-join rule). Modes:
- `contents-fsck <file>` — report: line count, per-ftype counts, malformed records (with line
  numbers + reason), duplicated trailing pkg fields, sort-order violations, spaced pathnames.
- `contents-fsck -r <file>` — repair: writes `<file>.fixed` (tmp+rename discipline, never in
  place): dedupes duplicated pkg fields, normalizes field whitespace, preserves `#` comments.
  Spaced pathnames: **kept** by default (our tools tolerate them; the file on disk is real);
  `-s` strips such records (prints the affected disk paths so the user can rename first) for
  pure-stock-tool systems.
- `-b` also writes `<file>.bak` before any rename; exit 0 clean / 1 findings / 2 error.
Builds both host-side and cross (same source). Validated against `contents.factory` (28,646 lines).

## 4. Migration script (`tools/migrate/amix-sadm-migrate.sh`)

Pre-POSIX Bourne sh, runs on the box as root, idempotent:
1. Backup `contents` → `contents.pre-migrate` (once).
2. Append `VERSION=2.1` to every `/var/sadm/pkg/*/pkginfo` lacking VERSION= (bench-proven safe).
3. `mkdir` missing `/var/sadm/pkg/*/install` dirs (bnu, face, intf_install, nsu).
4. `chmod 644 /var/sadm/install/contents` (fixes factory world-writability).
5. Print summary; `-n` dry-run flag.
(The corrupt-record decision stays in contents-fsck, not here.)

## 5. Repo tools (`tools/repo/`, host-side)

Eighteen non-test files, all host-side (Linux, python3 stdlib + sh); nothing here runs on the box,
though the gate and acceptance scripts are Bourne sh precisely so they *can* be driven on it.

### 5.1 Catalog and publishing

- **Kernel space** (apkg 0.3, amix-dlm C2-2 v2 / C2-3): `gen-catalog.py` puts a kernel package —
  one whose pkgmap carries `/stand/k30/kabi` or `/stand/k46/kabi` — in a `#ext kpkg 1` … `#end kpkg`
  block after the entries, never as an ordinary entry, with `line=`, `kabi=` and `pin=` read from
  that sidecar inside the package byte for byte (kbootset gate 2 compares them), `size=`/`sha256=`
  of the served file, `pkginst=`, and `offset=` under `--raw`. Not opt-in; a staging root without
  kernel space gives the catalog it always did. A loader package (`/stand/loader/ldrinfo`) gets
  `role=loader line=any loader=<n>` from its ldrinfo and no `kabi=`/`pin=` (C2-2 v3, C2-3 v2); the
  kbootset package is an ordinary entry. A module package (stage 3; one object in
  `/etc/conf/mod.d/`) gets `role=module line= kabi= pin=` from that object's `.moddata` (C3-1: the
  type-13 section, keys `kabi=` and `cc=`; `line=` is kabi's family), no `depend=`. apkg names
  each install record `/var/apkg/kpkg/<pkginst>` (C2-2 v4) and keeps one kernel package per line
  (C2-2 v5 §2.1, apkg 0.3.1). NOTES.md 2026-10-25 (late) and the sections after it are the record.

- `gen-catalog.py` (python3): scan a staging dir of `.pkg`/`.pkg.Z` datastreams; for each, read the
  `# PaCkAgE DaTaStReAm` header + first cpio member to extract pkginfo params (PKG, NAME, VERSION,
  CATEGORY, and optional `APKG_DEPS=`, `APKG_DESC=`); emit `catalog` (+ `catalog.md5`). Deps may
  also come from a `deps.conf` override (`name: dep1,dep2`), the category from `cats.conf` and the
  description from `descs.conf` (section 5.3). Every assembled entry line is checked against the
  **client's** own per-line read limit before anything is written (**Gate 8**, `CATALOG_MAX_ENTRY`
  = 2046 bytes, from `src/apkg/catalog.c`'s `MAXLINE`): a longer line makes apkg reject the *whole*
  catalog, not the one line, so the generator fails closed (rc 2, no catalog written) exactly as
  Gate 7 does. `--raw` additionally assigns each
  package a 512-aligned byte offset, appends it as the catalog's 10th field, and packs a
  self-describing `raw.img` (to the `source.h` layout) for the RAW source. `--isize` appends the
  installed-size extension block (section 2); it is **opt-in**, so without the flag the catalog is
  byte-for-byte what it always was. A package whose pkginfo carries `APKG_FSTYPE` (section 2b)
  is validated (malformed: SKIP), listed in the `#ext fstype 1` trailer and named in the summary
  line (`1 UFS-only (perl=ufs)`). `--scan-private` builds nothing — it is the licensing gate,
  below.
- `publish.sh`: rsync staging → `$PUBLISH_DEST` (`<user>@<host>:<docroot>`; `catalog`,
  `catalog.md5`, `pkgs/`), verify via `curl http://pkg.amigaux.org/catalog`. `PUBLISH_DEST` is
  **required** — there is no default host, so every publish names its destination — and the
  verify URL is overridable (`PUBLISH_URL`). Since 2026-09-15 the destination is **remote** —
  rsync over ssh as the invoking user (the docroot is owned by that user, so no root and no
  service credential is involved); until then it was a local LAN mirror. The consequence for the
  licensing gate below is that the destination is now **publicly reachable**, not LAN-only.
- **Private-content gate — fail-closed, no `--force`.** publish rsyncs *every* `.pkg` in staging,
  not only the cataloged ones, so a hand-added or stale-catalog kernel package would otherwise
  reach the public host. Before rsyncing, `publish.sh` runs `gen-catalog.py --scan-private` on the staging
  dir — one definition of "private", in one place. The scan keys on the **pkginfo markers**
  `KSUM_R`/`BOOT2_SHA` that our kernel mints carry, *not* on pathnames, so stock packages that ship
  `/stand/unix` and `/stand/boot2.boot` as original Amix content publish normally. A marked package
  refuses the whole staging (`exit 4`); a scan that cannot run also refuses. The same gate fires
  inside a catalog build (`rc 3`, no catalog written). Detail: `docs/kernel-packages.md`.
- **Payload-licence gate — a different question, independently checked.** `publish.sh` also runs
  `payload-licence-gate.py`, which reads payload contents — a property `--scan-private` cannot
  see, since it keys on pkginfo markers. It refuses (exit 5, no `--force`) a Kickstart ROM image,
  which the Amix permission does not cover. Stock Amix object code statically linked into a
  payload binary (SVR4 `libm`, detected via embedded `STT_FILE` source names) was refused until
  2026-10-30; since the owner's decision that day (ports link the stock `libm.a`; the permission
  covers all of Amix, ruling 2026-10-29) it is recorded as an `embeds` line, not refused. A
  stripped payload binary reports UNKNOWN, never a clean pass. Detail: NOTES.md 2026-10-30; the
  history and the four ways the gate was wrong before it was right: NOTES.md 2026-09-16.

### 5.2 Building packages

- Package building uses the **host-built** heirloom `pkgmk`/`pkgtrans` (they run on Linux — proven).
- `build-packages.sh`: stage + build this project's own datastreams — `--apkg`, `--eng`, `--cdfs`,
  `--demo` (`--all` = the redistributable set). It **enforces the ≤ 9-character PKG name**
  (constraint 1: stock `pkgadd` silently drops longer ones) and verifies every emitted datastream
  carries `070701` newc members at offset 512, failing closed on either. The kernel arms
  (`--kernbench`/`--kernz3660`/`--kern`) are **never** part of `--all` and stage into a separate
  private directory (`$KERNEL_STAGING`, default `build/kernel-private`), so private packages are
  physically apart from the redistributable staging.
- `repackage-stock.py`: repackage the 27 Amix 2.1 factory tape packages (amixpkg media format: one
  cpio-newc archive per tape file, `.Z` where the tape List says so) into proper SVR4 datastreams.
  It parses every cpio member **header** itself — mode, uid, gid, rdev major/minor, symlink
  targets, hardlinks — because the tape archives were written by root on Amix and extracting them
  as a normal user loses ownership and cannot create device nodes; it emits a `prototype(5)` from
  those headers and builds with the host `pkgmk`/`pkgtrans`.

### 5.3 Authored metadata

Stock Amix metadata has no dependency graph and no useful taxonomy, so both are **authored** here.
All of them are pure metadata: editing one and re-running `gen-catalog.py` moves no `.pkg` byte and
no `.pkg` md5. `gen-catalog.py` reads `deps.conf`, `cats.conf`, `descs.conf` and `names.conf` from
the **staging root** (`build-packages.sh` copies `deps.conf` and `descs.conf` there); the authored
copies live in `tools/repo/`.

- `deps.conf` — the dependency graph. `core` is essential base and never a declared dep, and there
  are **no "you need a compiler" deps**.
- `cats.conf` — the category taxonomy, applied at *catalog* level (it wins over the package's own
  `CATEGORY`, which is `system` for all 27 factory packages). Two statement types:
  `<name>: <category>` assigns, `@group <token>: <gloss>` **declares**. Declaring any group closes
  the vocabulary: an assignment naming an undeclared group is refused per-package (SKIP, as a
  category containing a space already was, since apkg rejects such a catalog whole), and a package
  falling through to a pkginfo `CATEGORY` outside the vocabulary warns. A `cats.conf` with no
  `@group` line declares nothing and keeps the old permissive behaviour. **Thirteen groups** today:
  `system`, `network`, `utility`, `archive` (added 2026-10-30), `text`, `editor`, `documentation`, `development`, `x11`,
  `openlook`, `emacs`, `games`, `source`. Categories say what a package **is**; who wants it is a
  set.
- `descs.conf` — the **description** overrides, the same catalog-level pattern one field over
  (`<name>: <free text>`; only the first colon separates, so the text may hold more). The ninth
  column is the only prose a user ever sees — `apkg list`/`search`/`info` and the installer menu —
  and it was a pure function of the package's own pkginfo (`APKG_DESC`, falling back to `NAME`), so
  saying anything *new* about an already-published package meant re-minting it and moving its md5
  for a change that touches no installed byte. Refused per-package: a `|` (the field separator —
  refusing beats `clean_field()` silently rewriting an authored sentence to `/`) and an empty
  override (a truncated line, and it would blank a description the pkginfo did supply; delete the
  line to fall back). Over-long is Gate 8 above. Unlike `cats.conf`, this file **is** staged on
  every mint — safe precisely because it names only packages we mint, so staging it moves exactly
  those lines; a key naming a stock package would move a published stock line on the next
  regeneration, and `tools/repo/tests/run-tests.sh` T18 asserts it does not.
- `sets.conf` + `sets.py` — the named install sets the installer offers, and the reference
  resolver for them (`<set>: a,b` lines, `+<other-set>` includes transitively). The five locked
  sets are a strict chain, `minimal` ⊂ `standard` ⊂ {`full`, `developer`, `x11`}: `minimal` (8) is
  the metal installer's attested base, `standard` (17) is the tape's own default plus our three,
  `full` (30) is the complete Amix 2.1 distribution plus our three — **not** "every package in the
  catalog". A sixth set, `extra`, is declared empty and sits **off** the chain: it is the handle
  for the sibling `amix-packages` userland, disjoint from the five by test. `sets.py` resolves
  names only — no dependency closure (that is `deps.conf` + apkg's resolver) and no ordering (that
  is the core-first gate). The miniroot re-implements the same grammar in pre-POSIX sh, which is
  why the grammar is one statement per line with a single separator; the resolved memberships are
  asserted by `tools/repo/tests/run-tests.sh` so the two cannot drift.

### 5.4 Acceptance gates and analysis

The gates are Bourne sh so they run on the box (euid 0), and they all fail closed:

- `core-first-gate.sh` (Gate 13) — refuse a `pkgadd -R` of any non-`core` package into a target
  root that lacks both `<root>/etc/passwd` and `<root>/etc/group`. Absent those, libpkg's
  `clgrnam()`/`clpwnam()` silently fall back to the *installing* box's name service, which is
  correct only by coincidence when the ids happen to match. `core` is the legitimate exception: it
  is the package that ships them.
- `content-gate.sh` (Gate 12) — verify installed **content** against the per-file cksum/size in
  the contents DB via `pkgchk -R -c`; fails on any discrepancy. (Gate 11, `pkgchk -R -a`, attests
  ownership; nothing else checksums content.)
- `altroot-acceptance.sh` — drives the whole base-set `pkgadd -R` run in dependency order:
  Gate 13, install, Gate 12, Gate 11 per package; then `contents-fsck` (must report zero repairs),
  `pkginfo -R`, and an emit of the installed DB + `etc/passwd` + `etc/group`.
- `altroot_attest.py` (Gate 11, host side) — resolve the emitted tree's owner/group **names**
  through the *target* root's passwd/group and print a canonical, reproducible tree digest.
- `source-acceptance.sh` — the same battery driven **through apkg's source layer** (HTTP, a
  mounted `/cdrom`, `raw:<device>`) into three fresh roots: "three sources, one digest".
- `pkgmap-symlink-gate.py` — mint-time link gate, run by `build-packages.sh` on every package it
  builds (and standalone with `--pkg <datastream>`): every `s`/`l` entry in the minted pkgmap must
  carry an **absolute** target that resolves to a path the package itself declares. The absolute
  rule is not pedantry — APKG 0.2's relative `../apkg/bin/apkg` is what the SVR4 spec blesses and
  what our heirloom `pkgadd` gets right, but `/usr/apkg/bin` is not on the default PATH, so the
  `pkgadd` an operator types is the stock 1991 one, and that prefixes the basedir onto the link
  *source* as well: on metal it created `/usr/bin/apkg -> /../apkg/bin/apkg` and `apkg` was "not
  found" straight after a successful install (2026-09-16).
- `s5-collision-scan.py` — host-side analysis: read published datastreams' pkgmaps and find the
  objects a set cannot lay down on a 14-character s5 filesystem, keyed on `(dirname,
  basename[:14])` because a collision is a property of a *directory*. Feeds
  `docs/s5-14char-collisions.md`. It names the UFS-only packages (`APKG_FSTYPE`, section 2b) it
  scans; a collision group made only of their objects is reported as exempt and does not fail
  `--fail-on-collision`. The counts and the pinned constants are unchanged.

## 6. Packaging & bootstrap

- `apkg` + repaired-engine binaries + admin file + man pages ship as SVR4 datastream packages built
  host-side: `APKG` (client, /usr/apkg + /etc/apkg.conf + /var/apkg) and `APKGENG` (heirloom
  tools + man pages under /usr/apkg). Both installable with **stock** pkgadd (bootstrap path:
  ftp/download one file, `pkgadd -d APKG-x.y.pkg`).
- First repo content: APKG, APKGENG; later the repackaged stock + community packages.

## E2E acceptance (the "everything ready" bar)

On the guest: `pkgadd -d APKG*.pkg` (stock tools) → run migration script → `apkg update` over
plain HTTP from pkg.amigaux.org → `apkg list/search/info` → `apkg install <test pkg>` (with a dep)
→ files on disk, `/var/sadm` updated, stock `pkginfo` still happy → `apkg remove` reverses it.
