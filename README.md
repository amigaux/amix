# amix

One repository that builds the Amiga UNIX (Amix) system: the kernels for the
68030 and the 68040/68060, the loadable-module system, the drivers, the
generic modules, the package tools, the outside software packaged for Amix,
and the install media.

Amix 1.1 is out: the install media are on
[amigaux/amix-media](https://github.com/amigaux/amix-media/releases), and the
packages at <http://pkg.amigaux.org/1.1>. Installing it:
<https://amigaux.org/install/>.

## Build it yourself

`make dist` builds the whole release from this repository, in a container, the
same bytes on any machine:

```sh
git clone https://github.com/amigaux/amix.git && cd amix
system/fetch-amix-system ../amix-system
make tools SYSTEM=../amix-system
make dist  SYSTEM=../amix-system RELEASE_PUBLIC=1
```

You need Linux on x86-64 with docker (podman and other hosts are untested), a
full clone (not shallow), network for the first run, about 7 GB of disk, and
time. `make tools` downloads the published build images (about 0.9 GB); with
`TOOLS_FROM_SOURCE=1`, or when the download fails, it builds them, in about 19
minutes on a 32-thread machine. `make dist` took 28 minutes there. Everything
lands in `out/`. If `make tools` stops on a download, run it again later:
every download is pinned, and what was fetched is kept.
[docs/BUILDING.md](docs/BUILDING.md) explains each step, what it builds, and how
to check a build against a release; [docs/RELEASING.md](docs/RELEASING.md) how
releases are made.

## Status

Projects move in one at a time, each with its history kept. Until a directory
holds its project, its README says what will live there.

## Layout

| Directory | What lives there |
|-----------|------------------|
| `kernel/port/` | The 68040/68060 kernel, pinned by commit to a fork of Antti Sokero's port |
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
- Projects that other developers lead stay in their own repositories and are
  pinned here by commit; they can move in later with their history.

## More

What each release brings: [docs/WHATS-NEW.md](docs/WHATS-NEW.md). The
project's home is <https://amigaux.org>.

## Licence

MIT, see [LICENSE](LICENSE). A directory that carries its own LICENSE keeps it.
