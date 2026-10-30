# build/pkg

The packaging framework. It builds a package from its package directory and
generates every piece of package metadata from that directory's `package.sh`,
so each fact about a package is written in one place.

| File | What |
|------|------|
| `pkgbuild.sh` | the driver: fetch, patch, configure and make (by style), the gates, stage, check the prototype, roll |
| `styles/<STYLE>.sh` | the build styles: `configure` (`./configure --host`, then make) and `make` (a plain Makefile, tools given on make's command line) |
| `pkgmeta` | checks `package.sh` and writes pkginfo, the catalog line, our catalog configuration lines and the index; also the one-version guard |
| `tests/` | the host test, `make -C build test` |

## The package directory

```
<name>/
  package.sh        the metadata: KEY=value assignments only
  build.sh          optional hooks only (see the top of pkgbuild.sh)
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
| `URL`, `SHA256` | the source tarball and its sha256 |
| `STYLE=configure` | `styles/<STYLE>.sh` |
| `TOOLCHAIN=gcc14` | `gcc14` or `period` |
| `PREFIX=/opt/amix` | the install prefix |
| `DEPENDS=""`, `BUILD_DEPENDS=""` | catalog names, space-separated |
| `SRCDIR=$NAME-$VERSION`, `PATCH_STRIP=1` | the tree the tarball unpacks to, and `patch -p` |

`pkgmeta` reads `package.sh` by sourcing it with `/bin/sh`, exactly as the
driver does, so the two never disagree about a value.

## pkgmeta

```sh
build/pkg/pkgmeta check <package dir>|<packages dir>
build/pkg/pkgmeta pkginfo <package dir>
build/pkg/pkgmeta catalog <package dir> --pkg <rolled .pkg>
build/pkg/pkgmeta fragments <packages dir> [-o DIR]
build/pkg/pkgmeta index <packages dir> > <packages dir>/README.md
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
- `index` writes the table of packages for the packages directory's README.

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
AMIX_PKG_COMMON=/path/to/amix-packages/recipes/common \
	sh build/pkg/pkgbuild.sh /path/to/<package dir>
```

`AMIX_PKG_COMMON` names the build environment, the fetcher, the gates and
the roll the driver uses. Until the packages move into `userland/packages`
those are amix-packages' `recipes/common`. With `AMIX_GCC14_BUILD_ROOT` set,
everything a build writes goes under that directory. Besides the package,
the driver leaves `catalog.line` with the package's catalog line in the
build directory.
