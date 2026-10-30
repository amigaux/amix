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
| tests | build/pkg pkgmeta host test | `make -C build test` |

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

## What it does not run yet

Everything that needs the cross compilers: the dlm kit (`make kit`,
`kit-test`, the boot loaders), the module objects, and the kernels. Those run
once the build container of `toolchain/` is in CI. Host-test cases that need
inputs outside this repository (stock kernels, floppies) skip themselves and
say so.

## Running it locally

Each step is an ordinary command; run it from the top of the repository. The
host tests need a C compiler, `make`, `python3` and zlib's headers
(`zlib1g-dev` on Debian and Ubuntu).
