# amix-benchmark-gcc14 — the amix-bench suite built with GCC 14

The second build of [`amix-benchmark`](../amix-benchmark/README.md): the same benchmark sources
and the same `runbench.sh` driver, compiled with GCC 14 (`gcc14-cross-amix`, `-m68020-60 -mno-strict-align`)
instead of shipped as the gcc 2.7.2.3 fieldkit binaries. The two packages install side by side,
so one box can run both and compare the compilers.

    sh build/pkg/pkgbuild.sh userland/packages/amix-benchmark-gcc14        # TOOLCHAIN=gcc14 implied

| | `amix-benchmark` | `amix-benchmark-gcc14` |
|---|---|---|
| SVR4 PKG instance | `amixbench` | `amixbch14` |
| Entry command | `/opt/amix/bin/amix-bench` | `/opt/amix/bin/amix-bench-g14` |
| Kit | `/opt/amix/lib/amix-bench/` | `/opt/amix/lib/amix-bench-g14/` |
| Binaries | fieldkit, gcc 2.7.2.3, verbatim | built here, GCC 14.2.0, stripped |
| Results header | `build_cc_version=GCC: (GNU) 2.7.2.3` | `build_cc_version=GCC: (GNU) 14.2.0` |
| Built | outside amix (published 1.3) | here: `out/pkg/pkg/amixbch14-1.3-4.pkg` |

The catalog name `amix-benchmark-gcc14` is mapped from the instance by the generated
[`../conf/names.conf`](../conf/names.conf) (`amixbch14: amix-benchmark-gcc14`).

**Same experiment, other compiler.** The benchmark sources are amix-kerntools `c25e0e2`, the
commit whose `dhry.c`/`iobench.c`/`fpbench.c`/`membench.c`/`vmbench.c` match the sha256s in the
period kit's `BUILD-INFO`; the driver and field README are the kit 1.2 files (`8e17364`) the
period package ships. They are in [`../amix-benchmark/src`](../amix-benchmark/src/), with their
sha256s, and this package builds from them (`SRCPKG`). The flags differ from the period
`build-fieldkit.sh` in two places: `dhry` is compiled
`-std=gnu89 -fno-inline` (C89 source; GCC 14's `-O2` would otherwise inline `Proc_*` into the
measured loop), `fpbench` stays `-O0` with the same FP-instruction floor.

**Names.** The entry command is `amix-bench-g14`, not `amix-bench-gcc14`: the Amix root is s5
and keeps 14 bytes of a name. Inside the kit the binaries keep their names, because
`runbench.sh` finds them by those names beside itself and stays byte-identical to the period
package's driver; no file is shared between the two packages.

`whet` is not built, for the licence reason in [`../amix-benchmark/src/README.md`](../amix-benchmark/src/README.md).

## Build notes

Each benchmark is compiled (`-c`, the line in `make.log` for the strict and alignment gates) and
then linked. `dhry.c` stays exactly as Weicker published it, so GCC 14 warns twice that its
pre-ANSI `char *malloc ()` and its undeclared `strcpy` mismatch the compiler's built-ins; the
build accepts those two and nothing else, and our four sources must be warning-free. The
binaries are stripped before `BUILD-INFO` and `PROVENANCE` are written, so `PROVENANCE` lists the
shipped sha256s, and every payload file's mtime is the kit 1.2 date (1789516800).

The recipe moved to `package.sh` and hooks on 2026-10-30 without a revision: the rebuilt `1.3-4`
has the recorded one's payload (every file's sha256 and mode, `BUILD-INFO` and `PROVENANCE`
included), pkginfo and pkgmap (mtimes aside). Its catalog name is `amix-benchmark-gcc14`, as the
recipe always meant; the recorded build's catalog row said `amixbch14` because the publish root
lacked the `names.conf` line (the package was never published). `PROVENANCE` still names the
recipe as `amix-packages recipes/amix-benchmark-gcc14`, as `1.3-4` was built; the next revision
names its amix home.
