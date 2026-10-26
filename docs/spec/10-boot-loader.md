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
| What is read | exactly one blob behind one info block placed right after boot2 (0x2600 on the 8 KiB-boot2 disk slice; discovered by scanning on a floppy; a larger boot2 moves it) (`MP/refute-boot2-one-blob.md`, P2–P5) | a generation manifest, then the kernel and each root-class module as separate files |
| Block size | 512-byte reads only; a 2048-byte unit gets zero-block reads (`MP/refute-cd-boot-chain.md`, `MP/CLAIMS.md` C11) | every read aligned to and a multiple of 2048 bytes, so one code path serves 512- and 2048-byte media |
| Media read | raw slice / floppy | the boot store (disk, SD image, floppy); on a CD, files through AmigaDOS (§4.4) |
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
  longword, and code from offset 12; it ends with a trailer longword
  (0x03010401) used by the A3000 SuperKickstart. The strap refuses a bad
  checksum (`grimoire-amix/docs/boot-disks/anatomy-boot-adf.md:49-65`;
  `KT/docs/amix-kernel-source-map.md:150,187-188`; trailer: stock
  `amix-a4091/tmp/amix-src/amiga/boot/elf2boot.c:24-25,59`).
- Entry: register a1 points to an open `IOStdReq` on the boot device and unit
  (`PORT/docs/contracts/RTH1-ROOT-HINT.md:72`); on Kickstart 1.4 and later
  (exec version 36 and up) `io_Offset` holds the partition start, and the
  stock bootblock forces it to 0 on older straps (stock
  `amix-a4091/tmp/amix-src/amiga/boot/boot1.c:110-116`). Exec is alive;
  ExecBase is at absolute address 4.
- On an A3000 with SuperKickstart the bootblock runs before the operating
  system choice; the stock bootblock detects this from an `ExpansionBase`
  flag and returns into the strap so the Kickstart choice continues
  (`KT/docs/amix-kernel-source-map.md:158-161`).
- The strap picks the highest-priority boot node; boot1 never rescans
  (`grimoire-amix/docs/how-it-works/boot-process.md:169-196`). The device
  name in the mount entry is compared as a C string because Kickstart counts
  the NUL in its length (`boot-process.md:224-258`).

Our boot1 keeps the same bootblock framing (header longwords, checksum,
trailer) and reproduces the SuperKickstart return. What the strap checks
was measured (M-LD1, `docs/measurements/2026-10-26-m-ld1-m-ld3.md`) on
Kickstart 3.1 and 3.2.x, on a floppy and on an RDB `UNI\0` partition:
- the magic's first three bytes, `DOS` (the type byte is not checked);
- the checksum.

It does not check the third longword or the trailer. A bootblock whose
magic is `UNI\0`, the partition's DosType, counts as none. When the strap
refuses a disk partition it shows the insert-disk screen; when it refuses
DF0 it tries the next boot node. The Z3660 boot ROM is measured on metal. A CD is a different case: the ROM's ISO9660 boot node runs
no bootblock at all; the CD route starts the loader from AmigaDOS (§4.4,
M-LD2).

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
  The stock copy loops are unbounded: more than 16 boards or memory regions
  overflow into the next array, so our boot2 refuses to write more than 16 of
  either (`docs/040-060-analysis-repo-study.md:161`; stock
  `amix-a4091/tmp/amix-src/amiga/boot/boot2.c:322-324`; the boot2 entry in
  `KT/docs/amix-kernel-source-map.md:153`).
- The kernel image relocated to its bind address: by default the 256-byte
  aligned base of the largest non-chip memory region (the stock `bind.c`;
  1.1 counts only memory below 0x40000000, step 6 below); relocation types
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
3. **Loader trial.** If the header marks the primary boot2 as on trial,
   read the loader tally block (§4.2): if it records no attempt for this
   header's sequence number, write one attempt to it and continue with the
   primary; if it already records an attempt, take the secondary boot2 and
   print `B4`. If the tally write fails, take the secondary. boot1 does not
   parse the control block; the tally block is the only thing it writes.
4. Read the chosen boot2 extent, check its CRC-32; on failure read the other
   boot2 extent and check it.
5. Jump to boot2 with a1 (the IOStdReq), the partition start, the header,
   and a code saying which boot2 copy it took and why.
