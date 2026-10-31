# pin.sh -- kernel-k46-m: the module kernel of the 040/060 line, by sha256.
# Sourced by build.sh.
#
# Moved into amix kernel/port/pkg from amix-packages' recipes/kernel-k46-m
# at 450ba6a (P-38 S3.3): the same pins and the same package text; the
# licences that came from beside the checkout now come from amix at a
# commit (K46M_AMIX_COMMIT) and from amix-paula by hash.  The cut's output
# has no home in amix yet: K46M_SRC names it (make dist's kernel-k46 step,
# P-38 S2.3, is to make it).
#
# Not built in the recipe.  Cut by the port station (kabi k46.1.3, the audio
# driver with the bounded init wait, 2026-10-28;
# amix-040-060-port/build/cuts/2026-10-28-k46-paula-iw, README.md there): port branch
# k46-module at d76a7f0 (relink-040-audio.sh: amix-paula 62fdcab's three
# patchers on the stock audio.c, safeclose, initwait -- audioopen's wait for
# Paula's first interrupt is bounded, a silent Paula fails the open with EIO
# instead of spinning -- and paula, the /dev/paula exclusion; 1c58661 adds
# only the KINFO.md row for this cut), on 87b8a88's ufs mount guard and
# 88dcfc0's S5-46, built as -59 with the c chain (build-c.sh, post-c.sh,
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
# s5 module, S5-37).  out/c/ufs.mod is the port's patched ufs object
# (ufsmod/ufs-exp.k46 6636b27e, fsobj-patch.py: the mount guard) wrapped by
# amix-dlm e45b061's carve.py --build 68060-261028-61 and built with the k46
# kit of e45b061; shipped VERBATIM at /etc/conf/mod.d/ufs with a
# comment-only modreg.d file.  build.sh rebuilds it from ufsmod/c with this
# repository's kit export and requires the same bytes (S5-12 R2).  The kit
# is kabi k46.1.3; the module says kabi=k46.1.2 (the highest minor it
# imports, never below 1.2, amix-dlm C3-2 v2; K46M_FSKABI).  No module
# catalog row.
#
# A module kernel (family=generic) is its own package, never a revision of
# a static family's (C2-3 sec 1.1, amix-dlm bb088bb): kernel-k46-m, pkginst
# kern46m, version <kabi>.<yymmdd>-<nn> from the sidecar's build id, above
# the -51 of record (C2-3 v8 sec 1.1).
#
# The S5-13 checks stay (the stamp's leading blank, -91): the cut's core is
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

# K46M_SRC: the output of the port's cuts/68060-261031-52/cut.sh (no default)
K46M_SUMS=SHA256SUMS-68060-261031-52   # under K46M_SRC, the cut's seven sums
K46M_OUT=out/c                     # the cut's outputs under K46M_SRC
K46M_CARVE=ufsmod/mod              # the ufs carve sources (R2)
K46M_DLM_COMMIT=e45b061     # amix-dlm, the cut's core (port/build/dlm-rev/.rev): axrel, ksymgate.py, abi/k46 (lists, reference)
K46M_CORE_STRIP=7b07bce     # amix-dlm, the first core that skips the stamp's leading blank (S5-13)
K46M_KIT_COMMIT=e45b061     # amix-dlm, the kit the module is checked and rebuilt with (445c12e or later)
K46M_KIT_PORT=fff9660       # amix-040-060-port, the k46 kit's 4 KiB headers (the cut's PORT_REV)
K46M_PORT_COMMIT=fff96600f72849b385c23428cbd7ba33ca4040f4    # K46M_KIT_PORT in full, fetched by hash
K46M_AMIX_COMMIT=fce38f4    # amix, the cut's kernel/k30 tools: the in-amix licence
K46M_PAULA_COMMIT=62fdcabe4b5c94ec8fcbaa610655b9a0795778ec   # amix-paula, the audio patchers

K46M_CATALOG_NAME=kernel-k46-m
K46M_PKG=kern46m
K46M_BUILDID=68060-261031-52
K46M_KABI=k46.1.3
K46M_FSKABI=k46.1.2       # the .moddata kabi of ufs (the minor it imports)
K46M_VERSION=k46.1.3.261031-52

K46M_UNIX_SHA=c902f310113a8e298197bdf35baeebab4bf6b719589d7a35c88185702ae93071
K46M_UNIX_SIZE=2420313
K46M_KABI_SHA=7f8c9ee0b5ed0882554426c4759cf3c34e46287e257de4b80b5bfe630f066039

# the filesystem module: <fs> <sha256> <size> <file under $K46M_OUT>
K46M_FSMODS="\
ufs f4b9ab71fa23ad3924053169f5da97432acce567e2d376385ff226f03dfa494b 79624 ufs.mod"
# the port's patched ufs object the carve links (ufsmod/Makefile's EXTRA=):
# since -52 the tail-zeroed one, ufs-exp.k46 (6636b27e, as -61) with
# ufs_vptrunz bound in by the port's tools/ufs-tailzero.sh
K46M_FSEXP=ufsmod/ufs-exp-qz.k46
K46M_FSEXP_SHA=f49bf55e3048b2a3ff30cc4dc3b9d02ab31e979fd389d346925c2f60da4c0b8e

# the port's licence and the third-party notices of the code linked into the
# kernel (as kernel-k46), from the cut's copy of the port tree (fff9660
# since -52, the same bytes as d76a7f0, 87b8a88 and 88dcfc0;
# MOTOROLA-M68060-SP.txt changed since -82's port tree)
K46M_NOTICES="\
LICENSE                                    ceec1a0761d69087a733d3b04716c29baa0c0243f2c0def26456516f73ad8ca6
THIRD_PARTY_NOTICES/MOTOROLA-M68040-FPSP.txt 5992bb2233f332643bf14ab275bfd71719e316e10a4de5f6d772a9526d28ab79
THIRD_PARTY_NOTICES/MOTOROLA-M68060-SP.txt a8fd4c6fe11aa1c3eede5f74fcb726ee09440c2decb665603408ecc6625b26f1
THIRD_PARTY_NOTICES/NETBSD-M68K-FPE.txt    dab091a6bad4311450455e7410bcfe9c3378cdc5878b66d282d2936d88d8e41b"
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

K46M_SOURCE_EPOCH=1793404800     # 2026-10-31 00:00 UTC
