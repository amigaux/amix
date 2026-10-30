# amix-packagemanager

Remote package management for **Amiga Unix (Amix)** — Commodore's 1992 SVR4.0 port to the
68030 Amiga.

Amix ships the stock SVR4 `pkg` tooling — `pkgadd`, `pkgrm`, `pkginfo`, `pkgtrans`, the `.pkg`
datastream format and the `/var/sadm` installed-product database — and that is all it ships.
There is **no remote repository support** of any kind: a package reaches the box because you
carried it there. And the factory installed-product database is **corrupt out of the box**: the
X11R5 package installed a file literally named `TrueType Fonts`, and because `contents(4)` is
whitespace-delimited with no quoting, that one record makes every stock tool that fully parses the
database abort — `pkgrm` and `pkginfo -l` are dead on a factory install.

This repository fixes both, without replacing the packaging model Amix already has. The SVR4 `pkg`
model and the live `/var/sadm` database stay; a repaired engine and a small HTTP client are added
beside them, under a parallel prefix, so the stock tools keep working the whole time.

**Status: shipped and in use.** The direction was decided 2026-07-04 and everything below is
bench-verified on a real Amix 2.1c system; the live package repository is at
<http://pkg.amigaux.org/>. Development state and history:
[NOTES.md](NOTES.md) (the authority) and [CHANGELOG.md](CHANGELOG.md).

## What is here

