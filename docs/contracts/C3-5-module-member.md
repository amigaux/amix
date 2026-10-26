# C3-5 — the module package and the per-module manifest record, draft

- **Status:** draft 2026-10-26, for agreement with the S3-08 report. Every
  consumer is in amix-dlm: `kbootset` writes the records, boot2 and the
  module core read them. Once it is agreed, a change is a contract change
  with a version bump.
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

## 3. The manifest records

After the kernel's record, one record per module: root class first, then
boot class in `depend` order, then demand class; then the `param`
records.

```
module <name> boot <size> path=/stand/gen/<id>/mod/<name> sha256=<64 hex> match=<keys> [depend=<names>] [tier=core build=<id>]
module <name> demand <size> path=/stand/gen/<id>/mod/<name> sha256=<64 hex> majors=<c:N,...> [depend=<names>] [tier=core build=<id>]
module <name> root <size> at=<off> [stored=<n> z=deflate] crc32=<8 hex> sha256=<64 hex> match=<keys> ...   (stage 4)
param <name>.<pname>=<value>
```

| Key | Written from | Read by |
|---|---|---|
| `<size>` | the object's size | `kbootset check` |
| `path=` | the generation directory | the core: where the bytes come from (patch 0009) |
| `sha256=` | the object | the core: what they must hash to (patch 0009); `kbootset check` |
| `match=` | **copied verbatim** from `.moddata`; required on boot and root class | `marc_post`: a boot-class record loads only if a key names a board in this box (the platform's matcher; `always` always matches); boot2 selects root-class records by it (10 §5.3) |
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
  - the module list at offset 536 holds the modules actually loaded
    (name, address, size), filled from the core's list;
  - flag 0x4 is safe mode.
  So `kbootset status` lists the manifest's boot-class members, each
  marked loaded or not loaded from kinfo's list. The reason for a member
  that did not load is on the console. `mark-good` does not depend on
  it, because whether a generation is good is a full run level 2, not a
  module count.

## 6. Settled at agreement (to confirm)

- The package files, and the `disable` and `param` keys.
- The record keys and the four copied verbatim (`match=`, `majors=`,
  `depend=`, `tier=`/`build=`); the refusals of §2.
- No change to GMF1 or `loader-min` (§4).
- The order, the console lines and kinfo's role (§5).
