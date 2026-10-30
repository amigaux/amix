# patch — the recipe

**Package `patch` 2.5.9** — GNU patch, re-minted for Amix. GPL-2.0-or-later.
Metadata and source pin: [`package.sh`](package.sh); build hooks: [`build.sh`](build.sh).

    sh build/pkg/pkgbuild.sh userland/packages/patch

Wave 0 for a structural reason rather than a popularity one: without a `patch` on the box, every
other recipe's patches can only be applied host-side — workable for a cross-build, impossible for
anyone doing anything on the box itself.

**★ But the roadmap's premise was half wrong, and the bench said so.** "SVR4 ships no `patch` at
all" is true of SVR4 and misleading about Amix: the stock **`public`** package — which is in the
**standard 17-package set**, so a normal install has it — ships Larry Wall's patch at
`/usr/public/bin/patch`, *"Patch level: 12u4"* (`patch.c,v 2.0.2.0`, 1990). Run on the box against
this recipe's own fixture it answered *"Hmm... Looks like a unified diff to me..."*, applied the
hunk, and produced the byte-exact expected output. **It works.**

So this package supersedes a 1990 release rather than filling a void. It still earns Wave 0 — 13
years of fixes and the modern option set — and it takes over cleanly because `/usr/local/bin`
precedes `/usr/public/bin` on the stock PATH. The `pkginfo` DESC was rewritten to say this; a
package whose own description repeats a claim its smoke test disproved is not one to ship.

## Result

Builds clean. Zero implicit declarations, zero pointer/integer conversions, m68k SVR4 ELF,
71 768 bytes stripped, D4-clean (no `mulu.l`/`muls.l` with a `Dh:Dl` destination).
**No patches to the upstream source were needed** — hence no `patches/` directory, which is absent
rather than empty so nobody has to wonder whether one went missing.

## This is the family's first completed cross-`configure`

`docs/porting.md` §4 said the route was derived from the constraints and had never been run. It has now.
Three things bit that no amount of reading would have found.

### ★ Trap 1 — the wrapper cannot preprocess, so configure used the *host's* preprocessor

`m68k-cbm-sysv4-gcc -E` does not preprocess. The `fix_asm` wrapper has cases for `-c` and `-S`;
`-E` falls through to its "unrecognised dash argument is an ld flag" branch, so the wrapper
**links** the file instead — exiting 0 with a linker complaint on stderr and nothing on stdout.

Autoconf's *"checking how to run the C preprocessor"* rejects that and walks down its candidate
list to **`/lib/cpp`** — the build host's preprocessor. Every `AC_CHECK_HEADER` presence test then
reads the host's `/usr/include`, and autoconf 2.5x resolves a presence/usability disagreement by
**trusting the preprocessor**:

```
checking wchar.h usability... no
checking wchar.h presence... yes
configure: WARNING: wchar.h: present but cannot be compiled
configure: WARNING: wchar.h: proceeding with the preprocessor's result
checking for wchar.h... yes
```

`config.h` then declared `HAVE_WCHAR_H 1` for a header Amix does not have, and the build died in
`quotearg.c` with *"wchar.h: No such file or directory"* — a long way from anything that mentions
cross-compiling. This one failed loudly. The same mechanism sets `HAVE_*` for anything that merely
*looks* present on a modern Linux host, and most of those fail quietly.

Fix: [`build/pkg/common/amix-cpp`](../../../build/pkg/common/amix-cpp), passed as `CPP`. It calls `gcc.real -E` with
the sysroot include path — the one place calling `gcc.real` is safe by construction, since `fix_asm`
post-processes *assembly* and `-E` never produces any. `build.sh` then **asserts** five `config.h`
answers, so if `CPP` ever regresses the build stops instead of shipping a binary that will not run.

**This is a `gcc-cross-amix` bug, not just a workaround.** The wrapper should implement `-E`.

### ★ Trap 2 — the `__STDC__` header gate has three keys, and they are not interchangeable

`docs/porting.md` §2.4 documents `-U__STDC__` and warns against `-D_POSIX_SOURCE`. Measured on this
sysroot, each key opens and closes a *different* set of doors:

