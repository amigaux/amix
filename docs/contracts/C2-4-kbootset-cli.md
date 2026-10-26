# C2-4 — `kbootset` as a called program, version 10

- **Status:** agreed 2026-10-25 (orchestrator); version 2 (2026-10-26): where `bootset=` is read (§3); version 3 (2026-10-26): the box form and the default journal exist (§2), `/etc/default/bootset` (§6); version 4 (2026-10-26): `/dev/kinfo` made when missing (§2); version 5 (2026-10-26): `kbootset retry` for the base system's fsck-repair reboot (§7); version 6 (2026-10-26): `create` zeroes and refuses an occupied slice, `status` prints the set id (§8). version 7 (2026-10-26): `commit` writes nothing when the generation equals the default, and `commit --again` (§3, §10). version 8 (2026-10-26): module members in `build`, `commit`, `media` and `status` (§11). version 9 (2026-10-26): the booted kernel's namelist, `kbootset namelist` and `mark-good` (§9, §12). version 10 (2026-10-26): a boot from a read-only medium, a CD or a floppy pair (§13). Other repositories build against this text; a change from here is a contract change with a version bump. The exit codes and messages are implemented (`kbootset/kbootset.c`).
- **Implements:** `docs/spec/40-generations-and-composer.md` §3, §6 (the apkg trigger), §7 (the installer)
- **Called by:** apkg 0.3 (the trigger), the installer (`-R`), the media builders (`--image`)

## 1. Exit status

| Status | Meaning | The store |
|---|---|---|
| 0 | done | changed as asked, or nothing to do |
| 1 | an I/O error, a read-back mismatch, or a damaged store | a commit interrupted before its commit point leaves it unchanged; a later run reports the journal |
| 2 | usage | not touched |
| 3 | refused by a rule (read-only store, pristine never bad, no older good generation, …) | not touched |
| 4 | refused by a gate of 40 §3.1; the line names the gate's number | not touched |

apkg treats 3 and 4 as "the committed generation is unchanged" and
passes the `kbootset:` line on. Every line kbootset prints for a person
starts with `kbootset: `.

## 2. Where it works

| Form | Use |
|---|---|
| (none) | on the running box (S2-06): kinfo read from `/dev/kinfo` (C2-1). When the node is missing, kbootset makes it (character 53, 0, mode 0444) and says so; when it cannot, the facts come from bootset and the options only; the boot store found as in 40 §5 (bootset's `store=`, else the loader record through kinfo's card table, else a scan of every disk), refusing at gate 8 or 9; the facts from the options, then kinfo, then bootset (§6); `mark-good`'s `--booted` and `--secondary` default to kinfo's loader record |
| `-R <root>` | on a mounted target (the installer, repair mode): packages, records and `/stand` under `<root>`; the boot store from `<root>/etc/default/bootset` or `--bootdev` |
| `--image <file> [--offset N]` | a store in a disk image at byte offset N (host media builds) |
| `--dev <path> [--offset N]` | a store on a raw device at offset N |
| `--journal <path>` | the journal; default `<root>/var/kbootset/journal` in the box form, none with `--image`/`--dev` unless named (apkg names it); kbootset makes the missing directories above it (mode 0755) when it writes the journal |
| `media …` | the pristine generation of a new medium (host build only, S2-04): `--disk`, `--floppy`, `--cd` |

## 3. The trigger

After a transaction that changed a kernel-space package, apkg runs
`kbootset build && kbootset commit` when `bootset=auto`, and prints the
command otherwise. apkg reads `bootset=` from
`<target>/etc/default/bootset`: when the file or the key is absent it is
`auto`, and any value other than `auto` or `manual` counts as `manual`. On status 0 it repeats kbootset's last line:
`generation N committed; power-cycle to boot it`, or, when the
transaction changed nothing the default generation holds (a loader-only
or kbootset-only transaction, say),
`the default generation M already has these members; nothing to commit`
(§10). apkg never passes `--again`.

## 4. Power-cut rows

`commit` announces each step of 40 §3.2 on stderr as
`kbootset: step N <what>` (1 journal, 2 members, 4 manifest, 5 control
block = the commit point, 7 journal cleared). With `KBOOTSET_HOLD=N` in
the environment it syncs and waits before step N, for the rig to cut the
power (S2-08, S2-40).

## 5. Settled at agreement

- The five statuses are as above.
- apkg runs `build` and `commit` as two calls.
- The default journal path is `<root>/var/kbootset/journal`.

