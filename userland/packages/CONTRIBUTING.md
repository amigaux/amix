# Contributing to amix-packages

This repo turns upstream GNU/BSD sources into SVR4 `.pkg` datastreams for Amiga UNIX (Amix). The
technical guide every recipe inherits is [`PORTING.md`](PORTING.md); read it before porting
anything. What it takes to build at all (the sibling repositories and host tools) is in
[`README.md`](README.md#prerequisites).

## Layout

- **One directory per port**, `recipes/<name>/`, named for its registry entry:
  - `pin.sh`: one upstream URL and one sha256;
  - `build.sh`: the entry point (fetch, patch, cross-build, gate, roll);
  - `pkginfo` and `prototype`: authored by hand, never generated;
  - `patches/`: unified diffs in a stated order, each with its reason;
  - `tests/smoke.sh`: the on-box acceptance check;
  - `README.md`: what the port needed, and why.

  [`recipes/README.md`](recipes/README.md) describes the four pieces in detail.
- **The shared harness** is in `recipes/common/`: `amix-env.sh` (toolchain and sibling discovery),
  `fetch.sh`, `gates.sh`, `pkgroll.sh`, `amix-cpp`, `amix-pwgr.c`.
- **One registry YAML per candidate package** in `registry/`. The schema is in
  [`registry/README.md`](registry/README.md).
- **After changing any `package.sh`**, regenerate the index and the catalog fragments with
  `build/pkg/pkgmeta index userland/packages` and
  `build/pkg/pkgmeta fragments userland/packages -o userland/packages/conf`
  (from the top of amix); CI's `make -C build check-packages` fails while they are stale.
- **Everything a build produces** goes under the gitignored `build/`: work trees, fetched source
  tarballs, `.pkg` datastreams, staging roots and logs. Git tracks recipes, tools and docs only.

## Rules every recipe follows

1. **Never vendor upstream source.** Fetch at build time from one URL, check it against one
   sha256, and verify the digest *before* extracting (`recipes/common/fetch.sh`).
2. **Every package ships its upstream licence text** under `<prefix>/doc/<tool>/`, listed in the
   `prototype`, and records `license.spdx` in its registry entry.
3. **Nothing SVR4-derived is committed here.** That covers stock Amix headers, libraries, objects
   and binaries. The toolchain's sysroot provides them at build time.
4. **The object-code gates must pass.** These are the m68k SVR4 ELF check, the undefined-symbol
   listing, the no-imported-assembly check and the strict 68060 **D4** gate (no 64-bit
   multiply/divide, `movep`, `cmp2`, `chk2` or `cas2` in any file, archive or rolled datastream).
   A clean exit from this toolchain proves nothing. Run `sh tools/gate060-selftest.sh` after
   touching the gate.
5. **Scripts that run on the box are pre-POSIX Bourne shell** (`PORTING.md` §3.6). Install scripts
   are an unproven path, so prefer pure file payloads.
6. **`PKG` names are at most 9 characters** and `ARCH=Amiga`. Stock `pkgadd` silently drops a
   longer name. When the readable catalog name differs, the packagemanager's `names.conf` maps it,
   for example `gtar` → `tar` and `amixbench` → `amix-benchmark`.
7. **Prefix:** new packages install under `/opt/amix` ([`COEXISTENCE.md`](COEXISTENCE.md)).
   `/usr/local` is left to the box's user. The two Wave-0 packages (`acompat`, `patch`) predate
   this and still use `/usr/local`.

## Format, catalog and publishing

The `.pkg` datastream format, the catalog format and the provenance sets are defined by
`amix-packagemanager` (its `NOTES.md` is the authority). This repo's userland belongs to the
`extra` set and is served from `pkgs/extra/` on the package host. Its category is a catalog field,
not a directory.

Publishing to `http://pkg.amigaux.org/` is a manual step done by the maintainer with the
packagemanager's `tools/repo/publish.sh`. The host and docroot are set in `PUBLISH_DEST` at publish
time and are not recorded in this repo. Pull requests never publish anything. A rebuilt package
gets a new package revision (`-2`, `-3`, …) so that `apkg upgrade` sees it.

## Commit messages

Use an imperative subject of at most 72 characters that says what changed. The body is optional
and short: why, plus the hashes, checksums or measured numbers a reader cannot get from the diff.
Put analysis in the recipe's README or in `PORTING.md`, not in the commit message.
