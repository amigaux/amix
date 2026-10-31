# pin.sh -- modtools: /sbin/modadmin, the module administrator for the box,
# by commit and sha256.  Sourced by build.sh.
#
# Built from amix-dlm at a pinned commit (build/pkg/common/dlm-src.sh) with its
# own Makefile target build/box/modadmin: the module core's modadmin.c
# (core/upstream with core/series applied, tools/stagecore.sh) plus
# modtools/libmod.c (the six module system calls through the stock
# syscall()), GCC 14 (gcc14-cross-amix), static, -Ttext-segment=0x80000000,
# checked by gcc14-cross-amix's check-68060-safe.py --68881 in that Makefile
# (S3-11, C2-4 v8 sec 11).  USERLAND, like kbootset: no kernel-space record.
#
# The bytes depend on the gcc14-cross-amix runtime it links (libgcc,
# libamixc99), the same runtime kbootset links (--with-cpu=m68020-60).
#
# -9 (2026-10-31, P-36 W8): no postinstall or preremove (the inittab line is
# amix-base's now), APKG_ESSENTIAL=yes; modadmin as 4442c76 builds on the
# current gcc14 pin b51ff39 (74aa6272, 39028 bytes): the latest that passes
# the gates, rebuildable from today's pin (D1), where -8 shipped -7's
# cf461e3 bytes.
#
# -8 (2026-10-31): a package-only revision for the 1.1 kernel-space set:
# -7 re-rolled without the pkginfo BASEDIR line (7cef686; stock pkgadd
# refuses one).  modadmin from the -7 datastream (MT_FROM_PKG): gcc14 is
# b51ff39 since a6b124c, whose -mno-strict-align default changes the code, so
# 4442c76 no longer rebuilds f51c98d6; the pin below still decides.
#
# -7 (2026-10-27): amix-dlm 4442c76 (reviewed as 9a7279c; modadmin source
# unchanged since 2233745) -- rebuilt on gcc14-cross-amix cf461e3 (S5-01:
# pointers in %a0 and %d0, structs through %a0), checked by dlm-src.sh
# against gcc14-pin.sh (the pins and the ABI self-check of TOOLCHAIN=gcc14).
# modadmin f51c98d6, equal to amix-dlm's own build/box/modadmin at 4442c76.
# -6's scripts (= -4's).
# -6 (2026-10-26): amix-dlm 2233745 (reviewed; core patches 0025 as
# d834597: -L prints the message buffer's words first, oldest byte first,
# text only; 0026 as 662de06: -K, root, sets prt_where's PRW_BUF so kernel
# messages stay in putbuf), modadmin 0518fb28, equal to amix-dlm's own
# build/box/modadmin.  -5's scripts (= -4's).
# -5 (2026-10-26): amix-dlm c6ad5bd (reviewed; core patch 0024 as
# 7e731f9: `modadmin -L` prints the kernel's message buffer), modadmin
# 7329e183, equal to amix-dlm's own build/box/modadmin.  -4's scripts.
# -4 (2026-10-26): the same binary as -3 (f5ce731, a206874d).  -3's
# scripts wiped /etc/inittab on Amix 2.1's 1991 Bourne shell, whose read
# keeps a buffer across `exec <file' (two passes; the second read nothing).
# Now: no exec, no IFS change; cat/dd copy the bytes (the line after an
# initdefault line 1, else first); read only in a child process; cat, ls,
# dd, expr from the miniroot required; a size check refuses before any mv.
# -3 (2026-10-26): the same binary (amix-dlm f5ce731, a206874d).  The
# postinstall/preremove pair is pure sh (C3-5 v4 sec 1.2): builtins and mv,
# cat/chgrp/rm only behind test -x.  The install miniroot, where pkgadd runs
# them with a fixed PATH, has no awk, grep or cmp (-2 stopped the install
# there with `awk: not found').  A rewrite is now a rename: 0664, group sys
# when chgrp is there.
# -2 (2026-10-26): amix-dlm f5ce731 (reviewed as b61ab31, a changelog on
# top; modadmin as core patch 0017: -B, the modadm command MOD_C_POST --
# the boot-class modules load from /etc/inittab's first sysinit entry, C3-5
# v3 sec 5).  The package gains the postinstall/preremove pair that puts
# that inittab line in and takes it out again.
# -1 (2026-10-26): amix-dlm 42df482 (reviewed; modadmin as 55722ef, core
# patch 0015: -k, -a, -p/-w).  Equal to amix-dlm's own build/box/modadmin
# (text 28756, data 1648, bss 2508).
MT_DLM_COMMIT=4442c76
MT_SHA=74aa6272224840e937e7f89451f2c75f8f16d2e5d928404f6d7cd0418e0fc37d

MT_VERSION=1.0.261027-9
MT_SOURCE_EPOCH=1793404800
