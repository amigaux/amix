# amix-benchmark-gcc14 — the amix-bench suite built with GCC 14

The second build of [`amix-benchmark`](../amix-benchmark/README.md): the same benchmark sources
and the same `runbench.sh` driver, compiled with GCC 14 (`gcc14-cross-amix`, `-m68020-60 -mno-strict-align`)
instead of shipped as the gcc 2.7.2.3 fieldkit binaries. The two packages install side by side,
so one box can run both and compare the compilers.

    sh recipes/amix-benchmark-gcc14/build.sh        # TOOLCHAIN=gcc14 implied

| | `amix-benchmark` | `amix-benchmark-gcc14` |
|---|---|---|
| SVR4 PKG instance | `amixbench` | `amixbch14` |
| Entry command | `/opt/amix/bin/amix-bench` | `/opt/amix/bin/amix-bench-g14` |
| Kit | `/opt/amix/lib/amix-bench/` | `/opt/amix/lib/amix-bench-g14/` |
| Binaries | fieldkit, gcc 2.7.2.3, verbatim | built here, GCC 14.2.0, stripped |
| Results header | `build_cc_version=GCC: (GNU) 2.7.2.3` | `build_cc_version=GCC: (GNU) 14.2.0` |
| Datastream | `build/pkg/amixbench-1.3.pkg` | `build/gcc14/pkg/amixbch14-1.3-4.pkg` |

The catalog name `amix-benchmark-gcc14` needs a `names.conf` line in the publish root
(`amixbch14: amix-benchmark-gcc14`).

**Same experiment, other compiler.** The benchmark sources are amix-kerntools `c25e0e2`, the
commit whose `dhry.c`/`iobench.c`/`fpbench.c`/`membench.c`/`vmbench.c` match the sha256s in the
period kit's `BUILD-INFO`; the driver and field README are the kit 1.2 files (`8e17364`) the
period package ships. All are pinned by sha256 in [`pin.sh`](pin.sh). The flags and why each
differs from `build-fieldkit.sh` are in the header of [`build.sh`](build.sh): `dhry` is compiled
`-std=gnu89 -fno-inline` (C89 source; GCC 14's `-O2` would otherwise inline `Proc_*` into the
measured loop), `fpbench` stays `-O0` with the same FP-instruction floor.

**Names.** The entry command is `amix-bench-g14`, not `amix-bench-gcc14`: the Amix root is s5
and keeps 14 bytes of a name. Inside the kit the binaries keep their names, because
`runbench.sh` finds them by those names beside itself and stays byte-identical to the period
package's driver; no file is shared between the two packages.

`whet` is not built, for the licence reason in [`../amix-benchmark/pin.sh`](../amix-benchmark/pin.sh).
