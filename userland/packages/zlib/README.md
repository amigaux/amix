# zlib — the recipe

**Package `zlib` 1.2.13** — the deflate/inflate compression library, static. SPDX `Zlib`.
Metadata and source pin: [`package.sh`](package.sh); build hooks: [`build.sh`](build.sh).

    sh build/pkg/pkgbuild.sh userland/packages/zlib

The first library this line ships, and BATCH-1's sole remaining Wave-0 item. It is the foundation
`rsync`, `wget` and (one day) `git` link. Shipped **static** in the first cut — the `-G`/`-h` SONAME
shared path is unproven here and a library is the wrong place to debug it (`docs/porting.md §2.5`).

## Result

Builds clean. libz.a is a valid m68k SVR4 archive, **D4-clean** (no `mulu.l`/`muls.l` with a
`Dh:Dl` destination — CRC and adler32 are 32-bit). **Bench-proven** on the emulated golden 030
(2026-08-30): `pkgadd` with the stock engine, the shipped `/opt/amix/bin/zlib-test` reported PASS,
`pkgchk` 0, and it survived `pkgrm` of the batch's gzip/grep beside it.

## Why 1.2.13 and not newer

zlib **≥ 1.3.2 silently stubs `gzprintf()`** unless built `-DZLIB_INSECURE` — a compression
library that quietly writes nothing is exactly the failure class this campaign exists to avoid.
1.2.13 predates the change, is integer-only, ships its own hand-written `./configure` (no autotools,
no gnulib wall), and its only assembler is x86-64 `contrib/` never touched by the default build.

## The one interesting decision — configure is used, the objects are not built by it

zlib's `./configure` is cross-safe here for one reason: **SVR4.0 has `size_t`**, so the size_t
probe passes and configure never reaches its single run-test (`sizet=\`./$test\``), the one probe
that would try to *execute* an m68k binary on the build host. Every other probe is compile- or
**link**-only, and a link probe links against the *target* `libc.so.1`, so a missing symbol fails
it correctly (`off64_t` absent, `fseeko` absent → `-DNO_FSEEKO`, right for a 1992 SVR4).

But one probe cannot reach its correct answer: the `vs[n]printf` test links with `$CC $CFLAGS`
only — it never threads `LDFLAGS`/`LIBS` — so it cannot see `libamixcompat`, concludes vsnprintf is
absent, and would bake `-DNO_vsnprintf -DNO_snprintf` into the Makefile, switching `gzprintf()` to
the **unbounded** `vsprintf`/`sprintf` path (the SHIM-SNPRINTF blocker). So this recipe runs
configure only for what it does right — generate `zconf.h`, report the platform — and **compiles
the fixed object list itself** (exactly as `acompat/`, the libamixcompat library, does), with *no* `NO_*` macro, so
`gzwrite.c`/`gzlib.c` take their default **secure** `vsnprintf(next, state->size, …)` path. The two
symbols resolve from `libamixcompat` at the consumer's final link, and the build **asserts via
`nm`** that libz.a really references `vsnprintf`/`snprintf` — checking the artifact, not the
configure log, as the blocker asks.

The only tolerated implicit declarations are `snprintf`/`vsnprintf` in the two gz TUs: Amix's
`<stdio.h>` does not *declare* them (the symbols live in libamixcompat), but their real return type
**is** `int`, so gcc 2.7's invented `int f()` prototype loses nothing.

## Package shape

`/opt/amix/lib/libz.a`, headers `/opt/amix/include/{zlib.h,zconf.h}`, the man page at
`/opt/amix/man/man3/zlib.3`, `LICENSE`/`README`/`ChangeLog` under `/opt/amix/doc/zlib/`, and the
on-box acceptance binary `/opt/amix/bin/zlib-test`. Nothing lands outside `/opt/amix`; there is no
stock file to conflict with. Pure file payload (`CLASSES=none`, D9).

## On-box evidence

[`tests/zlib-test.c`](tests/zlib-test.c) is shipped in the package and linked against exactly this
libz.a. It runs three checks a byte-order or struct-packing mistake could not all pass: crc32 and
adler32 of a fixed string against **algorithm-defined** constants (the endianness canaries), a 4 MB
`deflate`→`inflate` round trip byte-compared back, and `inflate` of a zlib stream produced by the
**host's** zlib (cross-decompression, the half a shared-bug round trip would hide).
[`tests/smoke.sh`](tests/smoke.sh) — pre-POSIX Bourne — runs it and reports the verdict.

## GCC 14 build

The current package is built with GCC 14 (`TOOLCHAIN=gcc14`, revision `-6`, on gcc14-cross-amix
b51ff39); the period build stopped at `-2`. It uses the framework's `hooks` style: `build.sh`'s
`build` hook runs zlib's own configure, compiles the fifteen objects itself (each compile line in
`make.log` for the strict gates) and links `zlib-test`. Under GCC 14 `snprintf`/`vsnprintf` come
from the toolchain runtime `libamixc99`, so nothing from libamixcompat is linked. `contrib/` is
removed before the build (`ASM_REVIEWED`): it holds only x86 assembly.

The recipe moved to `package.sh` and hooks on 2026-10-30 without a revision: the rebuilt package has
the recorded one's payload (every file's sha256 and mode; `libz.a` member by member, the member headers carrying build-time mtimes), pkginfo, pkgmap (mtimes aside) and
catalog line.

## Revision -7: the catalog group

`-7` takes the P-31 §10.9 catalog group `library` (it was `development`), as a new revision because the category
is in the packed pkginfo. Built on the gcc14 container pin (amix 4af93f5): the payload is the
previous revision's, file for file (sha256 and mode); pkginfo differs in `VERSION`, `CATEGORY` and
`PSTAMP` only, and the pkgmap only in its `i pkginfo` line.
