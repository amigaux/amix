# 20 — Module format and ABI

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §3 (both lines get the same module format), D-3 §4 (controllers and filesystems as modules need match keys, registries and a published ABI), D-3 §7 (the ABI kit is published in amix-dlm), D-3 §8 (Emre builds Gayle IDE against the kit; Antti reviews the ABI), D-3 §9 (kernel space on gcc-cross-amix; the ABI kit pins it)
- **Builds on:** P-28 D5, D6, D8, D10, D20, D58 (unchanged in substance); the adopted core's format (`tmp/2026-10-22-modules-proposal/ashnazag-dlm-core-map.md` §3)

Paths are relative to the Amix project workspace. `MAP` =
`tmp/2026-10-22-modules-proposal/ashnazag-dlm-core-map.md`, `STUDY` =
`tmp/2026-10-14-modules-study/STUDY.md`, `L2` =
`tmp/2026-10-14-modules-study/L2-our-kernels.md`.

## 1. Object format

### 1.1 Modules (both lines)

A module is one ELF32 big-endian relocatable object (`ET_REL`, `EM_68K`),
the format the adopted core loads (`MAP` §3):

- RELA relocations only (a `SHT_REL` section is refused); types
  `R_68K_NONE`, `32`, `16`, `8`, `PC32`, `PC16`, `PC8`, range-checked;
- exactly one `.symtab` with its string table;
- exactly one `.moddata` section (section type 13, written by `modfix`
  because binutils 2.8.1 cannot emit it);
- allocated sections of type PROGBITS, NOBITS or 13; image ≤ 2 MiB;
- the module name ≤ 14 characters.

The same format serves both lines; a module is built for one line (its
`kabi` family, §3) because the kernels differ in page size, layout and
exported symbols.

### 1.2 Kernel images per line

| Line | Kernel form | Relocations the loader applies | Source |
|---|---|---|---|
| 030 (k30) | `brel` (e_type 0xff00): `.text`+`.rodata`+`.data` merged into one section, compact 8-byte relocation pairs, no symbol table | R_68K_32 only (the only type the 030 kernels carry) | `amix-kerntools/contracts/bootchain-v1.json:383-395`; `amix-kerntools/tools/elf2brel.py` header |
| 040/060 (k46) | `ET_REL` with full symbol table, built by overriding the stock 2.1c binary | R_68K_32 plus 330 intra-`.text` PC-relative records (PC16 223, PC32 106, PC8 1) | `amix-kerntools/docs/040-kernel-line.md:10-22,395-415` |

Because the 030 kernel has no symbol table, everything a module needs from
the kernel comes through the exported-symbol block (§4), which is itself a
table of R_68K_32 `.long` relocations inside `.data` and therefore survives
`elf2brel` (to be confirmed for ~1000 entries, M-ABI2 = STUDY U6). The arena
offset and the identity record offset come from the kernel package's sidecar,
not from symbols (`10-boot-loader.md` §5.2).

Facts the format must respect on both lines (`tmp/2026-10-22-modules-proposal/refute-rel-c-last-writable-section.md`):
every kernel in the tree has exactly one writable PROGBITS section, `.data`;
the arena and the exported-symbol block live inside it.

## 2. `.moddata` version 2

The adopted core's `.moddata` is a relocation to the wrapper followed by
dependency names, and `MODREV == 1` in the wrapper is its only version check
(`MAP` §3). Version 2 keeps word 0 and adds a typed record list. The wrapper
revision becomes 2, so a version-1 core refuses a version-2 module with
`EBADVER` instead of misreading it.

```
word 0      R_68K_32 relocation to <prefix>_wrapper (unchanged)
bytes 4..7  "MD2\0"
then        NUL-terminated key=value strings, ending with an empty string
```