## 6. `/etc/default/bootset`

The installer writes it, apkg reads `bootset=`, and kbootset reads the
rest and rewrites `store=` and `store-id=`. One `key=value` per line,
lowercase keys, `#` comments, unknown keys ignored.

```
# /etc/default/bootset -- read by kbootset and apkg (40 §2.2, §5; C2-4 §6)
bootset=auto
store=/dev/rdsk/c6d0s3
store-id=1a2b3c4d
line=46
bootdev=zorro:0202:54
rootdev=zorro:0202:54
rootfs=ufs
mem=16777216
```

| Key | Meaning |
|---|---|
| `bootset` | `auto` or `manual` (§3) |
| `store` | the boot store's raw slice. The store starts at offset 0 of its slice. Used when kbootset is called without `--image`/`--dev` |
| `store-id` | the store header's set id, 8 hex digits. When the slice's header no longer carries it, kbootset finds the store again (40 §5) and rewrites `store` and `store-id` |
| `line`, `bootdev`, `rootdev`, `rootfs`, `mem` | the box facts (`bootdev`/`rootdev` are C2-1 §2.1 match keys, `mem` in bytes), used only for a fact that kinfo does not give |

There are no `root=` or `swap=` keys. kbootset carries both from the
default generation's manifest, and the installer names them once, on the
pristine build (`build --root … --swap …`).

## 7. `kbootset retry`: the fsck-repair reboot

Called by the base system (amix-installng owns `/sbin/bcheckrc`) just
before each `/sbin/uadmin 1 1` that follows a root repair: the `0|40`
case, the `*` case, and after the repair shell. One line before each:

```
[ -x /sbin/kbootset ] && /sbin/kbootset retry >/dev/console 2>&1
```

- **It acts** only when the booted generation (kinfo) is the trial on its
  attempt: the attempt is given back, at most twice per trial, and the
  next boot tries the trial again.
- **Otherwise** it does nothing and exits 0. That includes a kernel
  without kinfo, such as a 1.0 kernel: retry then prints nothing.
- **What it writes:** the boot store's control block, nothing else; the
  root may still be read-only or unrepaired.
- **Exit status:** 0, or 1 on an I/O error. The reboot follows either way.

## 8. `create` and the set id

- `create SIZE BOOT2 [--boot1 FILE] [--version N] [--force]` refuses,
  with status 3, a slice that already holds a store header or a bootblock
  (the magic `DOS`, as a 1.0 chain has). With `--force`, or on a blank
  slice, it zeroes the first 64 KiB, then lays the store, so nothing of
  an earlier chain survives. The installer need not zero the slice
  itself, and passes `--force` when it replaces a chain.
- `status` prints `store-id: <8 hex>`, the store header's set id, as
  `/etc/default/bootset`'s `store-id=` records it. Nothing outside
  kbootset needs to compute it.

## 9. `kbootset mark-good` at the end of run level 2

The base system (amix-installng) calls it once per boot, as the last
step of run level 2 (40 §3, D54), after every other `rc2.d` script,
so that a generation counts as good only when the whole of run level 2
has run:

```
[ -x /sbin/kbootset ] && /sbin/kbootset mark-good >/dev/console 2>&1
```

- **No options.** The booted generation, and whether boot1 ran the
  primary boot2, come from kinfo's loader record (§2).
- **What it prints:**
  - on a trial: `kbootset: generation N is good and the default`;
  - on any other boot: `kbootset: generation N is <state>; nothing to
    mark`;
  - after a new loader's trial boot, one more clause: the new loader is
    accepted, or, when boot1 ran the secondary boot2, the new loader did
    not complete a boot.
- **Exit status:**
  - 0 for all of the above;
  - 3 when it refuses: the booted generation is not in the store, or the
    kernel has no kinfo (`which generation booted is unknown`);
  - 1 on an I/O error.
- **The boot goes on whatever the status;** the hook never stops run
  level 2. A trial that is not marked good is taken back by the loader
  on the next boot (L8). That is the try-once rule, and the hook adds
  nothing to it.
- **On every boot** (not only a trial), after its own work, `mark-good`
  writes the booted kernel's namelist as `kbootset namelist` does (§12),
  and prints its line when it wrote one. A namelist it cannot write does
  not change the exit status.
- `retry` (§7), `namelist` (§12) and `mark-good` are the only calls the
  base system makes on every boot. `retry` writes no namelist: the root
  is not repaired when it runs.

