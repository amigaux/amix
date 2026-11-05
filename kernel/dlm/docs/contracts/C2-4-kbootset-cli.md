# C2-4 — `kbootset` as a called program, version 28

- **Status:** agreed 2026-10-25; version 2 (2026-10-26): where `bootset=` is read (§3); version 3 (2026-10-26): the box form and the default journal exist (§2), `/etc/default/bootset` (§6); version 4 (2026-10-26): `/dev/kinfo` made when missing (§2); version 5 (2026-10-26): `kbootset retry` for the base system's fsck-repair reboot (§7); version 6 (2026-10-26): `create` zeroes and refuses an occupied slice, `status` prints the set id (§8). version 7 (2026-10-26): `commit` writes nothing when the generation equals the default, and `commit --again` (§3, §10). version 8 (2026-10-26): module members in `build`, `commit`, `media` and `status` (§11). version 9 (2026-10-26): the booted kernel's namelist, `kbootset namelist` and `mark-good` (§9, §12). version 10 (2026-10-26): a boot from a read-only medium, a CD or a floppy pair (§13). version 11 (2026-10-26): a read-only medium's gate 3 checks only the root controller (§13). version 12 (2026-10-27): `kbootset nodes`, the sd disk nodes of a four-card kernel, run by `commit` and reported by `check` (§14). version 13 (2026-10-27): `media --disk --ramdisk`, the netinstall raw image (§13). version 14 (2026-10-27, from a bench run): `status` in a safe boot names the safe set and says why the others did not load (§11). version 15 (2026-10-28, from a loader fallback in a bench run): `mark-good` after a boot where the loader fell back from the default verifies the default and marks it bad when its bytes are damaged (§9). version 16 (2026-10-30): `kbootset major`, a module's majors from the registry, for the base system's boot scripts (§15). version 17 (2026-10-31): the kbootset package ships the two boot scripts that call `namelist` and `mark-good`; the installer no longer writes them (§9, §12, §16). version 18 (2026-10-31): `kbootset major -l`, the whole registry (§15). version 19 (2026-10-31): the kbootset package owns `/dev/kinfo` (§2). version 20 (2026-10-31): a demand member may load at the first mount of its filesystem type, and `status` says so (§11). version 21 (2026-11-01): `kbootset cards`, the running kernel's sd cards with their controllers' match keys, and one disk's key, for an installer that takes the controller from the disk the user picks (§17); version 22 (2026-11-02): `cards` reads and prints the controller number `N` in hex, as the stock names write it (§17); version 23 (2026-11-02): `kbootset inquiry CARD UNIT` and `kbootset cards --probe`, one read-only SCSI INQUIRY per unit through `/dev/scsi`, so an installer knows a unit's type before anything reads it (§18). version 24 (2026-11-02): the A3000 onboard WD (`mobo:a3000-wd`) as a known limit of §18. Version 25 (2026-11-02): the limit is lifted for k30 -70 on (§18). Version 26 (2026-11-03): the namelist carries `crash_sync`'s word and the loaded modules' globals, and `modadmin` rewrites it after a load or an unload (§12). Version 27 (2026-11-04): `kbootset default`, and what `build`, `commit`, `check` and `status` say after an upgrade (§3, §19); a `brel` generation keeps its own `unix.sym`, and `status` tells a namelist that lacks a loaded module from another kernel's (§12); nothing to commit also removes the build's module copies (§10); the directory of a generation gone from the store is removed (§19); version 28 (2026-11-05): each store write is flushed before the next, `kbootset flush` (§20). Other repositories build against this text; a change from here is a contract change with a version bump. The exit codes and messages are implemented (`kbootset/kbootset.c`).
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
| (none) | on the running box: kinfo read from `/dev/kinfo` (C2-1). When the node is missing, kbootset makes it (character 53, 0, mode 0444) and says so; when it cannot, the facts come from bootset and the options only; the boot store found as in 40 §5 (bootset's `store=`, else the loader record through kinfo's card table, else a scan of every disk), refusing at gate 8 or 9; the facts from the options, then kinfo, then bootset (§6); `mark-good`'s `--booted` and `--secondary` default to kinfo's loader record |
| `-R <root>` | on a mounted target (the installer, repair mode): packages, records and `/stand` under `<root>`; the boot store from `<root>/etc/default/bootset` or `--bootdev` |
| `--image <file> [--offset N]` | a store in a disk image at byte offset N (host media builds) |
| `--dev <path> [--offset N]` | a store on a raw device at offset N |
| `--journal <path>` | the journal; default `<root>/var/kbootset/journal` in the box form, none with `--image`/`--dev` unless named (apkg names it); kbootset makes the missing directories above it (mode 0755) when it writes the journal |
| `media …` | the pristine generation of a new medium (host build only): `--disk`, `--floppy`, `--cd` |

