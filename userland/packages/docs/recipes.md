# Recipes — the traps they encode, and why they are hand-written

The package directory, the `package.sh` keys and the driver are described in
[`build/pkg/README.md`](../../../build/pkg/README.md); the shared harness (the build environment,
the fetcher, the gates, the roll, `amix-cpp` and the C shims) is in `build/pkg/common/`. The
packages and their versions are in [`../INDEX.md`](../INDEX.md). The constraints every recipe
inherits are in [`porting.md`](porting.md).

This file keeps what the recipes and the harness encode, and why: the toolchain traps that shaped
them, the prototype rules, and the two rules that keep recipes hand-written. Paths are relative to
`userland/packages`, except `build/…` and `userland/pkgtools/…`, which are relative to the top of
amix. The traps below were found on the period toolchain (GCC 2.7.2.3); the gates they produced
run on every build, GCC 14 included.

## ★ The trap that makes `amix-cpp` exist

`m68k-cbm-sysv4-gcc -E` **did not** preprocess. The wrapper had cases for `-c` and `-S`; `-E` fell
through to its "unrecognised dash argument is an ld flag" branch, so it **linked** the file and
exited 0 with a linker complaint on stderr. Autoconf rejected `$CC -E` and fell back to **`/lib/cpp`,
the build host's preprocessor** — after which every `AC_CHECK_HEADER` presence test read the *host's*
`/usr/include`, and autoconf 2.5x resolves a presence/usability disagreement by *trusting the
preprocessor*. `patch` got `HAVE_WCHAR_H 1` for a header Amix does not have. That one failed loudly;
the same mechanism sets `HAVE_*` for anything that merely looks present on a modern Linux host, and
most of those fail quietly.

**★ FIXED 2026-08-29** (`gcc-cross-amix` 3c2d272): the wrapper now dispatches `-E` to the real
compiler with its own target include path, exactly as `-S` was already dispatched, so
`m68k-cbm-sysv4-gcc -E` preprocesses correctly and autoconf no longer falls back to the host's
`/lib/cpp`. The trap above is kept in full because it is the reason `amix-cpp` exists and it
explains why every recipe so far still passes it as `CPP`: `amix-cpp` calls `gcc.real -E` directly
with the sysroot include path added by hand, which is exactly what the wrapper now does internally
— it was never broken by the wrapper's old defect and is not made redundant by the fix, so nothing
here needs to change. A *new* recipe may pass `$CC` directly as `CPP` instead.

## ★ The D4 gate could not fire until 2026-09-26

