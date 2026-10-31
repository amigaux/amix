# x11r6.3 — X11R6.3 for Amix

The X Window System, release 6.3, under `/opt/amix/X11R6`:
- the `Xzz9000` server for the ZZ9000 and the Z3660 RTG (isoriano's Amiga DDX);
- the Xlib, Xt, Xaw, Xmu, Xext, SM and ICE libraries (static) with their headers;
- xinit, xdm, twm, xterm and the standard clients.

It coexists with the stock X11R4/R5 in `/usr/X`.

    AMIX_USR_AMIGA=<dir with amiga/ and ucblib/> sh build/pkg/pkgbuild.sh userland/packages/x11r6.3

**Status: work in progress.** The whole tree (libraries, server, clients) compiles under the gcc14
strict gate: no implicit declarations, no pointer/integer conversions, `-mno-strict-align` on all
1237 compile lines. Staging the payload is next: install, fonts, rgb, XKB data, man pages, the
`/usr/X11R6` link and the profile.d drop-in. The package does not roll yet.

Package: `x11r63`, category `x11`, set `extra`. Licence: the X Consortium's (`X11`) for X11R6.3,
MIT for isoriano's port. Built with GCC 14 (`-m68020-60 -mno-strict-align -O2`).

## Source

`xc-1.tar.gz` (the tree) and `xc-2.tar.gz` (fonts, docs) from
`https://www.x.org/archive/X11R6.3/tars/`, sha256 `a1324ca1…ba370b8` and `cb9e6725…6dcb8d`. The fetch
falls back to our byte-identical copies in the amigaux/amix-distfiles archive (`x11r6.3-6.3/`);
`AMIX_DISTFILES` names a local copy. `xc-3` holds only hardcopy documentation and is not used.

The server needs the stock `/usr/amiga` (the screen manager: `amiga/screen.h`, `libscreen.so`) and
`/usr/ucblib` (`libdbm.a`), which the sysroot names but does not yet carry. `AMIX_USR_AMIGA` points
at a directory that holds both.

## Patches

| Patch | What |
|---|---|
| `00-isoriano-amix-overlay.patch` | isoriano's AMIX port (Ignacio Soriano, MIT; amix-userland `components/x11/x11r6.3/overlay`), unchanged: `amix.cf`/`amix.rules`, the `hw/amix` DDX with the `rtg/zz9000` driver, imake and font fixes, his development scripts. |
| `01-amix-build-config.patch` | Ours: the two-argument `gettimeofday` in `Xos.h`; `site.def` includes the cross build's `host.def`. |
| `02-implicit-int-externs.patch` | Ours: 197 extern declarations in 4 headers had no return type (`extern XClipBox(...)`); they get their `int`, so no client hits gcc 14's implicit-int error. |
| `03-allocator-declarations.patch` | Ours: K&R `char *malloc();`-style declarations that collide with `<stdlib.h>` become comments; xinit's own `shutdown()` becomes `xinit_shutdown()`. |
| `04`–`10-protos-*.patch` | Ours: the prototypes gcc 14 needs, by area (the libraries, the fonts, the server, xterm, twm, xdm, the small clients). Each comes from the definition the call links with (`gcc -aux-info`). A K&R definition's narrow parameters (char, short, their typedefs, float) are default-promoted in the prototype, so caller and callee agree. Each patch's header lists every promotion and every function left unprototyped, with the reason. |

## Build notes

- **xcc.** Every compile goes through `build.sh`'s `xcc`, which force-includes `amix-xlibc.h`
  (the C library headers the 1990s sources often omit) and `amix-decls.h`. It logs each line for
  the strict gates.
- **host.def** (`host.def.in`) sets the cross compiler and tools, `ProjectRoot` `/opt/amix/X11R6`,
  static libraries, MIT-SHM on, colours from `rgb.txt`. It turns off what is not shipped: XIE,
  LBX, the print server and Xnest. PEX is already off in `amix.cf`.
- **Host tools.** imake, makestrs and makekeys (`ks_tables.h`) are built for the build host.
  imake runs through `imakecpp.sh`, and config files go through a plain host `cpp -traditional`.
- **rgb.** The server's colour database reader is Amix's classic `dbm`, whose `.dir`/`.pag` format
  no build-host tool writes. So the server reads `rgb.txt` itself (`UseRgbTxt`).
- **MIT-SHM** is built in. The 68040/68060 kernel's shared-memory fixes make it safe; on a kernel
  without them, clients must not use it.
