# C4-4 — the arena filled: what boot2 places and the core links, version 4

- **Status:** agreed 2026-10-26 (orchestrator), version 1; version 2
  (2026-10-26, option A of S4-01's design): each root module's NOBITS and
  COMMON lie in a zeroed tail boot2 reserves behind its file, from the
  record's `bss=` (§1.2, §4); version 3 (2026-10-26, from S4-10's
  measurement): boot2 places every root record and the core evaluates
  `match=`; `kbootset` marks the safe set (`safe=1`) and checks the whole
  root set against the capacity; boot2 writes no parameter strings; L7
  leaves boot2 (§1–§4); version 4 (2026-10-26, from the port's S4-22 cut):
  no root-class module for a controller the kernel drives itself (§4.1).
  Other repositories build against this text; a change from here is a
  contract change with a version bump.
- **Implements:** `docs/spec/10-boot-loader.md` §5.1 (`module … root`),
  §5.3, §7.4 (safe mode), §9 (L3, L5, L7); `30-module-core.md` §2 patches 2
  and 16, §3 (`marc_root`); `70-static-floor.md` §4
- **Layout:** C3-4 version 1, unchanged. This contract fills it; it adds
  no field, so `AXA1` stays version 1.
- **Written by:** boot2 and `amix-cdboot` (S4-10); `kbootset`, which
  writes the manifest's `module … root` records, their `bss=` and
  `safe=1` (S4-12, C3-5 version 7)
- **Read by:** the module core at `marc_root` (S4-01, S4-04); `kinfo`,
  nothing new

## 1. What boot2 places

Every `module <name> root …` record of the booted manifest, in manifest
order (in safe mode only the safe set, §2), and nothing else. boot2 does
not evaluate `match=`: **boot2 places, the core selects** (§4). The
records are only the generation's: `kbootset` composes the root-class
modules of the box's (or the medium's) controllers and filesystems, so
nothing is placed that the generation does not carry.

A placed module's directory entry has class 1 and flag 0x1. Flag 0x2
("forced by the menu") stays reserved: no 1.1 path forces a module.
boot2 writes no parameter strings (each entry's parameter offset and
length are 0). The core takes a module's parameters from the manifest
copy's `param` records, as it does for a boot-class module (C3-5 §3).

**The accepted cost.** Every root-class module of the generation is read
and placed on every boot, including the filesystems the root does not
use and the controllers the box lacks. On a disk store that is a few
hundred KB more read per boot. A floppy pair or netinstall medium
carries only its own controllers anyway. The arena holds the whole set
(M-MOD1 sized it at twice the set), and S4-70's measured number is the
check on that.

### 1.1 Order

`kbootset` writes the root-class records in dependency order: a module
after every module it names in `depend`. boot2 keeps that order in the
directory. The core links the entries in directory order, so a
dependency is always linked first.

### 1.2 Bytes

Each placed module is decompressed (raw or `z=deflate`, 10 §5.5) to an
address that is a multiple of 16, after the parameter strings (C3-4 §2).
Behind it boot2 reserves its **tail**: from the file's end rounded up to
16, the record's `bss=` bytes, zeroed. The next module starts after the
tail, rounded up to 16. A root record without `bss=` has no tail. The
directory entry's length stays the file's length; C3-4's "bytes used"
counts the tails.

The file's allocated PROGBITS sections run where they lie in it, and its
NOBITS sections and COMMON symbols lie in the tail (§4). So the module's
image is one contiguous span, from the file's start to the tail's end,
inside the arena and with its cache class (30 §8).

Its CRC-32 over the decompressed bytes must equal the record's `crc32=`.
Otherwise L3 names the module and boot2 goes on as for L2 (10 §9): the
next generation in the order of 10 §7.2, and the menu when none is left.
**This is how a damaged root module selects the menu** (80 §2).

`kbootset`'s gate 4 checks, when it composes the generation, that the
directory, the manifest copy and every root record's file and tail fit
the arena's capacity (C2-4). So boot2's L5, which refuses the generation
when they exceed it and gives the needed and the available bytes
(C3-4 §4), is a backstop.

## 2. Safe mode

`kbootset` marks the **safe set** with `safe=1` on its root records
(C3-5 §3):
1. the root controller's module, from the card that holds the root disk
   in `kinfo`'s card table (C2-1). A motherboard root's `root sd … mobo`
   record names no controller, so only `kbootset` can tell an A3000 WD,
   a Gayle and a 53C710 apart. The A3000 WD33C93 is on the floor, so no
   module is marked for it. A `root ramdisk` generation marks `ramdisk`;
