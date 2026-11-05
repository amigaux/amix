# Building Amix: make dist

`make dist` builds the release from this checkout and one closed input, the
Commodore system files: the ABI kits, the kernels, the modules and drivers,
both package catalogs and the media, all under `out/`. This page is how it
works today. A step that lacks an input, or is not in make dist yet, says so with
a `[MISSING]` line: that is a gap (its exit status is 3), the other steps still
run, and make dist ends by naming its gaps and exits 3.

## What you need

- **A full clone** of amix, not a shallow one. A package's epoch, the time of
  every time stamp in it, is the last commit that changed its directory, so
  make dist reads the history and refuses a shallow clone.
- **The system input**: a checkout of
  [amigaux/amix-system](https://github.com/amigaux/amix-system) at the pin
  (`system/fetch-amix-system DIR` makes one). It is checked against
  `system/MANIFEST.sha256` and `system/SYMLINKS` before any step.
- **docker** or **podman**, for the build container (`toolchain/`).

```sh
system/fetch-amix-system ../amix-system
make tools SYSTEM=../amix-system      # the build container, amix-toolchain:dist
make dist  SYSTEM=../amix-system
```

Every step runs in the build container, as you, with this checkout at `/src`
and the system input read-only at `/system`. The fixed path is what makes the
period compiler (gcc 2.7.2.3, which cannot remap paths) build the same bytes
on every machine. The image carries the toolchain pins it was built from, and
make dist stops before any step if they are not this checkout's
(`toolchain/check-image`): after a pin changes, run `make tools` again.
`AMIX_IMAGE` names another image, and `CONTAINER=podman` uses podman. `DIST_HOST=1` runs the steps on your host instead, with the
toolchains `build/pkg/layout.sh` finds; that is for development, and a release
is built in the container.

## The steps

In make dist's order, provider before consumer. Each is also a target of its
own (`make kit`, `make recipes/zlib`), at the top of the checkout or in
`build/`.

| Target | What it builds | Output | Status |
|---|---|---|---|
| `kit` | kernel/dlm's ABI kits, k30 and k46, with the port at `kernel/port/port.pin` | `out/kit/{k30,k46,kit.digests}` | builds |
| `kernel-k30` | the 68030 kernel: the cut of record (`kernel/k30/cuts/CURRENT`) rebuilt by k30's hook `kernel/k30/cuts/build.sh`, which refuses sums other than the record's | `kernel/k30/build/cuts/<id>/` (kern30m reads it there), its sums in `out/kernels/k30.list` | builds |
| `kernel-k46` | the 68040/68060 kernel: the cut of record (`kernel/port/cuts/CURRENT`) rebuilt by the port's hook `kernel/port/cuts/build.sh`, which fetches the port at `kernel/port/port.pin` and refuses sums other than the record's | `kernel/port/build/cuts/<id>/` (kern46m reads it there), its sums in `out/kernels/k46.list` | builds |
| `modules` | `kernel/modules/*/module` on both lines | `out/modules/<line>/<name>` | builds |
| `drivers`, `drivers/<name>` | every driver module on both lines, on this checkout's kit: `kernel/drivers/{a4091,z3660scsi,z3660eth}/module` (a4091 with a4kt710) and the forks at their pins, fetched by commit (cdfs, gayle-ide, paula, z3660rtg; z3660rtg's `depend=monsw` on our monsw) | `out/modules/<line>/<name>` | builds |
| `kspace` | the kernel-space packages: each `kernel/<dir>/pkg/build.sh` in provider order (dlm, k30, port, the modules, the drivers), one version per name; a directory without one is named | `out/kspace/pkgs/` | builds: kernel/dlm, kernel/k30 and kernel/port have recipes; the modules and drivers to come |
| `userland`, `recipes/<name>` | every package of `userland/packages` and `userland/base/pkg`, one version per name, each after the packages its `BUILD_DEPENDS` names (`recipes/<name>` builds those first); a cycle or a name that is no package is refused | `out/userland/pkgs/` | builds |
| `apkg` | APKG and APKGENG, by pkgtools' `make dist` | `out/apkg/*.pkg` | builds |
| `catalogs` | the kernel-space and userland catalogs, by pkgtools' `gen-catalog.py` over each space's packages, with tools/repo's confs as the staging layer and the space's own: `userland/packages/conf`, and `kernel/conf` for kernel space (its `names.conf` names each kernel package; kernel packages without it are refused); no time stamp, so a rebuild gives the same catalog | `out/{kspace,userland}/{catalog,catalog.md5}` | builds |
| `release` | the 1.1 package repository, by pkgtools' `assemble-release.py`: the userland and kernel-space catalogs and packages, APKG, the stock packages `stock-1.1.lock` names and the published tree (`RELEASE_PREVIOUS=<dir>`, if there is one); `tools/release-check` checks it with `ROM_MANIFEST=<file>` and `PRIVACY_PATTERNS=<file>`, which never enter this repository and go into the container read-only. The stock packages are fetched (see below). A stock package not to be had, or either file missing without `RELEASE_PUBLIC=1`, is a gap | `out/release/1.1/{catalog,catalog.md5,pkgs/}` | builds |
| `media` | the CD, netinstall and floppy media, by `media/build.sh` in the media image (`toolchain/Containerfile.media`); no such script, or no such image, is a gap | `out/media/` | not yet |
| `lock` | every input and output of the build (`release/README.md`), gaps or not; with `LOCK=<file>`, refuses a build that is not that lock | `out/lock` | builds |

