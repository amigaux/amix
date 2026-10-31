# pin.sh -- kernel-k30-m: the module kernel of the 030 line, by sha256.
# Sourced by build.sh.
#
# Moved into amix kernel/k30/pkg from amix-packages' recipes/kernel-k30-m at
# 450ba6a (P-38 S3.3): the same pins and the same package text; the inputs
# that came from beside the checkout now come from amix at a commit
# (K30M_AMIX_COMMIT: elf2brel and the licences of the drivers' patches) and
# from the pinned forks by hash (the port's and paula's licences).
#
# Not built here.  amix-kerntools cut it (kerntools 22d3261, the k30 cut at
# DDI minor 3: amix-kerntools/build/cuts/2026-10-28-k30-paula/cut-paula.sh -- the S5-10
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
# with this repository's own kit export and requires the same bytes (S5-12
# R2).  The kit is kabi k30.1.3; a module carries the highest minor it
# imports, never below 1.2 (amix-dlm C3-2 v2), so ufs and s5 say
# kabi=k30.1.2 in .moddata (K30M_FSKABI).  No module catalog rows: they
# travel in the kernel package only.
#
# Its own package (C2-3 sec 1.1, amix-dlm bb088bb): kernel-k30-m, pkginst
# kern30m, version <kabi>.<yymmdd>-<nn> from the sidecar's build id, above
# the -20 of record (C2-3 v8 sec 1.1).  -04 to -13 stay in build/kspace/pkg;
# -14 to -16 are in build/kspace/pkg/superseded; -17 is 64d37aaa's; -20
# (kerntools 224b285, dlm dc9f6ab, kabi k30.1.2, the S5-12 cut) is the
# kernel of the catalogs of record 915e09f3 to b1f564f4.
#
# -22 against -20: kabi k30.1.3 (DDI minor 3: AllocMem, FreeMem,
# displaytype, paula_busy, audio_nopen, so the paula module loads), the
# patched audio driver (the /dev/paula exclusion, the bounded open), the
# module core e45b061 (0046).  The release notes in pkginfo since
# 2026-10-28 ride this cut (a new version); -20 is never re-rolled -- one
# version, one set of bytes (recipes/README.md).

# -64 against -63 (2026-10-31): the k30 station's cut 68030-261031-64 (amix
# kernel/k30/cuts/68030-261031-64), -63's recipe from amix b391504: the module
# core's major registry carries c 48 random (a8719fb), so the random module's
# char major is the kernel's own; the same fixes as -63.  The first cut made
# by make dist's kernel-k30 hook (cuts/build.sh), the same sums on the host
# and in the build container.  kabi k30.1.3 and abi 18c0a1c9 unchanged,
# module kabi k30.1.2; core and kit amix b391504, port 0d37eb1 and paula
# 1b2736d at their pins (the files the cut reads are -63's bytes), audio.c
# 1f43c5ff; ufs carved from the same qz/ufs.exp (c480330a).
#
# -63 against -56 (2026-10-31): the k30 station's cut 68030-261031-63
# (amix kernel/k30/cuts/68030-261031-63, a0e2ab4), from amix c1b7842's
# kernel/ with -56's recipe and fixes plus the STREAMS freeq guard (grimoire
# quirk 92: the 5 freeq calls in qdetach, strclose and stropen go through
# freeq_guarded, so a queue still scheduled is not freed under queuerun;
# prngd under prngd-ctl traffic panicked the kernel).  kabi k30.1.3 and abi
# 18c0a1c9 unchanged, module kabi k30.1.2; core and kit amix kernel/dlm
# c1b7842, port d0e8857 (kernel/port/port.pin), audio.c 1f43c5ff; ufs
# carved from the same qz/ufs.exp as -56.
#
# -56 against -22 (2026-10-30): the k30 station's cut 68030-261030-56 (amix
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
# there, from cuts/68030-261031-64/cut.sh (gitignored)
K30M_SRC="${K30M_SRC:-$AMIX_TOP/kernel/k30/build/cuts/68030-261031-64}"
K30M_SYSDIR=cut-68030-261031-64/usr/sys   # the cut's kernel tree under K30M_SRC
K30M_SUMS=SHA256SUMS-68030-261031-64      # under K30M_SRC; names relative to K30M_SYSDIR
K30M_CARVE=cut-68030-261031-64/carve      # the carve sources of ufs and s5 (R2)
K30M_AMIX_COMMIT=b391504    # amix, the cut's commit: elf2brel and the in-amix licences
K30M_ELF2BREL=kernel/k30/tools/elf2brel.py
K30M_ELF2BREL_SHA=0026fb59d5bd58468786e0af6b4178667260e77944758c91d834e8adaf4b42f5
K30M_DLM_COMMIT=b391504     # amix (kernel/dlm), the cut's core: axrel, ksymgate.py, abi/k30 (lists, reference)
K30M_KIT_COMMIT=b391504     # amix (kernel/dlm), the kit the modules are checked and rebuilt with
K30M_KIT_PORT=0d37eb1       # amix-040-060-port, the kit's headers (k46 half of `make kit`)
K30M_PORT_COMMIT=0d37eb1b1f16653e1fdd656eaf6d8d645721774d    # K30M_KIT_PORT in full, fetched by hash
K30M_PAULA_COMMIT=1b2736d9bb291af77bd1e8995d15f3e60d0627ff   # amix-paula, the audio patchers

