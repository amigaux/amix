# amix

One repository that builds the Amiga UNIX (Amix) system: the kernels for the
68030 and the 68040/68060, the loadable-module system, the drivers, the
generic modules, the package tools and recipes, and the install media.

## Status

Being assembled. Projects move in one at a time, each with its history kept.
Until a directory holds its project, its README says what will live there.

## Layout

| Directory | What lives there |
|-----------|------------------|
| `kernel/port/` | The 68040/68060 port: Antti Sokero's tree plus the module kernel chain |
| `kernel/k30/` | The 68030 kernel cut |
| `kernel/dlm/` | Loadable modules: boot loaders, module core, ABI kit, spec |
| `drivers/` | Hardware drivers (SCSI, ethernet, RTG, audio, IDE, CD filesystem) |
| `modules/` | Generic kernel modules that belong to no hardware driver |
| `userland/pkgtools/` | The package tools |
| `userland/recipes/` | Package recipes: `core/` for the base system, `extra/` for the rest |
| `media/` | Boot and install media |
| `toolchain/` | Compiler pins only |
| `system/` | The system-file manifest only; the Commodore files live elsewhere |
| `release/` | Lock files for releases |
| `build/` | The build system |
| `docs/` | Documentation |

## More

The project's home is <https://amigaux.org>.

## Licence

MIT, see [LICENSE](LICENSE). A directory that carries its own LICENSE keeps it.