It grepped `objdump -d` for `mulu.l …,%dH:%dL`. binutils 2.8.1's objdump prints MIT syntax —
`mulul %fp@(12),%d1,%d2`, no dot, no colon — so the pattern never matched and every package
reported "D4 ok" whatever it contained. The gate now classifies each `MUL.L`/`DIV.L` from its
opword and extension word (bit 10 = the 64-bit form; opword `0x4c3c` = the `#imm` source the
kernel's vector-61 handler emulates), and `amix_gate_d4_selftest` must see it reject a probe
before a build may trust a pass. Re-scanned under the real gate: the published `grep` 2.5.1a
**fails** (two register/memory-source multiplies in gnulib's `strtoull`/`xstrtoumax`); the other
published packages and the `amix-benchmark` binaries pass. The fix for a failing site is to route
the product through libgcc's `__muldi3` (built from 32-bit multiplies only) — ROADMAP D4's
"build the TU `-m68000`" does not work here, because this `libgcc.a` has no
`__mulsi3`/`__divsi3`/`__udivsi3`/`__umodsi3`.

## ★ 2026-10-05: D4 is strict — no 64-bit multiply in any form

The `#imm` source form the gate used to allow is what gcc 2.7.2.3 emits for every divide or modulo
by a constant, and a 68060 traps it like the others (Amix SIGKILLs; the release ships nothing that
leans on kernel emulation). The cure is the toolchain's: gcc-cross-amix `2ab2b22` fix_asm rule 11
rewrites each 64-bit multiply into 16x16 `mulu.w` partial products. `amix-env.sh` refuses
`AMIX_MUL64=keep` and sets `AMIX_SCAN060=1` (the wrapper scans each object it compiles);
`amix_gate_d4` fails on any 64-bit `MUL.L`/`DIV.L`, `movep`, `cmp2`/`chk2`/`cas2`, with three
scanners: the awk one, the toolchain's `m68k-cbm-sysv4-scan060` (run with a modern
`m68k-linux-gnu-objdump`: binutils 2.8.1 prints a linked binary's `0x8000xxxx` addresses
sign-extended, the scanner then misses every switch table and reports table words as `movep`) and
`userland/pkgtools/tools/repo/scan060.py` (the scanner of record for linked files and `.pkg`;
it does not open `ar` archives). `amix_pkgroll` runs the gate over the whole staged payload before
`pkgmk` and `scan060.py` over the rolled datastream after, and checks pkginfo `VERSION` against the
datastream name. `build/pkg/tests/gate060-selftest.sh` proves every layer rejects an unsafe artifact.
The `__muldi3` routing in `grep`/`tar` patches stays (harmless, and still correct).

## ★ Two wrapper link rules, both silent when broken

1. **An archive named on the command line lands *before* the objects.** The wrapper collects
   `foo.a` while parsing, then *appends* the objects it compiles from `.c` sources, so
   `gcc prog.c libfoo.a` links as `libfoo.a prog.o` — single-pass `ld` extracts nothing and every
   symbol in the archive comes back undefined. Use `-L`/`-l`, which land after the objects.
2. **Any explicit `-l` suppresses the implicit libc.** The wrapper defaults to `libs=(c)` only when
   *no* `-l` was given, so `-lacompat` alone drops libc entirely — and the first casualties are
   `crt1.o`'s own `atexit`/`exit`/`_environ`, which makes it look like a broken toolchain rather
   than a missing flag. **Always end the library list with `-lc`**, including in a configure-filled
   `LIBS=`.

## How an authored prototype stays free of host paths

The obvious prototype line is
`f none /usr/local/bin/patch=/home/…/build/dest/usr/local/bin/patch`, and it makes the file
*generated*, because half of it is one developer's home directory. `build/pkg/common/pkgroll.sh` runs
**`pkgmk -r <destroot>`**, which resolves each prototype path against the staged tree instead — so
what is committed is exactly the package's installed layout and nothing about anybody's machine.

## Why the two oldest packages sit at `/usr/local`

**Superseded as policy.** The shared prefix is `/opt/amix` ([`coexistence.md`](coexistence.md) §1, ROADMAP D11).
What follows is the reasoning that put `libamixcompat` and `patch` there before that policy was
settled, kept because those two packages are still minted at `/usr/local`.

Not a convention borrowed from elsewhere: **the stock Amix PATH already begins with it**
(measured on the box) —

    PATH=/usr/local/bin:/usr/bin:/usr/ccs/bin:/sbin:/usr/sbin:/etc:/usr/ucb:/usr/amiga/bin:
         /usr/public/bin:/usr/hosts

so a package installed there takes precedence over `/usr/public/bin` without displacing anything,
and `/usr/local` plus `/usr/local/bin` already exist on a stock root (dated Nov 1991). `/usr/apkg`
is taken by the package manager's own parallel prefix.

## ★ Symlink targets must be ABSOLUTE

Measured on the box, same `.pkg`, same admin file, only the engine differing:

| engine | result |
|---|---|
| stock `/usr/sbin/pkgadd` | `/usr/bin/patch -> /../local/bin/patch` — **dangling** |
| heirloom `/usr/apkg/bin/pkgadd` | `/usr/bin/patch -> ../local/bin/patch` — correct |

The pkgmap line was byte-identical in both runs, so this is an **engine defect**: stock `pkgadd`
prepends the install root to a *relative* symlink target, and reports "Installation was successful"
either way. A package shipped from here must survive a bare box, where the only engine is the
stock one — so relative targets are not available to us. The cost is `pkgadd -R` correctness, which
is the right trade for a developer tool; stock `core` uses absolute targets for the same reason
(`s none /usr/bin/uname=/sbin/uname`).

## The two rules that make recipes hand-written

Both are argued in full in `porting.md` §5; they are restated here because they are what this
directory's shape encodes.

1. **Automate the recipe. Never automate the porting.** Checksum-verified fetch, the shared build
   harness, the `.pkg` rolling and the bench smoke loop are all mechanical. The decisions inside a
   recipe — which version, which cached `ac_cv_*` answer, which patch — are not, and a wrong cached
   answer is a *silent* miscompile.
2. **Verify the encoding, never the exit status.** The family law. A build that exits 0 proves
   nothing on this toolchain: `fcmp` operand order, SGS `#`-as-comment, and constant-folded FP all
   produce clean exits and wrong binaries. Every recipe ends in an `objdump -d` gate, including the
   060 lane's `mulu.l`/`muls.l` `Dh:Dl` check (ROADMAP D4).
