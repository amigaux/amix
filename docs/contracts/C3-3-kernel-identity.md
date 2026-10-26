# C3-3 — the module kernel's identity record and the sidecar (C2-3 version 5), version 4

- **Status:** agreed 2026-10-26 (orchestrator), version 1; version 2 (2026-10-26): a stage-3 module kernel writes `root=`/`rootfs=`, and the first root-class module in a generation is what ends that (§3); version 3 (2026-10-26): the fingerprint's text, reference, tool and checks (§4); version 4 (2026-10-26): abi= required on a module kernel, k46.1.0's one rewrite done, equal fingerprints across lines (§4). Other repositories build against this text; a change from here is a contract change with a version bump. §3 is version 5 of C2-3 (the sidecar).
- **Implements:** `docs/spec/10-boot-loader.md` §5.1–§5.3,
  `20-module-format-and-abi.md` §1.2, §3.1, `40-generations-and-composer.md`
  §3.1 (gates 2, 4, 6, 7)
- **Built by:** the module kernels: k46 in amix-040-060-port (S3-20), k30
  in amix-kerntools (S3-21)
- **Read by:**
  - boot2, loader version 2 (S3-15): the record, before it fills the
    arena;
  - `kbootset` (S3-16): the sidecar;
  - the module core: its own record, at `dmainit`;
  - `kinfo`: the kabi and build id, as today.

## 1. Image offsets

Every offset here is from the kernel's bind address, in the layout boot2
gives the image (`loader/common/rel.h`):
- for `ET_REL`: `.text`, `.rodata` and `.data`, contiguous with no
  padding, then `.bss` and COMMON;
- for a `brel`: the combined section, from its first byte.

So for `ET_REL`, a `.data` object's image offset is the size of `.text`,
plus the size of `.rodata`, plus the object's offset in `.data`. The kernel
build computes it from the final link, writes it into the sidecar, and
checks it with the post-link gate's relocation (C3-2 §2).

## 2. The identity record `AXK1`

A `.data` object `dlm_ident`, 4-byte aligned, big-endian:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `AXK1` |
| 4 | 4 | version 1 << 16 \| length (64) |
| 8 | 4 | check: all longwords of the record sum to zero (as `AXL1` and `KIF1`) |
| 12 | 24 | kabi tag, NUL-padded: `k46.1.0` |
| 36 | 4 | line: 30 or 46 |
| 40 | 4 | arena image offset |
| 44 | 4 | arena capacity in bytes, a multiple of 64 KiB |
| 48 | 4 | symbol block image offset (`dlm_ksym`, C3-2) |
| 52 | 4 | symbol block size |
| 56 | 4 | flags: 0x1 module kernel; other bits 0 |
| 60 | 4 | 0 |

The record holds no addresses, only image offsets. Its bytes are therefore
the same in the file and in memory at any bind address, and the check holds
in both. The build id is not repeated here: it stays where it is today, the
kernel's buildid string, which `kinfo` and `uname -m` read.

**boot2's check** (10 §5.2), after relocating the kernel and before it
writes the arena, when the manifest has an `ident` record:
- the magic, the version, the length and the check;
- the kabi tag equal to the manifest's `kabi` line;
- the line equal to the manifest's `line`;
- arena offset and capacity equal to the manifest's `arena` line.

On any mismatch boot2 refuses the generation:
`amix-boot: L14 kernel identity does not match the manifest`, then as L2
(the next candidate in the order of 10 §7.2). That is a new code; 10 §9's
table gains it at agreement. A manifest without
`ident` and `arena` (a static kernel, stages 1 and 2) skips the check,
which is how today's kernels keep booting.

**The core's check** at `dmainit`: its own record, the magic and the check,
before it reads the arena (C3-4).

## 3. The sidecar, version 5

C2-3 §2's keys stay. For a module kernel they read as follows; three keys
are new:

```
kabi=k46.1.0                 the module kernel's tag; "static" stays for stage-2 kernels
family=generic               the module kernel; static families keep their name
line=k46
pin=gcc-2.7.2.3-8949028
build=68060-261101-NN
size=…                       of unix as shipped
sha256=…                     of unix as shipped
bss=…                        required for a brel, as in version 4
loader-min=2                 a module kernel needs loader version 2 (C3-4)
ident=0x001f1fc0             image offset of AXK1                       (new)
arena=0x001f2000 0x00080000  image offset and capacity, equal to AXK1's
ksym=0x001e8000 0x00002400   image offset and size of the symbol block  (new)
abi=<64 hex>                 the binary fingerprint (§4)                (new)
root=zorro:144b:01           built-in root controllers, through stage 3 (below)
rootfs=ufs,s5                built-in root filesystems, through stage 3
```

**`root=` and `rootfs=`.** Through stage 3 a module kernel writes
`root=`/`rootfs=` for its built-in root controllers and filesystems, as a
static kernel does: its root drivers are still linked in, and it has no
root-class modules. From stage 4, with root-class modules, it writes
neither.

