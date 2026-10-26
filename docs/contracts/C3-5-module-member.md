# C3-5 — the module package and the per-module manifest record, version 8

- **Status:** agreed 2026-10-26 (orchestrator), version 1; version 2
  (2026-10-26): what `kbootset` accepts and writes for a parameter value
  (§2); version 3 (2026-10-26): `marc_post` runs from the first sysinit
  entry, `modadmin -B` (§5, U15); version 4 (2026-10-26, from S3-31's
  dry run): the package's names and version (§1.1), and its scripts run
  on the installer's miniroot, so pure `sh` (§1.3); the package's contents (§1.2); version 5
  (2026-10-26, from S3-31's media of record): init's process ids are not
  stable, so no rc script trusts a pid from an earlier boot (§1.3); version 6
  (2026-10-26, C4-4 version 2): a root record carries `bss=`, the size of
  the module's NOBITS and COMMON, which boot2 reserves behind its file (§3); version 7
  (2026-10-26, C4-4 version 3): `safe=1` marks the root records of the safe-mode
  set (§3); version 8 (2026-10-26, amix-modules' ramdisk): its short name
  (§1.1), and a block driver's nodes in `/dev/dsk` (§1.2). Every consumer
  is in amix-dlm: `kbootset` writes the records, boot2 and the module core
  read them. A change from here is a contract change with a version bump.
- **Implements:** `docs/spec/40-generations-and-composer.md` §2.2, §3.1;
  `10-boot-loader.md` §5.1; `30-module-core.md` §2 patches 16 and 17, §3
- **Produced by:** the module packages (amix-packages, S3-22) from the
  driver repositories' modules (C3-1); `kbootset build` (S3-16)
- **Read by:**
  - apkg (S3-30): the catalog entry, C2-2 as it stands;
  - `kbootset`: the package files, and the manifest for `check` and `status`;
  - the module core: the records (manifest-only loading, core patch 0009;
    `marc_post`, core patch 0010);
  - boot2: root-class records only (stage 4).

## 1. The module package (role `module`)

| Path | Content |
|---|---|
| `/etc/conf/mod.d/<name>` | the module object (C3-1); the file name is its `.moddata` `name=` |
| `/etc/conf/modreg.d/<name>` | the package's defaults, one `key value` per line, `#` comments: `param <pname>=<value>` (a default other than the module's own), `disable` (shipped but off) |

`/etc/conf/modreg.local.d/<name>` belongs to the administrator: the same
keys, owned by no package, read after `modreg.d`, and a later line wins.

The catalog entry and the install record are C2-2's (`role=module` with
`line=`, `kabi=`, `pin=`, `size=`, `sha256=`, `file=`). C2-2 needs no
change.

### 1.1 Names and version

A module object is built for one line (its kabi family), so **one package
per line**:

| | Form | z3660eth on k46 |
|---|---|---|
| catalog name | `<name>-<line>` | `z3660eth-k46` |
| pkginst (C2-2 `pkginst=`, at most 9 bytes) | `<short><line digits>`, the short name at most 7 bytes | `zeth46` |
| version | the module's own release, `<major>.<minor>.<patch>[-<rev>]`, the same on both lines | `1.0.0-1` |

- The kabi is not in the version: it is the catalog's `kabi=` (C2-2),
  which apkg's pre-flight checks against the installed kernel.
- **Where the version lives:** the module's repository records it in
  `module/VERSION`, one line `x.y.z-rev`, the same for both lines.
  amix-packages reads it when it makes `<name>-<line>`. It is not a
  `.moddata` key: that would change the module's bytes and need a C3-1
  version. z3660eth is 1.0.0-1, z3660rtg 1.1.0-1.
- The short names, assigned here, one per module, unique:

