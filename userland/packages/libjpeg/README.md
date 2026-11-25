# libjpeg — the Independent JPEG Group's libjpeg 9f for Amix

The IJG's JPEG library and its programs, under `/opt/amix`:
- `libjpeg.a` and the shared `libjpeg.so.9` (with the link `libjpeg.so`), with `jpeglib.h`,
  `jconfig.h`, `jmorecfg.h` and `jerror.h`;
- `cjpeg`, `djpeg`, `jpegtran`, `rdjpgcom` and `wrjpgcom`, with their manual pages.

    sh build/pkg/pkgbuild.sh userland/packages/libjpeg

Package: `libjpeg`, category `library`, set `extra`. Licence: the IJG licence (SPDX `IJG`; the
LEGAL ISSUES section of `README`, shipped in `/opt/amix/doc/libjpeg`). Built with GCC 14
(`-m68020-60 -mno-strict-align -O2`). CDE's help viewer library (DtHelp) links it.

One package serves both CDE variants: the static one links `libjpeg.a`, the shared one
`libjpeg.so.9`.

## Source

`jpegsrc.v9f.tar.gz` from `https://www.ijg.org/files/`, sha256 `04705c11…a1f832565b`: the IJG's own
release (not libjpeg-turbo, which needs cmake and has SIMD code for other CPUs).

## Build notes

- The tarball's configure and libtool, static and shared. Automake's silent rules are off so that every
  compile line reaches the build log and its gates.
- **`transupp.c` is compiled with `-fno-jump-tables`.** It holds jpegtran's lossless transforms and
  three GCC 14 switch tables with backward entries; the 68060 gate's `scan060.py` cannot size them,
  lost step in the stripped `jpegtran` and reported 56 `movep` that are table words and code read
  out of step. The two other scanners sized the tables. Those switches become compare chains;
  every other file keeps its tables, and `cjpeg` and `djpeg` pass all three scanners as built.
- Not shipped: libtool's `libjpeg.la` (it names the build tree) and `libjpeg.pc` (Amix has no
  pkg-config).
- `jconfig.h` as configure wrote it: prototypes, `unsigned char` and `unsigned short`, `stddef.h`,
  `stdlib.h` and `locale.h`; BMP, GIF, PPM and Targa for cjpeg/djpeg.
- `doc/libjpeg`: `README` (the licence), `change.log`, `libjpeg.txt` (the programming guide) and
  `usage.txt` (the programs' guide).