The trigger is the generation, not a date or a stage number: **the first
root-class module (`module … root`) in a generation.** `kbootset`'s gate 3
tells the two cases apart from the manifest alone:
- a generation with no root-class module is closed by the kernel's
  `root=`/`rootfs=`, which must name the boot and root disks' controllers
  and the root filesystem, as for a static kernel;
- a generation with at least one root-class module is closed by its
  root-class modules' `match` keys and `fs` (C3-1 §3); the kernel's
  `root=`/`rootfs=` are not read, and a kernel built only for such
  generations omits them.

What `kbootset` does with them (S3-16):
- gate 2: `kabi`, `pin`, and each module's `kabi`/`cc` against them;
- gate 3: `root=`/`rootfs=` while the generation has no root-class module
  (above);
- gate 4: `arena` (stage 4 places root modules; in stage 3 the arena holds
  only the directory and the manifest copy, C3-4);
- gate 6: kernel + `bss` + the arena;
- gate 7: `loader-min`.

It writes the manifest's `ident 0x…`, `arena 0x… 0x…` and `kabi` lines
from the sidecar. `ident` is a manifest record new with loader version 2.
An older loader ignores it, and `loader-min 2` keeps such a loader from
booting the generation anyway.

## 4. The fingerprint `abi=`

The SHA-256 of a text the kernel build writes, one line per item, sorted:
- every DDI-tier data symbol's name and `st_size` from the final link;
- the probe module's structure-offset table (`cdevsw`, `streamtab`,
  `qinit` and the other offsets the core generates, 30 §2 patch 15).

**The text**, ASCII, one item per line, each ending in a newline, the
lines sorted bytewise:

```
data <name> <st_size>     each name abi/<line>/ddi.list marks data, from the final link
offs <NAME> <value>       each #define of dlm_offs.h: tools/mkoffs over dlmoffs.c (the probe),
                          compiled against the kernel's headers (the brief's step 2)
```

`abi=` is the SHA-256 of that text, 64 lowercase hex digits. The core tier
(C3-2 §4, stage 5) adds its data names when it is written.

**The tool** is `tools/mkabi.py` (the kit ships it, with the probe
`dlmoffs.c` and `tools/mkoffs`). It runs at the brief's step 9, on the
final link as it ships:
`mkabi.py --check abi/<line>/abi-<kabi>.txt <kernel> abi/<line>/ddi.list dlm_offs.h`
prints `abi=…` for the sidecar (step 11) when the text equals the
reference, and otherwise names each line that moved and fails.

**The reference** is the text of the last fingerprint of each tag,
`abi/<line>/abi-<kabi>.txt`, tracked in amix-dlm and shipped in the kit. A
new tag's first text is written with `mkabi.py --text` and committed
there with the tag's kit change. The k30.1.0 text was written from the
S3-21 cut. k46.1.0's was rewritten once, from the stage-3 re-cut
(KD060-Z build 68060-261026-54), when the port gave `cputype` its size:
`data cputype 0` became `4`, and nothing else moved. The rule binds both
tags from now on.

**The two lines' fingerprints may be equal, and today they are**
(`7a90c7d9…`): the same DDI data names at the same sizes, and the same
structure offsets. That is expected, not a clash. The fingerprint guards
a tag against drift, and the kabi tag tells the lines apart: a module
carries `k30.…` or `k46.…`, and gate 2 and the core compare the family
first.

**The rule (20 §3.1):** the build fails when `abi=` changes and the kabi
tag does not. An added symbol raises the minor. A changed size or offset,
or a removed symbol, raises the major. The kit keeps the text of the last
fingerprint per tag, so the failure names what moved.

**Where it goes, and who checks it.** `abi=` is a sidecar key only. It is
not in the manifest (GMF1 and its records do not change, C3-5 §4) and not
in `AXK1`. It is checked at build time, where it can still stop a
mismatched kernel: the kernel build fails on it, and the kit's probe,
measured through the kit's headers, must give the same offsets
(`make kit-test`). At run time the kabi tag, which modules carry and gate
2 compares, stands for it. `kbootset` refuses a module kernel whose
sidecar has no `abi=`, or one that is not 64 hex digits (gate 2). boot2
and the core never read it.

## 5. Settled at agreement

- `AXK1` as above, with no addresses in it; its check holds in the file and
  in memory.
- Image offsets measured from the bind address in `rel.h`'s layout.
- The new sidecar keys `ident`, `ksym` and `abi`; `loader-min=2`.
- Version 2: `root`/`rootfs` on a module kernel through stage 3; the first
  root-class module in a generation is the stage-4 trigger for gate 3.
- Version 3: the fingerprint's text form, the reference per tag in
  amix-dlm and the kit, `tools/mkabi.py` at the brief's step 9, and the
  checks of §4 (build time; kbootset the form only).
- Version 4: `abi=` required on a module kernel's sidecar (gate 2), once
  both re-cut kernels carried it; k46.1.0's one rewrite; equal
  fingerprints across lines expected.
- The manifest record `ident`.
- The new loader code L14 (L1–L13 are taken).
