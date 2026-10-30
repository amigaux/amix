# Contributing to userland/packages

This directory turns upstream GNU/BSD sources into SVR4 `.pkg` datastreams for Amiga UNIX (Amix).
The technical guide every recipe inherits is [`docs/porting.md`](docs/porting.md); read it before
porting anything. What it takes to build at all (the toolchains, the sysroot, the host pkgtools) is
in [`build/pkg/README.md`](../../build/pkg/README.md).

## Layout

- **One directory per package**, `<name>/`, named for its catalog name. The full shape and every
  `package.sh` key are in [`build/pkg/README.md`](../../build/pkg/README.md#the-package-directory):
  - `package.sh`: the metadata, `KEY=value` assignments only — name, instance, version and
    revision, summary, category, set, licence, the source URL and its sha256, the build style;
  - `build.sh`: optional build hooks (configure arguments, configure seeds, asserts, staging);
  - `src/`: our own source, when there is no upstream tarball;
  - `prototype`: the SVR4 payload, written by hand; `i pkginfo` is generated;
  - `patches/*.patch`: unified diffs applied in name order, each with its reason in its header;
  - `tests/smoke.sh`: the on-box acceptance check;
  - `README.md`: what the port needed, and why.
- **The shared harness** (the build environment, the fetcher, the gates, the roll, `amix-cpp`,
  the `amix-pwgr.c` and `amix-ftruncate.c` shims) is in `build/pkg/common/`, and the driver is
  `build/pkg/pkgbuild.sh`. Both belong to the build framework; a change there is a change to
  `build/`, not to a package.
- **After changing any `package.sh`**, regenerate the index and the catalog fragments with
  `build/pkg/pkgmeta index userland/packages` and
  `build/pkg/pkgmeta fragments userland/packages -o userland/packages/conf`
  (from the top of amix); CI's `make -C build check-packages` fails while they are stale.
- **Everything a build produces** goes under the ignored `out/pkg/`: work trees, fetched source
  tarballs, `.pkg` datastreams, staging roots and logs. Git tracks recipes, tools and docs only.

## Rules every recipe follows

1. **Never vendor upstream source.** Fetch at build time from one URL, check it against one
   sha256, and verify the digest *before* extracting (`build/pkg/common/fetch.sh`).
2. **Every package ships its upstream licence text** under `<prefix>/doc/<tool>/`, listed in the
   `prototype`, and names its licence as an SPDX identifier in `package.sh` (`LICENSE`).
3. **Nothing SVR4-derived is committed here.** That covers stock Amix headers, libraries, objects
   and binaries. The toolchain's sysroot provides them at build time.
4. **The object-code gates must pass.** These are the m68k SVR4 ELF check, the undefined-symbol
   listing, the no-imported-assembly check and the strict 68060 **D4** gate (no 64-bit
   multiply/divide, `movep`, `cmp2`, `chk2` or `cas2` in any file, archive or rolled datastream).
   A clean exit from this toolchain proves nothing. `build/pkg/tests/` holds the gates'
   self-tests.
5. **Scripts that run on the box are pre-POSIX Bourne shell** (`docs/porting.md` §3.6). Install
   scripts are an unproven path, so prefer pure file payloads.
6. **`PKG` names are at most 9 characters** and `ARCH=Amiga`. Stock `pkgadd` silently drops a
   longer name. When the catalog name differs from the instance (`tar` for `gtar`,
   `amix-benchmark` for `amixbench`), `pkgmeta fragments` writes the `names.conf` line.
7. **Prefix:** new packages install under `/opt/amix` ([`docs/coexistence.md`](docs/coexistence.md)).
   `/usr/local` is left to the box's user. The two oldest packages (`acompat`, `patch`) predate
   this and still use `/usr/local`.
8. **One version, one set of bytes.** A changed package takes a new `PKGREV`; a version that has
   been rolled into a catalog is never rolled again with other bytes.

## Format, catalog and publishing

The `.pkg` datastream format, the catalog format and the provenance sets are defined by
[`userland/pkgtools`](../pkgtools/) (its `NOTES.md` is the authority). This directory's userland
belongs to the `extra` set and is served from `pkgs/extra/` on the package host. Its category is a
catalog field, not a directory.

Publishing to `http://pkg.amigaux.org/` is a manual step done by the maintainer with pkgtools'
`tools/repo/publish.sh`. The host and docroot are set in `PUBLISH_DEST` at publish time and are not
recorded here. Pull requests never publish anything. A rebuilt package gets a new package revision
(`-2`, `-3`, …) so that `apkg upgrade` sees it.

## Commit messages

Use an imperative subject of at most 72 characters that says what changed. The body is optional
and short: why, plus the hashes, checksums or measured numbers a reader cannot get from the diff.
Put analysis in the recipe's README or in `docs/porting.md`, not in the commit message.
