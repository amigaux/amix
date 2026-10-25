# 10 — Boot loader

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §1 (own the loader: boot1 and boot2 from our source, manifest, separate files, 2048-byte blocks, menu, rollback key, tested like a driver, stock loader kept until proven), D-3 §2 (how each medium boots), D-3 §3 (both CPU lines), D-3 §6 (menu key or mouse button, one-shot previous generation, safe mode, one boot slice per disk)
- **Replaces:** P-28 D2 (no loader change; slot inside the kernel), D29/D33 (safe-mode flag as an RTO1 bit), D32 (second boot slice), D41 (no bootable CD in 1.1)

Paths are relative to the Amix project workspace (see `00-overview.md`,
"Sources"). Abbreviations: `MP/` = `tmp/2026-10-22-modules-proposal/`,
`KT/` = `amix-kerntools/`, `IN/` = `amix-installng/`, `PORT/` =
`amix-040-060-port/`.

**Clean-room rule.** The stock loader is Commodore code. Its behaviour is
documented in the project's research record and is described below where our
loader must reproduce an interface. Our loader is written from these
descriptions and from public AmigaOS interfaces; no stock source text is
copied into this repository.

## 1. What changes and what stays

| | 1.0 (stock chain) | 1.1 (this loader) |
|---|---|---|
| boot1 | stock 1 KB bootblock, never rebuilt (`MP/bootchain-facts.md` A12) | ours, hand-written assembly, ≤ 1024 B |
| boot2 | stock lineage patched in place, 8192 B slot, 76 B / 256 B free (`MP/bootchain-facts.md` B4); rebuilt only on the golden box with the 1992 compiler (B5) | ours, C + assembly built with gcc-cross-amix, self-relocating, ≤ 28 KiB |
| What is read | exactly one blob behind one info block at a fixed offset (`MP/refute-boot2-one-blob.md`, P2–P5) | a generation manifest, then the kernel and each root-class module as separate files |
| Block size | 512-byte reads only; a 2048-byte unit gets zero-block reads (`MP/refute-cd-boot-chain.md`, `MP/CLAIMS.md` C11) | every read aligned to and a multiple of 2048 bytes, so one code path serves 512- and 2048-byte media |
| Media read | raw slice / floppy | the boot store (disk, SD image, floppy) and ISO9660 (CD) |
| Choice at boot | none; root from the compiled-in device or the RTH1/RTO1 records | menu, rollback key, safe mode, one-shot previous generation, try-once fallback |
| Output | Intuition alerts, a mouse click to continue (`MP/CLAIMS.md` C15) | one line per step on the screen and on the serial port; no step waits for a mouse |

## 2. The interfaces at both ends

### 2.1 What the Kickstart strap hands boot1

Facts (all from the research record; the stock sources are referenced, not
reproduced):

- The strap reads the first two blocks (1 KB) of the boot device or
  partition and runs them as a bootblock. On an RDB disk the partition must
  be of DosType `UNI\0` (0x554E4900); Kickstart 2.0 and later boots such a
  partition exactly like a floppy (`MP/stock-ship-and-boot-facts.md:26,41`;
  `grimoire-amix/docs/how-it-works/boot-process.md:75`).
- The bootblock image starts with `DOS\0`, the bootblock checksum, a third
  longword, and code from offset 12; it ends with a trailer longword used by
  the A3000 SuperKickstart. The strap refuses a bad checksum
  (`grimoire-amix/docs/boot-disks/anatomy-boot-adf.md:49-65`;
  `KT/docs/amix-kernel-source-map.md:150,187-188`).
- Entry: register a1 points to an open `IOStdReq` on the boot device and unit;
  on Kickstart 1.4 and later `io_Offset` holds the partition start. Exec is
  alive; ExecBase is at absolute address 4 (`PORT/docs/contracts/RTH1-ROOT-HINT.md:72`;
  loader digest of the stock bootblock startup in `MP/bootchain-facts.md` A6).
- On an A3000 with SuperKickstart the bootblock runs before the operating
  system choice; the stock bootblock detects this from an `ExpansionBase`
  flag and returns into the strap so the Kickstart choice continues
  (`KT/docs/amix-kernel-source-map.md:158-161`).
