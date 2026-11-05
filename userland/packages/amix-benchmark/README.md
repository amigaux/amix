# amix-benchmark — the amix-bench suite as a package

Our own benchmark suite, built with the period toolchain (gcc 2.7.2.3, the compiler of its reference
numbers) from [`src/`](src/). [`src/README.md`](src/README.md) gives the sources' provenance and
licences. [`amix-benchmark-gcc14`](../amix-benchmark-gcc14/) builds the same sources with GCC 14 and
installs beside it.

    sh build/dist.sh recipes/amix-benchmark

| | |
|---|---|
| Catalog / apkg name | `amix-benchmark` |
| SVR4 PKG instance | `amixbench` (at most 9 bytes; the catalog name is 14) |
| Entry command | `/opt/amix/bin/amix-bench` |
| Kit | `/opt/amix/lib/amix-bench/`: `runbench.sh`, `dhry`, `iobench`, `fpbench`, `membench`, `vmbench`, `BUILD-INFO`, `PROVENANCE` |
| Page | `amix-bench(1)` |
| Docs | `/opt/amix/doc/amix-benchmark/`: `README.txt` (the kit's), `LICENSE.amix`, `NOTICE` |
| Dependencies | none; the binaries need only the box's `libc.so.1` |

`amix-bench` with no arguments runs the safe default suite: Dhrystone 2.1, the floating-point rows,
memory bandwidth and the three VM rows. A disk row runs only against a target you name
(`--read-target`, `--write-target`); there is no default disk target. `runbench.sh` is the authority
on the matrix: 24 rows. It finds the binaries beside itself, and the entry command execs it by its
absolute path.

## 1.3-3 and the published 1.3

The published 1.3 shipped the kit's binaries as they were: unstripped, with a `BUILD-INFO` naming
the build host, its compiler path and the build date, so it could not be rebuilt unchanged. 1.3-3 is
built here: stripped, reproducible, and `BUILD-INFO` names the toolchain's pin instead. The results
header carries every `BUILD-INFO` key, so a result from 1.3-3 says `build_toolchain=` and no longer
says `build_built_host=` or `build_built_date=`. The man page moved to `/opt/amix/man/1`.

**The binaries are not the published ones, and the code is.** Built from `src/` with the kit's flags
on gcc-cross-amix 33ebadc, before stripping, all five differ from the published binaries by about
90 bytes: that toolchain links a `values-X` object, as the native `cc` does, and the published kit predates
it. Disassembled and compared, the only differences are that one symbol (`_lib_version`, 4 bytes of
`.text`, nothing reads it here: no benchmark links libm), the dynamic-symbol tables that name it, and
the absolute addresses it moves by about 36 bytes. Every other instruction is the same, and `.rodata`
and `.comment` are byte-identical. So the numbers should stay comparable with the kit's; the moved
addresses could change alignment-sensitive rows by a little on a real cache, and that has not been
measured.

The flags are the kit's and should stay so: `dhry` keeps `-O2 -fno-inline-functions -DHZ=60
-Dfloat=double` (`-Dfloat=double` works around gcc 2.7.2.3; Dhrystone divides by HZ at compile time)
and `fpbench` keeps `-O0`, with a floor on its FP instructions in the build, so it computes rather
than folds. `fpbench` and the others have no `fcmp`, and the build refuses one.

**No `whet`.** The kit's sixth benchmark statically links the stock SVR4 `libm.a`, which is not ours
to ship, so it is not built, and the build refuses a binary that defines the math symbols. `fpu.whet`
reports `status=skipped reason=no-whet-in-this-kit`; it is the binary that is absent, not the row.

## The driver's stdin

`runbench.sh` reads its rows through a pipe, so a benchmark child that inherits that pipe can eat the
remaining rows: on an emulated FPU the first kit's default suite stopped after `fpu.dhry`. Kit 1.2
gives the children `/dev/null` as stdin, and the build checks the file still does.

## Test

`tests/smoke.sh [<scratch directory>]` on the box, with the package installed: `--help`, `--list`,
the default suite to its end with every row's status, then one disk write row and one read row on a
scratch file it removes. It repeats the `TEST` lines, so the numbers stay with the result.

**Comparing numbers.** Only between runs on one class of machine. The metal baseline for a real
68LC060 at 80 MHz is `cpu.dhry` about 70k dhrystones/s, 39.8 DMIPS (kit 1.1, 2026-09-16); emulated
figures are not comparable with it.
