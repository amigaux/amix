# C4-4 — the arena filled: what boot2 places and the core links, version 1

- **Status:** draft 2026-10-26 (amix-dlm), for the orchestrator's
  agreement. Once agreed, other repositories build against this text, and
  a change is a contract change with a version bump.
- **Implements:** `docs/spec/10-boot-loader.md` §5.1 (`module … root`),
  §5.3, §7.4 (safe mode), §9 (L3, L5, L7); `30-module-core.md` §2 patches 2
  and 16, §3 (`marc_root`); `70-static-floor.md` §4
- **Layout:** C3-4 version 1, unchanged. This contract fills it; it adds
  no field, so `AXA1` stays version 1.
- **Written by:** boot2 and `amix-cdboot` (S4-10); `kbootset`, which
  writes the manifest's `module … root` records (S4-12)
- **Read by:** the module core at `marc_root` (S4-01, S4-04); `kinfo`,
  nothing new

## 1. What boot2 places

Every `module <name> root …` record of the booted manifest whose `match=`
is satisfied, in manifest order, and nothing else. A record matches when
any one of its keys does:

| Key | Satisfied when |
|---|---|
| `zorro:MMMM:PP` | a board with that manufacturer and product is in the board list boot2 hands the kernel (`bootinfo.autocon[]`, built from the ConfigDev list) |
| `mobo:<name>` | always. The name is a registry probe (20 §6); the module's gated probe decides in its `_load`, which returns `ENXIO` when the controller is absent |
| `always` | always |

A zero key never reaches boot2: `modcheck` and `kbootset` refuse it
(C3-1 §3). A key boot2 does not know makes the record unmatched, and
boot2 prints the key.

A placed module's directory entry has class 1 and flag 0x1. Flag 0x2
("forced by the menu") stays reserved: no 1.1 path forces a module.

### 1.1 Order

`kbootset` writes the root-class records in dependency order: a module
after every module it names in `depend`. boot2 keeps that order in the
directory. The core links the entries in directory order, so a
dependency is always linked first.

### 1.2 Bytes

Each placed module is decompressed (raw or `z=deflate`, 10 §5.5) to an
address that is a multiple of 16, after the parameter strings (C3-4 §2).
Its CRC-32 over the decompressed bytes must equal the record's `crc32=`.
Otherwise L3 names the module and boot2 goes on as for L2 (10 §9): the
next generation in the order of 10 §7.2, and the menu when none is left.
**This is how a damaged root module selects the menu** (80 §2).

If the directory, the manifest copy, the parameter strings and the placed
modules exceed the arena's capacity, boot2 refuses the generation with
L5, giving the needed and the available bytes (C3-4 §4).

## 2. Safe mode

In safe mode (the menu's `s`, 10 §7.4) boot2 places only:
1. **the root controller's module**, found from the manifest's `root`
   record:
   - `root sd id=<id> …` with a Zorro id (manufacturer non-zero, C2-1
     §2.1): the root-class module whose `zorro:` key equals that id;
   - with a motherboard id (codes 1–4, C2-1 §2.1): the root-class module
     whose `mobo:` key names that controller (`a3000-wd`, `gayle`,
     `a4000t-710`, `z3660-window`). The A3000 WD33C93 is on the floor,
     so no module is placed for it;
   - `root ramdisk`: the module named `ramdisk`;
2. **the root filesystem's module**: the root-class module whose name is
   the manifest's `rootfs` (`ufs`, `s5` or `cdfs`);
3. the root-class modules those two name in `depend`.

Those modules carry flag 0x4 in every boot, not only in safe mode, so the
kernel can tell the safe-mode set (`kinfo`, the core's console lines). In
safe mode the loader record's safe flag is set (10 §6), and the kernel
loads no boot- or demand-class module (70 §4).

## 3. L7

boot2 prints L7 and the boards it saw when the `root` record names a
controller that is neither on the floor nor the controller of a placed
module. Then it boots anyway: the kernel names the missing controller
when the root does not mount (10 §9).

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
   copy with the same name and CRC-32;
3. it relocates the module in place (patch 2): the bytes stay in the
   arena, and nothing is allocated for the image or freed;
4. it runs `_load` with the entry's parameter string, in the
   `marc_root` context (C3-6 v4 §1.3: level 7, the clock stopped,
   `KM_NOSLEEP` only);
5. a `_load` that returns `ENXIO` leaves the module unlinked and silent,
   as at a boot-class load. Any other error prints
   `dlm: root module %s: error %d` and unlinks it. Either way its
   registrations are undone first (C3-6 v3).

In safe mode the core links exactly the entries with flag 0x4. A module
the core does not link stays in the arena as dead bytes until the next
boot.

## 5. Not in this contract

- The RAM-disk image (C4-3): it is placed outside the arena.
- How a controller registers once linked (C4-1).
- The deferred self-test point (S4-05, C4-2).
