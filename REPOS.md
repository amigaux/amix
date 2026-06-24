# The Amix driver ecosystem — repo map

**Amix** is Commodore's port of AT&T System V Release 4 (SVR4.0) UNIX to the 68030 Amiga. These
repos are a family of MIT-licensed device drivers for it, plus the hub that builds them into a
kernel. Each repo has a single responsibility, and they reference each other by relative path —
**no submodules**. Place them as siblings:

| Repo | Owns | Kind |
|---|---|---|
| **amix-kerntools** (this repo) | The **build hub**: kernel-assembly harness, `driver.conf` discovery, generated SCSI selector wiring, the D245 clean-gate, and the host↔box tools. No driver source, no Amix. | hub |
| **amix-a4091** | The Amix **SCSI** driver for the Commodore A4091 / A4092 / A4770 (NCR 53C710). | driver (SCSI) |
| **amix-z3660scsi** | The Amix **SCSI** driver for the Z3660 PiStorm `piscsi` mailbox. | driver (SCSI) |
| **amix-z3660net** | The Amix **ethernet** driver for the Z3660 (`z3660eth`, STREAMS/DLPI). | driver (net) |

Each driver repo is independently MIT-licensed and ships only its `driver.conf` + its own `src/` +
`kernel-patches/` (unified diffs against stock Amix files) — never any full Amix source, and never
the generated `sd.c` / kernel `Makefile`.

## How they connect — the `driver.conf` contract

The hub is **not** a parent of the driver repos; it discovers them by relative path and reads each
one's `driver.conf`:

```sh
./amix-build --list                          # discoverable drivers
./amix-build a4091 z3660scsi z3660net         # build a kernel combining these
```

From each `driver.conf` the hub generates the on-box `sd.c` / `Makefile` (SCSI) or wires `cdevsw[]`
(net), applies the driver's `kernel-patches/*.patch` to the builder's own stock `/usr/sys`, links
the kernel, and runs the clean-gate. Driver source stays canonical in its own repo.

See [`AGENTS.md`](AGENTS.md) for the full driver-author contract and [`README.md`](README.md) for
the build how-to.

## Commit convention

No AI attribution in commit messages across these repos.