| feature | default | `-U__STDC__` | `-D_POSIX_SOURCE` | `-D_XOPEN_SOURCE` |
|---|---|---|---|---|
| `fdopen` `popen` `pclose` `fileno` `system` | implicit decl | ok | **ok** | ok |
| `struct sigaction` + `sigset_t` + prototypes | **parse error** | struct only | **ok** | **parse error** |
| `SA_SIGINFO` | hidden | ok | hidden | parse error |
| `struct timeval` | ok | ok | hidden | ok |
| ANSI `va_start` (**gcc's own** `stdarg.h`) | ok | **broken — K&R form** | ok | ok |
| `<signal.h>` compiles at all | ok | ok | ok | **parse error** |

Two rows were not previously written down anywhere and both are load-bearing:

- **`-U__STDC__` is not free.** It flips gcc 2.7's *own* `<stdarg.h>` to the K&R `va_start(ap)`
  form, so every ANSI variadic function stops compiling — `macro 'va_start' used with too many (2)
  args`. patch's `util.c` needs `struct sigaction` **and** five variadic functions in the same
  translation unit, so per-file flags cannot rescue it.
- **`-D_XOPEN_SOURCE` is never the answer.** It makes `<signal.h>` itself fail to parse.

So this recipe uses **`-D_POSIX_SOURCE`**, against the general advice and for a measured reason: it
is the only key that opens both the stdio and the sigaction doors while leaving ANSI varargs
intact. What it closes — `SA_SIGINFO` and `struct timeval` — patch does not use (no source file
includes `<sys/time.h>` or names `struct timeval`). The general advice stands; this is a package
where the measurement says otherwise.

### ★ Trap 3 — `AC_PATH_PROG` probes the build host

`checking for ed` found the *Linux* box's `/usr/bin/ed` and compiled that path into the binary. It
is right — `/usr/bin/ed` exists on a stock Amix root, verified against the extracted 2.1 install
tape — but it was right by coincidence, so `ed_PROGRAM=/usr/bin/ed` is now passed explicitly.

## Cache variables — one seeded, two deliberately not

patch's configure has **seven** `AC_TRY_RUN` sites and every one already carries a
cross-compilation fallback, so the cross route is far less hostile than §4 feared. Only one default
is wrong:

- **`ac_cv_func_closedir_void=no`** — seeded. The cross default is `yes` (closedir returns void) and
  that is false here: `$SYSROOT/usr/include/dirent.h:39` declares `extern int closedir(DIR *)`.
- **`ac_cv_func_malloc_0_nonnull`** / **`ac_cv_func_realloc_0_nonnull`** — *not* seeded. They default
  to `no`, which installs configure's own `rpl_malloc` wrapper turning `malloc(0)` into `malloc(1)`.
  That wrapper is correct whichever way SVR4.0's `malloc(0)` behaves, so the conservative default is
  also the right answer. Seeding it would be a claim we cannot check without the box.
- `ac_cv_header_stdc` — no seed needed, and worth recording because it looks like it needs one: its
  cross branch is a no-op (`:`), so the compile-test result survives.

## The predicted libacompat dependency does not exist

The roadmap gave patch a `SHIM-MKSTEMP` blocker and `depends.build: [libamixcompat]`. **Measurement
says otherwise, and the registry has been corrected.**

- patch 2.5.9 **bundles its own `strncasecmp.c`** (configure adds it to `LIBOBJS` when the platform
  lacks it).
- It uses **`mktemp(3)` — which Amix has** — plus its own `O_EXCL` create. Its source says so out
  loud: *"It might be better to use mkstemp to avoid some DoS problems, but simply substituting
  mkstemp for mktemp would…"*.
- A build with libacompat on both the include path and the library path links **zero** symbols out
  of it — checked with `nm`.
- The counterfactual build with no libacompat anywhere also compiles clean, with no implicit
  declarations.

This is standing decision **D8** — self-containedness is the strongest portability predictor —
confirmed rather than assumed. The shipped package is the standalone build, because declaring a
dependency that does not exist is worse than declaring none.

## Package shape

`/usr/local/bin/patch`, the man page at `/usr/local/man/man1/patch.1`, `COPYING`/`NEWS`/`README`
under `/usr/local/doc/patch/`, and one symlink:

    s none /usr/bin/patch=../local/bin/patch

That line is why the package is useful at all — `/usr/local/bin` is not on the stock Amix PATH, so
without it the user installs `patch` and cannot type `patch`. It follows the package manager's own
`/usr/bin/apkg` precedent, relative target included so it stays correct under `pkgadd -R`. SVR4
ships no `patch` in `/usr/bin`, so nothing is being shadowed — the 1990 one lives in
`/usr/public/bin`, later on PATH. `pkgproto` would have silently dropped this line, which is the
concrete reason prototypes here are authored.

The target is **absolute** rather than relative, and that is a bench finding: stock `pkgadd`
prepends the install root to a relative symlink target and reports success anyway. See the
prototype's own comment for the two-engine measurement.

Pure file payload: `CLASSES=none`, class `none` on every object, no install scripts (**D9**).

## On-box evidence

[`tests/`](tests/) carries a real unified diff produced by a modern host `diff`, the original, and
the byte-exact expected result. [`tests/smoke.sh`](tests/smoke.sh) — written for the 1992 pre-POSIX
Bourne shell — applies it, byte-compares against the host's expected output, then **reverses** the
patch and byte-compares back to the original. Forward-only would pass for a patch that mangles a
file consistently; the round trip would not.

## GCC 14 build

The current package is built with GCC 14 (`TOOLCHAIN=gcc14`, revision `-6`, on gcc14-cross-amix
b51ff39); the period build stopped at `-2`. Nothing in the recipe differs between the two
toolchains. The `/usr/bin/patch` symlink is staged with its absolute target, as the prototype
lists it; `/usr` and `/usr/bin` are stock directories the package does not own.

The recipe moved to `package.sh` and hooks on 2026-10-30 without a revision: the rebuilt package has
the recorded one's payload (every file's sha256 and mode), pkginfo, pkgmap (mtimes aside) and
catalog line.
