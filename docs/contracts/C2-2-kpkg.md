# C2-2 — kernel-space catalog entries and apkg's install record, version 5

- **Status:** agreed 2026-10-25 (orchestrator); version 2 (2026-10-26): the optional `pkginst=` and `offset=` keys (§1); version 3 (2026-10-26): the keys required per role, and the loader's (§1.1); version 4 (2026-10-26): the record is named by the pkginst (§2); version 5 (2026-10-26): one kernel package per line, and how an install replaces the other (§2.1). Other repositories build against this text; a change from here is a contract change with a version bump.
- **Implements:** `docs/spec/60-signing-and-publishing.md` §3–§4 (as changed by D-3 §13: SHA-256, no signature, the hook), `40-generations-and-composer.md` §3.1 gate 1 and §6
- **Written by:** amix-packagemanager (`gen-catalog.py` writes the block; apkg 0.3 writes the records)
- **Read by:** apkg 0.3, `kbootset` gate 1, the installer

## 1. The catalog block

It follows the catalog's ordinary entries. Every line starts with `#` in
column 0 and is under 2048 bytes, so a deployed apkg skips the block
whole.

```
#ext kpkg 1
#kpkg <name> <version> role=<kernel|module> line=<k30|k46> kabi=<tag> pin=<compiler pin> size=<bytes> sha256=<64 hex> file=<datastream>
#kpkg <name> <version> role=loader line=any loader=<n> size=<bytes> sha256=<64 hex> file=<datastream>
#ksig <key-id> <file>
#end kpkg
```

- After the name and the version, the attributes are `key=value` in any
  order.
- An unknown key is ignored; an unknown key starting with `!` refuses the
  entry.
- `sha256=` and `size=` are of the package datastream as served (`file=`).
- Two optional keys (version 2):
  - `pkginst=<name>`: the datastream's package instance name, when it
    differs from `<name>`. Names like `kernel-k46` exceed the 9-character
    pkginst limit.
  - `offset=<bytes>`: where the datastream starts on a raw medium (a tape
    or a raw source disk).
- `#ksig` is optional and absent in 1.1. A 1.1 client records it and does
  not act on it (60 §4).

### 1.1 The keys each role requires (version 3)

| Role | Required | Absent |
|---|---|---|
| `kernel` | `line=k30\|k46`, `kabi=`, `pin=`, `size=`, `sha256=`, `file=` | — |
| `module` | `line=k30\|k46`, `kabi=`, `pin=`, `size=`, `sha256=`, `file=` | — |
| `loader` | `line=any`, `loader=<n>`, `size=`, `sha256=`, `file=` | `kabi=`, `pin=` |

- An entry that lacks a key its role requires is refused, as is an entry
  that carries a key its role excludes.
- `loader=` is the loader version (C2-3 §3, `ldrinfo` `version=`). It is
  what a kernel's `loader-min` is compared with (gate 7).
- The loader carries no `kabi=` or `pin=`: boot1 and boot2 serve both
  lines and no kernel interface binds them.
- The kbootset package is userland (C2-3 §4). It goes in the catalog's
  ordinary entries, not in this block.
- Module packages are published from stage 3 on; until then
  `gen-catalog.py` may skip them.
- **Where the values come from** (the stage-3 mint's conventions, version
  5):
  - a `kernel` row's `line=`, `kabi=` and `pin=` come from the kernel's
    sidecar (C2-3 §2). The row carries only what apkg's pre-flight needs.
    Everything else kbootset reads from the installed sidecar itself:
    `abi=`, `loader-min=`, `bss=`, `sym=`, `ident=`, `arena=`;
  - a `module` row's `kabi=` and `pin=` come from the object's
    `.moddata` `kabi=` and `cc=` (C3-1), and `line=` from the kabi family.
    A row has no `depend=` key: apkg does not check module dependencies at
    install, kbootset's gate 3 does at build (C3-5 §2);
  - `file=` is a path under the repository's `base/`, as for the
    ordinary entries.

## 2. The install record `/var/apkg/kpkg/<pkginst>`

