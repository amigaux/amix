# cdfs

The userland half of cdfs, the read-only CD filesystem: the mount helper
`/usr/lib/fs/cdfs/mount` and the mount point `/cdrom`. The filesystem itself
is a kernel module, in the kernel-space packages `cdfs-k30` and `cdfs-k46`
(`kernel/drivers/cdfs`). Without this helper, `mount -F cdfs` fails, however
good the module is: SVR4's `mount(1M)` mounts nothing itself, it execs
`/usr/lib/fs/<fstype>/mount`.

    mount -F cdfs 0,2 /cdrom      # SCSI controller 0, target 2
    umount /cdrom

## Source

`platform/amix/mount.c` in amix-cdfs, the fork that
`kernel/drivers/cdfs/cdfs.pin` pins. The recipe builds from the `git
archive` of that commit (`FORKPIN`), so the module and the helper always come
from the same commit. The fork's `platform/amix/README.md` documents the
helper in full: the spec, the `/etc/mnttab` entry, the exit statuses and the
errno table.

## Build

GCC 14 (`TOOLCHAIN=gcc14`), as all userland is, from the fork's `amix-mount`
rule: `mount.c` alone, compiled and linked apart so the gates see the
compile, with system headers only. The file is K&R C so that the box's own
1991 `cc` can still build it as a recovery route; GCC 14 (C17) accepts K&R
definitions, and the build fails on any warning. The harness's predefines
(`unix`, `__unix__`, `__svr4__`, `AMIX`) are all it needs; it does not test
`SVR4`. Dynamically linked against the stock `libc.so.1`, like the rest of
the GCC 14 userland.

## Layout

| Path | Mode, owner | Why |
|---|---|---|
| `/usr/lib/fs/cdfs/mount` | 0755 bin bin | the helper `mount(1M)` execs for `-F cdfs` |
| `/usr/lib/fs/cdfs` | 0755 bin bin | its directory, beside stock `ufs`, `s5` and `nfs` |
| `/cdrom` | 0755 bin bin | the usual mount point |
| `/opt/amix/man/1m/mount_cdfs` | 0644 root bin | the helper's manual page (SVR4 names these `mount_<fstype>`) |
| `/opt/amix/doc/cdfs/LICENSE`, `NOTICE` | 0644 root bin | the fork's BSD 2-clause licence and its notice |

The first three keep the paths, modes and owners of the July `cdfs 0.1`
package that the install CD carried until now; a box that has that one gets
the same objects. They are outside `/opt/amix` because `mount(1M)` looks
only in `/usr/lib/fs/<fstype>`: `SYSTEM_PATHS` names `/usr/lib/fs/cdfs`, and
`/cdrom` is an empty mount-point directory. No stock package owns either
path. `/usr/lib/fs/cdfs` must hold exactly one file: there is no cdfs
`umount` helper, `umount(1M)` never runs one, and a stray file named
`umount` there makes `umount(1M)` fail with "cannot execute".

## Why its own package, with no DEPENDS

The module is kernel space and rolls per kernel line (`cdfs-k30`,
`cdfs-k46`), in make dist's kspace step; the helper is the same file for
both lines. `DEPENDS` cannot name the module package, as its catalog names
are per line; the description says it is needed. Set `base`: a
network-installed system can mount the install CD with it.

## Test

`tests/smoke.sh <card>,<unit> [<name>]` on the box, as root, with a disc in
the drive: mounts it on `/cdrom`, lists it, checks the `/etc/mnttab` entry,
that a second mount fails with status 1 (EBUSY) and that `umount` unmounts
it and removes the entry.
