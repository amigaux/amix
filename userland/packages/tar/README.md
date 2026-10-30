# tar — the recipe

**Package `gtar` 1.14** (catalog name `tar`) — GNU tar with base-256 header reads, long names and
`-z`. GPL-2.0-or-later. Pin:
[`pin.sh`](pin.sh).

    sh build/pkg/pkgbuild.sh userland/packages/libamixcompat   # once: tar links gettimeofday from libacompat
    sh build/pkg/pkgbuild.sh userland/packages/tar

## Coexistence

Stock ships SVR4 `tar` at `/usr/sbin/tar` (+ `/etc/tar`), owned by `core`. This package does not
touch it: ours is `/opt/amix/bin/tar` and wins by PATH order. The PKG is **`gtar`**, so the catalog
never lists two packages named `tar` — the catalog *name* is `tar` via the packagemanager's
`names.conf` (`gtar: tar`), the same name/pkginst split `amix-benchmark` proved on metal.

## Result

Builds clean — zero implicit declarations, m68k SVR4 ELF, dynamic against `libc.so.1` only,
**D4-clean under the corrected gate** (23 `#imm` 64-bit multiplies, all the vector-61-emulated
form, and no register/memory-source ones). **Bench-proven** on the emulated golden 030
(2026-09-26): stock `pkgadd`, `pkgchk` 0, `tests/smoke.sh` PASS, and a box-made archive extracted
byte-for-byte by the host's GNU tar (`sum -r` identical both sides).

## ★ D3 — the first package that needed it

`tar -c` maps uid→name (`getpwuid`), and `tar -x` as root maps name→uid (`getpwnam`) — and the
**first `getpwnam()` of a process crashes in the stock shared libc** (docs/porting.md §3.1, ROADMAP D3).
The executable therefore **defines** all four lookups itself —
[`build/pkg/common/amix-pwgr.c`](../../../build/pkg/common/amix-pwgr.c), linked as a plain object — and `build.sh`
asserts via `nm` that they are `T` in the binary and never `U`. On the box: an archive entry owned
by `bin` with a wrong numeric id (4242) extracts owned by the box's own `bin` (uid 2), an unknown
name keeps its number, and a box-made archive records owner names.

The binary stays **dynamic**. D3 says "link static"; what it needs is that the executable's own
definitions win, and for the program's own calls they win in a dynamic link just as surely (ld
binds them at link time). A static link would pull stock SVR4 `libc.a` objects into a published
binary — the exposure that kept `whet` out of `amix-benchmark` 1.3.

## ★ The configure answer that would have silently broken it

`lstat` is a **static function in `<sys/stat.h>`** (a wrapper around `_lxstat`), so autoconf's
link-only probe says it does not exist — and tar then does `#define lstat stat`, archiving what
every symlink *points at*, with no warning anywhere. Seeded `ac_cv_func_lstat=yes` and asserted
in `config.h`; on the box a symlink archives and extracts **as a symlink**. Two more seeds:
`valloc` is declared by `stdlib.h` but not exported by `libc.so.1` (so `malloc`), and the
cross-default "gettimeofday clobbers localtime" wrapper is not needed over libacompat's
`_abi_gettimeofday`-based symbol.

## ★ D4 — and the gate that could not fire

The shared D4 gate grepped for `mulu.l …,%dH:%dL`, a spelling binutils 2.8.1's objdump never
prints (it writes `mulul %fp@(12),%d1,%d2`), so it passed everything. Fixed in
[`build/pkg/common/gates.sh`](../../../build/pkg/common/gates.sh) to classify by **encoding** (MUL.L/DIV.L opword +
extension-word bit 10), with a self-test that must see it fail on a probe first. Under the real gate
tar had four register/memory-source 64-bit multiplies — `human.c` ×2 (`--totals`), `bkm_scale` in
the `uintmax_t` instance of `xstrtol.c` (size suffixes), and `strtoull` (every numeric option) — each
a SIGKILL on the 68LC060. Patches 05–07 route them through libgcc's `__muldi3`, which is built from
32-bit multiplies only. D4's documented escape hatch, "build the TU `-m68000`", does **not** work on
this toolchain: `libgcc.a` has no `__mulsi3`/`__divsi3`/`__udivsi3`/`__umodsi3`.