| Module | Short name | pkginst k30 / k46 |
|---|---|---|
| z3660eth | `zeth` | `zeth30` / `zeth46` |
| z3660rtg | `zrtg` | `zrtg30` / `zrtg46` |
| monsw | `monsw` | `monsw30` / `monsw46` |
| ramdisk | `ramdisk` | `ramdisk30` / `ramdisk46` |

  A new module's owner adds its row in a version bump of this contract.

### 1.2 The package's contents (the stage-3 mint's conventions)

- `CATEGORY` is `system`.
- Files: `/etc/conf/mod.d/<name>`, and `/etc/conf/modreg.d/<name>`. When
  the package sets no parameter other than the module's own defaults, the
  modreg file is comments only, pointing at the format and at
  `modreg.local.d` for the administrator's overrides.
- Directories: `/etc/conf`, `/etc/conf/mod.d` and `/etc/conf/modreg.d`
  0755 root sys; `/etc` 0755 root root, as the core packages have it.
- `/etc/conf/modreg.local.d` is the administrator's and is never shipped
  (§1).
- **Device nodes:** the package ships the nodes of the majors its driver
  owns as pkgmap device entries, no script: z3660eth `/dev/zen0` c 51 0.
  A block driver's nodes (`b`) are in `/dev/dsk`, and its character
  (raw) nodes in `/dev/rdsk` only when the driver has a character row:
  the ramdisk, block only, ships `/dev/dsk/ram0`–`ram2`, b 20 0–2, 0600
  root root, and no `/dev/rdsk` node. Network plumbing (`slink`, `ifconfig`) is not the package's: the
  installer's `S99zen` does it (S3-31).
- The catalog row (C2-2 §1.1) takes `kabi=` and `pin=` from the object's
  `.moddata`. **apkg does not check dependencies** between module
  packages at install: a module whose `depend=` names a module that is not
  installed (or is disabled) is refused by `kbootset build`, gate 3 (§2).

### 1.3 Package scripts

