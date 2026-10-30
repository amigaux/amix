# toolchain

The cross compilers that build Amix, pinned by commit, and the recipe of the
build container that holds them. Their sources stay in their own
repositories; nothing here is vendored.

## The pins

| File | Toolchain | Builds |
|------|-----------|--------|
| `gcc-cross-amix.pin` | GCC 2.7.2.3 and binutils 2.8.1 for `m68k-cbm-sysv4` | kernel space: kernels, loadable modules, drivers, the dlm kit |
| `gcc14-cross-amix.pin` | GCC 14.2.0 and binutils 2.43.1 for `m68k-elf`, with AMIX's return convention (pointers in `%a0` and `%d0`, structs in memory) | userland: C and C++ programs and libraries |
| `gcc14-cross-amix.tree` | the build of that commit amix uses: the digest of the container's gcc14 file list (below) | |

Each pin is one line, `<repository URL> <full commit hash>`, the same format
as `kernel/port/port.pin`.

gcc14-cross-amix is pinned in the organisation's fork, on the branch
`upstream-58130fe-plus`: Antti Sokero's upstream at `58130fe` plus two
commits on their way to it, one that builds the runtime for the whole
68020–68060 range so it also runs on a 68881/68882 (and checks that it does),
and one that refuses a sysroot without `stdint.h`. Once upstream has them, the
pin moves back to upstream. Kernel-space code is never built with GCC 14: it
has to be object-compatible with what AMIX itself was built with.

Both toolchains need an AMIX sysroot (the system headers, libraries and
startup objects). That is the `usr/` tree of `amigaux/amix-system`; see
`system/README.md`.

## The build container

