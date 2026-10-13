# pin.sh -- which amix-bench fieldkit files this recipe packages, and their
# sha256 anchors.  Sourced, never executed.  fetch.sh's rule holds here too:
# one location + one sha256 per file, and the pins live in the recipe.
#
# ---------------------------------------------------------------------------
# THE SOURCE IS A SIBLING REPO, NOT AN UPSTREAM URL.
#
# amix-bench is OUR OWN benchmark suite; its sources and its prebuilt m68k
# SVR4 binaries (the "fieldkit") live in ../amix-kerntools/tools/amix-bench,
# where they are authored, cross-built and validated.  There is no upstream
# tarball to fetch: the analog of a pinned download here is a pinned COPY of
# the fieldkit, verified byte-for-byte before it is staged.  So this recipe
# does not fetch over the network -- it resolves the fieldkit by relative path
# (overridable with AMIX_BENCH_FIELDKIT) and verifies every file's sha256
# before it goes into the package, exactly the "verify before use" discipline
# fetch.sh applies to a download.
#
# ---------------------------------------------------------------------------
# ★ WHY `whet` IS NOT IN THIS PACKAGE (licence).  FIVE binaries, not six.
#
# The fieldkit carries a sixth benchmark, `whet` (Whetstone).  It is NOT
# packaged, and must not be re-added without a licence ruling.
#
# Measured, not assumed: `whet` STATICALLY LINKS the stock SVR4 math library.
# `nm` shows it T-defining sin, cos, tan, atan, atan2, exp, log, log10, sqrt
# and matherr (plus _sin/_cos/_reduce and the atanhi/atanlo tables), and those
# objects come from the sysroot's /usr/ccs/lib/libm.a -- Commodore/AT&T SVR4
# object code, not ours.  The other five binaries embed NO libm at all (fpbench
# does its floating point without pulling one), so dropping `whet` removes the
# entire exposure.
#
# pkg.amigaux.org publishes OUR OWN builds and never stock Amix material, and
# this repo's rule is blunt: nothing SVR4-derived.  Shipping `whet` would have
# put proprietary libm object code on a public HTTP mirror -- a wider
# distribution than the mailed field-kit tarball, which amix-kerntools excluded
# `whet` from for exactly this reason (937b4b9).  This package mirrors that
# decision.
#
# The cost is one row, and the driver already absorbs it by design:
# `run_whet()` emits `TEST fpu.whet status=skipped reason=no-whet-in-this-kit`
# and returns 0, and the header's `tools=` line records which binaries the kit
# actually carried.  Nothing fails; one row reports skipped.
#
# tests/smoke.sh enforces this MECHANICALLY: it refuses any package whose
# binaries T-define the libm.a signature symbols, so the exposure cannot come
# back silently in a later kit bump.
#
# (Separate and NOT addressed here: every binary in this line -- and every
# already-published package in this repo -- links crt startup objects
# (_start/_mcount) from the same sysroot and the box's libc.so.1.  Distribution
# of the Commodore Amiga binaries was approved by Amiga Corporation on
# 2026-09-23.)
#
# ---------------------------------------------------------------------------
# ★ WHY THE PREBUILT BINARIES ARE SHIPPED VERBATIM, NOT RECROSS-BUILT.
#
# These five binaries ARE the amix-bench reference artifacts: the numbers in
# ../amix-kerntools/tools/amix-bench/results were measured with this kit, and
# the sources carry deliberate gcc-2.7.2.3 codegen workarounds (the SGS fcmp
# operand-order fix whetstone.c leans on, the 64-bit MULS.L constant-divisor
# avoidance and the SGS compare-operand order in iobench.c/fpbench.c).  A
# benchmark that miscompiles reports WRONG NUMBERS -- worse than not shipping
# -- and a silent codegen difference on this toolchain cannot be caught
# without running the result on a 68k.  So the package ships the exact,
# validated bytes rather than a rebuild whose equivalence we could not prove
# offline.  They were built with the SAME cross toolchain this repo uses
# (gcc-cross-amix, m68k-cbm-sysv4-gcc 2.7.2.3 -- see the fieldkit BUILD-INFO,
# shipped in the package for attribution).  Because they are shipped verbatim
# they are NOT stripped: stripping would change the bytes and break the pin
# that ties them to the validated artifacts.
#
# All five are m68k SVR4 ELF, DT_NEEDED = [/usr/lib/libc.so.1] only (the box's
# own libc, a proper SONAME at the standard path -- so the SONAME-less
# host-path DT_NEEDED trap does not apply), and pass the D4 68LC060 gate
# (no mulu.l/muls.l with a Dh:Dl destination).  build.sh re-asserts all three.
#
# ---------------------------------------------------------------------------
# PROVENANCE OF THESE PINS
#
# Computed 2026-09-16 from ../amix-kerntools/tools/amix-bench/fieldkit at
# Kit 1.2, amix-kerntools 8e17364 (2026-09-16).  runbench.sh reports
# BENCH_FORMAT=1 / TOOL_VERSION=1.0 -- the RESULTS-FORMAT version, a different
# axis from the kit version, and it deliberately did NOT move in 1.2 because the
# results format did not change.  The package version tracks the KIT.
#
# ---------------------------------------------------------------------------
# ★ WHY 1.2 EXISTS: THE PIPE-DRAIN DEFECT (metal, 2026-09-16).
#
# 1.1 was METAL-PROVEN on the real 68LC060 A4000D @ 80 MHz: push, pkgadd,
# pkgchk, --help, the iobench read row and pkgrm all PASS, layout correct.  One
# RUNTIME defect turned up, and it was in the DRIVER, not in this packaging:
# `amix-bench` with no arguments stopped after cpu.dhry + fpu.dhry, because
# runbench.sh drives the matrix as `matrix_rows | while read row` -- the row list
# arrives on the shell's STDIN and the benchmark children INHERIT that pipe, so
# fpbench's pilot ladder (which iterates far more on soft FP than on the
# emulated reference) consumed the remaining rows and the loop ended early.
#
# A host-independent shell defect that only SHOWS UP where FP is slow enough to
# make the ladder iterate -- which is exactly the machine class this suite
# exists to measure.  Fixed in kit 1.2 by amix-kerntools (8e17364): every one of
# the eight benchmark children now takes `</dev/null`, so none can reach the
# matrix pipe (cpu.dhry was already isolated by its own `echo | dhry` pipe).
# tests/smoke.sh step 6 asserts the SHIPPED driver really carries that redirect,
# so a kit without the fix cannot be packaged.
#
# ★ THE BINARIES ARE UNCHANGED in 1.2 -- same sha256, verified here against
# the 1.1 pins before the re-mint.  The defect was in the shell driver, not in
# any compiled artifact, so nothing about the "ship the validated reference
# binaries" argument above changes and the measurement story is untouched.  Only
# runbench.sh and BUILD-INFO moved (the latter records the kit's tool_version,
# 1.1 -> 1.2); README-FIELD.txt is byte-identical to 1.1, so its pin is the same
# digest it has always had.  The binaries still self-report 1.1, by design.
#
# ★ IF A BINARY PIN EVER FAILS on a kit bump, that is a STOP: the "binaries
# unchanged" premise is wrong and the measurement provenance must be re-argued.
# It is never a pin to quietly update to match a delivery.

