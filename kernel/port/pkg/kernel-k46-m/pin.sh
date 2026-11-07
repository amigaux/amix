# pin.sh -- kernel-k46-m: the module kernel of the 040/060 line, by sha256.
# Sourced by build.sh.
#
# Moved into amix kernel/port/pkg from amix-packages' recipes/kernel-k46-m
# at 450ba6a: the same pins and the same package text; the
# licences that came from beside the checkout now come from amix at a
# commit (K46M_AMIX_COMMIT) and from amix-paula by hash.  The cut's output
# is make dist's kernel-k46 step's (kernel/port/cuts/build.sh).
#
# Not built in the recipe.  Cut in amix-040-060-port (kabi k46.1.3, the audio
# driver with the bounded init wait, 2026-10-28;
# amix-040-060-port/build/cuts/2026-10-28-k46-paula-iw, README.md there): port branch
# k46-module at d76a7f0 (relink-040-audio.sh: amix-paula 62fdcab's three
# patchers on the stock audio.c, safeclose, initwait -- audioopen's wait for
# Paula's first interrupt is bounded, a silent Paula fails the open with EIO
# instead of spinning -- and paula, the /dev/paula exclusion; 1c58661 adds
# only the KINFO.md row for this cut), on 87b8a88's ufs mount guard and
# 88dcfc0's motherboard root record, built as -59 with the c chain (build-c.sh, post-c.sh,
# families-c.json):
#   b-new 284154a3 -> carve 300cf756 -> dd -> sd4 -> f4arms -> f6 -> audio
#   817d0edc -> rth1 -> kinfo -> dlm (amix-dlm e45b061, core b736c59 + 46
#   patches, kabi k46.1.3, mkksym -k) -> fpe -> sddevsize, W-D7 -> --fill
#   -> emit; the image stamped " 68060-261028-61"
# into
#   amix-040-060-port/build/cuts/2026-10-28-k46-paula-iw/out/c/{unix,kabi,ufs.mod}
# with SHA256SUMS at the top of that directory.  unix is the emitted ET_REL
# (the loader takes it as is; it carries its own symbol table, so no
# unix.sym, C2-3 v6 sec 1), kabi the build's sidecar for that form (rth1=2,
# no rootfs=).  Both are shipped VERBATIM; build.sh only checks them.
#
# The filesystem module (C2-3 v8 sec 1, C4-6 sec 4): ufs only on k46 (no k46
# s5 module).  out/c/ufs.mod is the port's patched ufs object
# (ufsmod/ufs-exp.k46 6636b27e, fsobj-patch.py: the mount guard) wrapped by
# amix-dlm e45b061's carve.py --build 68060-261028-61 and built with the k46
# kit of e45b061; shipped VERBATIM at /etc/conf/mod.d/ufs with a
# comment-only modreg.d file.  build.sh rebuilds it from ufsmod/c with this
# repository's kit export and requires the same bytes.  The kit
# is kabi k46.1.3; the module says kabi=k46.1.2 (the highest minor it
# imports, never below 1.2, amix-dlm C3-2 v2; K46M_FSKABI).  No module
# catalog row.
#
# A module kernel (family=generic) is its own package, never a revision of
# a static family's (C2-3 sec 1.1, amix-dlm bb088bb): kernel-k46-m, pkginst
# kern46m, version <kabi>.<yymmdd>-<nn> from the sidecar's build id, above
# the -51 of record (C2-3 v8 sec 1.1).
#
# The build-id checks stay (the stamp's leading blank, -91): the cut's core is
# the pin and contains 7b07bce (K46M_CORE_STRIP), and the core's rule over
# the shipped bytes (recipes/common/kbuildid.py: the image's buildid
# stripped == the sidecar's build= == the module's .moddata build=).
#
# -61 against -51: kabi k46.1.3 (DDI minor 3: AllocMem, FreeMem,
# displaytype, paula_busy, audio_nopen, so the paula module loads; abi
# 18c0a1c9), the patched audio driver, the module core e45b061 (0046); the
# ufs module differs in .moddata build= only (ufs-exp.k46 6636b27e as -51).
# The release notes in pkginfo ride this cut (a new version); -51 is never
# re-rolled -- one version, one set of bytes (recipes/README.md).

