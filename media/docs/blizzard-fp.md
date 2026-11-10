# The Blizzard FP fix — the 13-instruction FP-elimination patch for the two ufs binaries

> **The test bench.** Where this document names `tools/install-matrix.sh`, `mkroot.sh`,
> `build-miniroot.sh`, `build-ramdisk-miniroot.sh`, `build-raw-source.sh`, `miniroot/miniroot.proto`,
> `configs/*.uae`, `profiles/cards`, `cards/`, `floppies/`, `work/…` or a sibling repository (`../amix-*`), it
> names the test bench's tools, configurations and run records. They are not in this repository: the
> bench authors the RAM-disk miniroot, runs the install matrix and keeps the evidence. This repository
> builds the media with `media/build.sh` (`media/README.md`), a step of make dist.

**Status: DONE — all three pre-registered gates passed, 2026-08-25 (see §7).** Binding:
`../docs/BLIZZARD.md` §5, the census verdict and the **ruling** —
*"the 13-instruction integer-math patch to mkfs_ufs+fsck_ufs (installed + miniroot
copies)"*. Census evidence: the maintainer's notes (`CENSUS.txt`,
`dis-fsck.txt`, `dis-mkfs-ufs.txt`, `mkfs/mkfs-real.txt`, `lc/fsck-deepdive.txt`).
Every number below was **re-verified in this repo against the binaries themselves**
before being built on; where re-verification corrected the brief it is marked
**`BRIEF CORRECTION`**.

The standing rule *check the 030 installer history first* applies to
anything touching `install.sh`/media. It does not fire here: this round changes no
script, no install order and no media layout — it changes 180 bytes inside two 1991
SVR4 executables and wires those two members into the miniroot build.

---

## 0. What this is, in one paragraph

On a 68060 **without** an FPU (the LC060 the BLIZZARD campaign targets) exactly two
install-path binaries take vector 11 and die: `mkfs_ufs` at its banner (before it writes
anything) and `fsck_ufs` at its summary line (after all repairs, but *upstream* of
everything that marks the filesystem clean). Both traps are **display-only** — a
percentage and two megabyte figures. This patch replaces those expressions with exact
integer arithmetic that renders the same columns to the same precision, so the two
binaries carry **zero** coprocessor-1 instructions and the ufs install path becomes
FP-free end to end. It is not a soft-FPU and it is not a substitute for one; it is the
triage the census priced at 13 instructions.

---

## 1. The miniroot-member confirmation `MEASURED — SAME SOURCE`

The census brief flagged this as owed: the miniroot's own `/bin/mkfs_ufs` and
`/bin/fsck_ufs` are `stock-miniroot` members (`miniroot/miniroot.proto:87,95`) and were
**not yet confirmed same-source** as the installed `/etc/fs/ufs/{mkfs,fsck}`.

Extracted from the stock root floppy `floppies/orig/amix_21_root.adf` through
`tools/lib/s5.py` (inode 15 `mkfs_ufs`, inode 27 `fsck_ufs`):

| member | miniroot size | installed size | mapped image (file `0x34`..end of last LOAD) |
|---|---|---|---|
| `mkfs_ufs` | 19,664 B | 20,092 B | **byte-identical** |
| `fsck_ufs` | 45,548 B | 111,580 B | **byte-identical** |

The only differing bytes in the whole file are in the **ELF header**: `e_shoff`
(bytes 32–35) and `e_shnum`/`e_shstrndx` (bytes 48–51) — 3 bytes differ in `mkfs`,
5 in `fsck`. Section table, VMAs and file offsets are identical section for section.
The miniroot copies are the **same build**, stripped of `.comment` (both) and of
`.debug`/`.line`/`.symtab` (`fsck`). `install.sh:851`'s 45,548 B figure is that
stripped `fsck`.

**Consequence, and it is the load-bearing one:** one patch, expressed in *file offsets
inside the LOAD segments*, applies unchanged to all four binaries. There is no
per-copy variant, and the same assert-old-bytes gate protects all four.

