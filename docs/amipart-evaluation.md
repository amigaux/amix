# AmiPart for 1.1: evaluation (2026-10-10)

[AmiPart](https://github.com/ChuckyGang/AmiPart) (MIT, per its README) is an Amiga RDB partition editor, and its
Linux CLI builds from the same source. Evaluated at commit `fa843c9`: `host/` builds with `make` and no warnings
(gcc, no dependencies). The tool and the test copies are in the maintainer's notes (`eval/partdump.py` dumps every RDSK
and PART field). Nothing was written to any of our images; the writes went to reflink copies.

## (a) Reading our disks: yes

`amipart IMAGE=<hdf> INFO`:

| Image | What INFO prints |
|---|---|
| `k1-blank200.hdf` | `No valid RDB found.` (correct: the image is all zeros) |
| `k1-desktop-rtg.hdf` | 6368 cyl x 1 x 64; `UNIX_Root` cyl 2-5313 `UNI\1` 166 MB; `UNIX_Swap` 5314-6273 `res\118` 30 MB; `UNIX_Boot` 6274-6337 `UNI\0` pri 2, 2 MB |
| cd-full-pub-r6 target (classic, 512 MB) | 16352 cyl; root 2-15297 478 MB; swap 15298-16257; boot 16258-16321 pri 2 |
| cd1-full-pub-r6 target (060, 512 MB) | the same layout |

- Names, dostypes, cylinder ranges, boot priority and sizes all agree with what `/etc/rdb` wrote and
  `tools/rootfs-type.py` reads. `res\118` is our swap dostype `resv` (0x72657376), with the last byte printed in
  decimal.
- It also prints `RDB blocks : 0-6399` because stock `/etc/rdb` sets RDBBlocksHi to 6399 although the root starts at
  block 128. That is our RDB as written, not a misreading.
- **Use:** an independent second reader for a 1.1 selftest. Read-only, and on our disks it agrees with `rdb.py`.

## (b) Setting the UNIX_Boot boot priority from the host: no, not with this CLI

The CLI and its scripts cannot edit a partition in place; only `ADDPART` takes `BOOTPRI`. Tried on a copy of the
cd-full-pub-r6 target: `DELPART NAME=UNIX_Boot`, then `ADDPART NAME=UNIX_Boot LOW=16258 HIGH=16321 TYPE=0x554E4900
BOOTPRI=-128 ENFORCESIZE`, then `WRITE`. Only RDB blocks 0-3 changed and no data blocks, but the rewrite changes far
more than the priority:

| Field | Ours (stock `/etc/rdb`) | After AmiPart |
|---|---|---|
| UNIX_Boot BootBlocks | 2 | **0**: Kickstart would load no boot code, so the disk would not boot |
| UNIX_Boot MaxTransfer / Mask | 0xFFFFFF / 0xFFFFFFFC | 0x1FE00 / 0x7FFFFFFE (AmiPart's defaults) |
| Reserved, every partition | 0 | 2 |
| PART SummedLongs | 64 | 128 |
| RDSK Flags / Park / RDBBlocksHi | 0x8 / 0 / 6399 | 0xC / 0x3FE0 / 3 |

The ADDPART syntax has no BootBlocks, MaxTransfer or Mask option. The GUI's Advanced dialog may have them, but it
runs only on the Amiga and was not tried. For the r6d M6 case (an A4092 disk at priority 2 outranking the CD
installer's priority 1), the safe host-side fix is ours: rewrite the one PART field and its checksum with `rdb.py`,
or let `/etc/rdb -p N -P <pri>` do it on the box. AmiPart's CLI cannot do it without damage.

## (c) Pre-partitioned empties as a download: no

- The installer authors the RDB on the box (`/etc/rdb`, then mkfs), and its interview starts from a blank disk.
  A pre-partitioned disk is not blank, so the unattended path refuses it unless TARGET_ERASE_OK is set.
- AmiPart cannot write our PART fields (BootBlocks, MaxTransfer, Mask, Reserved), as shown in (b).
- The empties stay zero-filled.

## For the 1.1 list

Optional: an AmiPart INFO cross-check in a host selftest, as an independent reader of the RDBs we author. Do not use
it to write Amix disks.
