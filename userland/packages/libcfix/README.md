# libcfix — the stock `libc.so.1` with two `malloc` faults fixed

`/usr/lib/libc.so.1` is Amix 2.1c's own shared C library, the one every dynamically linked
program on the system uses. This package ships that file with 64 bytes changed, in three places,
to fix two faults in its allocator. Everything else is the stock file, byte for byte.

| | sha256 | size |
|---|---|---|
| stock, core's `/usr/lib/libc.so.1` (`system/MANIFEST.sha256`) | `09d52bb3ff5a691c9ec4b057f3b3cad484ba98ce8d057a892082ca2010dda46c` | 206876 |
| this package | `f57f624ba2d325dee8839adb5c7fcf1559f7a11ecdc21d870dcd78f75831cf52` | 206876 |

Package: `libcfix`, category `library`, set `base`, essential. Nothing is compiled and no binary is
kept here: `build.sh` takes the stock file from amix-system at its pin, checks it against
`system/MANIFEST.sha256`, checks the bytes it changes, changes them, reads them back, and checks
the result's sha256. The installer installs the package with the base set, so a new system has it
from its first boot; `apkg` carries it to systems installed before.

## Licence

The library is Commodore's, AT&T's and Amiga Corporation's, and is published, like the rest of the
Amix system files, under the approval described in amix-system's README (section "Licensing"):
`LicenseRef-Amix-System`. The 64 changed bytes, the recipe and this README are ours, under MIT
(`LICENSE.amix` in `/opt/amix/doc/libcfix`).

## The faults

**1. `realloc` hands a live block back to `malloc`.** When `realloc` grows the block at the top of
the heap, it records that block as the heap's free end (`Bottom`) and asks for more memory. If
`sbrk` refuses, it takes its block back from `Bottom` but leaves `Bottom` pointing at it. The
caller's block, still in use, now counts as free, and the next `malloc` that fits returns memory
inside it. Measured on a 68060 and a 68030 under an 8 Mbyte data limit: `realloc` to 512 Mbyte
fails, as it should, and the next four `malloc(4096)` all return addresses inside the caller's
1 Mbyte block, which is then overwritten. Under memory pressure this damaged heaps silently:
Vim wrote files with lines lost, and a stress test died in `t_delete`.

**2. A request of 2 Gbyte or more shrinks the heap.** `malloc` and `realloc` have no ceiling.
For a size with the top bit set, `_morecore`'s arithmetic wraps and it calls `sbrk` with a
negative increment, which gives back memory still in use and leaves `malloc`'s own record of the
break wrong. Only a caller that already has a bad size gets there (Vim, out of memory, asked for
0xffc7d8b8 bytes), but instead of a NULL it gets a heap that faults later, elsewhere.

## The bytes

Offsets are file offsets, which are the library's own addresses (its text segment is mapped at
offset 0).

| Offset | Stock | Fixed | What |
|---|---|---|---|
| `0x1cfb6` | `2875 0170 0000 03c4 2654` | `286d 03c4 2654 4294 4e71` | In `realloc`, after `_morecore` fails: `tp = Bottom` and now `Bottom = NULL` (`clr.l (a4)`). The load of `Bottom`'s address goes from the 8-byte form to the 4-byte one with the same operand, which makes the room. |
| `0x1cc94` | `242e 0008 7203 c282 6700 000a 2002 5880 2400 9481 2875 0170 0000 03b4` | `242e 0008 6b00 019e 7203 c282 6700 000a 2002 5880 2400 9481 286d 03b4` | `malloc`'s entry: a size with the top bit set branches (`bmi.w`) to `malloc`'s own `return NULL` at `0x1ce38`. The size rounding moves down 4 bytes, its branch offset unchanged; the load at the end takes the 4-byte form. |
| `0x1d2dc` | `2875 0170 0000 03c8` + 26 bytes | `286d 03c8` + the same 26 bytes | `_morecore`: the load of `Baddr`'s address takes the 4-byte form, and the 26 bytes after it (the size computation, whose branches stay inside them) move down 4. |
| `0x1d2fa` | (the end of the 26 bytes) | `6b18 4e71` | After the size is rounded to pages: a negative growth branches (`bmi.s`) to `_morecore`'s own `return NULL` at `0x1d314`. Covers `realloc`, which grows through `_morecore`. |

The 68060 scanner reports the stock and the fixed library alike: clean, 20 switch tables
skipped.

## What it does not cover

- **`realloc` to `0xfffffffd`–`0xffffffff`**: the size rounding at `realloc`'s entry wraps to a few
  bytes before any check, and there is no room at that entry for one. Such a call returns a small
  block. `malloc` of those sizes returns NULL.
- **`calloc`** needs nothing: the stock one already checks that `n * size` does not wrap.
- **Copies that keep the stock code**:
  - `/etc/sulogin`, the one stock program linked statically, against `libc.a`;
  - the installer's own statically linked `pkgadd`;
  - the RAM disks' `libc.so.1`, a different build (206796 bytes) with the same `realloc` fault at
    other offsets;
  - `libc.a`, `libp/libc.a` and `minabi/libc.so` in `/usr/ccs/lib`, for anything linked statically
    on the box.
## Install, upgrade and removal

**Install it with `apkg`**: `apkg update`, then `apkg install libcfix`. Do not use the stock
`/usr/sbin/pkgadd`: run with `-n` over the stock library it stops with "interaction required"
(rc 5) and leaves the stock file. The pkgadd of the APKGENG package, `pkgadd -n -a <admin>`,
installs it as `apkg` does.

Once installed, the contents file lists `/usr/lib/libc.so.1` under both `core` and `libcfix`
with the fixed file's size and sum, so `pkgchk` is clean for both.

The file goes in by one rename over the live name: a dynamically linked program cannot start
while `/usr/lib/libc.so.1` is missing, `mv` included. `pkgadd` writes a temporary file beside it
and renames it. Programs already running keep the library they started with until they exit.

The package is essential, and `apkg` refuses to remove it. `pkgrm` leaves the file in place
because core claims the path too.

## Tests

On a 68060 (k46) and a 68030 (k30), stock and fixed library side by side:
- a `realloc` that `sbrk` refuses at the top of the heap, then four `malloc(4096)`: stock returns
  them inside the live block and it is overwritten; fixed returns them elsewhere, the block intact;
- `malloc` and `realloc` of `0x7ff00000` to `0xfffffff0`: NULL, with the heap whole after each;
- 300,000 random `malloc`, `realloc` and `free` calls under an 8 Mbyte data limit, with about
  11,000 refusals each, every block's contents checked: stock fails one seed in `t_delete`, the
  fixed library passes every seed;
- Vim on a 57 Mbyte edit under a 32 Mbyte data limit, its output compared whole.
