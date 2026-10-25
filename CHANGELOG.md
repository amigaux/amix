# Changelog

## Unreleased

## 2026-10-25 — boot1 stops on failure (3081ee1)

boot1 stops with a message on the serial port instead of returning failure to the strap: on the Z3660 boot ROM chain a
failure return raised AN_BootError and reset the machine about every 14 s, and a reset loop can leave a real 68060 dead until
a power cycle (M-LD3 bench half, from the S1-16 run). Spec change after freeze: 10 §3.1 step 6, failure rows B1/B3, the menu's
r key; OQ-10.1 narrowed to the other boot ROMs. boot1 884 of 1008 bytes. Also d1782bd: assembler comments no longer read as
line markers (binaries unchanged).

## 2026-10-25 — loader stage 1, items S1-07..S1-15 (c4893cf..fd64097)

Raw deflate decoder; generation selection (try-once, one-shot requests, fallback order); kernel relocator for ET_REL, brel and
ET_EXEC with the stock binding rules, bounds-checked; bootinfo, RTH1/RTO1 and AXL1 builders; boot2 linked at 0 and
self-relocating (b2link); boot2 itself (CPU probe, store reads through a chip bounce buffer, manifest, inflate, relocation,
bootinfo with the RTH1 boot-node walk, 68030 and 68040/060 hand-off); menu with rollback key, safe-mode and development-load
toggles, screen and serial console, keyboard, mouse and serial input; multi-volume floppy stores; mkstore stores members
deflated and builds packed floppy pairs. boot2 25 824 B + 2 336 bss of 28 672. 308 host checks; the real 1.0 floppy kernels
inflate byte-identical; the relocator matches kerntools' elf2brel on three real kernels. Nothing has run on an Amiga yet.

## 2026-10-25 — stage 1 plan and the first loader code (f4081f5..b029dbe)

Stage 1 plan (docs/plan/stage-1.md: 28 items plus 3 that wait for the CD fork, each with owner repo, evidence class, what
it blocks and an estimate). Toolchain pin with a presence check (gcc-cross-amix 8949028: GCC 2.7.2.3, binutils 2.8.1);
shared C89 store-format, CRC-32 and GMF1 manifest code with 94 host checks; boot1 in position-independent assembly,
784 of 1008 bytes, under a build gate on size and relocations, framed so the stock 1992 bootblock also passes the gate;
mkstore/lsstore host tools with a store round-trip test. Spec change after freeze: boot1 reports failures on the serial
port only (screen output needs graphics.library, which does not fit in 1 KB). boot1 not yet run on any Amiga (S1-19).

## 2026-10-25 — M-NET1a/b measured; S0 frozen (4d9c5e6..2506516)

Netinstall miniroot (installer + network userland + HTTP apkg): 2 562 866 B (k30) / 2 468 595 B (k46) raw, 959 940 B /
924 595 B deflated with the unused engine tools dropped; with a deflated kernel a floppy pair keeps 16.1 % / 13.0 % margin,
so netinstall form A (floppy pair) is chosen. Record in docs/measurements/, script tools/measure/m-net1.py. S0 freeze
condition met; the specification is frozen at this commit (orchestrator, 2026-10-25).

## 2026-10-25 — S0 revised after review T-52 (f4d1b1f..026215c)

CD boot written as two options for the owner (RDB-style disc, or a loader started from the disc's AmigaDOS startup);
boot1 counts loader-trial attempts in a tally block; the loader record gains root and swap selectors (RAM-disk root on
block major 20, replacing stock ram.c); the kernel loads only modules of the booted manifest, a development override is
printed at boot; the core tier exports bdevsw/vfssw/nfstype; Z3660 keys corrected to 144b:01; four-card minor encoding and
the drivers to rebuild listed, board sets of record and the card-number gate defined; our line rebuilds the 040/060 base
without ufs/s5; the ABI kit publishes the stock headers (built from the pinned sysroot, never tracked); S0 freezes on
M-NET1a/b, deviation DV-1 recorded.

## 2026-10-25 — bootstrap and the S0 specification (ce351f8..5cd25a7)

Repository bootstrapped (MIT licence, README, docs layout). S0 specification for Amix 1.1 loadable kernel modules in
docs/spec/: our own boot loader (boot1/boot2, boot store, ISO9660, generation manifest, module arena, menu, rollback,
safe mode, try-once), .moddata v2 and the kabi rule with the pinned kernel-space toolchain, the ashnazag DLM core as a
patch queue, the four-controller sd contract, filesystems as modules, generations and kbootset, the 1.1 disk layout and
the upgrade install, media (disk/SD, floppy pair on both lines, bootable CD, netinstall, tape, emulation), signing, the
static floor, the proof stages and the measurement list.
