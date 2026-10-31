# Continuous integration

`.github/workflows/ci.yml` runs on every push to `master` and on every pull
request against it. It is not required for a merge yet; a red run is a
finding to fix, not a gate.

## What it runs

| Job | Step | Command |
|-----|------|---------|
| privacy | the privacy check over the new commits | `tools/privacy-check --range BASE..HEAD` |
| tests | the privacy check's self-test | `tools/test-privacy-check` |
| tests | kernel/dlm host tests | `make -C kernel/dlm test` |
| tests | kernel/modules monsw host test | `make -C kernel/modules/monsw/module test` |
| tests | kernel/modules ramdisk host test | `make -C kernel/modules/ramdisk/module test` |
| tests | kernel/drivers a4091 host tests | `make -C kernel/drivers/a4091/test/host check` |
| tests | kernel/drivers z3660scsi host tests | `make -C kernel/drivers/z3660scsi/test/host check` |
| tests | build/pkg host tests (pkgmeta, the driver, the roll's normaliser) | `make -C build test` |
| tests | toolchain host tests (the distfile fetch, the m68k-gnu-bin shim) | `sh toolchain/test-tools` |
| tests | userland/packages and userland/base/pkg: every package.sh; `INDEX.md` and `conf/` in userland/packages current | `make -C build check-packages` |
| kit | amix-system at its pin, checked | `system/fetch-amix-system DIR` |
| kit | the build container (or the cached image) | `toolchain/container-build.sh DIR amix-toolchain:ci` |
| kit | the image's gcc14 is the pinned build (`toolchain/gcc14-cross-amix.tree`) | `toolchain/extract-g14.sh --check amix-toolchain:ci` |
| kit | the dlm kit, its tests and every module, in the container | `toolchain/container-kit.sh amix-toolchain:ci` |
| kit | the packaging harness selftests (68060 and gcc14 gates, one-version guard, the reproducible roll), in the container | `make -C build selftests` |

The range of the privacy check is the pull request's base to its head, or for
a push the previous tip of `master` to the new one. When there is no previous
tip (the first push of a branch) it checks the whole history (`--all`).

## Public rules only

The privacy check has public classes (private addresses, station files,
secrets, images and oversized blobs, the system files in
`system/MANIFEST.sha256`, AI attribution in our messages) and a maintainer's
local extras, read from the `PRIVACY_PATTERNS` and `PRIVACY_BLOCKED`
environment variables. The local list never enters this repository, so CI
runs the public classes only and says so in its log. Every maintainer's push
still runs the full check, local list included, from the pre-push hook.

## The kit job

The kit job builds the build container of `toolchain/` from the two
toolchain pins and the AMIX system files, then the dlm ABI kit for both
kernel lines, its tests and both lines of every module in kernel/modules,
all with the pinned compilers. The system files come from
`amigaux/amix-system` at the commit in `system/amix-system.pin`, checked
against `system/MANIFEST.sha256` and `system/SYMLINKS` before anything is
built; the 68040/68060 port comes from `kernel/port/port.pin`.

Building the container is most of the time, so the image is cached: a
`docker save` of it, compressed with zstd, under a key made from the files
it is built from (`Containerfile`, the pins, `container-build.sh` and the
`system/` pin, manifest and check). Any change to those builds a new image;
anything else loads the cached one. The image is about 650 MB of the
repository's 10 GB cache, and only the newest is useful: when a push to
`master` saves a new image, the job deletes the images of every other key
(it has `actions: write` for that alone). A restore that fails on the cache
service's side is tried once more before the image is built from scratch,
and the build retries apt against the Ubuntu snapshot service, which answers
5xx at times, for minutes: an index it cannot fetch fails the update, which
is tried again. The step summary lists the digest of
each kit and the sha256 of each module object; `kit.conf` and `NOTICE` name
the amix commit, so the kit's second digest leaves them out.

The harness selftests build the host packaging tools
(`userland/pkgtools/heirloom/build-host.sh`) first. The one-version guard's
selftest needs the kernel-space catalog of record, which stays in the
amix-packages clone until the kernel-space packages move; CI has none, so it
skips (exit 77) with a warning on the run. Locally it finds amix-packages
beside the main working tree, or `AMIX_KSPACE_REPO`. The reproducible-roll
selftest is the gate that a rolled `.pkg` is byte-identical when rolled again
from another path, at another time, under another umask and on another
filesystem (the container's `/tmp` and `/dev/shm`).

The container's gcc14 is the one gcc14 packages are built with, in CI and
on the host (`toolchain/extract-g14.sh` copies it out). The kit job checks
the image against its pin first, so the gcc14 gates' selftest runs against
the pinned compiler.

What CI does not build yet: the kernels and the boot media. Host-test cases
that need inputs outside this repository (stock kernels, floppies) skip
themselves and say so.

## Running it locally

Each step is an ordinary command; run it from the top of the repository. The
host tests need a C compiler, `make`, `python3` and zlib's headers
(`zlib1g-dev` on Debian and Ubuntu). The kit job needs docker (or podman,
with `CONTAINER=podman`) and network access to GitHub and the GNU mirrors.