SHA-256 of the extracted stock miniroot members (pre-patch):

```
mkfs_ufs  61de819dd6e1b5798a96c4ed3bc4431d4828527a4de9b1213ca4e0234c453c91
fsck_ufs  3b095d05ffce95884fd61e1acbd0b3dd010568bce7347bfc51296fb39723fd22
```

---

## 2. The two sites, re-measured

Both binaries are non-PIC ELF with two LOAD segments, `p_align 0x2000`; the data
segment carries `PF_R|PF_W|PF_X`. File-offset ↔ VMA is affine per segment:
text `file = VMA - 0x80000000`, data `file = VMA - 0x80002000` (both binaries).

### 2.1 `fsck_ufs` — `checkfilesys`, the fragmentation percentage

Four consecutive FP instructions at `0x800018ca`..`0x800018dd`, inside one expression
(census `lc/fsck-deepdive.txt`; re-disassembled here):

```
800018c2  7064            moveq   #100,%d0
800018c4  4c2e 0800 fffc  mulsl   %fp@(-4),%d0        ; 100 * n_ffree
800018ca  f200 4000       fmovel  %d0,%fp0            <-- THE KILL
800018ce  f239 4080 …2c4c fmovel  sblk+0x38,%fp1      ; the divisor
800018d6  f200 0424       fsgldivx %fp1,%fp0          ; SINGLE-precision divide
800018da  f227 7400       fmoved  %fp0,%sp@-
800018de  201f/221f/2f01/2f00                         ; a no-op hi/lo re-push
800018e6  2f2e fff4       movel   %fp@(-12),%sp@-     ; n_bfree
800018ea  2f2e fffc       movel   %fp@(-4),%sp@-      ; n_ffree
800018ee  4879 8000 b3e4  pea     LC%34
800018f4  4eb9 8000 7f0e  jsr     pwarn
800018fa  defc 0014       addaw   #20,%sp
```

The window `0x800018c2`..`0x800018f3` is **50 bytes**. Stack consumed by the call is
20 bytes (`fmt` + two longs + one double); replacing the double with two longs keeps
it at 20, so `addaw #20,%sp` stays correct and is not touched.

`%fp@(-4)` is the value printed as `%d frags`; `%fp@(-12)` as `%d blocks`; the divisor
is the absolute datum at `0x80012c4c`. This matches the BSD `fsck` source shape
`(float)(n_ffree * 100) / sblock.fs_dsize` exactly, including the `fs_frag * n_bfree +
n_ffree` sum three instructions earlier (`sblk+0x48` = `fs_frag`, i.e. a 16-byte
`bufarea` header, which puts `sblk+0x38` at `fs_dsize`).

**Inbound control flow:** exactly one branch enters the window — `beqw 800018c2` at
`0x800018b0`, targeting the window's **first** byte, which does not move. Nothing else
in the image branches into it and no 32-bit datum anywhere in the file points into it
(scanned, whole mapped image).

### 2.2 `mkfs_ufs` — the geometry banner

Nine FP instructions at `0x800020a0`..`0x800020e1`, all feeding one `printf`:

```
80002094  45f9 8000 088c  lea     printf@plt,%a2
8000209a  4e92            jsr     %a2@                ; printf #1 (integer, prints fine)
8000209c  2f2b 00b8       movel   %a3@(184),%sp@-     ; fs_ipg
800020a0  f22b 4080 00bc  fmovel  %a3@(188),%fp1      <-- THE KILL (fs_fpg)
800020a6  f22b 4000 0034  fmovel  %a3@(52),%fp0       ; fs_fsize
800020ac  f200 00a7       fsglmulx %fp0,%fp1
800020b0  f23c 54a3 …     fmuld   #1e-06,%fp1
800020bc  f227 7480       fmoved  %fp1,%sp@-          ; the %.2f arg
800020c0  2f2b 00b4       movel   %a3@(180),%sp@-     ; fs_cpg
800020c4  2f2b 002c       movel   %a3@(44),%sp@-      ; fs_ncg
800020c8  f22b 4080 0024  fmovel  %a3@(36),%fp1       ; fs_size
800020ce  f200 00a7       fsglmulx %fp0,%fp1
800020d2  f23c 54a3 …     fmuld   #1e-06,%fp1
800020de  f227 7480       fmoved  %fp1,%sp@-          ; the %.1f arg
800020e2  4879 8000 5d6d  pea     LC (the geometry format)
800020e8  4e92            jsr     %a2@
800020ea  defc 0038       addaw   #56,%sp             ; cleans BOTH printf calls
```

