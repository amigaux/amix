# pin.sh -- the amix-bench sources this recipe compiles with GCC 14, and their
# sha256 anchors.  Sourced, never executed.  fetch.sh's rule holds: one
# location + one sha256 per file, verified before anything is built.
#
# THE SOURCE IS A SIBLING REPO.  amix-bench is our own suite; its sources live
# in ../amix-kerntools/tools/amix-bench.  The analog of a pinned download is
# `git archive <commit>` of the paths below, each file then checked against its
# sha256 here.  A commit the clone does not have, or a file whose bytes differ,
# stops the build.
#
# WHICH SOURCES, AND WHY THESE.  The point of this package is a SECOND BUILD
# of the benchmark that `amix-benchmark' (PKG amixbench) ships, so the two can
# run side by side and the only variable is the compiler:
#
#   - the five benchmark sources are the ones the period binaries were built
#     from.  amix-benchmark ships the fieldkit binaries built 2026-08-28 with
#     gcc 2.7.2.3; their BUILD-INFO records dhry/iobench/fpbench/membench/
#     vmbench sha256s, and amix-kerntools c25e0e2 is the commit whose files
#     match all five.  The later membench/vmbench changes (dec931d, faa90f2:
#     the RAM ceiling and BENCH_RAM_MB checks) are in neither package.
#   - the driver (runbench.sh) and the field README are the ones
#     amix-benchmark 1.3 ships verbatim: kit 1.2, amix-kerntools 8e17364, the
#     same digests as ../amix-benchmark/pin.sh.  Same driver, same parsing,
#     same rows -- only the binaries differ.
#
# `whet' is not built, for the licence reason ../amix-benchmark/pin.sh gives
# (it links the stock SVR4 libm.a); the fpu.whet row reports skipped, as in
# the period package.

AMIX_KERNTOOLS="${AMIX_KERNTOOLS:-$AMIX_SIBLINGS/amix-kerntools}"

# 1.3 was built on gcc14-cross-amix e316f1b (never published: GCC 14 returned
# pointers in %d0 only and small structs in registers); 1.3-2 is the same
# sources on cf461e3, whose return-value ABI is AMIX's; 1.3-3 the same with
# -mno-strict-align (owner decision 2026-10-27, gcc14-env.sh AMIX_ARCH_FLAGS).
# 1.3-4: the same objects relinked on gcc14-cross-amix b51ff39 (owner Y3,
# 2026-10-29): only the runtime and the toolchain name in BUILD-INFO differ.
AMIXBENCH_G14_VERSION=1.3-4

AMIXBENCH_SRC_COMMIT=c25e0e2178f6eb1e5dc8a36fd8da6d6c1df6cf51
AMIXBENCH_KIT_COMMIT=8e17364b96a36ee03e9a87fe7fa72dcdb3679eff

# Payload mtimes are pinned to this epoch (the kit 1.2 date, as in the period
# package), so the payload members are a pure function of their contents.
AMIXBENCH_SOURCE_EPOCH=1789516800

# path-in-amix-kerntools<TAB>sha256, at AMIXBENCH_SRC_COMMIT
AMIXBENCH_SRC_PINS="\
tools/amix-bench/src/dhry.c          843e8d68719b5292203ed3ded7b48be66852af6eedbfa617b7668900a752cd18
tools/amix-bench/src/iobench.c       142fc3d464904aeaf9b82bb3ac79fea2ddfa9859719c168a162ae8ad33b7731b
tools/amix-bench/src/fpbench.c       f0b84cb24d069104204b026e0bbd867084c694cca80bcabc415b853bb078a6d3
tools/amix-bench/src/membench.c      fc7f557bebf124b970ae7a0832af27ec0169f7c72d0ea02d442519b97accf349
tools/amix-bench/src/vmbench.c       30c39aa1942d633b886c5905abd802530f0b4f67624d8e8d56ca010f82e7811f
tools/amix-bench/src/bench-compat.h  81d7d1db709cf9502737c38697f8eb3d2b22dcb6f6fc2e9ba7055d1bbfa9f78b"

# path-in-amix-kerntools<TAB>sha256, at AMIXBENCH_KIT_COMMIT (= the period
# package's runbench.sh and README-FIELD.txt pins)
AMIXBENCH_KIT_PINS="\
tools/amix-bench/fieldkit/runbench.sh      924eff3987a44277aba4f2d7e9ffb5dbe5ccd3a9da25d969d02462b451f87b1e
tools/amix-bench/fieldkit/README-FIELD.txt 960f3e9df95ea966fc6ebfda9e25f55e32e230a1ca4b154472643d0da289ddd3"
