# Changelog

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

## Unreleased

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