`%a3` = `0x800069dc` = the start of `.bss` = the in-core superblock; the offsets are the
classic UFS superblock layout (`fs_size` 36, `fs_ncg` 44, `fs_fsize` 52, `fs_cpg` 180,
`fs_ipg` 184, `fs_fpg` 188), which is what makes the two banner lines legible.

The FP window `0x8000209c`..`0x800020e9` is **78 bytes**. The call's stack block is
32 bytes (`fmt`, double, `ncg`, `cpg`, double, `ipg`); two doubles → four longs keeps it
at 32, so the shared `addaw #56,%sp` stays correct and is not touched.

**Inbound control flow:** nothing branches into `0x80002068`..`0x800020e9` and nothing
points into it (scanned, whole mapped image) — which is what licenses §4.2's slightly
larger rewrite window.

---

## 3. The arithmetic, and why it reproduces the column exactly

Every displayed field is `round_half_up(A / S)` for positive integers `A`, `S`, then a
split into integer part and fraction. The identity used throughout is

> **`round_half_up(A/S) == (floor(2A/S) + 1) >> 1`**
>
> *Proof.* Write `A/S = m + f`, `0 ≤ f < 1`. Then `floor(2A/S) = 2m + floor(2f)`, which
> is `2m` when `f < ½` and `2m+1` when `f ≥ ½`. Adding 1 and shifting right by one gives
> `m` in the first case and `m+1` in the second — which is `floor(A/S + ½)`. ∎

so one extra `addq.l #1` + `lsr.l #1` (4 bytes) buys correctly-rounded output with no
second divide and no remainder compare. Concretely:

| field | value | integer form |
|---|---|---|
| `fsck` `%.1f%%` | `100·n_ffree / D` shown to 0.1 | `T = (floor(2000·n/D)+1)>>1`; print `T/10` `.` `T%10` |
| `mkfs` `%.1fMb` | `fs_size·fs_fsize·1e-6` to 0.1 | `T = (floor(B₁/50000)+1)>>1`; print `T/10` `.` `T%10` |
| `mkfs` `%.2fMb/g` | `fs_fpg·fs_fsize·1e-6` to 0.01 | `H = (floor(B₂/5000)+1)>>1`; print `H/100` `.` `H%100` (`%02d`) |

