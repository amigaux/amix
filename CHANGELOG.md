# Changelog

## Unreleased

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
