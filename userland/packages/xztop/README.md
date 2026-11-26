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
the gates see the compile, against the headers and libraries (Xaw, Xmu, Xt,
SM, ICE, Xext, X11) of the x11r6.3 recipe's build (`BUILD_DEPENDS`), with
`-lsocket -lnsl` from the sysroot.

    sh build/pkg/pkgbuild.sh userland/packages/xztop                   # the default variant, shared
    VARIANT=static sh build/pkg/pkgbuild.sh userland/packages/xztop

Two variants, one package (`xztop`), so a machine has one or the other:

- **The shared variant (`1.1.1-3.s`, `prototype.shared`) is the default.** xztop
  is linked against X11R6.3's shared libraries from the x11r6.3 recipe's
  shared build, as X11R6.3's own clients are: `DT_RPATH /opt/amix/X11R6/lib`,
  and its own `_XtInherit` from `libXtInherit.a` (x11r6.3's README says why).
  It needs the shared X11R6.3 (`x11r6.3>=6.3-15.s`; installing or upgrading it
  over a static X11R6.3 lifts that in the same transaction) and
  `amixrt>=1.0-5`, the floor of the X stack. The build checks that it is
  dynamic, has its own `_XtInherit`, no text relocations and its library
  names first in `.dynstr`.
- **The static variant (`1.1.1-3`, `prototype`)**, `VARIANT=static`: the X
  libraries are linked in, so a re-roll of x11r6.3 is a new xztop.

## Why its own package

The driver package is kernel space and carries no X: rolled in make dist's
kspace step, before userland, it could not link X11R6.3, and the kernel set
must not change whenever X does. `DEPENDS` names x11r6.3, whose server it
draws on. The driver package cannot be named there, as its catalog names are
per kernel line; the description says it is needed.

## Licences

`/opt/amix/doc/xztop`, in both variants: the fork's `LICENSE` (MIT) and
`NOTICE`, and, for the X libraries (linked in, or loaded), X11R6.3's `LABEL` (its copyright holders) and the X
Consortium notice the libraries carry (from `xc/lib/X11/Xlib.h`).