> ### ★ MEASURED CORRECTION (2026-08-25, the FPU bench rig) — the 64-bit forms are fatal
>
> This section originally read: *"All three multiplies use the **64-bit** `MULU.L
> <ea>,Dh:Dl` and all three scale-divides the **64-bit** `DIVU.L <ea>,Dr:Dq` — same
> encoding length as the 32-bit forms on this core, so exactness is free."* **That
> prediction is REFUTED, and it is scored as a miss.** The first block cut that way
> ran the five phases and then died: `Killed`, `rc=137` — **SIGKILL**, not SIGSYS, and
> on the **hardware-FPU** rig, so nothing to do with the FPU.
>
> The **MC68060 does not implement 64-bit `MULU.L`/`MULS.L`/`DIVU.L`/`DIVS.L`** (nor
> `CMP2`/`CHK2`/`CAS2`/`MOVEP`); they raise the *unimplemented integer instruction*
> exception, **vector 61**, which Motorola's 060SP is supposed to complete. This AMIX
> kernel has no 060SP integer arm and `u_trap`'s table stops at vector 55, so vectors
> 60/61 fall through to a bare `SIGKILL` — exactly what
> `M68060-SUPPORT-LANDSCAPE.md:44` already recorded, and exactly what we walked into.
> The bench found it in one run; a static review would not have.
>
> **The patch therefore uses 32-bit forms only** — `MULU.L <ea>,Dl`, `DIVU.L <ea>,Dq`
> and `DIVUL.L <ea>,Dr:Dq`. Those are not a guess either: the *stock* binaries already
> execute both (`mulsl %fp@(-4),%d0` in `fsck`, `divsll %d5,%d0,%d1` in `mkfs`) on this
> very rig, so their implementation on the 68060 is proven by the code being replaced.
> The cost is a bound instead of exactness — see below. The correction changes no size:
> both blocks still fill their windows exactly (`fsck` 48 B of code + a 2-byte pad).

Every multiply is the **32-bit** `MULU.L <ea>,Dl` and every scale-divide the 32-bit
`DIVU.L <ea>,Dq`, so each scaled product must fit in 32 bits:

| field | exact while | what that means |
|---|---|---|
| `fsck` `%.1f%%` | `2000·n_ffree < 2³²` | `n_ffree < 2,147,483` **free fragments**. `n_ffree` counts only fragments in partially-allocated blocks; the bench rig's 545 MB root carries **3,216** — three orders of margin. The stock code's own `moveq #100` + **signed** `mulsl` overflows at 21.4 M, so this is the same class of bound, not a new one. |
| `mkfs` `%.1fMb` | `fs_size·fs_fsize < 2³²` | a filesystem **under 4 GiB** |
| `mkfs` `%.2fMb/g` | `fs_fpg·fs_fsize < 2³²` | a cylinder group under 4 GiB — unreachable |

Past those bounds the *displayed number* is wrong; nothing else is, because the value is
display-only and every byte that shapes the filesystem is upstream of it.

**BRIEF CORRECTION.** The brief says *"the numerator is already integer in `%d0`"* for
`fsck` and invites reusing it. The replacement does **not** reuse it: `moveq #100` +
`mulsl` is a *signed 32-bit* product that overflows at `n_ffree > 21.4 M`, and scaling it
by a further ×10 or ×20 would drop that bound to ~2.1 M. Loading `%fp@(-4)` afresh and
multiplying by 2000 in 64 bits costs the same 12 bytes and has **no** bound at all.
**Superseded by the ★ MEASURED CORRECTION above:** that "no bound" property is true
only in isolation from this platform — the MC68060 does not implement the 64-bit
`MULU.L`/`DIVU.L` forms at all, so the correction they cost is not a display-only
inexactness but a bare `SIGKILL`. The shipped patch uses the bounded 32-bit forms
above, never the 64-bit ones this paragraph describes.

### 3.1 The three divergences, declared before the runs

1. **Half-way decimals.** The original prints a `float` through SVR4 `_doprnt`; our
   value is exact and rounds half **up**. A disagreement is only possible when the true
   value lands exactly on a `x.x5` (or `x.xx5`) boundary *and* `_doprnt` rounds
   half-to-even. Where the FPU-rig oracle shows such a case, the integer result is the
   correctly-rounded one and the divergence is reported, not papered over.
2. **`float` precision.** The originals compute through `FSGLMUL`/`FSGLDIV`
   (24-bit mantissa) before the `double` promotion, so the *original* is the inexact
   side: for `mkfs` the product error can reach ~256 bytes ⇒ ~2.6·10⁻⁴ Mb, four orders
   below the displayed digit.
3. **Divide by zero.** `fsck`'s divisor is `fs_dsize`. If it were 0 the original prints
   `inf`; ours takes the 68k zero-divide trap (SIGFPE). `setup()` validates the
   superblock before `checkfilesys` reaches this line, and a 0-`fs_dsize` filesystem has
   no data blocks at all. Accepted, recorded, not guarded — the window is exactly full.

---

## 4. The patch, byte for byte

