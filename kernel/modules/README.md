# kernel/modules

`kernel/modules` in the amix repository (https://github.com/amigaux/amix) holds the generic loadable
kernel modules for Amiga UNIX (Amix) that belong to no single hardware driver: one directory per module,
each built for both kernel lines (k30, k46) with the ABI kit from kernel/dlm and shipped as its own
packages (`<name>-k30` / `<name>-k46`, C3-5). A hardware driver keeps its module with the driver
(z3660eth, z3660rtg, a4091, gayle-ide, z3660scsi).

| Module | Class | Majors | Origin |
|---|---|---|---|
| `monsw` | demand | c 52 | the console monitor switch; moved from amix-040-060-port `src/monsw.c` (2026-10-26, D-3 / S3-27) |
| `ramdisk` | root | b 20 | the RAM disk: unit 0 the loader-placed miniroot image, units 1–2 scratch disks; replaces the stock `ram` driver (2026-10-26, D-3 / S4-34) |
| `random` | demand | c 48 | `/dev/random` and `/dev/urandom`: ChaCha20 with fast key erasure, and the seed kept across reboots; the interface of isoriano's random-amix, new code (2026-10-31, 1.1) |

Layout, per module (`monsw/README.md` is the worked example):

| Path | Content |
|---|---|
| `<module>/src/` | the source; where a module also has a static form, its module glue sits under `-D<NAME>_MODULE` (monsw) |
| `<module>/module/keys` | the `.moddata` keys, one `key=value` per line |
| `<module>/module/Master` | the kit's form of `keys`, generated from it |
| `<module>/module/Makefile` | builds both lines on the kit's `mk/module.mk` |
| `<module>/module/VERSION` | the package version, one line `x.y.z-rev`, the same on both lines |
| `<module>/tool/`, `<module>/rc/`, `<module>/man/` | where a module has them: its user tool, its boot step, its pages (monsw, random) |
| `<module>/test/` | host tests and on-box instruments |
| `<module>/build/<line>/mod.d/<name>` | the built module objects (not tracked) |

`include/sys/` holds the published interface headers (`sys/monsw.h`). The ABI kit of
`kernel/dlm` copies them, so a module that calls another module builds against the kit alone.

Build every module of a line with the kit of `kernel/dlm` and the pinned gcc-cross-amix
(`m68k-cbm-sysv4-*`, GCC 2.7.2.3) on `PATH`, for example `make -C monsw/module`. The
contracts are in `kernel/dlm/docs/contracts/`.

cdfs (a read-only CD filesystem, a fork of Stefan Reinauer's ODFileSystem) is to be pinned
here: its directory `cdfs/` and the pin `cdfs/cdfs.pin` arrive when the fork moves into the
amigaux organisation.