## 10. An unchanged generation, and `commit --again`

`kbootset commit` compares the built generation with the default one
before it writes anything. The comparison is of what the two manifests
say, through the loader's parser:
- the line, kabi, CPUs, `loader-min`, root, swap, root filesystem,
  boards and arena;
- every member, by kind, name, size and SHA-256, and `bss=`;
- the parameters.

The generation id and the `created` time are not compared.

- **When they are equal,** commit writes nothing: no journal, no member,
  no control block. It removes the build from `/stand/gen/<id>`, so the
  next build starts clean with the same id, and exits 0. Its last line is
  `kbootset: the default generation M already has these members; nothing to commit`.
  apkg's trigger repeats it and finishes its transaction as after any
  commit.
- **`build` says so in advance:** `generation N built in /stand/gen/N;
  kbootset commit writes it; it equals the default generation M:
  kbootset commit will write nothing (commit --again writes it)`.
- **`commit --again`** commits the built generation even when it equals
  the default. When it does not, `--again` is a plain commit. It is for:
  - a repair. The comparison reads manifests, not the stored bytes, so a
    damaged copy of the default in the store compares equal. `kbootset
    check` is what finds damaged store bytes, and `commit --again` writes
    a fresh copy as a new generation;
  - rows and tests that need a new generation from the same packages.
- **`commit --spec`** is never compared. It writes the generation the
  spec gives.

## 11. Module members (S3-16, C3-5)

From kbootset -10 (amix-dlm a64aee1) on, a generation takes
the module packages installed under the root, as C3-5 §2 says.