Both format strings would **grow** (`%.1f`→`%d.%d` is +1, `%.2f`→`%d.%02d` is +3) and
the string pools are packed with zero slack. Neither binary grows: the bytes are found
by *de-duplicating strings that already exist elsewhere in the same image*.

### 4.1 `fsck_ufs` — 3 edits, 103 bytes touched

| # | file offset | len | what |
|---|---|---|---|
| F1 | `0x018b6` | 4 | `pea` operand `0x8000b3e2` → `0x8000b3c4` — `LC%33` is `"\n\0"`; `0x8000b3c4` is the `"\n\0"` that terminates `"** Phase 5 - Check Cyl groups\n"`. Same two bytes, so the preen newline is unchanged. |
| F2 | `0x093e2` | 47 | the freed 2 bytes + the old 45-byte format = 47, into which the new **46-byte** `"(%d frags, %d blocks, %d.%d%% fragmentation)\n"` is written, NUL-padded to 47. |
| F3 | `0x018c2` | 50 | the code (below). |

```
	moveq	#125,%d0
	mulu.l	-4(%a6),%d0		| d0 = 125 * n_ffree
	lsl.l	#4,%d0			| d0 = 2000 * n_ffree
	divu.l	0x80012c4c,%d0		| d0 = floor(2000*n / fs_dsize)
	addq.l	#1,%d0
	lsr.l	#1,%d0			| = round(1000*n/D), tenths of a percent
	divul.l	#10,%d1:%d0		| d0 = whole, d1 = tenth
	move.l	%d1,-(%sp)
	move.l	%d0,-(%sp)
	move.l	-12(%a6),-(%sp)		| n_bfree
	move.l	-4(%a6),-(%sp)		| n_ffree
	pea	0x8000b3e2
	nop				| pad
```

2 + 6 + 2 + 8 + 2 + 2 + 8 + 2 + 2 + 4 + 4 + 6 = 48 bytes of code + a 2-byte pad =
**50 bytes**, an exact fill of the window.
Nothing outside the three edits changes; `addaw #20,%sp` and the `beqw` target are
untouched. **Census A3 is honoured by construction**: `LC%32` (`"%d files, %d used, %d
free "`, no newline) is not touched and its `pwarn` still runs immediately before, so
the two halves remain one stdio write and the newline still arrives from this line.

### 4.2 `mkfs_ufs` — 6 edits, 255 bytes touched

The FP window alone (78 B) cannot hold the replacement (86 B). Eight bytes are recovered
from the **four instructions immediately before it** by re-encoding absolute operands as
PC-relative — same instruction, same semantics, shorter encoding — which is legal here
because nothing branches or points into `0x80002068`..`0x800020e9`:

| was | becomes | saves |
|---|---|---|
| `lea 0x800069dc,%a3` (6) | `lea (0x4966,%pc),%a3` (4) | 2 |
| `mulsl 0x80006a58,%d5` (8) | `mulsl (0x49d8,%pc),%d5` (6) | 2 |
| `pea 0x80005d34` (6) | `pea (0x3ca8,%pc)` (4) | 2 |
| `lea 0x8000088c,%a2` (6) | `lea (0xe7fc,%pc),%a2` (4) | 2 |

and the new `pea` of the geometry format is PC-relative too (4 instead of 6). The
rewritten block is `0x80002068`..`0x800020e9` = **130 bytes**, an exact fill, ending
precisely on the untouched `addaw #56,%sp`.

| # | file offset | len | what |
|---|---|---|---|
| M1 | `0x02068` | 130 | the code block (prologue re-encoded + the integer banner) |
| M2 | `0x03d6d` | 101 | the string zone, recompacted: new 57-byte geometry format, then `"super-block backups (for fsck -b#) at:"` (39 B, **copied from the original bytes**, not retyped) at `+57`, then `" %d,"` (5 B, likewise) at `+96`. The two `"\n\0"` strings that used to sit between them are dropped. |
| M3 | `0x020f0` | 4 | `pea` operand `0x80005da2` → `0x80005da6` |
| M4 | `0x0211e` | 4 | `pea` operand `0x80005dc9` → `0x80005d32` (the `"\n\0"` that ends `"…preference %s\n"`) |
| M5 | `0x0215a` | 4 | `pea` operand `0x80005dcb` → `0x80005dcd` |
| M6 | `0x02174` | 4 | `pea` operand `0x80005dd0` → `0x80005d32` |

