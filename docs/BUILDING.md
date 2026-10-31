# Building Amix: make dist

`make dist` builds the release from this checkout and one closed input, the
Commodore system files: the ABI kits, the kernels, the modules and drivers,
both package catalogs and the media, all under `out/`. The plan is P-38
(*make dist for 1.1*); this page is how it works today. Steps that are not in
make dist yet say so and stop it (exit 3), naming the P-38 step and its owner.

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
on every machine. `AMIX_IMAGE` names another image, and `CONTAINER=podman`
uses podman. `DIST_HOST=1` runs the steps on your host instead, with the
toolchains `build/pkg/layout.sh` finds; that is for development, and a release
is built in the container.

## The steps

In make dist's order, provider before consumer. Each is also a target of its
own (`make kit`, `make recipes/zlib`), at the top of the checkout or in
`build/`.

| Target | What it builds | Output | P-38 | Status |
|---|---|---|---|---|
| `kit` | kernel/dlm's ABI kits, k30 and k46, with the port at `kernel/port/port.pin` | `out/kit/{k30,k46,kit.digests}` | S2.1, dlm | builds |
| `kernel-k30` | the 68030 kernel: the cut of record (`kernel/k30/cuts/CURRENT`) rebuilt by k30's hook `kernel/k30/cuts/build.sh`, which refuses sums other than the record's | `kernel/k30/build/cuts/<id>/` (kern30m reads it there), its sums in `out/kernels/k30.list` | S2.2, k30 | builds |
| `kernel-k46` | the 68040/68060 kernel, from the port's cut | | S2.3, port | not yet |
| `modules` | `kernel/modules/*/module` on both lines | `out/modules/<line>/<name>` | | builds |
| `drivers`, `drivers/<name>` | every driver module on both lines, on this checkout's kit: `kernel/drivers/{a4091,z3660scsi,z3660eth}/module` (a4091 with a4kt710) and the forks at their pins, fetched by commit (cdfs, gayle-ide, paula, z3660rtg; z3660rtg's `depend=monsw` on our monsw) | `out/modules/<line>/<name>` | S3.2 | builds |
| `kspace` | the kernel-space packages: each `kernel/<dir>/pkg/build.sh` in provider order (dlm, k30, port, the modules, the drivers), one version per name; a directory without one is named with its owner | `out/kspace/pkgs/` | S3.3, each directory with packages-fa | builds: kernel/dlm, kernel/k30 and kernel/port have recipes; the modules and drivers to come |
| `userland`, `recipes/<name>` | every package of `userland/packages` and `userland/base/pkg`, one version per name | `out/userland/pkgs/` | S4.1 | builds |
| `catalogs` | the kernel-space and userland catalogs, by pkgtools' `gen-catalog.py` over each space's packages, with tools/repo's confs as the staging layer and the space's own: `userland/packages/conf`, and `kernel/conf` for kernel space (its `names.conf` names each kernel package; kernel packages without it are refused); no time stamp, so a rebuild gives the same catalog | `out/{kspace,userland}/{catalog,catalog.md5}` | S5.1, pkgtools | builds |
| `media` | the CD, netinstall and floppy media | `out/media/` | S6.1, installng | not yet |
| `lock` | every input and output of the build (`release/README.md`); with `LOCK=<file>`, refuses a build that is not that lock | `out/lock` | S1.6, infra | builds |

`make tools` builds the container (`toolchain/container-build.sh`).

A kernel directory's recipes plug into `kspace` as `kernel/<dir>/pkg/build.sh`:
with no arguments it rolls all its recipes, with names those; it reads
`AMIX_BUILD_ROOT` (make dist sets `out/build/kspace`), writes each `.pkg` to
`$AMIX_BUILD_ROOT/kspace/pkg/`, prints a `pkg <file> <sha256>` line for each,
and exits non-zero on a failure. It exits 3 when an input outside the recipe
is absent, with a `[MISSING]` line naming the P-38 step and owner (a kernel
cut's output, for one); the step then runs the other directories and ends
with exit 3. Its recipes set `SOURCE_DATE_EPOCH` from
their own pinned epoch, never the environment's.

A release is proven against its lock: `make dist SYSTEM=… LOCK=release/amix-<version>.lock`
rebuilds everything and refuses the result if any line of its lock differs
(`release/README.md`).

## out/

```
out/kit/{k30,k46}/            the ABI kits
out/kit/kit.digests           one line per kit (kernel/dlm/tools/kitdigest.sh)
out/modules/<line>/<name>     the generic module objects
out/kspace/{catalog,catalog.md5,pkgs/}
out/userland/{catalog,catalog.md5,pkgs/}
out/media/{cd,netinstall,floppies}/
out/lock
out/cache/                    distfiles and the port at its pin
out/build/                    work trees and logs
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
  compared across commits), amixbench 1.3 (kept outside amix), and the installed
  disk and SD images, which are bench-built and proven by their contents.
