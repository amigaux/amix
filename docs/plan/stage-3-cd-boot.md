# The CD boot tree — recipe and first cell (S3-31 part 3)

D-3 §10 chose option B for 1.1: the install CD is an ordinary ISO9660 data
disc that an A4091/A4092 ROM boots through AmigaDOS. The disc's
`S/Startup-Sequence` runs `amix-cdboot`, boot2 built as an AmigaDOS
program (10 §4.4). This page is the recipe at amix-dlm 28aaf58 for
amix-installng, what is proven and what is not, and what the first
emulator cell should see.

## 1. What exists, and what has never run

| Piece | State |
|---|---|
| `amix-cdboot` (S1-C2) | built by `make cdboot` from boot2's own `core.c` with an AmigaDOS entry (`cdmain.c`, `adstart.s`): one code hunk with a `HUNK_RELOC32` table and bss. Host-checked only: `hunkcheck` applies its 477 relocations at a test address and compares them with the relocator. Rebuilt at 9f6f0bb with the Zorro III bind fix |
| the tree (`mkstore -C`, `lsstore -C`) | host round trip in `store-roundtrip.sh`: names, CRCs, mode 0755, a trial generation refused, reproducible with `SOURCE_DATE_EPOCH`. Both lines on one disc checked with the kernels of record (§3) |
| gated generations for it (`kbootset media --cd`) | host test in `kbuild.sh` |
| the ISO (`build-iso.sh --cd-boot`, S1-C3) | installng's builder and self-test exist; no disc has been mastered with a boot tree |
| **a CD boot** | **never run, on the emulator or on metal.** No stage-1 or stage-2 row booted `amix-cdboot`; the bench README has no CD row. The whole path from the ROM's CD filesystem to the hand-off is unproven until the first cell |

## 2. What stage 3 can and cannot boot from a CD

10 §4.4 describes the installer CD: the kernel and a compressed miniroot,
the miniroot as a RAM-disk root (`root ramdisk`, 10 §5.4). **That
generation cannot boot before stage 4:**
- boot2, and so `amix-cdboot`, refuses a generation with a `ramdisk`
  member: the L9 path in `core.c` load_first. The placement in 10 §5.4
  (decompress to the top of fast memory, shorten the region) is not
  implemented;
- the kernel side, the `ramdisk` root-class module, is stage 4's
  (`marc_root`, 30 §7), and M-RD1 is unmeasured.

The CD boot path itself (ROM, AmigaDOS, the CD filesystem, `amix-cdboot`,
the hand-off) does not depend on the RAM disk. It can be proven now with
a generation that roots on the vehicle's hard disk. **Proposed for S3-31
part 3:**
1. the CD-booted, disk-rooted cell below (§5), on both lines;
2. the installer CD (kernel + miniroot) as soon as stage 4 gives the RAM
   disk. The 1.1 media ship after stage 4 in any case (D-3 §8).

## 3. The tree, per line, then one disc

The generations are gated by kbootset like any medium's (C2-4 §11 `media`,
40 §3.1). On a CD the kernel is stored raw (10 §5.5).

```
# per line, from a staging root where that line's kernel package is installed
# (kernel-k46-m / kernel-k30-m: /stand/<line>/unix and kabi, k30 also unix.sym):
kbootset -R <stage46> media --cd <tmp46> --version 2 \
    --line 46 --bootdev zorro:0202:54 --rootdev <vehicle's root controller key> \
    --rootfs ufs --root "<vehicle's root record>" --mem <bytes>
kbootset -R <stage30> media --cd <tmp30> --version 2 \
    --line 30 --bootdev zorro:0202:54 --rootdev <key> --rootfs ufs --root "<record>" --mem <bytes>
#   each writes <tmpNN>.spec: generation 1, the kernel member raw
# one disc, both lines:
mkstore -C <TREE> -x build/amix-cdboot <tmp30>.spec <tmp46>.spec
lsstore -C <TREE>                                  # "lsstore: ok"
tools/build-install-iso.sh … --cd-boot <TREE> --out <ISO>     # installng
```

