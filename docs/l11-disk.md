# The 1.1 disk

amix-dlm `docs/spec/40-generations-and-composer.md` §2 defines it; this repository
implements it as `INSTALL_LAYOUT=1.1` (`src/installer/l11.sh`, sourced by `install.sh`).

> **1.1 requires a fresh install (2026-10-31).** There is no upgrade
> install and no update path from 1.0, and no migration code: a disk that holds Amix
> is erased and installed afresh. The upgrade install this file used to describe
> (`INSTALL_UPGRADE=yes`) is removed. Its text is
> `docs/upgrade-install.md` and its code is in `l11.sh`, `install.sh`, `setup.sh` and
> `firstboot.sh`, all in git up to 3ac92fb.

## The 1.1 disk

| Slice | DosType | Content | Size |
|---|---|---|---|
| s1 | `UNI\1` | root | what is left |
| s2 | `resv` | swap | as 1.0: 30 MB on the 040/060 line and on disks over 120 MB, else 18 MB |
| s3 | `UNI\0` | the boot store, the only `UNI\0` on the disk | 64 MiB |
| s4 | `UNI\1` | data, mounted at `/home` | `TARGET_DATA_MB`; by default a quarter of a disk of 512 MB or more, none below |

Each filesystem stays at or under 2047 MiB, 4194303 blocks (measured 2026-10-31: a
2047 MiB slice makes, fills and reads back; at 2048 MiB `mkfs_ufs` fails in `wtfs` with ENXIO
at the driver's raw-I/O clamp, at 3072 MiB with EINVAL at a 32-bit seek; spec 40 §2.1's 1024
was the old guess), and under the stock kernel's cap when `KERNEL_SDDEVSIZE` is not `fixed`.
A file over 256 MiB needs the login `ulimit` raised (amix-base 1.0-11: 4194303).

Each ufs is made with stock's `mkfs_ufs -o free=2,opt=s`; a slice over 512 MiB also gets
`nbpi=8192`, one inode per 8 KiB instead of stock's density (a 2047 MiB root then holds about
260000 inodes, not 830000, and keeps about 75 MiB more for files; the full set is about 29000
objects).

The installer:
1. authors that RDB. Before writing, it refuses a disk that already carries two
   `UNI\0` partitions, and it clears the whole RDB area (blocks 0–127).
   Afterwards it checks there is exactly one `UNI\0`, counting PART blocks by
   their DosType.
2. installs the medium's package set as for 1.0, then the base packages:
   amix-base, dhcp-client and syslog, from `/install/l11/base` (built by amix's
   reproducible roll at the set's `base` revision). They go in under the target's own
   chroot with APKGENG's engine (`/usr/apkg/bin/pkgadd`): their conffile class needs
   `cmp`, which the miniroot lacks. Before each package, `seed.sh` seeds the baseline
   (`/var/sadm/conffiles/<pkginst><path>`) of every conffile still equal to its contents
   record, so the class takes the new default silently. Then `removef core` hands
   amix-base's conffiles over from core (APKGENG's `removef`; stock 2.1 has none), and a
   fresh install that leaves a `PENDING` is refused.
