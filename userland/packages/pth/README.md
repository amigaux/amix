# pth — GNU Pth 2.0.7 for Amix

GNU Portable Threads: cooperative threads inside one process, for a system with no kernel threads.
The package installs, under `/opt/amix`:
- `libpth.a` with `pth.h`, Pth's own API;
- `libpthread.a` with `pthread.h`, the POSIX-threads emulation that ported programs link
  (Python and SDL2 do);
- the pages `pth(3)` and `pthread(3)`.

Its threads switch when the running one yields, waits or does wrapped I/O. They are not preemptive
and do not make CPU-bound work faster.

    sh build/pkg/pkgbuild.sh userland/packages/pth

Package: `pth`, category `library`, set `extra`. Licence: LGPL 2.1 or later (`COPYING` in
`/opt/amix/doc/pth`). Built with GCC 14 (`-m68020-60 -mno-strict-align -O2`), static.

## Source

GNU Pth 2.0.7, `https://ftp.gnu.org/gnu/pth/pth-2.0.7.tar.gz`, sha256 `72353660…bc77232`.
The fetch falls back to our byte-identical copy in the amigaux/amix-distfiles archive
(`pth-2.0.7/pth-2.0.7.tar.gz`); `AMIX_DISTFILES` names a local copy.

## Patches

All three are isoriano's, from his amix-userland port (Ignacio Soriano; LGPL 2.1 or later, as Pth
is), unchanged. They are guarded by `__amix__`, which `build.sh` defines.

| Patch | Why |
|---|---|
| `patches/0001-amix-global-errno.patch` | Amix's `errno` is one process-wide variable: each thread's `errno` is saved and restored across a context switch. |
| `postconf/0002-amix-public-timespec.patch` | `struct timespec` for programs that include `pthread.h`; Amix's headers have none. It patches `pthread.h`, which configure generates, so `build.sh` applies it in `post_configure`. |
| `patches/0003-amix-yielding-once.patch` | `pthread_once` yields while another thread runs the initialiser, instead of spinning. |

## Build notes

- **Machine context: mcsc** (`getcontext`/`swapcontext`), which is what his patches cover.
  `post_configure` asserts it. His port also has a faster sjlj switch, which makes no system call
  per switch, but that lives in his patcher script as assembly, not in a patch. It can follow as
  a patch of its own.
- **`-std=gnu89`**: Pth is 1990s C.
- **`-include amix-decls.h`** declares the socket calls and `select`. **`amix-uio.h`** declares
  `readv`/`writev`, which `libc.so.1` has and no Amix header declares; it goes once
  `amix-decls.h` carries them.
- `pth-config`, `pthread-config`, the libtool `.la` files and `pth.m4` are build-host material and
  are not shipped.

## Gates

All passed:
- strict, with `-mno-strict-align` on 36 of 36 compile lines;
- libacompat not linked;
- prototype == staged tree;
- the 060 gate.

Both libraries hold FPU instructions, none of them
040/060-only: a program linking them needs an FPU, or the kernel's FPE.

## Tests

The libraries are exercised on the box through the programs that link them (Python's threading
tests).
