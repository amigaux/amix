# pin.sh -- kernel-k30-m: the module kernel of the 030 line, by sha256.
# Sourced by build.sh.
#
# Moved into amix kernel/k30/pkg from amix-packages' recipes/kernel-k30-m at
# 450ba6a: the same pins and the same package text; the inputs
# that came from beside the checkout now come from amix at a commit
# (K30M_AMIX_COMMIT: elf2brel and the licences of the drivers' patches) and
# from the pinned forks by hash (the port's and paula's licences).
#
# Not built here.  amix-kerntools cut it (kerntools 22d3261, the k30 cut at
# DDI minor 3: amix-kerntools/build/cuts/2026-10-28-k30-paula/cut-paula.sh -- the
# cut-carve.sh recipe, --no-scsi-drivers --object-absent --no-fstypes
# --carve-fs ufs,s5, plus --kabi k30.1.3 and --audio-paula: amix-paula
# 548d258's three patchers on the stock amiga/driver/audio.c, safeclose,
# initwait (audioopen's wait for Paula's first interrupt is bounded: a
# silent Paula fails the open with EIO instead of spinning) and paula (the
# /dev/paula exclusion, paula_busy and audio_nopen), audio.c 1f43c5ff;
# --dlm-core amix-dlm e45b061 (core 0001-0046, mkksym -k: the kernel lists
# the names of its own kabi minor), the port's rth1 at 88dcfc0; build
# 68030-261028-22, KABI k30.1.3, abi 18c0a1c9) into
#   amix-kerntools/build/cuts/2026-10-28-k30-paula/cut-68030-261028-22/usr/sys/{unix,unix.brel,unix.sym,kabi,mod.d/ufs,mod.d/s5}
# with SHA256SUMS-68030-261028-22 one level above the cut (names relative
# to usr/sys; it also names the ET_REL and the patched audio.c).  unix.brel
# is the form shipped, kabi its sidecar (size=/sha256=/bss= of the brel,
# sym= of unix.sym, rth1=2, no rootfs=: a cut's root filesystem is the
# promoted module, C3-3 sec 3 v6), unix.sym the brel's symbols (C2-3 v6
# sec 2.1).  All three are shipped VERBATIM, the brel as /stand/k30/unix;
# build.sh only checks them, with the ET_REL beside them.
#
# The filesystem modules (C2-3 v8 sec 1, C4-6 sec 4): ufs and s5 carved by
# amix-dlm's carve.py from the stock fs/{ufs,s5}/exp, wrapped as core-tier
# boot modules bound to the cut's build=, built with the k30 kit (amix-dlm
# e45b061); shipped VERBATIM at /etc/conf/mod.d/{ufs,s5} with comment-only
# modreg.d files.  build.sh rebuilds both from the cut's carve/ directory
# with this repository's own kit export and requires the same bytes.
# The kit is kabi k30.1.3; a module carries the highest minor it
# imports, never below 1.2 (amix-dlm C3-2 v2), so ufs and s5 say
# kabi=k30.1.2 in .moddata (K30M_FSKABI).  No module catalog rows: they
# travel in the kernel package only.
#
# Its own package (C2-3 sec 1.1, amix-dlm bb088bb): kernel-k30-m, pkginst
# kern30m, version <kabi>.<yymmdd>-<nn> from the sidecar's build id, above
# the -20 of record (C2-3 v8 sec 1.1).  -04 to -13 stay in build/kspace/pkg;
# -14 to -16 are in build/kspace/pkg/superseded; -17 is 64d37aaa's; -20
# (kerntools 224b285, dlm dc9f6ab, kabi k30.1.2, the first carved cut) is the
# kernel of the catalogs of record 915e09f3 to b1f564f4.
#
# -22 against -20: kabi k30.1.3 (DDI minor 3: AllocMem, FreeMem,
# displaytype, paula_busy, audio_nopen, so the paula module loads), the
# patched audio driver (the /dev/paula exclusion, the bounded open), the
# module core e45b061 (0046).  The release notes in pkginfo since
# 2026-10-28 ride this cut (a new version); -20 is never re-rolled -- one
# version, one set of bytes (recipes/README.md).