K30M_CATALOG_NAME=kernel-k30-m
K30M_PKG=kern30m
K30M_BUILDID=68030-261031-64
K30M_KABI=k30.1.3
K30M_FSKABI=k30.1.2       # the .moddata kabi of ufs and s5 (the minor they import)
K30M_VERSION=k30.1.3.261031-64

K30M_BREL_SHA=03c4e1224e054fba3f905cb7e998ab3a8fc844c4cbf18d5e100dade2ee7710bb
K30M_BREL_SIZE=1536372
K30M_BSS=346396
K30M_KABI_SHA=cf7c8a313595416e8716bf2101e75da6cbcb869bc4f86f029299d4df11f63443
K30M_SYM_SHA=0745df745733cba58288ddb467a8f592e1fe31f62c8e98a8162a1768de1ecaaf
K30M_SYM_SIZE=179560
K30M_ETREL_SHA=278d4d0f5df4d7fb71597fc26b7a2fb07ed91c27e8e06192e539eb0c462f4cf0
# the cut's patched audio driver source (SHA256SUMS names it; the three
# amix-paula patchers, 1b2736d's (548d258's bytes), on the stock audio.c)
K30M_AUDIO_SHA=1f43c5ff6558bf6583bcc3525b456bf3560e2bcf6100f5c736b0aa0221b260cc
# the sidecar's other fields, for the record (build.sh checks ident/arena/
# ksym are present once and abi= against amix-dlm's reference):
#   ident=0x000e1c28  arena=0x000e1c70 0x00060000  ksym=0x000e0384 0x000018a0
#   abi=18c0a1c98b2c9284fb10a6b6386403ed5e13193e3ec7aa4f113ff2a174285378 (= abi-k30.1.3.txt)
#   root=mobo:a3000-wd,zorro:0202:01,zorro:0202:03, sdcards=4 and rth1=2
#   passed through verbatim; no rootfs= (build.sh refuses one)

# the filesystem modules: <fs> <sha256> <size>, at $K30M_SYSDIR/mod.d/<fs>
K30M_FSMODS="\
ufs 5938bb6276af61d45959efae2452c07995c1a2a191b4a82437b305278378b772 79624
s5  7dcca81eee6b936e0037952d8cba7e9478132b8b4b745dbdb2943c8640657bea 58310"
# the stock objects the carve wraps (the sysroot's, as the cut's carve/stock.sha256)
K30M_FSSTOCK="\
fs/ufs/exp a439e68f880d01450f156a0fd5886610c828d2a7cbdfdf3e8a28d93dd656273c
fs/s5/exp  1c9cb6342da321047b6861170543382eaa75457573858fe641586ff6fddaf33e"

# licences of the code linked in besides the stock kernel: as kernel-k30-u
# (pin.sh there says which repository gives what; rth1.c is the port's
# 0d37eb1 here), then the module core below.  Since -22 the patched audio
# driver: the stock amiga/driver/audio.c with amix-paula's three patchers
# (MIT).  Since -14
# the A4091 driver (a4091.o) and the Gayle IDE driver (ide.o) are not
# linked: amix-gayle-ide is dropped; since -17 the static cdfs
# (libcdfskern.o) is not linked: amix-cdfs is dropped; amix-a4091 stays,
# its four stock-file patches (a2091.c, a3091.c, scsi.c, support.c) are
# still applied (NOTICE parts 1 and 2)
# a filesystem whose carve links the cut's own object instead of the stock
# exp: name, path under the cut, sha256 (-56: ufs, the stock fs/ufs/exp with
# pvn_vptrunc rebound to ufs_vptrunz, the quirk-91 fix, by the cut's cut.sh)
K30M_FSEXTRA="\
ufs qz/ufs.exp c480330a55bf3a179b3fe4881df029ebb0c9699383f7c5021fb3d3658d9b9a61"
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
K30M_DLM_LICENCES="\
LICENSE               20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
core/upstream/LICENSE 7c74426a1d5885c08435d597fcb07c2395accef0773001fc6fbd22b2bbf8a66d"

K30M_SOURCE_EPOCH=1793404800     # 2026-10-31 00:00 UTC