apkg 0.3 writes it once the package is installed.
- The file is named by the package's pkginst: its `pkginst=` (C2-2 §1),
  else its name. A pkginst is at most 9 characters, so the record and
  apkg's `<pkginst>.new` stay distinct on an s5 root, which keeps 14
  characters of a name. `kernel-k46-zacd` and `kernel-k46-zacd.new` would
  not.
- The `name` line inside carries the full name.
- kbootset reads every file in the directory except `*.new` and goes by
  the `file` lines, so the file name does not matter to it.

The record is one `key value` per line:

```
name <name>
version <version>
role <kernel|loader|module>
line <k30|k46|any>
kabi <tag>                      kernel and module only
pin <compiler pin>              kernel and module only
loader <n>                      loader only
sha256 <64 hex>                 the datastream, as verified after download
source <catalog URL or medium id>
installed <seconds since 1970>
verified no                     the signature hook: always "no" in 1.1
file <path> <size> <64 hex>     one line per installed file: SHA-256 of the file
```

A module package's device node (C3-5 §1.2) gets no `file` line: `pkgadd`
makes it, and the contents database holds it.

`kbootset` gate 1 compares each generation member, which is a file such as
`/stand/k46/unix`, against the `file` line that names it. The gate refuses:
- a member that no record names (placed by hand or by a bare `pkgadd`);
- a member whose SHA-256 differs from its record.

A later policy `require-signature` would refuse `verified no` (60 §4).

### 2.1 One kernel package per line (version 5)

Every kernel package of a line installs the same paths
(`/stand/<line>/unix`, `kabi`, on k30 `unix.sym`): a static family's and
the module kernel's (C2-3 §1.1) alike. Two kernel records of one line
would name one path twice, which gate 1 refuses. So when a transaction
installs a `role=kernel` package and a `role=kernel` record of the same
line exists under another pkginst (**the other kernel package**), apkg
replaces it in the same journaled transaction:

1. **Plan:** the transaction's plan (and `-n`, the dry run) says
   `kernel-k46-m replaces kernel-k46-z (KERN46Z): one kernel package per
   line`.
2. **Pre-flight** (§1.1) checks the transaction and every installed
   module record against the new kernel. A module that does not fit
   refuses the transaction before anything changes, naming it:
   `zeth46: built for kabi k46.1.0, the new kernel kernel-k46-z is
   static: remove the module packages first`. So going back from the
   module kernel to a static family needs the module packages removed
   first.
3. **`pkgrm` the other kernel package,** then remove its record (prints
   `removed KERN46Z`). The new package's `pkgadd` comes after, not before,
   because both ship `/stand/<line>/unix`: a `pkgadd` over another
   package's file is a conflict, and a `pkgrm` after it would leave the
   path shared in the contents database.
4. **`pkgadd` the new package,** then write its record (the ordinary
   `installed kernel-k46-m-<version>` line).
5. **The trigger** (C2-4 §3) runs once, at the end, as for any
   kernel-space transaction.

The bracketed name in the plan line and in `removed …` is the pkgrm'd
instance. A cut between steps 3 and 4 leaves the line without a kernel
package. `apkg recover` finishes the install from the journal (`apkg -f
recover` prints and discards the journal, as always, and warns when that
leaves a line without a kernel); until then the box still boots: the boot
store's generations hold their own copies of the kernel.

Refused, with nothing changed:
- two or more kernel records of one line already present (a box damaged
  by hand), for a kernel install and for a module install of that line
  alike (pre-flight against "the installed kernel" has no meaning then):
  `two kernel records for line k46 (KERN46M, KERN46Z): remove one`, the
  record names sorted;
- two kernel packages of one line in one transaction.

A package of the same pkginst is an upgrade, as before. apkg 0.3.1
(amix-packagemanager 06b77c4) implements this section.

## 3. Settled at agreement

- The field names are as above.
- A `file` line carries the SHA-256 of the installed file, computed by
  apkg at install.
- For a medium, `source` is the mount path or the raw device as apkg saw
  it.
- `/var/apkg/kpkg/` is apkg's alone; `kbootset` only reads it.
