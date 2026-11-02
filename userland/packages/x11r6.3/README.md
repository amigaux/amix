# x11r6.3 — X11R6.3 for Amix

The X Window System, release 6.3, under `/opt/amix/X11R6`:
- the `Xzz9000` server for the ZZ9000 and the Z3660 RTG (the Amiga DDX; who wrote it: below);
- the Xlib, Xt, Xaw, Xmu, Xext, SM and ICE libraries (static) with their headers;
- xinit, xdm, twm, xterm and the standard clients, with smproxy, iceauth and rstart.

It coexists with the stock X11R4/R5 in `/usr/X`.

**X needs an FPU or the kernel's FP emulation** (68LC040/68LC060: emulated and slow; on a
68LC060 the server starts in about 25 s; the 68LC040 is untested). A 68030 with a 68881/68882,
or a full 68040 or 68060, runs it at full speed.

    sh build/pkg/pkgbuild.sh userland/packages/x11r6.3

**Status: work in progress.** The whole tree (libraries, server, clients) compiles under the gcc14
strict gate: no implicit declarations, no pointer/integer conversions, `-mno-strict-align` on every
compile line. It stages, and the prototype matches the payload (1107 paths). The roll stops at the
NEEDED gate until it accepts `/usr/amiga/lib/libscreen.so`, the library's own SONAME, which every
stock user records (infra 118a966).

Package: `x11r63`, category `x11`, set `extra`. Licence: the X Consortium's (`X11`) for X11R6.3,
MIT for the Amiga DDX (patch 00, `LICENSE.ddx`) and for our patches. Built with GCC 14
(`-m68020-60 -mno-strict-align -O2`).

## Who wrote the server

`Xzz9000` is X11R6.3's device-independent server with the Amiga DDX, `hw/amix`
(`LICENSE.ddx` has the notices and says which part each covers):
- **hw/amix's input and screen framework** (`amixInit.c`, `amixIo.c`, `amixKbd.c`,
  `amixMouse.c`, `amix.h`): the 1987 Sun X server through Commodore's Amix X server, under the
  UC Regents' and Sun's notices in each file;
