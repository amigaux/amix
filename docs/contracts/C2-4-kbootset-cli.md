# C2-4 — `kbootset` as a called program, version 4

- **Status:** agreed 2026-10-25 (orchestrator); version 2 (2026-10-26): where `bootset=` is read (§3); version 3 (2026-10-26): the box form and the default journal exist (§2), `/etc/default/bootset` (§6); version 4 (2026-10-26): `/dev/kinfo` made when missing (§2). Other repositories build against this text; a change from here is a contract change with a version bump. The exit codes and messages are implemented (`kbootset/kbootset.c`).
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
| `--journal <path>` | the journal; default `<root>/var/kbootset/journal` in the box form, none with `--image`/`--dev` unless named (apkg names it) |
| `media …` | the pristine generation of a new medium (host build only, S2-04): `--disk`, `--floppy`, `--cd` |

## 3. The trigger

After a transaction that changed a kernel-space package, apkg runs
`kbootset build && kbootset commit` when `bootset=auto`, and prints the
command otherwise. apkg reads `bootset=` from
`<target>/etc/default/bootset`: when the file or the key is absent it is
`auto`, and any value other than `auto` or `manual` counts as `manual`. On status 0 it repeats kbootset's last line
(`generation N committed; power-cycle to boot it`).

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