| Component | Path | What it is |
|---|---|---|
| **apkg** | [`src/apkg/`](src/apkg/) | The remote client. A single C89 binary (`update`/`list`/`search`/`info`/`download`/`install`/`upgrade`/`remove`) that fetches a catalog and packages over plain HTTP/1.0, md5-verifies them, resolves dependencies recursively, and drives the local `pkgadd`/`pkgrm`. Also installs from a mounted CD or a raw disk slice. |
| **the engine** | [`heirloom/`](heirloom/) | [Heirloom pkgtools](http://heirloom.sourceforge.net/pkgtools.html) — the open (CDDL) SVR4 `pkg` implementation — cross-ported to m68k SVR4 ELF, with eleven bench-verified root causes fixed. Notably its `contents` parser tolerates the factory corruption that kills the stock tools. Port log: [`heirloom/AMIX-PORT.md`](heirloom/AMIX-PORT.md). |
| **contents-fsck** | [`src/contents-fsck/`](src/contents-fsck/) | Standalone checker/repairer for `/var/sadm/install/contents`. Single C89 file, libc only. Report mode names every malformed record with a reason; repair mode never writes in place. Run against the live 28,716-record factory database. |
| **migration** | [`tools/migrate/`](tools/migrate/) | One-time `/var/sadm` migration: populate `VERSION=` into the installed database (the factory packages have none), create the missing `install/` directories, un-world-write the contents file. Pre-POSIX Bourne sh, idempotent. |
| **repo tools** | [`tools/repo/`](tools/repo/) | The host side: catalog generator, publisher, package builders, the authored dependency graph / category taxonomy / install sets, and the acceptance gates. Runs on Linux, python3 + sh. |

Architecture for all five: [`docs/design.md`](docs/design.md).

## Installing apkg on a stock Amix box

`APKG` is built to install with **stock** `pkgadd` — that is the whole bootstrap. Get one file
onto the box (FTP is the proven bridge; mounting a modern NFS server does not work — Amix's 1992
client is NFSv2 over UDP only) and, as root:

```
# pkgadd -d APKG-0.2.2.pkg APKG
```

(`0.2.2` is the current shipped version at `pkg.amigaux.org`; earlier `APKG-0.1.pkg`/`APKG-0.2.pkg`
stay served, decatalogued, for recovery fetches only — NOTES.md.)

That lays down `/usr/apkg/bin/{apkg,contents-fsck,amix-sadm-migrate}`, `/etc/apkg.conf`,
`/var/apkg/`, the man page, and a single `/usr/bin/apkg` symlink so the client is on the default
PATH. Then bring the installed-product database up to date and fetch the catalog:

```
# /usr/apkg/bin/amix-sadm-migrate            (add -n first for a dry run)
# apkg update
# apkg install apkgeng                       (the repaired engine; apkg uses it from then on)
```

`apkg` prefers `/usr/apkg/bin/pkgadd` and falls back to the stock `/usr/sbin/pkgadd`
automatically, so it works before `APKGENG` is installed and is simply more capable after.

`/etc/apkg.conf` is plain `key=value`. Besides `repo`, `cachedir`, `pkgadd`, `pkgrm` and `admin`
it carries every tunable of the fetch path — `timeout`, `connect_timeout`, `retries`,
`retry_delay`, `progress`, `bufsize`, `redirects`, `rcvbuf`, `sndbuf` — so nothing on that path
is a compiled-in number an operator cannot move. `apkg -v` prints the whole set back on one line. The one worth
understanding is `timeout` (default 300 s): it bounds network **silence**, not how long a
transfer may take, because the timer is re-armed by every chunk that arrives. Sizing it against
package size is a category error — an 8.2 MB package over the measured ~37 KB/s A4000D path is
~220 s of perfectly healthy, continuously flowing transfer. See `apkg(1)` for the full table.

### Repairing the factory contents database

Worth doing on any factory install, whether or not you use `apkg` — the corrupt record is what
breaks stock `pkgrm` and `pkginfo -l`:

```
# contents-fsck /var/sadm/install/contents            see what is wrong
# contents-fsck -r -b /var/sadm/install/contents      write .fixed (+ .bak); never in place
# cp /var/sadm/install/contents.fixed /var/sadm/install/contents
```

Add `-s` to *drop* the spaced-pathname records instead of keeping them — the right choice on a
system that will only ever run the stock tools, since only the repaired engine parses them.
Details, including what each finding means: [`src/contents-fsck/README.md`](src/contents-fsck/README.md).

## Coexistence: nothing of the stock system is overwritten

This is a hard rule of the project, not a default:

* Everything installs under the parallel prefix **`/usr/apkg`** — client and engine binaries in
  `/usr/apkg/bin`, the sadm helpers (`pkginstall`, `pkgremove`) in `/usr/apkg/sadm/install/bin`
  (the engine's compiled-in `SADMDIR` is the parallel `/usr/apkg/sadm`), man pages in
  `/usr/apkg/man`.
* Stock `/usr/sadm`, the stock binaries in `/usr/bin` and `/usr/sbin`, and the factory `admin`
  file are **never** touched. The only object outside the parallel prefix is one added
  `/usr/bin/apkg` symlink, plus this project's own `/etc/apkg.conf` and `/var/apkg/`.
* **`/var/sadm` is shared** — the same installed-product database, read and written by both the
  stock tools and ours. That is the entire point: a package installed with `apkg` is visible to
  stock `pkginfo`, and if any of this goes wrong the stock tools are still there, unmodified, as
  the rescue path.

## Publishing a repository (maintainers)

A repository is a static file tree served over plain HTTP — a `catalog`, a `catalog.md5` and a
`pkgs/` directory. No server-side software. The host-side pipeline is:

```
tools/repo/build-packages.sh --all              mint APKG/APKGENG/cdfs/demo into build/repo-staging
python3 tools/repo/gen-catalog.py --isize <staging>
tools/repo/publish.sh --dry-run <staging>       then without --dry-run
```

`build-packages.sh` builds with the **host-built** heirloom `pkgmk`/`pkgtrans` (they run on
Linux), enforces the ≤ 9-character PKG name that stock Amix `pkgadd` silently requires, and
verifies every datastream carries `070701` cpio members. `repackage-stock.py` is the same idea for
the 27 Amix 2.1 factory packages, rebuilt from the original install tape with modes, owners,
device nodes and symlinks read out of the cpio headers. `publish.sh` rsyncs the staging tree to
the repository root named by `PUBLISH_DEST` (required; there is no default host) and verifies the
result over HTTP.

**The publish path is fail-closed on private content.** `publish.sh` first runs
`gen-catalog.py --scan-private`, which refuses to publish a staging directory containing this
project's kernel packages — kernel packages are private by policy, and the publish path refuses
them. The scan keys on pkginfo markers rather than pathnames, so stock packages that ship
`/stand` content publish normally. A hit refuses the *whole* staging with exit 4, a scan that
cannot run also refuses, and there is **no `--force`**.

A second, independent gate, `tools/repo/payload-licence-gate.py`, answers a different question —
what does a payload carry? It refuses (exit 5, no `--force`) a Kickstart ROM image, which the
Amix permission does not cover. Stock Amix object code statically linked into a payload binary
(SVR4 `libm`) is permitted since 2026-10-30 and is recorded, one `embeds` line per binary, not
refused. Detail and history: NOTES.md 2026-10-30 and 2026-09-16.

### Catalog format (v1)

Pipe-delimited text, one package per line, `#` comments:

```
#apkg-catalog 1
name|version|pkginst|filename|md5|size|deps|category|description[|offset]
```

`deps` is a comma-separated list of catalog names or `none`; `filename` is relative to `pkgs/`
and may contain `/` (the repository is organized into `stock/`, `base/`, `test/`, … purely as
metadata — reorganizing means regenerating the catalog, not moving a package's identity); `md5`
and `size` describe the file exactly as served (so, the `.Z` file for a compressed package). The
optional 10th field is a byte offset used only by the raw-slice source.

Because `#` lines are comments, a catalog may also carry **extension blocks** after the entries —
`#ext <name> <version>` followed by `#<name> <key> <value>` lines — which every existing client
already skips. One exists today: `isize`, the per-package installed size in bytes. A missing
`#isize` line means *unknown*, never zero. Full grammar: [`docs/design.md`](docs/design.md) §2.

## Building from source

The Amix targets need the `m68k-cbm-sysv4` cross toolchain
([gcc-cross-amix](https://github.com/isoriano1968/gcc-cross-amix): binutils 2.8.1 + GCC 2.7.2.3)
with a sysroot populated from an Amix 2.1 system (see gcc-cross-amix). Everything also builds and
tests on a plain Linux host, which is where the packaging pipeline and most of the test suites run:

```
(cd src/apkg          && make test)                    # 223 assertions
(cd src/apkg          && sh tests/nohttp-variant.sh)    # 20 (the FILE+RAW, no-sockets build)
(cd src/contents-fsck && make test)                     # 19
bash tools/repo/tests/run-tests.sh                      # 375 (bash, not sh)
sh tools/migrate/tests/run-tests.sh                     # 36
(cd heirloom && ./build-host.sh)         # the pkgmk/pkgtrans that build packages
```

Cross builds: `. <path-to>/gcc-cross-amix/build/env.sh`, then `make amix` in either `src/`
directory, and `heirloom/build-amix.sh` for the engine. The scripts expect **sibling checkouts**
beside this repository and fall back to them when nothing is set:

* `../gcc-cross-amix` — the cross toolchain's `build/env.sh`; override with `AMIX_CROSS_ENV`
  (heirloom scripts) or `CROSS_ENV` (contents-fsck), and the sysroot with `AMIX_SYSROOT`.
* `../amix-cdfs` — the built cdfs `mount` helper that `tools/repo/build-packages.sh --cdfs`
  packages (only that option needs it).

Test runs on an Amix box use a WinUAE or Amiberry guest reachable over telnet/ftp;
[`configs/amix-winuae.example.uae`](configs/amix-winuae.example.uae) is the reference emulator
config, with `<ROM_DIR>`, `<HDF_DIR>` and `<MAC>` placeholders to fill in. Conventions and the
hard constraints: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documentation

* [`NOTES.md`](NOTES.md) — session-by-session lab notes, newest first. The authority on current
  state; if any other document disagrees with it, it is stale.
* [`docs/design.md`](docs/design.md) — architecture of all five components, the catalog format,
  the source layer, the host pipeline.
* [`docs/requirements.md`](docs/requirements.md) — the original requirements and the decision of
  record.
* [`docs/stock-pkg-system.md`](docs/stock-pkg-system.md) — confidence-tagged map of the **stock**
  Amix packaging system, as Commodore shipped it.
* [`docs/s5-14char-collisions.md`](docs/s5-14char-collisions.md) — what an s5 filesystem's
  14-character names do to a large package set.
* [`heirloom/AMIX-PORT.md`](heirloom/AMIX-PORT.md) — the engine port log: every root cause, every
  deviation, the binary inventory.
* [`docs/direction-evaluation.md`](docs/direction-evaluation.md),
  [`docs/heirloom-pkgtools-dive.md`](docs/heirloom-pkgtools-dive.md) — historical; how the
  direction was chosen. Read them for "why not X?", not for current state.

## Licensing

This repository is a mosaic; the map is short.

| Path | License |
|---|---|
| `src/apkg/`, `src/contents-fsck/`, `tools/`, and the Amix-specific files added under `heirloom/` (`compat/`, `sslstub/`, `mk.config.amix`, `build-*.sh`) | MIT — [`LICENSE`](LICENSE) |
| `heirloom/` (vendored engine) | CDDL 1.0, OpenSolaris SVR4 lineage with AT&T notices intact and portions © 2007 Gunnar Ritter, plus the Caldera license for the ancient UNIX parts — [`heirloom/LICENSE/`](heirloom/LICENSE/) |
| `heirloom/compat/{fnmatch.c,fnmatch.h,charclass.h}` | BSD/ISC/public domain (OpenBSD via openssh-portable) |
| `heirloom/compat/snprintf.c` | Powell/Weiss permissive |
| `research/heirloom/` | patches and extracts of the vendored engine; CDDL-derived |
| `src/apkg/md5.{c,h}` | public domain (Colin Plumb, 1993) |

Per-file headers are authoritative. Every Amix deviation inside the CDDL tree is marked with an
`AMIX PORT:` comment at the site and recorded in `heirloom/AMIX-PORT.md`, and each modified CDDL
file carries a "Portions Copyright" contributor line below its CDDL header.

Amiga UNIX is Commodore's; on 2026-09-23 Amiga Corporation approved distributing the Commodore
Amiga binaries this project builds on (see [`NOTICE`](NOTICE), which also carries the trademark
notices and the third-party attributions). This tree carries no Amix source, binary, manual, tape
or disk image; where the work needs to refer to factory material it does so by name, checksum and
pointer. Running the tools needs an Amix 2.1 system, real or emulated, and repackaging the factory
set needs a copy of the 2.1 install tape.
