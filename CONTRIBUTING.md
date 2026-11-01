# Contributing to amix

amix is one repository that builds the Amiga UNIX (Amix) system: the kernels
for the 68030 and the 68040/68060 (`kernel/`), the loadable-module system,
drivers and generic modules, the package tools and packaged software
(`userland/`), the install media (`media/`), and the build itself (`build/`,
`toolchain/`, `system/`, `release/`). `docs/BUILDING.md` explains how it all
fits together and how `make dist` builds a release.

## Sending a change

Fork the repository, make your change on a branch, and open a pull request
against `master`. Keep a pull request to one topic. It is merged without
squashing, so your commits stay as you wrote them. CI
(`.github/workflows/ci.yml`, see `docs/ci.md`) runs on every pull request and
must pass.

## Licence

amix is MIT licensed (`LICENSE`), and a contribution comes under the same
licence: no CLA, no sign-off line. A directory that carries someone else's
code keeps its own licence file.

## What never goes in

Commodore system files, Kickstart ROMs, disk and card images, and large
binaries. The system files the build needs come from
[amigaux/amix-system](https://github.com/amigaux/amix-system) at the commit in
`system/amix-system.pin`. `tools/privacy-check` refuses all of these, and CI
runs it over your commits.

## Building and testing

- The whole release: `make dist SYSTEM=<amix-system checkout>`, in the build
  container (`docs/BUILDING.md`); `make kit`, `make recipes/<name>` and the
  other steps build one part.
- The host tests need no Amiga and no cross compiler; CI runs the same:
  - `make -C build test`
  - `sh toolchain/test-tools`
  - `tools/test-privacy-check`
  - `make -C build check-packages` after changing a package recipe
  - in a directory with its own tests, e.g. `make -C kernel/dlm test`.

## Commit messages

Say what the commit changes, in the imperative, briefly: a subject line of at
most 72 characters, then, if needed, a few lines with the facts the diff
cannot show (why, measured numbers, hashes).

## Bugs and questions

- Questions and ideas: [Discussions](https://github.com/amigaux/amix/discussions).
- Bugs, feature requests and hardware support: open an issue with one of the
  forms at [github.com/amigaux/amix/issues/new/choose](https://github.com/amigaux/amix/issues/new/choose).