- `--bootdev zorro:0202:54` is the A4091 (the CD's controller). `--rootdev`
  and `--root` name the disk the kernel roots on (§5): the vehicles' are
  `sd id=144b0100 unit=6 slice=1` (k46) and `sd id=00000000
  base=00000000 unit=6 slice=1 mobo` (k30).
- For the installer CD (stage 4) the same call adds `--ramdisk <miniroot>`
  and names `--root ramdisk`.
- Checked at 28aaf58 with the kernels of record (generation 1 on each
  line, the specs written by hand in `media`'s form): `mkstore -C` writes
  one tree with both, and `lsstore -C` gives `ok`.

**What is on the disc:**

| Path | What |
|---|---|
| `/S/Startup-Sequence` | three lines: two comments and `SYS:BOOT/amix-cdboot` |
| `/BOOT/amix-cdboot` | the loader, mode 0755 (installng stages it 0755; on the disc 0555 with Rock Ridge) |
| `/BOOT/K46/CONTROL`, `/BOOT/K30/CONTROL` | the read-only control block of each line (10 §4.2), 2048 bytes |
| `/BOOT/K46/G1.GMF`, `G1K.BIN` (and `G1R.BIN`, `G1Mnn.BIN` when present) | generation 1's manifest and members, 8.3 names in every namespace |

**Boot records:** there are none. The ROM's mounter gives an ISO9660
disc with System Identifier `AMIGA BOOT` a boot node (priority 2) with no
boot blocks, Kickstart boots AmigaDOS from it through the ROM's CD
filesystem, and no bootblock ever runs (10 §4.4). The disc is mastered
with System ID `AMIGA BOOT`, Rock Ridge on (so `amix-cdboot` and
`Startup-Sequence` keep their names and modes), as `build-iso.sh
--cd-boot` already does.

**The hand-off** is boot2's own code (`core.c`, 10 §3.2 steps 6–10):
- the same bind rule (below 0x40000000);
- the same `bootinfo`;
- the same loader record AXL1, built from the manifest's `root` line,
  with the generation's id;
- the same RTH1, carrying an RTO1 root record for an `sd` root and no
  boot-node match;
- the same copy and jump.

Only the reader differs: files through dos.library instead of store
extents.

## 4. What the emulator needs

- **amiberry** (the workspace fork) with its A4091 emulation and a CD unit
  on the A4091's SCSI bus (as the install-CD config in amiberry
  `docs/d245-install-parity.md` has it, `scsi3_a4091`), the ISO as that
  unit's image, a Kickstart that boots AmigaDOS from a CD boot node (3.1
  and later on the A3000/A4000), and the vehicle's hard disk on the
  controller the generation roots on.
- **A CD-capable A4091 ROM.** The ROM in the workspace store (registry
  R003, `boards/a4091/amiga-boot-a4091.rom`, A4091 v40.13) is Commodore's
  and has no CD filesystem. The ROM that boots a data CD is the open
  `a4091-software` ROM built with the ODFileSystem ROM profile
  (`amix-a4091/reference/a4091-software/Makefile:187-196`). It is not in
  the ROM store. It has to be built from a copy of that tree (the
  reference tree is protected) and registered, with its version, before
  the cell.
- **Unproven:** whether that ROM's CD filesystem mounts amiberry's
  emulated CD unit (2048-byte blocks) and gives the boot node. ODFileSystem
  reads 2048-byte media by design, but nobody has run it under amiberry's
  A4091. It is the first question of the first cell.

## 5. The first cell: CD-booted, disk-rooted

A vehicle slot copy (the k46 or k30 vehicle of the S3 rows), its own boot
store untouched, the ISO in the A4091's CD unit, the CD unit given boot
priority over the hard disk (the ROM gives the disc priority 2).

Expected on the console, in order:
1. AmigaDOS boots from the CD, and the Startup-Sequence runs.
2. `amix-cdboot 2: 680x0, generations from SYS:BOOT/K46` (k30:
   `SYS:BOOT/K30`).
   This is the CD entry's own first line, in place of boot2's
   `amix-boot 2: … boot1 choice …`. The line directory follows the probed
   CPU.
3. `amix-boot: generation 1, kernel unix 2431362 bytes` (k30: `unix
   1715944 bytes`), then `amix-boot: kernel bound at <below 0x40000000>…`
   and `amix-boot: starting the kernel`.
4. The kernel's banner. `dlm: modules from generation 1's manifest` and
   `dlm: 80 kernel symbols` (k30: 78): the CD's generation carries the
   arena, and `amix-cdboot` fills it from the CD's manifest.
5. Multi-user from the hard disk.
6. A missing file gives `amix-boot: L12 cannot open <path>`. A bad
   control file gives `amix-cdboot: no valid control file`.

**Watch on that boot:** the vehicle's own `S01kbnamelist` and the
`mark-good` hook run against kinfo's loader record, which names generation
1 of the CD. The CD has no store, so kbootset's store search (40 §5) may
fall back to scanning the disks and find the vehicle's store, which has
its own generation 1. Note what `kbootset status`, `namelist` and
`mark-good` print on a CD boot. Whether a CD boot should tell kbootset so
(a loader record flag) is the cell's finding to bring back.
