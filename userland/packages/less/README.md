# less — the recipe

**Package `less` 704** — the backward-scrolling pager. Dual-licensed
GPL-3.0-or-later OR BSD-2-Clause. Pin: [`pin.sh`](pin.sh).

    sh build/pkg/pkgbuild.sh userland/packages/less

Fills a genuine gap: stock Amix has only `more`/`pg`/`page`. less adds backward scroll, incremental
search and no-write paging. The best demonstration of D5 in the whole roadmap — a **2026** release
that still supports SVR4 `regcmp`/libgen, still needs no `config.sub`, and has no gnulib dependency.

## Result

Builds clean — **zero implicit declarations, zero pointer/integer conversions**, m68k SVR4 ELF,
all three binaries **D4-clean**. Links **nothing** from libamixcompat — every symbol resolves from
`libc.so.1`, `libgen.a` (regcmp) and `libcurses.a` (termcap). **Bench-proven** on the emulated golden
030 (2026-08-30): `pkgadd`, `less --version` = "less 704 (V8 regular expressions)" (V8 is less's
label for the regcmp backend — `HAVE_REGCMP=1`), `less -EF` reproduced a file byte-exact through the
pager, `pkgchk` 0, and it survived `pkgrm` of the batch's gzip/grep. The **interactive** half —
search, backward scroll, resize, clean exit with the terminal restored — is a reader's manual check
over a real tty.

## The four things that made it build (all measured)

1. **The `/usr/ccs/lib` link path, and `-lc`.** `regcmp` is in `libgen.a` and the termcap API in
   `libcurses.a`, both under `/usr/ccs/lib` — not the wrapper's default `/usr/lib` — so
   `-L<sysroot>/usr/ccs/lib` goes on the configure `LDFLAGS`. And **`LIBS=-lc`**: the wrapper drops
   the implicit libc the moment any explicit `-l` appears, which is why the stock configure's
   `curses`/`regcmp` probes first failed (`crt1.o`'s own `atexit`/`_environ` came back undefined).
2. **`-DUSE_TERMCAP`.** In the default terminfo path less pulls SVR4 `<term.h>`, whose `TERMINAL`
   struct has a `struct termio` field that stays **incomplete**: less includes `<termios.h>` (for
   `tcgetattr`), which defines `VINTR`, which makes `<curses.h>` skip its own `<termio.h>` include.
   The termcap path avoids `<term.h>` entirely, and on SVR4 the termcap `tgetent` reads the terminfo
   database (D2) — so `-lcurses` alone is enough.
3. **`ac_cv_func_stat=yes`.** SVR4 `stat` is a static-inline wrapper over `_xstat`, so autoconf's
   link-test for a bare `stat` symbol **fails** and `HAVE_STAT` comes out unset — after which
   `edit.c`/`cmdbuf.c`/`filename.c` skip `<sys/stat.h>` and every `struct stat` is incomplete. `stat`
   works; the probe just cannot see it.
4. **Three source patches** for the strict-ANSI SVR4 header gaps:
   [`01-less-svr4-headers.patch`](patches/01-less-svr4-headers.patch) adds `ssize_t` (absent from
   `<sys/types.h>`) and declares the `__STDC__`-gated / header-less functions (`fileno`, `popen`,
   `kill`, `fchmod`, `strdup`, and the termcap calls) so the pointer-returning ones are not truncated;
   [`02-pattern-libgen.patch`](patches/02-pattern-libgen.patch) replaces less's own stale, fixed-arg
   `regcmp`/`regex` prototypes with SVR4's variadic `<libgen.h>` ones (the reason `regcmp(pattern,0)`
   was "too many arguments"); [`03-lesskey-strdup.patch`](patches/03-lesskey-strdup.patch) declares
   `strdup` for the one TU that does not include `less.h`.

(less ships its source read-only, mode 444; the build makes the tree writable before patching.)

## Package shape

`/opt/amix/bin/{less,lesskey,lessecho}`, man pages under `/opt/amix/man/man1/`,
`LICENSE`/`COPYING`/`NEWS` under `/opt/amix/doc/less/`. Pure file payload (D9), nothing outside
`/opt/amix`, no scripts, no symlinks.
