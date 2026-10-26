# C2-1 — the `kinfo` record, version 3

- **Status:** agreed 2026-10-25 (orchestrator), version 2 (2026-10-26): the memory sizes at 528 and 532, so the module list moves by 8 (gate 6, 40 §3.1); version 3 (2026-10-26): the loader's bootdata block at 536, where the kernel was bound, for the namelist (40 §4.2), so the module list moves by 40. Other repositories build against this text; a change from here is a contract change with a version bump.
- **Implements:** `docs/spec/40-generations-and-composer.md` §4, `70-static-floor.md` (`kinfo` in the floor), `20-module-format-and-abi.md` §6 (major 53)
- **Built by:** the kernels of both lines: the 040/060 families (amix-040-060-port) and the 030 families (amix-kerntools), stage-2 static kernels included (S2-10, S2-11)
- **Read by:** `kbootset` (the booted generation, the boot disk, the namelist), apkg 0.3 (line, kabi), the installer

## 1. The device

- A character device, major 53, minor 0, node `/dev/kinfo`, mode 0444.
  It is present in every 1.1 kernel, in safe mode too.
- The record is a byte array of `length` bytes (§2):
  - `read(2)` at offset `o` returns the bytes from `o` up to `length`,
    and 0 at the end;
  - `lseek(2)` works;
  - `write(2)` fails with `EPERM`.
- The kernel builds the record on the first open, from its own copy of
  `bootinfo`. Only the module list (§2, offset 576) changes after that.

