# python3 — CPython 3.11.18 for Amix

Python 3.11.18 under `/opt/amix`:
- `/opt/amix/bin/python3.11`, the interpreter, statically linked;
- `/opt/amix/bin/python3`, a small wrapper (below);
- the standard library in `/opt/amix/lib/python3.11`, compiled to bytecode;
- the pages `python3.11(1)` and `python3(1)`.

Threads come from GNU Pth's pthread emulation (cooperative: one Python thread runs at a time, and
another runs when it blocks or yields).

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

## The port (isoriano's)

From isoriano's amix-userland (Ignacio Soriano), unchanged:
- `patches/01-cpython-3.11-amix.patch` (PSF licence, as CPython): `configure` learns AmigaUNIX as
  a cross-build host, plus SVR4.0 changes to `pytime.c`, `posixmodule.c` and `zlibmodule.c`;
- `port/`, his adapters for the older AMIX C interface (MIT; `amix-math.c` derives from CPython,
  PSF, `port/LICENSE.PSF`):
  - `amix-math.c`, C99 math fallbacks;
  - `amix-wide.c`, wide-character functions;
  - `amix-clock.c` and `amix-time.c`, clocks and time;
  - `amix-environ.c`, the environment;
  - `amix-python.h`, force-included;
  - `include/` with `wchar.h` and `inttypes.h`.

His set of built-in modules (`Modules/Setup.local`) is kept, with zlib: `math`, `_struct`,
`binascii`, `_json`, `_random`, `_datetime`, `select`, the hashes (`_md5`, `_sha1`, `_sha256`,
`_sha512`, `_sha3`, `_blake2`) and `zlib`.

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
- **Bytecode** is compiled by the build host's Python (the same 3.11.18, the same magic number)
  with `--invalidation-mode unchecked-hash`. The `.pyc` files are byte-reproducible and are never
  rewritten on the box, where the library directory is root's.
- `ZERO_OK` lists upstream's five empty files: package markers and a frozen-module test package.

## Gates

`build.sh` passes:
- strict, with `-mno-strict-align` on every compile line;
- libacompat not linked;
- prototype == staged tree;
- the 060 gate.

## Tests

`tests/smoke.sh` runs on the box:
- `python3` starts with no `PYTHONHASHSEED`, whatever `/dev/urandom` does;
- `tests/smoke.py` checks big integers, float repr, json, a zlib round trip, sha256, datetime,
  four threads through Pth, file I/O and the sysconfig platform.