# -66 against -65 (2026-11-07): the port's cut 68060-261106-66 (amix-040-060-port
# cuts/68060-261106-66 at 388b93b; REV 512a99f; amix 46ef7d1): the audio driver
# answers each AUDIO_VOLUME and AUDIO_PERIOD request once, refuses a zero-length
# request (a panic in xmsgsize before), and plays each byte of a long write once
# (src/patch_audio_replies.py, after amix-paula's three patchers). The base
# (b-new), the ufs objects, abi 18c0a1c9 and kbootset-min 1.1.0.261103-37 as
# -65's; ufs.mod differs in its build id only; all eight sums equal the record's.
# -65 against -62.3 (2026-11-06): the port's cut 68060-261106-65 (amix-040-060-port
# cuts/68060-261106-65 at b936f5f; REV 53e52e4; amix 46ef7d1). The port's -63
# and -64 were not packaged here, so -65 brings theirs too: -63 the 8 MiB
# kernel arena, the large-allocation wakeups that compared bytes with pages,
# IP's lower read queue mark at 64 KiB, an access the kernel cannot serve
# (a user page below 1 GiB in vtop and the bus-error path) no longer restarting
# for ever, the kept stores at 32 records and the swap guard's limits only once
# an area exists; -64 the ufs module's rwip passing base + mapon to
# segmap_pagecreate. -65 itself: rwip's ufs_bmap call goes to ufs_bmap_hf, so a
# new block in a hole is zeroed and a rewrite of an allocated block keeps
# alloc-only (the module carved from ufs-exp-hf.k46); ddread and ddwrite fail a
# request past the slice end with ENXIO. kabi k46.1.4, abi 18c0a1c9 and
# kbootset-min 1.1.0.261103-37 as -62; all eight sums equal the record's.
# -62.3 against -62.2 (2026-11-04): the same cut and objects, re-minted so
# GCC-LIBGCC.txt names our copy of GCC's source first and GNU's as the original.
# -62.2 against -62.1 (2026-11-04): the same cut and objects, re-minted so the
# copyright file names the libgcc routines linked in, with the GPL-2 text, the
# exception and where the source is (GCC-LIBGCC.txt); DESC in plain words.
# -62.1 against -62 (2026-11-04): the same cut and objects, re-minted for the
# copyright file's wording (a corrected copy of the port's FPE notice, below).
# -62 against -61 (2026-11-03): the port's cut 68060-261103-62 (amix-040-060-port
# cuts/68060-261103-62 at d8c7548; REV 84b0623; amix 46ef7d1): the core tier
# keeps five COMMONs (inode, ifreelist, ufs_inode, inodeNINODE, ifreeh), so the
# kernel's namelist has the names sar, sadc and adb -k read, and the module
# core binds the ufs module's COMMONs to the kernel's; inode is an empty
# read-only table (no s5 on this line); kbootset-min 1.1.0.261103-37 (kbootset
# -37 writes the loaded modules' globals into /stand/unix). The base (b-new),
# kabi k46.1.4, abi 18c0a1c9 and the ufs objects as -61's; the module differs
# in its build id only.
# -61 against -60 (2026-11-03): the port's cut 68060-261103-61 (amix-040-060-port
# cuts/68060-261103-61 at 105f682; REV a483e89; amix 46c269c): a 68040 keeps
# the pending write-backs of a user fault that ends in a signal and replays
# them when setcontext restores that context, so a handler that repairs the
# mapping and returns (sh growing its heap) no longer loses the store; the
# in-kernel break grow (hgfault040.s) is not linked. kabi k46.1.4 and abi
# 18c0a1c9 as -60; the ufs objects as -60's, the module differs in its build
# id only.
# -60 against -57 (2026-11-02): the port's cut 68060-261102-60 (amix-040-060-port
# cuts/68060-261102-60 at 4c363c3; REV 422efc5; amix 46c269c). The port's -58
# and -59 were not packaged here, so -60 brings theirs too: -58 the user-trap
# diagnostics off the trap path and core patch 0052 (an interrupt chain runs
# only with a handler attached); -59 the investigation instruments out of the
# default build and the sidecar's kbootset-min= (1.1.0.261102-35). -60 itself:
# sdqueue at IPL 2 at least (the A3091's first command after boot completes),
# the A1200's Gayle port as motherboard id 2, cputype from the k46 loader's
# AXL1 record (a 68040 boots), the Ramsey read only when tracing. kabi
# k46.1.4 and abi 18c0a1c9 as -57; the ufs objects as -57's, the module
# differs in its build id only.
# -57 against -56 (2026-11-01): the port's cut 68060-261101-57 (amix-040-060-port
# cuts/68060-261101-57 at 5d6f586; REV 5a0d8cd): the idle override's own waitloc, so an
# idle tick is counted as idle; kit, abi and ufs objects as -56's (amix ac168e5).
# -56 against -55 (2026-11-01): the port's cut 68060-261101-56 (amix-040-060-port
# cuts/68060-261101-56 at 7af6b2d; REV 2e3b9d5): ITT0/DTT0 supervisor-only,
# so a user process no longer reaches physical memory below 1 GiB; no 68030
# segment tables in user address spaces; swap -a of an area too big for the
# kernel's map fails with ENOMEM; the soft data and vmem limits unlimited.
# amix 3b53a8a's core adds 0050 (a first-use load short of memory for its
# first records prints the first-use line) and 0051 (module majors are the
# booted manifest's major records, so kbootset -34 or later), built with
# gcc-cross-amix 33ebadc (DLM_PIN and the sidecar's pin=gcc-2.7.2.3-33ebadc).
# kabi k46.1.4 and abi 18c0a1c9 unchanged; the ufs module differs in its
# .moddata pin= and build= only.
#
# -55 against -53 (2026-10-31): the port's cut 68060-261031-55 (amix-040-060-port
# cuts/68060-261031-55 at 392a44e; REV eae06ae), with amix 3c3e353's module
# core, kit and family tools: core patch 0048 loads a demand-class filesystem
# module at its first mount (kabi k46.1.4, no new list name, abi 18c0a1c9 as
# before) and 0049 makes a first-use load never wait for memory, the load's
# file copy sized exactly and freed before the module's _load.  The module
# stays kabi k46.1.2, boot class, core tier; the ufs objects are -53's.  The
# kernel-k46 hook reproduces its seven sums on the host and in the build
# container.
#
# -53 against -52 (2026-10-31): the port's cut 68060-261031-53 (amix-040-060-port
# cuts/68060-261031-53 at 727cbe7; REV 2e7f715), the first made with gcc14's
# binutils 2.43.1 (toolchain/m68k-gnu-bin, one binutils for both lines) and amix
# b391504's module core and kit, whose major registry carries c 48 random
# (a8719fb).  2.43.1 makes the FPSP 040's stan.s lea and the ISP glue's jmp
# PC-relative where 2.46 kept them absolute, so the kernel's bytes move; -52
# stays the record of what was tested on metal.  make dist's kernel-k46 hook
# (kernel/port/cuts/build.sh) reproduces its seven sums on the host and in
# the build container, from the public port.  kabi k46.1.3 and abi 18c0a1c9
# unchanged, module kabi k46.1.2; the ufs objects are -52's (6636b27e,
# f49bf55e), the module differs in its build id.
#
# -52 against -61 (2026-10-31): the port's cut 68060-261031-52
# (amix-040-060-port cuts/68060-261031-52, 53ec472: cut.sh and its
# SHA256SUMS), the first from public inputs only: port k46-module fff9660,
# amix e45b061 (the module core and kit, as -61) and fce38f4 (kernel/k30
# tools and contracts: the sddevsize and W-D7 injectors, until -51 from
# amix-kerntools bd091b4; kernel/k30/LICENSE is amix-kerntools' bytes),
# amix-paula 62fdcab, gcc-cross-amix 8949028.  The port's own -51
# (68060-261030-51) was never packaged here, so -52 brings its two fixes
# too: kzero (quirk 90) and the ufs tail zeroing (quirk 91: the module is
# carved from ufs-exp-qz.k46, ufs-exp.k46 with ufs_vptrunz bound in); and
# its own, the STREAMS freeq guard (quirk 92: qdetach, strclose and stropen
# free a queue through freeq_guarded).  kabi k46.1.3 and abi 18c0a1c9
# unchanged, module kabi k46.1.2.  The port's run root was not kept, so
# the cut was reproduced with its cut.sh into K46M_SRC: all seven sums
# equal the record's.