6. If no header or no boot2 is valid, or boot2 gives up, put a line on the
   serial port (the screen needs graphics.library, which does not fit in
   1 KB; boot2 owns the screen) and **stop**: boot1 loops with interrupts on
   and the user resets. Returning failure to the strap does not make
   Kickstart try the next boot node: on the Z3660 boot ROM chain it raises
   a recoverable AN_BootError alert and resets, about every 14 s (M-LD3,
   measured 2026-10-25), and a reset loop can leave a real 68060 dead until
   a power cycle.

boot1 has no CPU gate and no filesystem knowledge; it reads extents named in
the header, reads and writes the tally block, and nothing else. On a
read-only medium the header never marks a loader trial, so boot1 never
writes there.

### 3.2 boot2

C compiled by gcc-cross-amix (GCC 2.7.2.3, `m68k-cbm-sysv4`) plus a small
assembly start-up and hand-off. The stock boot2 could only be assembled on
the golden box because it is PC-relative code in the 1992 assembler's syntax
(`KT/docs/boot2-040.md:56-77`). Ours avoids position-independent code
generation entirely: it is linked at address 0, the build tool appends a
table of its R_68K_32 relocations, and the start-up stub (PC-relative
assembly) applies the table to itself before calling C. Size budget:
**28 KiB** per copy in the store (§4.2); the AmigaDOS-hosted CD entry of §4.4 shares its C code.

**Where it runs.** boot1 loads boot2 into chip memory, because the strap's
device reads by DMA. Run from there, its code competes with the display for
the chip bus: on a 25 MHz 68030, inflate runs 7 times and CRC-32 25 times
slower than from fast memory (M-LD8, `docs/measurements/2026-10-26-m-ld7-m-ld8.md`).
So the stub first copies boot2 into a MEMF_FAST block, then relocates it
there, and calls C. A machine without fast memory runs it in place and
boot2 says so on the console.
- Device reads still land in a chip bounce buffer, because the controllers
  need it there.
- Members are read into fast memory and inflated, checked and relocated
  there by code running from fast memory.
- The kernel's destination (step 6): the base of the largest fast-memory
  region, counting only its part **below 0x40000000**. A kernel is never
  bound in chip memory, where address 0 is the vector table, and never in
  Zorro III expansion memory. The Amix kernels map the first 1 GiB one to
  one, and keep their own segment maps at virtual 0x40040000 (`syssegs`,
  the `sptalloc` arena). A kernel bound at 0x40000000 or above is not
  mapped once translation is on, and never starts. S3-43-7 (2026-10-26)
  showed it on both lines with a 128 MB Zorro III board, after `amix-boot:
  starting the kernel`. The stock loader's `bind.c` has no such limit.
- The loader tells the regions apart by address, from the memory list it
  copies into `bootinfo.memory[]`: each `MemHeader`'s `mh_Lower` and
  `mh_Upper` (offsets 20 and 24; `mh_Attributes` at 14 gives `MEMF_CHIP`).
  Zorro III RAM carries the same `MEMF_FAST | MEMF_PUBLIC` attributes as a
  CPU board's, so the attributes cannot tell them apart.
- On a machine without fast memory below 0x40000000, or whose largest such
  region is smaller than the bound kernel, boot2 refuses the generation
  with L4 and says which of the two it was (`no fast memory below
  0x40000000 to run the kernel in`).
- **Neither line uses any memory but the region it is bound in.** The
  kernel's main store is the region its end lies in, joined with regions
  that touch it (the stock `support.c`). kinfo's fast memory is that
  region alone, and Zorro III RAM beside it is never kernel memory
  (S3-43-8, 2026-10-26).
- **On k30 that region is at most 64 MiB.** The 2 KiB-page kernel stops
  before its banner with a larger main store: 128 MB at 0x08000000 never
  starts, 64 MB at the same address boots (S3-43, N70 and N75). So for a
  k30 generation boot2 caps the kernel's room at 64 MiB, and in the
  `bootinfo.memory[]` it hands over it ends the bind region 64 MiB above
  its base and ends a region that touches it from below one 2 KiB page
  short of the base (`ax_memcap`). The kernel's join of touching regions
  then leaves that region out of the main store with its range intact,
  where the k30 DMA pool comes from (C4-5 §5.2). A k30 kernel on a
  128 MB box uses 64 MB of it. The k46 line takes its whole region.