# The fieldkit directory (override for a non-standard workspace layout).
AMIX_BENCH_FIELDKIT="${AMIX_BENCH_FIELDKIT:-$AMIX_SIBLINGS/amix-kerntools/tools/amix-bench/fieldkit}"

AMIXBENCH_VERSION=1.3

# Fixed mtime stamped onto every staged payload path before pkgmk, so the
# payload members are reproducible regardless of when they are built.  The
# fieldkit's last-change date, as an epoch: for 1.1 this was 2026-09-15
# (1789430400, amix-kerntools faa90f2).  Bump it whenever the shipped kit
# changes -- which 1.2 does.
AMIXBENCH_SOURCE_EPOCH=1789516800

# name<TAB>sha256   -- the files copied verbatim from the fieldkit.
# In the 1.1 -> 1.2 kit bump exactly TWO of these moved: runbench.sh (the fix)
# and BUILD-INFO (tool_version); the binaries and README-FIELD.txt are
# byte-identical to 1.1.  Package 1.3 keeps kit 1.2 and simply OMITS `whet`
# (licence, above), so no digest here changes between package 1.2 and 1.3.
AMIXBENCH_PINS="\
dhry            fd7c89930d814750b02550bcd9fc053adfe9c484eda575e8a1f0b789fd4bb56c
fpbench         f1807aa69f714828f5e656645981d2c8893f3d96769622f42c3a7d2167b61216
iobench         f084265ccc840e66cb7ed53cd90b4b91f5a0be48ec9e2b92708f87e63a8d24d9
membench        02ef1505937d8f2e528d59d97af15274148650d867b24ff8978abe322424ad08
vmbench         43c93cdb1d1fe3e43df4b233bb679f44307635975f9b68120b6df694388c9d6b
runbench.sh     924eff3987a44277aba4f2d7e9ffb5dbe5ccd3a9da25d969d02462b451f87b1e
BUILD-INFO      399a57c928b43199804c28f00acefa5612dc4923d8330f0a1ed75d3ac222af80
README-FIELD.txt 960f3e9df95ea966fc6ebfda9e25f55e32e230a1ca4b154472643d0da289ddd3"

# For reference, the 1.1 values the two moved pins replace (do NOT reuse --
# recorded only so a reviewer can see exactly what changed in the re-mint):
#   runbench.sh  525551ae8d2164de21e31960fa2b6383148c6b75f8b444e7d4362edcaa40c31b
#   BUILD-INFO   554f97f60ef9c1dda714f855ed6eb6249eb7c1acf0380314bcbe2a81ab51f8c3
