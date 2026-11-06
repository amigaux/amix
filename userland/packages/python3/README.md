# python3 — CPython 3.11.18 for Amix

Python 3.11.18 under `/opt/amix`:
- `/opt/amix/bin/python3.11`, the interpreter, statically linked;
- `/opt/amix/bin/python3`, a small wrapper (below);
- the standard library in `/opt/amix/lib/python3.11`, compiled to bytecode;
- the pages `python3.11(1)` and `python3(1)`.

Threads come from GNU Pth's pthread emulation, which is cooperative: one Python thread runs at a
time, and another runs when it blocks or yields. A thread that only computes hands over every
switch interval through a CPU-time timer (patch 05); without it, such a thread kept every other
thread from running, sleepers included.

    sh build/pkg/pkgbuild.sh userland/packages/pth
    sh build/pkg/pkgbuild.sh userland/packages/zlib
    sh build/pkg/pkgbuild.sh userland/packages/python3

Package: `python3`, category `language`, set `extra`. Licence: the PSF licence (`LICENSE` in
`/opt/amix/doc/python3`). Built with GCC 14 (`-m68020-60 -mno-strict-align -O2`).
`BUILD_DEPENDS="pth zlib"`: both are linked in statically, so nothing is needed at run time.

**UFS only.** About 1350 files, 25 MB, and many names longer than s5's 14 bytes (every
`__pycache__/<module>.cpython-311.pyc`). The roll marks it `APKG_FSTYPE=ufs`.

## /dev/urandom and the wrapper

CPython seeds its hash randomisation from `/dev/urandom` at startup and stops if it cannot read it.
Stock Amix has no working random device. `/opt/amix/bin/python3` is a Bourne-shell wrapper: if
`PYTHONHASHSEED` is unset and `/dev/urandom` cannot be read, it sets `PYTHONHASHSEED=0` (hash
randomisation off), then runs `python3.11`. Once the random driver (random-amix) is installed,
the device reads and randomisation is on, with no change here.

`os.urandom()` and the `secrets` module need the device either way. Until it is installed, they
raise an error. The wrapper goes once random-amix ships.

## Source

CPython 3.11.18, `https://www.python.org/ftp/python/3.11.18/Python-3.11.18.tar.xz`,
sha256 `9120e0a6…d8fa290`. The fetch falls back to our byte-identical copy in the
amigaux/amix-distfiles archive (`python3-3.11.18/Python-3.11.18.tar.xz`); `AMIX_DISTFILES`
names a local copy.

## Patches of ours

| Patch | Why |
|---|---|
| `02-amix-py-unreachable.patch` | In a release build `Py_UNREACHABLE()` is `__builtin_unreachable()`, so gcc drops the range check in front of every switch whose default it is. The 060 gate then cannot size those jump tables (11 sites in python3.11). On Amix it is `Py_FatalError()`, as in a debug build: one compare per switch. |
| `03-amix-bytes-format-base.patch` | Bytes %-formatting's fast path picks the base with a switch whose range gcc knows from the code before it, so it emits no bound check at all: an if/else instead, with the same choices. |
| `04-amix-format-via-snprintf.patch` | **A real bug.** `PyUnicode_FromFormat` (behind every `PyErr_Format`) and `PyBytes_FromFormat` format each integer through libc `sprintf`, whose Amix version reads `ll` as `l` and knows no `z`. Every `%lld`, `%zd` and `%zu` in an error message came out wrong, and so did the arguments after it. They now go through `snprintf`, libamixc99's, which reads both right. |
| `05-amix-gil-switch-timer.patch` | **A real bug.** A thread computing in Python held the GIL and never blocked, so under Pth no other thread ran again, not even one whose `sleep` was over (`tests/starve.py` hung on both rows, 3 of 3). A timer on user CPU time (`setitimer(ITIMER_VIRTUAL)`, SIGVTALRM, every `sys.getswitchinterval()`, from the first new thread on) marks a switch due; at its next eval-breaker check the running thread drops the GIL, yields to Pth and takes it back, when another Python thread exists. Amix rounds the timer to its clock (about 30 ms); it does not run while the process is idle. A program's own ITIMER_VIRTUAL replaces it. |
| `06-amix-socket-resource.patch` | The `_socket` and `resource` modules on Amix. In `socketmodule.c`: `INET_ADDRSTRLEN`, the declarations of `port/amix-net.c`, a number for `AF_INET6`, which `asyncio` names even with no IPv6, and non-blocking mode through `fcntl`, which is what Pth can read. In `fileutils.c`: no `ioctl(FIOCLEX)`, which fails with `EINVAL` on a socket; `fcntl` works on any descriptor. In `resource.c`: `getpagesize` through `_SC_PAGESIZE`, which is how Amix spells it. |
| `07-amix-arena-align.patch` | **A real bug.** `pyarena.c` wants its allocations 8-aligned and assumes `malloc` gives that: a new block pads up to 8 but holds only the bytes asked for. Amix's `malloc` aligns to 4, so a block made to the exact size of a large request, and needing that padding, ran 4 bytes past its end, over the next block's `malloc` header. Compiling any source with a syntax-tree object over 8 KB could then crash inside `libc`'s `malloc` (`compileall` stopped at `encodings/iso8859_7.py`, with `User BUS ERROR`, on both kernel lines). The block now has room for the padding. |

