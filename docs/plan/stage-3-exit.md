# Stage 3 — the exit ledger

80 §2 lists what stage 3 must prove, and 80 §3 what it must not break:
a module that fails to load leaves the kernel as it was. This ledger
gives, per line, the bytes of record and every row's result. The stage
closes in one commit, when no cell below is empty or pending. A row's
result is PASS or FAIL with its evidence (a Bench run id), or a number
for a measurement. The recipes are `tests/bench/README.md` (stage 3,
S3-43, S3-41) and `docs/plan/stage-3.md`.

## 1. The bytes of record

| What | k46 | k30 |
|---|---|---|
| kernel | KD060-Z module kernel -58, ET_REL, 2 431 362 bytes, `8459eaee…` (amix-040-060-port `k46-module`) | K030-U module kernel, brel, 1 715 944 bytes, `bss=349324`, `3fb1aa50…`; `.etrel` `48b8f1e8…`; `unix.sym` 196 444 bytes, `4012b09b…` (amix-kerntools) |
| its core | `core/series` 0001–0022 (0021 and 0023 are test only) | the same |
| kinfo | version 3 (C2-1) | version 3 |
| kernel package | `kernel-k46-m` / `kern46m`, `k46.1.0.261026-58` | `kernel-k30-m` / `kern30m`, `k30.1.0.261026-01` |
| loader | boot2 version 2, 28 100 bytes, `c7bff405…` (amix-dlm 124b86c) | the same |
| kbootset | -12: amix-dlm 9763024, box binary `cd02b817…` (the k46 B rows ran -12 at cf49440, `4a09a6dd…`, which differs only in the `unix.sym` reader k46 does not use) | -12 at 9763024, `cd02b817…` (the B rows ran it) |
| modadmin | modtools -3, `a206874d…` | the same |
| ABI kit | `dlmkit46` -2, KIT_REV e84878e, PORT_REV 617c64e | `dlmkit30` -2, KIT_REV e84878e |
| z3660eth | `z3660eth-k46` / `zeth46` 1.0.0-1, 18 787 bytes, `8356712a…` | `z3660eth-k30` / `zeth30` 1.0.0-1, `0c5c3580…` |
| z3660rtg | `z3660rtg-k46` / `zrtg46` 1.1.0-1, `21ccf3c5…` | `z3660rtg-k30` / `zrtg30` 1.1.0-1, `4f8c3e33…` |
| monsw | not yet (S3-27, §4) | not yet |
| apkg | 0.3.1, amix-packagemanager 06b77c4, `apkg.amix` `87b0c427…` | the same |
| the S3-43 set | `build/s3-43/handover/k46` (`tests/bench/s3-43/handover.sh`, its SHA256SUMS) | `build/s3-43/handover/k30` |

## 2. The boot rows (S3-20, S3-21, S3-16)

| Row | k46 | k30 |
|---|---|---|
| S3-B1 loader version 2, the module generation | PASS | PASS (N62: kinfo version 3, 0x8 clear, text 0x04000000, 1 471 752 bytes) |
| S3-B2 loader version 1 refuses the generation (L9) | PASS | PASS |
| S3-B3 loader version 1, no arena | PASS | PASS |
| S3-B4 the stock loader | PASS | PASS |
| S3-B5 z3660eth from the generation; the namelist | PASS (zen0 up: ping, telnet, ftp; `/stand/unix` written for generation 2 at 0x08000000) | PASS (N62: `/stand/unix` = `unix.sym`'s 196 444 bytes for generation 3, its own inode; zen0 up after `S99zen`'s two steps: ping 3/3, telnet, ftp; kinfo: z3660eth at 0x40306000, 12 865 bytes) |
| S3-B6 modadmin on the box | PASS | PASS (N62) |

## 3. The emulator rows (S3-43; 80 §2)

| Row | k46 | k30 |
|---|---|---|
| S3-43-1 the generation | | |
| S3-43-2 load, backstop, unload (allowed, pinned), dependency, M-SIG3 at `modload`, dependency load and first open, relocation oracle | | |
| S3-43-3 development load, kabi refusal (family, major, minor, pin), bad-object refusal (`SHT_REL`, type, zero match key, name over 14, version 1, off-list symbol) | | |
| S3-43-4 a dependency outside the generation | (k30 only if the 4 MiB store refuses) | |
| S3-43-5 L14 | | |
| S3-43-6 L5 (as L2) | | |
| S3-43-7 128 MB | | |

## 4. The measurements (S3-41; 90 §3)

| ID | k46 | k30 |
|---|---|---|
| U1 status register, clock and `KM_NOSLEEP` at dmainit and at the hook (U1 kernels, core patch 0023) | | |
| U2 kernel memory for module images at 128 MB | | |
| U4 large kmem requests return | | |
| U15 file loading in process 0 | answered: unsafe (S3-B5, core patch 0017) | answered |

## 5. The plan's rows

| Row | Status |
|---|---|
| S3-01 … S3-11, S3-15, S3-16 (the core, the kit, the user side, the loader, kbootset) | done on the host; audited 2026-10-26 (`stage-3-audit-2026-10-26.md`), every audit item closed by core patches 0016–0022 and the tools' follow-ups |
| S3-20, S3-21 the module kernels | built; the rows of record are §2 |
| S3-22 packages | minted (§1), except monsw |
| S3-25 z3660eth as a module | built; loads from the generation and carries zen0 on both lines (S3-B5) |
| S3-26 z3660rtg as a module | built; composes only with monsw in the generation, or with monsw disabled, which gate 3 refuses for z3660rtg's `depend=` |
| S3-27 monsw as a module | waits for the owner's decision on where monsw lives (Q3-2) |
| S3-30 module packages in apkg | apkg 0.3.1 |
| S3-31 the installer | S3-31's dry run passed on the host; on the box with the kernels of record, pending. Part 3: the CD-booted, disk-rooted cell (`stage-3-cd-boot.md` §5), pending the CD-capable A4091 ROM |
| S3-40 host measurements | done (`docs/measurements/2026-10-26-m-reg1-m-abi1.md`, `2026-10-26-u16-m-abi2.md`) |
| S3-41 bench measurements | §4 |
| S3-43 emulator rows | §3 |
| S3-44 M-INT1, bench half | pending (z3660net) |
| S3-45 exit row: network and graphics only from modules, installed by the installer, upgraded with apkg, rollback | pending: needs S3-27 (the graphics stack's monsw) |
| S3-46 metal | waits for the owner's bench time |

## 6. Open, outside the Bench's sweep

- **monsw (S3-27):** the module waits for the owner's decision on its
  repository (Q3-2). z3660rtg composes into a generation only after it,
  because gate 3 refuses `depend=monsw` without a monsw member. So
  S3-45's graphics half waits too.
- **Metal (S3-46):** the stage-3 metal rows (z3660eth and z3660rtg as
  modules on both boxes, interrupt attachment on metal) wait for the
  owner's bench time.
- **The installer CD (S3-31 part 3, second half):** the compressed miniroot
  as a RAM-disk root waits for stage 4's `ramdisk` module (boot2 and
  `amix-cdboot` refuse a ramdisk member until then; 10 §5.4's placement is
  unimplemented; M-RD1 unmeasured). The CD boot path itself is proven in
  stage 3 by the disk-rooted cell.
- **Throughput (80 §2, OQ-80.3):** "no regression against the static
  drivers' figures" needs the static baselines of record named before
  S3-45.