`Containerfile` builds both toolchains from their pins on a fixed base image
(Ubuntu 24.04, pinned by digest, host packages from a fixed archive
snapshot, the same release as CI's runner). `container-build.sh` prepares its
inputs and runs the build:

```sh
system/fetch-amix-system /path/to/amix-system                 # at its pin
toolchain/container-build.sh /path/to/amix-system            # docker
CONTAINER=podman toolchain/container-build.sh /path/to/amix-system
```

It exports each toolchain's tree at the pinned commit with `git archive`,
fetched from the pin's URL, or from a local clone named by `GCA_REPO` or
`G14_REPO`. The GNU source tarballs are fetched by the build and checked
against their sha256, and the system input is checked against
`system/MANIFEST.sha256` first. A build from scratch takes about six minutes
on a 32-core machine, most of it GCC 14.

Reproducibility: every path inside the image is fixed (`/opt/amix-cross`,
`/opt/amix/...`), so no build folder, user name or host path of the machine
that builds it reaches the toolchains; `SOURCE_DATE_EPOCH` (the date of the
gcc14 pin's commit) sets the dates, and the members of every static archive
are normalised to it. `/opt/amix/TOOLCHAIN.sha256` lists the sha256 of every
installed file, so two builds are compared by that one file:

```sh
docker run --rm amix-toolchain:<tag> cat /opt/amix/TOOLCHAIN.sha256 > a.sha256
```

The image holds the AMIX sysroot, so it is built locally from a checkout of
`amix-system` and not published to a registry.

### Layout inside the image

| Path | What |
|------|------|
| `/opt/amix-cross/bin/m68k-cbm-sysv4-*` | gcc-cross-amix's tools; `-gcc` is its wrapper script |
| `/opt/amix-cross/m68k-cbm-sysv4/sysroot` | its sysroot |
| `/opt/amix/gcc-cross-amix/build/env.sh` | its environment (`PATH`, `AMIX_SYSROOT`, `AMIX_ROOT`) |
| `/opt/amix/gcc14-cross-amix/build/prefix/bin/m68k-elf-*` | GCC 14 |
| `/opt/amix/gcc14-cross-amix/build/prefix/m68k-elf/sysroot` | its sysroot, with the X11 pieces and `stdint.h`; `build/sysroot` links to it |
| `/opt/amix/amix-system/usr` | the AMIX root both were built from |
| `/opt/amix/TOOLCHAIN.sha256` | the hash list |

`GCA` and `G14` are set in the image's environment, and both toolchains are
on `PATH`.

## GCC 14 on the host

The gcc14 every package is built with is the container's: the build of the
commit in `gcc14-cross-amix.pin` that this Containerfile makes, pinned by
`gcc14-cross-amix.tree`. Its sysroot is inside the prefix, so the compiler
and the linker find it relative to where they are, and a copy outside the
container builds the same bytes. `extract-g14.sh` makes that copy:

```sh
toolchain/extract-g14.sh amix-toolchain:<tag>            # into out/toolchain/
toolchain/extract-g14.sh --check amix-toolchain:<tag>    # only check the image
```

It refuses an image whose gcc14 file list does not have the pinned digest,
checks every copied file against that list, and keeps the list as
`TOOLCHAIN.sha256` in the copy. The default place is
`out/toolchain/gcc14-cross-amix` in the main working tree (ignored), one copy
for every worktree of the checkout; `G14` is its `build/`, and that is
build/pkg's default (`build/pkg/layout.sh`). The packaging harness pins four
of its files (`build/pkg/common/gcc14-pin.sh`) and refuses any other
compiler.

Until 2026-10-30 the pin was a build of the same commit on a workstation.
The container's differs from it in every file the harness pins, none of it
in generated code: `specs` has no `-gz=zstd` (the container's binutils are
built without zstd); `cc1` and the other host programs were built by another
host compiler, and carry other build paths; `libgcc.a` and `libstdc++.a`
differ in their members' debug information and, in two `libstdc++.a`
members, in `__FILE__` strings, both of which name the build directory
(`/opt/amix/g14-work` here); `libamixc99.a` differs only in its archive
headers.

## How kernel/dlm uses them

kernel/dlm's kit build takes the toolchains through two variables:

- `GCA` is gcc-cross-amix's `build/` directory. The kit build sources
  `$GCA/env.sh` and uses the `m68k-cbm-sysv4` tools on `PATH`, the headers
  under `$AMIX_SYSROOT/usr/include`, and the stock headers under
  `$AMIX_ROOT/usr/include` and `$AMIX_ROOT/usr/sys`.
- `G14` is gcc14-cross-amix's `build/` directory, with the compiler in
  `prefix/` and the sysroot in `sysroot/`. Only the kit's tests and the
  boot-time tools need it, not the kit itself; they also run the checkout's
  `tools/check-68060-safe.py`, so `G14` has to sit inside a gcc14-cross-amix
  checkout, as it does in the image.

The 68040/68060 kit also needs `PORT`, a git checkout of the port at
`kernel/port/port.pin`. In the container, from the top of an amix checkout
mounted at `/src`:

```sh
docker run --rm -v "$PWD":/src amix-toolchain:<tag> sh -c '
  . "$GCA/env.sh" &&
  make -C kernel/dlm kit GCA="$GCA" PORT=/path/to/port'
```

`container-kit.sh IMAGE` does the same from the top of a checkout: it
fetches the port at its pin, runs `make kit kit-test` in kernel/dlm and
builds both lines of every module in kernel/modules in the container, as the
calling user. It then prints a digest of each kit and the sha256 of each
module object. CI runs it on every push; see `docs/ci.md`.

The install prefix does not enter the kit's bytes. A kit built in the
container can still differ from one built elsewhere in the host-compiled
`modfix` and in the revision lines of `kit.conf` and `NOTICE`, so compare a
container kit with a container kit.

## Updating a pin

Change the commit in the `.pin` file, rebuild the container, and compare
`TOOLCHAIN.sha256` with the previous image's to see what moved. Bump
`SOURCE_DATE_EPOCH` in `Containerfile` to the new gcc14 pin's commit date.
