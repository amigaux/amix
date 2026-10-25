# C2-1 — the `kinfo` record, version 1 (draft)

- **Status:** draft for agreement, 2026-10-26
- **Implements:** `docs/spec/40-generations-and-composer.md` §4, `70-static-floor.md` (`kinfo` in the floor), `20-module-format-and-abi.md` §6 (major 53)
- **Built by:** the kernels of both lines: the 040/060 families (amix-040-060-port) and the 030 families (amix-kerntools), stage-2 static kernels included (S2-10, S2-11)
- **Read by:** `kbootset` (the booted generation, the boot disk), apkg 0.3 (line, kabi), the installer

## 1. The device

- A character device, major 53, minor 0, node `/dev/kinfo`, mode 0444.
  It is present in every 1.1 kernel, in safe mode too.
- The record is a byte array of `length` bytes (§2):
  - `read(2)` at offset `o` returns the bytes from `o` up to `length`,
    and 0 at the end;
  - `lseek(2)` works;
  - `write(2)` fails with `EPERM`.
- The kernel builds the record once at boot, from `bootinfo` before that
  memory is reused. Only the module list (§2, offset 528) changes after
  boot.

## 2. Layout (big-endian; all offsets in bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `KIF1` |
| 4 | 4 | version 1 << 16 \| `length` |
| 8 | 4 | check: all longwords of the record sum to zero (as RTH1 and AXL1) |
| 12 | 4 | CPU as the kernel runs it: 30, 40 or 60 |
| 16 | 4 | line: 30 or 46 |
| 20 | 4 | `AttnFlags` |
| 24 | 24 | kabi tag, NUL-padded (C2-3: the kernel's sidecar `kabi=`; `static` on a stage-2 static kernel) |
| 48 | 32 | build id, NUL-padded: the version field of `uname -v` (C2-3 `build=`) |
| 80 | 4 | flags: 0x1 an AXL1 loader record was found; 0x2 an RTH1 record was found; 0x4 safe mode (from AXL1) |
| 84 | 124 | the AXL1 loader record as booted, verbatim (`10-boot-loader.md` §6), or zeros |
| 208 | 56 | the RTH1 record as booted, verbatim, or zeros |
| 264 | 4 | number of boards (at most 16) |
| 268 | 16 × 12 | boards in AutoConfig order: manufacturer (2), product (1), 0 (1), board base (4), board size (4) |
| 460 | 4 | number of sd cards (at most 4) |
| 464 | 4 × 16 | sd card table: card number (the `c` of `cNdMsK`) (4), controller id = manufacturer << 16 \| product << 8, or a motherboard id (4), board base, 0 for the motherboard (4), flags: 0x1 motherboard controller (4) |
| 528 | 4 | number of loaded modules (0 on a static kernel) |
| 532 | n × 32 | per module: name NUL-padded (24), load address (4), size (4) |

`length` = 532 + 32 × modules. The booted generation's id and state are
the AXL1 fields at record offsets 84 + 28 and 84 + 32 (`10-boot-loader.md`
§6). The boot device is AXL1 unit, partition start, board base and id, at
84 + 44 onwards.

## 3. What each reader takes from it

| Reader | Fields |
|---|---|
| `kbootset mark-good` | AXL1 generation id; AXL1 boot1 choice (bit 9 set: the secondary boot2 ran, so the loader trial is not accepted) |
| `kbootset` boot-disk finding (40 §5) | AXL1 boot device + the sd card table → card and unit → the slice whose start is the AXL1 partition start; RTH1 boot fields when there is no AXL1 |
| `kbootset` gates 3, 10 | the card table and the board set (closure); the line (line gate) |
| apkg 0.3 pre-flight | line, kabi |

## 4. To agree

- the major and the node name;
- the board-entry shape (12 bytes);
- the card table as the four-card sd contract will define it at stage 4
  (stage 2 fills it from the static drivers' own card numbering);
- whether the module entry needs more than name, address and size.
