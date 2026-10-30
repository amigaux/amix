# package.sh -- amix-benchmark-gcc14 1.3 (P-31 sec 10.9); assignments only.
# The amix-bench suite built with GCC 14 from amix-benchmark's src/.
NAME=amix-benchmark-gcc14
PKG=amixbch14
VERSION=1.3
PKGREV=5   # -5: man pages in /opt/amix/man/<sect>/<name> + whatis.d (docs/man-pages.md)
SUMMARY="amix-benchmark-gcc14 1.3-5 - the amix-bench suite built with GCC 14"
APKG_DESC="amix-bench benchmark suite built with GCC 14: run 'amix-bench-g14'. The same sources and driver as amix-benchmark (gcc 2.7.2.3), installable beside it, so the two compilers can be compared on one box; the fpu.whet row reports skipped."
DESC="The amix-bench standard benchmark matrix, built with GCC 14 (gcc14-cross-amix, -m68020-60): Dhrystone 2.1 CPU, an FP-only loop and an FP paranoia check, memory bandwidth, three VM rows and the iobench disk speedtest. The benchmark sources are the ones the amix-benchmark package's binaries were built from with gcc 2.7.2.3, and the runbench driver is the same file, so the two packages differ only in the compiler. Installs beside amix-benchmark without sharing a file: entry command /opt/amix/bin/amix-bench-g14, kit in /opt/amix/lib/amix-bench-g14. Every results header names the compiler (build_cc_version). whet (Whetstone) is not built: it would link the stock SVR4 libm, so the fpu.whet row reports status=skipped. See /opt/amix/lib/amix-bench-g14/PROVENANCE."
CATEGORY=utility
SET=extra
LICENSE="MIT AND LicenseRef-PublicDomain"
SRCPKG=amix-benchmark
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
