# kernel/port

The 68040/68060 kernel. It is built from our fork of Antti Sokero's
amix-040-060-port, amigaux/amix-040-060-port, which carries the module kernel
chain on top of his tree. We fix the port in our fork, the build takes it by
pin, and changes go to Antti's repository as pull requests when we choose to.
The fork stays a repository of its own, so merging his upstream into it stays
ordinary git work.

This directory holds this README, `port.pin`, which names the fork and the
exact commit the build uses, and make dist's two hooks for the 68040/68060
line: `cuts/build.sh` (the `kernel-k46` step) rebuilds the fork's cut of record
that `cuts/CURRENT` names, as the fork has it at the pin, and refuses sums
other than the record's; `pkg/` rolls that cut into the `kern46m` package
(the `kspace` step, `pkg/README.md`).

A pin file is one line, `<git URL> <full commit hash>`; the build fetches that
exact commit.

`port.pin` names the fork in the amigaux organisation; the pinned commit is on
its `k46-module` branch. The port can move in later with its history.