| Key | Content | Checked by |
|---|---|---|
| `name` | module name (≤ 14) | core |
| `kabi` | `<fam>.<major>.<minor>` (§3) | apkg, `kbootset`, core |
| `cc` | compiler pin id (§3.2) | apkg, `kbootset` |
| `cpu` | lowest CPU (`68020`, `68040`) | `kbootset`, loader (through the manifest) |
| `class` | `root`, `boot` or `demand` | `kbootset`, core |
| `match` | one or more keys: `zorro:MMMM:PP`, `mobo:<probe>`, `always` | loader (root class), core |
| `rank` | sd rank key, root-class disk controllers only (`30-module-core.md` §5) | core |
| `majors` | `c:<n>` / `b:<n>` from the registry (§6) | `kbootset`, core |
| `fs` | filesystem name for `vfs_register` | core |
| `depend` | comma-separated module names | `kbootset`, core |
| `unload` | `never` (default) or `allowed` | core |
| `param` | `<name>:<type>:<default>[:<min>:<max>]`, type `int`, `bool`, `str`, `hex` | `kbootset` (validates values), core |
| `tier` | `ddi` (default) or `core`: which tier of the exported-symbol block the module may resolve against (§4.1) | core |
| `build` | the kernel build id a core-tier module was built with; required with `tier=core` | core, `kbootset` |
| `desc` | one-line description | tools |

The exact syntax, limits and refusals are contract C3-1
(`docs/contracts/C3-1-module-object.md`). Rules: a zero match key is refused (a zeroed autoconfig row must never match,
P-28 risk 8); `mobo:` keys name a gated, positively identifying probe listed
in the registry (§6), never an address; a root-class module must carry
`match`, `rank` (disk controllers) or `fs` (filesystems).

Parameter values are not in the module: `kbootset` composes them from the
package's defaults and the administrator's overrides into the manifest
(`param` records, `10-boot-loader.md` §5.1), and the core passes them to the
module at load.

## 3. The kabi rule

### 3.1 The tag

`kabi=<fam>.<major>.<minor>`, families `k30` and `k46` (P-28 D5;
`STUDY` §2.9). A kernel accepts a module of the same family and major whose
minor is ≤ its own. The major changes when any of these change: a DDI
structure or calling convention, the wrapper, `.moddata`, a switch-table row
layout, the page size, the exported-symbol set (removal or semantic change).
Adding exported symbols raises the minor. Static kernels from stage 1 report
`k30.0.0` / `k46.0.0` and accept no modules.

The kernel package's sidecar records, next to the tag: the base identity (for
k46, the 040/060 port's base commit and build id), the compiler pin, the
semantic contract version, and a binary fingerprint (sizes of exported data
objects and a probe module's structure-offset table). The build fails when
the fingerprint moves and the tag does not (`STUDY` §2.9).

Whether the 68040 and 68060 kernels of the k46 family export the same ABI is
measured before the family is fixed (M-ABI1 = STUDY U7).

### 3.2 One compiler per kernel line, pinned

Every object in a kernel line's kernel space — the kernel's own passes, the
module core, every module of that line, and the loader — is built by one
pinned build of gcc-cross-amix (GCC 2.7.2.3, binutils 2.8.1,
`m68k-cbm-sysv4`, used through its wrapper with `AMIX_KERNEL_CFLAGS` and the
060-safe integer rewrite on; `gcc-cross-amix/README.md:5-20,204-306,496-562`).
The pin is a short id naming the toolchain commit and the flag set; it is
stored in the kabi sidecar and in each module's `cc` key. apkg and `kbootset`
refuse a module whose pin differs from its kernel line's. GCC 14 is never used
for kernel space (D-3 §9; its own README says so,
`gcc14-cross-amix/README.md:57-62`).

Changing the pin is a kabi major change for that line.

## 4. Exported symbols and DDI v1

### 4.1 The allowlisted table

Modules resolve kernel symbols only through an exported-symbol block
embedded in the kernel's `.data`, never through `/stand/unix` (P-28 D6). The
adopted core's block exports every global (160 KiB, `MAP` §4); ours exports
an allowlist of two tiers (`STUDY` §2.3):

- **DDI tier** — the stable interface for outside modules. Version 1 is
  about 75 names: console and errors (`printf`, `cmn_err`, `panic`),
  memory (`kmem_alloc`/`kmem_zalloc`/`kmem_free`, `sptalloc`/`sptfree`,
  `dma_alloc`/`dma_free`, `vtop`), copy and string helpers, sleeping and
  timers (`sleep`, `wakeup`, `timeout`, `untimeout`), privilege and device
  numbers (`suser`, `drv_priv`, `getmajor`, `getminor`, `makedevice`),
  autoconfig (`autocon`, `bprobe`), the disk layer (`sd_register`,
  `sdqueue`, `iodone`), interrupts (`intr_attach`, `intr_detach`), the
  STREAMS and network attachment helpers (`if_attach`, `if_detach`), the
  console hook (`cons_hook_set`, `cons_hook_clear`), filesystems
  (`vfs_register`), `spl0`…`spl7`/`splx` as functions, the libgcc helpers
  the compiler calls (`__udivdi3`, `__umoddi3`, `__lshrdi3`), and read-only
  `bootinfo` and `cputype`. On k46 also `dev_kvmap`/`dev_kvunmap` and
  `dma_prepare`/`dma_complete`.
- **Core tier** — what the root filesystem modules (ufs, s5, cdfs) need from
  the base: 112 undefined symbols in the stock ufs object and 108 in s5,
  among them `bdevsw` and `vfssw` (checked with `nm -u` on
  `amix-kerntools/work/cross-kernel-k030u-c6s1/usr/sys/fs/{ufs,s5}/exp`);
  cdfs imports `vfssw`, `nfstype`, `sdopen` and `sdqueue` (`L2`:462). The
  core tier therefore exports `bdevsw`, `vfssw` and `nfstype`. The exported
  `vfssw` entry names the **grown** table the core installs
  (`30-module-core.md` §6), not the stock one, and `nfstype` is read live, so
  the stock filesystem objects work unchanged against the grown table.
  Core-tier modules are built with the kernel and also carry the kernel
  build id; outside modules may not use the core tier.

Never exported in the DDI tier: the raw switch tables and interrupt vectors
(`int2_tbl`, `vfssw`, `cdevsw`, `bdevsw`), `conputc`, `ifstats`. Outside
modules reach them only through the registration calls; only the core tier
sees `bdevsw`, `vfssw` and `nfstype`, for the stock filesystem objects.

Several DDI providers are not in today's kernels (`dev_kvmap` exists only
where the A4091 pass linked it, `sdcardbase` only after the RTH1/A4091
passes, the libgcc helpers nowhere, every spl but one is inline), so the core
pass links its own providers and a post-link gate checks that every
allowlisted name is defined in every kernel built (`STUDY` §2.3, C2-F6).

