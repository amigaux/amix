# amix

One repository that builds the Amiga UNIX (Amix) system: the kernels for the
68030 and the 68040/68060, the loadable-module system, the drivers, the
generic modules, the package tools, the outside software packaged for Amix,
and the install media.

## Status

Being assembled. Projects move in one at a time, each with its history kept.
Until a directory holds its project, its README says what will live there.

## Layout

| Directory | What lives there |
|-----------|------------------|
| `kernel/port/` | The 68040/68060 base: Antti Sokero's tree plus our module kernel chain |
| `kernel/k30/` | The 68030 kernel, cut from Commodore's relink kit |
| `kernel/dlm/` | Loadable modules: boot loaders, module core, ABI kit, spec, kbootset |
| `kernel/drivers/` | Hardware drivers, one directory each, recipe inside |
| `kernel/modules/` | Generic loadable modules, recipe inside |
| `userland/pkgtools/` | apkg, the Heirloom package engine, catalog tools |
| `userland/packages/` | Outside software, flat, one directory per package |
| `media/` | CD, netinstall and floppy builders, install profiles |
| `toolchain/` | Cross-compiler pins and the container recipe |
| `system/` | The system-file manifest and the replaced-files list; the files live in `amix-system` |
| `release/` | Lock files, one per release |
| `build/` | `make dist`, the build container, the packaging framework |
| `tools/` | Host-side developer tools |
| `docs/` | Building, layout, ownership, release process |
| `.github/` | CODEOWNERS, CI, templates |

## Principles

- The tree follows the two catalogs: everything under `kernel/` ships in the
  kernel-space catalog, everything under `userland/` in the userland catalog.
- A package's recipe lives next to its code; `userland/packages/` holds only
  outside software.
- Packages are flat: the installer set and the category are fields, not
  directories.
- The cross compilers that build Amix are pinned in `toolchain/`; developer
  tools that run on the box are ordinary packages.

## More

The project's home is <https://amigaux.org>.

## Licence

MIT, see [LICENSE](LICENSE). A directory that carries its own LICENSE keeps it.