Each of those five string addresses is referenced from **exactly one** place in the whole
mapped image (scanned; no pointer tables). New format string, 57 bytes with its NUL:

```
\t%d.%dMb in %d cyl groups (%d c/g, %d.%02dMb/g, %d i/g)\n
```

### 4.3 Blast-radius accounting

| binary | bytes in file | site spans rewritten | bytes that actually differ | FP instructions before → after |
|---|---|---|---|---|
| `fsck_ufs` (miniroot) | 45,548 | 103 | 87 | 4 → 0 |
| `fsck_ufs` (installed) | 111,580 | 103 | 87 | 4 → 0 |
| `mkfs_ufs` (miniroot) | 19,664 | 255 | 211 | 9 → 0 |
| `mkfs_ufs` (installed) | 20,092 | 255 | 211 | 9 → 0 |

(Site spans: `fsck` 6 + 47 + 50, `mkfs` 130 + 101 + 4×6. The `pea` edits assert the
opcode word as well as the operand, so 2 of each 6 are rewritten identical.)

File sizes, section tables, program headers, symbol tables and every other byte are
unchanged. No section moves; no address moves.

---

## 5. Pre-registered acceptance

Written before the patch was applied. All three must pass; a miss is reported as a miss.

1. **Byte-diff.** For each of the four binaries, the diff against its unpatched original
   consists of exactly the edits in §4 and nothing else; file length unchanged; a
   host disassembly of the patched image shows **zero** coprocessor-1 instructions in
   either binary (`fpscan`-equivalent count 0), and the rewritten blocks disassemble to
   the intended instructions at the intended addresses.
2. **FPU-oracle parity.** The patched binaries, run on the hardware-FPU bench rig
   (`f2m0-fpu` lineage, `fpu_model=68060`), print **the same displayed values** as the
   unpatched binaries on the same filesystems — same `mkfs` banner text, same `fsck`
   summary text, byte for byte. Any difference must be a §3.1 boundary case with the
   integer value shown to be the correctly-rounded one.
3. **The LC gate.** On the FPU-less rig (`f2m0-lc` lineage, `fpu_model=0`):
   `mkfs_ufs` completes a real `mkfs -F ufs` on a real slice and `fsck_ufs -y` repairs a
   dirty filesystem all the way to `FILE SYSTEM STATE SET TO OKAY`, with the kernel
   counter `f60_fpudis_nofpu_n` showing **zero** kills across both.

A host-side pre-gate runs first because it is nearly free: the same arithmetic, both
ways, under `qemu-m68k`, swept over realistic geometries. It does not replace gate 2 —
it fails cheap before the rigs are booted.

## 6. Media integration

`tools/patch-ufs-fp.py` is idempotent, asserts the old bytes at every site before
writing, refuses on any mismatch, and can report `--check` without writing. It patches a
plain file or, with `--s5 IMAGE PATH`, a member **in place inside an s5 image** — which
is exactly what the miniroot needs, because the patch preserves length, so the inode,
the size and the block list are all untouched.

The miniroot build (`tools/build-miniroot.sh`) starts from a byte copy of
`floppies/orig/amix_21_root.adf` and preserves `stock-miniroot` members untouched; the
patch is applied after that copy, under an explicit flag (`MINIROOT_FP_PATCH=yes`), and
`miniroot/miniroot.proto` records the two members' changed provenance. That miniroot
build is not re-run here — the miniroot digest is re-attested on the build that turns
the flag on.

### 6.1 The INSTALLED tree — `--ufs`, and why it is not the CD package set