`make tools` builds both containers (`toolchain/container-build.sh`, then
`toolchain/container-media.sh` on top of it). A step gets only its own inputs:
`STOCK`, `STOCK_URL`, `RELEASE_PREVIOUS`, `ROM_MANIFEST`, `PRIVACY_PATTERNS` and
`RELEASE_PUBLIC` reach `release`, the last three `media` too, and `LOCK` reaches
`lock`, so a name a kernel's recipe reads for itself is never set by accident.

A kernel directory's recipes plug into `kspace` as `kernel/<dir>/pkg/build.sh`:
with no arguments it rolls all its recipes, with names those; it reads
`AMIX_BUILD_ROOT` (make dist sets `out/build/kspace`), writes each `.pkg` to
`$AMIX_BUILD_ROOT/kspace/pkg/`, prints a `pkg <file> <sha256>` line for each,
and exits non-zero on a failure. A file the media need that is no package goes to
`$AMIX_BUILD_ROOT/kspace/beside/`, which reaches `out/kspace/beside/` and the lock. It exits 3 when an input outside the recipe
is absent, with a `[MISSING]` line naming the input (a kernel
cut's output, for one); the step then runs the other directories and ends
with exit 3. Its recipes set `SOURCE_DATE_EPOCH` from
their own pinned epoch, never the environment's. A driver directory's
`pkg/build.sh` is three lines around `build/pkg/common/kdrv.sh`, which rolls
each recipe (in `pkg/`, or one subdirectory per package) from the objects the
`drivers` step built in `out/modules/<line>/`.

A release is proven against its lock: `make dist SYSTEM=… LOCK=release/amix-<version>.lock`
rebuilds everything and refuses the result if any line of its lock differs
(`release/README.md`). A gap leaves lines of the lock unbuilt, so it is refused
too, and the check prints them. Scripts should call `sh build/dist.sh dist`:
`make` turns any failure of its recipe, a gap included, into its own exit 2.

### The stock packages

The `release` step takes the Commodore datastreams `stock-1.1.lock` names by
size, md5 and sha256. By default it fetches them into `out/cache/stock-1.1/` from
the release assets at the URL in `system/stock-1.1.assets`. `STOCK_URL=<base>`
names another place, `STOCK=<dir>` a directory that already holds them, and
`AMIX_DISTFILES` is looked in first as for any distfile. The sha256 decides every
time; other bytes are not taken. They are not under this repository's licence.

### A public rebuild

The ROM register and the private list are the maintainers' and never enter this
repository. Anyone else builds with

```sh
make dist SYSTEM=../amix-system RELEASE_PUBLIC=1
```

The content check then runs its public tests: Kickstart headers, known-bad
modules, private addresses, credentials. The two lists only stop a release, and
never change what is built, so the tree and the lock are the same bytes. A release
of record is built with both lists.

`build/dist-proof WORKDIR [COMMIT]` is the proof itself: it clones
the commit twice, at two different paths under WORKDIR, runs every step in
each, and compares the two locks; with `LOCK=` each run is also checked
against the lock of record. Only `media`, not in make dist yet, may be a gap: the
run goes on and the summary names it as not compared. A gap in any other step,
or any other failure, stops it. `WORKDIR/summary` says what each step
did, and on which machine. `ELSEWHERE=<empty directory on another filesystem>`
puts the second clone there, which also compares the order directories list in;
without it the summary says that order was not compared. CI runs it by hand as
the dist workflow (`docs/ci.md`).

## out/

```
out/kit/{k30,k46}/            the ABI kits
out/kit/kit.digests           one line per kit (kernel/dlm/tools/kitdigest.sh)
out/modules/<line>/<name>     the generic module objects
out/kspace/{catalog,catalog.md5,pkgs/,beside/}
out/userland/{catalog,catalog.md5,pkgs/}
out/media/{cd,netinstall,floppies}/
out/lock
out/cache/                    distfiles, the stock packages and the port at its pin
out/build/                    work trees and logs
out/build/pkgtools-host/      make dist's own host pkgmk and pkgtrans, built from a
                              copy of userland/pkgtools (never the checkout's build-host/)
```

`out/` is ignored by git.

## The rules that make it reproducible

- **One version, one set of bytes.** A rebuilt package is byte-identical or it
  takes a new revision (`build/pkg`, the one-version guard). The roll stamps
  every time with the package version's own epoch: `SOURCE_EPOCH` in
  package.sh, or the last commit that changed the package directory, never the
  environment's `SOURCE_DATE_EPOCH`. The release's own epoch stamps only what
  is per release: the catalogs, the media and the lock.
- **The datastream is normalised** by pkgtools' pkgmk and pkgtrans and checked
  by `build/pkg/common/dsnorm.py`. A payload's static libraries get the member
  headers `ar D` writes (`build/pkg/common/arnorm.py`).
- **Toolchains.** A package builds with `gcc14` (userland), `period`
  (gcc-cross-amix, for a tool that must link only the stock libraries), or
  `none`: a script-only package, with no compiler at all. A `none` package
  that compiles anything is refused.
- **Paths.** gcc14 writes `/build` for the build tree, `/src` for the
  checkout and `/gcc14` for the toolchain (`-ffile-prefix-map`), and the roll
  refuses a build-host path in a gcc14 payload.
- **Cut ids** come from the cut record (`kernel/k30/cuts/<id>/`, the port's
  `cuts/<id>/`): a rebuild repeats them.
- **Inputs from outside** are pinned: the toolchains, amix-system and the port
  by commit (`.pin`), and the forks in `kernel/drivers/<name>/<name>.pin`.
  Distfiles are pinned by sha256 (`toolchain/*.distfile`, a package's
  `URL`/`SHA256`) and fetched in one order: `AMIX_DISTFILES=<dir>`, a local
  directory of them (make dist passes it into the container, read-only at
  `/distfiles`), then the original site, then our copy, a release asset of
  [amigaux/amix-distfiles](https://github.com/amigaux/amix-distfiles) at
  `releases/download/<name>-<version>/<the upstream's file name>`. The
  sha256 decides every time. Our copy is kept for the sources whose sites
  move (NetBSD, GitHub archive tarballs, SourceForge, the X11 set); a stable
  source with no copy simply has no fallback.
- **Known exceptions**, which the proof lists by name: the kits' revision lines
  (`kit.conf` and `NOTICE` name the commits, so the `norev` digest is the one
  compared across commits) and the installed disk and SD images, which are bench-built and proven by their contents.
