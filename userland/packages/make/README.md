# make — the recipe

**Package `make` 3.81** — GNU make. GPL-2.0-or-later (the bundled `glob/` is LGPL-2.0-or-later;
both texts ship). Metadata and source pin: [`package.sh`](package.sh); build hooks: [`build.sh`](build.sh).

    sh build/pkg/pkgbuild.sh userland/packages/make

## Coexistence

Stock ships the AT&T/SVR4 `make` at `/usr/ccs/bin/make`, owned by `core`. This package does not
touch it: ours is `/opt/amix/bin/make` and wins by PATH order.

## Result

Builds clean — zero implicit declarations, m68k SVR4 ELF, dynamic against `libc.so.1` only,
D4-clean under the corrected encoding-based gate (4 `#imm` 64-bit multiplies, the emulated form).
Needs **nothing** from libamixcompat. **Bench-proven** on the emulated golden 030 (2026-09-26):
stock `pkgadd`, `pkgchk` 0, `tests/smoke.sh` PASS — pattern rules through `VPATH`, `$(shell)`,
`$(eval)`, order-only prerequisites, up-to-date detection, recursive `-j2` with the jobserver, and a
C program built with the box's own `cc`.

## ★ `-D_POSIX_SOURCE` — the right key of the `__STDC__` gate, for once

make's job control needs `sigset_t`/`sigprocmask`/`sigemptyset`/`kill`, all hidden in the default
ANSI view (`job.c` does not even parse). docs/porting.md §2.4.1's matrix picks the key: `-U__STDC__`
breaks gcc's `<stdarg.h>`, `-D_XOPEN_SOURCE` breaks `<signal.h>`, and `-D_POSIX_SOURCE` opens every
door make walks through. What it closes is either unused (`struct timeval` — make falls back to
`time()`), not wanted by default (`lstat`, only for `-L`), or put back by
[`patches/01-config-h-svr4.patch`](patches/01-config-h-svr4.patch). The cross-configure answers were
diffed with and without the key: identical.

`patches/01` (appended to `config.h.in`, so every TU including `glob/` sees it): declares `strdup`
(hidden) and `getrlimit`/`setrlimit` (declared by no SVR4 header outside `_KERNEL`), defines
`SA_RESTART` (a kernel ABI value the POSIX view hides), and `#define environ _environ` —
`libc.so.1` exports only `_environ` (docs/porting.md §3.1).

## Two configure answers that were wrong

- `ac_cv_have_decl__sys_siglist=no` — `<signal.h>` declares `_sys_siglist`, `libc.so.1` does not
  export it. make builds its own signal-name table instead.
- `make_cv_sa_restart=yes` — the probe compiles in the POSIX view, where the macro is hidden; the
  kernel honours the flag. This also enables the **jobserver** (`-j` across recursive makes).

## ★ `make -l` has no load average, on purpose

`getloadavg.c` finds no OS branch for SVR4.0/m68k and compiles to a stub, so `make -l` warns and
carries on. That is the right outcome: the alternative is `nlist()` + `/dev/kmem`, and on Amix
`nlist()` returns an **alignment** for the COMMON `avenrun` symbol and reports success
(docs/porting.md §3.3) — make would throttle on garbage. The build asserts no `nlist` and no
`/dev/kmem` reference.

## Package shape

`/opt/amix/bin/make`, `/opt/amix/man/1/make` (and `whatis.d/make`), and `COPYING`, `COPYING.LIB`, `NEWS`, `README`
under `/opt/amix/doc/make/`. No info manual (no reader on the box). Pure file payload (D9).

## GCC 14 build

The current package is built with GCC 14 (`TOOLCHAIN=gcc14`, revision `-7`, on gcc14-cross-amix
b51ff39); the period build stopped at `-2`. GCC 14 links the SVR4 way (`usr/ccs/lib/libc.so` is
`libc.so.1` plus static members), so four probes find what the period link never saw and are
pinned to the period answers: `elf_begin` in `-lelf` (it would make `AC_FUNC_GETLOADAVG` take the
`nlist()`/kmem load average with a setgid-kmem install; the LOADAVG check refuses that), `vfork`
(make keeps the bench-proven `fork`), `stdint.h` (`make.h` then uses `uintmax_t` without including
it) and `lstat` (`MAKE_SYMLINKS` needs `lstat`, `readlink` and `S_IFLNK`, which the
`-D_POSIX_SOURCE` view hides).

The recipe moved to `package.sh` and hooks on 2026-10-30 without a revision: the rebuilt package has
the recorded one's payload (every file's sha256 and mode), pkginfo, pkgmap (mtimes aside) and
catalog line.

## Revision -8: man pages where `man` finds them

The man pages move to `/opt/amix/man/<sect>/<name>` with the package's whatis fragment
`/opt/amix/man/whatis.d/make` (docs/man-pages.md), where the base package's `man` and the stock
`man` find them; `make(1)` is upstream's. Built on the gcc14 container pin: every other payload file is the previous
revision's.
