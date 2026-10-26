# The 1.1 disk and the upgrade install

amix-dlm `docs/spec/40-generations-and-composer.md` §2, §7 and D-3 §5 define them;
this repository implements them as `INSTALL_LAYOUT=1.1` (`src/installer/l11.sh`,
sourced by `install.sh`) and `INSTALL_UPGRADE=yes`. Stage-2 work items S2-30 and S2-31.

## The 1.1 disk

| Slice | DosType | Content | Size |
|---|---|---|---|
| s1 | `UNI\1` | root | what is left |
| s2 | `resv` | swap | as 1.0: 30 MB on the 040/060 line and on disks over 120 MB, else 18 MB |
| s3 | `UNI\0` | the boot store, the only `UNI\0` on the disk | 64 MiB |
| s4 | `UNI\1` | data, mounted at `/home` | `TARGET_DATA_MB`; by default a quarter of a disk of 512 MB or more, none below |

Each filesystem stays at or under 1024 MiB (`mkfs_ufs`'s limit), and under the
stock kernel's cap when `KERNEL_SDDEVSIZE` is not `fixed`.

The installer:
1. authors that RDB. Before writing, it refuses a disk that already carries two
   `UNI\0` partitions, and it clears the whole RDB area (blocks 0–127).
   Afterwards it checks there is exactly one `UNI\0`, counting PART blocks by
   their DosType.
2. installs the medium's package set as for 1.0.
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

   modtools' postinstall puts `dlm::sysinit:/sbin/modadmin -B </dev/console
   >/dev/console 2>&1` in `/etc/inittab` before its first sysinit entry (C3-5
   §5): the boot-class modules load there. The installer then checks the file:
   exactly one line with the id `dlm`, the first sysinit entry, C3-5's text, and
   the rest core's inittab (`sum -r` against the medium's copy). Anything else
   stops the install and names the postinstall.

   modtools (-4 on) refuses to touch an inittab whose dlm line is misplaced or
   duplicated, and an inittab that would be left empty: it exits 1 and leaves the
   file for the administrator. Neither the installer nor the package makes such a
   file; a fresh install starts from core's.
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
   - `/etc/rc2.d/S01kbnamelist`, the one line
     `[ -x /sbin/kbootset ] && /sbin/kbootset namelist >/dev/console 2>&1`. It
     sorts after `S01MOUNTFSYS` and before every other run-level-2 script, and
     writes the booted generation's namelist to `/stand/unix` at every boot. The
     installer cannot write it: where the kernel is bound is known only once it
     has booted;
   - `/etc/rc2.d/S99zen` when the z3660eth module is installed, on either line.
     A profile whose interface is zen0 brings zen0 up at `FB_IP`. Otherwise zen0
     comes up beside that interface at its own `FB_ZEN_IP` (`FB_ZEN_NETMASK`,
     optional `FB_ZEN_GATEWAY`), or is left down when there is none. It never takes
     `FB_IP`.

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
reads `store=` from `/etc/default/bootset` (S2-06), the trigger that `recover`
runs cannot find the store, so recover still exits 6 after it reinstalls the
packages. Then compose the store from the repair shell:
`/mnt/sbin/kbootset -R /mnt --dev <store=> build`, then `commit`.

`/etc/rc2.d/S99zkbootset`, the last run-level-2 script (it sorts after `S99zen`),
runs C2-4 §9's `[ -x /sbin/kbootset ] && /sbin/kbootset mark-good >/dev/console 2>&1`,
with no options. kbootset takes the booted
generation from the loader record through kinfo, so a box that came all the way up
marks its trial good (spec 40 §3.3). One that panics or hangs in `rc` never gets
there, and the loader's try-once rule boots the previous good generation. On the
pristine first boot it says that generation 1 is good and there is nothing to
mark.

The repair path of the install miniroot (`install or repair` → `repair`) mounts
the root. On a 1.1 disk it then offers `status`, `rollback` and `mark-bad`
through the disk's own `/sbin/kbootset`, using the store named in its
`/etc/default/bootset`.

## The upgrade install

`INSTALL_UPGRADE=yes` (with `INSTALL_LAYOUT=1.1`) installs over a disk that
already holds Amix.

### What survives

| What | 1.0 disk (no data slice) | 1.1 disk |
|---|---|---|
| the configuration set (below) | saved, put in place by the installer and checked there | the same |
| the first-boot dialog's choices kept in package files (below) | saved as states, set again on the new root and checked | the same |
| `/home` | saved with the configuration and restored into the new `/home` (into s4 when the new disk has one) | on s4: the slice is not touched; on a 1.1 disk without s4: saved like 1.0 |
| installed packages | no: the medium's set is installed again | no |
| anything else on the root | no | no |
| the boot store | re-laid: one new pristine generation | re-written: one new pristine generation |

The configuration set is every file of this list that exists on the old root (proposed for OQ-40.1):

```
etc/nodename etc/domain etc/TIMEZONE etc/TZ etc/tz.index etc/clkzone
etc/passwd etc/shadow etc/group etc/default/login
etc/inet/hosts etc/inet/rc.inet etc/inet/zen.conf etc/resolv.conf etc/netconfig
etc/rc2.d/S99zen etc/rc2.d/S99zkbootset etc/apkg.conf sbin/bcheckrc
var/adm/firstboot/firstboot.conf
etc/conf/modreg.local.d/*
```

The old `firstboot.conf` is the record of the old box's answers. It is kept as
`/var/adm/upgrade/firstboot.conf.prev`, while the new one drives this install's first boot.

The first-boot dialog's other choices live in files that packages own. Each is kept as a
state, `L11_STATE_SH` in `l11.sh`, detected on the old root at capture and recorded in the
HEADER. At the end of the install it is set again from the new system's own files, then
detected on the new root and compared:

| State | Where it lives | Set again by |
|---|---|---|
| `syslog=y\|n` | the vendor `exit` line in `/etc/init.d/syslogd` | `FB_SYSLOG=n` in the new `firstboot.conf`; the first boot edits the file, as for a fresh install |
| `a2024=true\|false` | `/usr/amiga/bin/A2024`, a link to `/usr/bin/true` or `false` | the link |
| `kmap=<map>` | `/usr/amiga/lib/kmap/default.kmap`, a link to one map | the link |
| `xcolor=X2410\|Xdmi` | `/usr/X/bin/X` (stock `amixcolorx`) | the link |
| `news=cnews\|nntp` | the `inews` flavour (stock `amixnews`) | the new system's `amixnews`, answered |

A choice whose package the medium does not install (no X, no `public`) cannot come back.
The install says so. `/etc/hosts.equiv` and root's dotfiles are not kept: users' own files
come back with `/home`, and root's are the new system's.

`etc/conf/modreg.local.d` holds the administrator's module parameters (C3-5 §1).
The restore also puts it on the new root before the store is composed, so the
pristine generation takes them.

`/sbin/bcheckrc` survives upgrades as a configuration file (P-29 class).
- A stock copy (every 1.0 disk) is saved and comes back with `kbootset retry` in it.
- An already patched copy comes back as it was.
- A copy the administrator changed comes back as it was, without the lines; the
  install says so.

Password entries keep their aging fields only if the clock can be trusted (spec 40 §7). The
install runs the new system's plausibility-gated `setclk` (1992..2037) under chroot, and
requires that no entry's last change is later than today. Otherwise every entry's aging
fields are cleared: the install says so and leaves `/var/adm/upgrade/AGING-CLEARED`. A
clock that was put back after it ran ahead would otherwise lock those accounts out.

### How

1. **Capture**, before the first write. The old root is mounted read-only
   (ufs, else s5) and saved by that system's own tools: `chroot /mnt`, `find`,
   `cpio -oc` and `du`.
   - The archive (relative names) goes to the start of the old swap slice.
   - A header `AMIXUPG1 <blocks> <sum -r> <home y|n>` goes in that slice's last block.
   - Each configuration file's `sum -r` is noted.
   - `/home` that does not fit in the swap slice (less 1 MiB) stops the install,
     unless `UPGRADE_DROP_HOME=yes`.
   - The console says what is not kept.
2. **Re-lay** a 1.0 disk to the 1.1 layout. The old swap slice must lie clear
   of the new root, swap and data slices, which is checked before the first
   write; only the new store may cover it.

   A 1.1 disk keeps its RDB: s1 is re-made and s4 kept. Its s2 is both the stash
   and the swap, so no swap is added until the restore.
3. **Install** the base set and the three packages as on a fresh disk, so an
   upgraded disk carries the same records (kbootset, loader-amix, the kernel) as a
   fresh one. `/var/apkg` and the package database are not part of the saved set:
   they describe the new install.
4. **Restore**, before the store is written:
   - the archive is read through the whole-disk node at the old slice's block,
     and must give back its `sum -r`;
   - `/home` is extracted into place;
   - the configuration goes to `/var/adm/upgrade/cfg`, and every file must
     match its noted sum.

   A mismatch stops the install unarmed. The archive stays where it was, and
   the console names its block.
5. **Put in place**, at the end of the install, after everything else is laid (S4-54):
   - every saved file comes back from the archive into its own place, with the archive's
     owners, modes and times;
   - `bcheckrc` is written with `cat`, so its `/usr/sbin` link keeps the same content;
   - each file must match its noted sum on the new root;
   - the dialog's states are set again and checked, and the aging rule is applied;
   - `FB_UPGRADED=y` goes into the new `firstboot.conf`, and `RESTORED` into
     `/var/adm/upgrade`.

   The first-boot dialog is not armed on an upgrade. One owner per file: the first boot
   skips the node name, time zone, passwords, hosts and network files (sections 1–3 and
   5–5d), and only sets the running node name from the restored `/etc/nodename`.
   `/etc/rc2.d/S17upgrade` is a guard: it reports a `cfg/` the install did not finish (no
   `RESTORED`) and applies nothing.

The unattended erase guard does not stop an upgrade; the upgrade is itself the
deliberate reinstall.
