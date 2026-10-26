# core/ — the module core

The loadable-module core of Amiga UNIX 1.1 (docs/spec/30-module-core.md).
It is a patch queue on **kdedon's DLM core** from the ashnazag project:
six system calls, an ELF relocatable loader, a kernel symbol block, and
the character-device, STREAMS, exec and hook linkages. The core is MIT
licensed, "Copyright (c) 2026 kdedon", and its licence is
`upstream/LICENSE`. Our thanks to its author.

| Path | What |
|---|---|
| `upstream.pin` | the upstream URL and commit the queue is based on |
| `upstream/` | upstream's `kernel/dlm` at that commit, unmodified, with upstream's `LICENSE` |
| `patches/NNNN-*.patch` | our changes, one self-contained change per patch, applied with `patch -p1` from `upstream/`'s root |
| `series` | the order the patches apply in |

The tree is never edited in place. A change is a patch. When the pin
moves to a later upstream commit, patches upstream has taken are dropped
from the series. The queue's base is the MIT commit in `upstream.pin` or
a later one; the project's earlier commits are GPL-2.0 and are never
used.

`tests/core/run.sh` (`make core`) builds the core from the patched copy
with this repository's toolchains and runs upstream's own host tests
against our kernels (M-CORE1).

## The patches

| # | Patch | What and why | Offered upstream |
|---|---|---|---|
| 0001 | `trampoline-hold-volatile` | The exec and cdev trampolines set the hold after `setjmp` and read it on the `longjmp` path. ISO C leaves such a variable indeterminate unless it is `volatile`: GCC 2.7.2.3 kept it in memory, but GCC 15 at `-O` put it in a register, and the state harness failed three checks. | not yet (OQ-30.6) |
| 0002 | `platform-registrations-out-of-dlm_init` | 30 §2 patch 1: `dlm_init` no longer registers ashnazag's guest major 59 or calls its `ds_modinit`. A platform registers in `plat_dmainit()`, which `dmainit()` calls after `dlm_init()`; ours live in `plat/k30/` and `plat/k46/`. | not yet (upstream would move the two calls to its own platform file) |
| 0003 | `moddata-v2-kabi-pin` | 30 §2 patch 4, contract C3-1. Wrapper revision 2, and `.moddata` version 2 (`MD2\0` plus key=value strings), every key checked. The module is checked against the kernel: its name, kabi family, major and minor, compiler pin, and the build id for the core tier. Root class is refused until the arena load path. The kernel's kabi and pin come from the kernel build (`DLM_KABI`, `DLM_PIN`). `mkmod` writes version 2 (`-K`, `-P`), and `modfix` checks it (`-1` lets the harness's version-1 case through). The state harness and `test/run.sh` gain the C3-1 refusals. | not yet |

The patches 30 §2 plans (the platform split, `.moddata` v2, the
allowlisted symbol block and the rest) follow in stage 3's order
(docs/plan/stage-3.md §2.2).