- **What kbootset reads under the root** (the box's `/`, or `-R <root>`):
  - `/etc/conf/mod.d/<name>`: each module object, with its apkg record
    (C2-2, `role module`), which gate 1 checks;
  - `/etc/conf/modreg.d/<name>`, then `/etc/conf/modreg.local.d/<name>`:
    `param <pname>=<value>` and `disable`, a later line winning.
  No module package means a kernel-only generation, as before.
- **`build`** puts every module that is not disabled through gates 1 to 3
  (C3-5 §2). It copies each object byte for byte to
  `/stand/gen/<id>/mod/<name>`. Into the build it writes one `module`
  record per member, boot class first, then demand class, each in
  `depend` order, then one `param` record per declared parameter, its
  value in C3-1 §3's form. A refusal names the module and the gate, and
  exits 4.
- **`commit`** checks each copy against its record again (size and
  SHA-256: `… changed since kbootset build`, gate 1), and gate 2 against
  the kernel as it is now. The records go into the manifest after the
  kernel's.
- **`media … -R <root>`** composes the medium's pristine generation
  (id 1) the same way. The records go into the medium's manifest, and the
  copies go to `<root>/stand/gen/1/mod/<name>`. The medium's root
  filesystem must carry that tree at the same path: the module core loads
  `path=` from the root filesystem and checks it against the manifest's
  SHA-256. A medium whose staging root has no module package gets no
  module record. Only a host-mastered medium needs the copy: built from a
  staging root where the module packages are installed, its
  `/stand/gen/1/mod/` goes onto the target root with the rest of
  `/stand`. **The 1.1 installer on the box** runs `kbootset -R $TARGET
  build` (and `commit`), which writes `/stand/gen/<id>/mod/<name>` on the
  target root directly: no copy step.
- **`check`** hashes each module copy the manifests name (C2-5).
- **`status`** lists the booted generation's members, each marked from
  kinfo's module list (C2-1 offset 576, version 3; 536 in version 2): `module <name> (boot): loaded`;
  `… not loaded (the console says why)`; for demand class `… not loaded
  (loads at the first open of its device)`.
- **The unchanged-generation comparison** (§10) compares the module
  records and the parameters with the rest.
- **On the box,** `modadmin` (amix-dlm 55722ef on, built with `make box`,
  shipped in its own package `modtools`, not in kbootset's) lists the
  loaded modules and reads a module's tunables and counters by
  name (`-s`, `-Q`, `-k`, `-p`, `-w`). `modadmin -B` loads the boot-class
  members, from `/etc/inittab`'s first sysinit entry (C3-5 §5).

## 12. `kbootset namelist` (40 §4.2)

Writes the booted kernel's namelist to `/stand/unix`, the one path the
stock `nlist` consumers read (`netstat`, `ifconfig`, `crash`; S3-B5's
survey). It writes `/stand/unix.new` and renames it over `/stand/unix`,
so a `/stand/unix` that is a hard link to `/stand/2.1_unix` (as 1.0 left
it) loses only its name; `/stand/2.1_unix` is untouched.

- **No options.** The booted generation comes from kinfo (C2-1 version
  3); the kernel from that generation's manifest, read from the boot
  store. An ET_REL kernel gives its own symbols, laid out by the loader's
  relocator at kinfo's text vaddr. A `brel` gives none, so the symbols
  come from the line's `unix.sym` (C2-3 §2.1), when its SHA-256 matches
  the sidecar's `sym=` and the generation's kernel is the installed
  `unix`.
- **The check:** the layout's text, rodata and data addresses must equal
  kinfo's bootdata block. Otherwise nothing is written.
- **What it prints:**
  - `kbootset: namelist /stand/unix written for generation N, bound at
    0x<addr>` when it wrote one;
  - `kbootset: namelist for generation N is current` when the files
    already match;
  - `kbootset: no namelist: <reason>` otherwise: `kinfo version 2 gives no
    bind address`, `the kernel has no symbols (no unix.sym)`, `the layout
    does not match kinfo`, `kinfo flags a loader fault (0x8)`.
- **Exit status:** 0 when written or current, 3 when it cannot, 1 on an
  I/O error. The base system calls it early in run level 2 and ignores
  the status, from **`/etc/rc2.d/S01kbnamelist`**. `/sbin/rc2` runs the
  `S*` scripts in byte order, so it runs after `S01MOUNTFSYS` (`M` < `k`)
  and before every other `rc2.d` script (`S02PRESERVE` included), so before the
  network scripts (`netstat` and `ifconfig` users) and long before
  `S99zkbootset`, the `mark-good` hook (§9). Its body is the one line:

```
[ -x /sbin/kbootset ] && /sbin/kbootset namelist >/dev/console 2>&1
```

- **`status`** adds one line:
  - `namelist: /stand/unix is generation N's, bound at 0x<addr>` when it
    matches the booted kernel;
  - `namelist: /stand/unix is not the booted kernel's: run kbootset
    namelist` when it differs, or is another kernel (a link to
    `/stand/2.1_unix`);
  - `namelist: /stand/unix is missing: run kbootset namelist`;
  - `namelist: none (<reason>)` when none can be made, with the reasons
    above.
  `status` itself writes nothing.
- **The installer** (S3-31) removes the name `/stand/unix` from the
  target (`/stand/2.1_unix` stays) and installs `S01kbnamelist`.

## 13. A boot from a read-only medium (CD, floppy pair)

A CD (`amix-cdboot`, 10 §4.4) or a floppy pair boots a generation of the
medium. On a box that has a store of its own, that store did not boot,
and its generation of the same id is another generation. kinfo's loader
record says so: AXL1 flag 0x08, a read-only medium (10 §6); the CD also
gives no boot device (unit 0xFFFFFFFF).

- **`mark-good`** marks nothing: `kbootset: booted from a read-only medium
  (generation N of a CD|a floppy pair): nothing to mark`, exit 0. It still
  writes the namelist as below.
- **`retry`** does nothing and prints nothing (exit 0): no trial of the
  box's store booted.
- **`namelist`** cannot read the medium's kernel (the medium is not this
  box's store), so it takes the line's installed kernel. It does so only
  when the installed sidecar's `build=` is kinfo's build id. Then the
  kernel bytes are `/stand/<line>/unix` (and `unix.sym` for a `brel`),
  with the same layout check against kinfo's bootdata block. It prints
  `kbootset: namelist /stand/unix written for the medium's kernel
  (<build>), bound at 0x<addr>`, or `… is current`. Otherwise it prints
  `kbootset: no namelist: booted from a read-only medium whose kernel
  (<build>) is not the one installed here (<build>)`, exit 3.
- **`status`** prints `booted: generation N of a read-only medium (a
  CD|a floppy pair), not of this box's store; kernel <build>, …` and
  kinfo's loaded-module count, in place of the booted-generation and
  member lines. Its namelist line reads `namelist: /stand/unix is the
  medium's kernel's (<build>), bound at 0x<addr>`. The store found (40 §5)
  is listed as on any boot. None of its generations is the booted one.
- `build`, `commit` and the other commands compose for the box's own store
  as on any boot.