- The strap picks the highest-priority boot node; boot1 never rescans
  (`grimoire-amix/docs/how-it-works/boot-process.md:169-196`). The device
  name in the mount entry is compared as a C string because Kickstart counts
  the NUL in its length (`boot-process.md:224-258`).

Our boot1 keeps the same bootblock framing (header longwords, checksum,
trailer) and reproduces the SuperKickstart return. Which header fields the
strap actually checks on each medium (floppy, RDB partition, 2048-byte CD
node) is measured, not assumed (M-LD1, M-LD2).

### 2.2 What the kernel expects from boot2

Both CPU lines' kernels expect, unchanged from 1.0 (`PORT/docs/boot-path-map.md:35-146`;
`KT/docs/boot2-040.md:83-199`):

- d0 = 3 (boot method EXEC1), d1 = pointer to `struct bootinfo`;
  supervisor mode, SR = 0x2700, MMU off, a stack in chip RAM.
- On a 68040/68060: caches pushed (`cpusha bc`) and TC, ITT0/1, DTT0/1
  cleared before the jump. On a 68030: no cache action.
- `struct bootinfo` in the loader's layout, 0x778 bytes: `autocon[16]`
  (ConfigDev copies), `memory[16]` (MemHeader copies), `keystates[16]`,
  `bootdata` (entry point and text/rodata/data placement), `reserved[256]`
  zero-filled. The kernel copies 0x76c bytes, so only `reserved[0..243]`
  arrive, at kernel `bootinfo+0x678` (`PORT/docs/contracts/RTH1-ROOT-HINT.md:16-37`).
  The copy loops are unbounded: more than 16 boards or memory regions
  overflow into the next array, so boot2 refuses to write more than 16 of
  either (`MP/bootchain-facts.md` A14; loader digest §2).
- The kernel image relocated to its bind address: by default the 256-byte
  aligned base of the largest non-chip memory region; relocation types
  R_68K_32 on the 030 line, plus R_68K_PC32/PC16/PC8 (range-checked) on the
  040/060 line (`KT/docs/boot2-040.md:21-27`; `MP/CLAIMS.md` C2). Kernel
  forms: ET_REL with symbols (040/060 line), the compact `brel` form
  (e_type 0xff00, one combined section plus an 8-byte-pair relocation table;
  030 line and floppies) (`KT/contracts/bootchain-v1.json:383-395`;
  `KT/tools/elf2brel.py`), and ET_EXEC.
- The RTH1 root-hint record (0x38 bytes) at `reserved[0]`, built exactly as
  the RTH1 loaders build it: boot node matched by device name, partition
  start and unit; flags BOOT/BCDEV/BMOBO/ROOT/AMBIG; the RTO1 root record
  copied into `root[7]` when present (`PORT/docs/contracts/RTH1-ROOT-HINT.md:16-114`;
  hardening in `KT/src/boot2-patches/README.md:31-56`). The kernel half and
  its rules (`review/D-2-root-hint-r6-decisions.md`, row 4) are unchanged.

New in 1.1, read only by kernels that know it:

- The **loader record** (`AXL1`) at `reserved[0x38]`, ≤ 188 bytes (§6).
- `keystates[]` filled with the keyboard matrix as read at the menu window
  (the stock loader never wrote it, `MP/bootchain-facts.md` B8).
- The **module arena** inside the kernel's `.data`, filled with the
  root-class modules (§5.3).
- Optionally a **RAM-disk image** placed at the top of a fast-memory region,
  with that region shortened in `memory[]` so the kernel never treats it as
  free memory (§5.4).

## 3. The two programs

### 3.1 boot1

Hand-written 68000-compatible assembly (GNU as from gcc-cross-amix, MIT
syntax), ≤ 1024 bytes including the bootblock framing. It has one job:

1. If running under an A3000 SuperKickstart that wants the operating-system
   choice, return into the strap as the stock bootblock does.
2. Read bytes 0–2047 of the boot partition in one aligned read and pick the
   valid store header with the highest sequence number (§4.2).
3. Read the primary boot2 extent, check its CRC-32; on failure read the
   secondary boot2 extent and check it.
4. Jump to boot2 with a1 (the IOStdReq), the partition start, the header,
   and a code saying which boot2 copy it took.
5. If no header or no boot2 is valid, put one line on the screen and
   **return to the strap with a failure code**, so Kickstart can try the next
   boot node. (What the strap does with the return value is not recorded in
   the tree; M-LD3 measures it. If returning proves unsafe, boot1 halts with
   the message instead.)

