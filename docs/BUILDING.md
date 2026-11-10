# Building Amix: make dist

`make dist` builds the release from this checkout and one closed input, the
Commodore system files. It builds the ABI kits, the kernels, the modules and
drivers, both package catalogs, the package repository and the media, all
under `out/`, and writes a lock listing every input and output. Everything runs in
a build container, so the result does not depend on your machine: two builds of one
commit give the same bytes.

## In short

```sh
git clone https://github.com/amigaux/amix.git && cd amix
system/fetch-amix-system ../amix-system
make tools SYSTEM=../amix-system
make dist  SYSTEM=../amix-system RELEASE_PUBLIC=1
```

Run them from the top of the checkout. A relative path you give make dist
(`SYSTEM`, `LOCK`, …) is read from there. `make dist` ends with `make dist: done;
out/` and exits 0.

## What you need

- **A full clone**, not a shallow one (no `--depth`). A package's epoch, the time
  of every time stamp in it, is the last commit that changed its directory, so
  make dist reads the history and refuses a shallow clone.
- **docker or podman.** `CONTAINER=podman` uses podman. Your user must be able to
  run containers; the steps run in them as you, not as root.
- **Disk**: about 7 GB once built: the two images 3 GB (the media image shares
  all but 30 MB with the build container), `out/` 3.2 GB, the checkout and
  amix-system 0.5 GB. Docker's build cache needs room on top while `make tools`
  runs.
- **Time**: on a 32-thread x86-64 machine, `make tools` took 19 minutes with no
  docker cache, 9 of them downloading the image's packages from the Ubuntu
  snapshot service, and `make dist` 28 minutes. Fewer cores take longer.
