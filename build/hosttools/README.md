# build/hosttools

The host tools whose output Amix reads, built once from our pinned sources
and used by every recipe in place of the build host's own. A tool that
writes a file Amix reads, or that decides how Amix code is built, has to
write Amix's format and see Amix's defines and headers, never the build
host's: the host's `gencat` writes glibc's catalogue format, which Amix's
`catgets` cannot read, and the host's `imake` and `makedepend` see `linux`,
`__x86_64__` and `/usr/include`. See [docs/build-tools.md](../../docs/build-tools.md)
for the tools the build container provides instead.

| Tool | From | What it does for Amix |
|------|------|-----------------------|
| `imake` | X11R6.3 `config/imake` | built with `-DAMIX` (patches/x11r6.3/01): its cpp gets `-traditional -DAMIX -DSVR4 -Dm68k`; the wrapper runs it with `IMAKECPP=libexec/imakecpp`, the host cpp with `-undef -nostdinc`, so no define of the build host reaches the config files, nor its uname |
| `makedepend` | X11R6.3 `config/makedepend` | no built-in defines (01); the wrapper passes the target compiler's (`AMIX_MAKEDEPEND_CC`, else build/pkg's `AMIX_GCC14_CC` with `AMIX_PREDEFS`), its include directories and the sysroot's `usr/include` as `-Y`; with no target compiler it refuses |
| `bdftopcf` | X11R6.3 `programs/bdftopcf` and the bitmap part of `lib/font` | PCF in the Amix server's layout: MSB-first bytes and bits, glyphs padded to 4 bytes (02); the same bytes on every run and host (03, 04, 05) |
| `mkfontdir` | X11R6.3 `programs/mkfontdir` | `fonts.dir` for those fonts. Its rows follow `readdir`; sort them (`LC_ALL=C`, count line first) as the x11r6.3 recipe does |
| `amix-xcpp` | the host cpp | a traditional cpp with the stock `/usr/ccs/lib/cpp`'s predefines (`m68k`, `unix`) and none of the host's: what `xrdb` runs on the box, for resource files preprocessed at build time |
| `gencat` | ours, [gencat/](gencat/) | the catalogue formats of Amix's libc, byte for byte as the stock `gencat` writes them: `-m`, one self-contained file, which is what packages should ship; without `-m`, `catfile` and `catfile.m` |

```sh
sh build/hosttools/build.sh            # -> out/hosttools/bin (printed last)
sh build/hosttools/build.sh --check    # built and current?
sh build/hosttools/tests/test-hosttools
```

`build/pkg/pkgbuild.sh` builds the set when it is missing or stale, puts its
`bin/` first on a recipe's `PATH` and refuses a build that ran the build
host's copies (`build/pkg/hosttools.sh`). A recipe calls the tools by name.

## Inputs and output

- The X11R6.3 source is `x11r6.3.distfile`, the tarball the x11r6.3 recipe
  builds (the same sha256 as its `package.sh`), fetched by
  `toolchain/fetch-distfile` into `out/cache`. `patches/x11r6.3/*.patch` is
  applied in name order, each with its reason in its header. They are ours;
  03 and 04 do what the x11r6.3 recipe's patches 13 and 14 do, so the fonts
  are the package's bytes.
- The host compiler is `HOSTCC` (default `cc`), with the flags R6.3 needs on
  a 64-bit host (`-std=gnu89 -fcommon`, `-DLONG64` on the font side).
- `AMIX_HOSTTOOLS` (default `out/hosttools`) gets `bin/`, `libexec/`,
  `TOOLS` (each program's sha256) and `STAMP`, the digest of every file here,
  the distfile pin and the host compiler's version line. The same inputs do
  not build again.

What the set was checked against: from the 6.3-11 x11r6.3 package's BDF
sources, `bdftopcf` writes all 468 PCFs of misc, 75dpi and 100dpi
byte-identical to the package's, and `mkfontdir` writes its three
`fonts.dir` (sorted as above). The gencat format and its byte reference are
in [gencat/](gencat/).

## For the x11r6.3 recipe

The recipe builds imake, makestrs, makekeys, xkbcomp, bdftopcf and mkfontdir
for the build host itself today. It can take imake, bdftopcf and mkfontdir
from here (on `PATH`, or `$AMIX_HOSTTOOLS_BIN/<tool>`); makestrs, makekeys and
xkbcomp stay its own, being built from its configured tree.
