# C3-1 — the module object and `.moddata` version 2, version 3

- **Status:** agreed 2026-10-26 (orchestrator), version 1; version 2
  (2026-10-26): the text form of parameter values (§3); version 3
  (2026-10-26): the §4 table is the load call's, a refused first open is
  `ENXIO` (§4). Other repositories build against this text; a change from here is a contract change with a version bump.
- **Implements:** `docs/spec/20-module-format-and-abi.md` §1.1, §2, §3;
  `30-module-core.md` §2 patches 4 and 14
- **Produced by:** the ABI kit's `mkmod` and `modfix` (S3-10), used by the
  driver repositories (amix-z3660net, amix-z3660rtg; amix-gayle-ide from
  stage 4)
- **Read by:**
  - the module core (S3-03), at every load;
  - `kbootset build` (S3-16), when it composes a generation;
  - apkg's pre-flight (S3-30);
  - the kit's checker.

The base is the object format of kdedon's MIT DLM core (upstream
`b736c59`, `kernel/dlm/tools/modfix.c` and `mkmod` there). What changes is
the wrapper revision and the `.moddata` contents.

## 1. The object

A module is one file, `/etc/conf/mod.d/<name>` in its package and
`/stand/gen/<id>/mod/<name>` in a generation. The file name is the module's
`name` (§3).

| Rule | Content |
|---|---|
| ELF header | ELF32, big-endian, `ET_REL`, `EM_68K`, version 1 |
| Sections | allocated sections of type PROGBITS, NOBITS or 13 only; the allocated image ≤ 2 MiB |
| `.moddata` | exactly one section of type 13, allocated, at least 12 bytes (§3). `modfix` sets the type, which binutils 2.8.1 cannot emit |
| Relocations | `SHT_RELA` only; a `SHT_REL` section is refused. Types `R_68K_NONE`, `32`, `16`, `8`, `PC32`, `PC16`, `PC8`; every result range-checked |
| Symbols | exactly one `.symtab` with its string table. Each undefined global resolves to a name in the kernel's allowlist for the module's tier (C3-2), or to a global of a module named in `depend`. A weak undefined symbol that resolves nowhere is 0. COMMON symbols are allocated by the core |
| The wrapper | `<prefix>_wrapper` defined once, globally; word 0 of `.moddata` holds an `R_68K_32` relocation against it with addend 0 |
| Code | built by the line's pinned gcc-cross-amix with `AMIX_KERNEL_CFLAGS` and the 060-safe rewrite (20 §3.2). The checker scans for instructions the 68060 does not have |

## 2. The wrapper

`struct modwrapper` as upstream's `sys/moddefs.h`, with `mw_rev` = **2**
(`MODREV 2`): revision, `_load`, `_unload`, `_halt`, configuration data,
linkage list.

| Entry | Called | Context | Returns |
|---|---|---|---|
| `_load` | once, after relocation, before the linkages are installed | boot class: process 0 in `marc_post` (30 §3), or the first `sysinit` entry (U15); demand class: the process that opened the device. It may sleep | 0, or an errno; on an errno the core unwinds everything and the kernel is as it was (80 §3) |
| `_unload` | only when the module declares `unload=allowed` and nothing holds it | process context; may sleep | 0, or an errno; the linkages are put back |
| `_halt` | from the halt pass, newest module first (stage 4) | no sleep, interrupts may be off | — |

Linkage types the core accepts in stage 3:
- `mod_miscops`;
- `mod_drvops` (character majors, `drv_bcount` = 0);
- `mod_strops` (an `fmodsw` row);
- the STREAMS-driver path (`d_str` set).

Block devices, filesystems and disk controllers come with stage 4 and 5,
under the same wrapper revision.

## 3. `.moddata` version 2

```
offset 0   4 bytes   R_68K_32 relocation to <prefix>_wrapper (as version 1)
offset 4   4 bytes   "MD2\0"
offset 8   ...       NUL-terminated "key=value" strings, ending with an empty string
```

- Keys are lowercase. A value runs to the NUL and holds no NUL.
- Each string is at most 255 bytes, and the whole section at most 2 048.
- A key may appear once, except `param`, which appears once per
  parameter.
- An unknown key is ignored, unless it starts with `!`. Then the core and
  `kbootset` refuse the module unless they understand it, the same rule as
  the manifest's (10 §5.1).