- **Network** (https) for the first run: GitHub (amix-system, the toolchain
  sources, the pinned forks, the release assets that hold the stock packages and
  distfiles), `snapshot.ubuntu.com` (the image's packages, by date), and the
  package sources' own sites. Every download is pinned by commit or sha256.
  `AMIX_DISTFILES=<dir>` names a directory of distfiles to take first. What is
  fetched is kept in `out/cache`. The snapshot service answers 5xx at times, for
  minutes or longer; `make tools` then stops, and running it again later goes on.
- Nothing else on the host: no cross compiler, no Amiga, no Kickstart.

## The system files: amix-system

The Commodore system files are not in this repository. They are in
[amigaux/amix-system](https://github.com/amigaux/amix-system), at the commit
`system/amix-system.pin` names. `system/fetch-amix-system DIR` fetches that
commit into `DIR` (which must not exist) and checks every file against
`system/MANIFEST.sha256` and every link against `system/SYMLINKS`. make dist
checks it again before any step. Pass its path as `SYSTEM=`. Without `SYSTEM`,
make dist looks for `amix-system` beside the main working tree.

## make tools: the build containers

`make tools SYSTEM=…` builds two images.

- **`amix-toolchain:dist`**, the build container (`toolchain/Containerfile`,
  `toolchain/container-build.sh`). It is Ubuntu from a dated snapshot, with the
  two cross compilers built at their pins:
  - gcc-cross-amix, the period gcc 2.7.2.3 for kernel space;
  - gcc14-cross-amix, GCC 14 for userland, with amix-system's `usr/` as its
    sysroot.

  `/opt/amix/TOOLCHAIN.sha256` lists every toolchain file. Its GCC 14 is then
  checked against `toolchain/gcc14-cross-amix.tree` (`toolchain/extract-g14.sh
  --check`), as CI checks it.
- **`amix-toolchain:media`**, the media image (`toolchain/Containerfile.media`).
  It is the build container plus xorriso and amitools for the CD, floppy and
  disk images. Nothing below them is rebuilt: the image is refused if its
  toolchains differ from the build container's. `/opt/amix-media/TOOLS` names
  the tools' versions.

The images carry the toolchain pins they were built from. make dist stops
before any step if those are not the checkout's (`toolchain/check-image`), so
after a pin changes, run `make tools` again. `AMIX_IMAGE` and `AMIX_MEDIA_IMAGE`
name other images.

## make dist

Every step runs in the build container, as you, with this checkout at `/src`
and the system input read-only at `/system`. The fixed path keeps the period
compiler, which cannot remap paths, from building a checkout's own location
into its bytes. `DIST_HOST=1` runs the steps on your host instead, with the
toolchains `build/pkg/layout.sh` finds. That is for development; a release is
built in the container.

The exit status is 0 when every step built. A step that lacks an input says
so with a `[MISSING]` line: that is a gap. Its exit status is 3, the other
steps still run, and make dist names its gaps at the end and exits 3.
`make` itself turns any failure of its recipe into its own exit 2, so scripts
should call `sh build/dist.sh dist`, which exits 0, 1 (failed) or 3 (a gap).

### A public rebuild: RELEASE_PUBLIC=1

The `release` and `media` steps run a content check (`tools/release-check`).
It takes two lists the maintainers keep outside this repository:

- `ROM_MANIFEST`, the register of Kickstart ROMs that must never ship;
- `PRIVACY_PATTERNS`, the names that must never appear.

Without them, and without `RELEASE_PUBLIC=1`, those steps stop with a gap.
`RELEASE_PUBLIC=1` runs the check's public tests only: Kickstart headers,
known-bad modules, private addresses, credentials. The lists only stop a
release; they never change what is built, so a public rebuild gives the same
tree, media and lock. A release of record is built with both lists.

### The steps

In make dist's order, provider before consumer. Each is also a target of its
own (`make kit`, `make recipes/zlib`), at the top of the checkout or in
`build/`.

| Target | What it builds | Output |
|---|---|---|
| `kit` | kernel/dlm's ABI kits, k30 and k46, with the port at `kernel/port/port.pin` | `out/kit/{k30,k46,kit.digests}` |
| `kernel-k30` | the 68030 kernel: the cut of record (`kernel/k30/cuts/CURRENT`) rebuilt by `kernel/k30/cuts/build.sh`, which refuses sums other than the record's | `kernel/k30/build/cuts/<id>/`, its sums in `out/kernels/k30.list` |
| `kernel-k46` | the 68040/68060 kernel: the cut of record (`kernel/port/cuts/CURRENT`) rebuilt by `kernel/port/cuts/build.sh`, from the port at `kernel/port/port.pin` | `kernel/port/build/cuts/<id>/`, its sums in `out/kernels/k46.list` |
| `modules` | `kernel/modules/*/module` on both lines | `out/modules/<line>/<name>` |
| `drivers`, `drivers/<name>` | every driver module on both lines, on this checkout's kit: `kernel/drivers/{a4091,z3660scsi,z3660eth}/module` and the forks at their pins (cdfs, gayle-ide, paula, z3660rtg) | `out/modules/<line>/<name>` |
| `kspace` | the kernel-space packages: each `kernel/<dir>/pkg/build.sh` (dlm, k30, port, every module and driver), one version per name | `out/kspace/{pkgs,beside}/` |
| `userland`, `recipes/<name>` | every package of `userland/packages` and `userland/base/pkg`, each after the packages its `BUILD_DEPENDS` names | `out/userland/pkgs/` |
| `apkg` | APKG and APKGENG, by pkgtools' `make dist` | `out/apkg/` |
| `catalogs` | the kernel-space and userland catalogs, by pkgtools' `gen-catalog.py`; no time stamp, so a rebuild gives the same catalog | `out/{kspace,userland}/{catalog,catalog.md5}` |
| `release` | the 1.1 package repository, by pkgtools' `assemble-release.py`: both spaces' packages, APKG, the stock packages `stock-1.1.lock` names, and the published tree (`RELEASE_PREVIOUS=<dir>`, if any), then the content check | `out/release/1.1/{catalog,catalog.md5,pkgs/}` |
| `media` | the install CD, the netinstall CD, the boot floppies and the Z3660 boot disk, by `media/build.sh` in the media image, from the kernel-space packages and the 1.1 repository, then the content check; dated by `SOURCE_DATE_EPOCH`, else the commit's time | `out/media/` |
| `lock` | every input and output of the build (`release/README.md`); with `LOCK=<file>`, refuses a build that is not that lock | `out/lock` |

A step gets only its own inputs. `STOCK`, `STOCK_URL`, `RELEASE_PREVIOUS`,
`ROM_MANIFEST`, `PRIVACY_PATTERNS` and `RELEASE_PUBLIC` reach `release`; the
last three reach `media` too, with `SOURCE_DATE_EPOCH`, and `LOCK` reaches `lock`. So a name a kernel's
recipe reads for itself is never set by accident.

**The stock packages.** The `release` step takes the Commodore datastreams
`stock-1.1.lock` names by size, md5 and sha256. By default it fetches them into
`out/cache/stock-1.1/` from the release assets at the URL in
`system/stock-1.1.assets`. `STOCK_URL=<base>` names another place, `STOCK=<dir>`
a directory that already holds them, and `AMIX_DISTFILES` is looked in first, as
for any distfile. The sha256 decides every time. They are not under this
repository's licence.

**The RAM-disk images.** The media boot four RAM-disk images (a 2 MiB and a
6 MiB one per kernel line), which are made on a running Amix system, so no
container can make them. make dist takes them by sha256, like any distfile
(`media/inputs/*.distfile`), and the media step checks that they hold the boot
modules of this build's kernel-space packages; if not, it is a gap.

**Kernel-space recipes.** A kernel directory's recipes plug into `kspace` as
`kernel/<dir>/pkg/build.sh`. With no arguments it rolls all of them, with names
those. It reads `AMIX_BUILD_ROOT` (make dist sets `out/build/kspace`), writes each
`.pkg` to `$AMIX_BUILD_ROOT/kspace/pkg/`, and prints a `pkg <file> <sha256>` line
for each. It exits non-zero on a failure, and 3, with a `[MISSING]` line, when an
input outside the recipe is absent.

A file the media need that is no package goes to `$AMIX_BUILD_ROOT/kspace/beside/`,
then to `out/kspace/beside/` and the lock. `kspace_beside` in `build/dist.sh` lists
the files a directory must leave there (kernel/dlm: `amix-cdboot`). A missing one
after an exit 0 fails the step. The recipes set `SOURCE_DATE_EPOCH` from their own
pinned epoch, never the environment's. A driver directory's `pkg/build.sh` is three
lines around `build/pkg/common/kdrv.sh`, which rolls each recipe from the objects
the `drivers` step built.

## out/

```
out/kit/{k30,k46}/                   the ABI kits
out/kit/kit.digests                  one line per kit (kernel/dlm/tools/kitdigest.sh)
out/kernels/{k30,k46}.list           the kernel cuts' sums (the cuts in kernel/*/build/cuts/)
out/modules/<line>/<name>            the module and driver objects
out/kspace/{catalog,catalog.md5,pkgs/,beside/}
                                     the kernel-space packages and their catalog
out/userland/{catalog,catalog.md5,pkgs/}
                                     the userland packages and their catalog
out/apkg/                            APKG and APKGENG
out/release/1.1/                     the 1.1 package repository, as pkg.amigaux.org/1.1 serves it
out/media/                           amix-1.1-install.iso, amix-1.1-netinstall.iso,
                                     amix-1.1-boot-{k30,k46}-{1,2}.adf, amix-1.1-boot-z3660.hdf,
                                     MEDIA.txt, SHA256SUMS
out/lock                             every input and output (release/README.md)
out/cache/                           distfiles, the stock packages, the port at its pin
out/build/                           work trees and logs
```

`out/` is ignored by git. Delete it to start over; `out/cache` is worth keeping.

## Checking a build against a release

A release is three things, and each can be checked:

- **The lock**, `release/amix-<version>.lock`, which names every input and every
  output. `make dist … LOCK=<file>` rebuilds everything and refuses the result if
  any line differs, printing the lines that do. A gap leaves lines unbuilt, so it
  is refused too.
- **The package repository**, `http://pkg.amigaux.org/<version>`. Every
  `pkg release/<version> <file> <size> <sha256>` line of `out/lock` is the sha256
  of `pkgs/<file>` there.
- **The media**, on [amigaux/amix-media](https://github.com/amigaux/amix-media/releases),
  with a `SHA256SUMS` of every file. Every date on the media (the ISOs' file and
  volume dates, the boot store's set ids, the disk's file system) is the media's
  epoch: `SOURCE_DATE_EPOCH` if you set it, else the time of the commit built. The
  lock's `media-epoch` line says which. After a build, `make media` with the
  release's epoch remakes only the media, in a minute or two:

  ```sh
  make media SYSTEM=../amix-system RELEASE_PUBLIC=1 SOURCE_DATE_EPOCH=<the release's epoch>
  cd out/media && sha256sum -c --ignore-missing <the release's SHA256SUMS>
  ```

  `--ignore-missing` skips the release files make dist does not build (below);
  a file whose bytes differ is named `FAILED`.

## Building a past release

Each release is a tag, `1.1` and on, on the commit its kernels and packages were
built from. For a release whose media make dist built, the tag's own make dist
rebuilds all of it. For 1.1, check out the tag, build it, and check it against its
lock:

```sh
git show master:release/amix-1.1.lock > ../amix-1.1.lock
git checkout 1.1
make dist SYSTEM=$PWD/../amix-system RELEASE_PUBLIC=1 LOCK=$PWD/../amix-1.1.lock
```

Use an amix-system at that commit's pin, and images of its toolchain pins (the
`make tools` of the same checkout). At `1.1`, give the paths absolute, as above:
a relative path is read from the top of the checkout only since a later commit.

The tag `1.1` is older than `media/build.sh`: the 1.1 media were built by the
installer project before it moved into `media/` (commit 3cd5fa0 there, 8767589
here; `media/HISTORY-MAP.txt` maps every old commit to its new one). At `1.1`,
`media` is a gap: the lock check passes, and make dist names that gap (exit 3,
which `make` reports as 2).
Its packages are 1.1's, so make dist at `1b7d979`, the first commit whose make
dist builds the media and takes `SOURCE_DATE_EPOCH` for them, rebuilds the 1.1
media with 1.1's epoch, the time of the tag's commit:

```sh
git checkout 1b7d979
make dist SYSTEM=$PWD/../amix-system RELEASE_PUBLIC=1 SOURCE_DATE_EPOCH=$(git log -1 --format=%ct 1.1)
cd out/media && sha256sum -c --ignore-missing <amix-media 1.1's SHA256SUMS>
```

Six of the seven files are then byte for byte those of the amix-media 1.1
release: the netinstall CD, the four boot floppies and the Z3660 boot disk. The
install CD is named `FAILED`: it differs in one file, `/install/l11/INPUTS`, the
record of what it was built from: 1.1's names the earlier builder's inputs, a
rebuild's names make dist's by sha256.

## The SD card kit and the ready installed disk images

The Z3660 SD card kit (`amix-<version>-z3660-sd-kit.zip`) and the four ready
installed disk images (`amix-<version>-{k30,k46}-4g.zip`,
`amix-<version>-{k30,k46}-ide-2g.zip`) are not built by make dist yet. They are
checked by the release's `SHA256SUMS`, which also lists the four unzipped images.

- **The disk images** are made by installing the release in an emulator, from an
  install medium mastered for the purpose, onto a 3600 MiB disk (1800 MiB for
  IDE), and checking what was installed. A copy is booted once to test it; the
  image itself is never booted, so its first-boot questions are still to come.
  An install is not byte-for-byte reproducible, so the images are proven by their
  contents.
- **The SD card kit** is the Z3660 card's two partitions: the release's boot disk
  and ready installed 68060 system, with the card's fixed parts (its boot loader,
  the CPLD and SCSI ROM images, the settings and presets). The Z3660 firmware is
  a release file of its own.

For make dist to build them, their inputs must be pinned: the emulator install
as a build step, or its output pinned by sha256; and the card's fixed parts by
sha256 or by their upstream release. A Kickstart is needed to run the emulator
and never enters this repository.

## The rules that make it reproducible

- **One version, one set of bytes.** A rebuilt package is byte-identical or it
  takes a new revision (`build/pkg`, the one-version guard). The roll stamps
  every time with the package version's own epoch: `SOURCE_EPOCH` in
  package.sh, or the last commit that changed the package directory, never the
  environment's `SOURCE_DATE_EPOCH`. The media's dates are the commit's time,
  or `SOURCE_DATE_EPOCH` when it is set; the catalogs and the lock carry no
  time at all.
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
  Distfiles are pinned by sha256 (`toolchain/*.distfile`, `media/inputs/*.distfile`,
  a package's `URL`/`SHA256`) and fetched in one order: `AMIX_DISTFILES=<dir>`,
  a local directory of them (make dist passes it into the container, read-only at
  `/distfiles`), then the original site, then our copy, a release asset of
  [amigaux/amix-distfiles](https://github.com/amigaux/amix-distfiles) at
  `releases/download/<name>-<version>/<the upstream's file name>`. The
  sha256 decides every time. Our copy is kept for the sources whose sites
  move (NetBSD, GitHub archive tarballs, SourceForge, the X11 set); a stable
  source with no copy simply has no fallback.
- **Known exceptions**, which the proof lists by name: the kits' revision lines
  (`kit.conf` and `NOTICE` name the commits, so the `norev` digest is the one
  compared across commits) and the installed disk and SD images, which are not
  built by make dist (above).

## The proof

`build/dist-proof WORKDIR [COMMIT]` clones the commit twice, at two different
paths under WORKDIR, runs every step in each, and compares the two locks; with
`LOCK=` each run is also checked against the lock of record. A gap in any step
but `media`, or any other failure, stops it; a `media` gap is named in the
summary as not compared. `WORKDIR/summary` says what each step did, and on which
machine. `ELSEWHERE=<empty directory on another filesystem>` puts the second
clone there, which also compares the order directories list in. CI runs it by
hand as the dist workflow (`docs/ci.md`).

1.1 was proven so: at the tag `1.1`, a public rebuild gave one lock,
`release/amix-1.1.lock`, in four builds. Two were on a local machine (Intel
i9-13980HX, 32 threads), the second clone on a filesystem of its own. Two were in
the dist workflow on one CI runner. The CI image differs from the local one only
in four logs of the image build and the ldconfig cache, which no lock line shows.
That is two machines agreeing, and says nothing about a third; another commit
needs a proof of its own.
