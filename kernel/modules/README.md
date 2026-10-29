# amix-modules

Generic loadable kernel modules for Amiga UNIX (Amix) that belong to no single hardware driver repository:
one directory per module, each built for both kernel lines (k30, k46) with amix-dlm's ABI kit and shipped as
its own packages (`<name>-k30` / `<name>-k46`, C3-5). Hardware drivers with their own repository keep their
module there (z3660eth, z3660rtg, a4091, gayle-ide, z3660scsi, cdfs).

| Module | Class | Majors | Origin |
|---|---|---|---|
| `monsw` | demand | c 52 | the console monitor switch; moved from amix-040-060-port `src/monsw.c` (2026-10-26, D-3 / S3-27) |
| `ramdisk` | root | b 20 | the RAM disk: unit 0 the loader-placed miniroot image, units 1–2 scratch disks; replaces the stock `ram` driver (2026-10-26, D-3 / S4-34) |

Layout, per module (`monsw/README.md` is the worked example):

| Path | Content |
|---|---|
| `<module>/src/` | the source; where a module also has a static form, its module glue sits under `-D<NAME>_MODULE` (monsw) |
| `<module>/module/keys` | the `.moddata` keys, one `key=value` per line |
| `<module>/module/Master` | the kit's form of `keys`, generated from it |
| `<module>/module/Makefile` | builds both lines on the kit's `mk/module.mk` |
| `<module>/module/VERSION` | the package version, one line `x.y.z-rev`, the same on both lines |
| `<module>/test/` | host tests and on-box instruments |
| `<module>/build/<line>/mod.d/<name>` | the built module objects (not tracked) |

`include/sys/` holds the published interface headers (`sys/monsw.h`). amix-dlm's ABI kit
copies them, so a module that calls another module builds against the kit alone.

Build every module of a line with amix-dlm's kit and the pinned gcc-cross-amix
(`m68k-cbm-sysv4-*`, GCC 2.7.2.3) on `PATH`, for example `make -C monsw/module`. The
contracts are in amix-dlm `docs/contracts/`.

Pinned fork: `cdfs/` (a read-only CD filesystem), a fork of Stefan Reinauer's
ODFileSystem. Its directory holds only a README and `cdfs/cdfs.pin`, naming
the fork and the exact commit the build uses.

A pin file is one line, `<git URL> <full commit hash>`; the build fetches that
exact commit.
