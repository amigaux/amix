# kernel/drivers/paula

The Paula audio driver. It is built from our fork of Ignacio Soriano's
paula-amix, amigaux/amix-paula, on its `dlm-module` branch. We fix it in our
fork, the build takes it by pin, and changes go to the original repository as
pull requests when we choose to.

This directory holds this README, `pkg/`, the recipe of the kernel-space
packages paula-k30 and paula-k46 that make dist rolls from the driver, and
`paula.pin`, which names the fork and the exact commit the build uses. A pin
file is one line, `<git URL> <full commit hash>`; the build fetches that exact
commit. The driver can move in later with its history.
