# kernel/drivers/cdfs

The CD-ROM filesystem, as a module. It is built from our fork of Stefan
Reinauer's ODFileSystem, amigaux/amix-cdfs, on its `main` branch. We fix it in
our fork, the build takes it by pin, and changes go to the original repository
as pull requests when we choose to.

This directory holds only this README and `cdfs.pin`, which names the fork and
the exact commit the build uses. A pin file is one line,
`<git URL> <full commit hash>`; the build fetches that exact commit. The
driver can move in later with its history.