# -74 against -73 (2026-11-06): the cut 68030-261106-74 (amix kernel/k30/cuts/
# 68030-261106-74), -73's recipe from amix fb39fec with hat_growsdt's shrink
# freeing the tail where it is (tools/growsdt030.py, 2 bytes in unix) and
# pagecreate kept only for writes that start at the 8 KiB window and cover it
# or reach EOF (src/as_iolock_ufs.c linked into the ufs object,
# tools/iolockufs030.py; carved from hole/ufs.exp, rwip/ufs.exp with it).
# Against -73 only the build ids, kabi's sha256= of the brel, the 2 bytes in
# unix and the ufs module differ.  kabi k30.1.4 and abi= 18c0a1c9 unchanged;
# modules kabi k30.1.2.  Core and kit amix fb39fec (the kernel's bytes as at
# 9cd652d), port 0508945, paula 1b2736d.
#
# -73 against -72 (2026-11-06): the cut 68030-261106-73 (amix kernel/k30/cuts/
# 68030-261106-73), -72's recipe from amix 38ee0a2 with ufs rwip's
# segmap_pagecreate given base + mapon (tools/rwippc030.py, 4 bytes in the
# ufs object; carved from rwip/ufs.exp, which is qz/ufs.exp with the fix).
# Against -72 only the build ids, kabi's sha256= of the brel and those 4
# bytes differ.  kabi k30.1.4 and
# abi= 18c0a1c9 unchanged; modules kabi k30.1.2.  Core and kit amix 38ee0a2
# (the kernel's bytes as at 9cd652d), port 0508945, paula 1b2736d.
#
# -72 against -71.2 (2026-11-06): the cut 68030-261106-72 (amix kernel/k30/cuts/
# 68030-261106-72), -71's recipe from amix 9cd652d: kvseg at 8 MiB (arena8m030.py),
# kmem_freepool's wake (kmemwake030.py), the swap guard's area cap, retries and
# 1 MiB kvseg reserve,
# the denied-access, tas/cas and core-dump fixes, and IP's lower read queue mark
# at 0x10000 (the port's patch_ip_lrhiwat.py at 0508945).  kabi k30.1.4 and abi=
# 18c0a1c9 unchanged; modules kabi k30.1.2; kbootset-min 1.1.0.261103-37.  The
# same sums on the host and in the build container (amix-toolchain:dist).  Core
# and kit amix 9cd652d, port 0508945, paula 1b2736d, audio.c 1f43c5ff.
#
# -71.2 against -71.1 (2026-11-04): the same cut and objects, re-minted so
# GCC-LIBGCC.txt names our copy of GCC's source first and GNU's as the original.
# -71.1 against -71 (2026-11-04): the same cut and objects, re-minted so the
# copyright file names the libgcc routines linked in, with the GPL-2 text, the
# exception and where the source is (GCC-LIBGCC.txt); DESC in plain words.
# -71 against -70 (2026-11-03): the cut 68030-261103-71 (amix kernel/k30/cuts/
# 68030-261103-71), -70's recipe from amix c0d7df1: the stock tools that read
# kernel tables through /dev/kmem and the namelist (sadc, so sar and timex -s,
# and crash) find inode, ifreelist, ifreeh, ufs_inode and inodeNINODE in the
# kernel again (core.list names them; build-cross-kernel.sh 8i links them as
# the kernel's COMMONs, carvecom.o, and the carved modules bind to them); the
# module core points inode at an empty read-only table while s5 is not loaded.
# The inputs that differ from -70: carvecom.o, the core's objects and the s5
# wrapper.  kabi k30.1.4 and abi= 18c0a1c9 unchanged; modules kabi k30.1.2;
# the sidecar's kbootset-min is 1.1.0.261103-37 (kbootset -37's namelist
# carries crash_sync and the modules' globals).  The same sums on the host and
# in the build container (amix-toolchain:dist).  Core and kit amix c0d7df1, port
# 31edbc6, paula 1b2736d, audio.c 1f43c5ff.
#
# -70 against -69 (2026-11-02): the cut 68030-261102-70 (amix kernel/k30/cuts/
# 68030-261102-70), -69's recipe from amix 406be5d: sdqueue runs the
# controller's queue function at sdspl() or above (templates/sd.c.in, raise
# only), so the raw passthrough's first command to the A3000 WD no longer
# kills the stock driver ("a3091: 0x1 0 0x0"); kinfo030.c gives "A1200 IDE"
# motherboard id 2, as "A4000 IDE", and the port at 31edbc6 gives rth1.c the
# same rule.  The link inputs that differ from -69: sd.o, kinfo.o, rth1.o.
# kabi k30.1.4 and abi= 18c0a1c9 unchanged; modules kabi k30.1.2; the sidecar
# keeps kbootset-min=1.1.0.261102-35.  The same sums on the host and in the
# build container (amix-toolchain:dist).  Core and kit amix 406be5d, port
# 31edbc6, paula 1b2736d, audio.c 1f43c5ff.
#
# -69 against -68 (2026-11-02): the cut 68030-261102-69 (amix kernel/k30/cuts/
# 68030-261102-69), -68's recipe and pins from amix 46c269c: the module core's
# patch 0052 skips the INT2 and INT6 chain walks while no handler is attached
# (int2_n, int6_n).  Only the core's dlm_intr.o differs among the link's
# inputs; ufs and s5 are -68's bytes but for the build id they are bound to.
# The sidecar gains kbootset-min=1.1.0.261102-35 (kernel/dlm/core/kbootset-min).
# kabi k30.1.4 and abi= 18c0a1c9 unchanged; modules kabi k30.1.2.  The same
# sums on the host (gca 33ebadc) and in the build container
# (amix-toolchain:dist, gca 33ebadc).  Core and kit amix 46c269c, port b0f1d86,
# paula 1b2736d, audio.c 1f43c5ff.
#
# -68 against -67 (2026-11-01): the cut 68030-261101-68 (amix kernel/k30/cuts/
# 68030-261101-68), -67's recipe from amix 3b53a8a built with gcc-cross-amix
# 33ebadc (pin= gcc-2.7.2.3-33ebadc, the core's toolchain.pin): the module
# core's patch 0051 takes a module's majors from the booted manifest's major
# records (kbootset -34 writes them; the registry has c 55 zz9ksvc), and the
# soft data and vmem limits are unlimited (the soft stack stays 16 MB).  kabi
# k30.1.4 and abi= 18c0a1c9 unchanged; modules kabi k30.1.2.  The same sums
# from the kernel-k30 hook on the host (gca 33ebadc) and in the build
# container (amix-toolchain:gca-33ebadc).  Core and kit amix 3b53a8a, port
# b0f1d86, paula 1b2736d, audio.c 1f43c5ff.
#
# -67 against -66 (2026-11-01): the cut 68030-261101-67 (amix kernel/k30/cuts/
# 68030-261101-67), -66's recipe from amix e155eb3: the swapadd guard (swap -a
# of an area whose anon array has no free run in kvseg fails with ENOMEM
# instead of sleeping for ever; src/swapguard030.c, tools/swapguard-retarget.py)
# and the module core's patch 0050 (a first-use load short of memory prints
# the first-use line).  kabi k30.1.4 and abi= 18c0a1c9 unchanged; modules kabi
# k30.1.2.  The same sums from the kernel-k30 hook on the host and in the
# build container.  Core and kit amix e155eb3, port b0f1d86, paula 1b2736d,
# audio.c 1f43c5ff.
#
# -66 against -65 (2026-10-31): the cut 68030-261031-66 (amix kernel/k30/cuts/
# 68030-261031-66), -65's recipe from amix 3c3e353: the module core's patch
# 0049 makes a first-use load never wait for memory (the load's file copy is
# sized exactly and freed before the load proper).  kabi k30.1.4 and abi=
# 18c0a1c9 unchanged; modules kabi k30.1.2.  The same sums from the kernel-k30
# hook on the host and in the build container.  Core and kit amix 3c3e353,
# port b0f1d86, paula 1b2736d, audio.c 1f43c5ff.
#
# -65 against -64 (2026-10-31): the cut 68030-261031-65 (amix kernel/k30/cuts/
# 68030-261031-65), -64's recipe from amix 74405ce: the module core's patch
# 0048 loads a filesystem module at its first mount, and the kernel claims kabi
# k30.1.4 (no new list name: abi= 18c0a1c9 as before); the modules stay
# kabi k30.1.2, boot class, core tier.  The same sums from make dist's
# kernel-k30 hook on the host and in the build container.  Core and kit amix
# 74405ce, port b0f1d86 and paula 1b2736d (the files the cut reads are -64's
# bytes but for comments), audio.c 1f43c5ff; ufs carved from the same qz/ufs.exp.
#
# -64 against -63 (2026-10-31): the cut 68030-261031-64 (amix
# kernel/k30/cuts/68030-261031-64), -63's recipe from amix b391504: the module
# core's major registry carries c 48 random (a8719fb), so the random module's
# char major is the kernel's own; the same fixes as -63.  The first cut made
# by make dist's kernel-k30 hook (cuts/build.sh), the same sums on the host
# and in the build container.  kabi k30.1.3 and abi 18c0a1c9 unchanged,
# module kabi k30.1.2; core and kit amix b391504, port 0d37eb1 and paula
# 1b2736d at their pins (the files the cut reads are -63's bytes), audio.c
# 1f43c5ff; ufs carved from the same qz/ufs.exp (c480330a).
#
# -63 against -56 (2026-10-31): the cut 68030-261031-63
# (amix kernel/k30/cuts/68030-261031-63, a0e2ab4), from amix c1b7842's
# kernel/ with -56's recipe and fixes plus the STREAMS freeq guard (grimoire
# quirk 92: the 5 freeq calls in qdetach, strclose and stropen go through
# freeq_guarded, so a queue still scheduled is not freed under queuerun;
# prngd under prngd-ctl traffic panicked the kernel).  kabi k30.1.3 and abi
# 18c0a1c9 unchanged, module kabi k30.1.2; core and kit amix kernel/dlm
# c1b7842, port d0e8857 (kernel/port/port.pin), audio.c 1f43c5ff; ufs
# carved from the same qz/ufs.exp as -56.
#
# -56 against -22 (2026-10-30): the cut 68030-261030-56 (amix
# kernel/k30/cuts/68030-261030-56: cut.sh and its SHA256SUMS; the files in
# kernel/k30's own build/cuts), from amix 4fc583f's kernel/ with the -22
# recipe and its three build-cross-kernel.sh defaults: kzero (grimoire quirk
# 90, a big file's ftruncate shrink no longer panics), ufs tail zeroing (quirk
# 91, a shrink then a sparse regrow no longer reads old bytes back) and the
# sendsig FPU gate (quirk 74, an FPU-less 030 no longer panics at the first
# signal).  kabi k30.1.3 and abi 18c0a1c9 unchanged; the module core and kit
# are amix kernel/dlm 4fc583f; port 88dcfc0, audio.c 1f43c5ff as in -22.
# kernel/k30's tools/elf2brel.py (0026fb59) and amix-kerntools' (af80bd6c,
# pinned until the move) both make the shipped brel from the ET_REL.

