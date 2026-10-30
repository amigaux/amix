# userland/packages

Modern GNU/BSD tools for **Amiga Unix** (Amix — Commodore's AT&T SVR4.0 for the 68k, 1992),
cross-compiled and delivered as **SVR4 `.pkg` datastream packages** that the stock `pkgadd` on a
real Amix box can install.

This directory builds *packages*. The package *manager* (the Heirloom pkgtools engine, the
`/var/sadm` database, the remote `apkg` catalog client) is [`userland/pkgtools`](../pkgtools/),
whose `NOTES.md` is the authority on the `.pkg` format, the catalog and installation semantics.
The packaging framework that builds every package here is [`build/pkg`](../../build/pkg/).

This directory was the standalone repository amix-packages until 2026-10-30. It moved in with its
history rewritten (the kernel-space recipes, the registry and the publish records stayed behind),
so its commit hashes changed: [`docs/history-map.txt`](docs/history-map.txt) maps each old hash to
the new one. A hash cited in `CHANGELOG.md` or a README resolves through that map.

## The packages

[`INDEX.md`](INDEX.md) lists every package with its version, instance, category, set, toolchain and
licence. It is generated from each package's `package.sh`, as are the catalog lines in
[`conf/`](conf/).

| Package | Prefix | What it adds over stock Amix |
|---|---|---|
| [`libamixcompat`](libamixcompat/) (PKG `acompat`) | `/usr/local` | Shim for the libc symbols and headers SVR4.0 lacks — `snprintf`, `setenv`, `strcasecmp`, `mkstemp`, `usleep`, `<stdint.h>` … |
| [`patch`](patch/) | `/usr/local` | Supersedes the stock Larry Wall patch 12u4 (1990) in `public` |
| [`zlib`](zlib/) | `/opt/amix` | The deflate/inflate library (static `libz.a`); stock has none |
| [`gzip`](gzip/) | `/opt/amix` | The first `.gz` on the box; stock has only 1985 LZW `compress` |
| [`bzip2`](bzip2/) | `/opt/amix` | `.bz2` and the static `libbz2.a` |
| [`grep`](grep/) | `/opt/amix` | `-r`, `-o`, `--color` and a reliable `-E`; stock SVR4 `grep` has none of the first three |
| [`less`](less/) | `/opt/amix` | Backward scroll and incremental search; stock has only `more`/`pg`/`page` |
| [`tar`](tar/) (PKG `gtar`) | `/opt/amix` | GNU tar: base-256 sizes and ids, long names, owner names via in-executable parsers |
| [`make`](make/) | `/opt/amix` | GNU make beside the stock SVR4 `make` |
| [`diffutils`](diffutils/) (PKG `diffutil`) | `/opt/amix` | `diff -u`, `diff3`, `sdiff`, `cmp`; stock `diff` has no `-u` |
| [`coreutils`](coreutils/) (PKG `coreutil`) | `/opt/amix` | GNU coreutils, including `md5sum` and `sha1sum` |
| [`rsync`](rsync/) | `/opt/amix` | rsync, protocol 31, over rsh/ssh or its own daemon |
| [`amix-benchmark`](amix-benchmark/) (PKG `amixbench`) | `/opt/amix` | The `amix-bench` CPU/IO benchmark suite, period toolchain |
| [`amix-benchmark-gcc14`](amix-benchmark-gcc14/) (PKG `amixbch14`) | `/opt/amix` | The same suite built with GCC 14 |

**Published.** Nine packages are in the family catalog at `http://pkg.amigaux.org/` under
`pkgs/extra/`: `acompat`, `patch`, `zlib`, `gzip`, `grep`, `less`, `gtar`, `make` and `amixbench`,
built with the period toolchain (GCC 2.7.2.3) in 2026-09. Each was bench-proven on the emulated
68030: installed with the **stock** `/usr/sbin/pkgadd`, exercised by the package's own
`tests/smoke.sh`, checked with `pkgchk` and removed with `pkgrm`.

**Current, not published.** The recipes here build the GCC 14 revisions of the userland set
(`TOOLCHAIN=gcc14`), and these replace the period builds when the owner publishes them. They are
built, gated and smoke-tested in emulation. Publishing to pkg.amigaux.org is a manual maintainer
step.

Most packages install under **`/opt/amix`**, which no stock package owns, so they coexist with stock
Amix instead of replacing it ([`docs/coexistence.md`](docs/coexistence.md)). The two oldest
packages (`acompat`, `patch`) predate that policy and are still built at `/usr/local`.

## Building a package

From the top of amix:

```sh
sh build/pkg/pkgbuild.sh userland/packages/grep    # fetch (sha256-checked), patch, build, gate, roll
ls out/pkg/pkg/                                    # the .pkg datastreams; out/ is ignored
```

What a build needs is in [`build/pkg/README.md`](../../build/pkg/README.md): the two cross
toolchains at their pins in [`toolchain/`](../../toolchain/) (GCC 14 for userland, GCC 2.7.2.3 for
the period benchmark), an AMIX sysroot ([`system/`](../../system/)), and the host `pkgmk`/`pkgtrans`
from `userland/pkgtools`. Host tools: a POSIX shell, `python3`, `curl` or `wget`, `sha256sum`, and
`m68k-linux-gnu-objdump` for the 68060 scanner.

Sources are **never vendored**. Each `package.sh` carries one upstream URL and one sha256, and the
fetcher verifies the digest *before* extracting; our own code (`libamixcompat`, `amix-benchmark`)
is in the package's `src/`.

Every build ends in object-code gates rather than an exit status: an m68k SVR4 ELF check, the
undefined-symbol listing, a no-imported-assembly check, and the strict 68060 gate (no 64-bit
multiply or divide, `movep`, `cmp2`, `chk2` or `cas2`). On this toolchain a clean exit proves
nothing; see [`docs/porting.md`](docs/porting.md) §2.2.

## Installing on an Amix box

The easy way is `apkg install <name>` from the catalog at `http://pkg.amigaux.org/` (see
`userland/pkgtools`). By hand: transfer the `.pkg` (FTP in **binary** mode), then, as root:

```sh
pkgadd -n -a ./admin -d ./grep-2.5.1a-7.pkg grep
pkgchk grep                       # re-checks every object against the DB; returns 0
/opt/amix/bin/grep --version
pkgrm grep                        # cleanly reverses the install
```

The `admin` file is what makes it non-interactive — `pkgadd -n` alone aborts on the first question.
`docs/porting.md` §7 gives the working set of admin settings, and the whole smoke loop as it was
actually run. [`tools/pkg-smoke`](tools/pkg-smoke/) stages that loop for one package.

**`/opt/amix/bin` is not on the stock Amix PATH**, so add it yourself — after `/usr/local/bin`, ahead
of `/usr/bin`, so your own builds still win and stock scripts that hard-code `/usr/bin/grep` keep
stock behaviour:

```sh
PATH=/usr/local/bin:/opt/amix/bin:/usr/bin:/usr/ccs/bin:/sbin:/usr/sbin:/etc:/usr/ucb:/usr/amiga/bin:/usr/public/bin:/usr/hosts
export PATH
```

No package here edits `/etc/profile` or symlinks into a stock directory. The reasoning, and the
`pkgadd` conflict behaviour behind it, is in [`docs/coexistence.md`](docs/coexistence.md) §2–§4.

## The documents

| File | What it is |
|---|---|
| [`docs/porting.md`](docs/porting.md) | The constraints every recipe inherits, probe-verified against the real toolchain: the wrapper traps, the `__STDC__` header gate, the libc gap, the packaging rules |
| [`docs/coexistence.md`](docs/coexistence.md) | How these packages sit beside stock Amix — the `/opt/amix` prefix, the never-overwrite rule, PATH precedence, and the stock-userland audit |
| [`docs/recipes.md`](docs/recipes.md) | The traps the recipes encode, and why they are written by hand |
| [`docs/history-map.txt`](docs/history-map.txt) | Old amix-packages commit hashes → amix hashes |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | The package directory, the rules every recipe follows, and how publishing works |
| [`CHANGELOG.md`](CHANGELOG.md) | What landed, when, and what it cost |
| [`INDEX.md`](INDEX.md), [`conf/`](conf/) | The package table and our catalog configuration lines, generated from each `package.sh` by `build/pkg/pkgmeta` (`index`, `fragments`); never edited by hand |
| [`tools/`](tools/) | The on-box acceptance: `pkg-smoke/` stages one package's smoke test, `client-e2e-onbox.sh` runs `apkg` install → smoke → `pkgchk` → remove |

**On citations.** `../<repo>/…` citations name sibling Amix repositories, and `../tmp/<date>-<topic>/`
citations name the maintainer's dated research notes, which are not in version control; `ROADMAP`
and `registry/` citations name the planning records of the former repository, which stay with the
maintainer. They record where a claim was measured, not a link you can follow. Commit hashes cited
before 2026-10-13 refer to the pre-public development history.

## Licensing

- **Upstream packages** keep their own licences, listed per package in `INDEX.md`. Every package
  ships its upstream licence text under `<prefix>/doc/<tool>/`. Nothing SVR4-derived is committed
  here, and no upstream source tree is vendored.
- **`libamixcompat`** is first-party and BSD-2-Clause; its text is
  [`libamixcompat/LICENSE`](libamixcompat/LICENSE).
- **The rest of this directory** — the recipes, `tools/`, the benchmark sources and the
  documentation — is **MIT**, copyright 2026 Jussi Alanärä ([`LICENSE`](LICENSE)), except where a
  file says otherwise. The MIT grant does **not** extend to any packaged upstream program, its
  source or the binaries built from it, nor to the `*/patches/` diffs, which are offered under the
  licence of the program each one modifies.
- **Stock Amix objects.** Built binaries link the stock Amix startup objects and the box's shared
  `libc.so.1`; on 2026-09-23 Amiga Corporation approved distributing the Commodore Amiga binaries
  this project builds on. Trademark and attribution notes: [`NOTICE`](NOTICE).
