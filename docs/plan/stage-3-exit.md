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
| its core | `core/series` 0001–0022 (0021 and 0023 are test only), `dlm_maximage` 2 MiB; 0024–0026 are user side, 0027 rides the stage-4 cut (§6) | the same |
| kinfo | version 3 (C2-1) | version 3 |
| kernel package | `kernel-k46-m` / `kern46m`, `k46.1.0.261026-58` | `kernel-k30-m` / `kern30m`, `k30.1.0.261026-01` |
| loader | boot2 version 2, 28 100 bytes, `c7bff405…` (amix-dlm 124b86c) | the same |
| kbootset | -12: amix-dlm 9763024, box binary `cd02b817…` (the k46 B rows ran -12 at cf49440, `4a09a6dd…`, which differs only in the `unix.sym` reader k46 does not use) | -12 at 9763024, `cd02b817…` (the B rows ran it) |
| modadmin | modtools -3, `a206874d…` | the same |
| ABI kit | `dlmkit46` -2, KIT_REV e84878e, PORT_REV 617c64e | `dlmkit30` -2, KIT_REV e84878e |
| z3660eth | `z3660eth-k46` / `zeth46` 1.0.0-1, 18 787 bytes, `8356712a…` | `z3660eth-k30` / `zeth30` 1.0.0-1, `0c5c3580…` |
| z3660rtg | `z3660rtg-k46` / `zrtg46` 1.1.0-1, `21ccf3c5…` | `z3660rtg-k30` / `zrtg30` 1.1.0-1, `4f8c3e33…` |
| monsw | `monsw46` 1.0.0-1, amix-modules c0386d9, `2a01aa1f…` (the package) | `monsw30` 1.0.0-1, `aed6eb1a…` |
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
| S3-43-1 the generation | PASS (N65) | PASS (N66) |
| S3-43-2 load, backstop, unload (allowed, pinned), dependency, M-SIG3 at `modload`, dependency load and first open, relocation oracle | PASS (N65; run-time lines through `modadmin -K` and `-L`; oracle "t43rel at 0x401a4c00: 83 words, 332 bytes of 332, identical to the host loader") | PASS (N66; run-time lines through `-L`; oracle at 0x402fcc00, identical) |
| S3-43-3 development load, kabi refusal (family, major, minor, pin), bad-object refusal (`SHT_REL`, type, zero match key, name over 14, version 1, off-list symbol) | PASS (N65): every refusal's errno as C3-1 §4 | PASS (N66) |
| S3-43-4 a dependency outside the generation | not run, as the row allows: the box's kbootset -12 did not deflate (gate 5: 2 433 024 bytes needed, 972 800 free); kbootset -14 deflates on the box | PASS (N66): "dlm: monsw is not a member of the booted generation" |
| S3-43-5 L14 | PASS (N65): L14 to generation 3 after the rollback, then L8 | PASS (N66): L14 to generation 4, then L8 |
| S3-43-6 L5 (as L2) | PASS (N67): "the arena needs 337 bytes, it has 64", fallback to generation 1 | PASS (N68): 367 bytes, fallback to generation 1 |
| S3-43-7 128 MB | PASS (N69, 128 MB at 0x08000000: load, dependency, oracle at 0x4035b400 identical) | at 64 MB, the line's maximum (N66). 128 MB in one bank (N70) failed: K030-U runs in 64 MiB at most, so boot2 caps k30 there (S3-43-9) |
| S3-43-8 Zorro III RAM beside and alone (boot2 e36c1c55) | PASS (N71 beside: kernel at 0x08000000; N73 alone: "no fast memory below 0x40000000 to run the kernel in", L4) | PASS (N72 beside: kernel at 0x04000000; N74 alone: the same refusal) |
| S3-43-9 the k30 64 MiB cap (boot2 6147ab3b) | — (k30 only) | PASS (N76: 128 MB bank, "kernel bound at 08000000", 67 108 832 bytes of fast memory) |

## 4. The measurements (S3-41; 90 §3)

| ID | k46 | k30 |
|---|---|---|
| U1 status register, clock and `KM_NOSLEEP` at dmainit and at the hook (U1 kernels, core patch 0023) | done (N77): sr 0x2704 / 0x2700 (priority 7), the clock still at both, `KM_NOSLEEP` up to 2 MiB gives memory at 128 MB | done (N78): sr 0x2704 at both, the clock still, `KM_NOSLEEP` 1 MiB yes, 2 MiB fails at 64 MB (`docs/measurements/2026-10-26-u1.md`) |
| U2 kernel memory a module gets in process context | done (N81, 128 MB): 5 × 64 KiB = 320 KiB with `KM_NOSLEEP`, all given back (first run N79 void) | done (N82, 64 MB): 10 × 64 KiB = 640 KiB, all given back (`docs/measurements/2026-10-26-u2.md`; first run N80 void) |
| U4 large kmem requests return | done (N79): `KM_NOSLEEP` 256 KiB yes, 512 KiB fails; `KM_SLEEP` 512 KiB **never returns** | done (N80): `KM_NOSLEEP` 512 KiB yes, 1 MiB fails; `KM_SLEEP` 1 MiB **never returns** (`docs/measurements/2026-10-26-u4.md`) |
| U15 file loading in process 0 | answered: unsafe (S3-B5, core patch 0017) | answered |