- **the rtg/ layer and the ZZ9000 driver**: based on Antti Sokero's
  [xrtg-amix](https://github.com/asokero/xrtg-amix) (its rtg/ layer and VA2000 driver), MIT,
  Copyright (c) 2025-2026 Antti Sokero;
- **the ZZ9000 version**, `mfbimage.c` and the A3000 + Z3660 series (CopyWindow box order, tiled
  and stippled fills, the bell, the direct 16-bit PutImage): Ignacio Soriano, MIT
  (amix-userland, patch 00);
- **the Z3660 work in patch 00** (the Z3660 modes, the raster-op and window copy fixes, fills
  and copies on the card's blitter, the monitor switch, the keyboard hand-back), from
  amix-z3660rtg, and **patches 01–28**, among them `zz9000screen.c` on cfb16: ours, MIT.

## Source

`xc-1.tar.gz` (the tree) and `xc-2.tar.gz` (fonts, docs) from
`https://www.x.org/archive/X11R6.3/tars/`, sha256 `a1324ca1…ba370b8` and `cb9e6725…6dcb8d`. The fetch
falls back to our byte-identical copies in the amigaux/amix-distfiles archive (`x11r6.3-6.3/`);
`AMIX_DISTFILES` names a local copy. `xc-3` holds only hardcopy documentation and is not used.

The server needs the stock `/usr/amiga` (the screen manager: `amiga/screen.h`, `libscreen.so`) and
`/usr/ucblib` (`libdbm.a`), from the toolchain sysroot (amix-system). `AMIX_USR_AMIGA` names another
directory that holds both; the default is the sysroot's `usr`.

## Patches

| Patch | What |
|---|---|
| `00-isoriano-amix-ddx.patch` | **isoriano's tree, used unchanged apart from comments** (Ignacio Soriano, MIT; amix-userland `components/x11/x11r6.3/overlay`): the `hw/amix` DDX with the `rtg/zz9000` framebuffer driver (`Xzz9000`) and `Xamix(1)`, and his `mfbimage.c`, which builds depth-1 images in a stack pixmap for that DDX. Its rtg/ layer and ZZ9000 driver are based on Antti Sokero's xrtg-amix (MIT). It already carries amix-z3660rtg's Z3660 work (the Z3660 modes, the card blitter, the monitor switch, the keyboard hand-back) and his soft3D and CDE fixes; who wrote which part: above. |
| `01-amix-platform.patch` | Ours: the Amix platform. `Imake.cf` selects our own `amix.cf` (the platform's facts and what the package builds); imake's cpp gets `-DAMIX -DSVR4 -Dm68k`; `servermd.h` has Amix's byte and bit order; the server Imakefile has an `Xzz9000` target; mfb uses the portable bit-field code; `Xos.h` takes the two-argument `gettimeofday`; `site.def` includes `host.def`. It follows isoriano's analysis of mfb's 68020 bit-field asm, of Xaw without `wctype.h`, and of how imake must be told about AMIX. |
| `02-implicit-int-externs.patch` | Ours: 197 extern declarations in 4 headers had no return type (`extern XClipBox(...)`). Each gets its `int`, so no client hits gcc 14's implicit-int error. |
| `03-allocator-declarations.patch` | Ours: K&R `char *malloc();`-style declarations that collide with `<stdlib.h>` become comments; xinit's own `shutdown()` becomes `xinit_shutdown()`. |
| `04`–`10-protos-*.patch` | Ours: the prototypes gcc 14 needs, by area (the libraries, the fonts, the server, xterm, twm, xdm, the small clients). Each comes from the definition the call links with (`gcc -aux-info`). A K&R definition's narrow parameters (char, short, their typedefs, float) are default-promoted in the prototype, so caller and callee agree. Each patch's header lists every promotion and every function left unprototyped, with the reason. |
| `11-mfb-fakepixmap-privates.patch` | Ours: the stack pixmaps of `00`'s `mfbimage.c` get `devPrivates` NULL rather than stack garbage (the server is built with `PIXPRIV`). |
| `12-rstart-prefix.patch` | Ours: `rstartd` goes to the package's `bin` rather than `/usr/bin`, and the `rstart` client calls it by that path on the `rsh` command line. |
| `13-bdf-defaultch.patch` | Ours: a BDF without a `DEFAULT_CHAR` property gets no default character (`NO_SUCH_CHAR`) rather than whatever the caller's font record held; `bdftopcf`'s is on its stack, so such fonts differed from build to build. |
| `14-bdftopcf-clean-fontrec.patch` | Ours: `bdftopcf` starts from a zeroed font record. The BDF reader does not set every field (`info.inkMetrics` among them), and the record is on `bdftopcf`'s stack, so a PCF gained or lost its ink bounds from one build host to another. |
| `15-zz9000-composite-clip.patch` | Ours: the ZZ9000 GC's composite clip is rebuilt from scratch on every relevant validate, by one function for windows and pixmaps (as `miComputeCompositeClip`). A pixmap's clip is bounded by the pixmap, so a large client clip can no longer make fills write past a small pixmap's buffer; a window keeps its client clip when only the window or the subwindow mode changes; the `NotClippedByChildren` region is freed; CreateGC fails cleanly without its clip region. |
| `16-pixmap-size-bounds.patch` | Ours: dix `ProcCreatePixmap` refuses a width or height over 32767 (BadAlloc), and `ZZ9000CreatePixmap` refuses the same and any byte size that would wrap an int. Before, 65535 × 32769 at depth 16 allocated 131072 bytes for a drawable claiming the full size. |
| `17-amix-keycodes-from-8.patch` | Ours: keycodes are the raw code plus 8 (8..135), the protocol's range. The keysym table's KeySymsRec claimed 1..0xE8 against a 128-row table, so 232 rows were copied and sent to clients; the modifier map moves with the keycodes and loses its unused release-code row. |
| `18-amix-switch-key-filter.patch` | Ours: the filter for the system's screen-switch keys swallows the press of Alt-Esc and Alt-F1..F10 and exactly that press's release. It decided per event, so a key released with Alt down lost its release and stayed down in X; and its range ran to Print Screen, eating the keypad's `( ) / *` with Alt. |
| `19-amix-key-repeat.patch` | Ours: key repeat comes from one place, XKB when it is on, the DDX only with `-kb`. The DDX repeat now only shortens the server's select timeout (it replaced it), computes the time normalised (an unnormalised `tv_usec` of 1000000, or `-ar1` of 1000 or more, gave an EINVAL select that spun the server), honours per-key `xset r`, and passes `-ar1`/`-ar2` on to XKB; the system's own repeat events are dropped. |
| `20-amix-bell-gated.patch` | Ours: the Paula bell is off unless the server runs with `-audiobell` (the stock audio driver's open waits for Paula at level 4 with no timeout, so a missing interrupt froze the box); the bell's process closes every descriptor before opening `/dev/audio`; one bell at a time. |
| `21-zz9000-blits-partial.patch` | Ours: blitFlush follows the driver's BLITS count: the rest is sent until every record has run, EINVAL draws that one record on the CPU, any other error draws the records not yet run and turns the blitter off. Before, an error redrew the whole batch, applying a copy that had run twice. One record per operation: the driver bands; `-blitmax` is accepted and ignored. |
| `22-zz9000-map-framebuffer.patch` | Ours: the server maps the visible framebuffer only (not the whole board with its register window), and checks GETFBINFO against the mode it set (size, depth 16, RGB565, stride, inside the board) before drawing. |
| `23-zz9000-no-soft3d.patch` | Ours: the ZZ9K-SOFT3D extension goes, and with it the probe of ioctl 18 at every start, a call our card driver leaves unassigned. |
| `24-amix-no-mitshm.patch` | Ours: MIT-SHM is not built. ShmAttach attached any segment a client named with the server's root rights, and R6.3 cannot check a client's uid against the segment. |
| `25-zz9000-screen-on-cfb16.patch` | Ours: the ZZ9000/Z3660 screen is X's own 16-bit framebuffer code, `cfb16ScreenInit`, instead of the hand-built screen, GC and drawing layer: cfb owns validation, all drawing (planemask, dashed and wide lines, pixmaps, depth-1 pixmaps through mfb), windows, colormaps and text. TrueColor only, the visual set to the card's RGB565 (cfb's depth-16 default is 6-5-5 red-low). The card's blitter comes in at four points: window-to-window CopyArea (cfb's own BitBlt with a blitter doBitBlt), CopyWindow, solid GXcopy PolyFillRect and solid PaintWindow, each flushing before it returns; a 16-bit PutImage into a window keeps the direct path. `zz9000win.c`, `zz9000cmap.c`, `zz9000pix.c` and `zz9000cursor.c` go. Xzz9000's text grows by 115 KB (cfb16's line, glyph and fill code instead of mi's generic paths). `cfb/cfbglblt8.c` joins the `-fno-jump-tables` files. |
| `26-rtg-provenance-headers.patch` | Ours: a comment at the top of each `rtg/` source, which had none, saying what the file is and where it comes from (the rtg/ layer and the ZZ9000 driver based on Antti Sokero's xrtg-amix, the ZZ9000 version Ignacio Soriano's, the Z3660 and Amix changes ours; `zz9000screen.c` our own). Comments only: the compiled server is unchanged. |
| `27-amix-fork-not-vfork.patch` | Ours: the build uses fork, not vfork (`HasVFork NO`; Imake gave YES to anything not SystemV). Amix's libc keeps `signal()`'s handlers in a table in the process's own data, which a vfork child shares with its parent: xinit's child set SIGUSR1 to SIG_IGN before exec'ing the server, and the server's "ready" SIGUSR1 then sent the parent to address 1 (Bus Error). xinit, xdmshell and xmh use fork. |
| `28-font-path-fewer-fpu.patch` | Ours: font path setup with fewer floating-point instructions, same results. Each XLFD bitmap font in `fonts.dir` has eight matrix values rounded by `xlfd_round_double` (sprintf `%.3lg`, then atof) and asks `GetClientResolutions` for 75 or 100 dpi; on a 68LC060 every FPU instruction is emulated, about 160,000 per start and per reset. `xlfd_round_double` keeps 64 results keyed on the argument's bits, and the 88 dpi test is done in integers (`<=`, as 25.4 as a double is a little under 25.4). An A4000D (68LC060) is ready in about 24 s instead of 44 s (79,259 emulated instructions instead of 160,618); the font list and font properties are byte-identical. |

Not taken from isoriano's overlay, done our own way or not needed here:
- his `amix.cf` and `amix.rules`, the shared-data `.so`/`.sa` model (this package is static);
- the Xt/Xaw shared-library guards;
- `programs/Imakefile` without twm, rstart and smproxy (all three ship here);
- twm's `lex.l` guard for Amix's own lex;
- imake's on-box cpp path;
- his on-box build and session scripts in `config/util`;
- whitespace and comment edits.

## Build notes

- **xcc.** Every compile goes through `build.sh`'s `xcc`, which force-includes `amix-xlibc.h`
  (the C library headers the 1990s sources often omit) and `amix-decls.h`. It logs each line for
  the strict gates.
- **amix.cf** (patch 01) says what Amix is and what the package builds: static libraries, MIT-SHM
  off, colours from `rgb.txt`, man sections 1/3/4/5, xdm's greeter linked in. It turns off what is
  not shipped: PEX, XIE, LBX, the print server and Xnest. **host.def** (`host.def.in`) holds only
  the cross build: the compiler and tools, `ProjectRoot` `/opt/amix/X11R6`, the library paths and
  the install script.
- **Host tools.** imake, makestrs and makekeys (`ks_tables.h`) are built for the build host.
  imake runs through `imakecpp.sh`, and config files go through a plain host `cpp -traditional`.
- **rgb.** The server's colour database reader is Amix's classic `dbm`, whose `.dir`/`.pag` format
  no build-host tool writes. So the server reads `rgb.txt` itself (`UseRgbTxt`).
- **-fno-jump-tables** for five files only (`build.sh`'s `XNOJT`): each holds a GCC 14 switch table
  that the 68060 gate's scan060-g14 cannot size, though the code bounds it:
  `lib/font/bitmap/bdfutils.c` (bdfSpecialProperty: the bound is on the index before a shift),
  `lib/Xtst/XTest.c` (send_axes) and `programs/xdm/dm.c` (WaitForChild) (a signed compare before
  the unsigned bound), `lib/font/Speedo/do_trns.c` (sp_proc_outl_data: the index is a byte's high
  nibble) and `lib/font/Type1/type1.c` (Decode: the bound is set on the only path into the block).
  Those switches compile to compare chains; nothing else changes.
- **xrdb** runs the box's `/usr/ccs/lib/cpp` (the stock SVR4 cpp; the stock xrdb names
  `/usr/public/lib/gcc-cpp`); `xrdb -cpp <path>` picks another, `-nocpp` none.
- **Installs** go through the tree's BSD-style `config/util/install.sh`, because `bsdinst.sh` calls
  an SVR4 `install`.
- **Fonts** misc, 75dpi and 100dpi are compiled and indexed by this tree's own `bdftopcf` and
  `mkfontdir`, and the XKB data's `.dir` listings come from its own `xkbcomp -lfhlpR`, all three
  built for the build host (`build.sh`'s `hostx`), never the host's X install. They are built
  from a copy of the configured tree with the host cc and `-DLONG64` (R6.3's font code otherwise
  assumes 32-bit longs). The font side keeps `-DAMIX -Dm68k`, so `servermd.h` gives the PCF
  files Amix's MSB-first layout, the server's own. The server's default font path is these three directories
  (`amix.cf`'s `DefaultFontPath`), so it starts without `-fp`. `patches/host/` applies to that copy only:
  glibc's `stdin`/`stderr` cannot initialise xkbcomp's statics.
- **xdm** links its greeter in (`SharedLibXdmGreet NO`): there are no shared libraries to
  `dlopen`.
- **X** is a hard link to `Xzz9000`. `/usr/X11R6` is an absolute symlink to `/opt/amix/X11R6`.
  `/etc/profile.d/x11r63.sh` puts `/opt/amix/X11R6/bin` last on `PATH`, behind the stock X in
  `/usr/X/bin`.
- **Man pages** go to sections 1/3/4/5 (not svr4.cf's `1x`/`3x`), then into
  `/opt/amix/man/<sect>/<name>` with `whatis.d/x11r63`. `Xzz9000(1)` is the package's own page
  (`man/Xzz9000.1`); the DDX's `Xamix` page, the R5 Xsun page with the names swapped, is not shipped.
- The XIE and PEX client libraries are not shipped: their extensions are off.
- **rstart** runs `rsh host /opt/amix/X11R6/bin/rstartd`: Amix's `/usr/bin/rsh` is the remote
  shell, and the remote `rsh` PATH does not reach the package's `bin`. The contexts' `x` and
  `x11` aliases are absolute symlinks.
- **UFS only.** rstart's `commands/ListGenericCommands` has a 19-byte name, so the roll marks the
  package UFS-only; new installs are UFS.
- **MIT-SHM** is not built. Its ShmAttach attaches whatever segment id a client names, with the
  server's rights (root), and R6.3 has no way to learn a client's uid to check the segment's
  permissions: any client, remote ones included, could read or write any shared-memory segment on
  the box through the server. Clients fall back to ordinary image requests.
