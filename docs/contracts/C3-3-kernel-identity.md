# C3-3 — the module kernel's identity record and the sidecar (C2-3 version 5), version 1

- **Status:** agreed 2026-10-26 (orchestrator), version 1. Other repositories build against this text; a change from here is a contract change with a version bump. §3 is version 5 of C2-3 (the sidecar).
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
```

`root=` and `rootfs=` belong to static kernels. A module kernel has no
built-in root controllers and does not write them.

What `kbootset` does with them (S3-16):
- gate 2: `kabi`, `pin`, and each module's `kabi`/`cc` against them;
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

**The rule (20 §3.1):** the build fails when `abi=` changes and the kabi
tag does not. An added symbol raises the minor. A changed size or offset,
or a removed symbol, raises the major. The kit keeps the text of the last
fingerprint per tag, so the failure names what moved.

## 5. Settled at agreement

- `AXK1` as above, with no addresses in it; its check holds in the file and
  in memory.
- Image offsets measured from the bind address in `rel.h`'s layout.
- The new sidecar keys `ident`, `ksym` and `abi`; `loader-min=2`; no
  `root`/`rootfs` on a module kernel.
- The manifest record `ident`.
- The new loader code L14 (L1–L13 are taken).