# the cut's output: kernel/port/cuts/build.sh (make kernel-k46) writes it
# there, from the port's cuts/68060-261106-66/cut.sh (gitignored)
K46M_SRC="${K46M_SRC:-$AMIX_TOP/kernel/port/build/cuts/68060-261106-66}"
K46M_SUMS=SHA256SUMS-68060-261106-66   # under K46M_SRC, the cut's eight sums
K46M_OUT=out/c                     # the cut's outputs under K46M_SRC
K46M_CARVE=ufsmod/mod              # the ufs carve sources (R2)
K46M_DLM_COMMIT=46ef7d1     # amix-dlm, the cut's core (port/build/dlm-rev/.rev): axrel, ksymgate.py, abi/k46 (lists, reference)
K46M_CORE_STRIP=7b07bce     # amix-dlm, the first core that skips the stamp's leading blank
K46M_KIT_COMMIT=46ef7d1     # amix-dlm, the kit the module is checked and rebuilt with (445c12e or later)
K46M_KIT_PORT=512a99f       # amix-040-060-port, the k46 kit's 4 KiB headers (the cut's PORT_REV)
K46M_PORT_COMMIT=512a99f10b20a635320220d641945141a833ed2d   # K46M_KIT_PORT in full, fetched by hash
K46M_AMIX_COMMIT=46ef7d1    # amix, the cut's kernel/k30 tools: the in-amix licence
K46M_PAULA_COMMIT=62fdcabe4b5c94ec8fcbaa610655b9a0795778ec   # amix-paula, the audio patchers

