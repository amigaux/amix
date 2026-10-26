# 40 — Generations and the composer

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §5 (upgrade install that keeps a data slice and restores the surviving configuration; a 1.1 layout that never needs a re-lay), D-3 §6 (two kept generations plus the pristine install generation; good only after a full multi-user boot; one-shot previous; safe mode; one boot slice per disk), D-3 §7 (kernel-space packages trigger a generation build and a reboot)
- **Replaces:** P-28 D7/D11 (slot composition), D15/D32 (second boot slice), D31/D35 (installer writes host bytes), D54 (mark good late — kept), D56 (2 MiB slices — moot, 1.0 boxes reinstall), D60 (finding the boot disk — simplified by the loader record)
- **Keeps:** P-28 D12, D14, D16, D19/D55, D59, D63

Paths are relative to the Amix project workspace. `LC` =
`tmp/2026-10-22-modules-proposal/07-installed-box-lifecycle-design.md`,
`PK` = `tmp/2026-10-22-modules-proposal/packaging-kernel-lifecycle-facts.md`.

## 1. Vocabulary

- **Generation:** an immutable set — one kernel, its root-class modules, its
  boot- and demand-class modules, parameters — described by one manifest
  (`10-boot-loader.md` §5.1) and identified by a number that is never reused
  on a box.
- **States:** `pristine` (the generation the install laid down; never
  deleted), `good` (completed a full multi-user boot), `trial` (committed,
  not yet good), `bad` (a trial that failed, or one marked bad by hand).
- **Kept set:** the pristine generation, the two newest good generations,
  and at most one trial. Everything else is collected.

## 2. Where things live on an installed 1.1 disk

### 2.1 Disk layout (designed never to need a re-lay)

| Slice | DosType | Content | Size (proposed) |
|---|---|---|---|
| s1 | `UNI\1` | root filesystem | rest of disk after the others |
| s2 | `resv` | swap | 30 MB floor (the 1.0 floor on the 040/060 line, `amix-installng/docs/swap-before-mkfs.md:39`); 18 MB below 200 MB disks as in 1.0 |
| s3 | `UNI\0` | the boot store (`10-boot-loader.md` §4.2) — the only boot slice on the disk | **64 MiB** |
| s4 | `UNI\1` | data filesystem, mounted at `/home` (user homes and site data) | chosen at install; default 25 % of the disk from 512 MB up; below 512 MB offered but not laid by default |

The 1.0 installer lays root, swap and a 10 MiB boot slice and no data slice
(`amix-installng/docs/installer.md:425,440-442`;
`amix-installng/docs/releases/1.0.md:107-117`). 64 MiB for the boot store
holds the kept set four times over at today's kernel sizes (a k46 kernel is
about 2.0–2.1 MB uncompressed, `amix-kerntools/docs/k0-families.md:1107-1120`)
and leaves room for larger kernels, more root modules and a rescue RAM-disk
generation without a re-lay. Smaller boot slices are not a 1.1 target (D-3 §5: 1.0 boxes reinstall).
They still boot, but the kept set does not fit them. A 4 MiB slice, as the
stage-1 test vehicles have, holds two raw k46 generations (M-GEN1): the
first and one upgrade. A third needs a generation marked bad first, and
`collect` alone frees nothing, since the default and the two newest good
ones are all kept. The data slice exists so a later reinstall can
keep user data (D-3 §5). Each filesystem stays under the 1.0 limit of
1024 MiB (`mkfs_ufs` fails at 65 536 cylinders,
`amix-installng/docs/releases/1.0.md:265-301`); on larger disks the installer
caps s1 and s4 at that limit until the limit is lifted (OQ-40.7). A disk laid without s4 can only carry the surviving configuration through a later reinstall.

### 2.2 Files on the root filesystem