# the cut's output: kernel/k30/cuts/build.sh (make kernel-k30) writes it
# there, from cuts/68030-261103-71/cut.sh (gitignored)
K30M_SRC="${K30M_SRC:-$AMIX_TOP/kernel/k30/build/cuts/68030-261106-74}"
K30M_SYSDIR=cut-68030-261106-74/usr/sys   # the cut's kernel tree under K30M_SRC
K30M_SUMS=SHA256SUMS-68030-261106-74      # under K30M_SRC; names relative to K30M_SYSDIR
K30M_CARVE=cut-68030-261106-74/carve      # the carve sources of ufs and s5 (R2)
K30M_AMIX_COMMIT=fb39fec    # amix, the cut's commit: elf2brel and the in-amix licences
K30M_ELF2BREL=kernel/k30/tools/elf2brel.py
K30M_ELF2BREL_SHA=0026fb59d5bd58468786e0af6b4178667260e77944758c91d834e8adaf4b42f5
K30M_DLM_COMMIT=fb39fec     # amix (kernel/dlm), the cut's core: axrel, ksymgate.py, abi/k30 (lists, reference)
K30M_KIT_COMMIT=fb39fec     # amix (kernel/dlm), the kit the modules are checked and rebuilt with
K30M_KIT_PORT=0508945       # amix-040-060-port, the kit's headers (k46 half of `make kit`)
K30M_PORT_COMMIT=0508945adbe18896444e4dc4ec56030c10c91314    # K30M_KIT_PORT in full, fetched by hash
K30M_PAULA_COMMIT=1b2736d9bb291af77bd1e8995d15f3e60d0627ff   # amix-paula, the audio patchers

