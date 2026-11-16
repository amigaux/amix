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
- Shared libraries for packages, to save memory and disk.
- `crash` and `adb` on the 68040/68060 kernel, as a boot option.

## 1.1.2

A point release with new kernels on both lines. Its packages go into the 1.1 repository (`http://pkg.amigaux.org/1.1`), and a 1.1 or 1.1.1 system takes them in place with `apkg`; the 1.1 module packages keep working with the new kernels.
The VA2000 and ZZ9000 support is tested in emulation only, not on real cards.

- The MNT VA2000 graphics card: its kernel module (`va2000-k30`, `va2000-k46` 1.1.0-1, `/dev/va2000`) and X on it.
- The MNT ZZ9000 in Zorro II or Zorro III, on its own or beside the Z3660, then as the second display unit `/dev/zz9001` (`z3660rtg-k30`, `z3660rtg-k46` 1.1.2-3); `zz9k_probe` tells which board is behind each unit. A Zorro III ZZ9000 on the 68030 needs the new 68030 kernel.
- On a Z3660 running its emulated 68030, the Z3660's graphics are found automatically; 1.1 and 1.1.1 needed a hand-set `param fixed=1`. `fixed` is now a number: 0 (the default) automatic, 1 as before, -1 never (`z3660rtg` 1.1.2-3).
- X: one server, `Xrtg`, for every card it knows (Z3660, ZZ9000, VA2000), with `-card` and `-dev` to choose; a TERM to `xinit` ends the session and the server, as a hangup does. An upgrade keeps edited X configuration files and puts the new ones beside them as `.new` (`x11r63` 6.3-11).
- `xstart` picks the display by asking each card file's probe which board is there, and ends a server that `xinit` left running; `shutdown` waits until the system has really changed state (`amix-base` 1.0-36).
- The X-Surf-100 and X-Surf follow the link (state, speed, duplex) and say when it is lost; the probe accepts more cards and gives the reason when it refuses one; the new `xsf` tool shows the board, its link and counters (`xsurf-k30`, `xsurf-k46` 1.0.0-4).
- The 68040/68060 kernel `kern46m` k46.1.6.261115-67: a graphics card's framebuffer can use the fast non-cacheable class, and a root disk that cannot be mounted panics once, not twice.
- The 68030 kernel `kern30m` k30.1.5.261115-78: programs drawing on a Zorro III graphics card are no longer killed at random, a root disk that cannot be mounted panics once, and the panic backtrace stops at the outermost frame.
- `kbootset` 1.1.0.261115-46, which knows the VA2000 module.
- `apkg` 0.3.13: a plain `apkg upgrade` repairs an install that was cut short, a module package brings the `kbootset` it needs first, and a file that becomes a configuration file takes the new version when nobody edited it.
- `prngd` 0.9.29-4: `prngd.conf` is kept across upgrades.
- Memory limits are as in 1.1 and 1.1.1, on both kernel lines: a program's data and address space are unlimited, soft and hard, and only its stack is limited, to 16 MiB; `ulimit -d` and `ulimit -v` set a limit. A later kernel brings back the stock 16 MiB soft limits for data and address space as the default.

## 1.1.1

A point release on the 1.1 kernels. Its packages go into the 1.1 repository (`http://pkg.amigaux.org/1.1`), and a 1.1 system takes them in place with `apkg`.
Both new drivers are tested in emulation only, not on real cards.

- The Individual Computers Buddha and Catweasel Z-II IDE ports: disks and ATAPI CD-ROM drives, the root disk included (`buddha-k30`, `buddha-k46` 1.1.0-4).
- The Individual Computers X-Surf-100 and X-Surf ethernet cards, as the interface `xsf0` (`xsurf-k30`, `xsurf-k46` 1.0.0-3).
- `kbootset` 1.1.0.261114-45, which knows both drivers.
- New media replace 1.1's: the install CD, the network installer, the boot floppies and the Z3660 boot disk install onto a disk on a Buddha, and the CD and the network installer also onto one on a Catweasel Z-II.
- Every installed system carries both new drivers, and the network installer can also install over an X-Surf.
- Two new ready installed disk images, for the first port's master of a Buddha: one for the 68030, one for the 68040/68060.

## 1.1

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
- Memory limits: a program's data and address space are unlimited, soft and hard, and only its stack is
  limited, to 16 MiB. A user, or `/etc/profile` for everyone, can set a limit with `ulimit -d` and `ulimit -v`.
- Network and print services that few machines need start only when `/etc/rc.conf` turns them on.
