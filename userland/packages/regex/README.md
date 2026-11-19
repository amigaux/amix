# regex — Henry Spencer's regular expression library for Amix

The POSIX regular expression calls, `regcomp`, `regexec`, `regerror` and `regfree`, which Amix's
libc does not have (it has the older `regcmp` and `regex` in `libgen`), as Henry Spencer's library:
the one 4.4BSD took. Under `/opt/amix`:
- `lib/libregex.a` and `include/regex.h`;
- the manual pages `regex(3)` (the four calls, with an alias page for each name) and `regex(7)`
  (the expression syntax).

    sh build/pkg/pkgbuild.sh userland/packages/regex

The stock system documents other regular expression calls under the same names: `regex(3b)`
(BSD's `re_comp`), `regcmp(3g)` (libgen's `regcmp` and `regex`), `regexp(5)` (`compile` and
`step`) and FMLI's `regex(1f)`. This package's pages are `regex(3)` and `regex(7)`; `man 3 regex`
names this one.

Package: `regex`, category `library`, set `extra`. Built with GCC 14 (`-m68020-60 -mno-strict-align
-O2`). A program links it with `-I/opt/amix/include -L/opt/amix/lib -lregex`. CDE does.

**This revision is the static build**; a shared `libregex` follows when the add-on libraries go
shared. Nothing in the build ties it to one or the other.

## Source and licence

Release alpha3.8 (README: "alpha3.8 release, Tue Aug 10 15:51:48 EDT 1999"), from the repository
that keeps Spencer's releases, `github.com/garyhouston/regex`, pinned by commit (`70bc2965…`,
sha256 `ecc14060…009b1f`), with our archive copy in `amigaux/amix-distfiles` as the fallback.

The licence (SPDX `Spencer-94`, `COPYRIGHT`, installed in `/opt/amix/doc/regex`) permits any use,
alteration and redistribution on four conditions: the author is not responsible for the
consequences of use; the origin must not be misrepresented, and credits must appear in the
documentation; **altered versions must be plainly marked as such** and not misrepresented as the
original; the notice stays. This package is **not altered**: every source file is upstream's. The
build makes `regex.h` and the `.ih` headers with upstream's own `mkh` script, as its `Makefile`
does, and compiles with upstream's `-DPOSIX_MISTAKE` ("Do not take -DPOSIX_MISTAKE out"). The
credit: Henry Spencer wrote this library (`regex(3)`, `regex(7)`, `COPYRIGHT`). If a later revision
patches it, the patches are listed here and the package says it is altered.

## Test

On the emulator (released 1.1.1 disk, both kernels, 68060 and 68030): the package installs with
`apkg` and `pkgchk` is clean, and `re` passes every test in all three modes (no output).

Upstream's regression tester, `re` (`main.c`, `split.c`, `debug.c`), is linked with this
package's `libregex.a` and run on the box over upstream's `tests` file in its three modes (plain,
`-el`, `-er`), where no output means every test passed. It is built in the tree for that and not
shipped. Its `main.c` calls `getopt` and `exit` without including `<stdlib.h>`, as C89 allowed; the
build passes `-include stdlib.h` for the tester's objects instead of changing the source.
