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

| Patch | Whose | Why |
|---|---|---|
| `patches/0001-mcsc-keep-errno.patch` | isoriano's (amix-userland; Ignacio Soriano, LGPL 2.1 or later as Pth is), with our comment and no `__amix__` guard | `errno` is one variable per process: the mcsc switch now saves and restores each thread's, as the sjlj switch always did through `pth_mctx_save`/`restore`. A generic Pth 2.0.7 bug, not an Amix quirk. The store before `swapcontext` gives a thread starting at its `makecontext` entry its own `errno` (0). |
| `postconf/0002-amix-public-timespec.patch` | isoriano's, unchanged | `struct timespec` for programs that include `pthread.h`; Amix's headers have none (guarded by `__amix__`, which GCC 14 predefines). It patches `pthread.h`, which configure generates, so `build.sh` applies it in `post_configure`. |
| `patches/0003-pthread-once-cond.patch` | ours, replacing isoriano's yielding `pthread_once` (its states and cancellation reset are the model) | `pthread_once` runs the initialiser once and the other callers wait on a condition until it has run. Upstream ran it again in every caller that came before the first finished (a generic Pth bug); the yielding version looped on `pth_yield`, a spin at full CPU while the initialiser blocked, and forever when the initialiser called `pthread_once` on its own control, which now gives `EDEADLK`. A cancelled initialiser resets the control and wakes the waiters, and the next caller runs it. |
| `patches/0004-connect-eagain.patch` | ours | `connect` on a socket made non-blocking with `O_NONBLOCK` gives `EAGAIN` on Amix, not `EINPROGRESS`, and `select` reports the socket writable at once, connected or not (measured). `pth_connect` waited only on `EINPROGRESS`, so every `connect` through Pth failed at once, and a caller that waits on `select` took a connection in progress for one made. `pth_connect` now finishes the connection itself: it naps 20 ms and asks `connect` again until `EISCONN` or the real error. Other threads run meanwhile; a caller's own timeout on `connect` does not apply. A connection finished this way leaves a message of no data first in the stream's queue, and the first `recv` returns 0 for it, as if the peer had closed (`read` skips it; a blocking connect, or one under `O_NDELAY`, leaves none; measured). `pth_connect` removes it when `I_NREAD` shows it first in the queue. A refused connection comes back from the repeated `connect` as `EPIPE`, which callers took for a broken pipe (Python raised `BrokenPipeError`); it is now given as `ECONNREFUSED`. |
| `patches/0005-amix-recv-send.patch` | ours | Amix's libsocket faults (`User BUS ERROR at 0`) in `recvfrom` with a NULL address, and Pth's `recv` was `recvfrom` with a NULL address: every `recv` in a Pth program crashed. A non-blocking `send` that meets less room than it asked for writes part, counts every byte as sent and drops the rest; with no room at all it fails with `ENOMEM` (libsocket's `send` subtracts each piece it asked to write, not what the write took; measured with libsocket alone: an 8192-byte `send` with room for 4096 returned 8192 and 4096 arrived). A thread sending to a reader thread that had not run yet lost data this way. `recv` now calls `recv` when there is no address. `send` with no flags and no address calls `write(2)`, which gives the count that went, and `EAGAIN`; with flags or an address a stream sends in pieces of 1024 bytes (one stream message each, queued whole or not at all), a datagram goes whole, and `ENOMEM` is `EAGAIN`. `select` says writable when there is room for less than one message: on `EAGAIN` then, Pth waits 20 ms instead of spinning. Measured on both kernel lines. |
| `patches/0006-amix-poll-no-peek.patch` | ours | Pth's `poll` checks each readable descriptor for `POLLHUP` with `recv(MSG_PEEK)`, a listening socket included. Amix's libsocket answers that `recv` with `ENOTCONN` and then refuses `accept` on the listener with `EINVAL` without asking the kernel (measured with libsocket alone), so Python's `accept` after `poll`, or with a timeout set, failed with `EINVAL`. A listener cannot be told apart on Amix (`getsockopt` `SO_ACCEPTCONN` gives `ENOPROTOOPT`), so the check is left out on Amix. The cost: a reset connection's `POLLIN` is not turned into `POLLHUP`; the reader sees the error on its next read, as with `select`. |

## Build notes

- **Machine context: mcsc** (`getcontext`/`swapcontext`), which is what his patches cover.
  `post_configure` asserts it. His port also has a faster sjlj switch, which makes no system call
  per switch, but that lives in his patcher script as assembly, not in a patch. It can follow as
  a patch of its own.
- **`-std=gnu89`**: Pth is 1990s C.
- **`-include amix-decls.h`** declares the socket calls, `select` and `readv`/`writev`.
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

`tests/smoke.sh` runs two C programs on the box, which `build.sh` builds against the tree's own
`pthread.h` and `libpthread.a` and leaves in the tree (`tests/fixtures`); they are not shipped:
- `t-errno`: four threads keep their own `errno` across 1000 switches each, and a new thread starts
  with `errno` 0;
- `t-once`: four callers of a yielding initialiser run it once and all return after it; an
  initialiser calling `pthread_once` on its own control gets `EDEADLK`; a cancelled initialiser
  leaves its control unset, the waiting caller then runs the initialiser, later callers do not.

Python's threading tests exercise the libraries too.
