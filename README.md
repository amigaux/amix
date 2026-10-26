# amix-modules

Generic loadable kernel modules for Amiga UNIX (Amix) that belong to no single hardware driver repository:
one directory per module, each built for both kernel lines (k30, k46) with amix-dlm's ABI kit and shipped as
its own packages (`<name>-k30` / `<name>-k46`, C3-5). Hardware drivers with their own repository keep their
module there (z3660eth, z3660rtg, a4091, gayle-ide, z3660scsi, cdfs).

| Module | Class | Majors | Origin |
|---|---|---|---|
| `monsw` | demand | c 52 | the console monitor switch; moved from amix-040-060-port `src/monsw.c` (2026-10-26, D-3 / S3-27) |

Layout: `<module>/` holds the source, `<module>/module/Makefile` (the kit's `mk/module.mk`), `<module>/module/Master`,
`<module>/module/VERSION` (the package version, one line `x.y.z-rev`), and the module's `keys`. `include/sys/` holds the
published interface headers (`sys/monsw.h`) the ABI kit carries for module authors. Contracts: amix-dlm `docs/contracts/`.
