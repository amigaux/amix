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
| 0004 | `format-errors-enoload` | C3-1 §4: a file that is not a loadable module is refused with `ENOLOAD` (164), not `EINVAL`. | not yet |
| 0005 | `allowlisted-symbol-block` | 30 §2 patch 5, contract C3-2. Symbol block version 2. `mkksym -a` writes the block of the allowlisted names as assembler before the final link, with the values as relocations, so it stays right wherever the loader binds the kernel. `mkksym -f` fills the sizes. `st_other` is the tier, and only a core-tier module resolves a core-tier name. `dlm_init` checks the block against `dlm_ksym_space`, and the stock `dlmksym.s` is an empty block. | not yet |
| 0006 | `major-registry` | 30 §2 patch 6. A module's `majors=` must name numbers the registry gives to that module (`ECONFIG` otherwise). The kernel build generates the table from the kit's `abi/registry/majors` with `tools/mkreg`. | not yet (upstream would carry its own registry file) |
| 0007 | `fmodsw-no-truncation` | 30 §2 patch 12. Every stock STREAMS-module row is kept. More than 11 leave fewer rows for modules and are reported; more than the table holds panic at `dmainit`. | not yet |
| 0008 | `measured-structure-layouts` | 30 §2 patch 15. The `mod_drv_data`, `cdevsw`, `mod_str_data`, `streamtab` and `qinit` layouts are measured from the kernel's headers by the kernel's compiler (`dlmoffs.c`, `tools/mkoffs`, `dlm_offs.h`) instead of written down. On the 2.1 sysroot all 19 equal upstream's values. | not yet |
| 0009 | `manifest-only-loading` | 30 §2 patch 17, contract C3-4. Every load resolves a module only as a member of the booted manifest (the loader's copy in the arena, found through AXK1 and checked by `dlm_arena.c`). It is read from its `path=` into memory, its SHA-256 checked, and loaded from that copy; anything else is `EPERM`. The development-load flag (`dlm_devload`) lets a module outside the manifest load, and says so each time. SHA-256 and CRC-32 come from amix-dlm's `loader/common`. | not yet (upstream would supply its own hash code) |
| 0010 | `marc-post` | 30 §2 patch 16 (the boot-class half), C3-5. `dlm_marc_post()` registers the demand-class majors from the manifest, then loads the boot-class records in manifest order unless `match=` names no board here (`dlm_plat_match`), with one console line each. Safe mode (`dlm_safe`) loads nothing and refuses every other load. A member's `param` records reach its `_load` as one string. | not yet |
| 0011 | `ddi-providers` | The DDI v1 services the kernels have no callable form of. The `spl` functions match `<sys/inline.h>` (spl5–7 raise to level 4). `if_attach`/`if_detach` work on the stock `ifstats` list. `cons_hook_set`/`clear` wrap the stock `scrcon_put`, which the kernel build weakens and keeps as `__amix_scrcon_put`. | not yet |
| 0012 | `interrupt-chains` | 30 §4 (§2 patch 10). `intr_attach`/`intr_detach`: a level-2 chain walk in `int2_tbl`'s last handler slot, which calls the displaced handler first, and a level-6 chain behind a wrapper at the stock `aciabintr`, which the kernel build weakens and keeps as `__amix_aciabintr`. Every handler is called every time, as the stock ones are; claims are counted. | not yet |
| 0013 | `no-weak-symbols-kinfo-list` | From the port's dry run: `mkksym -a` aligns the block to 4 (`.data` follows `.text` directly); `hooksw` is strong, and `dlm_cache.s` has no weak `plat_dmainit` (the platform always provides it), so no weak symbol survives a splice; `dlm_kinfo_list()` gives a kinfo driver the loaded modules (C2-1 offset 536). | not yet |
| 0014 | `mkmod-for-the-kit` | `mkmod` runs from the ABI kit's directory with the compiler the kit's make fragment sets (`MKMOD_CC`), no toolchain `env.sh` beside it; `$modtype` takes `drv` and `str` as well as `misc`. | not yet |
| 0015 | `modadmin-symbols-kmem` | `modadmin -k` looks a name up with `getksym` (the kernel's exported names, then each loaded module's globals), `-a` the symbol at an address, `-p` reads longs at a symbol through `/dev/kmem` and `-w` writes one: a module's tunables and counters move with it, so they are reached by name (S3-11). | not yet |

The patches 30 §2 plans (the platform split, `.moddata` v2, the
allowlisted symbol block and the rest) follow in stage 3's order
(docs/plan/stage-3.md §2.2).