## 2. Layout (big-endian; all offsets in bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `KIF1` |
| 4 | 4 | version 2 << 16 \| `length` |
| 8 | 4 | check: all longwords of the record sum to zero (as RTH1 and AXL1) |
| 12 | 4 | CPU as the kernel runs it: 30, 40 or 60 |
| 16 | 4 | line: 30 or 46 |
| 20 | 4 | `AttnFlags`: from the AXL1 record when there is one, else 0 |
| 24 | 24 | kabi tag, NUL-padded (C2-3: the kernel's sidecar `kabi=`; `static` on a stage-2 static kernel) |
| 48 | 32 | build id, NUL-padded: the kernel's buildid string (`68060-261021-NN`), which `uname -m` shows (C2-3 `build=`) |
| 80 | 4 | flags: 0x1 an AXL1 loader record was found; 0x2 an RTH1 record was found; 0x4 safe mode (from AXL1); 0x8 (version 3) the bootdata text vaddr differs from the kernel's own `stext` (a loader fault; `stext` is at `.text`+0 in the 1.1 kernels, and a kernel where it is not leaves the bit clear) |
| 84 | 124 | the AXL1 loader record as booted, verbatim (`10-boot-loader.md` §6), or zeros |
| 208 | 56 | the RTH1 record as booted, verbatim, or zeros |
| 264 | 4 | number of boards (at most 16) |
| 268 | 16 × 12 | boards in AutoConfig order: manufacturer (2), product (1), 0 (1), board base (4), board size (4) |
| 460 | 4 | number of sd cards (at most 4) |
| 464 | 4 × 16 | sd card table: card number k, the sd card index (the device digit `c` of `cNdMsK` is 8k + unit) (4), controller id (§2.1) (4), board base, 0 for the motherboard (4), flags: 0x1 motherboard controller (4) |
| 528 | 4 | fast memory in bytes: all non-chip RAM the kernel uses |
| 532 | 4 | chip memory in bytes |
| 536 | 40 | the loader's bootdata block, verbatim from the kernel's copy of `bootinfo` bytes 0x650–0x677 (`10-boot-loader.md` §2.2): entry, then text vaddr, offset, size, rodata vaddr, offset, size, data vaddr, offset, size (4 each). boot2 and the stock loader's `rel()` both fill it, so static kernels carry it too; a `brel` has only entry and the text triple, the rest 0 |
| 576 | 4 | number of loaded modules (0 on a static kernel), at most 32 |
| 580 | n × 32 | per module: name NUL-padded (24), load address (4), size (4) |

`length` = 580 + 32 × modules, so at most 1 604 bytes. With more than 32
modules loaded, the record lists the first 32 the core reports
(`dlm_kinfo_list`, load order) and the count says 32.

### 2.1 Controller ids

- A Zorro board's id is manufacturer << 16 | product << 8. Its manufacturer
  is never zero and its low byte is always 0.
- A motherboard controller's id has a zero manufacturer and a code:

| Id | Controller |
|---|---|
| 1 | A3000 WD33C93 (`a3000-wd`) |
| 2 | Gayle IDE (`gayle`) |
| 3 | A4000T onboard 53C710 (`a4000t-710`) |
| 4 | the Z3660 window (`z3660-window`) |

The two kinds cannot collide. kbootset turns an id into the match key the
gates use (C2-3, 10 §5.1):
- `zorro:<manufacturer as 4 hex digits>:<product as 2 hex digits>` for a
  board;
- `mobo:<name>` with the name in brackets above for a motherboard
  controller.

The booted generation's id and state are
the AXL1 fields at record offsets 84 + 28 and 84 + 32 (`10-boot-loader.md`
§6). The boot device is AXL1 unit, partition start, board base and id, at
84 + 44 onwards.

## 3. What each reader takes from it

| Reader | Fields |
|---|---|
| `kbootset mark-good` | AXL1 generation id; AXL1 boot1 choice (bit 9 set: the secondary boot2 ran, so the loader trial is not accepted) |
| `kbootset` boot-disk finding (40 §5) | AXL1 boot device + the sd card table → card and unit → the slice whose start is the AXL1 partition start; RTH1 boot fields when there is no AXL1 |
| `kbootset` gates 3, 6, 10 | the card table and the board set (closure); the fast memory (memory gate); the line (line gate) |
| `kbootset` namelist (40 §4.2) | the bootdata block: text vaddr is the bind address; rodata and data vaddr check the layout the namelist computes |
| apkg 0.3 pre-flight | line, kabi |

## 4. Settled at agreement

- Major 53 and `/dev/kinfo`. The port and kerntools stations confirm that
  nothing in their trees uses 53 before they build.
- The board entry is 12 bytes as above.
- At stage 2 the card table is filled from the static drivers' own card
  numbering. The four-card sd contract (stage 4) defines it from then on.
- From the port station's implementation (wording, version 2 unchanged):
  - the motherboard ids of §2.1;
  - the build id is the buildid string that `uname -m` shows;
  - the card number is the sd card index;
  - `AttnFlags` comes from AXL1;
  - the record is built on first open.
- The module entry stays name, address and size. The header's length field
  leaves room to grow.
- From the port station's implementation (2026-10-26; wording, version 2
  and the record's version field unchanged): the module list holds at most
  32 entries, as the port's kinfo builds it. Readers size their buffer for
  1 564 bytes (kbootset reads 2 048). Version 3: 1 604 bytes.
- When the module list is current (2026-10-26; wording, version 2
  unchanged): a read at offset 0 returns the list as it is at that read,
  and so does the open that precedes it. A sequential read that continues
  past offset 0 may see that snapshot (k30's kinfo keeps it) or a fresh
  one (the port's refreshes on every read). A reader that wants one
  consistent record reads it whole, in one read from offset 0, as
  kbootset does.
- Version 3 (2026-10-26, from S3-B5: the stock `nlist` consumers read a
  kernel image whose symbols are not the booted kernel's): the bootdata
  block at 536, copied as the AXL1 and RTH1 records are. For a `brel`
  boot2 fills only entry and the text triple (the text is the whole image);
  for an ET_REL kernel all three.
- **Readers and versions.** A reader takes the version from offset 4 and
  reads version 2 (the module count at 536, the list at 540; the
  kernels up to build -56) and version 3 (the count at 576, the list at
  580). It refuses any other version. The namelist's bind address comes
  only from a version 3 record whose flag 0x8 is clear; with a version 2
  record kbootset writes no namelist and says so.
- **Check.** The record sums to zero over its `length` / 4 longwords (145
  with no module, 401 with 32), as before.

