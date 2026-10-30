# The Amix driver ecosystem — where each part lives

**Amix** is Commodore's port of AT&T System V Release 4 (SVR4.0) UNIX to the 68030 Amiga. Its
MIT-licensed device drivers are built into a kernel by `kernel/k30` in the
[amix](https://github.com/amigaux/amix) repository. Each driver has a single responsibility and
they reference each other by path — **no submodules**. The drivers live in amix under
`kernel/drivers/`:

| Part | Owns | Kind | Where it lives |
|---|---|---|---|
| **`kernel/k30`** (this directory) | The **on-box build**: kernel-assembly harness, `driver.conf` discovery, generated SCSI selector wiring, the D245 clean-gate, and the host↔box tools. No driver source, no Amix. | build | [amigaux/amix](https://github.com/amigaux/amix), `kernel/k30` (formerly the repository `amix-kerntools`) |
| **a4091** | The Amix **SCSI** driver for the Commodore A4091 / A4092 / A4770 (NCR 53C710). | driver (SCSI) | [amigaux/amix](https://github.com/amigaux/amix), `kernel/drivers/a4091` (formerly jusii/amix-a4091) |
| **z3660scsi** | The Amix **SCSI** driver for the Z3660 PiStorm `piscsi` mailbox. | driver (SCSI) | [amigaux/amix](https://github.com/amigaux/amix), `kernel/drivers/z3660scsi` (formerly jusii/amix-z3660scsi) |
| **z3660eth** | The Amix **ethernet** driver for the Z3660 (STREAMS/DLPI). | driver (net) | [amigaux/amix](https://github.com/amigaux/amix), `kernel/drivers/z3660eth` (formerly jusii/amix-z3660net) |
| **Z3660-amix** | The Z3660 **firmware + emulator** (Zynq ARM firmware, 68030 PMMU + emulated A3000 SCSI so a Z3660 can boot Amix). Owns the piscsi / ethernet **protocol spec** the `z3660*` drivers re-implement against. Fork of `shanshe/Z3660`. | firmware | [jusii/Z3660-amix](https://github.com/jusii/Z3660-amix), its own repository |

Each driver is independently MIT-licensed and ships only its `driver.conf` + its own `src/` +
`kernel-patches/` (unified diffs against stock Amix files) — never any full Amix source, and never
the generated `sd.c` / kernel `Makefile`. The `z3660scsi` / `z3660eth` drivers re-implement
against [`Z3660-amix`](https://github.com/jusii/Z3660-amix)'s protocol headers (citation discipline —
no shared include tree).

## How they connect — the `driver.conf` contract

`kernel/k30` is **not** a parent of the drivers; it discovers them in amix's `kernel/drivers/` (or,
as an explicit override, the folder given with `--drivers`) and reads each one's `driver.conf`:

```sh
./amix-build --list                                              # discoverable drivers
./amix-build a4091 z3660scsi                                     # build a kernel combining these
./amix-build --drivers ~/amix-drivers --list                     # drivers checked out elsewhere
```

From each `driver.conf` it generates the on-box `sd.c` / `Makefile` (SCSI) or wires `cdevsw[]`
(net), applies the driver's `kernel-patches/*.patch` to the builder's own stock `/usr/sys`, links
the kernel, and runs the clean-gate. Driver source stays canonical in its own directory or
repository.

See [`docs/driver-contract.md`](docs/driver-contract.md) for the full driver-author contract and
[`README.md`](README.md) for the build how-to.

## Commit convention

No AI attribution in commit messages.
