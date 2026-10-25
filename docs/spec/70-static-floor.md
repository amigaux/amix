# 70 — The static floor

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §4 (the static floor; everything else is a module), D-3 §6 (safe mode = floor + root controller), D-3 §3 (one floor per CPU line, same membership)
- **Replaces:** P-28 D26/D27 (the floor list), P-28 D22 (root filesystems static until the base separates them)

Paths in this file are relative to the Amix project workspace (see `00-overview.md`, "Sources").

## 1. Rule

The *static floor* is the set of drivers and subsystems linked into the kernel
image of a CPU line. It is fixed by D-3 §4 and is the same on both lines,
membership for membership. Everything not on the floor is a module: disk
controllers that can carry root, root filesystems, network interfaces other
than the A2065, graphics, the optical filesystem, the RAM disk. A floor member
is never also shipped as a module; a module never shadows a floor member.

The floor answers one question: *what must work when nothing but the kernel
file has been read?* Three situations need it:

1. **Safe mode** (D-3 §6): the loader loads the floor kernel plus only the
   modules the root disk needs (its controller and its filesystem). The floor
   must therefore give a console, a way to type, and every subsystem the root
   controller and root filesystem modules depend on.
2. **A bad module set.** If every root-class module of a generation is
   damaged, a stock-controller box (A3000, A2091, A2065 network) still boots
   and can be repaired from the floor alone.
3. **The install and rescue media.** A medium must reach its installer even
   when its module store is unreadable; the floor provides the floppy, the
   tape and the stock SCSI paths that the 1992 hardware boots from.

## 2. Members and the reason for each

| Member | Why it is on the floor | Notes |
|---|---|---|
| Base kernel (VM, process, STREAMS framework, `specfs`/`fifofs` and the other non-root pseudo filesystems, the inet stack) | Not separable without rewriting stock code; the module core and every module depend on it. | The inet stack stays with the base because the static A2065 needs it and because the network driver modules (z3660eth) attach below it. |
| Console and serial (`c0`-family console, the Amiga serial port) | Safe mode and the loader's failure paths end at a console; headless boxes are driven over the serial port. | The serial console is the only console on a headless box (see `10-boot-loader.md` §7.1 and §7.4). |
| Floppy (`fd`, major 16) | The classic install medium boots and roots from DF0 (`bootchain-facts.md` D5, F10); the floppy pair is a supported medium on both lines (D-3 §3). | On the 040/060 line the floppy's chip-RAM DMA buffer depends on the DTT0 no-cache window (`bootchain-facts.md` F10); proven on the bench only, a metal row is listed in `90-measurements.md` (M-FD1). |
| FPE (the floating-point emulation for the 68040/68060 unimplemented instructions; the 030 line's FPU support) | Needed before any user process runs; a missing FPE breaks `init`. P-28 D27 already ruled it never a module. | On the 040/060 line it is part of the port's base (Antti's line). |
| Stock WD33C93 host adapters (A3000 onboard SCSI, A2091/A2090) and the `sd`/`dd` disk layer | The machines Amix was written for boot from these; a stock box must reach its root disk with no module. The `sd` layer is the registry every root controller module plugs into (`30-module-core.md` §5), so it cannot itself be a module. | The A3000 probe keeps its gate (VPOSR AGA check and two-register readback) so a phantom A3000 controller never takes card 0 (`bootchain-facts.md` C6). |
| A2065 Ethernet | The stock network card of the period; a networked stock box can fetch packages with no module. | z3660eth is a module (boot class). |
| Tape (`ct`, the QIC SCSI tape driver) | Tape is a package source behind a boot medium (D-3 §2); a module store cannot be read from tape before the tape is readable, so the reader is static. | Positionless I/O and close-time filemark spacing are documented in `tmp/2026-10-22-modules-proposal/refute-tape-seof-raw-claim.md`. |
| `kinfo` | Read-only identity device: CPU line, kabi, generation id, boot and root disk, board set, loader record. `kbootset`, `apkg` and the installer need it on every boot, including safe mode (`40-generations-and-composer.md` §4). | Major number assigned in the registry (`20-module-format-and-abi.md` §6). |
| The module core | Loads everything else (`30-module-core.md`). | Includes the allowlisted symbol table. |

## 3. What is deliberately not on the floor

| Not on the floor | Why it can be a module | Consequence |
|---|---|---|
| z3660scsi, A4091/A4092, Gayle IDE, the A4000T onboard 53C710 (once its driver exists) | Root-class modules loaded by our loader before the kernel starts (D-3 §1, §4). | A box rooted on one of these needs its module from the generation; safe mode loads exactly that one. |
| ufs, s5, cdfs | Root-filesystem modules (D-3 §4). | Safe mode loads the root filesystem's module beside the root controller's. The manifest names the root filesystem type (`10-boot-loader.md` §5). |
| RAM disk | Needed only by media that root on a decompressed image (CD, netinstall). | A root-class module on those media. |
| z3660eth, z3660rtg, monitor switch, any later driver | Not needed to reach a shell. | Boot or demand class. |

## 4. Safe mode, precisely

Safe mode = the floor kernel + the root controller module + the root
filesystem module named in the generation manifest, and no other module.
The kernel learns it is in safe mode from the loader record
(`10-boot-loader.md` §6); in safe mode `marc_post` loads nothing and demand
loading is refused. A stock-controller box needs no module at all in safe
mode except its root filesystem.

## 5. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-70.1 | The exact symbol surface of the ufs/s5 carve-out from the 040/060 base (`30-module-core.md` §6, M-FS1); our line does the rebuild (D-3 §4). | us, Antti reviews |
| OQ-70.2 | Does safe mode with ufs as a module leave any boot-time consumer of ufs inside the base (swap, `/stand` paths in stock code)? | us |
| OQ-70.3 | Is the inet stack separable on either line? Not required by D-3; recorded so the answer is written down. | us |

## 6. Measurements

M-FL1 (floor kernel size per line), M-FL2 (safe-mode boot on every root
controller), M-FD1 (floppy DMA under 040/060 caches on metal). Definitions and
evidence classes in `90-measurements.md`.
