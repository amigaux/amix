# The 1.1 disk

amix-dlm `docs/spec/40-generations-and-composer.md` §2 defines it;
this repository implements it as `INSTALL_LAYOUT=1.1` (`src/installer/l11.sh`,
sourced by `install.sh`). Stage-2 work item S2-30.

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
4. clears the store's first 64 KiB, then runs the medium's box kbootset:
   - `create 67108864 boot2 --boot1 boot1` lays the amix-dlm loader;
   - `build` takes the facts: `--line`, `--bootdev`/`--rootdev` from
     `TARGET_HBA`, `--rootfs`, `--mem` from `TARGET_FASTMEM_MB`, and `--root`;
   - `commit` writes the pristine generation;
   - `check` is the post-write proof (status 1 means a problem was found).
   Any non-zero status stops the install before anything is armed.
5. lays the following on the target:
   - `/sbin/kbootset`;
   - `/etc/default/bootset` (C2-4 §6: `bootset=auto`, `store=`, `store-id=`, the facts);
   - `/dev/kinfo` (c 53 0, 0444; first boot gives it group sys).

   It lays none of the 1.0 boot-chain pieces: `/stand/boot2.boot`, the framed
   chain, `/stand/unix`, the RTO1 record or the reframe tools.

`kbootset mark-good` is not run anywhere yet. It needs the booted generation
from kinfo on the installed system (S2-10/S2-11). Until then a committed trial
boots once and falls back (try-once). The pristine generation needs no mark.
