# What's new

New packages and features, one line each, newest release first. Fixes and
internals are in each directory's `CHANGELOG.md`.

## Coming to 1.1 as packages

Added to the repository as they are ready and installed with `apkg`; no new release is needed.

- A web browser with HTTPS (text mode first, then graphical), and the HTTPS library and root certificates it needs.
- More window managers.

## Planned for 1.2

From 1.1 on, later releases upgrade an installed 1.1 system in place, with its packages through `apkg`: 1.1 is the last release that only installs clean.

Plans, with no dates; they may change.

- Offloading work such as crypto and video to the Z3660/ZZ9000's second core when one is present.
- The A600 (with a 68030 accelerator).
- Fast RAM at or above 1 GiB on the 68030 and 68040/68060, which opens the Blizzard 1230-IV/1240/1260, TF536, TF330 and ACA cards.
- Gigabit Ethernet on the Z3660 with a real 68060, without lost frames.
- Shared libraries for packages, to save memory and disk.
- `crash` and `adb` on the 68040/68060 kernel, as a boot option.

## 1.1 (unreleased)

- Loadable kernel modules on the 68030 and the 68040/68060, loaded at boot or on demand.
- Filesystems as modules, loaded when a filesystem of their type is mounted.
- One install CD for every 1.1 machine and both kernel lines, booted from the CD, boot floppies or a Z3660 boot disk.
- Install over the network, or from RAM-disk boot floppies.
- RAM-disk boot beside a software MapROM copy or a reset-proof `RAD:`: the boot loader places the image below the memory AmigaOS keeps at the top (tested in emulation: the A1200 with a 68030 and a 68040).
- The A4000's IDE disk as an install target and root disk (`gayle-ide`).
- The A4000T's onboard SCSI controller as the root disk (`a4kt710`).
- The A1200 with a 68030, 68040 or 68060 accelerator whose fast RAM sits below 1 GiB, rooted on its own IDE port (tested: Blizzard 1230-III, DKB 1240).
- The A3000, its onboard SCSI as the root disk.
- The Z3660 in its 68030 mode.
- X11R6.3 on the Z3660 graphics card (`x11r6.3`, `z3660rtg`).
- Paula audio: the `paula` driver and `/dev/paula`.
- `ztop` and `xztop`: the Z3660 board's sensors in a terminal and in an X window.
- SSH: `dropbear`, the server and client with scp, in the base set and on by default (`dropbear=no` in `/etc/rc.conf` turns it off), with a faster key exchange.
- Time sync: the clock set from time servers at boot and hourly (`ntp=yes`, the default; DHCP-announced servers first, then the pool), and the battery clock written with a corrected `setclk`.
- CDs: the `cdfs` filesystem module and its mount helper, in the base set.
- `libcfix`, in the base set: the system's C library with two memory-allocation faults fixed; a program that ran short of memory could have its data overwritten without any error (Vim saved files with lines missing).
- A `tar` that reads modern archives (GNU, ustar, pax) without crashing, from the Heirloom Toolchest.
- `/dev/random`: the `random` module.
- `sar`, `sadc` and `timex -s` work with the filesystems loaded as modules.
- `crash` starts on the 68030 line.
- New packages: `python3`, `vim`, `rsync`, `ncurses`, `pth`, `bzip2`, `prngd`, `coreutils`, `diffutils`, `libzz9k`.
- Shared libraries with GCC 14 (`gcc -shared`).
- Package repositories per release (`http://pkg.amigaux.org/1.1`).
- `make dist` builds the release reproducibly from this repository.
- Memory limits are the stock ones: one program gets 16 MiB of data and 16 MiB of address space by default.
  The hard limits are unlimited, so a user, or `/etc/profile` for everyone, can raise them with `ulimit -d`
  and `ulimit -v`.
- Network and print services that few machines need start only when `/etc/rc.conf` turns them on.