An earlier revision of this section said the installed copies "live in the CD package
set and are patched where that set is staged". **That is not a workable route and was
never taken.** `pkgadd` verifies each object against its package's `pkgmap` cksum, so
patching `core-2.1.pkg` makes the install itself complain about the two files it is
laying down. The installed copies therefore arrive **unpatched on every target**, which
is the gap this section closes: on an FPU-less 68060 that means a shipped image cannot
author or repair its own root, which is precisely the failure the patch exists to
prevent, reintroduced one layer down.

The route that works is to patch them **after** the install, in the target's own
filesystem:

```
tools/patch-ufs-fp.py --ufs TARGET.hdf --slice 1 /etc/fs/ufs/mkfs /etc/fs/ufs/fsck
tools/patch-ufs-fp.py --ufs TARGET.hdf --slice 1 --check /etc/fs/ufs/mkfs /etc/fs/ufs/fsck
```

`--ufs` is the exact analogue of `--s5`, and it rests on the same property: the patch
preserves every length, so the member's inode, its size and its block list are untouched
and only bytes already inside allocated fragments change. `--slice` names the RDB slice
(omit it for a bare-slice image); paths resolve from the filesystem root.

**This is not a host-side UFS writer, and the distinction is the design.**
`docs/ufs-target-scoping.md` §3.3 records the deliberate decision not to have one. A
writer allocates, frees, grows and rewrites metadata; this allocates nothing, frees
nothing, moves nothing and writes no metadata. A **hole is refused, not filled** — filling
one would be an allocation, and that refusal is the line between the two things. The
reader half is `tools/lib/ufs.py`, already gated.

**The attested digest does not move, by construction.** `altroot_attest.py`'s record is
`path \0 ftype \0 mode \0 uid \0 gid \0 size \0 linktarget \0 rdev` — no checksum and no
content hash (its own `FIELDS`), and `size` is what this patch preserves. A patched image
still attests at its set's reference digest, so the regression gate is unaffected. What
*does* notice is `pkgchk(1M)`, which compares the contents DB's own cksum: those two
paths will report a checksum mismatch. That is the same declared exception
`miniroot.proto` already carries for the miniroot pair, now stated for the target too.

**Gate:** `tools/patch-ufs-fp.py --self-test`, wired into `tools/run-checks.sh`. It runs
on `ufs.py`'s synthetic fixture with a made-up payload — no Commodore bytes — and proves
the locator agrees with the trusted reader, that a same-length scatter-write round-trips
across the single-indirect boundary and the fragment tail, that nothing outside the
located extents is touched, and that every refusal fires. Both halves were fault-injected
before landing: an off-by-one in the extent length trips six checks, and neutralising the
hole refusal trips that one.

**Licensing:** the patched binaries are derived Commodore bytes and are **never
committed**. What is committed is the tool, the assembly sources, the asserted old-byte
signatures and the SHA-256 of both inputs and outputs.

---

## 7. Results — scored against §5, 2026-08-25

Rigs: two `.uae` configs differing in **one key**, `fpu_model`, over one work copy of
the census seed `f2m0-seed.hdf` (sha256 `604a2b6f…`), repo amiberry build, tap anchor
.17. Evidence (gitignored, under `work/`) — `fpu-ab.out`, `lc-gate.out`,
`lc-miniroot.out`, `lc-prep.out`, and the two configs.

**Gate 1 — byte-diff. PASS.** For all four binaries the file length is unchanged and
every differing byte falls inside a §4 site (`fsck` 87 bytes differ across 3 sites,
`mkfs` 211 across 6). The miniroot and installed copies produce **identical change
patterns**, as §1 predicted. `fpscan` on the patched images: **`FP-CLEAN
(0 coprocessor-1 instructions)`** for both, against 9 and 4 before. Both rewritten
blocks disassemble to the intended instructions at the intended addresses under two
independent disassemblers (binutils 2.8.1, the era toolchain, and a modern one);
`beqw 800018c2`, `addaw #20,%sp` and `addaw #56,%sp` are untouched.

