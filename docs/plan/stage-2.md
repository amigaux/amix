# Stage 2 — lifecycle and rollback on static kernels: work breakdown

- **Status:** plan, 2026-10-25
- **Source:** `docs/spec/80-stages-and-proof.md` §2 stage 2, `docs/spec/40-generations-and-composer.md`, `docs/spec/60-signing-and-publishing.md` (as changed by D-3 §13), `docs/spec/90-measurements.md` stage-2 rows, `docs/spec/10-boot-loader.md` §6–§7
- **Exit gate (80 §2):** a box upgraded and rolled back with apkg alone; every power-cut point leaves a booting generation
- **Invariant carried forward (80 §3):** the pristine generation is never deleted; an unbooted generation never displaces a good one

Stage 2 still boots **static kernels**: a generation is a 1.0-family kernel
and its manifest. There are no modules and no arena, and a stage-1/2 loader
refuses both. What stage 2 adds is the lifecycle around that kernel:
- `kbootset` composes, commits, marks and rolls back generations;
- `kinfo` tells it which generation booted;
- apkg 0.3 delivers kernel-space packages with a SHA-256 and triggers
  `kbootset`;
- the installer lays the 1.1 disk layout and performs the upgrade install.

**Order against stage 1.** 80 §1 has each stage proven before the next
builds on it. The host-side items below use only the frozen formats (the
store, the manifest, the loader record), so they start now (orchestrator,
2026-10-25). Every stage-2 bench and metal row waits for stage 1's exit,
and the rows that rely on loader writes wait for M-LD4 (S1-22).

## 1. Conventions

