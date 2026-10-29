# amix-dlm — loadable kernel modules for Amix

Amix (Amiga UNIX) is Commodore's port of AT&T System V Release 4 to the
68030-based Amiga 3000UX, released in 1990–1992. The community distribution
built around it (amigaux.org) now runs it on two CPU lines: the classic 68030
line and a 68040/68060 line. Stock Amix has no loadable kernel modules: every
disk controller, network card, graphics board and filesystem is linked into
one kernel image, so every new driver means a new kernel and a new install
medium.

This repository is the home of loadable kernel modules for Amix release 1.1,
on both CPU lines and on every install medium. It holds five things:

| Part | What it is | Status |
|---|---|---|
| **Boot loader** | Our own first- and second-stage loaders (`boot1`, `boot2`), written from scratch. The loader reads a *generation manifest*, loads the kernel and the modules the root disk needs as separate files, reads disks, floppies and 2048-byte CD-ROM blocks, and offers a boot menu with a rollback key and a safe mode. | specified (`docs/spec/10-boot-loader.md`) |
| **Module core** | A patch queue on top of the MIT-licensed DLM ("dynamically loadable modules") core by kdedon, from the [ashnazag](https://github.com/kdedon/ashnazag) project. The upstream code keeps its author's copyright and MIT notice; our patches add pre-root loading, ABI identity, match keys, disk-controller and filesystem registration, interrupt attachment and a halt pass. | specified (`docs/spec/30-module-core.md`) |
| **kbootset** | The composer. It builds a *generation* (kernel + root modules + manifest + module store) from installed packages, writes it to the boot slice behind fail-closed checks with read-back, keeps the previous generation and the pristine install generation, rolls back, and marks a generation good only after a full multi-user boot. | specified (`docs/spec/40-generations-and-composer.md`) |
| **ABI kit** | The headers, the exported-symbol allowlist and the module tooling an outside developer needs to build a module for a given kernel line. | specified (`docs/spec/20-module-format-and-abi.md`) |
| **Specification** | The design every part above is built against. | `docs/spec/` — start at `00-overview.md` |

No code exists yet; the specification comes first.

## Toolchain

Everything that runs in kernel space — the kernel, drivers, the loader, the
module core and every module — is built with the period cross toolchain
[gcc-cross-amix](https://github.com/isoriano1968/gcc-cross-amix): GCC 2.7.2.3
targeting `m68k-cbm-sysv4`. Each kernel line pins one compiler, and the ABI
kit records the pin. The modern GCC 14 cross compiler is used for userland
only (including `kbootset` and the package tools) and never for kernel space.

## What is not here

No Commodore or AT&T material is tracked in this repository: no kernel
source, no headers from the Amix development kit, no binaries, no ROM images.
Where the design depends on the behaviour of a stock component, the
specification describes that behaviour and names the component; it does not
reproduce it. The published ABI kit additionally carries the stock Amix
kernel headers a module build needs, under the project's distribution
permission; the kit build adds them, so they never enter this repository's
history.

## Related projects

- [ashnazag](https://github.com/kdedon/ashnazag) — one SVR4 kernel for 68k
  Mac, Atari and Amiga; origin of the DLM core adopted here.
- [amix-040-060-port](https://github.com/asokero/amix-040-060-port) — the
  68040/68060 port of the Amix kernel; the kernel-side hooks are offered to it
  as merge requests.
- [gcc-cross-amix](https://github.com/isoriano1968/gcc-cross-amix) — the
  kernel-space cross toolchain.
- [amigaux.org](http://amigaux.org/) — the distribution, its documentation,
  and the package repository at `pkg.amigaux.org`.

## Layout

```
docs/spec/     the specification, one file per area (00-overview.md first)
docs/measurements/  records of closed measurements
docs/          other documentation (see docs/README.md)
tools/measure/ host-side measurement scripts
```

Planned, as the code arrives: `loader/` (boot1, boot2, filesystem readers),
`core/` (the patch series over the upstream DLM core), `kbootset/`,
`abi/` (the ABI kit).

## Licence

MIT, see `LICENSE`. The adopted DLM core is MIT, Copyright (c) 2026 kdedon;
its notice is kept on every file taken from it.
