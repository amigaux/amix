# build/pkg

The packaging framework. It builds a package from its package directory and
generates every piece of package metadata from that directory's `package.sh`,
so each fact about a package is written in one place.

| File | What |
|------|------|
| `pkgbuild.sh` | the driver: fetch (or copy the source in the tree), patch, configure and make (by style), the gates, stage, check the prototype, roll |
| `styles/<STYLE>.sh` | the build styles: `configure` (`./configure --host`, then make), `make` (a plain Makefile, tools given on make's command line) and `hooks` (the recipe's own `build` hook) |
| `layout.sh` | where the harness finds the toolchains, pkgtools and the build output in this checkout |
| `common/` | the harness: environment, fetcher, gates and roll |
| `pkgmeta` | checks `package.sh` and writes pkginfo, the catalog line, our catalog configuration lines and the index; also the one-version guard |
| `check-packages` | CI's check of `userland/packages` |
| `tests/` | the host tests, `make -C build test` |

## The package directory

```
<name>/
  package.sh        the metadata: KEY=value assignments only
  build.sh          optional hooks only (see the top of pkgbuild.sh)
  src/              our own source, when there is no upstream tarball
  prototype         the hand-written SVR4 payload; `i pkginfo' is generated
  patches/*.patch   applied in name order, each with its reason in its header
  tests/smoke.sh    the on-box acceptance test
  README.md         porting decisions
```

`package.sh` keys, required unless a default is shown:

| Key | What |
|-----|------|
| `NAME` | the catalog name; the directory's name |
| `PKG` | the SVR4 package instance, at most 9 characters (stock `pkgadd` drops longer names without a word) |
| `VERSION`, `PKGREV` | the upstream version and the package revision; the package's version is `VERSION-PKGREV` |
| `SUMMARY` | one line; pkginfo `NAME` and the catalog description |
| `DESC` | one line; pkginfo `DESC` |
| `CATEGORY` | one of the catalog groups: system, network, utility, archive, library, shell, language, text, editor, documentation, development, multimedia, x11, games, source |
| `SET` | the sets the package belongs to, space-separated: minimal, standard, full, developer, x11, extra |
| `LICENSE` | an SPDX identifier |
| `URL`, `SHA256` | the source tarball and its sha256; neither, when the source is in the tree |
| `SRCPKG=""` | build from another package's `src/` (`amix-benchmark-gcc14` from `amix-benchmark`) |
| `STYLE=configure` | `styles/<STYLE>.sh` |
| `TOOLCHAIN=gcc14` | `gcc14` or `period` |
| `PREFIX=/opt/amix` | the install prefix |
| `DEPENDS=""`, `BUILD_DEPENDS=""` | catalog names, space-separated |
| `SRCDIR=$NAME-$VERSION`, `PATCH_STRIP=1` | the tree the tarball unpacks to, and `patch -p` |

`pkgmeta` reads `package.sh` by sourcing it with `/bin/sh`, exactly as the
driver does, so the two never disagree about a value.

A package has one source: the tarball at `URL`, or the source in the tree.
That is the package's own `src/`, or, with `SRCPKG`, the `src/` of the
package it names. The driver copies it to the build tree, so patches and
builds never touch the checkout. `BUILD.txt` records a digest of the copy.

## pkgmeta

```sh
build/pkg/pkgmeta check <package dir>|<packages dir>
build/pkg/pkgmeta pkginfo <package dir>
build/pkg/pkgmeta catalog <package dir> --pkg <rolled .pkg>
build/pkg/pkgmeta fragments <packages dir> [-o DIR [--check]]
build/pkg/pkgmeta index <packages dir> [-o FILE] [--check]
build/pkg/pkgmeta guard <catalog>|<directory of .pkg>...
```

- `pkginfo` is what the roll packs.
- `catalog` prints the package's catalog v1 line, the one
  amix-packagemanager's `gen-catalog.py` writes for the rolled package:
  `name|version|pkginst|filename|md5|size|deps|category|description`.
- `fragments` prints our packages' lines of `names.conf` (only where the
  catalog name is not the lowercased instance), `cats.conf`, `deps.conf` and
  `sets.conf`. They are merged with the hand-written lines for the stock
  packages when the catalog is generated.
- `index` writes the table of packages to `INDEX.md` in the packages
  directory, never to its README, which is written by hand.
- With `--check`, `fragments` and `index` compare instead of writing.
  `check-packages` uses them on `userland/packages`: every `package.sh`
  passes `check`, and `INDEX.md` and `conf/` (the fragments) are current.
  It has nothing to check until the first `package.sh` lands.

## One version per name

A package name names one package, at one version. `pkgmeta check` over a
packages directory, `fragments` and `index` refuse two recipes with the same
instance, or an instance that is another package's catalog name. `pkgmeta
guard` applies the same rule to built output: a catalog, kernel-space rows
included, or a staging directory of rolled packages. It refuses any name or
instance that appears at two versions; the same version listed twice is
allowed. A changed package therefore takes a new revision and replaces the
old one; it does not sit beside it.

The roll keeps its own check: one version names one set of bytes. A version
already in a catalog of record is not rolled again with other bytes.

## Building

```sh
sh build/pkg/pkgbuild.sh userland/packages/<name>
```

The driver uses the harness in `build/pkg/common`: the build environment, the
fetcher, the gates and the roll. `layout.sh` tells the harness where things
are in this checkout:

- the toolchains: `GCA` and `G14` name their `build/` directories, as in the
  build container (`toolchain/README.md`). Unset, they are the
  `gcc-cross-amix` and `gcc14-cross-amix` checkouts beside the main working
  tree. The harness's gcc14 pin must be the commit in
  `toolchain/gcc14-cross-amix.pin`;
- pkgtools: the host `pkgmk` and `pkgtrans` that
  `userland/pkgtools/heirloom/build-host.sh` builds, and
  `userland/pkgtools/tools/repo/scan060.py`;
- kernel/dlm and kernel/modules in this checkout;
- the output: `out/pkg` (ignored), or `AMIX_BUILD_ROOT` or
  `AMIX_GCC14_BUILD_ROOT` when set.

`AMIX_PKG_COMMON` names another harness. An amix-packages `recipes/common`
finds its repository and siblings itself, and the driver leaves it to do so.

Outputs: `<build root>/<name>/` (the source, the build tree, the staged
payload, the logs, `BUILD.txt` and `catalog.line`, the package's catalog
line) and `<build root>/pkg/<PKG>-<VERSION>-<PKGREV>.pkg`.
