# What's new

New packages and features, one line each, newest release first. Fixes and
internals are in each directory's `CHANGELOG.md`.

## 1.1 (unreleased)

- Loadable kernel modules on the 68030 and the 68040/68060, loaded at boot or on demand.
- Filesystems as modules, loaded when a filesystem of their type is mounted.
- One install CD for every 1.1 machine and both kernel lines, booted from the CD, boot floppies or a Z3660 boot disk.
- Install over the network, or from RAM-disk boot floppies.
- The A4000's IDE disk as an install target and root disk (`gayle-ide`).
- The A4000T's onboard SCSI controller as the root disk (`a4kt710`).
- The A1200 with a 68030, 68040 or 68060 accelerator whose fast RAM sits below 1 GiB, rooted on its own IDE port (tested: Blizzard 1230-III, DKB 1240).
- The A3000, its onboard SCSI as the root disk.
- The Z3660 in its 68030 mode.
- X11R6.3 on the Z3660 graphics card (`x11r6.3`, `z3660rtg`).
- Paula audio: the `paula` driver and `/dev/paula`.
- `ztop` and `xztop`: the Z3660 board's sensors in a terminal and in an X window.
- SSH: `dropbear`, the server and client with scp, in the base set and on by default (`dropbear=no` in `/etc/rc.conf` turns it off), with a faster key exchange.
- CDs: the `cdfs` filesystem module and its mount helper, in the base set.
- A `tar` that reads modern archives (GNU, ustar, pax) without crashing, from the Heirloom Toolchest.
- `/dev/random`: the `random` module.
- `sar`, `sadc` and `timex -s` work with the filesystems loaded as modules.
- `crash` starts on the 68030 line.
- New packages: `python3`, `vim`, `rsync`, `ncurses`, `pth`, `bzip2`, `prngd`, `coreutils`, `diffutils`, `libzz9k`.
- Shared libraries with GCC 14 (`gcc -shared`).
- Package repositories per release (`http://pkg.amigaux.org/1.1`).
- `make dist` builds the release reproducibly from this repository.
- Programs can use all of the machine's memory: data and mapped-memory limits are unlimited by default.
- Network and print services that few machines need start only when `/etc/rc.conf` turns them on.
