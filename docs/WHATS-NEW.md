# What's new

New packages and features, one line each, newest release first. Fixes and
internals are in each directory's `CHANGELOG.md`.

## 1.1 (unreleased)

- Loadable kernel modules on the 68030 and the 68040/68060, loaded at boot or on demand.
- Filesystems as modules, loaded when a filesystem of their type is mounted.
- Install over the network, or from RAM-disk boot floppies.
- The A4000T's onboard SCSI controller as the root disk (`a4kt710`).
- Planned: installing to the A4000's IDE disk.
- Planned: the Z3660 in its 68030 mode.
- X11R6.3 on the Z3660 graphics card (`x11r6.3`, `z3660rtg`).
- Paula audio: the `paula` driver and `/dev/paula`.
- `/dev/random`: the `random` module.
- New packages: `python3`, `vim`, `rsync`, `ncurses`, `pth`, `bzip2`, `prngd`, `coreutils`, `diffutils`.
- Shared libraries with GCC 14 (`gcc -shared`).
- Package repositories per release (`http://pkg.amigaux.org/1.1`).
- `make dist` builds the release reproducibly from this repository.
