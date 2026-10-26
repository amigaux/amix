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
3. installs the kernel as a kernel-space package. The static apkg 0.3 on
   `/install/l11` takes it from the medium's FILE catalog (`#ext kpkg 1`), and
   its record lands in `/var/apkg/kpkg/<name>`. `/etc/default/bootset` says
   `bootset=manual` meanwhile, so apkg's trigger only prints the commands.
4. runs the medium's box kbootset:
   - `create 67108864 boot2 --boot1 boot1 --force` lays the amix-dlm loader over
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
   - `commit` writes the pristine generation;
   - `check` is the post-write proof (status 1 means a problem was found).
   Any non-zero status stops the install before anything is armed.
5. lays the following on the target:
   - `/sbin/kbootset`;
   - `/etc/default/bootset` (C2-4 §6: `bootset=auto`, `store=`, `store-id=`, the facts);
   - `/dev/kinfo` (c 53 0, 0444; first boot gives it group sys);
   - the `updbootpart` shim, which refuses and names kbootset;
   - `/sbin/bcheckrc` with `[ -x /sbin/kbootset ] && /sbin/kbootset retry >/dev/console 2>&1`
     before each of the three `/sbin/uadmin 1 1` of its root fsck block (C2-4 v5 §7), so a
     repair reboot gives a trial its attempt back instead of spending it. The medium carries
     the patched copy, made from core's 2.1 file (md5 bff26ae7). It is written in place
     (`cat`, so `/usr/sbin/bcheckrc`, its hard link, follows), and only over the stock
     file; a changed one is left alone with a warning.

   It lays none of the 1.0 boot-chain pieces: `/stand/boot2.boot`, the framed
   chain, `/stand/unix`, the RTO1 record or the reframe tools.

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
| the configuration set (below) | saved, restored, put in place at the first boot | the same |
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
```

`/sbin/bcheckrc` survives upgrades as a configuration file (P-29 class).
- A stock copy (every 1.0 disk) is saved and comes back with `kbootset retry` in it.
- An already patched copy comes back as it was.
- A copy the administrator changed comes back as it was, without the lines; the
  install says so.

Password entries are restored as they were, aging fields included (the
clock-plausibility rule of spec 40 §7 is not implemented).

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
3. **Install** the base set as usual.
4. **Restore**, before the store is written:
   - the archive is read through the whole-disk node at the old slice's block,
     and must give back its `sum -r`;
   - `/home` is extracted into place;
   - the configuration goes to `/var/adm/upgrade/cfg`, and every file must
     match its noted sum;
   - `/etc/rc2.d/S17upgrade` is armed.

   A mismatch stops the install unarmed. The archive stays where it was, and
   the console names its block.
5. **First boot.** `/etc/rc2.d/S17upgrade` runs after `S16firstboot`. It
   re-checks the sums, copies `cfg/` over `/`, sets the
   node name and removes its `PENDING`. The old box's identity therefore wins
   over the profile's first-boot values. `bcheckrc` is written with `cat`, so its
   `/usr/sbin` link keeps the same content.

The unattended erase guard does not stop an upgrade; the upgrade is itself the
deliberate reinstall.