boot1 has no CPU gate and no filesystem knowledge; it reads extents named in
the header and nothing else.

### 3.2 boot2

C compiled by gcc-cross-amix (GCC 2.7.2.3, `m68k-cbm-sysv4`) plus a small
assembly start-up and hand-off. The stock boot2 could only be assembled on
the golden box because it is PC-relative code in the 1992 assembler's syntax
(`KT/docs/boot2-040.md:56-77`). Ours avoids position-independent code
generation entirely: it is linked at address 0, the build tool appends a
table of its R_68K_32 relocations, and the start-up stub (PC-relative
assembly) applies the table to itself before calling C. Size budget:
**28 KiB**, so it fits the CD System Area after boot1 and the header (§4.4).

boot2 does, in order:

1. **Probe the CPU** with its own trap-guarded instruction probe (68030,
   68040, 68060), not by trusting `AttnFlags`: without SetPatch a real 68060
   has been reported to show no 040/060 bits
   (`PORT/docs/REALHW-060-BOOT-CPUTYPE-MISDETECT-260829.md:10-40`).
   `AttnFlags` is printed beside the probe result when they disagree.
2. **Open the console channels**: a screen text display through
   graphics.library, and the serial port at the console's speed. Every line
   goes to both.
3. **Read the medium**: the boot store (§4) on a disk, SD image or floppy;
   ISO9660 (§4.4) on a CD.
4. **Choose a generation** (§7): default, try-once fallback, one-shot flag,
   menu.
5. **Load the manifest**, check its CRC, check that its CPU line matches the
   probed CPU (§5.1).
6. **Load the kernel** into one fast-memory buffer, decompress if stored
   compressed, check its CRC-32, relocate it for its bind address.
7. **Fill the module arena** with the root-class modules whose match keys
   are satisfied (§5.3), checking each CRC-32.
8. **Place the RAM-disk image** if the manifest names one (§5.4).
9. **Build `bootinfo`**: ConfigDev and memory copies (memory shortened by any
   RAM-disk carve-out), keyboard matrix, RTH1 record, loader record.
10. **Hand off**: Forbid, supervisor, MMU off, the 040/060 cache and
    transparent-translation sequence, jump with d0 = 3, d1 = bootinfo.

### 3.3 Toolchain

boot1, boot2 and the build tool that frames them are built by gcc-cross-amix
(GCC 2.7.2.3 and binutils 2.8.1, `m68k-cbm-sysv4`) through its wrapper and
with 060-safe code on by default (`gcc-cross-amix/README.md:5-20,204-306`);
never by GCC 14 (D-3 §9). The loader package records the compiler pin.

## 4. On-medium formats and readers

### 4.1 Readers needed

| Medium | Reader | Why |
|---|---|---|
| Disk / SD image boot slice (the `UNI\0` partition) | **boot store** (§4.2) | writable by `kbootset` with atomic commits; read by boot1 and boot2 with fixed, aligned extents |
| Floppy pair (both lines) | **boot store**, multi-volume (§4.3) | same code as the disk; volumes 1 and 2 hold one store |
| CD-ROM | **ISO9660** (§4.4) | files are visible to every tool that reads the disc; one disc carries both lines |
| UFS | **not needed in 1.1** | considered for the boot slice and not chosen: UFS has no atomic update (a power cut needs `fsck` before the loader could trust it), the project has no host-side UFS writer for media builds (`MP/RESEARCH.md`, risk list), and the loader never needs the root filesystem. Reopened only if a future need appears (OQ-10.6). |

All reads are aligned to 2048 bytes and are multiples of 2048 bytes. On a
512-byte medium this costs nothing; on a 2048-byte CD node it is what makes a
read transfer data at all (`MP/refute-cd-boot-chain.md`).

### 4.2 The boot store (disk and SD image boot slice)

One boot slice per disk (D-3 §6). The whole `UNI\0` partition is the store.

