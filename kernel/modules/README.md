# kernel/modules

Generic loadable kernel modules that have no hardware of their own, one
directory each. Each directory holds the module's source and its package
recipe side by side; the module ships in the kernel-space catalog.

Planned: `monsw/`, `ramdisk/` (a RAM disk) and `cdfs/` (a read-only CD
filesystem). Each module moves in with its own history; until then its
directory does not exist.
