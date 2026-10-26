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
| Core patch for the DDI providers: `spl0`…`spl7`/`splx` as functions, `dma_alloc`/`dma_free` and on k46 `dma_prepare`/`dma_complete`, `cons_hook_set`/`cons_hook_clear`, `if_attach`/`if_detach`, and on k30 `cputype`. The libgcc names come from linking gcc-cross-amix's `libgcc.a` on k46 | the gate needs every allowlisted name defined; a stub in a real kernel would crash the first module that calls it | S3-04's provider half |
| Core patch for `intr_attach`/`intr_detach` (the INT2 chain walker in `int2_tbl`'s last handler slot, the INT6 chain after CIA-B) | the same name in the allowlist, and z3660eth's interrupt option | S3-09 |
| `core/plat/k46/` and `core/plat/k30/`: `plat_dmainit()` sets `dlm_devload` and `dlm_safe` from the AXL1 flags, `dlm_build` from the kernel's build id, and `dlm_plat_match` from the board list in `bootinfo` | development load, safe mode, the core tier, and `match=` | S3-02's platform half |
| `tools/mkident.py`: writes the `AXK1` record and the arena's zero block as assembler, then fills `AXK1`'s image offsets after the final link and prints the sidecar's `ident=`, `arena=` and `ksym=` | C3-3: the offsets exist only after the link | S3-10 |
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
     `dlmconf`, `dlmreg`, `dlm_arena`, `dlm_post`, the providers' file,
     and `core/plat/<line>`;
   - from assembler: `dlm_cache.s`, `dlm_hooksw.s`;
   - **not `dlmksym.s`**: it is the empty block, and step 6 replaces it;
   - `loader/common/sha256.c` and `crc32.c` with the loader's flags
     (`-O2 -m68020 -fno-builtin -fomit-frame-pointer`, C89, not
     `-traditional`);
   - no warning beyond the stock headers' own.
5. **Write the identity record and the arena:**
   `python3 tools/mkident.py --asm <line> $KABI 0x60000 > ident.s`
   (`dlm_ident`, 64 bytes; `dlm_arena`, 0x60000 bytes of zeros, both in
   `.data`). The capacity is 0x60000, from M-MOD1.
6. **Generate the symbol block:**
   `mkksym -a abi/<line>/ddi.list -a abi/<line>/core.list > ksym.s`, then
   assemble it.
7. **Splice into the base** as the adopted core does (core map §8):
   - `objcopy --weaken-symbol` on `dmainit`, `execsw` and `fmodsw`;
   - `--add-symbol` `__amix_execsw` and `__amix_fmodsw` as aliases of the
     stock tables;
   - `ld -r` with the core objects, `ident.o` and `ksym.o`, and on k46
     `libgcc.a`.
   - Leave the static z3660eth and zz9000 (and monsw) out, so majors 49,
     51 and 52 are free.
8. **The kernel hooks** (the kernel tree's own change):
   - `dlm_marc_post()` is called once after `vfs_mountroot` returns (in
     `rth1_mountroot`), or from the first `sysinit` entry if U15 says
     loading in process 0 is unsafe;
   - `kinfo`'s module list (C2-1 offset 536) is filled from the core's
     loaded modules.
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
    - no `root=`/`rootfs=`.

## 4. Acceptance

- **Steps 2–10 pass**, the gate 12 of 12 at both binds, and the port's
  own relocation and page-geometry gates pass with the arena in `.data`.
  That is **U16**; its numbers go in the report.
- **M-REG1 re-run** on the module kernel (amix-dlm
  `tools/measure/m-reg1.py`): `sysentsize` 142 with slots 64–69 `nosys`,
  majors 49/51/52 empty, `fmodcnt` 11.
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
