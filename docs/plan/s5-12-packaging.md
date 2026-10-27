# S5-12 — the kernel packages carry ufs and s5: the recipe for amix-packages

- **Status:** recipe, 2026-10-27 (amix-dlm), for the orchestrator to
  dispatch to amix-packages.
- **Implements:** plan row S5-12; contract C2-3 version 8 §1 (the kernel
  package carries a cut's filesystem modules; its version sorts above
  the line's kernel of record), C4-6 §4 (core tier, built per cut),
  C3-5 §1.2 (the modules' paths and modes).

## 1. The inputs of record

All paths are under `Amix/tmp/`. The modules were rebuilt on the host
with amix-dlm's kits at ebcdb80, which is after 445c12e, and came out
byte for byte the same as the stations' objects below. So amix-packages
takes these objects as they are; §3 R2 rebuilds them as a check.

| | k30 (S5-10, kerntools afde1fd) | k46 (S5-11, the port abc6080) |
|---|---|---|
| build id | `68030-261027-18` | `68060-261027-66` |
| tree | `2026-10-27-s5-10/cut-68030-261027-18/usr/sys/` | `2026-10-27-s5-11/out/c/` |
| kernel | `unix.brel` `ed2ba2ec285fd14e492906fb7be2409e10fb85fe8f4615b7584245997e0788ee` (1 534 496 bytes) | `unix` (ET_REL) `92c68025bfc38f059c9ee646efbbcd0cfbc65cc6bfa951a96819b769965c12d3` (2 411 588 bytes) |
| symbols | `unix.sym` `77b21335adfab9e3d34bbcb6e20a90f3e253498632abd469eaf10bcf6e58b22d` | none (ET_REL) |
| sidecar | `kabi` `48778ee00d7478b0a2dc14ffd39e015e98fc7a3256bfd3dcb39d595b557173cd` | `kabi` `aaffc3f546eb06d9ed8dd665c0b2078ab12a22103d4539b97ea95236e5719f34` |
| ufs | `mod.d/ufs` (from the cut's `SHA256SUMS`) `af4886200ebf862f501ebb506ed9bb5cce71e68ecf270c20eefa8e5e0725e92b`, 56 636 bytes of image | `out/c/ufs.mod` `202f33bab705dca4d0d099793b5377cb8cbe816925b7a0b054262fcc5547d876`, 56 636 bytes, from `ufsmod/ufs-exp.k46` `84316ffc…` |
| s5 | `mod.d/s5` `698bb42b76512f84eb224f53040d3cb4672c0cbf7ab6b5276724839400efb6a3`, 39 964 bytes | none (S5-37) |
| hash list | `2026-10-27-s5-10/SHA256SUMS-68030-261027-18` | `2026-10-27-s5-11/SHA256SUMS` |

Both sidecars carry `kabi=k30.1.2` / `k46.1.2`,
`abi=2ab48658596e166a…`, `sdcards=4` and the static `root=`, and no
`rootfs=`. That is right for a cut (C3-3 §3, version 6): a generation's
root filesystem is the promoted module.

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
  - k30: `k30.1.2.261027-18`, above the `-17` of record.
  - k46: not `k46.1.2.261027-66`. See §4.
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
- k30: `make -C cut-68030-261027-18/carve/{ufs,s5} KIT=<amix-dlm>/build/kit/k30`;
- k46: `make -C 2026-10-27-s5-11/ufsmod/ufs KIT=<amix-dlm>/build/kit/k46`;
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

## 4. Open: the k46 version (C2-3 v8 §1.1)

The k46 cut's build id `68060-261027-66` gives `k46.1.2.261027-66`. That
sorts below the k46 kernel of record, `k46.1.2.261027-82`. On a box with
-82 installed, `apkg upgrade` would call -66 up to date, so it can't be
minted as is. The rule now says: rebuild with a new stamp, never bend
the version.

The S5-11 note says a rebuild changes the build id, so the module must
be rewrapped. The steps, at the port:
1. Rebuild the cut. The new stamp must sort above -82.
2. Rewrap ufs: `carve.py wrap --fs ufs --obj ufsmod/ufs-exp.k46 --filesys … --build <new id>`.
3. Rebuild it with the kit. Only `.moddata` `build=` changes.

Then this recipe runs with the new pins.

If S5-15's kernel half (the RTH1 window match, the port's kinfo) needs
another k46 cut anyway, one rebuild covers both. Whether -66 and -18
already carry S5-15's kernel items is for the stations to say.

k30 is not affected: -18 sorts above the -17 of record, so the k30
package can be minted from §1 as it stands.

## 5. Not in S5-12

- s5 on k46 (S5-37).
- The static families' removal from the catalog (S5-34).
- The bench rows (S5-13).
- The measurement of the carve's sizes (S5-14, amix-dlm, from these two
  cuts).