3. installs, in one apkg transaction, the packages of the disk:
   - `kbootset` (userland, `/sbin/kbootset`);
   - `loader-amix` (kernel space, `/stand/loader/{boot1,boot2,ldrinfo}`);
   - the profile's kernel (`KERNEL_KPKG`: `kernel-k30-m` or `kernel-k46-m`,
     `/stand/k30|k46/{unix,kabi}`; k30's also `unix.sym`);
   - for a module kernel (its catalog row's `kabi=` is not `static`; its sidecar
     has `arena=`), `modtools` (`/sbin/modadmin`) and the profile's module
     packages (`KERNEL_MODPKGS`, catalog names `<module>-<line>`, such as
     `z3660eth-k46`; amix-dlm C3-5 v4 §1): `/etc/conf/mod.d/<module>`, the
     object, and `/etc/conf/modreg.d/<module>`, the package's defaults.

   The static apkg 0.3 on `/install/l11` takes them from the medium's FILE
   catalog, as amix-packages mints them. The box therefore carries a record for
   each and `apkg upgrade` reaches them all: the kernel-space records are
   `/var/apkg/kpkg/<pkginst>` (C2-2 v4; a module's says `role module` and names its
   two files), and kbootset and modtools are in the package database.
   `/etc/default/bootset` says `bootset=manual` meanwhile, so apkg's trigger only
   prints the commands. Neither the loader nor the kernel commits anything, and the
   store gets exactly one generation, the pristine one, in step 4.

   amix-base ships `/etc/inittab` with `dlm::sysinit:/sbin/modadmin -B </dev/console
   >/dev/console 2>&1` before its first sysinit entry (C3-5 §5): the boot-class modules
   load there. modtools (-9 on) has no package scripts and never edits the file. The
   installer checks it: exactly one line with the id `dlm`, the first sysinit entry,
   C3-5's text, and the file amix-base's default (`sum -r` against the medium's copy,
   taken from amix-base's datastream). Anything else stops the install.
4. runs the INSTALLED `/sbin/kbootset` (the package's; there is no other copy):
   - `create 67108864 /stand/loader/boot2 --boot1 /stand/loader/boot1 --version
     <ldrinfo's> --force` lays the loader package's bytes over
     whatever the slice held; `--force` makes kbootset zero the first 64 KiB itself
     (C2-4 v6 §8). `status` then prints the store's set id, which goes into
     `store-id=`;
   - `build` takes the facts: `--line`, `--bootdev`/`--rootdev` from
     `TARGET_HBA`, `--rootfs`, `--mem` from `TARGET_FASTMEM_MB`, and `--root`.
     `TARGET_FASTMEM_MB` is the fast memory of the box that will boot the disk, not of
     the machine running the install. The miniroot cannot measure it (no kinfo in the
     install kernels), so the profile states it. A kinfo kernel's own value wins at run
     time; on a kernel without kinfo (K030-U today), bootset's `mem=` is what kbootset's
     memory gate reads;
   - `build` also composes the installed modules (C2-4 §11): it copies each object
     to `/stand/gen/1/mod/<module>` on the target, where the module core loads it
     from, and writes its `module` and `param` records into the manifest;
   - `commit` writes the pristine generation;
   - `check` is the post-write proof (status 1 means a problem was found); it
     hashes the module copies too.
   Any non-zero status stops the install before anything is armed.
5. lays the following on the target:
   - `/etc/default/bootset` (C2-4 §6: `bootset=auto`, `store=`, `store-id=`, the facts);
   - `/dev/kinfo` (c 53 0, 0444; first boot gives it group sys);
   - the `updbootpart` shim, which refuses and names kbootset;
   - `/sbin/bcheckrc` with `[ -x /sbin/kbootset ] && /sbin/kbootset retry >/dev/console 2>&1`
     before each of the three `/sbin/uadmin 1 1` of its root fsck block (C2-4 v5 §7), so a
     repair reboot gives a trial its attempt back instead of spending it. The medium carries
     the patched copy, made from core's 2.1 file (md5 bff26ae7). It is written in place
     (`cat`, so `/usr/sbin/bcheckrc`, its hard link, follows), and only over the stock
     file; a changed one is left alone with a warning.

   - no `/stand/unix` and no `/unix` (C2-4 v9 §12). Core leaves `/stand/unix` as a
     hard link to `/stand/2.1_unix`, the 1992 kernel. `netstat`, `ifconfig` and
     `crash` read their kernel addresses from it, and on a 1.1 disk it is never the
     booted kernel. The name goes; `/stand/2.1_unix` stays, its `sum -r` checked;
   - `/etc/inet/interfaces`, `/etc/rc.conf` and `/etc/display`, the admin files no
     package owns (below).

   kbootset's package (-26 on) carries `/etc/rc2.d/S01kbnamelist`: it sorts
   after `S01MOUNTFSYS` and before every other run-level-2 script, and writes the
   booted generation's namelist to `/stand/unix` at every boot. The installer only
   checks that it is there. z3660eth's package (-7 on) carries
   `/etc/inet/link.d/z3660eth` and `/dev/zen0`; zen0 is a line of
   `/etc/inet/interfaces`.

   It lays none of the 1.0 boot-chain pieces: `/stand/boot2.boot`, the framed
   chain, the RTO1 record or the reframe tools.

   The first boot then:
   - takes `/stand/unix` out of core's contents: `/stand/2.1_unix` becomes its own
     file, so `pkgchk core` stays quiet on both. It uses APKG's heirloom
     `installf`/`removef` from `/tmp`; the stock ones take a bus error on the 68060;
   - gives `/etc/inittab` back root, sys, 0664. modtools rewrote it by rename, and
     the miniroot has no `chgrp`.

apkg's exit status is checked as well. These stop the install unarmed:
- a pending `/var/apkg/txn` before the kernel-space install;
- exit 6 (kbootset failed after the packages went in; the journal is kept);
- exit 7 (kbootset refused; the committed generation is unchanged);
- any other non-zero status;
- a journal left behind after exit 0.

The message names the way to finish the transaction: boot the medium, choose
repair, mount the install CD at `/cdrom` and run
`/cdrom/install/l11/bin/apkg -c /cdrom/install/l11/recover.conf -R /mnt recover`.
The repair menu reports a pending journal with the same command. Until kbootset
reads `store=` from `/etc/default/bootset`, the trigger that `recover`
runs cannot find the store, so recover still exits 6 after it reinstalls the
packages. Then compose the store from the repair shell:
`/mnt/sbin/kbootset -R /mnt --dev <store=> build`, then `commit`.

`/etc/rc2.d/S99zkbootset`, the last run-level-2 script, kbootset's link of
`/etc/init.d/kbmarkgood` (-26 on), runs C2-4 §9's
`/sbin/kbootset mark-good >/dev/console 2>&1`, with no options. kbootset takes the booted
generation from the loader record through kinfo, so a box that came all the way up
marks its trial good (spec 40 §3.3). One that panics or hangs in `rc` never gets
there, and the loader's try-once rule boots the previous good generation. On the
pristine first boot it says that generation 1 is good and there is nothing to
mark.

The repair path of the install miniroot (`install or repair` → `repair`) mounts
the root. On a 1.1 disk it then offers `status`, `rollback` and `mark-bad`
through the disk's own `/sbin/kbootset`, using the store named in its
`/etc/default/bootset`.

## The admin files and the first boot

Three files no package owns are written by the installer from the profile, each
checked by its reader under the target's chroot:

| File | From | Checked by |
|---|---|---|
| `/etc/inet/interfaces` (`interfaces(4)`) | a static profile (`FB_IP` set: bench, metal, matrix): `FB_ETHER_IF static FB_IP/bits gw FB_GATEWAY name FB_NODENAME`, a `zen0` line from `FB_ZEN_IP`, a MAC line per `FB_ZEN_CARDS` row, `dns`, `domain`. A public profile (no `FB_IP`): `* dhcp`, with its name or `hostname dhcp` | `ifup -n` |
| `/etc/rc.conf` (`rc.conf(4)`) | `syslogd=yes` or `no` (`FB_SYSLOG`) | |
| `/etc/display` (`display(4)`) | `card auto`, `monsw` from `MONSW`, `start manual` | `xstart -n` |

amix-base's `ifup` (S69inet) brings the interfaces up from `/etc/inet/interfaces`, and
writes this host's row of `/etc/inet/hosts` and the DNS parts. The packages carry what
the installer used to write: S99zen and zen.conf (z3660eth and `interfaces`), S20monsw
and `/etc/monsw` (monsw; the bits are `/etc/display`'s), the syslog unit (syslog: it
reads `syslogd=`; the 2.1c daemon stays the installer's overwrite, since no package
carries it), S89rootswap (amix-base's swap step, S90swap), S01kbnamelist and
S99zkbootset (kbootset). `/dev/kinfo` stays installer-written until kbootset -29
carries it.

The first boot of a 1.1 disk (`FB_L11=y` in `firstboot.conf`):
- the dialog asks `Use DHCP to configure the network?` (`* dhcp`) or one static
  interface, and offers DNS on every interface. Its answers become
  `/etc/inet/interfaces`; the syslog answer is `syslogd=` in `/etc/rc.conf`;
- the name may be left empty: it is then the name a DHCP server offers
  (`hostname dhcp`), else `amix-` and the last four hex digits of the first interface's
  MAC (`dlpi-mac`, zen0 first);
- it writes no host row, no S99zen, no rc.inet route and no DNS parts (ifup's), and
  does not edit `/etc/profile` (amix-base's conffile): the X11 and apkg PATH go in
  `/etc/profile.d/x11.sh` and `opt-amix.sh`. The desktop session is amix-base's
  `xstart`.

## Over a disk that holds Amix

A 1.1 install never keeps anything of the disk it is laid on:
- the interview asks stock's erase question (*"Are you sure you want to erase this
  disk?"*, no default) for any disk that carries an RDB, a 1.0 or 1.1 Amix disk
  included. It offers no upgrade;
- an unattended profile is refused over a disk with an RDB unless it sets
  `TARGET_ERASE_OK=yes`;
- `INSTALL_UPGRADE` set to anything but `no` stops the install: *"1.1 requires a
  fresh install"*;
- the RDB area is cleared and the layout above is authored. The new root carries
  no `/var/adm/upgrade` and no `/etc/rc2.d/S17upgrade`, and the first boot runs
  the dialog and the first-boot configuration in full. `tools/l11-target-check.py`
  checks this on every 1.1 target.

Matrix cell `l11-k46-reinstall-ia` proves it: `l11-rd-k46` over a copy of an installed
r7 060 disk with a seeded user (`TARGET_SRC`, default
`work/p36/r7-060-cd1pub-seeded.hdf`). The interview is answered `y 105 30 1 n n`, the
beacon carries the sizes, and `bootstore` checks that nothing of the old disk is left
(`EXPECT_ABSENT`: no `/home/alice`, no `alice` in `passwd` or `shadow`, not its node
name or hosts line, no `/var/adm/upgrade`, no `S17upgrade`). Then the first boot runs.

What `apkg upgrade` and kbootset's generations do on an installed 1.1 disk (a new
kernel or module package, a rollback) is unchanged: that is the running system's
package path, not the installer's.
