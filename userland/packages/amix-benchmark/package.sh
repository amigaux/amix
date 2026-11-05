# package.sh -- amix-benchmark 1.3; assignments only.
# The amix-bench suite built with the period toolchain from src/.
NAME=amix-benchmark
PKG=amixbench
VERSION=1.3
PKGREV=3   # -3: built here from src/, stripped, no build date: the published 1.3 shipped the kit's binaries as they were
SOURCE_EPOCH=1793836800   # 2026-11-05 00:00 UTC, the time stamp of this version
SUMMARY="amix-benchmark 1.3 - CPU/FP/memory/VM/disk benchmark suite"
APKG_DESC="amix-bench benchmark suite: run 'amix-bench' for the safe default (CPU/Dhrystone, floating point, memory bandwidth, VM); add --read-target for the iobench disk rows. Built with gcc 2.7.2.3, the compiler of the suite's reference numbers; the fpu.whet row reports skipped."
DESC="The amix-bench standard benchmark matrix for Amix: Dhrystone 2.1 CPU, an FP-only loop and an FP paranoia check, memory bandwidth, three VM rows (fork/context-switch/page-fault) and the iobench disk speedtest (seq/rand x read/write). Run 'amix-bench' with no arguments for the safe default suite (no disk write; there is no default disk target on purpose). Built with gcc 2.7.2.3 and linked only against the box libc; the runbench.sh driver finds the binaries beside itself. whet (Whetstone) is not built: it would link the stock SVR4 libm, so the fpu.whet row reports status=skipped. See /opt/amix/lib/amix-bench/PROVENANCE."
CATEGORY=utility
SET=extra
LICENSE="MIT AND LicenseRef-PublicDomain"
STYLE=hooks
TOOLCHAIN=period
PREFIX=/opt/amix
DEPENDS=""
BUILD_DEPENDS=""