K46M_CATALOG_NAME=kernel-k46-m
K46M_PKG=kern46m
K46M_BUILDID=68060-261106-66
K46M_KABI=k46.1.4
K46M_FSKABI=k46.1.2       # the .moddata kabi of ufs (the minor it imports)
K46M_VERSION=k46.1.4.261106-66

K46M_UNIX_SHA=351884635b3e8f4b737a524811f2fff9a966d02f21eabc1802cb5d5c643ba644
K46M_UNIX_SIZE=2360645
K46M_KABI_SHA=2aa56860c1908b25b30ec1b5a91aabe61611fa5a8fdfbf0aa2faf9b68deacf4e

# the filesystem module: <fs> <sha256> <size> <file under $K46M_OUT>
K46M_FSMODS="\
ufs 810ecba476629fe55c52841cc6e075e255d084812ee504aaadb28a3c1e5d5768 80261 ufs.mod"
# the port's patched ufs object the carve links (ufsmod/Makefile's EXTRA=):
# since -52 the tail-zeroed one, ufs-exp.k46 (6636b27e, as -61) with
# ufs_vptrunz bound in by the port's tools/ufs-tailzero.sh; since -65 the
# hole-fixed one, ufs-exp-qz.k46 (006f1c9c) linked with ufs_bmap_hf.o and
# rwip's ufs_bmap call retargeted by the port's tools/ufs-holefix.sh
K46M_FSEXP=ufsmod/ufs-exp-hf.k46
K46M_FSEXP_SHA=1efb27a043929f1eaefe2851a6af37d7419334b1b76a2f66a16bf31fa39a280c

# the port's licence and the third-party notices of the code linked into the
# kernel (as kernel-k46), from the cut's copy of the port tree (512a99f
# since -66, 53e52e4 in -65, 84b0623 in -62, a483e89 in -61, 422efc5 in -60, 5a0d8cd in -57, 2e3b9d5 in -56, eae06ae in -55, 2e7f715 in -53, fff9660 in -52, the same bytes as d76a7f0, 87b8a88 and 88dcfc0;
# MOTOROLA-M68060-SP.txt changed since -82's port tree)
K46M_NOTICES="\
LICENSE                                    ceec1a0761d69087a733d3b04716c29baa0c0243f2c0def26456516f73ad8ca6
THIRD_PARTY_NOTICES/MOTOROLA-M68040-FPSP.txt 5992bb2233f332643bf14ab275bfd71719e316e10a4de5f6d772a9526d28ab79
THIRD_PARTY_NOTICES/MOTOROLA-M68060-SP.txt a8fd4c6fe11aa1c3eede5f74fcb726ee09440c2decb665603408ecc6625b26f1
THIRD_PARTY_NOTICES/NETBSD-M68K-FPE.txt    dab091a6bad4311450455e7410bcfe9c3378cdc5878b66d282d2936d88d8e41b"
# The package ships this recipe's copy of that last file: three lines of the
# port's own prose reworded, every third-party notice in it the same bytes.
K46M_FPE_COPY=NETBSD-M68K-FPE.txt
K46M_FPE_COPY_SHA=0c4e04164ef71c9307a9dbcf67d75b7f82682a3fff1567a6419305ca49c6734f
# The libgcc routines linked in: which, their licence and exception, where the
# source is (the toolchain the cut names in pin=), and GCC 2.7.2.3's COPYING.
K46M_LIBGCC_COPY=GCC-LIBGCC.txt
K46M_LIBGCC_COPY_SHA=325b24e41076a218424efc0e5492df17d6c99059fe76097a14db0fd0c6dd1829
# The code linked in from sibling repositories besides the port and the
# module core (families-c.json in the cut: no z3660 pass, no zz9000/monsw;
# since -71 amix-z3660scsi is not linked and its LICENSE left this list):
#   amix-kerntools   the W-D7 support probe and the sddevsize constant
#                    (kernel-support-probe-inject.py, kernel-sddevsize-inject.py)
#   amix-paula       since -59: the three patchers of the stock audio.c
#                    (safeclose, initwait, paula; MIT)
# <name in the copyright> <sha256> <where>: amix:<path> at K46M_AMIX_COMMIT,
# paula:<path> at K46M_PAULA_COMMIT; amix-kerntools' licence is kernel/k30's,
# the same bytes
K46M_LICENCES="\
amix-kerntools/LICENSE     20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4 amix:kernel/k30/LICENSE
amix-paula/LICENSE         4e0b5700f025f487cff0c46858b1e70cdf27bf99544ddac930a6421f62319f42 paula:LICENSE"
# the module core linked in: amix-dlm's MIT and the adopted core's (kdedon)
K46M_DLM_LICENCES="\
LICENSE               20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
core/upstream/LICENSE 7c74426a1d5885c08435d597fcb07c2395accef0773001fc6fbd22b2bbf8a66d"

K46M_SOURCE_EPOCH=1794009600     # 2026-11-07 00:00 UTC
