# kernel/drivers/gayle-ide

The Gayle IDE driver of the A4000 and the A1200, and its Buddha flavour for
the IDE ports of the Individual Computers Buddha and Catweasel Z-II. Both are
built from our fork of Emre Bastuz's amix-gayle-ide, amigaux/amix-gayle-ide;
the 1.1 releases take it from its `release-1.1` branch. We fix it in our fork,
the build takes it by pin, and changes go to the original repository as pull
requests when we choose to.

This directory holds this README, `pkg/`, the recipes of the kernel-space
packages that make dist rolls from the driver (`pkg/gayle/`: gayle-k30 and
gayle-k46; `pkg/buddha/`: buddha-k30 and buddha-k46), and `gayle-ide.pin`,
which names the fork and the exact commit the build uses. A pin file is one
line, `<git URL> <full commit hash>`; the build fetches that exact commit. The
driver can move in later with its history.
