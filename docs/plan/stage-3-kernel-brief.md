# Stage 3 — the first module kernels (S3-20, S3-21): brief

- **Status:** brief, 2026-10-26. It names what amix-dlm hands over, what
  each kernel build does, and how it is accepted. §1 lists what amix-dlm
  still owes before a kernel can be cut. The kernel repositories can
  prepare §3's steps now, and dry-run them with the providers stubbed as
  `make core` does.
- **Plan items:**
  - S3-20, the k46 module kernel, amix-040-060-port: KD060-Z from the
    port's k46 line, the tree the stage-2 kinfo kernel came from;
  - S3-21, the k30 module kernel, amix-kerntools: K030-U with `kinfo`
    (kerntools 5b5fa21), as packaged in `kernel-k30-u`.
- **Contracts:**
  - C3-1, the module object;
  - C3-2, the symbol block, the allowlist and the gate;
  - C3-3, `AXK1` and the sidecar, C2-3 version 5;
  - C3-4, the arena;
  - C3-5, the manifest records;
  - C2-1, `kinfo`, whose module list is now filled.

## 1. Owed by amix-dlm before the cut

| What | Why the kernel needs it | Plan item |
|---|---|---|
| ~~Core patch for the DDI providers~~ **done, core patch 0011:** the `spl0`…`spl7`/`splx` functions (as `<sys/inline.h>`: spl5–7 = level 4); `if_attach`/`if_detach` on the stock `ifstats` list, with no kernel change; `cons_hook_set`/`cons_hook_clear`, a wrapper at the stock `scrcon_put` (step 7) | the gate needs every allowlisted name defined; a stub in a real kernel would crash the first module that calls it | S3-04's provider half |
| The other providers: on k46 `__udivdi3`/`__umoddi3`/`__lshrdi3` from gcc-cross-amix's `libgcc.a` (step 7) and `dev_kvmap`/`dev_kvunmap` from the port's own `devkvmap040.o` (KD060-Z lacks them, the A families link them); on k30 `cputype` (`core/plat/k30`). DMA is not in DDI v1.0 (orchestrator, 2026-10-26), so no kernel owes `dma_*`. The port's `dma_prepare`/`dma_complete` stay kernel-internal | as above | — |
| ~~Core patch for `intr_attach`/`intr_detach`~~ **done, core patch 0012:** a level-2 walk in `int2_tbl`'s last handler slot; a level-6 chain behind a wrapper at the stock `aciabintr`, spliced in step 7 | the same name in the allowlist, and z3660eth's interrupt option | S3-09 |
| ~~`core/plat/`~~ **done:** `core/plat/amiga.c` (both lines: `plat_dmainit()` sets `dlm_devload`/`dlm_safe` from AXL1, `dlm_build` from `buildid`, `dlm_plat_match` from `bootinfo`'s boards; `mobo:` keys always match), `core/plat/k30/cputype.c`; host-tested (`tests/core/t_plat.c`) | development load, safe mode, the core tier, and `match=` | S3-02's platform half |
| ~~`tools/mkident.py`~~ **done:** `--asm` (the `AXK1` record, the arena's zero block), `--fill` (the image offsets and the check, the sidecar lines), `--check` | C3-3: the offsets exist only after the link | S3-10 |
| The fingerprint `abi=` (C3-3 §4) | the release gate on the kabi tag; **not needed for the first cut**, it comes with the kit (S3-10) before any module ships | S3-10 |

The kernel hook points the providers need, for the console hook and
`if_attach`, are named in that patch's report. Where a hook needs a
change in the kernel tree, that is part of this brief's acceptance (§4).

## 2. What amix-dlm hands over (a commit after §1)

- `core/upstream/` and `core/series`: the core, applied with `patch -p1`
  in order;
- `core/plat/<line>/`;
- `abi/<line>/ddi.list` and `core.list` (the allowlists) and
  `abi/registry/majors`;
- `loader/common/sha256.c`, `crc32.c` and their headers;
- `tools/ksymgate.py` and `tests/host/axrel.c` (the gate and the loader's
  relocator), and `tools/mkident.py`.

`make core` in amix-dlm is the reference for every step below. It runs
them against the kernels of record, with the providers to come stubbed.

## 3. The kernel build

`KCC` is `m68k-cbm-sysv4-gcc $AMIX_KERNEL_CFLAGS` from the pinned
gcc-cross-amix (`toolchain.pin`). `PIN` is the sidecar's `pin=`
(`gcc-2.7.2.3-8949028`). `KABI` is `k46.1.0` or `k30.1.0`.

1. **Stage the core.** Copy `core/upstream` and apply `core/series`.
2. **Measure the layouts:**
   `sh tools/mkoffs $KCC -I<core>/include > <core>/dlm_offs.h`. It fails
   if any of the 19 layouts is missing.
3. **Generate the major registry:**
   `sh tools/mkreg abi/registry/majors > <core>/dlmreg.c`.
4. **Compile the core** with
   `$KCC -I<core>/include -I<core> -DDLM_KABI=\"$KABI\" -DDLM_PIN=\"$PIN\"`:
   - from C: `dlm_core`, `dlm_ld`, `dlm_sym`, `dlm_slot`, `dlm_str`,
     `dlmconf`, `dlmreg`, `dlm_arena`, `dlm_post`, `dlm_ddi`,
     `dlm_intr`; and from `core/plat`, `amiga.c` and `<line>/line.c` (with
     the loader's flags, like `sha256.c`: they use `loader/common/bootinfo.h`);
   - from assembler: `dlm_cache.s`, `dlm_hooksw.s`, `dlm_spl.s`;
   - **not `dlmksym.s`**: it is the empty block, and step 6 replaces it;
   - `loader/common/sha256.c` and `crc32.c` with the loader's flags
     (`-O2 -m68020 -fno-builtin -fomit-frame-pointer`, C89, not
     `-traditional`);
   - no warning beyond the stock headers' own.
5. **Write the identity record and the arena:**
   `python3 tools/mkident.py --asm <line> $KABI 0x60000 > ident.s`
   (`dlm_ident`, 64 bytes; `dlm_arena`, 0x60000 bytes of zeros, both in
   `.data`). The capacity is 0x60000, from M-MOD1. Both are 4-byte
   aligned, never 16, because `.data` follows `.text` directly in the
   loader's layout. The arena's image offset is therefore 4-aligned only:
   boot2 pads each module's bytes to a 16-byte absolute address (C3-4).
6. **Generate the symbol block:**
   `mkksym -a abi/<line>/ddi.list -a abi/<line>/core.list > ksym.s`, then
   assemble it (4-byte aligned, core patch 0013).
7. **Splice into the base**, in this order:
   1. **the base chain without the static z3660eth, zz9000 and monsw:** a
      rebuild of the chain on the kernel's own tree, not a splice option.
      On k46, z3660eth shares the z3660 pass with the SCSI root driver;
      the port's switch is `Z3660_NET=off`, branch `k46-module`, d0dbfea;
   2. **kinfo**, with its kabi set to `$KABI` (step 8);
   3. **the core's splice**, below;
   4. **last, fpe** (k46) or **`elf2brel`** (k30). Steps 9 and 10 run on
      the kernel before `elf2brel`, and on k46 on fpe's output.

   The core's splice is the adopted core's method (core map §8):
   - `objcopy --weaken-symbol` on `dmainit`, `execsw`, `fmodsw`,
     `scrcon_put` and `aciabintr`;
   - `--add-symbol` `__amix_execsw` and `__amix_fmodsw` as aliases of the
     stock tables, and `__amix_scrcon_put` and `__amix_aciabintr` at the
     stock functions' addresses. Those are `.text` 0x5284 for `scrcon_put`
     in both kernels of record, and for `aciabintr` 0xdf52 on KD060-Z and
     0x10a7e on K030-U; read them with `nm`, never hard-code them.
     `p6int` is `aciabintr`'s only caller. `make core` does this splice;
   - `ld -r` with the core objects, `ident.o` and `ksym.o`; on k46 add
     `libgcc.a` and the port's `devkvmap040.o`.
   - **.rodata:** `dlm.o` carries 0x100 bytes of `.rodata`, and libgcc's
     `__clz_tab` 0x200. The port folds `.rodata` into `.data`
     (`tools/fold-rodata.sh`, as for cdfs and fpe). C3-3's image offsets
     then hold with `.rodata` = 0: an offset is the size of `.text` plus
     the object's offset in `.data`. `mkident.py --fill` reads the final
     layout either way.
   - **No weak symbol survives:** `hooksw` is strong (patch 0013), and
     `plat_dmainit` comes only from `core/plat`. The weak references
     (`cputype` in `dlm_cache.s`, `dlm_ident` in `dlm_arena.c`) are
     defined by the link. `make core` checks that `nm` shows no `W`, `w`
     or `V`, and no undefined symbol but `etext`, `edata` and `end`.
8. **The kernel hooks** (the kernel tree's own change):
   - `dlm_marc_post()` is called once after `vfs_mountroot` returns (in
     `rth1_mountroot`), or from the first `sysinit` entry if U15 says
     loading in process 0 is unsafe;
   - **kinfo's kabi is `$KABI`, not "static":**
     - k30: compile amix-kerntools' `kinfo030.c` with
       `-DKINFO_KABI=\"k30.1.0\"` (it takes the define, `kinfo_kabi[]`);
     - k46: the port's kinfo sets its `kinfo_kabi` the same way;
   - **kinfo's module list (C2-1 offset 536):** on every read, kinfo calls
     `n = dlm_kinfo_list(buf, max)` (core patch 0013). It writes `n`
     entries of 32 bytes (name NUL-padded to 24, load address, size) and
     sets the count at 536, the `length` (540 + 32 × n) and the check;
   - **k30's build id** for the core is kinfo's `kinfo_buildid[]`, stamped
     by the build; `core/plat/k30/line.c` reads it. k46 reads `buildid`.
9. **Fill after the final link:**
   - `mkksym -f <kernel>`: the sizes; it fails on a listed name undefined
     or of the other kind;
   - `python3 tools/mkident.py --fill <kernel>`: the `AXK1` offsets and
     its check; it prints the sidecar lines.
10. **The gate:**
    `python3 tools/ksymgate.py axrel <kernel> abi/<line>/ddi.list abi/<line>/core.list`.
    On k30, run it on the `.etrel` before `elf2brel`, then convert.
11. **Write the sidecar (C2-3 version 5):**
    - `kabi=$KABI`, `family=generic`, `loader-min=2`;
    - `ident=`, `arena=0x… 0x60000`, `ksym=` from step 9;
    - `size=`, `sha256=` (and `bss=` for k30's brel) of the form shipped;
    - `root=`/`rootfs=` for the built-in root controllers and
      filesystems, the same two lines the line's static sidecar carries
      (C3-3 version 2 §3: through stage 3 a module kernel keeps its root
      drivers linked in; from the first root-class module in a
      generation, stage 4, it writes neither).

## 3a. Answers to the dry runs

**The port, KD060-Z (2026-10-26), steps 1–7 and 9–10 clean, the gate 12 of
12, U16 and M-REG1 holding:**
- **(a)** The symbol block, `dlm_ident` and the arena are 4-byte aligned
  (core patch 0013, `mkident.py`); steps 5 and 6.
- **(b)** Fold `.rodata` into `.data` (step 7). C3-3's offsets hold with
  `.rodata` = 0.
- **(c)** `hooksw` is strong and the weak `plat_dmainit` default is gone
  (patch 0013); `core/plat` provides `plat_dmainit`. No rebind is needed.
- **(d)** The order is base chain (static network, RTG and monsw left
  out) → kinfo → the core's splice → fpe last; steps 9–10 on fpe's
  output. Step 7.
- **(e)** M-REG1 now counts a row filled at boot (a store relocated
  against `cdevsw` inside the row). On the static -51, major 51 is filled
  at boot by z3660eth's init, and the record is corrected. The module
  kernel's acceptance asks for 49, 51 and 52 neither used nor filled at
  boot.
- **(f)** Confirmed: the arena's offset is 4-aligned only, and boot2 pads
  each module's bytes to 16 absolute (C3-4 §2).
- **(g)** kinfo's kabi and module list: step 8.

## 4. Acceptance

- **Steps 2–10 pass**, the gate 12 of 12 at both binds, and the port's
  own relocation and page-geometry gates pass with the arena in `.data`.
  That is **U16**; its numbers go in the report.
- **M-REG1 re-run** on the module kernel (amix-dlm
  `tools/measure/m-reg1.py`): `sysentsize` 142 with slots 64–69 `nosys`,
  majors 49/51/52 free (neither used nor filled at boot), `fmodcnt` 11.
- **`nm`** shows no weak symbol, and no undefined symbol but `etext`,
  `edata` and `end`.
- **The image boots under loader version 2** with a generation that has
  an `arena` and an `ident` line and no modules. The console shows
  `dlm: <n> kernel symbols` and `dlm: modules from generation <id>'s
  manifest`, then the system comes up as the static family did; `kinfo`
  reports kabi `k46.1.0` / `k30.1.0` and an empty module list. Loader
  version 2 (S3-15) is amix-dlm's, and the boot row waits for it.
- **The same image under loader version 1, or the stock loader:** the
  core prints that no valid arena exists, and the system boots.
- **The report gives:** the sidecar, the image's sha256, `dlm.o`'s size,
  the gate's output, U16's numbers, and the kernel-tree diff of step 8.
