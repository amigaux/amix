# C3-4 — the arena directory `AXA1` and the manifest copy, version 1

- **Status:** agreed 2026-10-26 (orchestrator), version 1. Other repositories build against this text; a change from here is a contract change with a version bump.
- **Implements:** `docs/spec/10-boot-loader.md` §5.3, §6;
  `30-module-core.md` §2 patches 2, 16 and 17, §3
- **Written by:** boot2, loader version 2 (S3-15)
- **Read by:**
  - the module core (S3-07, S3-08; the root modules from stage 4);
  - `kinfo`, nothing (the manifest's generation is already in `AXL1`).
- **Reserved by:** the module kernels, which give the arena's zero block
  its offset and capacity (C3-3)

## 1. Where

The arena is a zero-filled block in the kernel's `.data`. Its image offset
and capacity are in the identity record and the manifest's `arena` line
(C3-3). boot2 writes into it after it has relocated the kernel and checked
the identity record, and before the hand-off copy. The kernel never
allocates it.

## 2. Layout (big-endian; offsets from the arena's start)

```
0        the directory: header (32 bytes) + count × entry (48 bytes)
D        the manifest copy, verbatim, D = 32 + 48 × count
P        the parameter strings, P = D + manifest length rounded up to 4
M...     the root-class modules' bytes (stage 4), each starting at an
         absolute address that is a multiple of 16
```

Header:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `AXA1` |
| 4 | 4 | version 1 << 16 \| 32 (header length) |
| 8 | 4 | check: the header's and the entries' longwords sum to zero |
| 12 | 4 | count of entries; 0 in stage 3 |
| 16 | 4 | the manifest copy's offset, D |
| 20 | 4 | the manifest copy's length in bytes |
| 24 | 4 | bytes used from the arena's start, ≤ the capacity |
| 28 | 4 | the generation id the manifest describes (as in `AXL1`) |

Entry, one per root-class module placed:

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | module name, NUL-padded (≤ 14 characters) |
| 16 | 4 | offset of its bytes from the arena's start |
| 20 | 4 | length in bytes, decompressed |
| 24 | 4 | class: 1 root (the only class the loader places) |
| 28 | 4 | CRC-32 of the bytes, as the manifest gives it |
| 32 | 4 | flags: 0x1 placed by a matched key; 0x2 forced by the menu; 0x4 a safe-mode member |
| 36 | 4 | offset of its parameter string from the arena's start, 0 if none |
| 40 | 4 | length of the parameter string |
| 44 | 4 | 0 |

A parameter string is the module's `param` records from the manifest,
`name=value` separated by single spaces, without the `<module>.` prefix.

## 3. The manifest copy

The manifest copy is the manifest boot2 booted, byte for byte, including
its `end crc32=` line. It is the module core's trust anchor. Every later
load is checked against it, never against a file on the root filesystem
(30 §2 patch 17):
- a module loads only if a `module` record names it;
- its file at the record's `path=` must have the record's SHA-256.

**The core's rules:**
- At `dmainit` it checks the header (magic, version, check, all offsets
  and lengths inside the capacity) and the copy's own `end crc32=`.
- It then treats the arena as read-only.
- If either check fails, or there is no `AXA1` (a module kernel booted by
  a loader older than version 2, or by the stock loader), it loads no
  module and prints:
  `dlm: no valid arena directory; modules are refused this boot`.
  The floor boots as always.
- The development-load flag in `AXL1` (10 §6, §7.4) lifts the membership
  and SHA-256 rule, and only that. It is printed at boot and at every load
  it permits.

## 4. Stage 3

Stage 3 kernels get a directory with `count` 0, the manifest copy, and no
modules. boot2 still checks the capacity: with a manifest larger than the
capacity minus 32 it refuses the generation with L5 (10 §9), giving the
needed and the available bytes.

Stage 4 adds the entries and the module bytes without changing this
layout.

## 5. Settled at agreement

- The header and entry layouts, the 16-byte absolute alignment of module
  bytes, and the parameter-string form.
- The manifest copy as the only reference for membership and SHA-256.
- No valid `AXA1` means no modules this boot, and development load cannot
  replace a missing directory.
- `AXA1` version 1 serves stages 3 to 5. A change is a version bump that
  both boot2 and the core check.
