# release

`NOTICES.md` lists the acknowledgements the release notes must carry.

Lock files: the exact inputs and outputs of each release. None is here yet:
the lock of record for 1.1 is written when the 1.1 set is frozen.
`release/amix-<version>.lock` is the lock of the promoted candidate, written
by `make lock` (`build/mklock`) at the end of the make dist that built it.
A rebuild is proven against it:

```sh
make dist SYSTEM=../amix-system LOCK=release/amix-1.1.lock
```

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
previous <sha256>                     the catalog of the published tree the release is built on (RELEASE_PREVIOUS)

pin <path> <URL> <commit>             every one-line .pin in the checkout
pin <path> sha256 <sha256>            a .pin of another format, by its digest
distfile <path> <URL> <sha256> [<URL>...]
                                      every .distfile, as written: the original
                                      site, the sha256, then our copy
system <path> <sha256>                system/MANIFEST.sha256, system/SYMLINKS, system/stock-1.1.assets,
                                      release/carried-1.1

kit <line> <kabi> <manifest> <norev> KIT_REV=<c> PORT_REV=<c>|-
                                      out/kit/kit.digests, verbatim (kernel/dlm)
kernel <line> <path> <sha256>         each file of a kernel cut, as its hook prints it
                                      (out/kernels/<line>.list; the cut of record's sums)
module <line>/<name> <sha256>         out/modules
pkg kspace|userland|apkg|release/<rel> <file> <size> <sha256>
                                      out/{kspace,userland}/pkgs, out/apkg, and
                                      out/release/<rel>/pkgs (base/, stock/ below it)
catalog kspace|userland|release/<rel> md5 <md5> sha256 <sha256>
                                      the catalog (its md5 names it); catalog.md5 must agree
media <path> <size> <sha256>          out/media

exception <name> <why>                what the proof does not compare byte for byte
```

The exceptions are the kits' revision lines (`kit.conf` and `NOTICE` name the
commits, so across commits the kit's `norev` digest is the one compared) and the installed
disk and SD images (bench-built, proven by their contents). A release is built from a clean commit: a lock with a `dirty`
line is not one of record.

## What a release's packages are

Every live package rebuilds at the release's commit. Every published version
stays, so a repository also holds older versions, which that commit does not
build. `carried-<release>` lists them: each file, its sha256 and the commit whose
make dist rebuilds it, byte for byte. `make lock` refuses a tree whose older
versions are not exactly those. The stock packages are Commodore's: they are
checked by `userland/pkgtools/tools/repo/stock-<release>.lock`, not built.
