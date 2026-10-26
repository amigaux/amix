# Stage 3 — audit of the rows reported done (2026-10-26)

The S3-06 finding showed that a row reported done can be only half done:
"pin by default" was parsed and never enforced, until core patch 0016. So
every stage-3 row amix-dlm had reported done was audited the same way.
Each row was split into its clauses. For each clause the audit found where
the core or a tool enforces it, and which harness check, test or
measurement record exercises it.

- **Method:** seven independent read-only auditors, one per pair of rows,
  over the patched core as built (core/series through 0016) and the
  tools at `31e5676`; then each finding listed below as **verified** was
  checked again by hand against the code.
- **Scale:**
  - **done**: every clause enforced;
  - **half**: some clause partial or missing;
  - **not**: the core of the row missing.

  Untested clauses are listed under each row even when it is done.

| Row | Verdict | What decides it |
|---|---|---|
| S3-01 import, host tests, M-CORE1 | done | — |
| S3-02 platform split | done | — |
| S3-03 `.moddata` v2 | **half** | errnos and console lines of C3-1 §4; parameter value forms |
| S3-04 symbol block | done | the plan row's "core tier listed" is wording (C3-2 §4 defers it) |
| S3-05 registries, fmodsw, offsets | **half** | a driver's `drv_cmajor` is not checked against the registry |
| S3-06 range checks, pinning | **half** | patch 13 (range checks) is not implemented; registrations are not tracked |
| S3-07 manifest-only loading | **half** | development load does not lift SHA-256 for members, and lifts a missing manifest |
| S3-08 `marc_post` | done since `cf762a3` | U15 answered; the inittab line is packaging's (S3-31) |
| S3-09 interrupt chains | done | error returns untested; no unwind backstop (S3-06's) |
| S3-10 ABI kit | **half** | no sample driver module |
| S3-11 user side | done | modadmin untested until S3-B6; modtools to be re-pinned |
| S3-15 loader version 2 | done | L14 and L5 untested off the bench |
| S3-16 kbootset with modules | **half** | gate 6 omits an ET_REL kernel's bss |
| S3-40 host measurements | **half** | U16 and M-ABI2 (with the block) not recorded |

## 1. What the kernel needs, for the final cut

These change the module core, so they go into the final cut with 0016 and
0017.

1. **Development load (S3-07, verified).** `lf_gate`
   (`dlm_core.c`, patch 0009) checks the manifest member first, so a
   member keeps its SHA-256 check under development load. C3-4 §3 says
   development load lifts the membership and SHA-256 rule. It then
   honours `dlm_devload` before the missing-manifest check, so
   development load replaces a missing arena directory, which C3-4 §5
   forbids. Fix: no manifest refuses before anything else; under
   development load a member loads from its path with the SHA-256 check
   lifted, and that is printed.
2. **Range checks, plan patch 13 (S3-06, verified).** `okptr`
   (`dlm_str.c`) and the cdev entry check (`dlm_slot.c`) still accept any
   address in `[stext, end)`, upstream's test. That range includes kernel
   data and the arena, where other modules' images will live (stage 4).
   Fix: a code pointer must be in the module's own image or in kernel text
   `[stext, etext)`; a data pointer (`qi_minfo` and the like) in the
   module's own image.
3. **Registrations tracked, plan patch 14's second half (S3-06, S3-09).**
   `intr_attach`, `if_attach` and `cons_hook_set` record no owner, and the
   core relies on each driver's `_unload` (C3-6). A failed `_load` that
   attached, or an `_unload` that forgot, leaves a chain entry, the
   `ifstats` list or the console hook pointing into freed memory. Fix: a
   backstop after a successful `_unload` and after a failed `_load`. Any
   interrupt-chain entry, `ifstats` link or console hook still pointing
   into the module's image is removed and named on the console.
4. **Majors (S3-05, verified).**
   - The driver linkage installs at `drv_cmajor` without checking it
     against the registry or the module's own `majors=`. Neither
     `dlm_creg` nor `marc_post`'s demand registration consults the
     registry. Fix: refuse (`ECONFIG`) a major not registered to the
     module.
   - A row held at run time is `EEXIST`, where C3-1 §4 says `ECONFIG`:
     align the code to the contract.
5. **C3-1 §4 conformance (S3-03, verified for the errnos).**
   - A section type outside the list gives `ERELOC` and an image over
     2 MiB gives `ENOMEM`; both are `ENOLOAD` in C3-1 §4.
   - A version-1 module, a missing `MD2`, an unknown `!` key and a
     malformed key are refused without the console line C3-1 §4 asks for.
   - The core checks parameter declarations only for shape, not their
     default values against C3-1 §3's forms.
   - The core does not check word 0's relocation type and addend (modfix
     does).

   Fix all four in the core.
