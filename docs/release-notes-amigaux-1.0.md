# amigaux 1.0 — release notes (DRAFT, installer and K1 card part)

**amigaux 1.0** — Amiga UNIX 2.1 install kit for the Z3660 and classic Amigas, release 1.0.

This part covers what amix-installng ships; the full release notes combine it with the notes of the other
amigaux repositories. Values marked _(r5)_ were filled when the K1 r5 card was cut. Items marked _(r6)_ describe the r6
card set (one kernel per driver family, D-2) and are confirmed when its emulator and metal rows pass.

## The K1 card: Z3660 with a real 68060, in an A3000, A4000 or A4000T

- **Machines:** an A3000, an A4000 (desktop) or an A4000T with a Z3660. The A3000 and the A4000T are supported: the
  same boot path and media as the A4000D, which carries the 1.0 hardware acceptance.
- **Disks:** a ready-installed Amix desktop (RTG) and two installers, interactive and unattended. A blank
  200 MB target. A first-boot dialog asks for the name, network, time zone, package repository and root
  password.
- **Kernel:** KD060-Z _(r5: the O5 re-pin, ZS-04 + the on-box size fix)_.
- **Firmware:** ships with the project's firmware; stock firmware works with the caveats below.
  - `Z3660.bin` is fork 1.0 (C96EAD03); `BOOT.BIN` is the same fork image, the start-up loader.
  - `FAILSAFE.bin` is stock 1.03 BETA 21 (C0ADE49A).
  - Rollback: delete `Z3660.bin` (stock then runs under the project's start-up loader); full stock: copy
    `FAILSAFE.bin` over `BOOT.BIN`, then delete `Z3660.bin`.
  - On stock firmware, `kickstart 0` black-screens on a real CPU, and a rare register race can apply a
    disk request to the wrong block.
- **Kickstart:** none ships. Copy your own A4000 3.x ROM (512 KiB) to `kicks/kickstart.rom`. The presets
  map it (`kickstart 1`).
  - `kickstart 0` works only with the card's firmware.

## One kernel per driver family; any target disk at install _(r6)_

- **One kernel per family** on the card and in the build: KD060-Z (K1), the K030-U disk kernel (classic kit),
  KD060-ZA and KD060-ZA-CD (A4092). The per-unit kernel copies of earlier cards are gone.
- **Choose the target disk at install:** the K1 installers take any Z3660 unit 0-5 (unit 4 included); the CD
  installs onto Z3660 unit 0 or a disk behind the A4092. The boot loader tells the kernel which disk it was
  started from, and the kernel roots that disk, so an installed disk boots from any unit.
- **One console line at every boot says which root was used and why**, for example
  `RTH1: root c3d0s1 from the boot disk (...)` or `RTH1: root c6d0s1 built in (no record)`.
  - Without a usable hint the kernel falls back to its built-in root, Z3660 unit 6.
  - A valid hint naming an empty unit fails the mount, by design: it never boots a disk you did not
    install to.
- **A disk moved to another unit is expected to boot**, because root and swap follow the disk booted
  from, and `/sbin/bcheckrc` takes the root from the mounted disk, not from `/etc/vfstab`. This is a
  nice-to-have, tested on a short list: _(r6: the list)_.
  - `updbootpart` (kernel updates) now follows the mounted root too.

## Fixed in this release _(r6)_

- **A rare kernel panic at console login start:** `ttcompat: unexpected ioctl acknowledgment`. This is a stock SVR4
  defect: `ttcompatopen` left part of its state uninitialised. Every earlier 2.1 kernel carries it, including the
  1.0 r5 kernels; on those a reboot clears it.
- **A rare hang during an install on a small-memory 68060 box** (seen once in the emulator at 32 MB, never on
  metal): a stock SVR4 low-memory deadlock, where paging out needs memory that is not there. The 68060 kernels
  now keep pages in reserve for paging out.

## Things to know

- _(r5 cards)_ Amix mounts its root from **Z3660 unit 6**, whichever disk AmigaOS boots from. After
  installing, boot preset 3, the installed disk alone. _(r6: the root follows the disk booted, above.)_
- The installers boot at priority 1 and the installed disks at priority 2. If AmigaOS boots instead, hold
  both mouse buttons at power-on and pick UNIX_Boot.
- Shut down cleanly (`shutdown -i0 -g0 -y`) and **wait at least 10 seconds after the halt message**
  before switching off. The SD card may still be writing.
- **Black screen or no disk activity:** switch off for 20 s, then on. This covers the known Z3660 start
  issues and the restart after a file-system check that follows an unclean shutdown.
- Every card has the same Ethernet address (`02:00:00:00:00:01`). Give each machine on one network its
  own, digits only.
- During Kickstart's disk scan the Z3660's ARM may hit a known fault that recovers by itself: the firmware restarts
  within a few seconds and the boot then continues normally (about one boot in six on our A4000D; known upstream).
- The first boot takes a few minutes longer while it finishes setting up; later boots are normal.
- Do not use `reboot` or `shutdown -i6` on a real 68060: the Z3660 cannot reset the CPU, so the screen stays
  black until you switch the machine off and on again.
- Amiga UNIX does not save a crash dump on panic; the panic message and backtrace on the console/serial
  line are the only record.

## Installing from CD, and onto a disk behind the A4092 _(r6)_

- **The CD route:** the installer reads its packages from a CD (or a ZuluSCSI CD image) on the A4092 at
  SCSI id 3 (`cdfs 1,3`), booting from a small installer disk on the Z3660 SD card. Measured on an
  A4000D with the 68060 at 100 MHz: about 35 minutes for set 1 (standard, 17 packages) onto a 200 MB disk, and
  just under 2 hours for set 2 (everything, 30 packages) onto a 512 MB disk behind the A4092. The first boot
  reaches the network about 10 minutes after power-on.
- **A root on the A4092:** the target can be a disk behind the A4092 (Zulu id 1, `c9d0`). Measured on an
  A4000D, both cold boots clean, and every installed file byte-identical to the package contents.
- **Limits:**
  - **Interactive only:** there is no unattended CD install yet.
  - **The A4092 ROM (42.39) does not offer Amix partitions to Kickstart,** so a system rooted behind the
    A4092 is started from a boot disk on the Z3660 SD. That disk carries a root record naming the A4092
    disk.
  - **Only the CD driver may talk to the CD unit.** Never `dd` or `fsck` its `/dev` node; a 512-byte read of
    a 2048-byte CD wedges the A4092 bus until power-off. The installer keeps away from it by itself.
  - **ZuluSCSI:** name the image `CD3.iso` (2048-byte blocks) and leave unit attention off (no
    `zuluscsi.ini` flag for it). The CD driver cannot recover a unit attention.
  - The ISO's system ID stays blank, so the A4092 ROM gives the disc boot priority -1 and never boots it
    over the installer.

## The package engine: 1.12.3 replaces 1.12.0 on the 68060 _(r6)_

- **What the 68060 lacks:** the 64-bit forms of the integer multiply and divide instructions, and `movep`,
  `cmp2`/`chk2`, `cas2`.
  - The r6 kernels carry Motorola's 68060 Integer Support Package: the 64-bit **multiply** and **divide** forms,
    `movep` and `cmp2`/`chk2` are emulated. Only `cas2` and a misaligned `cas` still kill the program.
  - Kernels before r6's second cut emulated only some 64-bit multiply forms; a 64-bit **divide** killed the program.
  - The 68030 has all of these instructions, so it is not affected.
- **The July 2026 build of the package engine (APKGENG 1.12.0, as published on pkg.amigaux.org)** uses 64-bit
  divides. On a 68060, `installf -f`, `pkgchk` and other tools are killed. The engine on the K1 cards up to r5 is a
  different 1.12.0 build, and is not hit in ordinary use (measured).
- **1.0 ships APKGENG 1.12.3,** rebuilt without these instructions and checked clean for the 68060 by a scanner. It
  is also published to the repository.
- **The add-on packages** (acompat, zlib, patch, gzip, less, tar, make) are rebuilt the same way as package
  revision -2. The previous builds ran on the 68060 under the kernel's multiply emulation, only slower: measured on
  an emulated 68060, no tool was killed.
- **Upgrading a box installed from a K1 card:** `apkg update`, then `apkg upgrade apkgeng`. Measured on an
  emulated 68060 with the K1 r5 engine: upgrades itself cleanly, and the new engine adds, checks and
  removes packages.
- **A 68060 box running the July engine cannot upgrade itself:** its own `pkgadd` stops during the upgrade
  ("APKGENG quit in analysis state"). Install the new engine with the system's own `pkgadd` instead, as root
  (measured on an emulated 68060, both after a failed `apkg upgrade` and on a box that never tried one):

      /usr/apkg/bin/apkg update
      cd /tmp
      if [ -d /var/sadm/pkg/APKGENG ]; then mv /var/sadm/pkg/APKGENG /var/sadm/pkg/.save.APKGENG; fi
      P=`/usr/apkg/bin/apkg download apkgeng | tail -1`
      sed 's/^instance=.*/instance=overwrite/' /var/apkg/admin > /tmp/admin
      cp /var/sadm/install/contents /var/sadm/install/contents.bak
      /usr/apkg/bin/contents-fsck -r -s /var/sadm/install/contents
      cp /var/sadm/install/contents.fixed /var/sadm/install/contents
      /usr/sbin/pkgadd -n -a /tmp/admin -d $P APKGENG
      rm -rf /var/sadm/pkg/.save.APKGENG
      /usr/apkg/bin/apkg info apkgeng

  - The last line must say `Installed: yes, version 1.12.3`.
  - The three lines before `pkgadd` repair the package database for the system's own tools. Records whose path
    contains a space (one stock X11 R5 font file is named `TrueType Fonts`) cannot be read by the stock `pkgadd`;
    `contents-fsck -s` drops them, and the original is kept as `contents.bak`.
  - If `pkgadd` fails, undo the move: `mv /var/sadm/pkg/.save.APKGENG /var/sadm/pkg/APKGENG`.
  - The stale lock the failed upgrade leaves (`/var/sadm/install/.lockfile`) does not block this `pkgadd`.
- **The system's own `pkgadd -n` cannot install a package that carries install scripts.** It stops with
  "Installation of <...> was suspended (interaction required)" (exit 5) whatever the admin file says. The recipe above
  works because APKGENG has no scripts. APKG 0.2.3 has one (it keeps an edited `/etc/apkg.conf`), so upgrade APKG
  with the package engine (`apkg upgrade apkg`), not with `/usr/sbin/pkgadd` (measured on an emulated 68060 and on
  an emulated 68030 installed from the 1.0 classic media).

## The classic 68030 kit

The classic-Amiga kit (K030-U) is tested in the emulator only: the install CD on an emulated A3000 with an A4091,
and the boot-floppy route on an emulated A4000 with a full 68030 and an A4091. It has not been run on real hardware
for this release, and it does not run under the Z3660's 68030 mode: the 68030 kernel looks for the A3000's built-in
SCSI, and in that mode the A4092 becomes card 0. Support for that mode is planned for 1.1.

- **Swap:** the 68030 kernel swaps only on the first 10 MB of the swap partition, its built-in area. The installer
  adds the rest of the partition as a second area at every boot (`/etc/rc2.d/S89rootswap`; `swap -l` lists both).
  With the built-in 10 MB alone, an upgrade that runs an install script, such as `apkg upgrade apkg`, fails with
  "fork() failed errno=11 (No more processes)" and leaves the package partially installed. A classic system
  installed from pre-release media has only the built-in area; before upgrading, as root:
  `/usr/sbin/swap -a /dev/dsk/c6d0s2 20480 <blocks>`, with `<blocks>` the swap partition's length in 512-byte
  blocks minus 20480 (16384 for the default 18 MB partition).

## Older installs

Systems installed from media built before 2026-10-03 have world-writable first-boot files: a local root
hole. The hand fix is in `docs/installer.md` (SEC-1 release-notes text).