K30M_CATALOG_NAME=kernel-k30-m
K30M_PKG=kern30m
K30M_BUILDID=68030-261106-74
K30M_KABI=k30.1.4
K30M_FSKABI=k30.1.2       # the .moddata kabi of ufs and s5 (the minor they import)
K30M_VERSION=k30.1.4.261106-74

K30M_BREL_SHA=ac431c856d0266a27e0c1edc9df7d4b12795eab644ac488db45598f47c8a0237
K30M_BREL_SIZE=1543028
K30M_BSS=350780
K30M_KABI_SHA=b798419fa1b92fd2b99f6c51161cfc60b12a478148172eafda82a346f71105b6
K30M_SYM_SHA=2268a0f3c8b76bb92a353feea929df72f8a75e3db57982f9e260d93737a7ae56
K30M_SYM_SIZE=181232
K30M_ETREL_SHA=771504ee631179de576073693a04b549ccc73a540fac4d23c977dbb10ab8008a
# the cut's patched audio driver source (SHA256SUMS names it; the three
# amix-paula patchers, 1b2736d's (548d258's bytes), on the stock audio.c)
K30M_AUDIO_SHA=1f43c5ff6558bf6583bcc3525b456bf3560e2bcf6100f5c736b0aa0221b260cc
# the sidecar's other fields, for the record (build.sh checks ident/arena/
# ksym are present once and abi= against amix-dlm's reference):
#   ident=0x000e2f70  arena=0x000e2fb0 0x00060000  ksym=0x000e163c 0x00001930
#   abi=18c0a1c98b2c9284fb10a6b6386403ed5e13193e3ec7aa4f113ff2a174285378 (= abi-k30.1.4.txt, = 1.3's)
#   root=mobo:a3000-wd,zorro:0202:01,zorro:0202:03, sdcards=4 and rth1=2
#   passed through verbatim; no rootfs= (build.sh refuses one)