6. **`path=` (S3-07).** The core takes the manifest's `path=` as given.
   Checking that it lies under `/stand/gen/<booted id>/mod/` costs a
   compare.
7. **First open (S3-07, a contract question).** A refused first open
   returns `ENXIO` to `open()`, with the refusal on the console. C3-1 §4's
   table gives `EPERM` for the load. Proposal: keep `ENXIO` for the open,
   and say in C3-1 §4 that the table is the load call's.

## 2. Tools, outside the kernel

1. **kbootset gate 6 (S3-16, verified).** The memory gate adds `bss=`
   only for a brel kernel. An ET_REL kernel (k46) has its bss in its
   NOBITS sections, and gate 6 leaves it out, while C3-3 §3 counts
   kernel + bss + arena. The fix reads it from the section headers.
2. **make core.**
   - A missing provider (libgcc, `dev_kvmap`, spl, `cputype`) is stubbed
     and only echoed, never counted as a failure.
   - The warnings from compiling core/plat are appended after the
     no-warnings check runs.
   - Nothing guards `core/upstream/` against an in-place edit: a SHA-256
     list of its files, checked by `make test`, would.
   - Three of upstream's own harness checks are not ported:
     `cslots-check.sh`, `check_undef` for dlmtest, and mkmod's
     registration line.
3. **The kit (S3-10).**
   - No sample driver module. The sample is a misc module, and no
     driver- or STREAMS-type module goes through the kit test.
   - modcheck does not cross-check `drv_cmajor` against `majors=` either.
   - Several modcheck refusals have no kit-test case: relocation type,
     the 68060 scan, SHT_REL, image size, version 1, `!` key, missing
     key, `tier=core` without `build=`.
4. **modtools (S3-11).**
   - `libmod.c`'s syscall numbers and ERESTART are not checked against
     `mod.h`.
   - The package pin predates 0016/0017 and must be re-pinned, which is
     already scheduled.
5. **Untested branches worth a case:**
   - interrupt-chain error returns (`ECONFIG`, `ENXIO`, detach `EINVAL`)
     and handler order;
   - the boot-class depend order in `marc_post`;
   - kbootset gate 2's major, family and core-tier refusals, `check`'s
     BAD and missing branches, and the parameter refusals (hex, below
     min, overlong str, malformed modreg line);
   - boot2's L14, L5 and arena/ident-pairing refusals, which need a host
     build of `core.c` or a bench row;
   - `modstat` `MS_LOCKED` for a pinned module.

## 3. Records and wording

- **M-CORE1:** the record still gives 87 checks and a state harness of
  105/105; it is now 119 and 162/162.
- **U16:** the port reported it clean in S3-20, but no record holds the
  numbers.
- **M-ABI2:** measured for the format only. A brel that carries the block
  binds with boot2's relocator and passes its `AXK1` check (the S3-B host
  rehearsal), which is not yet in a record.
- **The plan's wording:**
  - S3-02's "out of `dlm_init`": majors 54–57 and exec 0x150 were in
    upstream's platform file, never imported;
  - S3-04's "core tier listed" (C3-2 §4 defers it to M-FS1);
  - S3-07's "`modpath` adds nothing" (it still serves development
    load);
  - S3-10's "probe module" (it is a probe object).
- **The brief** still names `core/plat/k30/cputype.c`, now `line.c`.
- **Patch 0002's header** still says `plat_dmainit` is weak in
  `dlm_cache.s`; patch 0013 removed that.
- **M-REG1** hard-codes the cdevsw geometry instead of taking it from the
  probe; M-ABI1's DDI table covers six kernels, not ten.

## 4. Order

§1 before the final cut, as one or two core patches with a harness case
each. §2's kbootset gate 6 and the make-core guards with them. §2.3 to
§2.5 and §3 can follow without holding the cut: they change no kernel.
