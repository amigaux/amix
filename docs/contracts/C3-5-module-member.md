# C3-5 — the module package and the per-module manifest record, draft

- **Status:** draft for agreement, 2026-10-26. Nothing builds against it
  until the orchestrator agrees it.
- **Implements:** `docs/spec/40-generations-and-composer.md` §2.2, §3.1;
  `10-boot-loader.md` §5.1; `30-module-core.md` §2 patches 16 and 17, §3
- **Produced by:**
  - the module packages (amix-packages, S3-22) from the driver
    repositories' modules (C3-1);
  - `kbootset build` (S3-16), which composes the generation.
- **Read by:**
  - apkg (S3-30): the catalog entry, C2-2 as it stands;
  - `kbootset`: the package files;
  - the module core (`marc_post`, the first-open registration, manifest-only
    loading): the manifest record;
  - boot2: root-class records only (stage 4).

## 1. The module package (role `module`)

| Path | Content |
|---|---|
| `/etc/conf/mod.d/<name>` | the module object (C3-1), the file name its `.moddata` `name=` |
| `/etc/conf/modreg.d/<name>` | the package's registration defaults: one `key value` per line, `#` comments; keys `param <pname>=<value>` (a default other than the module's own) and `disable` (shipped but off) |

`/etc/conf/modreg.local.d/<name>` is the administrator's: the same keys,
owned by no package, read after `modreg.d`; a later line wins.

The catalog entry and the install record are C2-2's (`role=module`,
`line=`, `kabi=`, `pin=`, `size=`, `sha256=`, `file=`). C2-2 needs no
change.

## 2. What `kbootset build` composes

For the kernel's line, every installed module package goes into the
generation unless a `modreg` file says `disable`.
- **Gate 1:** each object's SHA-256 equals the one in its install record.
- **Gate 2:** each object's kabi family and major equal the kernel's, its
  minor is not above the kernel's, and its `cc=` equals the kernel's pin
  (C3-1 §3).
- **Gate 3, extended:** every `depend=` names a module in the
  generation, and the root-class set covers the boot and root controllers
  and the root filesystem (stage 4).
- Each object is copied to `/stand/gen/<id>/mod/<name>`, byte for byte.
- **Parameters:** each one the module declares (`param` keys, C3-1) takes
  its default, then `modreg.d`'s value, then `modreg.local.d`'s.
  `kbootset` checks every value against the declared type and range, and
  refuses a value outside them, or a parameter the module does not
  declare (gate 2).

## 3. The manifest records

One record per module, after the kernel's, in this order: root class,
then boot class in `depend` order, then demand class.

```
module <name> boot <size> path=/stand/gen/<id>/mod/<name> sha256=<64 hex> [match=<keys>] [depend=<names>]
module <name> demand <size> path=/stand/gen/<id>/mod/<name> sha256=<64 hex> majors=<c:N,…> [depend=<names>]
module <name> root <size> at=<off> [stored=<n> z=deflate] crc32=<8 hex> sha256=<64 hex> match=<keys>    (stage 4)
param <name>.<pname>=<value>
```

| Field | From | Read by |
|---|---|---|
| `<size>` | the object's size | `kbootset check` |
| `path=` | the generation directory | the core (patch 17) |
| `sha256=` | the object's SHA-256 | the core (patch 17), `kbootset check` |
| `match=` | the `.moddata` `match=`, copied | the core, `marc_post`: a boot-class record with `match=` loads only when one key matches the booted board set; without it, it always loads (C3-1 §3, class rules) |
| `majors=` | the `.moddata` `majors=`, copied; required on a demand-class record | the core, `marc_post`: it registers each character major for the module, so the first open of it loads the module |
| `depend=` | the `.moddata` `depend=`, copied | the core (the order `marc_post` loads in), `kbootset` (gate 3) |
| `param` | §2 | the core: the module's parameters, passed to its `_load` as one string `"<pname>=<value> …"` |

boot2 does not read boot- or demand-class records (10 §5.1). The manifest
stays under the loader's 2 048-byte extent for a stage-3 generation; a
larger one takes more extents, as the store allows.

## 4. Settled at agreement (to confirm)

- The package files, and the `disable` and `param` keys of `modreg.d` and
  `modreg.local.d`.
- The record fields above, `match=`, `majors=` and `depend=` copied from
  `.moddata`, and the record order.
- Parameters reach `_load` as its first argument, a string valid only
  during the call (C3-6 tells the driver authors).
