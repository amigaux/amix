# amix-benchmark — the amix-bench suite as a `.pkg`

Packages **our own** benchmark suite, `amix-bench`, into an SVR4 datastream the
Amix package system can install and serve. Not a port of an upstream tool — the
sources and the validated m68k binaries live in
`../amix-kerntools/tools/amix-bench` and this recipe packages them.

**Not buildable from public sources yet:** the amix-bench fieldkit this recipe
packages (pinned by sha256 in `pin.sh`) is not in the public `amix-kerntools`
yet. The published `amixbench-1.3.pkg` on pkg.amigaux.org is the way to get it.

| | |
|---|---|
| Catalog / apkg name | **`amix-benchmark`** |
| SVR4 PKG instance (`pkginst`) | **`amixbench`** (9 chars — the ≤9 limit; `amix-benchmark` is 14) |
| Version | **1.3** (package version; fieldkit stays 1.2 — see "Version" below) |
| Entry command | `/opt/amix/bin/amix-bench` |
| Category | `utility` (closed cats.conf vocabulary; no `benchmark` group exists) |
| Deps | **none** (libc/`core` only; `core` is never a declared dep) |
| Datastream | `build/pkg/amixbench-1.3.pkg` |

## What it installs

```
/opt/amix/bin/amix-bench                      entry command (wrapper -> runbench.sh)
/opt/amix/lib/amix-bench/runbench.sh          the matrix driver (authority on what runs)
/opt/amix/lib/amix-bench/{dhry,iobench,       the five prebuilt m68k SVR4 benchmarks
                          fpbench,membench,    (no `whet` — see "No whet" below)
                          vmbench}
/opt/amix/lib/amix-bench/BUILD-INFO           the binaries' build provenance (read by runbench)
/opt/amix/lib/amix-bench/PROVENANCE           how this package was assembled (generated)
/opt/amix/man/man1/amix-bench.1               man page
/opt/amix/doc/amix-benchmark/README.txt       the fieldkit README (field usage / on-box rebuild)
```

**The kit is self-locating.** `runbench.sh` finds its binaries with `dirname $0`,
so the driver, the six binaries and `BUILD-INFO` share one directory and the PATH
command is just a wrapper that execs that `runbench.sh` by absolute path. Nothing
hard-codes a foreign binary path — the failure mode a wrapper pointing at
`/usr/amiga/bin` caused on the metal is avoided by construction.

**The entry command.**
* `amix-bench` (no args) runs the safe default suite — CPU (Dhrystone 2.1),
  floating point (an FP-only loop, Whetstone, an FP paranoia check), memory
  bandwidth and the three VM rows. **No disk row runs**: there is no default disk
  target, so `iobench`'s read/write rows are skipped (matches `sh runbench.sh`
  with no target).
* `amix-bench --help` prints usage (SVR4 `--help`, kept from the tool — no `-h`
  was invented; the driver already had both, and the C tools print their own
  `usage()` to stderr).
