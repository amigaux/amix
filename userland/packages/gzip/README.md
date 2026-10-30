# gzip — the recipe

**Package `gzip` 1.3.12** — GNU gzip, the `.gz` compressor. GPL-2.0-or-later.
Pin: [`pin.sh`](pin.sh).

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

`/opt/amix/bin/{gzip,gunzip,zcat}`, man pages under `/opt/amix/man/man1/`, `COPYING`/`NEWS`/`README`
under `/opt/amix/doc/gzip/`. `gunzip` and `zcat` are gzip's own `/bin/sh` wrapper scripts
(`exec gzip -d` / `exec gzip -cd`) — gzip's `argv[0]` mode-detection is compiled out under the
default `GNU_STANDARD=1`, so they are wrappers, not symlinks. Their shebang is rewritten from the
build host's `/bin/bash` to `/bin/sh`; the body is pure Bourne, safe under Amix's 1992 shell. Pure
file payload, nothing outside `/opt/amix` (D9).
