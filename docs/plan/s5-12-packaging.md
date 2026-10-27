# S5-12 — the kernel packages carry ufs and s5: the recipe for amix-packages

- **Status:** recipe, 2026-10-27 (amix-dlm), for the orchestrator to
  dispatch to amix-packages.
- **Implements:** plan row S5-12; contract C2-3 version 8 §1 (the kernel
  package carries a cut's filesystem modules; its version sorts above
  the line's kernel of record), C4-6 §4 (core tier, built per cut),
  C3-5 §1.2 (the modules' paths and modes).

## 1. The inputs of record

These are the cuts of S5-15 and S5-46, which replace the first pins
(-18, -66). All paths are under `Amix/tmp/`. amix-dlm rebuilt the
modules on the host with its kits at 3f12419 and later, and they came
out byte for byte the same as the stations' objects below, with no
`rootvp` warning. So amix-packages takes these objects as they are; §3
R2 rebuilds them as a check.

| | k30 (amix-kerntools 224b285, rebuilt byte-identical) | k46 (the port 7459d06 and S5-46) |
|---|---|---|
| build id | `68030-261027-20` | `68060-261027-91` |
| tree | `2026-10-27-s5-10/cut-68030-261027-20/usr/sys/` | `2026-10-27-s5-46-k46/out/c/` |
| kernel | `unix.brel` `d2e9c687a584613a427c7b169c370209a8f5db0097516c723e64776d7e61c7c6` (1 534 956 bytes) | `unix` (ET_REL) `e26c2df10b3d1cc56deadeece918c3f0cf23adaa2d50af2c6be1e77319b8515d` (2 412 229 bytes) |
| symbols | `unix.sym` `035dbda45e2b1bf2edb6989520cf06e0e07c446730fcf57d3b4cbe49d7faba36` | none (ET_REL) |
| sidecar | `kabi` `499514df1fabf470271bde9bb927d9fa6da83396b0073fea6842d47fa6d9333e` | `kabi` `9295bae59275d8bcc373a3ef4c331abec645b4b52627772dd699f4cbcc41100d` |
| ufs | `mod.d/ufs` `419c145c102dc1a7b094579dc77b88a2fbd66ed8a616b701e87ea59af4413c8c`, 78 580 bytes (56 636 allocated) | `out/c/ufs.mod` `b743007ead3dbe00e8ebbd8e61bbfe035b2b6c9911c2a638658b0a73173ae186`, 78 580 bytes (56 636 allocated), from `ufsmod/ufs-exp.k46` `84316ffc…` |
| s5 | `mod.d/s5` `a76a4a4fd40082c5b1e79deb33135e4bc9ac3d4b8ce0369e41074ccdf80c20f7`, 58 310 bytes (39 964 by modcheck) | none (S5-37) |
| hash list | `2026-10-27-s5-10/SHA256SUMS-68030-261027-20` | `2026-10-27-s5-46-k46/SHA256SUMS` |

Both sidecars carry:
- `kabi=k30.1.2` / `k46.1.2`;
- `abi=2ab48658596e166a…`;
- `sdcards=4`;
- `rth1=2` (C2-3 v9, C4-1 §5.2);
- the static `root=`;
- no `rootfs=`.

That is right for a cut (C3-3 §3, version 6): a generation's root
filesystem is the promoted module. Each module's `.moddata` carries its
cut's `build=`.

## 2. What changes in the two kernel recipes

`recipes/kernel-k30-m` and `recipes/kernel-k46-m`, per C2-3 v8 §1:

- **prototype** gains, after the `/stand` lines:
  ```
  d none /etc 0755 root root
  d none /etc/conf 0755 root sys
  d none /etc/conf/mod.d 0755 root sys
  d none /etc/conf/modreg.d 0755 root sys
  f none /etc/conf/mod.d/ufs 0644 root sys
  f none /etc/conf/modreg.d/ufs 0644 root sys
  ```
  and on k30 also `f none /etc/conf/mod.d/s5 0644 root sys` and
  `f none /etc/conf/modreg.d/s5 0644 root sys`. They stay pure files,
  so the kernel-space rule holds: no scripts, no device nodes.
- **modreg.d files:** comments only, as a module package's with no
  parameters of its own: the format, and `modreg.local.d` for the
  administrator. The `probe` parameter keeps its default of 0.
- **pin.sh:** the kernel pins of §1, plus the module objects and their
  SHA-256. The build check refuses a module whose `.moddata` `build=` is
  not the sidecar's `build=`.
- **Versions** (C2-3 §1.1):
  - k30: `k30.1.2.261027-20`, above the `-17` of record.
  - k46: `k46.1.2.261027-91`, above the `-82` of record (§4).
- **pkginfo DESC / APKG_DESC:** say the cut has no built-in ufs or s5,
  and that the package carries the ufs module (and on k30 the s5 module)
  as core-tier modules built with the cut. The sidecar has no `rootfs=`.
  Drop the old text that claims `rootfs=`.
- **Catalog:** the row stays `role=kernel` with `line=`, `kabi=`, `pin=`.
  No module rows are added for ufs or s5.

## 3. The checks (the acceptance of S5-12)

**R1. Pins.** Every input's SHA-256 is as §1 gives it. Each module's
`.moddata` says:
- `tier=core`;
- `class=boot`;
- `fs=ufs` / `fs=s5`;
- `build=` the cut's;
- the line's kabi.

**R2. Rebuild check, both lines.** Rebuild from the carve directories:
- k30: `make -C 2026-10-27-s5-10/cut-68030-261027-20/carve/{ufs,s5} KIT=<amix-dlm>/build/kit/k30`;
- k46: `make -C 2026-10-27-s5-46-k46/ufsmod/ufs KIT=<amix-dlm>/build/kit/k46`;
- with a kit built from amix-dlm 445c12e or later.

Then:
- `modcheck: ok` for each;
- `build/<line>/mod.d/<fs>` equals the §1 object byte for byte;
- no warning names `rootvp`. COMMON warnings that name the module's own
  symbols (`ihead`, `dquot`, …) are expected.

**R3. kbootset on a staged root, both lines.** On a root with the kernel
package and the line's root-class packages installed, run
`kbootset -R <root> build --line NN --rootfs ufs …`. It composes:
- `module ufs root … tier=core build=<cut>`, with `safe=1`, because ufs
  is promoted as the root filesystem (C4-4 §1.3);
- on k30, also s5 as a boot record;
- gate 3 closed by the promoted module, with no `rootfs=` in the
  sidecar.

On k30, `--rootfs s5` promotes s5 instead.

On k46, `--rootfs s5` is refused at gate 3: no s5 module, and none built
in. That is right for k46 (S5-37).

**R4. One owner.** `/etc/conf/mod.d/ufs` and `s5` are named by the kernel
package's install record only. Two records for one path fail at gate 1
("named by two apkg records").

**R5. The upgrade path, on the host.** Install over a root that holds
the line's kernel of record:
- k30 `-17`, k46 `-82`;
- `apkg upgrade` replaces the kernel, its sidecar and the module files
  in one transaction;
- the trigger's `kbootset build` and `commit` give a generation with the
  new ufs (and s5).

## 4. The k46 version (C2-3 v8 §1.1): settled

The first k46 pin, `68060-261027-66`, sorted below the k46 kernel of
record, `-82`, so it could not be minted. The re-stamp was folded into
S5-15 and S5-46. Their cut `68060-261027-91` sorts above -82, and its ufs
was rewrapped with `--build 68060-261027-91`. The k30 cut `-20` sorts
above -17.

## 5. Not in S5-12

- s5 on k46 (S5-37).
- The static families' removal from the catalog (S5-34).
- The bench rows (S5-13).
- The measurement of the carve's sizes (S5-14, amix-dlm): measured at
  -18 and -66, and re-checked at these cuts
  (`docs/measurements/2026-10-27-m-fs1-m-fl1.md` §4).