| Offset | Size | Content | Written by |
|---|---|---|---|
| 0x0000 | 1 KiB | boot1, in bootblock framing | `kbootset` (only by an explicit loader-install step) |
| 0x0400 | 512 B | store header A | `kbootset` |
| 0x0600 | 512 B | store header B | `kbootset` |
| 0x0800 | 28 KiB | boot2, primary copy | `kbootset` |
| 0x7800 | 2 KiB | reserved | — |
| 0x8000 | 28 KiB | boot2, secondary copy (the previous loader) | `kbootset` |
| 0xF000 | 2 KiB | control block A | `kbootset`, boot2 |
| 0xF800 | 2 KiB | control block B | `kbootset`, boot2 |
| 0x10000 | rest | data area: manifests and member files, each an extent aligned to 2048 | `kbootset` |

**Store header** (`AXS1`, big-endian, written only when the loader or the
store geometry changes): magic, version, sequence number, store size,
medium flags (writable, read-only, multi-volume), volume number and set id,
primary and secondary boot2 extents with their CRC-32 and loader versions,
control block extents, CRC-32 of the header. boot1 takes the valid copy with
the higher sequence number.

**Control block** (`AXC1`, 2048 bytes, two copies, valid copy with the higher
sequence number wins): the generation directory and the boot state —

- up to 16 generation entries: id, state (`pristine`, `good`, `trial`,
  `bad`, `free`), manifest extent and CRC-32, creation time, attempt count;
- default generation (the newest good one), previous good, trial generation;
- one-shot request: none / previous good / a named generation / safe mode;
- menu timeout, console settings (serial speed, screen on/off);
- loader-trial state for a newly installed boot2 (§7.4).

The control block is the store's only commit point: `kbootset` writes member
files and the manifest into free extents, reads them back, then writes the
inactive control-block copy with sequence + 1 and reads it back
(`40-generations-and-composer.md` §3). A power cut at any point leaves the
previous control block valid.

**The loader writes**, and only the control block, and only when a boot
consumes state: a trial attempt (§7.2) or a one-shot request (§7.3). A
normal boot of a good generation performs no write. Each write goes to the
inactive copy with sequence + 1. Read-only media have no writable control
block; boot2 never writes to them.

### 4.3 The floppy pair

The floppy pair uses the boot store across two DD volumes (901 120 bytes
each). Volume 1 begins with boot1 and the header; extents carry a volume
number; when an extent lies on the other volume boot2 prints
`insert boot volume N` and waits for the disk change (trackdisk change count)
or a key / mouse button. The stock loader already continued on volume 2 after
a read error (`MP/refute-boot2-one-blob.md` P2), but that path was never
exercised; ours is explicit.

Two profiles, decided by measurement (M-FP1, M-FP2):

- **RAM-disk profile (proposed default):** both volumes are store; the
  generation holds the kernel, root-class modules and a compressed miniroot
  image that becomes a RAM-disk root (§5.4). No floppy-rooted kernel is
  needed, the miniroot is compressed, and the 060 line's untested `fd0` root
  under its caches (`MP/bootchain-facts.md` F10, D6) is avoided.
- **fd0-root profile (fallback):** volume 1 is the store, volume 2 the
  uncompressed miniroot filesystem rooted on `fd0` as in 1.0
  (`IN/docs/universal-bootfloppy.md:42-63`).

Floppies are read-only to the loader (no control-block writes; no try-once).

### 4.4 The CD-ROM

| LBA 0–15 (ISO System Area, 32 KiB) | |
|---|---|
| 0x0000 | boot1 |
| 0x0400 | store header (read-only medium flag, medium type ISO9660) |
| 0x0800–0x7FFF | boot2 (≤ 28 KiB) |

From LBA 16 the disc is ordinary ISO9660 (Rock Ridge as today,
`IN/docs/install-iso.md:20`). boot2's ISO9660 reader finds the Primary Volume
Descriptor at LBA 16, walks the directory tree, compares names without case
and without the `;1` version suffix, and refuses multi-extent files. It reads
`/BOOT/K30/` or `/BOOT/K46/` according to the probed CPU, so one disc boots
both lines. Each line directory holds a read-only control file (the
generation list) and the generation files.

The A4091/A4092 ROMs offer any ISO9660 disc to the strap as a boot node:
priority 2 when the System Identifier reads `AMIGA BOOT` or `CDTV`, −1
otherwise (`MP/refute-cd-boot-chain.md`, citing the reference mounter). The
1.1 install CD sets `AMIGA BOOT` only on the bootable profile
(`50-media.md` §4). Open: whether the strap reads a bootblock from a node
with 2048-byte blocks (M-LD2), and why ROM 42.39 offered no Amix RDB
partition while the reference mounter would (OQ-10.3).