A module package's scripts (and `modtools`') run where `pkgadd` runs: on a
box, and on the installer's miniroot, which has no `awk`, `cmp`, `grep` or
`sed`, under a fixed `PATH`. The rule, which amix-packages' build gate
enforces:
- **Commands:** the sh builtins, plus `mv`, `cat`, `ls`, `dd` and `expr`
  (all in the miniroot's `/bin`). Each external runs only after `test -x`
  finds it, and a script that lacks a command it needs refuses, never
  carries on without it.
- **`read`:** never in the script's own shell. Each `read` runs in a child,
  a backquote or a redirected `while read … done < file`, with one
  redirection of its own. The 1991 sh's `read` keeps buffered input across
  redirections, so a second `exec <file` continues where the first read
  stopped. modtools -3's postinstall re-read `/etc/inittab` that way and
  left only the `dlm` line.
- **Forbidden:** `exec` redirection, `IFS`, `set -f`, `$(…)`, `${…#…}`
  and the other pattern expansions, `printf`, and flags to `read` or
  `echo`.
- **Files:** `cat` or `dd` copy the bytes, and a size check comes before
  every `mv` that replaces a file. A `while read l; … done < file` loop is
  never a byte-exact copy: on the default IFS the 1991 sh strips a line's
  trailing blanks.
- **What the 2.1 sh does** (installng's probe on the miniroot's `/bin/sh`):
  `exec <f` at top level, `read l <f`, a redirected while-read and
  `exec 4>f` behave; `for …; do exec <f; read l; done` continues at line 2
  on the second pass; `IFS` and `set -f` make no difference to that.

- **Process ids are not stable across boots** (version 5). What a
  package or the installer adds to init (an `inittab` sysinit line such as
  `modadmin -B`, an early `rc2.d` script such as `S01kbnamelist`) shifts
  every later process's id. So an rc script never trusts a pid an earlier
  boot saved without checking the process's name (`ps -p <pid>`, and that
  the command is the expected one). The stock `/etc/init.d/syslogd` does
  trust `/etc/syslog.pid` (`kill -0` alone). On the media of record that
  pid margin was zero (stale 87, and this boot's syslogd got 87), so
  syslogd never started. amix-installng's unit checks with `ps -p`. Kernel
  messages after boot then reach no log (`conslogging 0`).

Scripts are proven on the 2.1 sh (the installer miniroot), not only on a
host shell. modtools' postinstall, which puts the `modadmin -B` line first
among the sysinit entries (§5), follows the rule from modtools -4.

## 2. What `kbootset build` composes, and what it refuses

Every installed module package of the kernel's line goes into the
generation, unless a `modreg` file says `disable`. Each object is copied
byte for byte to `/stand/gen/<id>/mod/<name>`. `build` refuses, naming
the gate, when:

| Gate | Refusal |
|---|---|
| 1 | an object's SHA-256 differs from its install record |
| 2 | a kabi family or major other than the kernel's, a minor above it, a `cc=` other than the kernel's pin, a `tier=core` module whose `build=` is not the kernel's (C3-1 §3) |
| 2 | a parameter value outside its declared type or range, or a parameter the module does not declare |
| 3 | a `depend=` naming a module not in the generation; a **boot-class module without `match=`** (one that needs no board says `match=always`); a **demand-class module without `majors=`, or whose majors are not registered to it** (the registry, `abi/registry/majors`, as core patch 0006 checks at load) |
| 3 | stage 4: a root-class set that does not cover the boot and root controllers and the root filesystem |
| 4 | stage 4: the root-class set over the arena's capacity |
| — | over the loader parser's limits: more than 32 module records, more than 32 `param` records, or a record longer than 255 bytes (`loader/common/manifest.h`) |

**Parameters:** each parameter the module declares (`param`, C3-1) takes
its default, then `modreg.d`'s value, then `modreg.local.d`'s.
`kbootset` writes the value in C3-1 §3's form only. On input
(`modreg.d`, `modreg.local.d`) it accepts for a `bool` `0`/`1`,
`yes`/`no`, `true`/`false` and `on`/`off` (lowercase), and writes `1` or
`0`; for an `int` or `hex`, the number in either form, written in the
declared one. Anything else is refused at gate 2, naming the module, the
parameter and the value.

## 3. The manifest records

After the kernel's record, one record per module: root class first, then
boot class in `depend` order, then demand class; then the `param`
records.

```
module <name> boot <size> path=/stand/gen/<id>/mod/<name> sha256=<64 hex> match=<keys> [depend=<names>] [tier=core build=<id>]
module <name> demand <size> path=/stand/gen/<id>/mod/<name> sha256=<64 hex> majors=<c:N,...> [depend=<names>] [tier=core build=<id>]
module <name> root <size> at=<off> [stored=<n> z=deflate] bss=<n> crc32=<8 hex> sha256=<64 hex> match=<keys> [safe=1] ...   (stage 4)
param <name>.<pname>=<value>
```

| Key | Written from | Read by |
|---|---|---|
| `<size>` | the object's size | `kbootset check` |
| `bss=` | root class: the bytes the module's NOBITS sections and COMMON symbols need, laid out from 0 by the core's rules (C4-4 §4: each section aligned to max(its alignment, 4), then each common to its own; any alignment above 16 refused), rounded up to 4; written even when 0. Every COMMON is counted, so it is an upper bound when the core resolves one against the kernel or a dependency instead (`kbootset/kmod.c` `km_tail`) | boot2: the zeroed tail it reserves behind the file and counts against the capacity (C4-4 §1.2); the core: the tail it lays them into, refusing a layout larger than this |
| `path=` | the generation directory | the core: where the bytes come from (patch 0009) |
| `sha256=` | the object | the core: what they must hash to (patch 0009); `kbootset check` |
| `match=` | **copied verbatim** from `.moddata`; required on boot and root class | `marc_post`: a boot-class record loads only if a key names a board in this box (the platform's matcher; `always` always matches); `marc_root` the same for a root-class record (C4-4 version 3 §4). boot2 does not read it |
| `safe=1` | root class (version 7): on the records of the safe-mode set, written by `kbootset`: the root controller's module (from `kinfo`'s card table, C2-1), the root filesystem's module (the manifest's `rootfs`), and the root-class modules those two depend on; absent on every other record | boot2: in safe mode it places only these, and it sets flag 0x4 on their directory entries in every boot (C4-4 version 3 §2) |
| `majors=` | **copied verbatim**; required on demand class | `marc_post`: registers each character major for the module (block majors: stage 4) |
| `depend=` | **copied verbatim** | `kbootset` gate 3, and the record order |
| `tier=`, `build=` | **copied verbatim** when `tier=core` | `kbootset status`; the core decides from the object's own `.moddata` (patch 0003) |
| `param` | §2 | the core: passed to the module's `_load` as its first argument, one string `"<pname>=<value> ..."`, valid during the call |