## 5. The plan's rows

| Row | Status |
|---|---|
| S3-01 … S3-11, S3-15, S3-16 (the core, the kit, the user side, the loader, kbootset) | done on the host; audited 2026-10-26 (`stage-3-audit-2026-10-26.md`), every audit item closed by core patches 0016–0022 and the tools' follow-ups |
| S3-20, S3-21 the module kernels | built; the rows of record are §2 |
| S3-22 packages | minted (§1), except monsw |
| S3-25 z3660eth as a module | built; loads from the generation and carries zen0 on both lines (S3-B5) |
| S3-26 z3660rtg as a module | built; composes with monsw in the generation: gate 3 passes its `depend=monsw` |
| S3-27 monsw as a module | done: Q3-2 settled (amix-modules); the module at amix-modules c0386d9, packaged `monsw30`/`monsw46` 1.0.0-1 (§1), on the s3dry2 media and the media of record; z3660rtg passes gate 3 with it |
| S3-30 module packages in apkg | apkg 0.3.1 |
| S3-31 the installer | the dry run passed on the host. The box run: **done** — amix-installng's media of record (ISOs k30 `98a88d43…`, k46 `5ed3bbea…`, SHA256SUMS `fff4fd0d…`), four cells PASS on the -5 set; first boots of the record disks on both lines: `S01kbnamelist` writes `/stand/unix` (bound at 0x04000000 / 0x08000000), netstat works, k46 "module z3660eth (boot): loaded" (k30 error 6, no Z3660 on that rig, as it should), syslogd up every boot. Part 3, the CD-booted, disk-rooted cell (`stage-3-cd-boot.md` §5): k30 **PASS** (N83c: `amix-cdboot 2: 68030, generations from SYS:BOOT/K30`, the kernel bound at 0x04000000, `RTH1: root c6d0s1 from the root record`, multi-user from the disk, `kbootset: booted from a read-only medium (generation 1 of a CD): nothing to mark`, the namelist for the medium's kernel, the box's store byte-identical before and after; the disk at priority 1, §5). k46: pending (disc `1a5967b4…` mastered with kbootset 330f585) |
| S3-40 host measurements | done (`docs/measurements/2026-10-26-m-reg1-m-abi1.md`, `2026-10-26-u16-m-abi2.md`) |
| S3-41 bench measurements | §4 |
| S3-43 emulator rows | §3 |
| S3-44 M-INT1, bench half | rows S3-44-1 to -3 (`tests/bench/README.md` S3-44): the chains on the kernels of record (probe `t44intr`), a full chain and z3660eth's polled fallback (`t44fill`), z3660eth 1.0.0-2 with `intr=6` and its self-test. No z3660net build is owed. The Bench station, pending |
| S3-45 exit row: network and graphics only from modules, installed by the installer, upgraded with apkg, rollback | runnable: amix-installng builds the RTG-kit profile medium (zeth, monsw, zrtg) after the CD discs; the Bench station runs the cell (zen0 with telnet and ftp, X on the module RTG, the monitor switch, `apkg upgrade` of a module package, rollback); pending |
| S3-46 metal | the Bench station; the box that holds the Z3660 card is handed over through the orchestrator; pending. The k30 row (z3660eth on the Z3660 in 68030 mode): no K030 family of record carries z3660scsi, so its instrument is a **bench variant**, the K030-U `--dlm` cut plus a static z3660scsi, a measurement kernel never packaged. Its piscsi root is proven on the emulator in N24's shape first. The 1.1 kernel of record for an 030 on the Z3660 is stage 4's: the K030 floor with z3660scsi as a root-class module in the same slot (D-3 §4) |

## 6. Open, outside the Bench's sweep

- **The installer CD (S3-31 part 3, second half):** the compressed miniroot
  as a RAM-disk root waits for stage 4's `ramdisk` module (boot2 and
  `amix-cdboot` refuse a ramdisk member until then; 10 §5.4's placement is
  unimplemented; M-RD1 unmeasured). The CD boot path itself is proven in
  stage 3 by the disk-rooted cell.
- **Core patch 0027 (C3-1 v4, `dlm_maximage` 256 KiB) rides the stage-4
  kernel cut, not a stage-3 re-cut** (decided 2026-10-26). The kernels of
  record keep 2 MiB. The kit's checker refuses an image over 256 KiB or a
  file of 256 KiB for every module meanwhile, and no planned module is
  near the limit (cdfs, the largest, is a 69 KB image in a 97.6 KB file).
  A re-cut now would force a third remaster of the media of record.
- **Throughput (80 §2, OQ-80.3):** "no regression against the static
  drivers' figures" needs the static baselines of record named before
  S3-45.