* `amix-bench --read-target FILE` adds the `iobench` disk **read** rows;
  `--write-target FILE --create-scratch` adds the **write** rows against a
  scratch file (never a raw device — see the man page's WRITE SAFETY).

## The toolchain / correctness decision — ship the fieldkit binaries verbatim

The six binaries are shipped **byte-for-byte from the fieldkit**, unstripped, and
are **not** rebuilt by this recipe. Why, in full:

* They **are** the amix-bench reference artifacts — the numbers in
  `../amix-kerntools/tools/amix-bench/results` were measured with this kit, so
  "the shipped binaries produce the reference numbers" is exact by construction:
  the recipe verifies each packaged file's sha256 against the fieldkit
  (`pin.sh`), and the smoke test re-checks it after packaging.
* They were built with the **same cross toolchain this repo uses** —
  `gcc-cross-amix`, `m68k-cbm-sysv4-gcc` **2.7.2.3** (`mode=cross` in the shipped
  `BUILD-INFO`, which travels in the package for attribution).
* The sources carry deliberate **gcc-2.7.2.3 codegen workarounds** — the SGS
  `fcmp` operand-order issue Whetstone's rate line leans on, and the 64-bit
  `MULS.L` constant-divisor / SGS compare-operand order notes in
  `iobench.c`/`fpbench.c`. A benchmark that miscompiles reports *wrong numbers*,
  which is worse than not shipping, and a silent codegen difference on this
  toolchain cannot be caught without running the result on a 68k. Shipping the
  validated bytes is the safe correctness choice; rebuilding is the risky one.

The task's other branch — cross-build fresh and *prove* the numbers match within
noise — is not available offline (no 68k to run them on), and it would trade a
proven-equal artifact for an unproven one. Hence: ship the fieldkit.

**Not stripped, on purpose.** Stripping would change the bytes and break the pin
that ties them to the validated artifacts. The size cost is trivial (~90 KB of
binaries; the whole `.pkg` is ~148 KB).

## Linking (the "static" question)

The task asked for static binaries "no host-path DT_NEEDED — verify with
readelf". These binaries are **dynamic, linked only against the box's own
`/usr/lib/libc.so.1`** (verified: `DT_NEEDED = [/usr/lib/libc.so.1]`, no other
NEEDED, no RPATH/RUNPATH, no leaked host strings). That satisfies the *actual*
concern: the host-path-in-DT_NEEDED trap only afflicts **SONAME-less** DSOs (the
cross wrapper bakes a host path in for those); `libc` has a proper SONAME at the
standard box path, so a libc-only dynamic link is clean. This is also how the
whole family links — every stock Amix and BATCH-1 binary uses
`interpreter /usr/lib/libc.so.1`. A truly static link is neither available (no
static libc in the sysroot) nor desirable here. All six also pass the **D4**
68LC060 gate (no `mulu.l`/`muls.l` with a `Dh:Dl` destination), so they run on
the 030 and 060 lanes alike.

## No `whet` — omitted for licence

The fieldkit carries a sixth benchmark, `whet` (Whetstone). **It is not packaged**,
and must not be re-added without a licence ruling.

Measured, not assumed: `nm` shows `whet` **statically defining** `sin`, `cos`,
`tan`, `atan`, `atan2`, `exp`, `log`, `log10`, `sqrt` and `matherr` (plus
`_sin`/`_cos`/`_reduce` and the `atanhi`/`atanlo` tables). Those objects come from
the sysroot's `/usr/ccs/lib/libm.a` — **Commodore/AT&T SVR4 object code, not
ours**. The other five binaries embed no libm at all (`fpbench` does its floating
point without pulling one), so dropping `whet` removes the entire exposure.

`pkg.amigaux.org` publishes our own builds and never stock Amix material, and
this repo's rule is blunt: nothing SVR4-derived. Shipping `whet` would have put
proprietary libm object code on a public HTTP mirror — a wider distribution than
the mailed field-kit tarball, which `amix-kerntools` excluded `whet` from for
exactly this reason (937b4b9). This package mirrors that decision.

**The cost is one row, and the driver already absorbs it.** `run_whet()` emits
`TEST fpu.whet status=skipped reason=no-whet-in-this-kit` and returns 0; the
results header's `tools=` line records which binaries the kit carried. Note the
matrix still *lists* `fpu.whet` (24 rows) — it is the binary that is absent, not
the row. Nothing fails.

The smoke test enforces this **mechanically** (step 7): it refuses any package
whose binaries `T`-define the `libm.a` signature symbols, so the exposure cannot
return silently in a later kit bump. Imported (undefined) math symbols are fine —
they resolve from the box's own libc at runtime, which is the normal dynamic link.

*(Separate, and not this package's to fix: every binary in this line — and every
already-published package in this repo — links crt startup objects
(`_start`/`_mcount`) from the same sysroot and the box's `libc.so.1`. Distribution
of the Commodore Amiga binaries was approved by Amiga Corporation on 2026-09-23.)*

## Version

The package version tracks the **kit** version (the fieldkit dist artifact and
`BUILD-INFO`), not `runbench.sh`'s `BENCH_FORMAT=1` / `TOOL_VERSION` — that is
the **results-format** version, a different axis. Both numbers are recorded in
the shipped `PROVENANCE`.

| Kit | What changed | State |
|---|---|---|
| **1.1** | first mint | metal-proven 2026-09-16; superseded, never published |
| **1.2** | `runbench.sh` stdin fix (below); **binaries unchanged, same shas** | superseded, never published |
| **1.3** | **`whet` omitted for licence** (below); fieldkit stays 1.2 | the version this recipe mints |

**1.3 = "fieldkit 1.2, whet omitted for licence".** The package version moves
because the package *contents* changed while the kit did not.

**1.2 — driver stdin fix; the default suite completes on soft-FPU metal.** The
first metal baseline is **cpu.dhry ≈ 70k dhrystones/s = 39.8 DMIPS on the real
68LC060 A4000D @ 80 MHz**. The emulated numbers under
`../amix-kerntools/tools/amix-bench/results` are **not** comparable with metal
figures — see that tree's `VALIDATION.md`.

## Build

```
sh build/pkg/pkgbuild.sh userland/packages/amix-benchmark
sh userland/packages/amix-benchmark/tests/smoke.sh    # offline structural + driver smoke
```

The build fetches nothing over the network — it verifies a pinned copy of the
sibling fieldkit and packages it. **Content is reproducible**: every packaged
byte is a pure function of the pinned inputs, the 22 payload members are
mtime-normalised to a fixed epoch, and the payload checksums are identical
build-to-build (`pkgchk -d` rc 0). The one byte-level exception is the
`i pkginfo` control member's mtime: `pkgmk` writes its own processed pkginfo
into the spool and stamps it with the build wall-clock, so that single
timestamp moves across builds more than a second apart — a `pkgmk` property
shared by **every** package in this repo, and the reason the family records the
as-built `.pkg` md5 in the catalog at publish time rather than pinning it here.
(For scale: the 1.1 datastream was 147968 bytes; 1.2 moved only by the
`runbench.sh` delta, and 1.3 drops ~17 KB with `whet`.)

## Metal result (1.1, real 68LC060 A4000D @ 80 MHz, 2026-09-16)

**Packaging PASS.** Push, `pkgadd`, `pkgchk`, `amix-bench --help`, the `iobench`
read row and `pkgrm` all passed, and the installed layout was correct — so the
prototype, the `/opt/amix` layout, the self-locating driver and the shipped
binaries are all confirmed on real hardware, not just structurally.

**One runtime defect, in the driver — not in this packaging.** `amix-bench` with
no arguments stopped after `cpu.dhry` + `fpu.dhry`. Cause: `runbench.sh` drives
the matrix as `matrix_rows | while read row`, so the row list arrives on the
shell's **stdin** and the benchmark children **inherit that pipe**;
`run_fpdhry`'s `fpbench` pilot ladder — which iterates far more on the soft-FPU
metal than on the emulated reference — consumed the remaining rows and the loop
ended early. It is a host-independent shell defect that only *shows up* where FP
is slow enough to make the ladder iterate.

Note this is invisible to the offline smoke's `--help`/`--list` checks: neither
runs a benchmark child, so neither can drain the pipe. `amix-kerntools` (which
owns `tools/amix-bench`) fixed `runbench.sh` for kit **1.2** — stdin from
`/dev/null` on the benchmark calls, plus a sanity cap keeping the default suite
bounded on soft FP — with the **six binaries unchanged**. The smoke test now
asserts the shipped driver actually carries that stdin redirect (step 6), so a
kit without the fix cannot be packaged.

## Re-running the on-box test

Run this on a box or emulator guest (stock `pkgadd`, the bare-box engine):

```
# copy amixbench-1.3.pkg to the guest (ftp), then:
pkgadd -d /path/to/amixbench-1.3.pkg amixbench
pkgchk amixbench                              # expect rc 0
PATH=/opt/amix/bin:$PATH

amix-bench --help                             # usage, rc 0
amix-bench                                    # default suite: on 1.2+ it must RUN TO
                                              #   COMPLETION -- status=ok on cpu.dhry,
                                              #   fpu.dhry, fpu.paranoia,
                                              #   mem.bw and all three vm.* rows, with
                                              #   every disk.* row status=skipped and
                                              #   fpu.whet status=skipped (no whet,
                                              #   by design -- see "No whet" above).
                                              #   Stopping after fpu.dhry is the 1.1
                                              #   pipe-drain defect coming back.
# iobench, a bounded READ pattern (no writes):
dd if=/dev/zero of=/tmp/bench.dat bs=8192 count=1024   # a small scratch file
amix-bench --read-target /tmp/bench.dat --only disk.seq.read.8192 2>/dev/null || \
  amix-bench --read-target /tmp/bench.dat                # disk read rows now run
rm -f /tmp/bench.dat

pkgrm amixbench                               # clean removal; /opt/amix/... gone
```

**Comparing numbers.** Compare only against runs on the *same machine class*.
The emulated figures under `../amix-kerntools/tools/amix-bench/results` are
**not** comparable with metal figures — see that tree's `VALIDATION.md`. The
metal baseline to compare a real 68LC060 @ 80 MHz against is **cpu.dhry ≈ 70k
dhrystones/s = 39.8 DMIPS** (2026-09-16). Within a machine class the numbers
should match to noise, because every kit from 1.1 on ships the *same* binaries.