# the filesystem modules: <fs> <sha256> <size>, at $K30M_SYSDIR/mod.d/<fs>
K30M_FSMODS="\
ufs ae0bffa6b314b7ef6f4d2d613be95f50013aacc61488cec2dd06733531b0224c 80143
s5  65625d3898d0bfc0e21ebe5327882e57d561c7460a81493368f3066a3ee87741 58365"
# the stock objects the carve wraps (the sysroot's, as the cut's carve/stock.sha256)
K30M_FSSTOCK="\
fs/ufs/exp a439e68f880d01450f156a0fd5886610c828d2a7cbdfdf3e8a28d93dd656273c
fs/s5/exp  1c9cb6342da321047b6861170543382eaa75457573858fe641586ff6fddaf33e"

# licences of the code linked in besides the stock kernel: as kernel-k30-u
# (pin.sh there says which repository gives what; rth1.c is the port's
# 31edbc6 here), then the module core below.  Since -22 the patched audio
# driver: the stock amiga/driver/audio.c with amix-paula's three patchers
# (MIT).  Since -14
# the A4091 driver (a4091.o) and the Gayle IDE driver (ide.o) are not
# linked: amix-gayle-ide is dropped; since -17 the static cdfs
# (libcdfskern.o) is not linked: amix-cdfs is dropped; amix-a4091 stays,
# its four stock-file patches (a2091.c, a3091.c, scsi.c, support.c) are
# still applied (NOTICE parts 1 and 2)
# a filesystem whose carve links the cut's own object instead of the stock
# exp: name, path under the cut, sha256 (-74: ufs, hole/ufs.exp: the stock
# fs/ufs/exp with pvn_vptrunc rebound to ufs_vptrunz, the quirk-91 fix (as
# qz/ufs.exp since -56), rwip's segmap_pagecreate address fixed by
# tools/rwippc030.py (rwip/ufs.exp, -73) and src/as_iolock_ufs.c linked in with
# rwip's as_iolock call retargeted to it by tools/iolockufs030.py, all by the
# cut's build)
K30M_FSEXTRA="\
ufs hole/ufs.exp 16eb468f2250cf86d8e7af2fca9d6ef9a59dfea8246b55c5d0d790a81834eb05"
# <name in the copyright> <sha256> <where>: amix:<path> at K30M_AMIX_COMMIT,
# port:<path> at K30M_PORT_COMMIT, paula:<path> at K30M_PAULA_COMMIT.  The
# names are the repositories the code came from; amix-kerntools' licence is
# kernel/k30's, the same bytes.
K30M_LICENCES="\
amix-a4091/LICENSE         20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4 amix:kernel/drivers/a4091/LICENSE
amix-a4091/NOTICE          f37c3ca7dba3c5b572e961a2ce1bd67e13ecf2eed9f341221866dfafc8ca3f21 amix:kernel/drivers/a4091/NOTICE
amix-z3660scsi/LICENSE     20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4 amix:kernel/drivers/z3660scsi/LICENSE
amix-040-060-port/LICENSE  ceec1a0761d69087a733d3b04716c29baa0c0243f2c0def26456516f73ad8ca6 port:LICENSE
amix-kerntools/LICENSE     20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4 amix:kernel/k30/LICENSE
amix-paula/LICENSE         4e0b5700f025f487cff0c46858b1e70cdf27bf99544ddac930a6421f62319f42 paula:LICENSE"
# the module core linked in: amix-dlm's MIT and the adopted core's (kdedon)
# The libgcc routines linked in: which, their licence and exception, where the
# source is (the toolchain the cut names in pin=), and GCC 2.7.2.3's COPYING.
K30M_LIBGCC_COPY=GCC-LIBGCC.txt
K30M_LIBGCC_COPY_SHA=325b24e41076a218424efc0e5492df17d6c99059fe76097a14db0fd0c6dd1829
K30M_DLM_LICENCES="\
LICENSE               20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
core/upstream/LICENSE 7c74426a1d5885c08435d597fcb07c2395accef0773001fc6fbd22b2bbf8a66d"

K30M_SOURCE_EPOCH=1793404800     # 2026-10-31 00:00 UTC