After a CD boot the root is the RAM-disk miniroot from the CD's generation
(§5.4); the CD stays mounted through cdfs as the package source
(`50-media.md` §4).

## 5. What a generation is to the loader

### 5.1 The manifest

A generation is described by one manifest file (`GMF1`), plain ASCII, one
record per line, ≤ 255 bytes per line, written by `kbootset`
(`40-generations-and-composer.md`). The loader reads the records it needs and
ignores the rest; a record whose key starts with `!` must be understood or
the loader refuses the generation (forward compatibility with a refusal path).

```
GMF1
generation 41
line k46
kabi k46.1.0
cpu 68040 68060
loader-min 1
created 2026-11-02T10:00:00Z
rootfs ufs
root sd id=144b0100 base=00000000 unit=6 slice=1
boards 144b0100 02025400
arena 0x001f2000 0x00080000
kernel unix 2101234 at=0x00012000 stored=1203317 z=deflate crc32=1a2b3c4d sha256=...
module z3660scsi root 45678 at=... stored=... z=deflate crc32=... sha256=... match=zorro:144b:01
module a4091 root 61234 at=... crc32=... sha256=... match=zorro:0202:54,zorro:c0de:01
module gayle-ide root 19876 at=... crc32=... sha256=... match=mobo:gayle
module ufs root 61000 at=... crc32=... sha256=... match=always
module z3660eth boot 30212 path=/stand/gen/41/mod/z3660eth sha256=...
param z3660eth.intr=6
end crc32=5e6f7a8b
```

| Record | Meaning to the loader |
|---|---|
| `line`, `cpu` | must match the probed CPU, else the generation is refused with a message naming both |
| `loader-min` | lowest loader version that can boot this generation |
| `kernel` | size after decompression, extent (`at`, store-relative; on a CD a path), stored size, compression, CRC-32 |
| `module … root` | a root-class module the loader places in the arena |
| `module … boot` / `demand` | not read by the loader; loaded by the kernel from the root filesystem (`30-module-core.md` §3) |
| `arena` | offset and capacity of the module arena inside the relocated kernel image |
| `ramdisk` | a RAM-disk image to place (§5.4) |
| `rootfs`, `root` | passed to the kernel in the loader record; the root identity is the same rule as RTO1 |
| `boards` | the board set the generation was composed for; a difference is printed, not fatal |
| `end` | CRC-32 of every byte before this line |

The loader checks CRC-32 on the manifest and on every member it loads.
SHA-256 values are for `kbootset check`, the package system and the kernel's
own checks of boot- and demand-class files; whether the loader also checks
SHA-256 is decided by its cost on a 25 MHz 68030 (M-LD7).

### 5.2 Kernel identity

The kernel package's sidecar gives `kbootset` the arena offset and the
kernel's identity record offset; `kbootset` copies both into the manifest.
boot2 verifies the identity record's magic and kabi string at that offset in
the loaded image before it fills the arena. A static (pre-module) kernel has
no arena record; its manifest has no `arena` line and no root-class modules,
which is how stage 1 boots today's static kernels (`80-stages-and-proof.md`).

### 5.3 The module arena

The arena is a zero-filled region inside the kernel's `.data`, sized per
kernel line (2 × the measured root set rounded to 64 KiB, P-28 D57; M-MOD1).
It travels with `.data`, so modules placed in it keep the cache class today's
static drivers have on the 040/060 line (ITT0/DTT0, `MP/RESEARCH.md` §3.3;
`tmp/2026-10-14-modules-study/STUDY.md` §2.3), and the kernel needs no
allocation before root is mounted.

boot2 writes into the arena, after relocating the kernel and before the
hand-off copy:

- an arena directory (`AXA1`): count, then per module name, offset, length,
  class, CRC-32, flags (matched / forced / safe-mode member), parameter
  string;
- each selected module's file bytes, decompressed, 16-byte aligned.

