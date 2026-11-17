# release

`NOTICES.md` lists the acknowledgements the release notes must carry.

Lock files: the exact inputs and outputs of each release, written by
`make lock` (`build/mklock`) at the end of the make dist that built it.

- `amix-1.1.lock` (sha256 `671008eef95ec93ddfbb3834a4cfe65fe8ff0d63199d94d697b1f6aaee20e8c5`):
  1.1 as anyone rebuilds it, at the tag `1.1` with `RELEASE_PUBLIC=1`. A rebuild
  is proven against it.
- `amix-1.1-published.lock` (sha256 `caeca5303363d5de7695dc42d77461abe041e9339801748390d6cf1993f77992`):
  the record of what `http://pkg.amigaux.org/1.1` holds. It is the first lock
  plus a `previous` line, the digest of the catalog published before it; the
  published catalog (md5 `d630412aa9558451de52f10765e13951`) in place of the
  rebuild's; and the 24 older versions `carried-1.1` names, which that
  repository keeps. That earlier catalog is no longer served, so this lock
  is a record, not something a rebuild is checked against.

```sh
git show master:release/amix-1.1.lock > ../amix-1.1.lock
git checkout 1.1
make dist SYSTEM=$PWD/../amix-system RELEASE_PUBLIC=1 LOCK=$PWD/../amix-1.1.lock
```

The tag is older than this file, so the lock goes in as a copy from outside
the checkout, and at the tag the paths must be absolute (`docs/BUILDING.md`).

## A point release: 1.1.1

A point release adds to its release's repository; it does not start a new
one. 1.1.1 is built at its commit on the published 1.1 tree:

```sh
make dist SYSTEM=… RELEASE_PREVIOUS=<the published 1.1 tree>
```

The release step keeps every published file byte for byte (a published name
and version whose bytes differ is refused), adds the new versions, and moves
a live version that a newer one replaces to the catalog's older block, where
`carried-1.1` must name it. Against 1.1, 1.1.1 adds buddha-k30 and buddha-k46
1.1.0-4 and xsurf-k30 and xsurf-k46 1.0.0-3, and kbootset 1.1.0.261114-45
replaces 1.1.0.261105-43, which `carried-1.1` lists at the tag `1.1`. The
kernels and every other package are 1.1's. Its locks are as for 1.1, both
built at amix 7d9e944f:

- `amix-1.1.1.lock` (sha256 `29f765aecb959dbb1e031e10d1db513af09625d7f0c75c3b1f1cf72c0f6eec9f`):
  1.1.1 as anyone rebuilds it, with `RELEASE_PUBLIC=1` and no published tree.
  A rebuild is proven against it.
- `amix-1.1.1-published.lock` (sha256 `b37fb273039da097a2afc9477d11c8b09a956df18d0f3b81dda1ab0d674143fd`):
  the record of what `http://pkg.amigaux.org/1.1` holds with 1.1.1, the same
  build on the published 1.1 tree. It differs from the first only in its
  `previous` line (the digest of 1.1's catalog), the catalog (md5
  `ec6ab6f48fa71aec70df78717f35ab86` for the rebuild's
  `394ff54b7715ee3818beb8a575ac880d`) and the 26 older versions `carried-1.1`
  names. The media are the same bytes in both.

## A point release with new kernels: 1.1.2

1.1.2 is built the same way, at its commit on the published 1.1.1 tree. Against
1.1.1 it adds amix-base 1.0-36, APKG 0.3.13, kbootset 1.1.0.261115-46, both
kernels (kern30m k30.1.5.261115-78, kern46m k46.1.6.261115-67), prngd 0.9.29-4,
x11r6.3 6.3-11, xsurf-k30 and xsurf-k46 1.0.0-4, z3660rtg-k30 and -k46 1.1.2-3,
and the new va2000-k30 and va2000-k46 1.1.0-2. The versions they replace move
to the older block, and every 1.1.1 file is kept byte for byte. Its lock, built
at amix ec9dfd6e twice with the same result:

- `amix-1.1.2-published.lock` (sha256 `fc73999a22892c9bac3fb287a6facaed6103f8f31c8689ccfd9f5fe50124891d`):
  the record of what `http://pkg.amigaux.org/1.1` holds with 1.1.2 (catalog md5
  `5c958843dc71e9fda47246eba056610d`), the build on the published 1.1.1 tree.
  Its `previous` line is the digest of 1.1.1's catalog. The media were not
  part of this release: the step stops at the 1.1 RAM-disk images, which do
  not hold the new kernels' modules, so the lock has no lines for them.
- 2026-11-17, a catalog-only update: the repository's catalog went from md5
  `5c958843dc71e9fda47246eba056610d` to md5 `6c837186584ce26f812b1aa41c7d9e0f`
  (sha256 `4fb4ebff63a1364c9410282bd709c94ef894c37f6e23416f129ac9980cef06ea`).
  No package file changed. The only difference is in the two xsurf-k30 and
  xsurf-k46 1.0.0-4 lines, which lose `kbootset=1.1.0.261114-45`. That floor
  is at `module-floor-base`, and apkg 0.3.11 refused the line, so a 1.1 or
  1.1.1 box left xsurf out of its first upgrade. It was built at amix
  be3d20f1 on the published 1.1.2 tree, twice with the same result; the lock
  above stays the record of 1.1.2 as published.