## The patches

| Patch | Why |
|---|---|
| `01-system-h-svr4-decls` | `fdopen`/`fileno`/`strdup`/`kill`/`tzset` are in `libc.so.1` but behind the `__STDC__` gate. `-U__STDC__` breaks gcc's `<stdarg.h>`; `-D_POSIX_SOURCE` hides `lstat`/`mknod`, which tar needs |
| `02-human-no-long-double` | `long double` is the 96-bit 68881 type and libgcc has no `__fixunsxfdi` — the link fails |
| `03-exclude-strcase-decl` | no SVR4 header declares `strcasecmp`; include gnulib's `strcase.h` |
| `04-gettime-decl` | `gettimeofday` is in no header and not in `libc.so.1`; the symbol comes from libacompat |
| `05`–`07` `-d4-*` | the four D4 multiply sites above |

GCC 14 only (`patches-gcc14/`; the period build is frozen):

| Patch | Why |
|---|---|
| `02-hasher-size-t` | gnulib's `Hash_hasher` takes `size_t`; GCC 14 rejects tar's `unsigned` hashers (both 32 bits) |
| `03-ftruncate-freesp-aligned` | **The stock kernel panics** (grimoire quirk 90). gnulib's `ftruncate` is `fcntl(F_FREESP)`. Shrinking a file larger than its direct blocks (~96 KiB) to an EOF that is not block-aligned, inside the block holding the old EOF, faults `pvn_vptrunc`. tar truncates that way after `--delete`, and when it rewrites a `--listed-incremental` snapshot. Measured at 1.14-6: `tar -b 1 --delete` of a small member from a 215040-byte archive (new EOF 214016, same 8 KiB block) took the emulated golden 030 down. With the default `-b 20` an archive shrinks by whole 10240-byte records, so the new EOF is always in an earlier block, and that case survived. The patch cuts at the block boundary below the new EOF and writes the bytes up to it back, read first. |

## Package shape

`/opt/amix/bin/tar` and `COPYING`/`NEWS`/`README` under `/opt/amix/doc/tar/`. No `rmt` (remote tape
is not built), no man page (tar 1.14 documents itself in texinfo only; `tar --help` is the
reference). Pure file payload (D9). `-z` runs `gzip` from `PATH` — install the `gzip` package and
put `/opt/amix/bin` on `PATH`.

## Known limits

- An archive uid/gid above SVR4.0's `uid_t` range (e.g. 3000000) **reads** correctly — listing
  and the value handed to `chown(2)` are exact — but the kernel refuses to set it (`EINVAL`), so
  tar extracts the file as root-owned and exits 2. That is the OS, not the port.
- `--totals` shows `?/s` for a sub-second run (no sub-second clock in the rate).
- The period build (1.14-2) keeps the quirk 90 hazard: `-b <small> --delete` on a large archive
  can panic the stock kernel. Use the GCC 14 build (1.14-7 or later).

**Revision 1.14-7, 2026-10-30 (GCC 14): the stock-kernel ftruncate panic (grimoire quirk 90).**
- **Probed at -6** on E1, one boot per case:
  - `tar -b 1 --delete` of a small member from a 215040-byte archive panicked;
  - the same from a 214016-byte archive survived, because its new EOF (212992) is 8 KiB-aligned;
  - default-blocking `--delete` survived.
  - Evidence: `Amigaux/tmp/2026-10-30-ftx/`.
- **The fix:** `patches-gcc14/03`.
- **Bench:** E1 slot 1, rig-run 20261030-113242, `tools/gcc14-smoke`.
  - All 42 period-versus-GCC 14 comparisons EQUAL.
  - X4 (GCC 14 tar only; the period tar would panic): `-b 1 --delete` 215040 → 214016, two
    members left, `t/b` extracts byte-exact.
- **Package:** `gtar-1.14-7.pkg`, md5 `44e79c678a475cd6c96f7a7ade8afe9a`, 221696 bytes.