- The hand-off code is copied to chip memory as before (step 10).

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
   files through dos.library in the CD entry `amix-cdboot` (§4.4).
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
| CD-ROM | **files through dos.library**, in `amix-cdboot` (§4.4) | the ROM's ISO9660 boot node runs no bootblock; AmigaDOS mounts the disc and the loader reads plain files; one disc carrying both lines is proposed (OQ-50.7) |
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
| 0x7800 | 2 KiB | loader tally block (`AXT1`): header sequence number it refers to, attempt count, CRC-32 | boot1 (attempt), `kbootset` (reset) |
| 0x8000 | 28 KiB | boot2, secondary copy (the previous loader) | `kbootset` |
| 0xF000 | 2 KiB | control block A | `kbootset`, boot2 |
| 0xF800 | 2 KiB | control block B | `kbootset`, boot2 |
| 0x10000 | rest | data area: manifests and member files, each an extent aligned to 2048 | `kbootset` |

**Store header** (`AXS1`, big-endian, written only when the loader or the
store geometry changes): magic, version, sequence number, store size,
medium flags (writable, read-only, multi-volume), volume number and set id,
primary and secondary boot2 extents with their CRC-32 and loader versions,
the loader-trial flag (set by `kbootset loader-install`, cleared by
`kbootset mark-good` after a full boot through the new primary), control
block and tally block extents, CRC-32 of the header. boot1 takes the valid
copy with the higher sequence number.

**Why the loader attempt is not in the header or the control block.** The
header is written only by `kbootset` and changes rarely, so no boot code
ever rewrites it; the control block needs CRC and directory logic that does
not fit 1 KB. The tally block is a separate 2 KiB record that boot1 can write
with one aligned write, and a stale or damaged tally block (wrong sequence
number or bad CRC) reads as "no attempt yet" — so the worst case is one more
start of the new loader, never an endless loop.

**Control block** (`AXC1`, 2048 bytes, two copies, valid copy with the higher
sequence number wins): the generation directory and the boot state —

- up to 16 generation entries: id, state (`pristine`, `good`, `trial`,
  `bad`, `free`), manifest extent and CRC-32, creation time, attempt count;
- the **default** generation, a stored field (not derived): set to the trial
  by `kbootset mark-good`, set to an older good generation by
  `kbootset rollback`, never changed by `commit` (a commit only sets the
  trial); the trial generation;
- one-shot request: none / previous good / a named generation / safe mode;
- menu timeout, console settings (serial speed, screen on/off);
- the highest generation id ever issued on the store, so that an id is
  never reused after its generation is collected (40 §1). A block written
  before this field reads 0 there, and the highest id present counts.

(The loader-trial state lives in the header and the tally block, §3.1.)

The control block is the store's only commit point: `kbootset` writes member
files and the manifest into free extents, reads them back, then writes the
inactive control-block copy with sequence + 1 and reads it back
(`40-generations-and-composer.md` §3). A power cut at any point leaves the
previous control block valid.

**boot2 writes** only the control block, and only when a boot consumes
state: a trial attempt (§7.2) or a one-shot request (§7.3); boot1 writes only
the tally block, and only during a loader trial (§3.1). A normal boot of a
good generation with a good loader performs no write. Each write goes to the
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

