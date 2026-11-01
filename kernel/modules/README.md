# kernel/modules

`kernel/modules` in the amix repository (https://github.com/amigaux/amix) holds the generic loadable
kernel modules for Amiga UNIX (Amix) that belong to no single hardware driver: one directory per module,
each built for both kernel lines (k30, k46) with the ABI kit from kernel/dlm and shipped as its own
packages (`<name>-k30` / `<name>-k46`, C3-5). A hardware driver keeps its module with the driver
(z3660eth, z3660rtg, a4091, gayle-ide, z3660scsi).

Everything here is MIT (`LICENSE`) except `zz9ksvc/`, which carries the ZZ9000 SDK headers and is
GPL-3.0-or-later (`zz9ksvc/LICENSE`); its packages say so, and the interface board drivers use with
it, `include/sys/zz9kbus.h` and the `zz9kbus` module, is MIT.

| Module | Class | Majors | Origin |
|---|---|---|---|
| `monsw` | demand | c 52 | the console monitor switch; moved from amix-040-060-port `src/monsw.c` (2026-10-26) |
| `ramdisk` | root | b 20 | the RAM disk: unit 0 the loader-placed miniroot image, units 1–2 scratch disks; replaces the stock `ram` driver (2026-10-26) |
| `random` | demand | c 48 | `/dev/random` and `/dev/urandom`: ChaCha20 with fast key erasure, and the seed kept across reboots (2026-10-31, 1.1) |
| `zz9kbus` | boot | — | the registry between ZZ9000-family board drivers and `zz9ksvc` (`include/sys/zz9kbus.h`); MIT (2026-11-01) |
| `zz9ksvc` | demand | c 55 | `/dev/zz9ksvcN`, the service channel of a ZZ9000-family board's second ARM core: per-open buffers by handle, checked requests, bounded waits, mmap by handle; GPL-3.0-or-later (2026-11-01) |

Layout, per module (`monsw/README.md` is the worked example):

| Path | Content |
|---|---|
| `<module>/src/` | the source, with its module glue |
| `<module>/module/keys` | the `.moddata` keys, one `key=value` per line |
| `<module>/module/Master` | the kit's form of `keys`, generated from it |
| `<module>/module/Makefile` | builds both lines on the kit's `mk/module.mk` |
| `<module>/module/VERSION` | the package version, one line `x.y.z-rev`, the same on both lines |
| `<module>/tool/`, `<module>/rc/`, `<module>/man/` | where a module has them: its user tool, its boot step, its pages (monsw, random; ramdisk has a page) |
| `<module>/test/` | host tests and on-box instruments |
| `<module>/pkg/` | the package recipe, `<module>-k30` and `<module>-k46`: `build.sh` (make dist's kspace step runs it), `pin.sh`, `pkginfo.<line>`, the prototype, `modreg` |
| `<module>/build/<line>/mod.d/<name>` | the built module objects (not tracked) |

`pkg/kmod.sh` is the body every `<module>/pkg/build.sh` sources: it rolls each line through
build/pkg's `kmodpkg`, with the checkout as `KM_ROOT`.

`include/sys/` holds the published interface headers (`sys/monsw.h`, and `sys/zz9kbus.h`, the
interface between ZZ9000-family board drivers and `zz9ksvc`). The ABI kit of
`kernel/dlm` copies them, so a module that calls another module builds against the kit alone.

Build every module of a line with the kit of `kernel/dlm` and the pinned gcc-cross-amix
(`m68k-cbm-sysv4-*`, GCC 2.7.2.3) on `PATH`, for example `make -C monsw/module`. The
contracts are in `kernel/dlm/docs/contracts/`.

cdfs (a read-only CD filesystem, a fork of Stefan Reinauer's ODFileSystem) is to be pinned
here: its directory `cdfs/` and the pin `cdfs/cdfs.pin` arrive when the fork moves into the
amigaux organisation.
