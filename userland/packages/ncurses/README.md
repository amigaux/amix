# ncurses — ncurses 6.6 for Amix

The ncurses terminal library, as static libraries and headers under `/opt/amix`:
- `libncurses.a`, `libform.a`, `libmenu.a` and `libpanel.a` in `/opt/amix/lib`;
- the headers in `/opt/amix/include/ncurses`, so the stock `<curses.h>` stays the default.

It is for building programs: vim links it. Stock Amix keeps its own curses, `tic` and `tput`;
this package installs no programs and no terminfo database.

    sh build/pkg/pkgbuild.sh userland/packages/ncurses

Package: `ncurses`, category `library`, set `extra`. Licence: ncurses' X11-style licence
(`COPYING` in `/opt/amix/doc/ncurses`). Built with GCC 14 (`-m68020-60 -mno-strict-align -O2`).

## Source

ncurses 6.6, `https://ftp.gnu.org/gnu/ncurses/ncurses-6.6.tar.gz`, sha256 `355b4cbb…49ff11`.
`package.sh` fetches the byte-identical copy in the amigaux/amix-distfiles archive
(`AMIX_DISTFILES` names a local copy).

The configuration follows isoriano's amix-userland port (MIT, Ignacio Soriano): static,
narrow characters, no C++ binding, the stock terminfo directory. No source patches are needed.

## Build notes

- **Terminfo:** `--with-default-terminfo-dir=/usr/share/lib/terminfo` and
  `--disable-db-install`. The library reads the stock database, which Amix's own `tic` writes.
- **Narrow characters only** (`--disable-widec`): Amix has no wide-character support.
- **No programs** (`--without-progs`): ncurses' `tic`, `tput` and `clear` would shadow the stock
  ones on `PATH`, and its `tic` would write entries the stock curses may not read.
  `ncurses6-config` is a build-host helper and is not shipped either.
- **`ac_cv_func_tsearch=no`:** Amix's `<search.h>` declares `twalk` with a non-const callback
  (`void (*)(void *, VISIT, int)`). ncurses' `tsearch`-based `tparm` cache does not compile under
  the strict gate against it, so ncurses keeps its own list instead (`post_configure` checks).
- **`-include amix-decls.h`** declares `select`.

## Gates

All passed:
- strict, with `-mno-strict-align` on 223 of 223 compile lines;
- libacompat not linked;
- prototype == staged tree (24 paths);
- the 060 gate;
- no ll printf conversion.

`libncurses.a` and `libform.a` hold FPU instructions, none of them 040/060-only: a program linking
them needs an FPU, or the kernel's FPE on an FPU-less part.

## Tests

The library is exercised on the box through vim, which links it.