As in `stage-1.md` §1:
- **ID** `S2-nn` for work, `C2-n` for an interface that two repositories
  must agree on before either side builds on it. The orchestrator holds
  that agreement (the workspace's cross-repo rule).
- **Owner** is the repository the work lands in.
- **Class:** `host`, `bench` (the emulator) or `metal`.
- **Estimate** in working sessions of one station.

**Toolchain.** `kbootset`, apkg and the installer's tools are userland. D-3
§9 builds userland with GCC 14 (gcc14-cross-amix), and kernel space with
gcc-cross-amix (GCC 2.7.2.3). `kbootset`'s sources stay C89 and share
`loader/common` with the loader, so either compiler builds them. The box
binary of record is the GCC 14 static build (S2-07).

## 2. Work breakdown

### 2.1 Interfaces to agree first

| ID | Interface | Drafted by | Agreed with | Needed by | Est. |
|---|---|---|---|---|---|
| C2-1 | **`kinfo` record v1**: the byte layout of one `read` (40 §4): version, CPU and line, kabi, kernel build id, the booted generation and its state, the loader record (`AXL1`, 10 §6) and RTH1 as booted, the board set, the sd card table, and the loaded modules (empty on a static kernel) | amix-dlm | amix-040-060-port (040/060 families), amix-kerntools (030 families) | S2-06, S2-10, S2-11 | 0.25 |
| C2-2 | **Kernel-space catalog entry and install record**: the fields of an entry in the hidden `#ext kpkg 1` block (role, line, kabi, compiler pin, SHA-256) and of `/var/apkg/kpkg/<pkg>` (the entry installed from, `verified=no`); the `#ksig` hook line (60 §3–§4) | amix-dlm | amix-packagemanager | S2-03, S2-20 | 0.25 |
| C2-3 | **Kernel and loader package layout**: `/stand/k30/unix` / `/stand/k46/unix` and the `kabi` sidecar (kabi tag, compiler pin, arena and identity offsets, SHA-256, and for a static family the controllers and filesystems built in); `/stand/loader/{boot1,boot2}` and `ldrinfo` (40 §2.2) | amix-dlm | amix-kerntools, amix-040-060-port, amix-packages | S2-03, S2-12 | 0.25 |
| C2-4 | **`kbootset` as a called program**: exit codes (gate refusals distinct from errors), the messages apkg passes on (40 §6), `-R <root>` for the installer, `--image <file>` for media builds | amix-dlm | amix-packagemanager, amix-installng | S2-22, S2-30 | 0.25 |
| C2-5 | **Checksum contract v2** (OQ-40.5): identity = SHA-256 per member plus the manifest; `kbootset check` is the second reader. A decision record replacing `bootchain-v1.json`'s `sum_gate_interplay` | amix-dlm | amix-kerntools | S2-05 | 0.25 |

### 2.2 `kbootset` (amix-dlm)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S2-01 | **Store core**: access to a store in an image file or a raw slice (offset, size); the free-extent map, derived from the control block and the kept generations' manifests (nothing else claims space); the GMF1 manifest writer, round-tripped through the loader's parser; the kept-set rule (pristine + two newest good + at most one trial) | amix-dlm | host | — | S2-02 | 1 |
| S2-02 | **State machine**: `commit` (journal → members → read-back → manifest → read-back → control-block flip → collect → clear journal, 40 §3.2); `mark-good`, `rollback`, `next`, `mark-bad`, `collect`, `loader-install` (primary/secondary, tally reset, header sequence + 1). Every step reads back and every refusal is fail-closed. Host tests include a fault-injecting I/O layer: a power cut after every single write, then recovery, must leave the old or the new control block and a bootable default (host half of M-GEN3) | amix-dlm | host | S2-01 | S2-03, S2-04, S2-08 | 2 |
| S2-03 | **`build` and the gates** (40 §3.1): compose `/stand/gen/<id>/` under a root (`-R`) from the package contents database and the apkg records (C2-2), the kernel sidecar (C2-3), and the box facts from `kinfo` (C2-1) or `--bootdev`/`--rootdev` on a host build. Gates 1–10, each refusal naming its gate; on a static kernel the closure gate reads the family's built-in controllers from the sidecar | amix-dlm | host | S2-02, C2-2, C2-3 | S2-07, S2-30 | 1.5 |
| S2-04 | **`--image`**: the same commands against a disk image for media builds (a medium's pristine generation and loader); the media builders call it instead of mkstore, and mkstore stays as the test tool | amix-dlm | host | S2-02 | S2-30 | 0.5 |
| S2-05 | **`status`, `check`**: the kept set and states, the booted generation, free store space, warnings; SHA-256 of every member in the store and in `/stand/gen` against manifests and records (never writes); journal recovery at every start | amix-dlm | host | S2-02, C2-5 | S2-41 | 0.5 |
| S2-06 | **Finding the boot disk** (40 §5): the loader record via `kinfo`, the RTH1 fallback, the RDB scan of every disk for `UNI\0`; the one-boot-slice gate; `/etc/default/bootset` | amix-dlm | host (cross build) | C2-1, S2-10 | S2-41 | 0.75 |
| S2-07 | **Box build**: statically linked, the userland compiler (GCC 14, D-3 §9); **M-GEN4** static size per line; a smoke run against a store image on the emulator | amix-dlm | host + bench | S2-03 | S2-12, S2-41 | 0.5 |
| S2-08 | **Power-cut hooks**: a step marker on the console before each commit step, and `KBOOTSET_HOLD=<step>` (sync, then wait), so a row can kill the emulator at a known step | amix-dlm | host | S2-02 | S2-40 | 0.25 |

### 2.3 Kernel side and packages (static kernels)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S2-10 | **`kinfo`** (character major 53, 20 §6) in the 040/060 static families: the C2-1 record from `bootinfo` (the loader record, RTH1, the boards); read-only; present in safe mode | amix-040-060-port (built on our line, offered as a merge request, 80 §4) | bench | C2-1 | S2-06, S2-41 | 1 |
| S2-11 | **`kinfo`** in the 030 families (K030-U and kin) | amix-kerntools | bench | C2-1 | S2-06, S2-41 | 0.75 |
| S2-12 | **Kernel packages**, one per static family on its line's path, with the sidecar; the **loader package** (`/stand/loader` + `ldrinfo`); the **kbootset package** (`/sbin/kbootset`, part of the base set) | amix-packages (inputs from amix-kerntools, amix-040-060-port and amix-dlm) | host | C2-3, S2-07 | S2-41 | 1 |

### 2.4 apkg 0.3 (amix-packagemanager)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S2-20 | **Kernel space in apkg**: SHA-256; the `#ext kpkg 1` reader; the verification-hook step ("unverified", passes); the `/var/apkg/kpkg/<pkg>` records; pre-flight on kabi family/major, compiler pin and line | amix-packagemanager | host + bench | C2-2 | S2-21, S2-41 | 1.5 |
| S2-21 | **Transaction**: stage and verify every package, then install; the `/var/apkg/txn` journal; `apkg recover` | amix-packagemanager | host + bench | S2-20 | S2-41 | 1 |
| S2-22 | **Trigger**: after a transaction that changed kernel space, `kbootset build && kbootset commit` when `bootset=auto`, else print the command; the distinct exit code and "the committed generation is unchanged" | amix-packagemanager | bench | S2-21, C2-4 | S2-46 | 0.25 |
| S2-23 | **Repository**: `gen-catalog.py` puts kernel-space packages in the hidden block (the private gate re-scoped, 60 §7); one previous kabi kept served. Every publication is a per-action owner decision | amix-packagemanager | host | C2-2 | S2-46 | 0.5 |

### 2.5 Installer and base system (amix-installng)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S2-30 | **1.1 layout and the pristine generation**: s1 root, s2 swap, s3 the 64 MiB store (the only `UNI\0`), s4 data (40 §2.1); the pristine generation and the loader written by `kbootset -R`; `/etc/default/bootset`; `kbootset mark-good` at the end of run level 2; the `updbootpart` shim that refuses and names `kbootset` | amix-installng | bench | S2-03, S2-04, C2-4 | S2-41, S2-31 | 1.5 |
| S2-31 | **Upgrade install** (40 §7): a 1.1-layout disk keeps s4; a 1.0-layout disk is re-laid. The surviving configuration is captured to the swap slice as a checksummed archive, restored and verified before the first boot | amix-installng | bench | S2-30, OQ-40.1 settled | S2-45 | 1.5 |

### 2.6 Rig, rows and measurements

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S2-40 | **Power-cut rows on the rig**: watch the console for a `kbootset` step marker, kill the emulator there, boot again and judge | amix-kerntools (rig) | bench | S2-08 | S2-42 | 0.5 |
| S2-41 | **M-GEN5**: upgrade, commit, mark-good, rollback, `next --previous`, and the try-once fallback, on a trial whose kernel cannot mount its root (it never reaches `mark-good`) | amix-dlm (rows by the Bench station) | bench | S2-05–S2-07, S2-10–S2-12, S2-20, S2-21, S2-30; stage 1 exit | S2-46 | 1 |
| S2-42 | **M-GEN3**: a power cut at each commit step leaves a booting generation; `kbootset` cleans up the journal on the next run | amix-dlm (rows by the Bench station) | bench | S2-40, S2-41 | S2-47 | 0.5 |
| S2-43 | **M-GEN1** generation size per line, **M-GEN2** commit time (bench upper bound), **M-SIG2** SHA-256 throughput (from axtime, S1-23) | amix-dlm | host + bench | S2-07 | S2-47 | 0.25 |
| S2-44 | **M-PKG1**: files dropped by `pkgadd instance=overwrite`; stock `pkgadd` on `/stand` conflicts (OQ-40.4) | amix-packagemanager | bench | — | S2-20 | 0.25 |
| S2-45 | **M-UPG1** bench half: the upgrade install of a 1.0 disk (configuration captured and restored, layout re-laid, first boot) | amix-installng (rows by the Bench station) | bench | S2-31 | S2-47 | 0.5 |
| S2-46 | **Exit row**: a box upgraded and rolled back with apkg alone, from a catalog with kernel-space entries | amix-dlm (rows by the Bench station) | bench | S2-22, S2-23, S2-41 | S2-47 | 0.5 |
| S2-47 | **Metal**: one upgrade + rollback + power-cut row per box per line (M-GEN3, M-GEN5); M-GEN2 on a 68060; one upgrade install of a 1.0 box per box (M-UPG1) | amix-dlm, amix-installng (via the lab registry) | metal | S2-42, S2-43, S2-45, S2-46 | stage exit | 1.5 |

### 2.7 Stage-2 rows of the media track

90 gives these rows stage 2, the stage that needs their result to exit.
80's stage-2 exit gate does not name them. They are listed here so that
nothing with stage 2 in 90 goes unowned.

| ID | Item | Owner | Class | Needs | Est. |
|---|---|---|---|---|---|
| S2-50 | **M-NET1f**: a single-user miniroot runs the inet STREAMS stack on a static kernel (DV-1) | amix-installng (rows by the Bench station) | bench | — | 0.5 |
| S2-51 | **M-TAPE1**: stock floppies and the stock tape image install in the emulator (origin of the old "timeout"); **M-TAPE2**: TAPE1 written from a running box reads back, and its throughput | amix-installng, amix-kerntools (rig) | bench | — | 1 |
| S2-52 | **M-TAPE3**: an emulated tape (ZuluSCSI image) behind the A4092; **M-TAPE4**: tape on card 1 through the A4091 driver, 060 line | amix-installng (via the lab registry) | metal | S2-51 | 0.5 |

## 3. Critical path and totals

`C2-1/C2-2/C2-3 → S2-01 → S2-02 → S2-03 → S2-07 → S2-12 → S2-41 → S2-46 → S2-47`.
Three outside lines feed S2-41 in parallel:
- `kinfo` (S2-10, S2-11, other repos, after C2-1);
- apkg 0.3 (S2-20, S2-21, after C2-2);
- the installer (S2-30, after S2-03 and S2-04).

The first item outside amix-dlm on the path is **S2-10/S2-11** (`kinfo`),
and the interfaces C2-1 to C2-4 are what the other repositories wait for.

Estimate: interfaces about 1.25 sessions (amix-dlm drafts, the orchestrator
agrees them); `kbootset` about 7; kernel side and packages about 2.75 (other
repositories); apkg 0.3 about 3.25; installer about 3; rows and measurements
about 5.5; the media-track rows about 2.

## 4. Exit ledger (80 §2)

What 80 §2 asks for stage 2 on the emulator, and where each result is
recorded. Records under `docs/measurements/` are this repository's; the
others are named by the repository that holds them. Metal is S2-47 for
every line of this table.

| 80 §2 item | k46 (bench) | k30 (bench) |
|---|---|---|
| upgrade, commit, mark-good, rollback, one-shot previous, try-once fallback | **passed** 2026-10-26: M-GEN5, `2026-10-26-m-gen5.md` | after S2-11 and the k30 kernel package |
| pristine boot | **passed**: the stage-1 vehicles boot a `state pristine` generation 1 (M-LD4 rows, the floppy pairs); the installer's pristine generation on the 1.1 layout is amix-installng's S2-30 | as k46 (the stage-1 rows ran both lines) |
| power cut at each commit step | **passed** 2026-10-26: M-GEN3, `2026-10-26-m-gen3.md` | optional: one N = 7 cell once the k30 package exists |
| refusal of a kernel-space package whose SHA-256 differs | **passed** 2026-10-26: apkg's S2-20 row (amix-packagemanager), below | line-independent (apkg's check) |
| upgrade install from a 1.0 image | M-UPG1, amix-installng's S2-45 row: to confirm with amix-installng whether a k46 disk ran | reported passed 2026-10-26 (`l11-k30-upg`); record in amix-installng |
| **exit gate:** a box upgraded and rolled back with apkg alone | **passed** 2026-10-26: S2-46, `2026-10-26-s2-46.md` | after S2-11 and the k30 kernel package |
| **exit gate:** every power-cut point leaves a booting generation | **passed**, as M-GEN3 | as above |

Still open on the bench besides the k30 column: M-GEN2 (commit time,
recipe in `tests/bench/README.md`), a stage-2 measurement that 80's exit
gate does not name.

**The SHA-256 refusal row** (evidence: the workspace's
`tmp/2026-10-26-s2/s2-46sha/N36/`). On the kinfo vehicle with apkg 0.3
and the S2-46 catalog, with a logging stub in place of kbootset:
- A datastream altered by one byte: `sha256 mismatch (got 085f472b…,
  catalog 9f46ab01…)`, exit 3.
- The catalog's hash altered instead: the same message with the roles
  swapped, exit 3.
- In both cases nothing followed: no `/var/apkg/kpkg`, no `/var/apkg/txn`,
  no package installed, no cache file, and the stub was never called.
- The positive control, the unaltered set, installed and called the
  trigger.

## 5. Not in stage 2

- Modules, the module core and the arena (stage 3).
- Root-class modules, the RAM-disk root and the miniroot boot of the floppy
  pair (stage 4).
- Signing: suspended by D-3 §13; the hook only (C2-2).
- The CD and netinstall media builds beyond what stage 1 and the media
  track need.