### 4.2 DDI v1 semantics

Each DDI function has a written contract in the ABI kit: context (may it
sleep, which spl), memory class of what it returns (cache-inhibited DMA
memory vs ordinary kmem; `30-module-core.md` §8), and error returns. Root-
class module `_load` routines run before process 1 exists and may not sleep,
touch a disk or wait for a timeout; they may arm one (`STUDY` §2.2, C2-F9).

## 5. What the ABI kit publishes

The ABI kit is a directory of this repository (`abi/`) and a package per
kernel line:

| Content | Notes |
|---|---|
| Our headers: `mod.h`, `moddefs.h`, `ksym.h` (MIT, from the adopted core, with our changes), `ddi.h` (DDI v1 declarations and contracts) | Ours; MIT. |
| The stock Amix kernel headers a module build needs | Commodore's; published in the kit under the project's distribution permission of 2026-09-23 (D-3 §7: "the ABI kit (headers + module tooling) is published in amix-dlm"). Added to the kit at kit build time from the pinned sysroot; not tracked in this repository's history. |
| The allowlist per line and tier, and the kabi sidecar | Generated from each kernel build. |
| The registries of §6 | One text file each. |
| Module tooling: `mkmod`, `modfix`, a `.moddata` v2 writer, a module checker (format, relocation types, undefined symbols against the allowlist, 68060 instruction scan) | Host tools; MIT. |
| A make fragment that builds a module with the pinned compiler against the kit's headers | No separate Amix installation is needed to build a module. |
| A probe module and a sample driver module | For the fingerprint and as a template. |
| The DDI contracts and a "writing a module" guide | `docs/abi/`. |

The stock headers are part of the published kit, as D-3 §7 decided
(this settles P-28 D30 and P-22 D1 for the kit). The repository itself keeps
no Commodore text: the kit build copies the headers from the pinned sysroot
into the kit artefact, so the published kit is complete while the history of
this repository stays free of them. (`gcc-cross-amix` keeps its own,
stricter redistribution notice for its repository.)

