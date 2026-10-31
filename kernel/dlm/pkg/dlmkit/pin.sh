# pin.sh -- dlmkit30 / dlmkit46: the ABI kit of each kernel line, by amix-dlm
# commit and by a manifest digest of the kit as built.  Sourced by build.sh.
#
# The kit is amix-dlm's own `make kit` (tools/mkkit.sh, docs/spec/20 sec 5,
# plan row S3-10) run in the git archive of DK_DLM_COMMIT under build/kspace/
# src/ (build/pkg/common/dlm-src.sh amix_dlm_kit), so kit.conf says
# KIT_REV=DK_DLM_COMMIT.  Inputs from outside amix-dlm: the stock headers of
# gcc-cross-amix's sysroot, the k46 4 KiB immu.h/param.h of
# amix-040-060-port include-modelb/, and tools/modfix compiled by the host cc.
#
# DK_<LINE>_MANIFEST is the sha256 of the kit's manifest as amix_kit_manifest
# prints it (build.sh): one line per file, `<x|-> <sha256> <path>` in C
# sort order -- content and the execute bit, not the umask's other bits.  A
# kit that differs in any byte fails the build rather than ships.
#
# -1 (2026-10-26): amix-dlm f5ce731 (reviewed as b61ab31, a changelog on
# top): k30.1.0 and k46.1.0, abi= 7a90c7d9 both (C3-3 v4).
# -2 (2026-10-26): amix-dlm e84878e (the kit amix-dlm ships, reviewed in
# 13a8336): every kit name within s5's 14 bytes (abi.txt, docs/guide.md,
# C3-n.md), so no renames and no S5NAMES; k46 records PORT_REV=617c64e.
# Equal, file for file, to amix-dlm's own build/kit at e84878e.
# -3 (2026-10-26): amix-dlm c6ad5bd (KIT_REV; reviewed HEAD): the kit gains
# include/sys/monsw.h (the monitor switch's interface, NOTICE names it;
# since 9f175bf mkkit takes it from amix-modules' include/sys/, the same
# bytes as the port's); k46 records PORT_REV=ebe8dfd.  Names all within 14
# bytes.  Equal, file for file, to amix-dlm's own build/kit at b6b4b87 but
# for the revision stamp in kit.conf and NOTICE.
# -4 (2026-10-26): amix-dlm 2233745 (KIT_REV; reviewed): kit.conf records
# MONSW_REV=<repo>@<commit> (fca6140: no space, so kit.conf sources in sh);
# modcheck refuses an image over 256 KiB or a file of 256 KiB (1082c0c,
# C3-1 v4); the C3-1 copy in docs/ follows.  sys/monsw.h from the git
# archive of amix-modules DK_MONSW_COMMIT (the monsw packages' commit, same
# bytes as before), so MONSW_REV=amix-modules@c0386d9.
# -5 (2026-10-26): amix-dlm 594731b (KIT_REV; reviewed): modcheck warns
# on a demand-class module whose load working set passes 160 KiB (0e84a3e)
# and the module guide says so; sys/monsw.h unchanged, still from
# amix-modules c0386d9 (MONSW_REV=amix-modules@c0386d9).
# -6 (2026-10-26): amix-dlm 96205b6 (KIT_REV; reviewed): the first kits at
# kabi k30.1.1 / k46.1.1 (since 1aba361; abi-k30.1.1.txt, abi-k46.1.1.txt),
# core 0001-0035; sys/monsw.h still from amix-modules c0386d9.
# -7 (2026-10-26): amix-dlm 05f700a (KIT_REV; reviewed): the kit makes
# root-class modules (core 0038: mkmod writes rank=; modcheck accepts
# class=root with its rules), core 0001-0038; abi texts unchanged
# (fea18182 both); sys/monsw.h still from amix-modules c0386d9.
# -8 (2026-10-26): amix-dlm 49239b1 (KIT_REV; reviewed): the first kits at
# kabi k30.1.2 / k46.1.2 (42411c4: iodone, ramdisk_image, vfs_register
# minor 2 both lines, root_defer minor 2 on k30); modcheck accepts
# block-only drivers (186bd1f); amixddi.h gives VSECT1/phystokv on k46
# (8b0e43e); sys/monsw.h still from amix-modules c0386d9; k46 PORT_REV
# 12d416c.  Equal, file for file, to amix-dlm's own build/kit at 49239b1
# but for MONSW_REV in kit.conf and NOTICE (same sys/monsw.h bytes).
# -9 (2026-10-27): amix-dlm bbd20b6 (KIT_REV; reviewed): kabi k30.1.2 /
# k46.1.2 with S4-62 piece 1 (0e4c34f): dma_prepare, dma_complete,
# dma_addr, dma_alloc, dma_free in DDI 1.2 on both lines (minor 2); C4-5 v3
# dma_addr(r, pa); the k30 provider is a placeholder (NOTICE).  sys/monsw.h
# still from amix-modules c0386d9; k46 PORT_REV 12d416c (minted when
# mkkit stamped the live port HEAD; reproduced since from the git archive
# of DK_K46_PORT_COMMIT, below).
# Equal, file for file, to amix-dlm's own build/kit at bbd20b6 but for
# MONSW_REV in kit.conf and NOTICE (same sys/monsw.h bytes as dc433b6).
# -10 (2026-10-27): amix-dlm 33ea0c7 (KIT_REV; reviewed): the kit's sd.h
# in its four-card form (a8efd99: SDCARDS 4, the sdcard() decode); sdqueue,
# sdopen, vn_rele, copyinstr, getudev, fs_nosys/setfl/frlock/poll/
# pathconf/cmp/rwlock/rwunlock minor 2 in ddi.list on both lines (bc1c511);
# abi-k30/k46.1.2.txt with the filesystem layouts (core 0042, 0572fcf):
# abi= 2ab48658 on both lines (was fea18182); the k30 NOTICE no longer calls
# the DMA provider a placeholder (S4-62 piece 2, e9665e6).  sys/monsw.h
# still from amix-modules c0386d9; k46 PORT_REV 12d416c (immu.h/param.h
# equal at the port's 9ead75f).
# -11 (2026-10-27): amix-dlm c2dc7fb (KIT_REV; reviewed): modcheck's
# per-function page-shift waivers (8fc87de: modcheck -w FUNC,..., module.mk
# PAGESHIFT_OK -- a moveq #11 + lsrl/asrl pair waived only inside the named
# functions, counted and named in the ok line); ddi.md's sptalloc note
# (c2dc7fb; its S4-71 rprobe is tests/, not in the kit).  ABI unchanged:
# abi= 2ab48658 on both lines; sys/monsw.h still from amix-modules c0386d9;
# k46 PORT_REV 12d416c.
# -12 (2026-10-31, S5-47): amix 96720ad (KIT_REV; the landed master, kernel/dlm
# as 4976dac but for its changelog and plan): the first kits at kabi
# k30.1.3 / k46.1.3 (DDI minor 3: AllocMem, FreeMem, displaytype,
# paula_busy, audio_nopen), abi= 18c0a1c9 on both lines; modcheck --kernel
# KABI says whether a kit fits a kernel's sidecar (4976dac).  sys/monsw.h
# from amix's kernel/modules at the same commit (MONSW_REV=amix@96720ad, the
# bytes of c0386d9); k46 PORT_REV d0e8857 (amix's kernel/port/port.pin;
# immu.h/param.h equal at 12d416c and fff9660).  Equal, file for file, to
# dlm's own build at 4976dac but for KIT_REV in kit.conf and NOTICE.
# -1 was f5ce731: k30 8238a7ae..., k46 71111abc...; -2 e84878e: k30
# a8ce9b9d..., k46 dcc2c522...; -3 c6ad5bd: k30 46b5ba6a..., k46 650d9108...;
# -4 2233745: k30 0074187a..., k46 3c260a3d...; -5 594731b: k30
# 7726b151..., k46 d07f09a6...; -6 96205b6: k30 609da21f..., k46
# f753c84c...; -7 05f700a: k30 1c357390..., k46 f5bb0193...; -8 49239b1:
# k30 f04242ed..., k46 a6ce6e30...; -9 bbd20b6: k30 0e4c7208..., k46
# c0b64ee4...; -10 33ea0c7: k30 c883c4fd..., k46 749b19b8...; -11 c2dc7fb:
# k30 1e317abd..., k46 08463c97...; -12 96720ad (host build): k30
# db72da99..., k46 cee36ea8...
# -13 (not minted; the release-prep revision, P-38 D-g): -12's commit, kit
# built in the build container (amix-toolchain:dist), the reference build
# for the release.  Its kit differs from -12's host build in three things:
# the stock and sysroot headers are amix-system's pinned 2.1c p2a usr/
# (patchlevel.h, and sys/types.h and sys/socket.h with their comments
# closed), where the host gcc-cross-amix's sysroot is an older copy; and
# tools/modfix, the kit's host program, as the container's compiler builds
# it.  Pinned by the manifest digest, which covers kit.conf and NOTICE
# (the provenance the package carries), not by norev: the norev digest
# differs between the two builds as well.
DK_DLM_COMMIT=96720ad
# where the kit's sys/monsw.h comes from: kit.conf's MONSW_REV=<repo>@<commit>
# (amix-modules before the move-in, amix's kernel/modules since)
DK_MONSW_REPO=amix
DK_MONSW_COMMIT=96720ad
# amix-040-060-port: the k46 kit's include-modelb/sys/{immu,param}.h come
# from the git archive of this commit (dlm-src.sh amix_dlm_kit), so PORT_REV
# is this commit whatever the port's live HEAD is
DK_K46_PORT_COMMIT=d0e8857
# its full hash: git fetches a commit by its full hash only (build.sh fetches
# it into AMIX_PORT_REPO when that lacks it); the label stays the short one
DK_K46_PORT_HASH=d0e88574f7ee8559452cc7363ff7bcf3dd9133e6
DK_K30_MANIFEST=6fd5269dc806de36fb790ddac560f2c9fa3c6d5d9d006300c87ef9c8ecfc0e4d
DK_K46_MANIFEST=650b0e50595c60cf8a30706955e38e3a6b2352ee8d5d472cacb9f40ac0dbd681

DK_DATE=261031
DK_REV=13
DK_SOURCE_EPOCH=1793404800