**Host pre-gates. PASS.** `oracle.py`: 0 differences in 12,162 realistic-`fs_dsize`
`fsck` cases and 32,568 `mkfs` cases. `seq.S` — the patch's own opcode and extension
words in a callable harness — 14,802 executions on an m68k CPU model, 0 mismatches.

**Gate 2 — FPU-oracle parity. PASS, byte-identical.** Three A/B pairs on the
hardware-FPU rig, each with a stock re-run as the determinism control:

| test | stock | patched |
|---|---|---|
| `mkfs /dev/rdsk/c6d0s2 30720` | `15.7Mb in 12 cyl groups (16 c/g, 1.33Mb/g, 512 i/g)` | **identical**, and so are the `Warning:`, the sectors/cylinders line, `super-block backups (for fsck -b#) at:` and all twelve backup numbers — i.e. the two relocated strings and their retargeted `pea`s are proven live |
| `fsck -n` on that fresh fs | `2 files, 9 used, 14374 free (14 frags, 1795 blocks, 0.1% fragmentation)` | **identical** |
| `fsck -n` on the live 545 MB root | `27863 files, 306195 used, 238550 free (3214 frags, 29417 blocks, 0.6% fragmentation)` | **identical** (and the stock control repeated it exactly, so the filesystem was stable across the triple) |

**The §3.1 half-way divergence, characterized rather than assumed.** `printf '%.1f'` of
`6.25 6.75 31.25 18.75` on the box gives `6.2 6.8 31.2 18.8`, and `%.2f` of `1.125` gives
`1.12`: SVR4's `_doprnt` rounds **half-to-even**, exactly as `oracle.py` models it. So
the divergence class is real but confined to values that land exactly on a `x.x5`
boundary — 0 of 12,162 realistic `fsck` cases, 0 of 32,568 `mkfs` cases, and 0 of the
six live comparisons above.

**Gate 3 — the LC gate. PASS.** Same image, `fpu_model=0`, console `no fpu detected`.
The scratch filesystem was made dirty the honest way: mounted, populated with 158
objects, and the emulator **hard-killed** with it still mounted. On the FPU-less rig the
patched `fsck -y` then ran all five phases, reconnected **20 UNREF FILEs**, salvaged
`BLK(S) MISSING IN BIT MAPS`, and printed

```
307 files, 1401 used, 12982 free (38 frags, 1618 blocks, 0.3% fragmentation)
/dev/rdsk/c6d0s2 FILE SYSTEM STATE SET TO OKAY

***** FILE SYSTEM WAS MODIFIED *****
```

— the line the census measured as structurally unreachable on this part. A second
`fsck -y` found it clean; `mkfs` then authored a fresh ufs on the real slice (full
banner, `rc=0`); mount/write/umount/`fsck -y` completed; and `fsck -n` on the live root
printed its full summary.

**The kill counter, bracketed across the whole run: `f60_fpudis_nofpu_n` 2 → 2** — the
two boot daemons (`lpsched`, `smtpd`) the census already attributed, and **not one kill**
from `mkfs` or `fsck`, across 26,479 kernel traps. `kvp_vec[11]` likewise 2 → 2.

**The miniroot members, executed as themselves.** §1's byte-identity argument was not
left as an argument: the patched **stripped** miniroot copies (19,664 B / 45,548 B, taken
out of `amix_21_root.adf` and patched by the same tool) were pushed to the same FPU-less
rig and run directly. `mr_mkfs` authored the slice with the same banner to the byte;
`mr_fsck -y` checked it and `mr_fsck -n` printed the live root's summary. Counter
unchanged again: **2 → 2** across a further 25,679 traps. All **four** binaries are
therefore proven, not three plus an inference.

**Scored miss.** §3's prediction that the 64-bit `MULU.L`/`DIVU.L` forms were "free"
was wrong and cost one bench round — see the boxed correction in §3. It is the only
pre-registration in this document that did not survive contact with the rig, and the
rig is where it was always going to be settled.
