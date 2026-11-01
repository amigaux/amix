# xztop

`xztop` shows the Z3660/ZZ9000 board's temperatures, voltages and CPU clock
in an X window. It reads `/dev/zz9000i`, the sensors node the z3660rtg
driver package (`z3660rtg-k30` or `z3660rtg-k46`) ships; `ztop`, the same
readings on a terminal, comes with that package.

## Source

The program is in amix-z3660rtg (`x11/xztop`), the fork that
`kernel/drivers/z3660rtg/z3660rtg.pin` pins. The recipe builds from the
`git archive` of that commit (`FORKPIN`), so the driver module and the
program always come from the same commit.

## Build

GCC 14, the fork's `x11/xztop/Makefile` line with compile and link apart so
the gates see the compile. The headers and static libraries (Xaw, Xmu, Xt,
SM, ICE, Xext, X11) are the x11r6.3 recipe's, its `dest` tree
(`BUILD_DEPENDS`); with `-lsocket -lnsl` from the sysroot. The X libraries
are linked in, so a re-roll of x11r6.3 is a new xztop.

## Why its own package

The driver package is kernel space and carries no X: rolled in make dist's
kspace step, before userland, it could not link X11R6.3, and the kernel set
must not change whenever X does. `DEPENDS` names x11r6.3, whose server it
draws on. The driver package cannot be named there, as its catalog names are
per kernel line; the description says it is needed.

## Licences

`/opt/amix/doc/xztop`: the fork's `LICENSE` (MIT) and `NOTICE`, and, for the
linked X libraries, X11R6.3's `LABEL` (its copyright holders) and the X
Consortium notice the libraries carry (from `xc/lib/X11/Xlib.h`).
