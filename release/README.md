# release

Lock files: the exact inputs and outputs of each release.
`release/amix-<version>.lock` is the lock of the promoted candidate, written
by `make lock` (`build/mklock`) at the end of the make dist that built it
(P-38 S1.6). A rebuild is proven against it:

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
epoch package-version (...)           the epoch rule (P-38 D-b)
dirty <sha256>                        only when tracked files differ from the commit
image <sha256>|host                   the build container's /opt/amix/TOOLCHAIN.sha256, or "host"

pin <path> <URL> <commit>             every one-line .pin in the checkout
pin <path> sha256 <sha256>            a .pin of another format, by its digest
distfile <path> <URL> <sha256>        every .distfile
system <path> <sha256>                system/MANIFEST.sha256 and system/SYMLINKS

kit <line> <kabi> <manifest> <norev> KIT_REV=<c> PORT_REV=<c>|-
                                      out/kit/kit.digests, verbatim (kernel/dlm)
cut <id> <sha256>                     each kernel cut's SHA256SUMS (to come, P-38 S2)
module <line>/<name> <sha256>         out/modules
pkg kspace|userland <file> <size> <sha256>
catalog kspace|userland md5 <md5> sha256 <sha256>
                                      the catalog (its md5 names it); catalog.md5 must agree
media <path> <size> <sha256>          out/media

exception <name> <why>                what the proof does not compare byte for byte
```

The exceptions are the kits' revision lines (`kit.conf` and `NOTICE` name the
commits, so across commits the kit's `norev` digest is the one compared), amixbench 1.3
(kept outside amix), and the installed disk and SD images (bench-built, proven by
their contents). A release is built from a clean commit: a lock with a `dirty`
line is not one of record.