## 6. Registries

Fixed in S0; each is a text file in the kit. Values marked *proposed* are
checked against the built kernels before they are frozen (M-REG1).

| Registry | Entries |
|---|---|
| System calls | 64 `modload`, 65 `moduload`, 66 `modpath`, 67 `modstat`, 68 `modadm`, 69 `getksym` (the core's numbers; `sysentsize` 142 and slots 64–77 hold `nosys` in the 030 and 060 images examined, `tmp/2026-10-22-modules-proposal/refute-ashnazag-dlm-init-claim.md`) |
| Character majors | 49 z3660rtg (the ZZ9000-compatible device; the adopted core's own zz9000 module also uses 49), 50 SAD (stock), 51 z3660eth, 52 monitor switch, 53 `kinfo` (free in every kernel of record, M-REG1); stock rows free in the images examined: 7, 38, 39, 42–45, 47–48, 54–69 (`L2`:283) |
| Block majors | 18 `dd` (stock); 20 `ram` — the stock kmem-backed RAM disk (stock `tmp/2026-08-26-svr4-refs/amix-src/master.d/kernel.c:307`, driver `amiga/driver/ram.c` there), replaced in 1.1 by our `ramdisk` module on the same major (`30-module-core.md` §7); free: 0–15, 21–31 (`L2` §2.3) |
| Filesystem names | `ufs`, `s5`, `cdfs` (root class); stock rows otherwise unchanged; table grown by the core (`30-module-core.md` §6) |
| Interrupt chains | INT2 (Zorro/CIA-A level 2), INT6 (Zorro/CIA-B level 6); attachment only through `intr_attach` |
| Motherboard probes (`mobo:`) | `z3660-window` (above), `gayle` (VPOSR AGA gate + task-file write/readback at 0xDD2020, `amix-gayle-ide/README.md:44`), `a4000t-710` (gated by chipset identity; probe to be designed, `amix-kerntools/docs/k0-families.md:1190-1195`), `a3000-wd` (floor driver; VPOSR gate + two-register readback) |
| Zorro keys of record | **144b:01** (`Z3660_PROD 0x144B0001`, `amix-z3660net/src/z3660eth.h:15`; `amix-z3660rtg/DESIGN.md:158`) is shared by three modules: z3660scsi, z3660eth and z3660rtg on a Z3660. That ConfigDev is not the FPGA's: the Z3660 extended ROM builds it at the fixed window 0x10000000 (`Z3660/docs/real-cpu-autoconfig-and-ext-rom.md:14-30`), so the key matches only where that ROM runs. For setups without it the registry adds the gated probe `mobo:z3660-window` (the fixed base `Z3660_FIXED 0x10000000`, `z3660eth.h:16`), never read when the combo board has autoconfigured (`amix-z3660rtg/NOTES.md:157`). A4091 0202:54, A4092 c0de:01, A4770 c0de:02 (`amix-a4091/README.md:58`; the last two untested on hardware). 6d6e:03 is the upstream ZZ9000's own identity (`amix-z3660rtg/README.md:98-101`) and matches only a real ZZ9000 |
| sd rank keys | `30-module-core.md` §5 |

## 7. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-20.4 | Exact DDI v1 list and contracts; Antti reviews before the kit is frozen (D-3 §8). | us; Antti reviews |
| OQ-20.5 | Whether ashnazag's author wants the shared major/syscall registry to be common to both projects (his zz9000 and our z3660rtg both use 49). | ashnazag |

Closed by measurement (2026-10-26): OQ-20.2 — one k46 family: the 68040 and 68060 kernels of record differ in one byte, the CPU stamp, and export the same symbols with the same sizes (M-ABI1, `docs/measurements/2026-10-26-m-reg1-m-abi1.md`); the fingerprint (C3-3) guards it if the two ever diverge.

Closed in the review pass (T-52): OQ-20.1 — the stock headers are published in the kit (D-3 §7, §5 above); OQ-20.3 — z3660eth matches 144b:01 like its two siblings (§6).

## 8. Measurements

M-ABI1 (k46 040/060 export diff), M-ABI2 (brel with ~1000 `.long`
relocations), M-REG1 (registry values against built kernels), M-MOD1 (module
object sizes) — `90-measurements.md`.
