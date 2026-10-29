# kernel/modules

Generic loadable kernel modules that have no hardware of their own, one
directory each. Each module ships in the kernel-space catalog.

Kept here as source, with the package recipe beside the code: `monsw/` and
`ramdisk/` (a RAM disk).

Pinned fork: `cdfs/` (a read-only CD filesystem), a fork of Stefan Reinauer's
ODFileSystem. Its directory holds only a README and `cdfs/cdfs.pin`, naming
the fork and the exact commit the build uses.

A pin file is one line, `<git URL> <full commit hash>`; the build fetches that
exact commit.

Each module moves in with its own history; until then its directory does not
exist.
