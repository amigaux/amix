# C2-4 — `kbootset` as a called program, version 2

- **Status:** agreed 2026-10-25 (orchestrator); version 2 (2026-10-26): where `bootset=` is read (§3), and what is not in kbootset yet (§2). Other repositories build against this text; a change from here is a contract change with a version bump. The exit codes and messages are implemented (`kbootset/kbootset.c`).
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
| (none) | on the running box: the boot store found as in 40 §5, the root `/`. **Pending (S2-06, needs kinfo):** until then a store is always named with `--image` or `--dev` |
| `-R <root>` | on a mounted target (the installer, repair mode): packages, records and `/stand` under `<root>`; the boot store from `<root>/etc/default/bootset` or `--bootdev` |
| `--image <file> [--offset N]` | a store in a disk image at byte offset N (host media builds) |
| `--dev <path> [--offset N]` | a store on a raw device at offset N |
| `--journal <path>` | the journal. The default `<root>/var/kbootset/journal` is not in kbootset yet (it comes with the box form, S2-06): until then apkg always passes `--journal <target>/var/kbootset/journal`; without it there is no journal |
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
