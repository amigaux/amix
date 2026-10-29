# Documentation

| Path | Content |
|---|---|
| `spec/` | The S0 specification: one file per area, numbered in reading order. `spec/00-overview.md` maps the release decisions to the files, collects the open questions, and points to `spec/90-measurements.md`. |
| `contracts/` | Interfaces between this repository and the others that build on it (`kinfo`, kernel-space catalog entries, package layouts, `kbootset` as a called program, the checksum contract): drafted here, agreed before either side builds on them. |
| `measurements/` | One record per closed measurement: what was counted, from which inputs (with hashes), what was left out, the numbers and the verdict. The tools that produce them are in `../tools/measure/`. |

Later additions keep the same rule: one topic per file, written for a reader
who has never seen the project, with references instead of copies for any
stock Commodore or AT&T material.

Planned: `abi/` (how to build a module against the ABI kit), `howto/`
(installing, upgrading and rolling back a kernel on a running box).