| Key | Value | Required | Checked by |
|---|---|---|---|
| `name` | 1–14 characters `[a-z0-9_-]`, equal to the file name | always | core, `kbootset`, apkg |
| `kabi` | `<fam>.<major>.<minor>`: `k30` or `k46`, decimal major and minor | always | core, `kbootset`, apkg |
| `cc` | the compiler pin id (20 §3.2), equal to the kernel sidecar's `pin=` | always | `kbootset`, apkg, core |
| `cpu` | lowest CPU: `68020`, `68030`, `68040` or `68060` | always | `kbootset` |
| `class` | `boot` or `demand`; `root` from stage 4 | always | core, `kbootset` |
| `match` | comma-separated keys: `zorro:MMMM:PP` (4 and 2 lowercase hex digits, neither all zero), `mobo:<probe>` from the registry, `always` | root class; optional for boot and demand | core |
| `rank` | the sd rank key (30 §5) | root-class disk controllers | core |
| `majors` | comma-separated `c:<n>` / `b:<n>`, each in the registry (20 §6) | when the module registers a device | core, `kbootset` |
| `fs` | the filesystem name for `vfs_register` | root-class filesystems | core |
| `depend` | comma-separated module names | when it uses another module's symbols | core, `kbootset` |
| `unload` | `never` (the default) or `allowed` | no | core |
| `param` | `<name>:<type>:<default>[:<min>:<max>]`, type `int`, `bool`, `str` or `hex` | per parameter | `kbootset`, core |
| `tier` | `ddi` (the default) or `core` (C3-2 §4) | no | core |
| `build` | the kernel build id a core-tier module was built with (C2-3 `build=`) | when `tier=core` | core, `kbootset` |
| `desc` | one line | no | tools |

**Parameter values** (the same text in `.moddata`'s default, the
manifest's `param` record and the string `_load` receives):

| Type | Text |
|---|---|
| `int` | decimal, an optional `-`; `min` and `max` bound it |
| `hex` | `0x` and hexadecimal digits; `min` and `max` bound it |
| `bool` | exactly `0` or `1` |
| `str` | one word: no space and no NUL (`_load`'s string separates parameters with spaces), at most 63 bytes |

A module's parser may accept more spellings than these (a driver may
read `yes` as 1), but nothing it is given in the manifest or by the core
is ever other than the forms above: `kbootset` normalizes (C3-5 §2).

`tier` and `build` are additions to 20 §2's table. The core tier's modules
carry the kernel build id (20 §4.1), and this is where it goes. 20 §2
follows as a spec change after freeze once this is agreed.

**Class rules.**
- A boot-class module with `match` is loaded by `marc_post` only when one
  of its keys matches the booted board set (the boards in `bootinfo`). One
  without `match` is always loaded. A demand-class module loads at the
  first open of one of its `majors`.
- A module that finds no hardware returns `ENXIO` from `_load` and is not
  kept.

**What the version-1 core makes of a version-2 module.** The version-1
core reads the bytes after word 0 as dependency names. It sees a
dependency named `MD2`, finds no such module and refuses the load. If a
module of that name existed, the wrapper's revision 2 would be refused
with `EBADVER`. Either way a version-1 core never runs a version-2
module.

## 4. Refusals

Every refusal leaves the kernel as it was and prints one console line
naming the module and the rule. The errno values are upstream's (`mod.h`)
where one fits.

The table is the load call's: `modload`, a dependency's load, and
`marc_post`'s boot-class load return these. **A demand-class module
refused at the first open of its device returns `ENXIO` to `open(2)`**,
whatever the refusal, as a device that cannot be opened does. The
console line names the module and the rule.

| Refusal | errno |
|---|---|
| not ELF32 big-endian `ET_REL` `EM_68K`; a section type outside §1; image over 2 MiB; no `.moddata` or more than one | `ENOLOAD` (164) |
| a `SHT_REL` section; a relocation type outside §1; a result out of range | `ERELOC` (165) |
| an undefined symbol outside the allowlist of the module's tier and its dependencies | `ERELOC` (165) |
| wrapper revision other than 2; no `MD2\0`; a `kabi` family or major other than the kernel's; a minor above the kernel's; a `cc` other than the kernel's pin; `tier=core` with a `build` other than the kernel's | `EBADVER` (167) |
| a malformed or missing required key; a zero match key; an unknown `!` key; `name` other than the file name; a major outside the registry or already owned | `ECONFIG` (168) |
| `name` longer than 14 | `ENAMETOOLONG` |
| not a member of the booted manifest, or a SHA-256 other than the manifest's, without development load (C3-4, 30 §2 patch 17) | `EPERM` |

## 5. Settled at agreement

- Wrapper revision 2, the `MD2\0` marker, and the key table above,
  including the two additions `tier` and `build`.
- The 2 048-byte limit on `.moddata` and 255 bytes per string.
- A boot-class module with `match` loads only on a matching board set.
- The errno per refusal.