An extent may run past the end of its volume: its bytes continue at offset
0x800 of the next volume (after that volume's two store headers), and boot2
asks for that volume in the middle of the member. A deflated miniroot is
larger than the data area of one DD volume (M-FP1), so this is what lets the
RAM-disk profile fit. A manifest never spans; the writer places each
generation's manifest on the volume where its first member starts, so the
pair boots with one disk change.

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

### 4.4 The CD-ROM — boot2 as an AmigaDOS program (D-3 §10)

**Why this route.** The A4091/A4092 ROM mounter gives an ISO9660 data disc a
boot node with priority 2 (System Identifier `AMIGA BOOT` or `CDTV`) or −1;
that node has no boot blocks (`de_BootBlocks` is never set), carries the CD
filesystem's DosType (`CD01`/`CDVD`) and is added with `ADNF_STARTPROC`, so
Kickstart starts the CD filesystem and boots AmigaDOS from the disc; no
bootblock ever runs (`amix-a4091/reference/a4091-software/3rdparty/mounter/mounter.c:1229-1264`;
the parameter packet is zero-filled at :1231). The ROM takes its RDB path
only for a disc without an ISO descriptor (`mounter.c:1212-1214`), so an
RDB-style disc would stop being a data CD, and that path is unproven on
2048-byte blocks; it was rejected (D-3 §10).

**The design.**
- The disc is a standard ISO9660 data CD (Rock Ridge as today,
  `IN/docs/install-iso.md:20`) with System Identifier `AMIGA BOOT`. It mounts
  normally under Amix (cdfs), AmigaOS and other systems. The A4091/A4092
  ROM's CD filesystem is ODFileSystem's ROM profile:
  - it reads ISO9660, Rock Ridge and Joliet, preferring Rock Ridge, then
    Joliet, then plain names, and matches case-insensitively;
  - `S/Startup-Sequence` and `BOOT/amix-cdboot` therefore ride on Rock
    Ridge;
  - `amix-cdboot` needs an owner-execute mode, or AmigaOS refuses to run
    it;
  - the line directories use exact 8.3 names in every namespace
    (installng, S1-C3).
- Kickstart boots AmigaDOS from it through the ROM's CD filesystem and runs
  `S/Startup-Sequence`, which runs one program by its full path:
  **`amix-cdboot`**.
- `amix-cdboot` is boot2 built as an AmigaDOS executable: the same C sources
  and the same hand-off, with a different entry. Its entry gets ExecBase and
  dos.library instead of boot1's registers; its reader opens files through
  dos.library instead of reading store extents through the strap's IOStdReq.
  The build tool that makes boot2's self-relocating image emits, for this
  entry, an AmigaDOS load file instead (one code hunk, its 32-bit
  relocations as a `HUNK_RELOC32` table, bss included), so AmigaDOS's own
  loader relocates it and no self-relocation runs.
- It probes the CPU and reads the generation list from
  `/BOOT/K30/CONTROL` or `/BOOT/K46/CONTROL` (a read-only control block,
  §4.2), so one disc carries both lines (proposed, OQ-50.7). The manifest
  names members by file name in the line directory (`file=`, §5.1), never by
  extent.
- The line directory holds `CONTROL` (2048 bytes, the §4.2 control block;
  each generation entry carries its manifest's length and CRC-32, its extent
  is unused), the manifest of generation N as `GN.GMF`, and its members as
  `GNK.BIN` (kernel), `GNR.BIN` (RAM disk) and `GNMnn.BIN` (root-class
  modules, in manifest order): ISO9660 8.3 names, so the tree reads the same
  with or without Rock Ridge, and N ≤ 9999. `amix-cdboot` sits in `/BOOT`.
  `mkstore -C` writes this tree and `lsstore -C` verifies it.
- It loads the kernel and the compressed miniroot as plain files, builds the
  same `bootinfo`, RTH1 and loader record (the root selector names the RAM
  disk, §5.4; RTH1 carries no boot-node match), takes the machine over
  (Forbid, interrupts off, supervisor, MMU off) and hands off exactly as
  boot2 does (§3.2 steps 6–10). AmigaOS is the carrier for about two seconds
  and is never touched again.
- Menu, safe mode, development load and failure messages are those of
  §7–§9; try-once does not apply (read-only medium).
- Requirement: a boot ROM with a CD filesystem (the A4091 and A4092 have
  one) and a Kickstart that boots AmigaDOS from it. Other machines boot the
  floppy pair and install from the CD (`50-media.md` §3–§4).

Precedent for an AmigaDOS-hosted Amix loader: Markus Wild's `unix_boot`,
whose descendant is the 040/060 port's development path
(`PORT/docs/boot-path-map.md:13-37`).

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
loader-min 2
created 2026-11-02T10:00:00Z
rootfs ufs
root sd id=144b0100 base=00000000 unit=6 slice=1
boards 144b0100 02025400
arena 0x001f2000 0x00080000
ident 0x001f1fc0
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
| `loader-min` | lowest loader version that can boot this generation: 1 a static kernel, 2 a module kernel's arena (stage 3), 3 a generation with a root-class record, which only the boot2 of S4-10 places (changed after the freeze, 2026-10-26) |
| `kernel` | size after decompression, extent (`at=`, store-relative) or, on a CD, `file=` (a file in the line directory), stored size, compression, CRC-32; for a `brel` kernel, `bss=`: the bytes past the image to the kernel's end (bss and COMMON), which the `brel` format does not record. boot2 adds them to the kernel's end before it checks that the kernel fits fast memory; without `bss=` it assumes 512 KiB and says so (the 1.0 families measure 270–345 KiB) |
| `module … root` | a root-class module the loader places in the arena |
| `module … boot` / `demand` | not read by the loader; loaded by the kernel from the root filesystem (`30-module-core.md` §3) |
| `arena` | offset and capacity of the module arena inside the relocated kernel image |
| `ident` | image offset of the kernel's identity record `AXK1` (loader version 2, C3-3); a manifest has both `arena` and `ident` or neither, else L9 |
| `ramdisk` | a RAM-disk image to place (§5.4) |
| `rootfs`, `root` | copied into the loader record's root selector (§6); for an sd root boot2 also builds the RTO1-format root record (unit, base, id, flags) into RTH1's `root[]` field from this line, as the 1.0 installer wrote RTO1 into the kernel info block; `root ramdisk` names the RAM-disk root (§5.4) |
| `swap` | `swap sd … slice=2` or `swap none` (RAM-disk media); copied into the loader record |
| `boards` | the board set the generation was composed for; a difference is printed, not fatal |
| `end` | CRC-32 of every byte before this line |

The loader checks CRC-32 on the manifest and on every member it loads.
SHA-256 values are for `kbootset check`, the package system and the kernel's
own checks of boot- and demand-class files. The loader does not check
SHA-256: on a 25 MHz 68030 it costs 2.3 s for a k30 kernel and 3.75 s for a
k46 kernel, 6.3 times the CRC-32 (M-LD7,
`docs/measurements/2026-10-26-m-ld7-m-ld8.md`).

### 5.2 Kernel identity

The kernel package's sidecar gives `kbootset` the arena offset and the
kernel's identity record offset; `kbootset` copies both into the manifest.
boot2 (loader version 2) verifies the identity record at that offset in the
relocated image before it fills the arena: magic, version, check, kabi tag,
line, and the arena's offset and capacity (C3-3 §2); a mismatch is L14. A static (pre-module) kernel has
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
- a verbatim copy of the booted manifest, so the kernel checks every later
  load against the manifest the loader actually booted rather than against a
  file on the root filesystem (`30-module-core.md` §2, patch 17);
- each selected module's file bytes, decompressed, 16-byte aligned, then
  its zeroed tail of the record's `bss=` bytes, which holds its NOBITS and
  COMMON (contract C4-4 §1.2; changed after the freeze, 2026-10-26).

boot2 does **not** relocate modules; `marc_root` in the kernel does
(`30-module-core.md` §3). boot2 places every root-class record of the
generation and selects none: the core evaluates each record's match keys
at `marc_root` (contract C4-4 version 3; changed after the freeze,
2026-10-26). In safe mode only the records `kbootset` marked `safe=1`
are placed: the root controller's module, the root filesystem's module
and their dependencies. Arena overflow refuses the generation with a
message giving the needed and the available size; `kbootset`'s gate 4
already refused such a generation when it composed it.

### 5.4 The RAM-disk image

Media that root on a decompressed miniroot (CD, floppy RAM-disk profile,
netinstall floppies) name it in the manifest:
`ramdisk miniroot <size> at=… z=deflate crc32=…`. boot2 decompresses it to the
top of the largest fast-memory region, shortens that region in
`bootinfo.memory[]` by the image size rounded up to 64 KiB, and puts the
physical address and size in the loader record. The `ramdisk` root-class
module presents it as a block device (`30-module-core.md` §7). The manifest
of such a medium says `root ramdisk` and `swap none`; the loader record's
root selector then names the RAM disk, and the kernel half makes it root
(`30-module-core.md` §3). Whether the kernel's memory sizing honours a
shortened region exactly as given is measured (M-RD1).

### 5.5 Compression

Members may be stored raw or deflate-compressed. Deflate replaces the stock
LZW (`compress -b16`) stream: its decoder is small, it compresses better, and
the stock decoder is Commodore code. The ratio against LZW on the floppy
kernels and the decode time on a 68030 are measured (M-LD8); LZW is kept only
if deflate loses on either. Deflate wins the ratio (73 % and 71 % of the LZW
size).

**Raw where there is room.** Inflating costs seconds on a 68030 (M-LD8).
Reading a raw kernel from a hard disk or a CD costs well under a second
more. So members are stored raw in a disk store and on the CD, and deflated
only where a generation must fit: the floppy pair and the netinstall medium
(M-FP1). A floppy reads about 27 KiB/s, so there deflate saves more reading
time than it costs to decode.

## 6. The loader record

`AXL1` at `bootinfo.reserved[0x38]`, read by `kinfo` and the module core:

| Field | Meaning |
|---|---|
| magic, version/length, check | as RTH1 (negated sum) |
| loader version, boot2 copy used | which loader booted the box |
| CPU probe result, `AttnFlags` | both, for diagnosis |
| boot device | device name hash, unit, partition start, board base and id (the RTH1 match result, plus the start, so `kbootset` finds its own boot slice without an RDB scan, `40-generations-and-composer.md` §5) |
| generation id, state as booted | `good`, `trial`, `pristine`, `chosen-in-menu`, `one-shot` |
| flags | safe mode 0x01, menu used 0x02, try-once fallback taken 0x04, **read-only medium 0x08**, **development load** 0x10 (§7.4). 0x08 is set for every boot from a read-only medium, the CD (`amix-cdboot`, which also gives no boot device: unit 0xFFFFFFFF) and the floppy pair: the generation booted is the medium's, not one of the box's own store, and `kbootset` acts on that (C2-4 §13) |
| root selector | kind (`sd` or `ramdisk`); for `sd`: controller id, board base, unit, **slice**; from the manifest's `root` line |
| swap selector | `sd` (id, base, unit, slice) or `none` |
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
without the menu. If the attempt cannot be written, boot2 does not boot the
trial at all: it boots the default good generation (L10). Read-only media
have no trial state.

The attempt is written when the boot starts, so any reboot before
multi-user spends it. After an unclean shutdown, the base system's root
fsck repairs the root and reboots (`bcheckrc`, even after a successful
repair; M-GEN3, 2026-10-26). A trial committed just before a power cut
would therefore lose its only attempt to that reboot. So the fsck-repair
path calls `kbootset retry` (`40-generations-and-composer.md` §3.3) just
before it reboots. That gives the booted trial its attempt back, at most
twice per trial, and the next boot tries the trial again.

**A trial refused before it starts spends its attempt too** (L1, L2, L3,
L6, L9, L14). The attempt is written before boot2 reads anything of the
generation, and on purpose: a trial that hangs or crashes the loader
itself must still fall back on the next boot. So a trial boot2 refuses
keeps `trial`, attempt 1, for the rest of that boot (`kbootset status`
shows `trial`, 1 attempt), and the next boot marks it `bad` with L8. The
refusal line of the boot that spent it says why (for example
`amix-boot: L9 loader too old (generation 2)`), and that
line, not L8's wording, is the reason of record. In normal use kbootset's
gates keep such a generation out of the store (gate 7 for L9, gate 10 for
L1); only `kbootset commit --spec`, which runs no gates, can put one there.

When the chosen generation cannot be loaded (L2, L3, L6), boot2 tries in
this order: the default generation, the other good generations newest first,
the pristine generation, then the menu.

### 7.3 One-shot requests

`kbootset next --previous`, `kbootset next --safe` and `kbootset next <id>`
write a one-shot request into the control block. boot2 consumes it (writes the
cleared request) and boots accordingly; the following boot returns to the
default. This is the shell-command channel of D-3 §6.

A one-shot request takes its boot ahead of a pending trial, which waits,
unstarted, for the next boot (`select.c`). The safe-mode and
development-load requests (`kbootset next devload`) boot the **default**
generation in that mode, never the trial. To boot a new generation under
development load, mark it good first. A loader that is still on trial
(§3.1) also boots the default, and its boot consumes a pending request.

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
  s  safe mode (toggle)       d  development load (toggle)
choose [1]:
```

| Key | Effect |
|---|---|
| digit | select that generation |
| `p` | **rollback key**: previous good generation, at once (also accepted in the menu window without opening the menu) |
| `s` | toggle safe mode for the selection (floor + root controller + root filesystem, `70-static-floor.md` §4) |
| `d` | toggle **development load** for this boot only: the kernel then accepts modules that are not members of the booted manifest (`30-module-core.md` §2, patch 17); boot2 prints `amix-boot: DEVELOPMENT LOAD: modules outside the manifest allowed this boot` and the kernel repeats it; `kbootset next --devload` requests the same for the next boot |
| `r` | not offered: returning to the strap raises AN_BootError and resets rather than trying the next boot node (M-LD3); the key prints why |
| Return | boot the selection |
| left mouse button | next entry; held 2 s: boot the selection. Mouse actions count only after the button has first been released, so the hold that opened the menu never selects |

Keyboard input is read as the keyboard matrix through keyboard.device, the
mouse buttons from CIA-A and POTGO, the serial console byte by byte. Whether
the left button and the keyboard arrive through the HID converters used on
the reference machines is measured (M-LD5). A newly installed boot2 is a loader
trial: boot1 counts its starts in the tally block and falls back to the
secondary copy on the next start if the new one never completed a boot
(§3.1).

## 8. Both CPU lines and the stock loader during the proof period

- **One loader, both lines.** The same boot1 and boot2 run on 68030,
  68040 and 68060. boot2 refuses a generation of the other line with a
  message (the stock bootblock had no CPU gate, so an 030 would load a
  040/060 kernel and die in it, `PORT/docs/FLOPPY-BOOT-040-261002.md:73-74`).
  A CD carrying both lines, with the loader picking by CPU, is proposed
  (OQ-50.7).
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
| B1 | no valid store header (boot1) | print (serial port only), stop |
| B2 | primary boot2 CRC bad | print, use the secondary copy |
| B3 | both boot2 copies bad | print (serial port only), stop |
| B4 | loader trial: the new boot2 already had its attempt, or the tally write failed | print, use the secondary copy |
| L1 | CPU line of the generation ≠ probed CPU | name both; menu |
| L2 | manifest missing or CRC bad | name the generation; continue in the order of §7.2 (default, other good newest first, pristine, menu) |
| L3 | member CRC bad (kernel or module) | name the member; as L2 |
| L4 | not enough fast memory for kernel + arena (+ RAM disk) | give needed and largest region; menu |
| L5 | arena overflow | give needed and capacity; as L2 (the next generation in the order: try-once falls back to the good one, and an unattended box does not stop at a menu; the menu stays reachable by key) |
| L6 | unknown relocation type or out-of-range displacement | give type and offset; as L2 |
| L7 | retired (C4-4 version 3, 2026-10-26): boot2 no longer matches root-class modules; the kernel names a missing root controller when the root does not mount | — |
| L8 | trial generation did not reach multi-user | print, mark bad, boot the default |
| L9 | loader version below the manifest's `loader-min` | print; menu |
| L10 | control-block write failed | print; for a trial, boot the default good generation instead (§7.2); for a one-shot request, boot it without consuming it (the request repeats next boot) |
| L11 | volume N needed (floppy) | prompt, wait for the change |
| L12 | ISO9660 path not found / multi-extent file | name the path; menu |
| L13 | store read error | name extent and device error; retry once, then as L2 |
| L14 | kernel identity record does not match the manifest (magic, version, check, kabi tag, line, arena offset or capacity; C3-3 §2) | print; as L2 |

## 10. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-10.1 | What the strap does with a bootblock's return value on the other boot ROMs and Kickstart versions (the Z3660 ROM chain raises AN_BootError and resets, M-LD3). | us |
| OQ-10.2 | Which bootblock header fields the strap checks on an RDB `UNI\0` partition (the stock image carries `DOS\0`). | us |
| OQ-10.3 | Why ROM 42.39 offered no Amix RDB partition on a disk while the reference mounter source would. | us |
| OQ-10.4 | Whether boot2's screen output should use graphics.library directly or an Intuition screen, given the size budget. | us |
| OQ-10.5 | Whether the hand-off on a 68060 must clear CACR.CABC. | us; Antti for the kernel side |
| OQ-10.6 | Whether a UFS reader is ever needed (for example, a boot directly from a root filesystem). Not needed by D-3. | us |
| OQ-10.7 | Whether `keystates[]` has any kernel consumer that would misread a filled matrix. | us |
| OQ-10.8 | How the kernel's memory sizing treats a shortened `memory[]` region (RAM-disk carve-out). | us |

## 11. Measurements

M-LD1 … M-LD9, M-FP1, M-FP2, M-RD1, M-RD2, M-MOD1 (`90-measurements.md`).