**`/dev/kinfo` is the kbootset package's** (version 19): `c kinfo /dev/kinfo
53 0 0444 root sys`, in the class of its registry owner, `kinfo` (C3-5 v18
§1.2), from kbootset -29, the release-prep revision. Until that
is minted the installer makes the node, as it did before. kbootset still makes it
when it is missing, and amix-base's boot step re-creates it from the
package's record.

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
(§10). Either may end in `; the loader in /stand/loader is not on the boot
store yet: kbootset loader-install /stand/loader/boot2` (§19), and no
`kbootset: ` line follows it. apkg never passes `--again`.

## 4. Power-cut rows

`commit` announces each step of 40 §3.2 on stderr as
`kbootset: step N <what>` (1 journal, 2 members, 4 manifest, 5 control
block = the commit point, 7 journal cleared). With `KBOOTSET_HOLD=N` in
the environment it syncs and waits before step N, for the rig to cut the
power.

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

The kbootset package's boot script `kbmarkgood` calls it once per boot
(version 17, §16; amix-installng wrote the script before), as the last
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
- **After a fallback** (version 15). When kinfo's loader record has the
  fallback flag (0x04) and neither the menu flag (0x02) nor a menu or
  one-shot state, the loader passed over the default by itself. Unless a
  trial spent its attempt on that boot (L8 then takes the trial back),
  `mark-good` verifies the default's manifest and members as `check` does
  (40 §3.3) and adds one clause to its line:
  - damaged: `the loader refused the default and the store confirms it
    (<check's line for the member>): generation D marked bad, the default
    is generation N`. The default is marked bad and collected, and the
    booted generation N becomes the default;
  - intact: `the loader passed over the default, generation D, but its
    members verify: it stays the default (the loader's L line says why)`.
    Nothing is written.
  The pristine generation is never judged. With `--booted`, no loader
  record is read, so there is no fallback to judge. The exit status is as
  above; 1 when the control block cannot be written.
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
  no control block. It removes the build and its module copies from
  `/stand/gen/<id>`, and the directory, so the next build starts clean with the same id, and exits 0. Its last line is
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

## 11. Module members (C3-5)

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
  (loads at first use: an open of its device or a mount of its
  filesystem type)` (version 20).
  In a safe boot (kinfo flag 0x4), version 14: first the line
  `modules: safe mode: only the safe set loads this boot (<names>)`,
  naming the records marked `safe=1` (C3-5 §3) in manifest order. When
  none is marked, the line is
  `modules: safe mode: the safe set is empty; no module loads this boot`.
  A member outside the safe set that did not load says
  `… not loaded (safe mode)`. Before version 14 the first line read
  `modules: safe mode, none loads this boot`, even while root modules of
  the safe set were loaded.
- **The unchanged-generation comparison** (§10) compares the module
  records and the parameters with the rest.
- **On the box,** `modadmin` (amix-dlm 55722ef on, built with `make box`,
  shipped in its own package `modtools`, not in kbootset's) lists the
  loaded modules and reads a module's tunables and counters by
  name (`-s`, `-Q`, `-k`, `-p`, `-w`). `modadmin -B` loads the boot-class
  members, from `/etc/inittab`'s first sysinit entry (C3-5 §5).

## 12. `kbootset namelist` (40 §4.2)

Writes the booted kernel's namelist to `/stand/unix`, the one path the
stock `nlist` consumers read (`netstat`, `ifconfig`, `crash`). It writes `/stand/unix.new` and renames it over `/stand/unix`,
so a `/stand/unix` that is a hard link to `/stand/2.1_unix` (as 1.0 left
it) loses only its name; `/stand/2.1_unix` is untouched.

- **No options.** The booted generation comes from kinfo (C2-1 version
  3); the kernel from that generation's manifest, read from the boot
  store. An ET_REL kernel gives its own symbols, laid out by the loader's
  relocator at kinfo's text vaddr. A `brel` gives none, so the symbols
  come from the generation's own `/stand/gen/<id>/unix.sym` when it has
  one, else from the line's `unix.sym` (C2-3 §2.1), when its SHA-256
  matches the sidecar's `sym=` and the generation's kernel is the
  installed `unix`.
- **A generation's own `unix.sym`** (version 27): a package upgrade replaces
  the line's file, so a rollback's boot would have no symbols. A namelist
  made from the line's file saves a copy there, about 180 KB on k30; it
  goes with the generation's directory (§19). A generation
  that never booted under this version before its kernel was replaced has
  none: while the `/stand/unix` of its boot still matches kinfo's layout that
  counts as current; otherwise the line is `no namelist: generation N's
  kernel is not the installed one, whose unix.sym this is`.
- **The check:** the layout's text, rodata and data addresses must equal
  kinfo's bootdata block. Otherwise nothing is written.
- **What it carries beyond the kernel's symbols** (version 26), for stock
  `crash`:
  - `crash_sync` in a section of its own: PROGBITS, 4 bytes, the running
    kernel's word read through `/dev/kmem` (the 68040/68060 kernels set
    it at start-up, so the image's word is not the one in memory).
    `crash` reads its timestamp from the file at that symbol's own
    section, `sh_offset + (st_value - sh_addr)`, and stops on a NOBITS
    section. Without `/dev/kmem` the symbol is left out, and `crash` only
    warns that it checks no timestamps;
  - each loaded module's globals (kinfo's module list, C2-1 §2): the
    names from the module's file in the booted generation, the addresses
    from the module core's `getksym`, kept only inside that module's run.
    A boot from a read-only medium carries none.
- **Rewritten** at boot (`S01kbnamelist`), by `mark-good`, and by
  `modadmin` after `-l`, `-u` or `-U` has loaded or unloaded a module
  (core patch 0053). A demand-class module loaded at a mount shows at
  the next of these.
- **What it prints:**
  - `kbootset: namelist /stand/unix written for generation N, bound at
    0x<addr>` when it wrote one;
  - `kbootset: namelist for generation N is current` when the files
    already match;
  - `kbootset: no namelist: <reason>` otherwise: `kinfo version 2 gives no
    bind address`, `the kernel has no symbols (no unix.sym)`, `the layout
    does not match kinfo`, `kinfo flags a loader fault (0x8)`.
- **Exit status:** 0 when written or current, 3 when it cannot, 1 on an
  I/O error. The kbootset package's boot script `kbnamelist` calls it
  early in run level 2 and ignores the status, from
  **`/etc/rc2.d/S01kbnamelist`** (version 17, §16). `/sbin/rc2` runs the
  `S*` scripts in byte order, so it runs after `S01MOUNTFSYS` (`M` < `k`)
  and before every other `rc2.d` script (`S02PRESERVE` included), so before the
  network scripts (`netstat` and `ifconfig` users) and long before
  `S99zkbootset`, the `mark-good` hook (§9). Its call is the one line:

```
[ -x /sbin/kbootset ] && /sbin/kbootset namelist >/dev/console 2>&1
```

- **`status`** adds one line:
  - `namelist: /stand/unix is generation N's, bound at 0x<addr>` when it
    matches the booted kernel;
  - `namelist: /stand/unix is the booted kernel's, bound at 0x<addr>;
    kbootset namelist adds the modules loaded since` when only the module
    symbols differ, as after a demand load (version 27);
  - `namelist: /stand/unix is not the booted kernel's: run kbootset
    namelist` when it is another kernel or bind (a link to
    `/stand/2.1_unix`);
  - `namelist: /stand/unix is missing: run kbootset namelist`;
  - `namelist: none (<reason>)` when none can be made, with the reasons
    above.
  `status` itself writes nothing.
- **The installer** removes the name `/stand/unix` from the
  target (`/stand/2.1_unix` stays). `S01kbnamelist` comes with the
  kbootset package (§16).

## 13. A boot from a read-only medium (CD, floppy pair)

A CD (`amix-cdboot`, 10 §4.4) or a floppy pair boots a generation of the
medium. On a box that has a store of its own, that store did not boot,
and its generation of the same id is another generation. kinfo's loader
record says so: AXL1 flag 0x08, a read-only medium (10 §6); the CD also
gives no boot device (unit 0xFFFFFFFF).

- **`media --cd` and `media --floppy`** (version 11): the medium's loader
  reads it (amix-cdboot through dos.library, boot2 through trackdisk), and
  the kernel never drives its controller. So gate 3 checks the root
  controller and the root filesystem only, and `--rootdev` is required. A
  `--bootdev` given there is unused: `kbootset: --bootdev is not used for
  a read-only medium: its loader reads it, the kernel never drives it`.
  The generation carries no boot device either way. `media --disk` keeps
  both checks.
- **`media --disk --ramdisk`** (version 13): a disk store whose
  generation roots on the RAM disk, the netinstall raw image (C4-3 §1,
  50 §5). It is a read-only medium in the same sense: boot2 reads the
  store and the kernel roots on the RAM disk. So its generation is gated
  and composed as `media --cd` composes one (gate 3 checks the root
  controller only, members raw). mkstore's engine writes it into the
  image at `--offset`, a read-only store of `--size` bytes (mkstore's
  `-r`); the RDB around it is the media builder's. The bytes are the
  same as `mkstore -o IMG -p N -s S -1 F -2 F -r` on the spec that
  kbootset writes beside the image (`IMG.spec`). `--force` is not used
  there: mkstore writes the store in place.

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

## 14. `kbootset nodes`: the disk nodes of a four-card kernel (version 12)

Makes the device nodes C4-1 §2.4 requires on a root whose installed
kernel is a four-card one. It reads `sdcards=` from `<root>/stand/k30/kabi`
and `<root>/stand/k46/kabi`; when neither says 4, it does nothing.

- **No store.** It needs neither kinfo nor the boot store, so it works
  on a root that has none yet.
- **What it does:** it makes every node of the set that is missing, or
  is not of the right type, major and minor (it unlinks such a node
  first). It removes every `c<N>d1s<S>` node. On the running box (no
  `-R`) it then makes core's registration match: when
  `/var/sadm/install/contents` still names a d1 node, it runs
  `/usr/apkg/bin/removef core` with the d1 paths, 16 at a time, and
  `removef -f core`. When the contents do not name `/dev/rdsk/c1fd0s7`,
  it runs `installf core -` on the 256 card-2 and card-3 nodes and
  `installf -f core`. It runs APKG's tools from `/tmp`, because the
  stock ones take a bus error on the 68060. Under `-R` the registration
  is left to a run on the booted box.
- **What it prints** (one line, `kbootset: ` first):
  - `nodes: no four-card kernel installed (no sdcards=4 in /stand/k30/kabi or /stand/k46/kabi): core's nodes stand`
  - `nodes: the four-card set is complete (c0-c1f d0 s0-s7, no d1 nodes)`
  - `nodes: made N, removed M d1 nodes; registered to core`, with
    `no package database` or `the registration is the booted box's
    (kbootset nodes there)` in place of the last part where that applies
  - `nodes: N of T nodes could not be made or removed`
  - `nodes: made N, removed M d1 nodes; WARNING: core's registration failed (APKG's installf, removef)`
- **Exit status:** 0, or 1 for either of the last two lines.
- **`commit`** runs the same step on the running box once the commit
  has returned 0, whether it wrote a generation or had nothing to
  commit. It prints the `nodes:` line only when it made, removed or
  registered something, or failed. That line comes before the commit's
  own line, so apkg's trigger (§3) still repeats the commit's line.
  A failed node step leaves the commit's status unchanged.
- **`check`** on the running box adds the line
  `nodes: N of the four-card set missing or wrong, M d1 nodes left: run kbootset nodes`
  (with `, core's registration not done` before the colon when core
  disagrees) and counts it as one problem. A complete set prints the
  complete line. A root with no four-card kernel adds nothing.
- **The host build** writes no node and runs no tool. It prints each
  node it would make or remove (`would make /dev/rdsk/c16d0s0 c 40 134`),
  for the host test (`tests/host/knode.sh`).

## 15. `kbootset major`: a module's majors (version 16)

`kbootset major <name>` prints the majors the major registry gives the
module `<name>`, for a boot script that re-creates a missing `/dev` node
without carrying a number of its own.

- **The source** is the registry compiled into kbootset (`kbootset/kreg.c`,
  generated from `abi/registry/majors`). The kernel gives a module no other
  major: core patch 0006 refuses at load a module whose `majors=` the
  registry does not give it, and gate 3 refuses it at build (C3-5 §2).
- **No store, no kinfo.** It opens neither, nor the root, so it answers the
  same on a static kernel, in safe mode, on a boot from a read-only medium
  and under `-R` or `--image`.
- **What it prints:** one line per major, in the registry's order, `c <n>`
  for a character major and `b <n>` for a block major, with no
  `kbootset: ` prefix (the lines are for a script):
  - `kbootset major z3660eth` prints `c 51`;
  - `kbootset major ramdisk` prints `b 20`.
- **`kbootset major -l`** (version 18) prints every row of the registry,
  in its order, as `<module> c|b <n>`: `z3660eth c 51`, `ramdisk b 20`.
  It lets a boot step tell a node whose major the registry gives no
  module. There is no reverse form; `-l` covers it.
- **Exit status:** 0; 1 for a name the registry does not know, with
  `kbootset: no major is registered to <name>` on standard error and
  nothing on standard output; 2 for usage (no name, more than one, or
  anything after `-l`).
- **Stock drivers are not in the registry.** It names only the majors a
  module owns, so `kbootset major aen` (the A2065's c 18, a static stock
  driver) exits 1. A caller keeps its own number for those.
- **The host test** is `tests/host/kmajor.sh`.

## 16. The boot scripts (version 17)

The kbootset package owns the two scripts that make the calls of §9 and
§12. They are package objects, so an update of kbootset reaches them; the
installer stops writing them. The source is `kbootset/rc/`.

| Object | Type | Calls |
|---|---|---|
| `/etc/init.d/kbnamelist` | `f`, 0744 root sys | `kbootset namelist` (§12) |
| `/etc/rc2.d/S01kbnamelist` | `l` to it | |
| `/etc/init.d/kbmarkgood` | `f`, 0744 root sys | `kbootset mark-good` (§9) |
| `/etc/rc2.d/S99zkbootset` | `l` to it | |

- **The link names stay those the installer wrote**, so a 1.1 box's rc
  order does not change. `S01` sorts after `S01MOUNTFSYS`; `S99z*` is the
  band kept for the mark-good step.
- **Only `start` runs anything.** `/sbin/rc2` runs an `S` script as
  `/sbin/sh <script> start`; any other argument exits 0.
- **With amix-base's `/usr/lib/amix/rc.subr`** (`rc.subr(1M)`):
  - `kbnamelist=no` or `kbmarkgood=no` in `/etc/rc.conf` turns the script
    off; each is on when rc.conf has no line for it;
  - `kbmarkgood=no` prints `kbmarkgood: off (kbmarkgood=no in
    /etc/rc.conf): a trial generation is not kept` on the console at every
    boot: with it off, the loader takes every trial back (L8);
  - kbootset's exit status goes to `/var/adm/rc.log` (`rc_log`).
- **Without rc.subr** each script runs its call as before, with no log.
- **The call is the line of record** (§9, §12): `/sbin/kbootset <command>`,
  no options, its output on `/dev/console`; a missing `/sbin/kbootset` is
  skipped. Each script exits 0 whatever kbootset returns: neither ever
  stops run level 2.
- **Bourne sh of 1991** (C3-5 §1.3): no `$(…)`, no pattern expansions, no
  `printf`, no `local`.
- **The host test** is `tests/host/rcscripts.sh`: both scripts with and
  without rc.subr (amix-base's own, from `userland/base/rc/rc.subr`), the
  rc.conf keys, the log line, a missing kbootset, and the arguments other
  than `start`.

## 17. `kbootset cards`: which controller drives a disk (version 21)

`kbootset cards` prints the disk controllers the running kernel drives, so
an installer can take `--bootdev` and `--rootdev` from the disk the user
picks instead of from a profile per controller.

- **The source** is kinfo's sd card table (C2-1 §2): per card its number
  `k`, the controller id and the board base. The disks of card `k` are
  `c<8k>` to `c<8k+7>` in the `cNdMsK` names (C4-1 §2.4), `N` in
  lowercase hex as the stock `/dev/dsk` names and `kbootset nodes` write
  it: card 1 is `c8`–`cf`, card 2 `c10`–`c17` (version 22). The id becomes
  the match key exactly as gate 3 and the root record make it (C2-1 §2.1):
  `zorro:MMMM:PP` for a Zorro board, `mobo:<name>` for a motherboard
  controller.
- **kinfo only.** It opens neither the store nor the root and writes
  nothing, so `-R` and `--image` change nothing; on the box kinfo is
  `/dev/kinfo`.
- **What it prints**, with no `kbootset: ` prefix (the lines are for a
  script), one line per card in the table's order:
  - `card 0: c0-c7 zorro:144b:01 base 0x40000000` (the Z3660);
  - `card 1: c8-cf mobo:gayle`;
  - `card 2: c10-c17 mobo:a4000t-710`;
  - a Zorro board carries `base 0x<8 hex digits>`, its board base, which
    tells two boards of the same key apart; a motherboard controller has
    none;
  - an id with no key (an unknown motherboard code) reads
    `unknown controller id 0x<8 hex digits>` in place of the key.
- **`kbootset cards <disk>`** takes `/dev/dsk/cNdMsK`, `/dev/rdsk/cNdMsK`
  or the name alone and prints only the key of card `N / 8`:
  `kbootset cards /dev/dsk/c8d0s1` prints `mobo:gayle`, and so does
  `/dev/dsk/ced0s1` (unit 6 of card 1); `/dev/dsk/c10d0s0` is card 2.
  `N` is one or two lowercase hex digits; since `d` is one of them, the
  name is read from the right (`s` and the slice, `d` and the unit). The
  node is not opened; the name is enough.
- Version 21 read `N` as decimal: it refused `ca`–`cf` and gave card 1's
  key for `c10`–`c17` (kbootset 1.1.0.261101-34 and earlier; fixed in
  -35).
- **Only what the running kernel registered.** A card is in the table when
  its driver is linked and registered with sd in this boot (a static
  driver, or a root-class module the generation placed). On an install
  medium a target's controller is listed only when the medium's
  generation loaded its driver on that machine.
- **Exit status:** 0; 1 with a line on standard error and nothing on
  standard output when there is no valid kinfo record (`kbootset: no kinfo
  record at <path>: the kernel's sd cards are unknown`), when the disk's
  card is not in the table (`kbootset: <disk>: the running kernel has no
  card <k>`) or when its id has no key; 2 for a name that is not a disk
  node and for usage. With no cards in the table it prints no card line,
  says `kbootset: the running kernel registered no sd cards` on standard
  error and exits 0.
- **The host test** is `tests/host/kcards.sh`.

## 18. `kbootset inquiry` and `cards --probe`: what a unit is (version 23)

An installer must know whether a unit is a disk or a CD before it reads
it: a 512-byte read through `dd` of a CD behind an A4091 or A4092 wedges
the bus. These two forms ask each unit its type with one SCSI INQUIRY,
read-only, before anything opens it.

- **The command** is one INQUIRY (6-byte CDB `12 00 00 00 24 00`: LUN 0,
  36 bytes back) through the stock raw passthrough `/dev/scsi` (char major
  11, `scsi.c` `gsioctl`: `ioctl` `'GSIO'` with a `struct sdcom` carrying
  the card, the unit and the CDB). No other command is sent by these two
  forms, nothing is written, and no disk node is opened, so `sd` and `dd` never see the unit.
  Neither form reads the store or the root; `-R` and `--image` change
  nothing.
- **`kbootset inquiry CARD UNIT`**: `CARD` is the card number `cards`
  prints (0–3; card 1 is `c8`–`cf`), `UNIT` the target id (0–7). On an
  answer it prints one line, with no `kbootset: ` prefix, and exits 0:
  `type <n> <vendor> <product> <revision>`.
  - `<n>` is the peripheral device type, byte 0 & 0x1f, in decimal: 0 a
    disk, 5 a CD or DVD drive.
  - vendor is bytes 8–15, product 16–31, revision 32–35. Each has its
    trailing blanks and NULs trimmed and its inner blanks turned into `_`;
    a byte that is not printable reads `?`; a field that is all blank reads
    `-`. So the line is always five words.
  - Only the bytes the unit says it sent are read (5 + byte 4, the
    additional length): the kernel bounces the data through a static
    buffer it never clears, and a short answer leaves the last command's
    bytes behind it. A field past the end reads `-`.
- **No unit**, exit 1: nothing on standard output and one line on
  standard error, `kbootset: card <c> unit <u>: <why>`. That is the case
  for a qualifier other than 0 (byte 0 >> 5; 3 is "no device on this
  LUN"), type 0x1f, a command that failed or was not answered (a selection
  timeout), a card the running kernel did not register (`gsioctl`'s
  `sdopen` refuses it), and a missing `/dev/scsi` (the line names
  `mknod /dev/scsi c 11 0`).
- **Usage**, exit 2: a card outside 0–3, a unit outside 0–7, or not two
  numbers.
- **`kbootset cards --probe`** prints the `cards` lines of §17 and, under
  each card, one line per unit that answers: `  unit <u>: type <n>
  <vendor> <product> <revision>` (two blanks, then the five words of
  `inquiry`). It asks units 0–7 of every card in the table. A unit that
  does not answer prints nothing. Exit 0 whatever the units answer; the
  card lines and their statuses are as in §17. `cards --probe` takes no
  disk name.
- **Each line is flushed as it is printed**, a card's line before its
  units are asked, so output sent to a file is complete up to the moment
  of a stall: when a probe never returns, the last `card N:` line is the
  card whose controller it is waiting on.
- **How long it takes** depends on each controller module: `gsioctl`
  waits for the controller's own completion, with no timeout of its own,
  so an empty unit costs that controller's selection timeout. Every 1.1
  root-class controller module (z3660scsi, a4091, a4kt710, gayle) ends an
  empty unit's command with a failure, which the rows of the version-23
  host and emulator tests show.
- **One at a time.** `gsioctl` keeps its command and its buffer in
  static storage, so two processes must not use `/dev/scsi` at once.
- **Known limit: the A3000 onboard WD (`mobo:a3000-wd`, the stock static
  `a3091` driver; version 24).** Do not send it an INQUIRY through
  `/dev/scsi` unless it has already been used in this boot. The stock
  driver sets the WD33C93 up on its first command: it resets the chip and
  polls for the reset's interrupt. `gsioctl` queues its command at level
  0, so the driver's interrupt handler can take the reset's status (0x01,
  reset with advanced features) while it is idle. It prints
  `a3091: 0x1 0 0x0` and stops for the rest of the boot, so the queued
  command never completes and `gsioctl` sleeps for ever. The block path
  (`dd`, the partition reads) queues at `sdspl()`, level 2, so a block
  read as the first command is safe, and so is a box that boots from the
  WD. With kbootset -36 an installer runs `cards` (which sends nothing),
  leaves a `mobo:a3000-wd` card out of `inquiry` and `--probe`, and scans
  its units through the block path. **Lifted for k30 -70 and later
  (version 25):** its `sdqueue` raises to level 2 around every queue
  function, so the passthrough's first command takes the block path's
  route. Shown on an A3000 with the WD untouched by the boot: on -69 the
  first `kbootset inquiry` to the WD printed the line above and never
  returned; on -70 it answered (`type 0 …`), and a raw read, a mount and
  a second inquiry followed; -70 also boots with its root on the WD. k46
  -60 carries the same change; the limit stays for k46 until it is shown
  there, and for every earlier kernel of both lines.
- **The host test** is `tests/host/kinq.sh`: `KBOOTSET_SCSIDIR` names a
  directory whose file `<card>.<unit>` is the answer (no file, no unit), in
  place of `/dev/scsi`.

## 19. After an upgrade: the default, and what kbootset says (version 27)

A package upgrade puts files under the root; what boots stays what the
store holds. These commands say which is which.

- **`kbootset default ID`** makes a good or pristine generation the
  default, one control-block write and no new generation. It is the way
  back from `rollback`, whose line now ends
  `; kbootset default N goes back` while N is still in the kept set.
  - It prints `the default is generation N (was M); power-cycle to boot
    it`, or `generation N is already the default` and writes nothing.
  - Status 3, nothing written: `no such generation`; `generation N is on
    trial: power-cycle to boot it`; `only a good or pristine generation
    can be the default`; `generation T is on trial: boot it, or kbootset
    mark-bad T, first`, for a trial other than N.
- **`build`**, when another good or pristine generation already holds the
  built members (§10's comparison), ends its line
  `; good generation N already holds this: kbootset default N makes it
  the default without a new generation`. `commit` still composes a new
  generation: apkg's trigger never leaves the older default in silence.
- **`check`** compares the installed kernel package with the default, and
  says one of:
  - `<path> is the default generation N's kernel`;
  - `<path> (package P) is generation N's kernel, on trial: power-cycle
    to boot it`;
  - `<path> (package P) is generation N's kernel, not the default:
    kbootset default N boots it again`;
  - `<path> (package P) differs from the default generation N: kbootset
    build and commit compose it`, when no generation holds it.

  None of these counts as a problem.
- **A loader the store does not hold.** Upgrading the loader package
  changes `/stand/loader/boot2` and not the store. When the file differs
  from the store's primary boot2 (the length and CRC-32 in the store
  header, so no store read), with this clause:
  `the loader in /stand/loader is not on the boot store yet: kbootset
  loader-install /stand/loader/boot2`
  - `commit` appends it to its last line, after `; `, also when there is
    nothing to commit (§3);
  - `status` prints it as a `note:` line and `check` as a line of its own,
    not counted as a problem.

  kbootset never installs a loader unasked. No file, or an equal one, says
  nothing.
- **`/stand/gen/<id>` of a generation gone from the store** is removed:
  its module copies, `unix.sym`, build record and the directory. `commit`,
  `mark-good`, `collect`, `rollback`, `default` and `mark-bad` do it after
  they succeed, silently, so `mark-good` finishes at each boot what a power
  cut left. Three stay: the booted generation's, whose demand modules the
  running kernel still loads from there, until the next boot; one at or
  above the next id, a build not yet committed; and everything when the
  booted generation is unknown or a read-only medium (§13). `--image` or
  `--dev` without `-R` names a store that is not this root's, and removes
  nothing.
- **The host tests** are `tests/host/kupgrade.sh`, and `knamelist.sh` for the
  directories.

## 20. The order of store writes, and what a power cut can do (version 28)

What keeps a box bootable through a power cut is that each write of the store
is on the medium before the next starts: a header names only what is already
written, and only the header copy not in use is written.

- **After each store write**, before the next, kbootset:
  - calls `fsync` on the store, which is what a file or a block node needs. A
    raw node's write has already been completed by the disk, with no kernel
    cache in between;
  - sends the store's unit one SYNCHRONIZE CACHE (10) through `/dev/scsi`, when
    the store is a raw node named `cNdMsK`. gayle turns it into the ATA FLUSH
    CACHE, on a drive that has it. A unit that does not take it is no failure,
    as a unit without a write cache has nothing to flush; nor is a missing
    `/dev/scsi`. The store has already been read, so this is never the
    passthrough's first command on the disk (§18's known limit).
- **What this does not cover:** a unit with a write cache that does not take
  the command, or takes it and does not act on it, can still reorder writes.
  z3660scsi does not take it. boot1's tally write is not flushed, and needs not
  be: a lost attempt means one more start of the loader on trial.
- **`kbootset flush CARD UNIT`** sends that command alone, as `inquiry` sends
  its own, and needs no store. It prints `card <c> unit <u>: flushed` and exits
  0, or a line on standard error, `kbootset: card <c> unit <u>: <why>`, and
  exits 1. It exits 2 for arguments outside card 0-3 and unit 0-7. It tells
  whether a unit takes the command, not whether it has a cache.
- **The host test** is in `tests/host/kbox.sh`: `KBOOTSET_SYNCLOG` names a file
  that gets one line per flush, in the host build only.
