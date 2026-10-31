# kernel/drivers/z3660rtg

The Z3660 accelerator's RTG graphics driver. It is built from our fork of
Ignacio Soriano's zz9000-amix, amigaux/amix-z3660rtg, on its `dlm-module`
branch. We fix it in our fork, the build takes it by pin, and changes go to
the original repository as pull requests when we choose to.

This directory holds only this README and `z3660rtg.pin`, which names the fork
and the exact commit the build uses. A pin file is one line,
`<git URL> <full commit hash>`; the build fetches that exact commit. The
driver can move in later with its history.
