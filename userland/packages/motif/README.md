# motif — Motif 2.3.8 for Amix

The Motif toolkit under `/opt/amix/X11R6`, beside X11R6.3:
- the libraries `libXm`, `libMrm` and `libUil` with their headers (`Xm/`, `Mrm/`, `uil/`);
- `mwm`, the Motif window manager, with `system.mwmrc`;
- `uil`, the user interface language compiler, and `xmbind` with the virtual key bindings;
- the manual pages.

    VARIANT=shared sh build/pkg/pkgbuild.sh userland/packages/motif     # the default variant
    VARIANT=static sh build/pkg/pkgbuild.sh userland/packages/motif

Package: `motif`, category `x11`, set `extra`. It depends on `x11r6.3` (its server and its
`lib/X11` tree); it builds against x11r6.3's build output (`BUILD_DEPENDS`). Built with GCC 14
(`-m68020-60 -mno-strict-align -O2`). Licence: Motif is LGPL, version 2 or any later version (each
source file's header; `COPYING` is the LGPL 2.1); `mwm`, `uil` and `xmbind` also contain X11R6.3's
libraries, under the X Consortium's licence (`LGPL-2.0-or-later AND X11`).

**Two variants.** The default is the shared one (*The shared variant* below): `libXm`, `libMrm`
and `libUil` as plain shared libraries. In the static variant (`VARIANT=static`) the libraries are
static archives and `mwm`, `uil` and `xmbind` link X11R6.3 and Motif statically.

**UFS only**, as `x11r63` is: the section-3 pages keep names longer than s5's 14 bytes.

Motif uses floating point, so it needs an FPU or the kernel's FP emulation, as X does.

## Source

`motif-2.3.8.tar.gz`, the Open Group's release from SourceForge
(`https://downloads.sourceforge.net/project/motif/Motif%202.3.8%20Source%20Code/`), sha256
`859b7236…9ebce7`. Nothing comes from any other Motif or Amix port.

## What is built, and what is not

- **Printing is on** (`--enable-printing`): `XmPrintShell` and the print setup calls, linked
  against X11R6.3's own `libXp`. There is no print server on Amix, so a print job finds no printer;
  CDE's dtcm, dtmail and dtinfo need the API at build time.
- **Off**, because X11R6.3 has none of them: Xft (anti-aliased fonts), UTF-8 (`Xutf8*` calls), PNG
  and JPEG icons. Motif reads XPM itself (its own XPM code is in libXm). Themes and the message
  catalog are off, as upstream's defaults.
- **The demos are not shipped.** Upstream installs about thirty demo programs under
  `share/Xm`; statically linked, each is 1.5–2.8 MB. The build makes some in the tree for the
  smoke test only: the 27 demo directories that need no `.uid` file at build time, plus the
  programs of hellomotif, periodic and fileview, whose `.uil` files the smoke test compiles on the box with this
  package's `uil`.

## Layout

- Libraries, headers, programs and `lib/X11` data under `/opt/amix/X11R6`, as Motif sits in the X
  tree on other systems: X's own search paths (app-defaults, `system.mwmrc`, the bindings) are
  `/opt/amix/X11R6/lib/X11`, and builds find Motif beside X with one `-I` and one `-L`.
- **Configuration files** (conffiles: an upgrade keeps an edited one and puts the new default beside
  it as `.new`): `lib/X11/system.mwmrc` and `lib/X11/bindings/xmbind.alias`.
- **Manual pages.** Sections 1, 4 and 5 (`mwm`, `uil`, `xmbind`, `mwmrc`, `Traits`, `UIL`, `WML`) are
  in `/opt/amix/man` with `whatis.d/motif`, as every package's. The 695 section-3 library pages stay
  in upstream's layout, `/opt/amix/X11R6/man/man3/<name>.3`: 535 of their names are longer than s5's
  14 bytes, the limit of the shared tree, and cutting them would make many collide
  (`XmCreateScrolledList`, `XmCreateScrolledText`, …). Read one with
  `/usr/ucb/nroff -man /opt/amix/X11R6/man/man3/XmCreateScrolledList.3 | more`. x11r63 ships no
  section-3 pages at all.
- Not shipped: libtool's `.la` files (they name the build tree).
- `doc/motif`: `COPYING`, `README`, `RELNOTES`, and X11R6.3's `LABEL` and X Consortium notice, as
  `mwm`, `uil` and `xmbind` contain X11R6.3's libraries.

## The shared variant

`VARIANT=shared` builds Motif with shared libraries, version `2.3.8-<PKGREV>.s` (`SHARED_PKGREV`),
from `prototype.shared`, against X11R6.3's shared variant (its build tree `x11r6.3-shared`) and
the regex package's `libregex.so.1`. **It is the default variant.** `VARIANT=static` builds the
static one, version `2.3.8-<PKGREV>`, from `prototype`, its bytes as before. Both are the same
package (`motif`), so a machine has one variant or the other. The hooks take the variant from
`$VARIANT`.

The shared variant needs `amixrt` 1.0-5 or later (`amixrt>=1.0-5`): `libXm` takes `select` from
it, and 1.0-2 to 1.0-4 set a wrong `errno` on a failing call, so an interrupted `select` did not
return `EINTR`. It also needs the shared X11R6.3 (`x11r6.3>=6.3-15.s`) and `libregex.so.1`
(`regex>=3.8-2`; 3.8-1 was static only), so installing it over a static X11R6.3 or regex lifts
them to these in the same transaction.

- `libXm.so.4`, `libMrm.so.4` and `libUil.so.4` in `/opt/amix/X11R6/lib`, each the file its
  soname names with a `lib*.so` link beside it (libtool's `libfoo.so.4.0.4` name goes), and `mwm`,
  `uil` and `xmbind` linked against them, with `DT_RPATH /opt/amix/X11R6/lib:/opt/amix/lib`.
- **libtool's answers**: its SVR4 table does not know the host vendor `cbm`, so it would drop
  every library a library depends on; `lt_cv_deplibs_check_method=pass_all`, its answer for the
  vendors it knows, keeps them (`libXm.so.4` records `libXt`, `libX11` and the rest). Its own
  `-lc` would link the static-only parts of Amix's libc into the libraries; it is turned off
  (`lt_cv_archive_cmds_need_lc=no`), as the driver's `-shared` brings `libamixrt` for those.
- **POSIX `regcomp`** from the regex package's `libregex.so.1`: the fallback upstream takes on
  Amix, `libgen`'s `regcmp`, exists only static and non-PIC and would put text relocations into
  `libXm.so.4`.
- `DragICC.c` and `Container.c` are compiled without jump tables in this variant only: there a
  switch's bound is compared in memory and its index reloaded before the jump, a form the 68060
  gate cannot size.
- Every program links its own `_XtInherit` from X11R6.3's shared variant's `libXtInherit.a` (its
  README, *The shared variant*).
- **Gates**: `check-got-addend.py` on the PIC objects, `check-dynstr-order.py` and no `DT_TEXTREL`
  on every library and program.

## Patches

| Patch | What |
|---|---|
| `01-wml-no-wmd-in-all.patch` | `tools/wml` builds `motif.wmd` as part of `all` by running `wmldbcreate`, a program for the target. The file is a sample widget database: not installed, read by nothing in the build. `all` no longer asks for it; `make motif.wmd` still makes it. |
| `02-textf-no-wchar-h.patch` | `TextF.c` includes `<wchar.h>` for six wide-character string functions, except on the old BSDs, where it uses Xlib's `_Xwcslen`, `_Xwcscpy` and `_Xwcsncpy` and defines the other three itself. Amix has neither the header nor the functions, so the BSD path is taken whenever `HAVE_WCHAR_H` is unset, and the three Xlib functions are declared there (X11R6.3 declares them only in its internal `XlcPublic.h`). |
| `03-man-name-lines.patch` | The NAME lines of the seven pages in `/opt/amix/man` separate the name from the description with `\(em`; the whatis line needs the `-man` convention, `name \- text`. Only those lines change. |

## Build notes

- **The build's own tools are compiled for the build host from this tree**: `config/util/makestrs`
  (writes `XmStrDefs`), and `tools/wml`'s `wml` and `wmluiltok` (write the UIL compiler's tables).
  `wmluiltok` is flex output whose `main` lives in flex's library; the build gives it a one-line
  `main` instead of the host's `libfl`. The lex and yacc outputs ship in the tarball, and configure
  is told `LEX=false YACC=false`, so no host lex or yacc runs.
- **No XTHREADS.** Cross-compiling, Motif's configure cannot test whether libXt was built with
  threads and assumes it was, defining `XTHREADS` and `XUSE_MTSAFE_API`. X11R6.3 is built without
  threads, and `XTHREADS` changes Xlib's structures; the build sets `lt_cv_xthreads=no` and fails if
  `config.h` defines either.
- **-DSVR4**, as X11R6.3 itself is compiled (its `amix.cf`, `StandardDefines`); the toolchain
  leaves it undefined. Motif's SVR4 paths are Amix's: `regcmp`/`regex` from `<libgen.h>` and
  `-lgen` for the file selection box's patterns (Amix has no `regcomp`), `FD_SETSIZE` from
  `<sys/select.h>`, and `setsid()` for the commands mwm starts.
- `select` is in `libc.so.1` but no Amix header declares it: `amix-decls.h` is included in the
  compiles (not in configure, where it collides with autoconf's probes).
- Static libXt needs `-lSM -lICE` after it; they are on every link line, with `-lgen -lsocket -lnsl`.
- Configure seeds for the cross build: `setpgrp` takes no argument (SVR4), and the `/usr/X` and
  `/usr/X11R6` existence checks (they only choose a default prefix) are answered no.
- No `make -k`: each directory is made in turn and the first failure stops the build. The payload
  directories are made one by one rather than with a `SUBDIRS` override, which would reach every
  sub-make.

## Smoke test

On the emulator, a first-booted released 1.1.1 X disk, with both kernels (68060 and 68030): the
package installs with `apkg` from a local repository and `pkgchk` is clean; the box's own `uil`
compiles the three demo `.uil` files (`periodic.uid` is 120 KB); the nine demos (hellomotif,
periodic, fileview, sampler2_0, todo, colordemo, earth, autopopups, airport) each run and map their
window on the RTG server under twm, and sampler2_0 and periodic under mwm. The screens were checked
in `xwd` captures.
