# make — the recipe

**Package `make` 3.81** — GNU make. GPL-2.0-or-later (the bundled `glob/` is LGPL-2.0-or-later;
both texts ship). Pin:
[`pin.sh`](pin.sh).

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

`/opt/amix/bin/make`, `/opt/amix/man/man1/make.1`, and `COPYING`, `COPYING.LIB`, `NEWS`, `README`
under `/opt/amix/doc/make/`. No info manual (no reader on the box). Pure file payload (D9).
