# C3-2 — the exported-symbol block, the allowlist and DDI v1, version 1

- **Status:** agreed 2026-10-26 (orchestrator), version 1. Other repositories build against this text; a change from here is a contract change with a version bump. The DDI list (§3) goes to Antti for review through the owner (OQ-20.4, D-3 §8); names his review adds or removes before the kit freezes change the minor, not this version.
- **Implements:** `docs/spec/20-module-format-and-abi.md` §1.2, §3.1, §4;
  `30-module-core.md` §2 patch 5
- **Produced by:**
  - the kit's allowlist files (S3-10);
  - the block generator and post-link gate (S3-04);
  - the kernel builds that link the block: amix-040-060-port (k46,
    S3-20) and amix-kerntools (k30, S3-21).
- **Read by:** the module core at every symbol lookup; the kit's checker;
  `getksym`.

## 1. The block

The block keeps upstream's format (`sys/ksym.h` at `b736c59`): a header,
`Elf32_Sym` entries with entry 0 null, the strings, and an ELF hash table.
Three things change. `KSYM_VERSION` becomes 2 for them.

1. **Values are relocations, not numbers.** Upstream's `mkksym` writes
   run addresses into a fully linked image. Our loader binds the kernel
   where the largest fast region is (10 §2.2), so no address is known at
   link time. Instead:
   - the block is generated **before** the final link, as an assembler
     source from the allowlist;
   - each entry's `st_value`, and the header's `kh_lo` and `kh_hi`
     (`stext`, `end`), is a `.long <symbol>`, an `R_68K_32` relocation;
   - the loader applies these with the rest of `.data`: k46 keeps
     `ET_REL` relocations, and on k30 `elf2brel` turns them into its
     relocation pairs, which M-ABI2 confirms for this size.
2. **The hash depends on names only,** so the generator computes it from
   the allowlist. `st_size` and `st_info` are not relocated. The post-link
   step fills them from the final link's symbol table: they feed the
   fingerprint (C3-3).
3. **Only allowlisted names are in it:** the DDI tier and the core tier
   (§4), not every global. Each `Elf32_Sym.st_other` holds the tier, 0 for
   DDI and 1 for core. The space shrinks from upstream's 160 KiB to a few
   KiB. `KSYM_SPACE` is set per line from the allowlist, with room for the
   minors to come.

The block is the `.data` object `dlm_ksym`. The identity record gives its
image offset and size (C3-3).

**Module tables.** As upstream: each loaded module has a table of its own
defined globals. Another module sees them only if it names the module in
`depend`. This is how z3660rtg reaches `monsw_set`, for example: through
the module symbol table, never through the kernel's allowlist.

## 2. The allowlist files

One file per line and tier in the kit: `abi/<line>/ddi.list` and
`abi/<line>/core.list`. One line per symbol:

```
<name> <func|data> <since>     # since: the kabi minor it entered, e.g. 0
```

`#` comments; sorted by name.

The **post-link gate** fails the kernel build unless:
- every listed name is defined in the final link, with the listed kind;
- the block holds exactly the listed names;
- the block passes the core's own check at two bind addresses. The gate
  relocates the image as the loader would, at 0x00200000 and at
  0x07F00000, and looks every name up through the hash. Each must resolve
  to its link value plus the bind address. This is the method of
  `tests/host/b2check.c`.

## 3. DDI v1, the stage-3 set (k30.1.0, k46.1.0)

Context means where the function may be called.
- `any`: interrupt level included.
- `proc`: process context; it may sleep.
- `no-sleep`: never sleeps, safe at any spl.

The "Today" column names the provider:
- **stock**: defined in all ten kernels of record (S3-40,
  `docs/measurements/2026-10-26-m-reg1-m-abi1.md` §3);
- **core**: the core pass links its own provider, because a kernel lacks
  it (20 §4.1).

The second column marks names one of today's two drivers imports
(`nm -u` of `z3660eth_040.o` and `zz9000_040.o`, amix-040-060-port
`build/`).

