# Changelog

## 2026-10-31 — random: the package recipe random-k30 / random-k46; no credit lines (948305e, 69afdfa)

kernel/modules/random/pkg (P-38 S3.3), kmodpkg with KM_ROOT the checkout: it ships the object, modreg, /dev/random and
/dev/urandom (c 48 0/1, class random), randseed with S21/K02 copies, the pages random(7) and randseed(1M) under
/opt/amix/man, and whatis.d/<PKG>. Trial roll random30 b2b39b83, random46 934be87a, reproducible; rolling in make dist
waits for three build/pkg fixes. The random module is new code: its credit lines are removed (owner).

## 2026-10-31 — random 1.0.0-1: /dev/random and /dev/urandom as a module (3d4a48d)

A demand-class module for k30 and k46: ChaCha20 (RFC 8439) with fast key erasure, rekeyed after every read and every
64 KiB; it mixes in writes and a sample of lbolt, VHPOSR and the CIA timer bytes at load, open and read. c 48 (dlm
a8719fb), unload never. randseed (S21/K02) keeps a 512-byte seed across reboots. Pages random(7) and randseed(1M). The
interface follows isoriano's random-amix; the code is new. Objects k30 680d9752 / k46 f223164c, built on the kit at
7a68948; hosttest 442 checks, rctest 8. Loads only on cuts made from a kit carrying c 48 (k30 -64, k46 -53).

## 2026-10-31 — monsw.h: SETCFG comes from /etc/display's monsw at boot (a56cf4b)

include/sys/monsw.h's comment names /etc/display's monsw (else the older /etc/monsw), written in at boot by
/etc/rc2.d/S20monsw. Comment only; the kit's copy follows at its next rebuild, and the module objects are unchanged.

## 2026-10-31 — monsw: monswctl, the boot step and the pages move into kernel/modules (36a3004)

monsw/tool/monswctl.c is copied from kerntools tools/monsw (7996e07) with only comments changed; the cross build
b1915b96 equals kerntools' pin. rc/monsw (/etc/init.d/monsw, S20monsw) sets /etc/display's monsw, else /etc/monsw with
a log line naming the older file, else nothing so the card's seed applies, and never fails the boot (P-36 W9). Pages
monsw(7) and monswctl(1M). tooltest.sh 35 checks. Module objects unchanged: monsw 1f53a31b / 962709ca.

## 2026-10-29 — The prose names the monorepo (cc5fe5d)

READMEs and source headers say kernel/modules, kernel/dlm and github.com/amigaux/amix instead of the old standalone
repos; contract citations kept. The cdfs pin is noted as arriving with the fork's move. monsw README: kabi k30.1.2 /
k46.1.2, what the current kit builds. Objects unchanged: monsw 1f53a31b / 962709ca, ramdisk 5523d853 / 054467f6.

## 2026-10-29 — The module builds find the kit in the same repository (12f964c)

`DLM ?= $(abspath $(TOP)/../dlm)` in monsw and ramdisk (was ../amix-dlm); READMEs name kernel/dlm and kernel/modules/include.
Built with no override: monsw k30 1f53a31b / k46 962709ca (kabi tag 1.2: the kit's KABI_MIN since dlm 0edbd0f; the
catalog's 01a40342 / 2c2760e9 carry 1.0, code otherwise identical), ramdisk 5523d853 / 054467f6 (= the catalog).

## 2026-10-29 — Moved into the amix repository as kernel/modules by a subtree merge of amix-modules master dc433b6 (11 commits, hashes kept); the README notes cdfs as a pinned fork (311ed90)

## 2026-10-26 — ramdisk requires kabi 1.2; VSECT1/phystokv from the kit (cad5ff3)

iodone and ramdisk_image are kabi minor 2 (amix-dlm 42411c4); the local VSECT1/phystokv fallbacks are gone now that the
kit's amixddi.h provides them on both lines (8b0e43e); the host test's stub header matches. Objects byte-identical on the
1.2 kits: k30 5523d853, k46 054467f6; modcheck ok both lines (2944 B); hosttest 81 checks per page size.

## 2026-10-26 — ramdisk 1.0.0-1: the root-class RAM disk module (80d8b2e) — builds only against a kit with iodone

Block driver on major 20 (C4-2 §8, C4-3 §4; S4-34). Unit 0 = the loader-placed miniroot from `ramdisk_image` at
phystokv of its physical address (identity below VSECT1; never allocated or freed; writable). Units 1–2 = kmem scratch
disks allocated at first open in KM_NOSLEEP pieces ≤ 256 KiB, freed at last close; `size1`/`size2` (default 512/2048 KiB,
max 16384). Pinned, no _halt, no root_defer; _load calls only ramdisk_image and printf. .text 1544/.data 372/.moddata
206/.bss 816, file 4630 B, both lines. Host test 81 checks per page size, mutation-checked. Blocked on amix-dlm: `iodone`
in the DDI (modfix: undefined) and modcheck accepting a block-only driver (drvmajors demands a character major).

## 2026-10-26 — monsw 1.0.0-2 (b0f75a4)

A packaging release so S3-45 can test `apkg upgrade` of a kernel module: module/VERSION 1.0.0-2; README gains "Size and
memory" (C3-1 §6 / C3-6 §1): file 5197 B, image 2200 B (.text 1584, .data 432, .moddata 161, .bss 16), load working set
about 15 KiB, no kmem requests. Objects byte-identical to 1.0.0-1 (k30 01a40342, k46 2c2760e9); modcheck ok both lines.

## 2026-10-26 — monsw: a config that is not a number stays unset (6c407b7)

A `config` parameter that is not a number is left unset: one console line "monsw: config '<text>' is not a number; unset",
and root's MONSWIOC_SETCFG stays open (the seed and SETCFG order applies). A decimal that is not a valid bit sum is still
forced, reported once and taken as 0 (SETCFG EBUSY). Host test 96 checks. Objects k30 01a40342, k46 2c2760e9 (5197 B).

## 2026-10-26 — monsw: the console monitor switch as a module for k30 and k46 (b954ce9)

The source comes from amix-040-060-port ab53a85 src/monsw.c with the module glue under MONSW_MODULE; the static object is
byte-identical to the port's (59c76b95). include/sys/monsw.h is published, byte-equal to the port's. Module: class demand,
c:52, unload=never, param config:int:-1:-1:51; imports copyout, drv_priv, printf (+ the wrapper's mod_drvops); exports the
monsw_* API. modcheck ok on both lines (k30 7a5e2ff3, k46 82966137; 5109 B). Host test 87 checks; monsw/test/monswtest.c is
the /dev/monsw instrument. Package version monsw/module/VERSION 1.0.0-1 (monsw30 / monsw46; contents in monsw/README.md).
