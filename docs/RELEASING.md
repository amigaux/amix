# How releases are made

## Development

All work happens on `master` of this repository. Contributors fork it and open a
pull request against `master` (`CONTRIBUTING.md`); CI runs on every pull request.
`master` is never rewritten, so a commit hash cited anywhere stays valid.

## Betas

A beta of the next release is a pre-release of
[amigaux/amix-media](https://github.com/amigaux/amix-media/releases), named
`1.2-beta1`, `1.2-beta2` and so on. Its packages are in that release's own
repository, `http://pkg.amigaux.org/1.2`, so a beta never touches the
repository of a finished release.

## The release

The final release is tagged `X.Y` (for example `1.1`) in this repository and
in amix-media, and becomes GitHub's "latest" release of amix-media. The tag in
this repository is the commit `make dist` built the kernels and packages from.
The amix-media release carries the media, a `SHA256SUMS` of every file, and
the release's content check. The package repository is
`http://pkg.amigaux.org/X.Y`. Its lock (`release/amix-X.Y.lock`) records every
input and output of the build, and `docs/BUILDING.md` shows how to check a
build against both.

## After the release

From 1.1 on, an installed system is upgraded in place with `apkg`: a later
release brings its packages through the package repository, and nothing is
reinstalled. 1.1 itself installs only on a clean disk.

Fixes to a release come mostly as package updates in that release's repository:
a fixed package gets a new revision (one version, one set of bytes), and
`apkg` installs it. A release's repository keeps the older versions it shipped
(`release/carried-X.Y`), so a system can stay on one. New install media come
with the next release, or when a fix cannot be made as a package.
