# x11contrib — X11R6 contrib clients for Amix

Clients from the X11R6 contrib distribution, under `/opt/amix/X11R6` beside X11R6.3:

| Client | Upstream directory | What it is |
|---|---|---|
| `xeyes` | `contrib/programs/xeyes` | a pair of eyes that follow the pointer |
| `xedit` | `contrib/programs/xedit` | the Athena-widget text editor; its resources in `lib/X11/app-defaults/Xedit` (a conffile) |

X11R6 moved these clients out of the core tree into its contrib distribution, and X11R6.3
published no contrib of its own, so they come from X11R6's `contrib-2.tar.gz`
(`https://www.x.org/archive/X11R6/contrib-2.tar.gz`, pinned by sha256 in `package.sh`), the one
of its four tarballs that holds them. More contrib clients can be added to this recipe.

    sh build/pkg/pkgbuild.sh userland/packages/x11contrib

## Build

Each client is compiled from its upstream directory by the sources and libraries its Imakefile
names, one compile and one link at a time so the gates see each compile, against the headers
and static libraries of the x11r6.3 recipe's build (`BUILD_DEPENDS`). The programs carry those
libraries (Xaw, Xmu, Xt, SM, ICE, Xext, X11), so at run time they need only an X server, the
x11r63 package's. xeyes draws with floating point and needs an FPU or the kernel's emulation.
Each compile gets the platform defines imake gives every client in the X11R6.3 tree
(`-DAMIX -Dm68k -DSVR4`), so the clients' own SVR4 branches apply (xeyes's declaration of
`hypot`, which SVR4's `<math.h>` keeps from an ANSI compile). The gate is the x11r6.3 recipe's:
no call without a declaration and no pointer/integer conversion; the K&R code's implicit-int and
missing-return warnings stay as they are.

| Patch | What |
|---|---|
| `01-protos-gcc14.patch` | Ours: the declarations gcc 14 needs: prototypes from the definitions for xeyes's transform calls (`transform.h`) and its `eyeLiner` and `eyeBall`, and `<stdlib.h>` for xeyes's `malloc`/`free` and xedit's `exit`. |

## Not built: xload

xload, from the same tarball, is not built: on Amix it cannot show the machine's load. Its SVR4
code reads the kernel's `avenrun` through nlist(3) from `/unix`, and Amix's nlist resolves that
symbol (a COMMON one in a relocatable kernel) to its alignment instead of an address, so xload
would draw whatever lies there, as uptime and w print it today. The kernel's count also leaves
out the running process. xload can come once the kernel offers a load average a program can
read.

## Licences

xeyes is the X Consortium's (X11); xedit is Digital Equipment Corporation's under its
permission notice (HPND-DEC), its manual page the X Consortium's. Each client's notice is
installed as it stands in its source, with X11R6.3's holders (`LABEL`) and its libraries' X
Consortium notice, under `/opt/amix/X11R6/doc/x11contrib`.