`.moddata`'s `class`, `cpu`, `kabi`, `cc` and `name` are not copied. The
record's class word and the gates already carry them, and the core reads
the object.

## 4. The manifest format does not change

Every key above is an attribute of a `module` record or a `param`
record. The format stays GMF1, and no `loader-min` follows:
- **boot2 and kbootset's parser** (`loader/common/manifest.c`) keep the
  attributes they know (`at`, `stored`, `bss`, `z`, `crc32`, `sha256`,
  `match`, `path`, `file`) and skip any other on a member record. They
  read `param` records. They ignore an unknown record unless its key
  starts with `!`, which they refuse (10 §5.1). A loader of version 1
  therefore reads a stage-3 manifest correctly.
- **The core** reads only the records and keys it needs (`module` with
  `path=`, `sha256=`, `match=`, `majors=`; `param`) and skips the rest.

A later change that an older reader would misread must use a `!` key or
a new record, with `loader-min` raised. This contract adds none.

## 5. Order, safe mode, and what is reported

- **When:** `marc_post` runs from the first `sysinit` entry of
  `/etc/inittab`, before every other one:
  `dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1`
  (`modadmin -B`, the modadm command `MOD_C_POST`, root only, once a boot:
  a second is `EBUSY`). The module packages' installer (S3-31) and the
  `modtools` package put that line there. The kernel's own hook after
  `vfs_mountroot` loads nothing: it runs with interrupts masked, where
  reading a module file faults (U15, core patch 0017), and prints
  `dlm: boot-class modules load from the first sysinit entry (modadmin -B)`.
- **Order:** `marc_post` first registers the demand-class majors, then
  loads the boot-class records in manifest order. A module's
  dependencies load before it in any case.
- **Console:** one line per record:
  - `dlm: boot module <name> loaded`;
  - `dlm: boot module <name> not loaded: no board matches <keys>`;
  - `dlm: boot module <name> not loaded: error <n>`;
  - `dlm: demand module <name>: major <n> not registered (error <n>)`.
  In safe mode it prints one line,
  `dlm: safe mode: no boot- or demand-class module loads this boot`, and
  loads nothing; every other load, a first open or a `modload`, is
  refused too (patch 0010).
- **kinfo** (C2-1, no change):
  - the module list at offset 576 (C2-1 version 3; 536 in version 2) holds the modules actually loaded
    (name, address, size), filled from the core's list;
  - flag 0x4 is safe mode.
  So `kbootset status` lists the manifest's boot-class members, each
  marked loaded or not loaded from kinfo's list. The reason for a member
  that did not load is on the console. `mark-good` does not depend on
  it, because whether a generation is good is a full run level 2, not a
  module count.

## 6. Settled at agreement

- The package files, and the `disable` and `param` keys.
- The record keys and the four copied verbatim (`match=`, `majors=`,
  `depend=`, `tier=`/`build=`); the refusals of §2.
- No change to GMF1 or `loader-min` (§4).
- The order, the console lines and kinfo's role (§5).