boot2 does **not** relocate modules; `marc_root` in the kernel does
(`30-module-core.md` §3). A module is selected when one of its match keys is
satisfied: `zorro:MMMM:PP` against the ConfigDev list, `mobo:<name>` always
(the kernel's gated probe decides), `always`. In safe mode only the root
controller's module and the root filesystem's module are placed. Arena
overflow refuses the generation with a message giving the needed and the
available size.

### 5.4 The RAM-disk image

Media that root on a decompressed miniroot (CD, floppy RAM-disk profile,
netinstall floppies) name it in the manifest:
`ramdisk miniroot <size> at=… z=deflate crc32=…`. boot2 decompresses it to the
top of the largest fast-memory region, shortens that region in
`bootinfo.memory[]` by the image size rounded up to 64 KiB, and puts the
physical address and size in the loader record. The `ramdisk` root-class
module presents it as a block device (`30-module-core.md` §7). Whether the
kernel's memory sizing honours a shortened region exactly as given is
measured (M-RD1).

### 5.5 Compression

Members may be stored raw or deflate-compressed. Deflate replaces the stock
LZW (`compress -b16`) stream: its decoder is small, it compresses better, and
the stock decoder is Commodore code. The ratio against LZW on the floppy
kernels and the decode time on a 68030 are measured (M-LD8); LZW is kept only
if deflate loses on either.

## 6. The loader record

`AXL1` at `bootinfo.reserved[0x38]`, read by `kinfo` and the module core:

| Field | Meaning |
|---|---|
| magic, version/length, check | as RTH1 (negated sum) |
| loader version, boot2 copy used | which loader booted the box |
| CPU probe result, `AttnFlags` | both, for diagnosis |
| boot device | device name hash, unit, partition start, board base and id (the RTH1 match result, plus the start, so `kbootset` finds its own boot slice without an RDB scan, `40-generations-and-composer.md` §5) |
| generation id, state as booted | `good`, `trial`, `pristine`, `chosen-in-menu`, `one-shot` |
| flags | safe mode, menu used, try-once fallback taken, store read-only |
| root filesystem type | from the manifest; the kernel sets `rootfstype` from it so `vfs_mountroot` tries only that type |
| RAM-disk address and size | when present |

A kernel without module support ignores it; a module kernel booted by the
stock loader finds no record and boots the floor only (proof period only,
§8).

## 7. Choosing what to boot

### 7.1 Default path

No key held, no one-shot request, no trial: boot2 prints one line
(`amix-boot 1 k46: generation 41 (good) from c0 unit 6`), waits the menu
window (default 2 s; 0 on a headless profile with no screen) for a key or
the left mouse button, and boots the default generation.

### 7.2 Try-once

A generation committed by `kbootset` starts as `trial`. boot2 boots a trial
generation once: before loading it, boot2 writes attempt = 1 to the control
block. If on a later boot the trial generation is still not marked good (the
mark is written at the end of a full multi-user boot, D-3 §6), boot2 marks it
`bad`, prints `generation 42 did not reach multi-user; booting 41`, and boots
the default good generation. This gives a headless box an automatic way back
without the menu. Read-only media have no trial state.

### 7.3 One-shot requests

`kbootset next --previous`, `kbootset next --safe` and `kbootset next <id>`
write a one-shot request into the control block. boot2 consumes it (writes the
cleared request) and boots accordingly; the following boot returns to the
default. This is the shell-command channel of D-3 §6.

### 7.4 The menu

Entered by: any key on the keyboard or the serial console during the menu
window; the left mouse button held when the loader line appears (never from
power-on: at Kickstart start the left button bypasses the A4092 ROM driver
and both buttons open the Kickstart menu, `MP/07-installed-box-lifecycle-design.md:37`);
or automatically when the default generation cannot be loaded.

```
amix-boot 1 (k46, 68060)    boot device: c0 unit 6
  1  generation 41  good      2026-11-02   (default)
  2  generation 40  good      2026-10-28
  3  generation 12  pristine  2026-10-20
  s  safe mode (toggle)       r  return to Kickstart
choose [1]:
```

| Key | Effect |
|---|---|
| digit | select that generation |
| `p` | **rollback key**: previous good generation, at once (also accepted in the menu window without opening the menu) |
| `s` | toggle safe mode for the selection (floor + root controller + root filesystem, `70-static-floor.md` §4) |
| `r` | return to the strap (lets Kickstart try the next boot node) |
| Return | boot the selection |
| left mouse button | next entry; held 2 s: boot the selection |

Keyboard input is read as the keyboard matrix through keyboard.device, the
mouse buttons from CIA-A and POTGO, the serial console byte by byte. Whether
the left button and the keyboard arrive through the HID converters used on
the reference machines is measured (M-LD5). A newly installed boot2 runs as a
loader trial the same way as a generation: if it does not complete a boot it
chains to the secondary copy on the next start.

## 8. Both CPU lines and the stock loader during the proof period

- **One loader, both lines.** The same boot1 and boot2 run on 68030,
  68040 and 68060. boot2 refuses a generation of the other line with a
  message (the stock bootblock had no CPU gate, so an 030 would load a
  040/060 kernel and die in it, `PORT/docs/FLOPPY-BOOT-040-261002.md:73-74`).
  A CD carries both lines and boot2 picks by CPU.
- **Relocation by line.** brel compact relocations (030 kernels and any
  `brel`-form image) and ET_REL relocations with the 040/060 PC-relative
  types, both range-checked; an unknown type refuses with its offset.
- **The 060 branch cache.** Whether the hand-off must also clear the 68060
  branch cache (CACR.CABC) is open (OQ-10.5); the kernel's own user-code
  publication lacks it (`tmp/2026-10-14-modules-study/L2-our-kernels.md:365`).
- **Stock loader coexistence.** Until stage 1 exits (`80-stages-and-proof.md`),
  the stock loader stays where it is: 1.0 media are unchanged, and
  development disks may carry a second, lower-priority `UNI\0` partition with
  the stock chain and a 1.0 static kernel, reached through the Kickstart
  early-startup menu. This is a development arrangement only; no 1.1 medium
  or installed 1.1 disk carries a second boot slice (D-3 §6). Our loader
  boots 1.0 static kernels too (a manifest without arena or modules), which is
  the first proof.

## 9. Failure modes and what the loader prints

Every message is one line, prefixed `amix-boot:`, with a short code for
automated rows, shown on the screen and the serial port. No message waits for
a mouse click; where a choice is needed the menu opens.

| Code | Condition | Action |
|---|---|---|
| B1 | no valid store header (boot1) | print, return to the strap |
| B2 | primary boot2 CRC bad | print, use the secondary copy |
| B3 | both boot2 copies bad | print, return to the strap |
| L1 | CPU line of the generation ≠ probed CPU | name both; menu |
| L2 | manifest missing or CRC bad | name the generation; try the next good one, then the pristine one, then menu |
| L3 | member CRC bad (kernel or module) | name the member; as L2 |
| L4 | not enough fast memory for kernel + arena (+ RAM disk) | give needed and largest region; menu |
| L5 | arena overflow | give needed and capacity; menu |
| L6 | unknown relocation type or out-of-range displacement | give type and offset; as L2 |
| L7 | no root-class module matched any board | print the boards seen; boot anyway (the kernel will name the missing root controller) |
| L8 | trial generation did not reach multi-user | print, mark bad, boot the default |
| L9 | loader version below the manifest's `loader-min` | print; menu |
| L10 | control-block write failed | print; boot without consuming the state (the request repeats next boot) |
| L11 | volume N needed (floppy) | prompt, wait for the change |
| L12 | ISO9660 path not found / multi-extent file | name the path; menu |
| L13 | store read error | name extent and device error; retry once, then as L2 |

## 10. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-10.1 | What the strap does with a bootblock's return value (failure code and the a0/d0 convention), on each Kickstart version in use. | us |
| OQ-10.2 | Which bootblock header fields the strap checks on an RDB `UNI\0` partition (the stock image carries `DOS\0`). | us |
| OQ-10.3 | Whether the strap reads a bootblock from a 2048-byte-block CD node, and why ROM 42.39 offered no Amix RDB partition while the reference mounter source would. | us |
| OQ-10.4 | Whether boot2's screen output should use graphics.library directly or an Intuition screen, given the size budget. | us |
| OQ-10.5 | Whether the hand-off on a 68060 must clear CACR.CABC. | us; Antti for the kernel side |
| OQ-10.6 | Whether a UFS reader is ever needed (for example, a boot directly from a root filesystem). Not needed by D-3. | us |
| OQ-10.7 | Whether `keystates[]` has any kernel consumer that would misread a filled matrix. | us |
| OQ-10.8 | How the kernel's memory sizing treats a shortened `memory[]` region (RAM-disk carve-out). | us |

## 11. Measurements

M-LD1 … M-LD8, M-FP1, M-FP2, M-RD1, M-MOD1 (`90-measurements.md`).