| Path | Content | Owner |
|---|---|---|
| `/stand/k30/unix`, `/stand/k46/unix` + `kabi` | pristine kernel of the line and its sidecar (kabi tag, compiler pin, arena and identity offsets, SHA-256); `/stand/k30/unix.sym`, the symbols of a `brel` (C2-3 §2.1) | kernel package |
| `/stand/unix` | the booted kernel's namelist (§4.2), for the stock `nlist` consumers | `kbootset` |
| `/stand/2.1_unix` | the stock Amix 2.1 kernel, as the 1.0 install left it; nothing reads it | — |
| `/stand/loader/{boot1,boot2}` + `ldrinfo` | loader bytes and their version and SHA-256 | loader package |
| `/etc/conf/mod.d/<name>` | module objects | module packages |
| `/etc/conf/modreg.d/<name>` | the package's registration defaults (class, parameters) | module packages |
| `/etc/conf/modreg.local.d/<name>` | administrator overrides (parameters, disable) | administrator; owned by no package |
| `/stand/gen/<id>/` | per generation: `manifest`, `mod/` (boot- and demand-class objects, copied from `mod.d` at build) | `kbootset` |
| `/etc/default/bootset` | boot disk identity, `bootset=auto|manual`, menu timeout, console settings | installer, administrator |
| `/sbin/kbootset` | the composer, statically linked | kbootset package (part of the base set) |
| `/var/kbootset/journal` | in-flight build/commit record | `kbootset` |

Stock `/stand/boot2.boot` and `updbootpart` are no longer read, and no
loader reads `/stand/unix` (it holds the namelist, §4.2); `updbootpart` becomes a shim that refuses and names `kbootset` (P-28
D54). Members of a generation come from the package contents database, never
from a directory listing (`LC`:93).

## 3. `kbootset`

