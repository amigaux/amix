# pin.sh -- kbootset: the generation composer for the box, by commit and
# sha256.  Sourced by build.sh.
#
# Built from amix-dlm at a pinned commit (build/pkg/common/dlm-src.sh) with its
# own Makefile target build/box/kbootset: GCC 14 (gcc14-cross-amix), static,
# -Ttext-segment=0x80000000, checked by gcc14-cross-amix's
# check-68060-safe.py in that Makefile (C2-3 v2 sec 4).
#
# The bytes depend on the gcc14-cross-amix runtime it links (libgcc,
# libamixc99): KB_SHA is db0ef3a (kbootset retry, C2-4 v5) linked against
# the runtime rebuilt --with-cpu=m68020-60 (libgcc.a feb13ad3, libamixc99.a
# 6c243ef6; no 040/060-only FPU form), equal to amix-dlm's own
# build/box/kbootset at db0ef3a.  -2 was 1230e8b (e4d136d6).

# -39 (2026-11-04): amix e6dd2ac -- kbootset default ID makes a good or
# pristine generation the default again, and rollback and build name it;
# check names the generation that holds the installed kernel; commit's last
# line, status and check name a loader in /stand/loader the store does not
# hold; a brel generation keeps its own unix.sym for a boot after a rollback;
# status tells a namelist lacking a loaded module from another kernel's; an
# unchanged commit removes the build's module copies, and the directory of a
# generation gone from the store goes (C2-4 v27 section 19).  Built in
# amix-toolchain:dist: the box binary c3c59269 (179080 bytes, text + data + bss
# 6284 more than -38); kbootset(1M) 794c34f8; whatis and rc scripts as -38.
#
# -38 (2026-11-04): amix b7f6447 -- kbootset namelist and status no longer
# walk and free an unset module list on the five refusals of a brel kernel
# (k30: another kernel installed, or kabi or unix.sym wrong), which ran before
# the list was cleared.  Against -37 only kb_namelist_run differs, and the
# binary links bootinfo.c's ax_rd_place, which kbootset does not call.  Built
# in amix-toolchain:dist: the box binary 7de82527 (170740 bytes); kbootset(1M),
# whatis and rc scripts as -37.
#
# -37 (2026-11-03): amix 65e166c -- kbootset namelist carries crash_sync's
# running word in a PROGBITS section of its own, so stock crash can check
# its timestamp, and the loaded modules' globals at the addresses getksym
# gives, kept to each module's run (C2-4 v26 section 12).  Built in
# amix-toolchain:dist: the box binary 83ae6565 (170712 bytes); kbootset(1M)
# 26334a46 (the namelist's contents); whatis and rc scripts as -36.
#
# -36 (not minted; the revision for the release): amix f8e9027 -- kbootset
# inquiry CARD UNIT and kbootset cards --probe ask a unit its type with one
# read-only SCSI INQUIRY through /dev/scsi (gsioctl) before anything reads it
# (C2-4 v23), so an installer never reads a CD with dd; gate 1's "differs"
# line names the reinstall, apkg -f install <name> (14b5853).  Built in
# amix-toolchain:dist: the box binary 2a2d9016 (163472 bytes);
# kbootset(1M) 385b4462 (inquiry, cards --probe, gate 1); whatis and rc
# scripts as -35.
#
# -35 (not minted; the revision for the release): amix 2607bbe -- kbootset
# cards reads a disk node's controller number in hex, as the stock names
# write it (C2-4 v22): /dev/dsk/ced0s1 is card 1's unit 6, c10-c17 card 2
# (-34 refused ca-cf and gave card 1's key for c10-c17); the card list
# prints c8-cf, c10-c17, c18-c1f.  Built in amix-toolchain:dist (gcc14 as
# master's pin; -34's e072f89 rebuilds there to 0d5462db): the box binary
# 704d14fa (162016 bytes, as -34); kbootset(1M) 5ab8918c (cards); whatis
# and rc scripts as -34.
#
# -34 (not minted; the revision for the release): amix e072f89 -- kbootset
# writes the major table into a module kernel's manifest, one `major` record
# per registry row (C3-5 v22), which a kernel with core patch 0051 reads
# instead of a table built into it; gate 3 refuses a member on a row the
# kernel's own drivers fill; check compares each generation's table with
# the registry, and a default generation without the table is not taken
# for an equal one.  Built on gcc14 43825b2 in amix-toolchain:g14-43825b2:
# the box binary 0d5462db (162016 bytes, 2556 more than -33); kbootset(1M)
# 3a980b98 (check); whatis and rc scripts as -33.
#
# -33 (not minted; the revision for the release): amix 9be1705 -- kbootset
# knows character major 55, zz9ksvc (the ZZ9000/Z3660 service channel,
# kernel/modules), so gate 3 passes a zz9ksvc module; built on gcc14 43825b2 in amix-toolchain:g14-43825b2,
# whose amix_init.o runs library constructors after start-up.  The box
# binary 048e108a (159460 bytes, 452 more than -32: 20 the registry row
# and its name, 432 the start-up code); kbootset(1M), whatis and rc
# scripts as -32.
#
# -32 (not minted; the revision for the release): amix a7efb20 -- kbootset
# cards prints the running kernel's sd cards from kinfo's card table with
# their controllers' match keys, and one disk node's key, so an installer
# takes --bootdev and --rootdev from the disk the user picks (C2-4 v21
# sec 17).  The box binary bc934ce1 (159008 bytes, 1736 more than -31; the
# command reads kinfo into main's buffer, so bss is -31's); kbootset(1M)
# f7fd14f9 with the command; whatis and rc scripts as -31.
#
# -31 (not minted; the revision for the release): amix 6bb7dd6 -- kbootset
# composes a demand-class filesystem module: its record carries fs=, it
# needs a kernel at kabi minor 4, two modules of one type are refused, and
# as the rootfs it is promoted (C3-5 v20, C4-6 v5); status says a demand
# member loads at first use.  The box binary b7f9f05a (157272 bytes, 644
# more than -30, gcc14 b51ff39 in amix-toolchain:dist); page, whatis and rc
# scripts as -30.
#
# -30 (not minted; the revision for the release): amix 4ccb3f0 --
# kreg.c regenerated with c 48 random (a8719fb), so `kbootset major random`
# says c 48 and gate 3 accepts the random module; the box binary 6da558d0
# (156628 bytes, gcc14 b51ff39 in amix-toolchain:dist, a host build equal,
# the same at 97c4003); kbootset(1M) a80aa79f and kbmarkgood 1c089c0f, their
# text restated without internal ids; whatis and kbnamelist as -28,
# /dev/kinfo as -29.  -29 (01f1520) predates a8719fb and refuses random at
# gate 3.
#
# -29 (not minted; the revision for the release): -28's payload
# plus /dev/kinfo, `c kinfo /dev/kinfo 53 0 0444 root sys`, CLASSES none
# kinfo (C2-4 v19 sec 2), which the installer wrote before; the box binary,
# page and rc scripts as -28.
#
# -28 (2026-10-31): amix 01f1520 -- `kbootset major -l` lists the
# whole major registry; the box binary 1511ef9b (156608 bytes, gcc14
# b51ff39), kbootset(1M) b3c79fa5; the rc scripts and whatis as -26/-27;
# APKG_ESSENTIAL=yes as -27.
#
# -27 (2026-10-31): -26 with APKG_ESSENTIAL=yes in pkginfo (apkg refuses to
# remove it: a 1.1 box boots its generations through it, and it carries
# S01kbnamelist and S99zkbootset); the payload as -26's.
#
# -26 (2026-10-31): amix 88473bb -- the box binary rebuilt equal
# (d863c145); kbootset(1M) f25273d4; the package ships kbootset's two rc
# scripts (kernel/dlm/kbootset/rc): /etc/init.d/kbnamelist, linked as
# /etc/rc2.d/S01kbnamelist, and /etc/init.d/kbmarkgood, linked as
# /etc/rc2.d/S99zkbootset (hard links, as stock's run-level names and
# amix-base's), which the installer laid down by hand before.
#
# -25 (2026-10-30): amix master 0c537a4 -- since 565de49 the box binary
# changes only by bf90a17 (`kbootset major NAME` prints a module's majors
# from the registry, +37 lines), and the package gains kbootset(1M) and its
# whatis line (4f854d9; userland/packages/docs/man-pages.md), pinned below.
# Built on gcc14-cross-amix b51ff39 (gcc14-pin.sh), where -24 was cf461e3:
# b51ff39's specs default to -mno-strict-align (e8b6997),
# so .text is ~55 KB smaller -- 565de49 rebuilt on b51ff39 is 156168 bytes
# (019ed78f) against -24's 211856, and kbootset/*.c compiled with
# -mstrict-align gives back +45 KB of .text and 1035 bit-field instructions.
# Built clean: d863c145, 156488 bytes.  -24 stays the release candidate's.
# -24 (2026-10-28): amix-dlm 565de49 -- since e089c2a the box
# binary changes only by kbootset/kreg.c (6fe9c60: c 54 paula in the major
# registry, spec 20 sec 6), so kbootset knows paula's major; the rest is
# the loaders (a6a1511: DMA buffers by the partition's DosEnvec, shipped by
# loader-amix -10), the kits and core 0046 (DDI minor 3), and docs
# text.  Built clean: 0b9b8ec4, equal to the box kbootset of 6fe9c60.
# modadmin at 565de49 is f51c98d6 (= modtools -7): no modtools mint.  Same
# pkgmap as -4.  DESC carries the release notes of this set (the 1.3
# kernels; loader-amix -10's loaders).
# -23 (2026-10-28): amix-dlm e089c2a -- since 1308c0b: C2-4 v15
# (7925b96, df7124b): after a boot the loader fell back from the default on
# its own (AXL1 flag 0x04, no menu, no one-shot), mark-good verifies the
# default and marks it bad when its bytes are damaged, the booted generation
# becoming the default; intact members keep it.  The rest since 1308c0b is
# core (7b07bce) and docs, outside the box binary.  Built clean:
# 3c18c3b5, equal to amix-dlm's own build/box/kbootset.  modadmin at e089c2a
# is f51c98d6 (= modtools -7): no modtools mint.  Same pkgmap as -4.  DESC
# carries the kernels' release notes (kern30m -20 / kern46m -50 with -22 or
# later; s5 gone on k46) until their next cuts carry them.  The first
# -23 datastream (cfcfe78, without the s5 note) was withdrawn unproven.
# -22 (2026-10-27): amix-dlm 1308c0b -- since 4442c76: a medium's
# RAM-disk image after its root modules (28fb5a1); safe mode loads boot
# members marked safe=1 (484cdd2); the Z3660 one controller in either mode,
# card_of for two mobo cards (8941879); `kbootset nodes`, the disk nodes of
# a four-card kernel (4046392); media --disk --ramdisk (eb31c79); an old
# mobo root record takes its controller's id (c7d69cf); the namelist
# lookup takes the global, never a file static (0735e4d), status in a safe boot names the safe set it keeps
# (3f12419), a store root record keeps a core-tier module's tier and build
# (e8254e5).  Built clean (a fresh export, every object by cf461e3): 37e78d88,
# equal to amix-dlm's own build/box/kbootset.  Upgrade kern30m -20 together
# with it: an old mobo root record on a 030-mode Z3660 is rewritten only by
# -22.  modadmin at 1308c0b is f51c98d6 (= modtools -7): no modtools mint.
# Same pkgmap as -4.
# -21 (2026-10-27): amix-dlm 4442c76 (9a7279c with a changelog on
# top; kbootset code as 74b3e79) -- the safe set also takes every
# controller module ranked at or before the root's class, so safe mode keeps
# the normal boot's card numbers (C4-4 v6, C3-5 v13; skipped on a ramdisk
# root).  First box build on gcc14-cross-amix cf461e3 (pointers in
# %a0 and %d0, structs through %a0), checked by dlm-src.sh against
# gcc14-pin.sh (the pins and the ABI self-check of TOOLCHAIN=gcc14).  Every
# object compiled by cf461e3: 143cc1d8.  amix-dlm's own build/box/kbootset
# (2c3570a3) differs in 115 bytes -- an incremental make kept bootinfo.o,
# inflate.o and manifest.o from the pre-fix compiler (e316f1b rebuilds them
# byte for byte; relinked with ours they give 2c3570a3).  Same pkgmap as -4.
# -20 (2026-10-27): amix-dlm 1da3474 (kbootset code as 093b2a7,
# the only kbootset/ change since 178a47b) -- gate 2 checks the sidecar's
# build= against the kernel's own build id (buildid on k46, kinfo_buildid
# through unix.sym on k30, leading blanks ignored; a kernel without the
# symbol is unchecked): "is not the kernel's own build id".  boot1
# c6c380ee, boot2 61b3feb0 and modadmin 0518fb28 byte-identical at 1da3474.
# -19 (2026-10-27): amix-dlm 178a47b (kbootset code as fa7a4ab,
# the only kbootset/ change since d227dbf) -- a module whose depend= names
# a module the generation lacks is left out of gate 2's import check, so
# gate 3 says "depends on <m>, which is not in the generation" instead of
# "it needs a newer kernel cut".  boot1 c6c380ee, boot2 61b3feb0 and
# modadmin 0518fb28 byte-identical at 178a47b (no loader/modtools mint).
# -18 (2026-10-27): amix-dlm d227dbf (kbootset code as 101e9a3)
# -- gate 2 checks every module's imports against the kernel's symbol
# block (the sidecar's ksym=, found by binding a copy with ax_rel as boot2
# does): a name neither the block (at the module's tier) nor a module it
# depends on provides refuses the generation at compose time, naming the
# missing names and "it needs a newer kernel cut" (C3-3 v7, spec 40
# sec 3.1/7).  boot2 61b3feb0 and modadmin 0518fb28 unchanged at d227dbf.
# -17 (2026-10-27): amix-dlm 33ea0c7 (kbootset code as 5d3d988)
# -- reads a module's fs= (C4-6 sec 3) and promotes the rootfs's
# boot-class module to a root record on a generation rooted on that fs
# (C4-4 v5 sec 1.3, core 0043); `media --ramdisk` defaults to root ramdisk,
# swap none, and marks the module owning b:20 safe=1 (57b3832);
# gate 4 refuses a root-class generation whose kernel arena is not
# 16-aligned (a829c44); loader-min 3 as -16.  Same pkgmap as -4,
# including /var/kbootset.
# -16 (2026-10-26): amix-dlm f340556 (kbootset code as f5dedff) -- root-class
# modules compose as root records (`module <name> root ... bss= match=
# safe=1`); a generation that carries one needs loader version 3
# (AX_LOADER_ROOT, gate 7); a root module for a controller the kernel's
# sidecar root= names is refused at gate 3 (two drivers on one board).
# Same pkgmap as -4, including /var/kbootset.
# -15 (2026-10-26): amix-dlm 594731b (kbootset code as 35dd599)
# -- `media --cd`/`--floppy` runs gate 3 on the root controller only (C2-4
# v11 sec 13); `namelist` writes /stand/unix 0644 whatever the umask
# (dcc681b).  Equal to amix-dlm's own build/box/kbootset (d44f6a32).  Same
# pkgmap as -4, including /var/kbootset.
# -14 (2026-10-26): amix-dlm c6ad5bd (kbootset code as 72ed9c2)
# -- deflates on the box with its own encoder, so `--spec z=deflate`
# works; with -13's read-only-medium boot.  Equal to amix-dlm's own
# build/box/kbootset (9acb9add).  Same pkgmap as -4, including
# /var/kbootset.  -13 (d814da1, e56172b6) was never staged.
# -13 (2026-10-26): amix-dlm d814da1 (kbootset code as ccad712)
# -- a boot from a read-only medium (AXL1 flag 0x08: the CD, the floppy
# pair): mark-good marks nothing, retry does nothing, status says the
# medium booted; the namelist comes from the installed kernel when its
# build id is kinfo's (C2-4 v10 sec 13).  Equal to amix-dlm's own
# build/box/kbootset (e56172b6).  Same pkgmap as -4, including
# /var/kbootset.
# -12 (2026-10-26): amix-dlm af363be (kbootset code as 9763024) --
# `kbootset namelist` writes /stand/unix, the booted kernel's namelist
# (C2-4 v9 sec 12); a brel's unix.sym is read as C2-3 v6 sec 2.1 states it
# (ET_EXEC, st_value the address at bind 0, NOBITS sections by name).
# Equal to amix-dlm's own build/box/kbootset at 9763024.  Same pkgmap as -4,
# including /var/kbootset.  (13a8336's build, 4a09a6dd, read unix.sym
# st_value plus sh_addr and was never shipped.)
# -11 (2026-10-26): amix-dlm f5ce731 (b61ab31 with a changelog
# on top) -- gate 2 refuses a module kernel whose sidecar has no abi=
# (C3-3 v4); gate 6 counts an ET_REL kernel's bss from its section headers
# (6b2d669).  Equal to amix-dlm's own build/box/kbootset at f5ce731.  Same
# pkgmap as -4, including /var/kbootset.
# -10 (2026-10-26): amix-dlm 42df482 (code as a64aee1) --
# `kbootset media` composes the installed module packages into the
# medium's pristine generation as `build` does (gates 1-3, parameters).
# Equal to amix-dlm's own build/box/kbootset at a64aee1.  Same pkgmap as
# -4, including /var/kbootset.
# -9 (2026-10-26): amix-dlm a71a875 -- `build` composes module
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
KB_DLM_COMMIT=e6dd2ac
KB_SHA=c3c59269be86e71dbdc067a55d1578e64d787074aaa00c44bda432538b0eb84d
# kbootset(1M) and its whatis line, from the same commit (kernel/dlm/man)
KB_MAN_SHA=794c34f828302d45d37d3911ae942ccdb529b7bb1c11352bca268f4da6a3fd41
KB_WHATIS_SHA=b80d0af059afa64cee8c6d3f154c677064b223e7ce2d84138cd5f4a564c6445a

# the rc scripts, from the same commit (kernel/dlm/kbootset/rc)
KB_RC_KBNAMELIST_SHA=4594a81878859a1738b11f1c389f5e7a624bc8a8a5346781f2f88d150c9a4503
KB_RC_KBMARKGOOD_SHA=1c089c0f93e5f3ee2f962e55b59bb3ba326355ca69a6f535f0668fe891c59a04

KB_VERSION=1.1.0.261104-39
KB_SOURCE_EPOCH=1793750400
