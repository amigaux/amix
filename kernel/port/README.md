# kernel/port

The 68040/68060 kernel. It is built from a fork of Antti Sokero's
amix-040-060-port, which carries the module kernel chain on top of his tree.
The fork is kept as its own repository so that his upstream and pull requests
back to it stay ordinary git work.

This directory holds only this README and `port.pin`, which names the fork and
the exact commit the build uses.

A pin file is one line, `<git URL> <full commit hash>`; the build fetches that
exact commit.

`port.pin` names the fork in the amigaux organisation; the pinned commit is on
its `k46-module` branch. The port can move in later with its history.