A userland program (built with the project's userland compiler, D-3 §9),
statically linked, run on the box and on the host (media builds use the same
program against an image file, so media and boxes cannot drift).

| Command | Effect |
|---|---|
| `kbootset status` | the kept set, states, the booted generation (from `kinfo`), the boot disk, free store space, warnings |
| `kbootset build` | compose the next generation in `/stand/gen/<new>/` from installed packages; runs every gate; writes nothing to the store |
| `kbootset commit` | write the built generation into the store as `trial`; read back; flip the control block; the default generation is not changed (a newer trial replaces an older unbooted one) |
| `kbootset mark-good` | called at the end of a full multi-user boot (end of run level 2): if `kinfo` names the booted generation and it is the trial, marks it good, makes it the **default** and clears the trial; also clears the loader-trial flag after a full boot through a newly installed boot2 |
| `kbootset retry` | called by the base system's fsck-repair reboot path: when the booted generation is the trial, its attempt does not count (at most twice per trial); writes the boot store's control block only, nothing on the root filesystem |
| `kbootset rollback` | sets the **default** to the newest good generation older than the current default, or to the pristine generation when there is no older good one (control-block flip); the rolled-from generation stays good; a pending trial is cancelled; a later boot uses the new default |
| `kbootset next --previous | --safe | --devload | <id>` | one-shot request for the next boot only (`--devload`: development load, `30-module-core.md` §2 patch 17) |
| `kbootset mark-bad <id>` | administrator verdict |
| `kbootset check` | recompute every member's SHA-256 in the store and in `/stand/gen` against the manifests and the package database; compare the installed packages with the default generation; never writes |
| `kbootset collect` | remove generations outside the kept set (also done by `commit`) |
| `kbootset loader-install` | install a new boot2 as primary (old one becomes secondary) and, only with an explicit flag, a new boot1 |
| `-R <root>`, `--image <file>` | operate on a mounted target (installer, repair mode) or a disk image (host media builds) |

### 3.1 Gates (fail-closed; no `--force`)

`build` and `commit` refuse, naming the gate, when:

1. **Hash:** a kernel-space member's SHA-256 differs from the catalog entry
   apkg recorded at install, or no entry was recorded
   (`60-signing-and-publishing.md` §3). The gate also reads the entry's
   `verified=` field, the hook for a later signature policy (§4 there); 1.1
   has no signing (D-3 §13).
2. **kabi:** members disagree on family, major, or compiler pin; a module's
   minor exceeds the kernel's; or a module imports a name that neither a
   module it depends on defines nor the kernel's symbol block exports (the
   sidecar's `ksym=`, C3-2; a core-tier name only for a core-tier module).
   That last one the core would otherwise refuse only at link, in the
   boot, with error 165.
3. **Closure:** the root-class set does not contain a module for the boot
   disk's controller and for the root disk's controller and filesystem, as
   seen by `kinfo` (or named with `--bootdev`/`--rootdev` on a host build).
   A CD or floppy pair's generation checks the root only: its loader reads
   the medium, never the kernel (C2-4 §13).
   It also refuses a root-class module for a controller the kernel drives
   itself (its sidecar's `root=`): two drivers on one board (C4-4 version
   4 §4.1; changed after the freeze, 2026-10-26).
4. **Arena:** the root-class set exceeds the kernel's arena capacity: the
   directory (32 + 48 bytes a record), the manifest copy, and every root
   record's file rounded up to 16 with its `bss=` tail, as boot2 places
   them all (C4-4 version 3); or the kernel's arena offset is not a
   multiple of 16, where no root-class module could start (C3-3 version 5).
5. **Store space:** the new generation does not fit the free store space
   without deleting a member of the kept set. A module kernel carries its
   arena as zeros in `.data` (0x60000 in stage 3, M-MOD1), so its file is
   larger than the static family's: 2.4 MB on k46, 1.7 MB on k30.
   kbootset writes disk-store members raw (10 §5.5). So a 4 MiB store
   holds one module generation only beside a deflated static generation
   (as `mkstore` writes a vehicle's generation 1 with deflate), not beside
   a raw one: a raw KD060-Z generation 1 (1 998 273 bytes) and the k46
   module kernel (2 426 952 bytes) do not fit. The installer's 64 MiB
   stores hold many.
6. **Memory:** fast memory on the box is below about twice the kernel plus
   arena plus RAM-disk image (`amix-kerntools/docs/k0-families.md:1126-1128`).
   The figure is kinfo's fast memory (C2-1 offset 528): the region the
   kernel was bound in, the only memory either line's kernel uses. Zorro
   III RAM is never kernel memory, and on k30 the region is at most
   64 MiB (10 §3). boot2's L4 stays the binding check, against the largest
   region below 0x40000000 (64 MiB at most on k30).
7. **Loader:** the installed loader's version is below the generation's
   `loader-min`. A generation with a root-class record has `loader-min` 3
   at least, so a store whose loader cannot place root-class modules
   refuses it when it is composed, not with L9 at boot (changed after the
   freeze, 2026-10-26).
8. **Boot disk:** the boot store cannot be identified unambiguously (§5).
9. **One boot slice:** the boot disk carries more than one `UNI\0` partition.
10. **Line:** the kernel's line does not match the box's CPU.

### 3.2 Commit sequence

1. Write a journal record (generation id, target store, extents planned).
2. Write each member into free extents (raw in a disk store, deflated
   only on media where a generation must fit, `10-boot-loader.md` §5.5)
   of the store's data area.
3. Read every written extent back and compare byte for byte.
4. Write the manifest, read it back.
5. Write the inactive control-block copy (sequence + 1) with the new
   generation as `trial`, read it back. **This is the commit point.**
6. Collect generations outside the kept set (their extents become free in
   the next control-block write; nothing is overwritten before the flip).
7. Clear the journal; print `generation N committed; power-cycle to boot it`
   (a real 68060 is power-cycled, not rebooted in software,
   `amix-installng/docs/releases/1.0.md:265-301`).

A power cut before step 5 leaves the old control block valid and the new
extents unreferenced; the next `kbootset` run sees the journal and cleans up.
A power cut during step 5 leaves one valid control-block copy (the old or the
new) by construction (`10-boot-loader.md` §4.2).

### 3.3 Marking good

`mark-good` runs from the last run-level-2 script. A box that panics or hangs
in `rc` never reaches it, so the trial stays unmarked and the loader's
try-once rule boots the previous good generation next time
(`10-boot-loader.md` §7.2; P-28 D54).

One reboot before that point is not the generation's fault: the root fsck's
repair reboot in `/sbin/bcheckrc` after an unclean shutdown. The base
system calls `/sbin/kbootset retry` just before each `/sbin/uadmin 1 1`
that follows a root repair, so that reboot does not spend the trial's
attempt (M-GEN3).
- `retry` writes only the boot store's control block. The root is not
  repaired yet when it runs, so it writes no journal, no
  `/etc/default/bootset` and no `/dev/kinfo`.
- It acts only when kinfo says the booted generation is the trial.
- It gives an attempt back at most twice per trial, so a root that never
  stays clean still ends in the try-once fallback.

## 4. `kinfo` and the namelist

### 4.1 `kinfo`

A read-only character device in the static floor (`70-static-floor.md`),
major per the registry (`20-module-format-and-abi.md` §6). One `read`
returns a versioned record: CPU type, line, kabi, kernel build id, the
booted generation id and state, the loader record (`10-boot-loader.md` §6),
the RTH1 record, the board set (`bootinfo.autocon[]` identities), the sd card
table (card → controller identity), where the loader bound the kernel (the
bootdata block, C2-1 version 3), the loaded-module list.

### 4.2 The namelist

The stock tools that read kernel memory find kernel symbols with `nlist`
on `/stand/unix`: `netstat`, `ifconfig` ("no namelist /stand/unix") and
`crash` (S3-B5's survey of the stock binaries: nothing reads `/unix`,
`ps` reads no kernel file, there is no `/dev/ksyms`). In 1.0 that file was
a hard link to `/stand/2.1_unix`, the kernel the stock loader booted,
linked at the address it ran at. With generations the booted kernel is a
generation's member, bound by the loader where it chose, and its file on
disk does not carry those addresses: an ET_REL kernel's symbols are
section-relative, and a `brel` has none. Without a namelist, `netstat -i`
reads `ifstats` at another kernel's address (S3-B5).

So **`/stand/unix` is the booted kernel's namelist.**
- **What it is:** an ELF32 `ET_EXEC` holding the booted kernel's symbol
  table, each symbol's value its address in this boot: the bind address
  plus its offset in the loader's layout (text, rodata, data, bss, COMMON;
  `10-boot-loader.md` §5). Section headers give each section's address
  and size, with no contents. It is not a kernel and boots nothing.
- **Its inputs:** the bind address and the section addresses from kinfo's
  bootdata block (C2-1 version 3); the symbols from the generation's
  kernel when it is ET_REL (laid out by the loader's own relocator), or
  from the kernel package's `unix.sym` (C2-3 §2.1) for a `brel`.
- **Who writes it:** kbootset, on every boot that reaches `mark-good`
  (C2-4 §9, §12), and whenever `kbootset namelist` is called. It checks
  the layout it computes against kinfo's rodata and data addresses. It
  writes the file only when the content differs, as a new file renamed
  into place. It never writes through the old `/stand/unix`, which may be
  a link to `/stand/2.1_unix`: the rename replaces the name and leaves
  that file as it was. The base
  system calls `kbootset namelist` early in run level 2 as well, so
  nothing typed or started later reads a stale namelist.
- **When it cannot:** with a version 2 kinfo, no kinfo, a kernel without
  symbols (a `brel` with no `unix.sym`), or a layout that does not match
  kinfo, it writes nothing and says why. `kbootset status` reports
  whether the namelist matches the booted kernel.
- **The installer** cannot know where the first boot will bind the
  kernel (the loader chooses at boot), so it lays no namelist. It removes
  the name `/stand/unix` from the target (`/stand/2.1_unix` stays), so
  that nothing reads another kernel's symbols, and the first boot's early
  `kbootset namelist` writes it. Until then the stock tools say "no
  namelist /stand/unix" rather than print another kernel's numbers.

## 5. Finding the boot disk

1. From the loader record: device, unit, partition start, board base and id.
   `kbootset` maps the board to an sd card through `kinfo`'s card table and
   opens the slice of that card/unit whose start equals the recorded
   partition start (located by DosType `UNI\0` in that disk's RDB, never
   assumed to be s3, `amix-installng/tools/write-bootchain.py:403-406`).
2. With no loader record (a box booted by the stock loader during the proof
   period), from the RTH1 boot fields when the boot flag is set and the
   controller is registered (P-28 D60).
3. Otherwise an RDB scan of every disk for `UNI\0`; exactly one candidate
   whose store header matches is accepted; more than one is refused.

The result is recorded in `/etc/default/bootset` and re-checked at every run.
The 1.0 tool derived the boot slice as s3 of the root disk, wrong whenever
boot and root disks differ (`tmp/2026-10-22-modules-proposal/refute-updbootpart-s3-claim.md`).

## 6. apkg integration

Requires apkg 0.3 (amix-packagemanager); deployed 0.2.3 cannot see kernel
space at all (`tmp/2026-10-22-modules-proposal/refute-apkg-stage-and-comment-skip.md`).

| Item | Rule |
|---|---|
| Kernel-space packages | roles `kernel`, `loader`, `module`; published in the public catalog inside a hidden `#ext kpkg 1` block (every line < 2048 bytes, `#` in column 0, header unchanged), so older clients never see them (P-28 D12) |
| Pure files | kernel-space packages carry files only (class `none`, no scripts) and never write a boot slice; `kbootset` does |
| Pre-flight | apkg checks kabi family/major, compiler pin and line before staging, and each kernel-space package's SHA-256 after download |
| Transaction | stage and verify every package, then install; a journal (`/var/apkg/txn`) and `apkg recover` finish or undo an interrupted transaction (P-28 D63). Atomicity for the boot path comes from the generation commit: a half-installed set never reaches the store |
| Trigger | after a transaction that changed a kernel-space package, apkg runs `kbootset build && kbootset commit` when `bootset=auto` (default), else prints the command. A failed gate exits with a distinct code and the message "the committed generation is unchanged" (`tmp/2026-10-14-modules-study/L4-packaging-with-apkg.md:608-640`) |
| User message | "generation N committed; power-cycle to boot it" |
| Superseded packages | the repository keeps exactly one previous kabi's kernel-space packages served (P-28 D55) |
| Streaming installs | from media, `apkg -R /mnt` fetches, verifies, installs and deletes one package at a time (P-28 D59); never arms a half-installed disk |

## 7. The upgrade install

The 1.1 installer offers "upgrade install" when the target disk already
holds an Amix installation.

| Target found | What is kept | What is replaced |
|---|---|---|
| a 1.1-layout disk (s4 data slice present) | s4 untouched; the surviving configuration (below) captured from s1 | s1 re-made, s3 re-written with a new pristine generation, swap re-made |
| a 1.0-layout disk (no data slice) | the surviving configuration only | the whole disk re-laid to the 1.1 layout (D-3 §5: 1.0 boxes reinstall) |

On a 1.0 disk the user's own data lives on the root filesystem, because 1.0
lays no data slice; the installer cannot keep it in place. Before re-laying it
prints what it will not keep and the size of `/home` and offers to stop.

**Surviving configuration** (OQ-40.1, answered by S4-54). What the first-boot dialog and the interview write: the node name and domain; the time zone (TIMEZONE, TZ, tz.index, clkzone); users and passwords (passwd, shadow, group) and the console login rule (default/login); the network: hosts, rc.inet, zen.conf, resolv.conf, netconfig, S99zen; the package client's configuration (apkg.conf); bcheckrc and the administrator's module parameters (modreg.local.d); the dialog's record (firstboot.conf), kept beside the new one. The dialog's choices that live in files packages own (syslog on or off, the A2024 flag, the keymap, the X colour server, the Netnews flavour) are kept as states and set again with the new system's own files. A choice whose package the new install lacks is reported, not forced. Everything is captured into a checksummed archive written to the swap slice before any filesystem is made. It is restored after the new root is made, put in place by the installer at the end of the install and verified there (each file's sum on the new root), before the first boot; the first boot leaves those files alone. Restored password entries keep their aging fields only if the battery clock passes setclk's plausibility gate and no entry's last change is later than today; otherwise every entry's aging fields are cleared, and the installer says so.

## 8. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-40.1 | The exact surviving-configuration set and its format (P-29 is parked and defines only package-conffile policy, `review/P-29-config-files-and-network-setup.md`). **Answered by S4-54** (amix-installng 74abe1f): §7, "Surviving configuration". | us |
| OQ-40.2 | Data slice default size and mount point (`/home` proposed). | us |
| OQ-40.3 | Whether the boot store should also hold a rescue RAM-disk generation so every installed disk can rescue itself without a medium. Not required by D-3 ("every install medium is the rescue medium"). | us |
| OQ-40.4 | Stock `pkgadd` behaviour on `/stand` conflicts and on files dropped by `instance=overwrite` (E1); `kbootset` already avoids depending on either. | us |
| OQ-40.5 | The checksum contract (`amix-kerntools/contracts/bootchain-v1.json`, `sum_gate_interplay`) needs a version 2 for generations: identity = SHA-256 per member from the packages plus the manifest; `kbootset check` as the second reader (P-28 D23 re-scoped). Written as a decision record when the store format is frozen. **Closed 2026-10-25** by `docs/contracts/C2-5-checksum-v2.md`. | us |
| OQ-40.6 | Whether the swap slice is always large enough for the configuration archive (18 MB minimum) — it is for any plausible configuration; a size cap and refusal are specified. | us |
| OQ-40.7 | Lifting the 1024 MiB filesystem limit, or laying several data filesystems on large disks; must be settled before the 1.1 layout freezes so no later release needs a re-lay. | us |

## 9. Measurements

M-GEN1 (generation size per line), M-GEN2 (commit time on a 68030 and a
68060), M-GEN3 (power cut at each commit step), M-GEN4 (`kbootset` static
size), M-UPG1 (upgrade install of a 1.0 disk) — `90-measurements.md`.
