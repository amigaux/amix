# Build tools: where each one comes from

A package build runs tools on the build host besides the cross compilers.
They come from two places, and which place depends on one question: **does
Amix read what the tool writes?**

- A tool whose output Amix reads (a message catalogue, a font, a font
  index), or that decides how Amix code is built (the Makefiles imake
  writes, the dependencies makedepend finds), must write Amix's format and
  see Amix's defines and headers. The build host's own copy writes the
  host's format and sees `linux`, `__x86_64__` and `/usr/include`. These
  tools are **built from our pinned sources** in
  [build/hosttools](../build/hosttools/README.md), and every recipe uses
  them.
- A general tool whose output is only text, or which runs only on the build
  host, is **taken from the build container**
  ([toolchain/Containerfile](../toolchain/Containerfile)) at a pinned
  version.

## From the build container

The container is Ubuntu 24.04, pinned by digest. Its packages come from one
dated snapshot of the Ubuntu archive (`SNAPSHOT` in the Containerfile), so
each package's version is fixed until that date changes. The versions as of
snapshot `20261028T000000Z`:

| Tool | Version | Used for |
|------|---------|----------|
| perl | 5.38.2 | configure scripts, generators |
| m4 | 1.4.19 | autoconf output, m4-generated sources |
| bison | 3.8.2 | parsers (`yacc` grammars) |
| flex | 2.6.4 | scanners (`lex` sources) |
| Tcl | 8.6.14 (`tcl8.6`, `tcl8.6-dev`: `tclConfig.sh`, headers, library) | CDE's DocBook chain (man pages, help volumes) |
| OpenSP `onsgmls` | 1.5.2 | CDE's DocBook chain |
| TI-RPC (`libtirpc-dev`, `libtirpc3t64`: headers in `/usr/include/tirpc`, `libtirpc`) | 1.3.4 | CDE's host ToolTalk, which runs `tt_type_comp` |
| rpcgen | rpcsvc-proto 1.4.4, **built from source** | RPC stubs and XDR routines |

bison and flex write C that is then compiled by the cross compiler. Their
output is plain C for any target, which is why the distro's copies are good
enough. Tcl and OpenSP only process documentation on the build host. CDE's
own `instant`, which turns DocBook into the help and man formats, is built
by the CDE recipe. TI-RPC is a library for a program that runs only on the
build host: CDE's recipe builds a host ToolTalk against it to run
`tt_type_comp`, whose output, `types.xdr`, is XDR and so the same bytes on
any host's byte order. These tools are installed in the container's last stage,
after the toolchains are built, so the toolchains never see them.

rpcgen is the exception in this list. Amix programs are compiled from what
it writes, so its version is ours to choose. It is built from rpcsvc-proto's
release tarball, pinned with its sha256 in `toolchain/rpcgen.distfile`, and
installed as `/opt/amix/host/bin/rpcgen`. Its output is written for glibc;
`toolchain/test-rpcgen` shows what it needs to build for Amix:

```sh
rpcgen -5 proto.x        # SVR4 TI-RPC (svc_create); plain rpcgen: socket style
$CC $AMIX_CFLAGS -Wno-unused-variable \
    -include "$AMIX_GCC14_DECLS" -include "$AMIX_GCC14_RPCGEN" -c proto_xdr.c
$CC -o server proto_svc.o proto_xdr.o server.o -lnsl     # socket style: -lsocket -lnsl
```

`hyper` does not work: Amix's libnsl has no 64-bit XDR routine.

## Built from our sources

| Tool | Source | Why the host's copy is wrong |
|------|--------|------------------------------|
| `gencat` | ours (`build/hosttools/gencat`) | glibc's catalogue format; Amix's `catgets` reads only its own. Ours writes the stock gencat's bytes. Use `gencat -m`: one self-contained file |
| `bdftopcf`, `mkfontdir` | X11R6.3 | PCFs in the host's byte and bit order and glyph padding, and build-to-build differences; ours write the Amix server's layout, the same bytes every time |
| `imake` | X11R6.3 | hands its cpp the host's defines and uname, so the config files see Linux |
| `makedepend` | X11R6.3 | the host's defines and `/usr/include`; ours takes the target compiler's defines, include directories and sysroot |
| `amix-xcpp` | the host cpp, set up as the box's | for resource files preprocessed at build time: the stock `/usr/ccs/lib/cpp`'s predefines (`m68k`, `unix`), which `xrdb` sees on the box |

`build/pkg/pkgbuild.sh` builds this set when it is missing or stale
(`build/hosttools/build.sh`, into `out/hosttools`) and puts its `bin/` first
on every recipe's `PATH`. A recipe calls these tools by name: `GENCAT=gencat`,
not `/usr/bin/gencat`. The build is refused if one of them on `PATH` is not
the shared set's, before the build or after the stage, or if its logs show
the build host's copy run by its path. A tool a recipe builds in its own
tree is allowed.

## Adding a tool

Ask whether Amix reads what it writes. If it does, the tool belongs in
`build/hosttools`: built from a pinned source, with a test that shows its
output is Amix's. Add it to the gate's list in `build/pkg/hosttools.sh`. If
Amix does not read its output, add it to the Containerfile's last stage from
the snapshot. In both cases, give it a row in this page.
