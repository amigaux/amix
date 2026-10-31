# pin.sh -- loader-amix: the amix boot loader (boot1 + boot2), by commit and
# sha256.  Sourced by build.sh.
#
# Built from amix-dlm at a pinned commit (build/pkg/common/dlm-src.sh: git
# archive into build/, the sibling checkout is only read) with amix-dlm's own
# Makefile and the period cross toolchain its toolchain.pin names.  The
# outputs must equal the pins below: 124b86c reproduces the station's
# build/boot1.img and build/boot2.bin byte for byte (2026-10-26).
#
# -11 (2026-10-31): a package-only revision for the 1.1 kernel-space set:
# -10 re-rolled without the pkginfo BASEDIR line (7cef686; stock pkgadd
# refuses one); the same commit, the same payload bytes.
#
# -10 (2026-10-28): amix-dlm 565de49 (reviewed; loaders as a6a1511 on
# 39240c1): boot1's block and boot2's bounce buffer come from the boot
# partition's DosEnvec (de_BufMemType, MEMF_PUBLIC when 0; chip when de_Mask
# does not reach them or no boot node matches), as FFS does; boot2 reads
# whole blocks straight into a buffer the Mask allows, at most 32 KiB per
# transfer, and its boot-device line names the buffer (spec 10 sec 3.1,
# 3.2).  For the A4000T, whose onboard 53C710 hangs on DMA into chip memory
# with the Z3660 fitted.  boot2's self-relocation table is a byte a field
# (39240c1).  boot1 1024 B 765915a7, boot2 28349 B da260a96, equal to
# amix-dlm's own build/boot1.img and build/boot2.bin.  Loader version
# still 3.  -9 was ea75578 (boot1 c6c380ee, boot2 28658 B 76346d9a).
# -9 (2026-10-27): amix-dlm ea75578 (reviewed 78fcd50; boot2 L11): the
# volume-2 prompt re-reads every 4 s when the disk-change counter does not
# move.  boot2 file 28658 B.  Loader version still 3, boot1 unchanged.
# Equal to amix-dlm's own build/boot2.bin.  -8 was 33ea0c7 (boot2 28646 B
# 61b3feb0).
# -8 (2026-10-27): amix-dlm 33ea0c7 (reviewed; boot2 as S4-11 4003c9f):
# boot2 places the RAM-disk image (top of the kernel's region, 64 KiB
# aligned; AXL1 116/120 and the ramdisk root selector); ax_memcap ends the
# region one 2 KiB page short of the bind base; L texts within 20 chars.
# boot2 file 28646 B (image+bss 28420 of 28672).  Loader version still 3,
# manifest untouched, boot1 unchanged.  Equal to amix-dlm's own
# build/boot2.bin.  -7 was 05f700a (boot2 28526 B a151a252).
# -7 (2026-10-26): amix-dlm 05f700a (reviewed; ec99e40): loader version 3,
# which root-class generations need (S4-10, gate 7; banner `amix-boot 3:`).
# Manifest untouched, boot1 unchanged.  -6 was 2233745 (boot2 28356 B
# 344b8e07).
# -6 (2026-10-26): amix-dlm 2233745 (reviewed; boot2 aad576f): ax_ctl_pick
# with one scratch, 488 bytes off boot2's bss.  Loader version still 2,
# manifest untouched, boot1 unchanged.  -5 was 26492cf (boot2 28392 B
# 6147ab3b).
# -5 (2026-10-26): amix-dlm 26492cf (reviewed; boot2 001b04a): a k30 kernel
# gets at most 64 MiB of fast memory; Zorro III RAM is never kernel memory.
# Loader version still 2, manifest untouched, boot1 unchanged.  -4 was
# 28aaf58 (boot2 28136 B e36c1c55).
# -4 (2026-10-26): amix-dlm 28aaf58 (reviewed; boot2 9f6f0bb): boot2 binds
# the kernel only below 0x40000000, never in Zorro III RAM.  Loader version
# still 2, manifest untouched, boot1 unchanged.  -3 was 124b86c (boot2
# 28100 B c7bff405).
# -3 (2026-10-26): amix-dlm 124b86c -- loader version 2: boot2 checks a
# module kernel's AXK1 against the manifest (L14) and fills the arena's AXA1
# directory and manifest copy; L5 names the bytes needed and available.
# boot1 unchanged.  -2 was 1230e8b (boot2 27434 B 6897cd57, the boot2 that
# counts a brel kernel's bss=, C2-3 v4, loader version 1).

LDR_DLM_COMMIT=565de49

# LOADER_VERSION in loader/boot2/b2.h at that commit (since 124b86c it is
# AX_LOADER_VERSION of loader/common/store.h); ldrinfo version= and the
# catalog's loader= (C2-2 v3 sec 1.1, C2-3 sec 3), what gate 7 compares with
# a kernel's loader-min
LDR_VERSION=3

LDR_BOOT1_SIZE=1024
LDR_BOOT1_SHA=765915a71834bf2a8ade2576d2115e86b6b4d178e00a8ac735c7e466bab8c669
LDR_BOOT2_SIZE=28349
LDR_BOOT2_SHA=da260a9689f37745c9b3760204355f46dd5f5e8f4207f82f2622a27f81a27f72

LDR_CATALOG_NAME=loader-amix
LDR_PKG=ldramix
LDR_PKG_VERSION=1.0.261025-11

LDR_SOURCE_EPOCH=1792886400