## The port (isoriano's)

From isoriano's amix-userland (Ignacio Soriano); the code unchanged, the headers ours where noted:
- `patches/01-cpython-3.11-amix.patch` (PSF licence, as CPython): `configure` learns AmigaUNIX as
  a cross-build host, plus SVR4.0 changes to `pytime.c`, `posixmodule.c` and `zlibmodule.c`;
- `port/`, his adapters for the older AMIX C interface: MIT, `port/LICENSE` ("Copyright (c) 2026
  isoriano1968"), shipped as `doc/python3/LICENSE.adapters`; `amix-math.c` derives from CPython,
  PSF, `port/LICENSE.PSF`, shipped as `LICENSE.port`. Our change: an SPDX line naming each file's
  licence:
  - `amix-math.c`, C99 math fallbacks;
  - `amix-wide.c`, wide-character functions;
  - `amix-clock.c` and `amix-time.c`, clocks and time;
  - `amix-environ.c`, the environment;
  - `amix-net.c` (ours, MIT, shipped under `LICENSE.amix`), IPv4 `inet_pton` and `inet_ntop`, which
    Amix's libraries lack;
  - `amix-python.h`, force-included;
  - `include/` with `wchar.h` and `inttypes.h`.

His set of built-in modules (`Modules/Setup.local`) is kept: `math`, `_struct`, `binascii`, `_json`,
`_random`, `_datetime`, `select` and the hashes (`_md5`, `_sha1`, `_sha256`, `_sha512`, `_sha3`,
`_blake2`). Ours are `zlib`, `_socket`, `resource`, `unicodedata`, `_posixsubprocess`, `fcntl`,
`_contextvars`, `_csv`, `array`, `grp`, `termios`, `syslog`, `cmath`, `pyexpat` (with the bundled
expat), and the C versions of `_pickle`, `_bisect`, `_heapq`, `_queue`, `_opcode`, `_statistics`,
`_typing` and `_zoneinfo`. Together they take the interpreter from 3.76 to 5.28 Mbyte
(text + data + bss), `unicodedata` 1.1 Mbyte of it; text is paged in only when used.

## What is not here

Of the 287 standard-library modules, 246 import; the rest are below. A pure-Python module
needs nothing more; a C extension can only be built in, since the interpreter is static and
`lib-dynload` stays empty.

| Missing | So | Needs | Cost |
|---|---|---|---|
| `_ssl`, `_hashlib` | no `ssl`, no `https`, no `pip` | OpenSSL, and the random driver for its entropy | about 2–3 Mbyte, estimated; a port of its own |
| `_sqlite3` | no `sqlite3` | SQLite (its one-file source) | about 0.7–1 Mbyte, estimated; small work |
| `_ctypes` | no `ctypes` | libffi for m68k SVR4, and loading shared objects | about 0.2 Mbyte with libffi, estimated; real porting work |
| `_curses`, `_curses_panel` | no `curses` | ncurses, already a package | about 0.5 Mbyte with ncurses, estimated; small work |
| `readline` | no line editing at the `>>>` prompt | GNU readline (GPL-3) or editline | about 0.2 Mbyte, estimated; licence choice |
| `_bz2`, `_lzma` | no `bz2`, no `lzma` | libbz2 (the bzip2 package), liblzma (not packaged) | under 0.1 Mbyte each with their library, estimated |
| `_multiprocessing`, `_posixshmem` | `multiprocessing` imports, but its pools and locks fail | POSIX semaphores and shared memory, which Amix lacks | not portable as it is |
| `_decimal`, `_elementtree`, `_asyncio`, `_lsprof` | the pure-Python versions run (`cProfile` needs `_lsprof`) | nothing | measured 29 kbyte (`_asyncio`), 7 (`_lsprof`); `_decimal` about 0.25 Mbyte with libmpdec |
| CJK codecs (`_codecs_*`, `_multibytecodec`) | no Chinese, Japanese or Korean encodings | nothing | about 1.3 Mbyte, `_codecs_jp` alone 213 kbyte measured |
| `mmap`, `audioop`, `_crypt` | none of these | `msync` declared (mmap) | 25 kbyte (`audioop`), 1 kbyte (`_crypt`) measured |
| `venv`, `ensurepip` | taken out | `ensurepip` brings `pip`, which needs `ssl` | `venv` alone is about 40 kbyte of Python |
| `nis`, `spwd`, `_dbm`, `_gdbm`, `_uuid`, `ossaudiodev`, `_tkinter` | none of these | their libraries or devices, none on Amix | — |

The C sizes measured are text + data + bss of the module compiled with this build's flags.

## Networking

`socket`, `http.client`, `urllib.request` and `http.server` work, over IPv4 only. `ssl` is not built,
so no `https`.

- **Names** go through `gethostbyname`: `/etc/hosts` until DNS is turned on on the box, which is the
  system's setting (`/usr/lib/libsockdns.so`, `/etc/netconfig.DNS`, `/etc/resolv.conf`). There is
  no `getaddrinfo` on Amix, so CPython's own built on `gethostbyname` is used.
- **`unicodedata` is what names cost.** `socket.getaddrinfo` and `gethostbyname` encode a host name
  with the `idna` codec, which imports `stringprep` and `unicodedata` even for a plain ASCII name.
  It adds 1.1 MB to the binary and is paged in only when used.
- **Threads:** `pthread.h` maps `connect`, `accept`, `recv`, `send`, `recvfrom`, `sendto` and `poll`
  to Pth's, so a thread that blocks on a socket lets the others run. `gethostbyname` is not mapped:
  a name lookup stops every thread until it answers. Pth 2.0.7-3 or later is needed: earlier ones
  failed every `connect`, crashed in every `recv`, read every connection as closed at once, gave
  a refused connection as `BrokenPipeError`, dropped the part of a `send` that did not fit while
  counting it as sent, and broke `accept` with `EINVAL` after a `poll` on the listener or with a
  timeout set, on Amix (its README).
- **`connect` waits until it is done**, timeout or not: Amix gives no way to see a connection in
  progress, so Pth finishes it before returning (other threads run meanwhile). A socket's timeout
  applies to everything after the connection, not to making it.
- `resource` has `getrlimit`, `setrlimit` and `getpagesize`; Amix has no `getrusage` or
  `getpriority`.

## Build notes

- **Two Pythons.** The cross build runs a Python for the build host (`--with-build-python`),
  built first from the same tree (`$BUILD/hostpy`).
- **Staged by hand.** `make install` would rebuild every extension module with setup.py, and
  that does not cross-build. So the stage hook copies:
  - the interpreter;
  - `Lib/`, less the test suite, IDLE, Tk, turtle, `ctypes` (no `_ctypes`), `sqlite3`, `venv`
    and `ensurepip`;
  - the generated `_sysconfigdata__amigaunix_.py`, with the build's paths replaced by `/build`;
  - an empty `lib-dynload`, which Python looks for to find its exec prefix.
- **`-include amix-decls.h`** declares the socket calls, which Amix's headers do not. Configure's
  own tests do not see it and answer that `socket`, `bind`, `connect` and the rest are missing, and
  `socketmodule.c` then builds a `socket()` that always fails: the build sets those answers
  (`ac_cv_func_*`) and stops if one stays off.
- **Bytecode** is compiled by the build host's Python (the same 3.11.18, the same magic number)
  with `--invalidation-mode unchecked-hash`. The `.pyc` files are byte-reproducible and are never
  rewritten on the box, where the library directory is root's.
- `ZERO_OK` lists upstream's five empty files: package markers and a frozen-module test package.
- **No build-host path in the binary.** `getpath.c`'s `VPATH` is the out-of-tree source directory,
  used only when Python runs from its build tree; the generated Makefile gets it empty. `make
  Makefile` (makesetup) runs first, so `Setup.local`'s modules are in it.
- **The printf gate is reviewed** (`AMIX_LL_PRINTF_REVIEWED`). The binary's `%ll` strings are
  `PyUnicode_FromFormat`/`PyErr_Format` formats, formatted through snprintf after patch 04. Its
  `vsprintf` import is libc's own `vsyslog`. A few `fprintf` calls with `%zd`/`%zu` remain in
  debug and statistics output only (the debug allocator's dump, reference listing, cache and
  specialisation statistics). There the `z` prints wrong.

## Gates

`build.sh` passes:
- strict, with `-mno-strict-align` on every compile line;
- libacompat not linked;
- prototype == staged tree;
- the 060 gate: `scan060-g14.py` reports python3.11 CLEAN, 169 switch tables sized and no NOTE.

## Tests

`tests/smoke.sh` runs on the box:
- `python3` starts with no `PYTHONHASHSEED`, whatever `/dev/urandom` does;
- `tests/smoke.py` checks big integers, float repr, json, a zlib round trip, sha256, datetime,
  four threads through Pth, file I/O and the sysconfig platform;
- `tests/starve.py`: a thread spinning in Python must let the main thread run again after its
  0.2 s sleep (its SIGALRM ends the process after 10 s if not).
- `tests/mods.py`: `subprocess` (pipes both ways, a status, a timeout, a thread running while a
  child is waited for), `csv`, `decimal`, `fractions`, `statistics`, `cmath`, `contextvars`, `lockf`
  and `flock` against another process, XML through `pyexpat` (minidom, ElementTree, plistlib), the
  C `pickle`, `heapq`, `bisect` and `queue`, `array`, `grp`, `termios`, `syslog`, and `asyncio`
  over TCP and with a child;
- `tests/net.py`, with no outside network: a blocking server thread and a client on loopback,
  names through `/etc/hosts`, a timeout, `accept` with a timeout and after `poll`, a refused
  connection, HTTP through `urllib` and `http.server`, and the `resource`
  limits (its SIGALRM ends it after 120 s if it hangs).
