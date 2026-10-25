# C2-2 — kernel-space catalog entries and apkg's install record, version 1

- **Status:** agreed 2026-10-25 (orchestrator), version 1. Other repositories build against this text; a change from here is a contract change with a version bump.
- **Implements:** `docs/spec/60-signing-and-publishing.md` §3–§4 (as changed by D-3 §13: SHA-256, no signature, the hook), `40-generations-and-composer.md` §3.1 gate 1 and §6
- **Written by:** amix-packagemanager (`gen-catalog.py` writes the block; apkg 0.3 writes the records)
- **Read by:** apkg 0.3, `kbootset` gate 1, the installer

## 1. The catalog block

It follows the catalog's ordinary entries. Every line starts with `#` in
column 0 and is under 2048 bytes, so a deployed apkg skips the block
whole.

```
#ext kpkg 1
#kpkg <name> <version> role=<kernel|loader|module> line=<k30|k46> kabi=<tag> pin=<compiler pin> size=<bytes> sha256=<64 hex> file=<datastream>
#ksig <key-id> <file>
#end kpkg
```

- After the name and the version, the attributes are `key=value` in any
  order.
- An unknown key is ignored; an unknown key starting with `!` refuses the
  entry.
- `sha256=` and `size=` are of the package datastream as served (`file=`).
- `#ksig` is optional and absent in 1.1. A 1.1 client records it and does
  not act on it (60 §4).

## 2. The install record `/var/apkg/kpkg/<name>`

apkg 0.3 writes it once the package is installed. It is one `key value`
per line:

```
name <name>
version <version>
role <kernel|loader|module>
line <k30|k46>
kabi <tag>
pin <compiler pin>
sha256 <64 hex>                 the datastream, as verified after download
source <catalog URL or medium id>
installed <seconds since 1970>
verified no                     the signature hook: always "no" in 1.1
file <path> <size> <64 hex>     one line per installed file: SHA-256 of the file
```

`kbootset` gate 1 compares each generation member, which is a file such as
`/stand/k46/unix`, against the `file` line that names it. The gate refuses:
- a member that no record names (placed by hand or by a bare `pkgadd`);
- a member whose SHA-256 differs from its record.

A later policy `require-signature` would refuse `verified no` (60 §4).

## 3. Settled at agreement

- The field names are as above.
- A `file` line carries the SHA-256 of the installed file, computed by
  apkg at install.
- For a medium, `source` is the mount path or the raw device as apkg saw
  it.
- `/var/apkg/kpkg/` is apkg's alone; `kbootset` only reads it.
