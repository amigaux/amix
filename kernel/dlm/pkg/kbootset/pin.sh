# pin.sh -- kbootset: the generation composer for the box, by commit and
# sha256.  Sourced by build.sh.
#
# Built from amix-dlm at a pinned commit (build/pkg/common/dlm-src.sh) with its
# own Makefile target build/box/kbootset: GCC 14 (gcc14-cross-amix), static,
# -Ttext-segment=0x80000000, checked by gcc14-cross-amix's
# check-68060-safe.py in that Makefile (C2-3 v2 sec 4, D-3 sec 9).
#
# The bytes depend on the gcc14-cross-amix runtime it links (libgcc,
# libamixc99): KB_SHA is db0ef3a (kbootset retry, C2-4 v5) linked against
# the runtime rebuilt --with-cpu=m68020-60 (libgcc.a feb13ad3, libamixc99.a
# 6c243ef6; no 040/060-only FPU form), equal to the station's
# build/box/kbootset at db0ef3a.  -2 was 1230e8b (e4d136d6).

# -29 (not minted; the release-prep revision, P-38 D-g): -28's payload
# plus /dev/kinfo, `c kinfo /dev/kinfo 53 0 0444 root sys`, CLASSES none
# kinfo (C2-4 v19 sec 2), which the installer wrote before; the box binary,
# page and rc scripts as -28.
#
# -28 (2026-10-31, D-N21): amix 01f1520 -- `kbootset major -l` lists the
# whole major registry; the box binary 1511ef9b (156608 bytes, gcc14
# b51ff39), kbootset(1M) b3c79fa5; the rc scripts and whatis as -26/-27;
# APKG_ESSENTIAL=yes as -27.
#
# -27 (2026-10-31): -26 with APKG_ESSENTIAL=yes in pkginfo (apkg refuses to
# remove it: a 1.1 box boots its generations through it, and it carries
# S01kbnamelist and S99zkbootset); the payload as -26's.
#
# -26 (2026-10-31, P-36 W8): amix 88473bb -- the box binary rebuilt equal
# (d863c145); kbootset(1M) f25273d4; the package ships kbootset's two rc
# scripts (kernel/dlm/kbootset/rc): /etc/init.d/kbnamelist, linked as
# /etc/rc2.d/S01kbnamelist, and /etc/init.d/kbmarkgood, linked as
# /etc/rc2.d/S99zkbootset (hard links, as stock's run-level names and
# amix-base's), which the installer laid down by hand until W7.
#
# -25 (2026-10-30): amix master 0c537a4 -- since 565de49 the box binary
# changes only by bf90a17 (`kbootset major NAME` prints a module's majors
# from the registry, +37 lines), and the package gains kbootset(1M) and its
# whatis line (4f854d9; userland/packages/docs/man-pages.md), pinned below.
# Built on gcc14-cross-amix b51ff39 (gcc14-pin.sh), where -24 was cf461e3:
# b51ff39's specs default to -mno-strict-align (e8b6997, owner 2026-10-27),
# so .text is ~55 KB smaller -- 565de49 rebuilt on b51ff39 is 156168 bytes
# (019ed78f) against -24's 211856, and kbootset/*.c compiled with
# -mstrict-align gives back +45 KB of .text and 1035 bit-field instructions.
# Built clean: d863c145, 156488 bytes.  -24 stays the release candidate's.
# -24 (2026-10-28): amix-dlm 565de49 (reviewed) -- since e089c2a the box
# binary changes only by kbootset/kreg.c (6fe9c60: c 54 paula in the major
# registry, spec 20 sec 6), so kbootset knows paula's major; the rest is
# the loaders (a6a1511: DMA buffers by the partition's DosEnvec, shipped by
# loader-amix -10), the kits and core 0046 (DDI minor 3), spec and plan
# text.  Built clean: 0b9b8ec4, equal to the box kbootset of 6fe9c60.
# modadmin at 565de49 is f51c98d6 (= modtools -7): no modtools mint.  Same
# pkgmap as -4.  DESC carries the release notes of this set (the 1.3
# kernels; loader-amix -10's loaders).
# -23 (2026-10-28): amix-dlm e089c2a (reviewed) -- since 1308c0b: C2-4 v15
# (7925b96, df7124b): after a boot the loader fell back from the default on
# its own (AXL1 flag 0x04, no menu, no one-shot), mark-good verifies the
# default and marks it bad when its bytes are damaged, the booted generation
# becoming the default; intact members keep it.  The rest since 1308c0b is
# core (7b07bce), spec and plan text, outside the box binary.  Built clean:
# 3c18c3b5, equal to amix-dlm's own build/box/kbootset.  modadmin at e089c2a
# is f51c98d6 (= modtools -7): no modtools mint.  Same pkgmap as -4.  DESC
# carries the kernels' release notes (kern30m -20 / kern46m -50 with -22 or
# later; s5 gone on k46, S5-37) until their next cuts carry them.  The first
# -23 datastream (cfcfe78, without the s5 note) was withdrawn unproven.
# -22 (2026-10-27): amix-dlm 1308c0b (reviewed) -- since 4442c76: S5-05
# (a medium's RAM-disk image after its root modules, 28fb5a1), S5-09 (safe
# mode loads boot members marked safe=1, 484cdd2), S5-15 (the Z3660 one
# controller in either mode; card_of for two mobo cards, 8941879), S5-44
# (`kbootset nodes`, the disk nodes of a four-card kernel, 4046392), S5-45
# (media --disk --ramdisk, eb31c79), S5-46 (an old mobo root record takes
# its controller's id, c7d69cf), the namelist lookup takes the global, never
# a file static (0735e4d), status in a safe boot names the safe set it keeps
# (3f12419), a store root record keeps a core-tier module's tier and build
# (e8254e5).  Built clean (a fresh export, every object by cf461e3): 37e78d88,
# equal to amix-dlm's own build/box/kbootset.  Upgrade kern30m -20 together
# with it: an old mobo root record on a 030-mode Z3660 is rewritten only by
# -22.  modadmin at 1308c0b is f51c98d6 (= modtools -7): no modtools mint.
# Same pkgmap as -4.
# -21 (2026-10-27): amix-dlm 4442c76 (reviewed as 9a7279c, a changelog on
# top; kbootset code as 74b3e79, S5-02) -- the safe set also takes every
# controller module ranked at or before the root's class, so safe mode keeps
# the normal boot's card numbers (C4-4 v6, C3-5 v13; skipped on a ramdisk
# root).  First box build on gcc14-cross-amix cf461e3 (S5-01: pointers in
# %a0 and %d0, structs through %a0), checked by dlm-src.sh against
# gcc14-pin.sh (the pins and the ABI self-check of TOOLCHAIN=gcc14).  Every
# object compiled by cf461e3: 143cc1d8.  amix-dlm's own build/box/kbootset
# (2c3570a3) differs in 115 bytes -- an incremental make kept bootinfo.o,
# inflate.o and manifest.o from the pre-fix compiler (e316f1b rebuilds them
# byte for byte; relinked with ours they give 2c3570a3).  Same pkgmap as -4.
# -20 (2026-10-27): amix-dlm 1da3474 (reviewed; kbootset code as 093b2a7,
# the only kbootset/ change since 178a47b) -- gate 2 checks the sidecar's
# build= against the kernel's own build id (buildid on k46, kinfo_buildid
# through unix.sym on k30, leading blanks ignored; a kernel without the
# symbol is unchecked): "is not the kernel's own build id".  boot1
# c6c380ee, boot2 61b3feb0 and modadmin 0518fb28 byte-identical at 1da3474.
# -19 (2026-10-27): amix-dlm 178a47b (reviewed; kbootset code as fa7a4ab,
# the only kbootset/ change since d227dbf) -- a module whose depend= names
# a module the generation lacks is left out of gate 2's import check, so
# gate 3 says "depends on <m>, which is not in the generation" instead of
# "it needs a newer kernel cut".  boot1 c6c380ee, boot2 61b3feb0 and
# modadmin 0518fb28 byte-identical at 178a47b (no loader/modtools mint).
# -18 (2026-10-27): amix-dlm d227dbf (reviewed; kbootset code as 101e9a3)
# -- gate 2 checks every module's imports against the kernel's symbol
# block (the sidecar's ksym=, found by binding a copy with ax_rel as boot2
# does): a name neither the block (at the module's tier) nor a module it
# depends on provides refuses the generation at compose time, naming the
# missing names and "it needs a newer kernel cut" (C3-3 v7, spec 40
# sec 3.1/7).  boot2 61b3feb0 and modadmin 0518fb28 unchanged at d227dbf.
# -17 (2026-10-27): amix-dlm 33ea0c7 (reviewed; kbootset code as 5d3d988)
# -- reads a module's fs= (C4-6 sec 3) and promotes the rootfs's
# boot-class module to a root record on a generation rooted on that fs
# (C4-4 v5 sec 1.3, core 0043); `media --ramdisk` defaults to root ramdisk,
# swap none, and marks the module owning b:20 safe=1 (57b3832, S4-11);
# gate 4 refuses a root-class generation whose kernel arena is not
# 16-aligned (a829c44); loader-min 3 as -16.  Same pkgmap as -4,
# including /var/kbootset.
# -16 (2026-10-26): amix-dlm f340556 (kbootset code as f5dedff) -- root-class
# modules compose as root records (`module <name> root ... bss= match=
# safe=1`, S4-12); a generation that carries one needs loader version 3
# (AX_LOADER_ROOT, gate 7); a root module for a controller the kernel's
# sidecar root= names is refused at gate 3 (two drivers on one board).
# Same pkgmap as -4, including /var/kbootset.
# -15 (2026-10-26): amix-dlm 594731b (reviewed; kbootset code as 35dd599)
# -- `media --cd`/`--floppy` runs gate 3 on the root controller only (C2-4
# v11 sec 13); `namelist` writes /stand/unix 0644 whatever the umask
# (dcc681b).  Equal to amix-dlm's own build/box/kbootset (d44f6a32).  Same
# pkgmap as -4, including /var/kbootset.
# -14 (2026-10-26): amix-dlm c6ad5bd (reviewed; kbootset code as 72ed9c2)
# -- deflates on the box with its own encoder, so `--spec z=deflate`
# works; with -13's read-only-medium boot.  Equal to amix-dlm's own
# build/box/kbootset (9acb9add).  Same pkgmap as -4, including
# /var/kbootset.  -13 (d814da1, e56172b6) was never staged.
# -13 (2026-10-26): amix-dlm d814da1 (reviewed; kbootset code as ccad712)
# -- a boot from a read-only medium (AXL1 flag 0x08: the CD, the floppy
# pair): mark-good marks nothing, retry does nothing, status says the
# medium booted; the namelist comes from the installed kernel when its
# build id is kinfo's (C2-4 v10 sec 13).  Equal to amix-dlm's own
# build/box/kbootset (e56172b6).  Same pkgmap as -4, including
# /var/kbootset.
# -12 (2026-10-26): amix-dlm af363be (reviewed; kbootset code as 9763024) --
# `kbootset namelist` writes /stand/unix, the booted kernel's namelist
# (C2-4 v9 sec 12); a brel's unix.sym is read as C2-3 v6 sec 2.1 states it
# (ET_EXEC, st_value the address at bind 0, NOBITS sections by name).
# Equal to amix-dlm's own build/box/kbootset at 9763024.  Same pkgmap as -4,
# including /var/kbootset.  (13a8336's build, 4a09a6dd, read unix.sym
# st_value plus sh_addr and was never shipped.)
# -11 (2026-10-26): amix-dlm f5ce731 (reviewed as b61ab31, a changelog
# on top) -- gate 2 refuses a module kernel whose sidecar has no abi=
# (C3-3 v4); gate 6 counts an ET_REL kernel's bss from its section headers
# (6b2d669).  Equal to amix-dlm's own build/box/kbootset at f5ce731.  Same
# pkgmap as -4, including /var/kbootset.
# -10 (2026-10-26): amix-dlm 42df482 (reviewed; code as a64aee1) --
# `kbootset media` composes the installed module packages into the
# medium's pristine generation as `build` does (gates 1-3, parameters).
# Equal to amix-dlm's own build/box/kbootset at a64aee1.  Same pkgmap as
# -4, including /var/kbootset.
# -9 (2026-10-26): amix-dlm a71a875 -- S3-16: `build` composes module
# members under /etc/conf/mod.d through gates 1-3, copies them to
# /stand/gen/<id>/mod/ and writes module and param records in depend order;
# `commit` re-verifies; `status` marks members loaded or not.  Equal to
# amix-dlm's own build/box/kbootset at a71a875.  Same pkgmap as -4,
# including /var/kbootset.
# -8 (2026-10-26): amix-dlm 124b86c -- sidecar v5: reads ident=; a module
# kernel needs arena=, ident= and loader-min=2 together (gate 2); the
# manifest gets arena and ident records; gate 4 checks the manifest copy
# fits the arena.  Loader version 2 is the default --version.  Equal to
# amix-dlm's own build/box/kbootset at 124b86c.  Same pkgmap as -4,
# including /var/kbootset.
# -7 (2026-10-26): amix-dlm f43fe08 -- C2-4 version 7: `kbootset commit`
# writes nothing when the built generation equals the default one (compared
# through the loader's parser), `commit --again` writes it all the same.
# Same pkgmap as -4, including /var/kbootset.  build.sh refuses a pending pin.
# -24 was 565de49 0b9b8ec4; -23 was e089c2a 3c18c3b5; -22 was 1308c0b 37e78d88; -21 was 4442c76 143cc1d8; -20 was 1da3474 b3e7b987; -19 was 178a47b f537493d; -18 was d227dbf a9e4f923; -17 was 33ea0c7 527b8d59; -16 was f340556 98c04c09; -15 was 594731b d44f6a32; -14 was c6ad5bd 9acb9add; -13 was d814da1 e56172b6; -12 was af363be cd02b817; -11 was f5ce731 013fe25f; -10 was 42df482 305345a3; -9 a71a875 8cb4c157; -8 124b86c 05c1d40f; -7 f43fe08 a2970b20;
# -6 fb77acd 870d4752; -5 6c69125 6b76c54c; -4 d64bad7 9cf75c1c;
# -3 db0ef3a f4a6632b.
KB_DLM_COMMIT=01f1520
KB_SHA=1511ef9b85f19e18c5cb7f50640a9eff559eca4562a92683b1de67e0d442bf24
# kbootset(1M) and its whatis line, from the same commit (kernel/dlm/man)
KB_MAN_SHA=b3c79fa570a419d6c99e3ca28490b7140db9faeb878161b448c07cf826e4ff96
KB_WHATIS_SHA=b80d0af059afa64cee8c6d3f154c677064b223e7ce2d84138cd5f4a564c6445a

# the rc scripts, from the same commit (kernel/dlm/kbootset/rc)
KB_RC_KBNAMELIST_SHA=4594a81878859a1738b11f1c389f5e7a624bc8a8a5346781f2f88d150c9a4503
KB_RC_KBMARKGOOD_SHA=70816e6d90253d51c9d0e1e2bd59e98e46f60b2eda2b777d8de266d9ca5e7dff

KB_VERSION=1.1.0.261031-29
KB_SOURCE_EPOCH=1793404800