2. the root filesystem's module: the module named by the manifest's
   `rootfs` (`ufs`, `s5` or `cdfs`);
3. the root-class modules those two name in `depend`.

In safe mode (the menu's `s`, 10 §7.4) boot2 places only the records with
`safe=1`. The safe set's entries carry flag 0x4 in every boot, not only in
safe mode, so the kernel can tell them apart (`kinfo`, the core's console
lines). In safe mode the loader record's safe flag is set (10 §6), and
the kernel loads no boot- or demand-class module (70 §4).

## 3. L7

L7 leaves boot2, since boot2 no longer matches anything. When the root
controller's module finds no board, or no module drives the root disk,
the kernel names the missing controller when the root does not mount
(10 §9).

## 4. The core at `marc_root`

At `dmainit` the core has checked the header and the manifest copy
(C3-4 §3). At `marc_root`, for each entry in directory order:
1. it recomputes the CRC-32 of the module's bytes and compares it with the
   entry's. On a mismatch it prints `dlm: root module %s damaged; not
   linked` and goes on with the next entry. A mismatch here means the
   bytes changed after boot2 checked them. The generation is not marked
   good, because it never reaches multi-user, and try-once and L8 return
   the box to the default generation at the next boot (10 §7.2);
2. it checks that the module is a `module … root` member of the manifest
   copy with the same name and CRC-32, and takes the record's `bss=`;
   then it evaluates the record's `match=` with the platform matcher
   `marc_post` uses (`zorro:MMMM:PP` against the board list, `mobo:` and
   `always` always). An entry none of whose keys holds is skipped
   silently;
3. it relocates the module in place (patch 2):
   - each allocated PROGBITS section runs at its offset in the file; an
     offset that is not a multiple of the section's alignment, or an
     alignment above 16, is refused (`ENOLOAD`);
   - the NOBITS sections, then the COMMON symbols, are laid into the
     tail, each aligned to its own alignment (at least 4 for a section)
     and at most 16. These are the rules `kbootset` used for `bss=`. A
     layout larger than `bss=` is refused:
     `dlm: root module %s: its bss is over the reserved %d`;
   - the relocations are applied to those bytes. The symbol, string and
     relocation tables are read in the file and never written;
   - the bytes stay in the arena, and nothing is allocated for the image
     or freed;
4. it runs `_load` with the module's parameters from the manifest copy
   (§1), in the
   `marc_root` context (C3-6 v4 §1.3: level 7, the clock stopped,
   `KM_NOSLEEP` only);
5. a `_load` that returns `ENXIO` leaves the module unlinked and silent,
   as at a boot-class load. Any other error prints
   `dlm: root module %s: error %d` and unlinks it. Either way its
   registrations are undone first (C3-6 v3).

In safe mode the core links exactly the entries with flag 0x4. A module
the core does not link stays in the arena as dead bytes until the next
boot.

### 4.1 Two drivers on one board

A root-class module for a controller the kernel still drives statically
would register the same board with sd, and both drivers would talk to
it. Three layers refuse it, each before the next:
1. **The rule, at compose time:** `kbootset`'s gate 3 refuses a
   generation with a root-class module one of whose `match=` keys the
   kernel's sidecar `root=` names: `root-class module %s is for %s,
   which the kernel drives itself`.
2. **The backstop, before `_load`:** the kernel names its built-in root
   controllers in `dlm_static_root`, a string beside the identity record
   that `tools/mkident.py --asm LINE KABI CAP ROOT` writes from the same
   `root=` list (`""` when it has none; every module kernel defines it).
   At `marc_root`, after the match, the core skips an entry one of whose
   keys is in it: `dlm: root module %s is for %s, which the kernel drives
   itself; not linked` (core patch 0037). The module's `_load` never
   runs, so the board is not touched.
3. **The last line, in sd:** a registration whose base is already a card
   is dropped (the port's sd pass; amix-kerntools' `sd.c.in` the same).

A kernel that drives a controller statically and a root module for it
are a stage-4 transition: the module replaces the static driver only in
a kernel cut without it.

## 5. Not in this contract

- The RAM-disk image (C4-3): it is placed outside the arena.
- How a controller registers once linked (C4-1).
- The deferred self-test point (S4-05, C4-2).