A box upgrades with the apkg it has. On a 1.1 or 1.1.1 box (apkg 0.3.11),
the first `apkg upgrade` brings APKG 0.3.13. A module row that names a
kbootset above `module-floor-base` (`kernel/conf/kbootset.conf`, C2-2 v8),
such as va2000's, installs only after that, by name or in the next upgrade.
The release step checks this: pkgtools' `older-apkg-check.sh` runs the apkg
of every earlier release of the series, built from its tag, against the
written tree. A row it refuses fails the step; a row that only has to wait
is named on a WAIT line.

`make lock LOCK=<file>` writes nothing; it refuses a build in `out/` whose
lock differs from `<file>`, and prints each line that differs (`-` in the lock
of record, `+` in this build).

## The format

Text, one item per line, fields separated by single spaces. The first line
says which format it is. The head comes next, then sections in a fixed order,
each sorted in C order, so one build has one lock.

```
#amix-lock 1
amix <commit>                         the amix commit built
epoch package-version (...)           the epoch rule
dirty <sha256>                        only when tracked files differ from the commit
image <sha256>|host                   the build container's /opt/amix/TOOLCHAIN.sha256, or "host"
media-tools <sha256>                  the media image's /opt/amix-media/TOOLS, when the media step ran
media-epoch <seconds>                 the media's dates (SOURCE_DATE_EPOCH, else the commit's time), when it ran
previous <sha256>                     the catalog of the published tree the release is built on (RELEASE_PREVIOUS)

pin <path> <URL> <commit>             every one-line .pin in the checkout
pin <path> sha256 <sha256>            a .pin of another format, by its digest
distfile <path> <URL> <sha256> [<URL>...]
                                      every .distfile, as written: the original
                                      site, the sha256, then our copy
system <path> <sha256>                system/MANIFEST.sha256, system/SYMLINKS, system/stock-1.1.assets,
                                      release/carried-1.1
stock userland <name>-<version> <path> <sha256> [patched <sha256>]
                                      each amix-system file a userland package carries:
                                      copied (STOCK_ETC), or patched by its stage hook
                                      (STOCK_PATCHED); from the recipe's BUILD.txt
source userland <name>-<version> <pin> <URL> <commit> <path> digest <sha256>
                                      each directory of a pinned fork a userland package
                                      copies into its source (FORKDIRS): the path in the
                                      fork and the digest of its files; from BUILD.txt

kit <line> <kabi> <manifest> <norev> KIT_REV=<c> PORT_REV=<c>|-
                                      out/kit/kit.digests, verbatim (kernel/dlm)
kernel <line> <path> <sha256>         each file of a kernel cut, as its hook prints it
                                      (out/kernels/<line>.list; the cut of record's sums)
module <line>/<name> <sha256>         out/modules
pkg kspace|userland|apkg|release/<rel> <file> <size> <sha256>
                                      out/{kspace,userland}/pkgs, out/apkg, and
                                      out/release/<rel>/pkgs (base/, stock/ below it)
beside kspace|apkg <path> <size> <sha256>
                                      out/<space>/beside: what a recipe builds beside
                                      its packages, for the media
catalog kspace|userland|release/<rel> md5 <md5> sha256 <sha256>
                                      the catalog (its md5 names it); catalog.md5 must agree
media <path> <size> <sha256>          out/media

exception <name> <why>                what the proof does not compare byte for byte
```

The exceptions are the kits' revision lines (`kit.conf` and `NOTICE` name the
commits, so across commits the kit's `norev` digest is the one compared) and the installed
disk and SD images (bench-built, proven by their contents). A release is built from a clean commit: a lock with a `dirty`
line is not one of record.

## Packages that ship together

`together-<release>` lists pairs a release tree must carry together, one rule a
line: `<name> <version>: needs <name> <version>`. When the release catalog's live
row for the first name is at least its version, the second's must be at least
its version, or the release step refuses the tree (`build/release-together`,
versions in apkg's order). A module's own kbootset floor is not listed here: its
catalog row carries it (`kbootset=`).

## What a release's packages are

Every live package rebuilds at the release's commit. Every published version
stays, so a repository also holds older versions, which that commit does not
build. `carried-<release>` lists them: each file, its sha256 and the commit whose
make dist builds it. For 1.1, 24 of the 25 came out byte for byte at their commit:
the b97a720 rows once, on one local machine, the 6029ab5 rows in the proof there
(two clones, two file systems). x11r63-6.3-7 does so only on the file system it was
built on, as `carried-1.1` says. `build/dist-proof` does not rebuild them. `make lock`
refuses a tree whose older versions are not exactly those, by name and sha256.
For what the proof has shown of the live packages, see `docs/BUILDING.md`.
The stock packages are Commodore's: they are
checked by `userland/pkgtools/tools/repo/stock-<release>.lock`, not built.