| Group | Names | Used today | Context | Today |
|---|---|---|---|---|
| console, errors | `printf`, `cmn_err`, `panic` | `cmn_err`, `printf` | any | stock |
| panic state | `panicstr` (data, read-only) | z3660eth | any | stock |
| kernel memory | `kmem_alloc`, `kmem_zalloc`, `kmem_free` | — | proc with `KM_SLEEP`; no-sleep with `KM_NOSLEEP` | stock |
| large memory | `sptalloc`, `sptfree` | z3660eth | proc | stock |
| DMA memory | `dma_alloc`, `dma_free`, `vtop`; on k46 also `dma_prepare`, `dma_complete`, `dev_kvmap`, `dev_kvunmap` | — | proc | `vtop` stock; `dma_alloc`, `dma_free`, `dma_prepare`, `dma_complete` core; `dev_kvmap`/`dev_kvunmap` stock in the A families, core in KD060-Z and K060 |
| copy, string | `bcopy`, `bzero`, `bcmp`, `memcpy`, `strlen`, `strcmp`, `strncmp`, `copyin`, `copyout`, `uiomove` | `bcopy`, `bzero`, `bcmp`, `memcpy`, `copyin`, `copyout`, `uiomove` | `copyin`/`copyout`/`uiomove`: proc; the rest any | stock |
| sleep, timers | `sleep`, `wakeup`, `timeout`, `untimeout`, `lbolt` (data, read-only) | `timeout`, `untimeout` | `sleep`: proc; the rest any | stock |
| privilege, devices | `suser`, `drv_priv`, `getmajor`, `getminor`, `makedevice` | `getmajor`, `getminor`, `makedevice` | proc for the first two; the rest any | stock |
| autoconfig | `autocon`, `bprobe` | `autocon` | proc | stock |
| interrupt level | `spl0`…`spl7`, `splx` as functions | — | any | core |
| interrupts | `intr_attach`, `intr_detach` | — | proc | core (S3-09) |
| STREAMS | `allocb`, `freemsg`, `freeb`, `dupmsg`, `copymsg`, `linkb`, `unlinkb`, `msgdsize`, `putq`, `getq`, `putbq`, `putnext`, `qreply`, `canput`, `flushq`, `OTHERQ`, `RD`, `WR` | all but `freeb`, `dupmsg`, `copymsg`, `linkb`, `msgdsize` | any, except where the STREAMS rules say otherwise | stock |
| network attachment | `if_attach`, `if_detach` | — | proc | core |
| console hook | `cons_hook_set`, `cons_hook_clear` | — | proc | core |
| libgcc | `__udivdi3`, `__umoddi3`, `__lshrdi3` | — | any | stock on k30, core on k46 |
| identity | `bootinfo`, `cputype` (data, read-only) | `bootinfo` | any | stock; `cputype` core on k30 |

**Never in the DDI tier** (20 §4.1): the switch tables and vectors
(`cdevsw`, `bdevsw`, `vfssw`, `int2_tbl`), `conputc` and `ifstats`. Today
z3660eth uses `ifstats` and zz9000 uses `conputc`. Their module forms move
to `if_attach` and `cons_hook_set` (C3-6). Each DDI function's written
contract (arguments, errors, memory class of what it returns) is in
`docs/abi/ddi.md` in the kit (S3-10). This table is its index.

**Later stages add to the DDI by minor:**
- stage 4: `sd_register`, `sdqueue`, `iodone`;
- stage 5: `vfs_register`.

Adding names raises the minor, never the major (20 §3.1). So the stage-3
set can freeze as v1.0 without waiting for the root drivers.

## 4. The core tier

The core tier is reserved now and first used in stage 5. It holds what the
stock filesystem objects import (`bdevsw`, `vfssw`, `nfstype` and the
others, 20 §4.1). Only a module with `tier=core` and the kernel's `build`
(C3-1) may resolve against it. The list is written when the filesystems are
carved (M-FS1).

## 5. Settled at agreement

- Values as relocations, the block generated before the final link from
  the allowlist, `KSYM_VERSION` 2, the tier in `st_other`.
- The allowlist file format, and the post-link gate at two bind addresses.
- The stage-3 DDI set above as v1.0. Antti's review may add or remove
  names before the freeze; after it, the minor rule holds.
- `panicstr` and `lbolt` exported read-only as data, as `bootinfo` and
  `cputype` are.
