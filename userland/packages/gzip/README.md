# gzip — the recipe

**Package `gzip` 1.3.12** — GNU gzip, the `.gz` compressor. GPL-2.0-or-later.
Metadata and source pin: [`package.sh`](package.sh); build hooks: [`build.sh`](build.sh).

    sh build/pkg/pkgbuild.sh userland/packages/gzip

The highest day-one user value in batch 1: the first tool on the box that reads and writes the
universal `.gz`/deflate format, which **stock cannot touch** — stock compression is 1985 BSD/Spencer
`compress` (LZW, `.Z`) plus `pack`/`zcat`. gzip does not touch those; it installs alongside under
`/opt/amix`.

## Result

Builds clean — **zero implicit declarations, zero pointer/integer conversions**, m68k SVR4 ELF,
**D4-clean**. Like `patch`, it links **nothing** from libamixcompat: every undefined symbol in the
binary resolves from the stock `libc.so.1` (`fchmod`/`fchown`/`fileno` are all present as weak
symbols). **Bench-proven** on the emulated golden 030 (2026-08-30): stock `pkgadd`, a `.gz` round
trip byte-exact, a **host-produced** `.gz` decompressed byte-exact, `pkgchk` 0, `pkgrm` clean.

## Version — 1.3.12, and why the asm stays off

The gnulib wall for gzip is **1.4**, not the naive 1.3.6 (D5), so 1.3.12 is free headroom over the
archived 1.3.5. Its longest-match inner loop can be built from an assembler source; this recipe
seeds **`gzip_cv_assembler=no`** to force the C path (`config.h` has no `ASMV`, asserted by the
build). The SGS `#`-is-a-comment trap makes a mis-assembled `.s` a valid instruction with a clean
exit, so imported asm is banned.

## ★ The finding worth carrying — the cross wrapper defeats gnulib's header replacement

gzip 1.3.12 ships gnulib *replacement* headers (`lib/fcntl.h`, `lib/time.h`) meant to shadow the
system ones via the package's own `-I./lib` and add `O_BINARY=0`, `O_NOFOLLOW=0` and
`struct timespec` on a platform that lacks them. **They never win here.** The
`m68k-cbm-sysv4-gcc` wrapper hard-codes `-I<sysroot>/usr/include` at the **front** of every compile
(its `common_cflags`), *ahead* of `-I./lib`, so `<fcntl.h>` and `<time.h>` resolve to the 1992 SVR4
headers and the gnulib wrappers are dead. gzip therefore sees a pure SVR4 libc, and
[`patches/01-gzip-svr4-compat.patch`](patches/01-gzip-svr4-compat.patch) fills the four gaps that
opens directly in gzip's own `gzip.h` (`struct timespec`, `O_BINARY`/`O_NOFOLLOW`/`S_IRWXUGO`, plus
`fileno`/`fchmod` declarations the `__STDC__` gate / no-SVR4-header hides).
[`patches/02-utimens-timespec.patch`](patches/02-utimens-timespec.patch) does the same for gnulib's
`utimens.h`; its runtime path is a plain `utime()` (all the `futimes`/`utimes` config bits are off).

> **This is a `gcc-cross-amix` observation, not just a workaround.** The wrapper putting the sysroot
> include dir before the package's own `-I` defeats gnulib header replacement for *every* such
> package. Worth a look on the toolchain side.

## Package shape

`/opt/amix/bin/{gzip,gunzip,zcat}`, man pages under `/opt/amix/man/1/` with `whatis.d/gzip`, `COPYING`/`NEWS`/`README`
under `/opt/amix/doc/gzip/`. `gunzip` and `zcat` are gzip's own `/bin/sh` wrapper scripts
(`exec gzip -d` / `exec gzip -cd`) — gzip's `argv[0]` mode-detection is compiled out under the
default `GNU_STANDARD=1`, so they are wrappers, not symlinks. Their shebang is rewritten from the
build host's `/bin/bash` to `/bin/sh`; the body is pure Bourne, safe under Amix's 1992 shell. Pure
file payload, nothing outside `/opt/amix` (D9).

## GCC 14 build

The current package is built with GCC 14 (`TOOLCHAIN=gcc14`, revision `-6`, on gcc14-cross-amix
b51ff39); the period build stopped at `-2`. Three configure answers are pinned for it: `lstat`
(GCC 14 links the SVR4 way, `usr/ccs/lib/libc.so` being `libc.so.1` plus static members, so the
probe finds a static `lstat.o` the period link never saw; with `HAVE_LSTAT` gzip would treat
symbolic links differently from the bench-proven period build), and the absolute paths of
`fcntl.h` and `sys/time.h`. GCC 14's own copies of those two are C++-linkage wrappers that reach
AMIX's header with `#include_next`, which behaves as a plain `#include` in a file included by
absolute path, so gnulib's `lib/fcntl.h` would find itself again and `creat()` would be undeclared;
the configure assertion refuses any `ABSOLUTE_` header that is such a wrapper.
[`patches/03-gnulib-timespec.patch`](patches/03-gnulib-timespec.patch) (formerly
`patches-gcc14/01`) lets `gzip.h` and `lib/utimens.h` accept the `timespec` that gnulib's
`lib/time.h` declares under GCC 14.

The recipe moved to `package.sh` and hooks on 2026-10-30 without a revision: the rebuilt `-6` has
the recorded `-6`'s payload (every file's sha256 and mode), pkginfo, pkgmap (mtimes aside) and
catalog line.

## Revision -7: the catalog group

`-7` takes the P-31 §10.9 catalog group `archive` (it was `utility`), as a new revision because the category
is in the packed pkginfo. Built on the gcc14 container pin (amix 4af93f5): the payload is the
previous revision's, file for file (sha256 and mode); pkginfo differs in `VERSION`, `CATEGORY` and
`PSTAMP` only, and the pkgmap only in its `i pkginfo` line.

## Revision -8: man pages where `man` finds them

The man pages move to `/opt/amix/man/<sect>/<name>` with the package's whatis fragment
`/opt/amix/man/whatis.d/gzip` (docs/man-pages.md), where the base package's `man` and the stock
`man` find them; the pages are upstream's; `gunzip` and `zcat` are aliases. Built on the gcc14 container pin: every other payload file is the previous
revision's.
