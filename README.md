# amix-installng

Builder for custom **Amix 2.1** boot/install media — boot/root floppies, a
bootable SCSI install-source `.hdf`, an install CD/ISO, and the host-side
install pipeline behind them — with the A4091 and Z3660 accelerator drivers
baked in, so freshly built media boots straight into a working Amix 2.1
without a separate vendor patch-floppy step.

Amix is Commodore's 1991 SVR4/68k Unix port for the Amiga. This repository
does not carry the distribution itself (see **Licensing**, below) — it
operates on Amix media and turns it into install media these accelerator
cards can boot from out of the box. It is the source of the **amigaux 1.0**
install media published on amigaux.org.

## Charter

- **Build fresh Amix 2.1 install media supporting the A4091 and A4000 out of
  the box.** Strategy: bake 2.1c plus the accelerator driver into the media
  *at install time*, rather than shipping a patch floppy applied afterwards —
  a patch floppy is a boot-breaker risk this project deliberately avoids.
- **Scope is universal**: A3000 (stock), A3000+A4091, an A4000/030 with an
  A4091 or Gayle IDE, and an A4000 with a Z3660. The classic boot floppy serves
  the 030 machines (WD, A2091/A3091, A4091, Gayle IDE); a Z3660 installs from
  its own self-booting `.hdf` media (the K1 card), not from the floppy.
  A3000+A4091 is the canonical bench profile; tape sourcing works but is
  timeout-prone, so the CD/ISO and the install-source `.hdf` are the paths.
- **Validation is emulation-first**, on a repo-pinned Amiberry build, before
  anything touches real hardware. A growing 68040/68060 metal-port line
  (`profiles/metal-a4000-z3660-040.profile`) carries the same profiles onto
  real A4000+Z3660 hardware once a step is bench-proven.

## What's here

| piece | what it produces | entry point |
|---|---|---|
| Classic boot floppy | a bootable `boot.adf` framing the K030-U-FD install kernel (a3091/a2091, a4091, Gayle IDE, cdfs; **no** z3660scsi) | `tools/build-universal-bootfloppy.sh` — `docs/universal-bootfloppy.md` |
| Install-source `.hdf` | a bootable SCSI disk that replaces the classic boot+root floppy pair — the tape-free Z3660 install path | `tools/build-source-hdf.sh`, `tools/build-raw-source.sh` |
| Install miniroot | the tiny root filesystem the install kernel mounts to author the target disk (s5 for the 030 line, UFS for 040/060) | `tools/build-miniroot.sh` — `docs/miniroot.md` |
| Install CD / ISO | the self-contained `/install/` tree: the driver, the first-boot payload, and the package catalog | `tools/build-install-iso.sh`, `tools/build-iso.sh` — `docs/install-iso.md` |
| Installer driver | replaces Amix's stock interactive installer with a non-interactive, **profile**-driven transplant | `src/installer/install.sh` + `profiles/*.profile` — `docs/installer.md`, `profiles/README.md` |
| First-boot payload | bakes machine identity (nodename, network, timezone, keymap) into the freshly installed target on its first multiuser boot | `payload/firstboot/` |
| Regression matrix | one command, one unattended from-scratch install on the bench, gated against attested tree digests | `tools/install-matrix.sh` |

Every target rig — which kernel, which SCSI id, which CD address, which
first-boot answers — is a **profile** (`profiles/*.profile`), not a
hardcoded fact in the driver; see `profiles/README.md` for the full key
reference.

## Workspace layout

The builders expect this repository beside its sibling repositories, in one
directory (the "workspace"), and find them by relative path (`../<name>`):

| Directory | Used for | Status |
|---|---|---|
| `amix-installng/` | this repository | public |
| `amix-kerntools/` | the install kernels and boot loaders; the host-to-box tools (`amixrun.py`, `amixsync.py`); `tools/run-checks.sh` needs it | public |
| `amix-a4091/`, `amix-z3660scsi/`, `amix-z3660net/` | the A4091 and Z3660 SCSI drivers, the Z3660 network driver (`src/zenmac`) | public |
| `grimoire-amix/` | the boot-floppy framing tool; the host network scripts the emulator bench uses | public |
| `amiberry/` | the Amiberry build the emulator matrix runs (`../amiberry/build/amiberry`) | public (fork) |
| `amix-cdfs/` | the CD filesystem in the install kernels and on the media | not public yet |
| `amix-packagemanager/` | the package engine builds (APKGENG, APKG) and the package staging the media carry | not public yet |
| `amix-z3660rtg/` | the RTG X11 kit on the K1 desktop media | not public yet |
| `amix-040-060-port/` | `monsw.h` for the K1 RTG builds (`MONSW`), the RTH1 root-record spec | private |
| `amix-images/` | the golden donor disks (boot chains, the emulated build box) | not published |
| `cards/`, `roms/` | built K1 card directories (`card-audit.py` input); the ROM registry the card pins name by id | local |

Not in any repository: the Amix 2.1 distribution media (user-supplied), your
own Kickstart and A4091 ROM images, and the Amiberry driver scripts that
`install-matrix.sh` launches the emulator with (`AMIBERRY_AMIX_SKILL`).

**The bench network.** Profiles, emulator configs and the bench tools name
the bench network only with documentation values (RFC 5737 addresses, the
domain `example.net`) and name paths with `@WS@` / `@AMIBERRY@`. A bench
keeps its real values in one gitignored file, `bench/local.env` (copy
`bench/local.env.example`); `tools/lib/lab-env.sh` maps them wherever a
profile or a config is staged.

## Checks

```sh
tools/run-checks.sh           # host-side self-test suite -- no box, no media
tools/run-checks.sh --quick   # skip the checks that master synthetic fixtures
python3 tools/installer-selftest.py
bash tools/install-matrix.sh --selftest
```

`run-checks.sh` is fail-closed: a missing sibling repository, an unreadable
fixture, or a check that silently did not run is a **failure**, never a skip.
It needs `../amix-kerntools`. Two self-tests (`fsdupcheck.py`,
`sec1check.py`) also read optional local disk images and skip them when
absent. `installer-selftest.py` and `install-matrix.sh --selftest` run on
this repository alone.

## Building the 1.0 media

Every step needs a user-supplied Amix 2.1 distribution and the kernels from
`amix-kerntools`. The commands are the ones the 1.0 cut ran; the bytes they
produced are listed in `docs/releases/1.0.md`.

- **Install CDs** (needs `amix-packagemanager` and `amix-cdfs`, not public
  yet; the 060 CDs and the K1 media also `amix-z3660rtg`, not public yet,
  and `amix-040-060-port`, private):

  ```sh
  tools/build-install-iso.sh --profile public-a3000-a4091-r6 --set full \
      --out work/iso/amix21-install-public-full-r7-<date>.iso
  tools/build-install-iso.sh --profile public-a4000-z3660-060-a4092cd-r6 --set full \
      --out work/iso/amix21-install-public060-sd-full-r7-<date>.iso
  tools/build-install-iso.sh --profile public-a4000-z3660-060-a4092cd2-r6 --set full \
      --out work/iso/amix21-install-public060-a4092root-full-r7-<date>.iso
  ```

  `STAGING` and `STATIC` point at the package engine builds (default:
  `amix-packagemanager`'s build tree).
- **Classic boot floppy:** `KERNEL_SRC=<K030-U-FD kernel> BOOTFLOPPY_OUT=<adf>
  tools/build-universal-bootfloppy.sh` (frames the kernel with
  `grimoire-amix`'s tool). **Root floppy:** `tools/build-miniroot.sh`, which
  needs the emulated build box from `amix-images` (not published).
- **060 CD installer disk and A4092 boot disk:** `tools/build-boot-hdf.sh
  --profile <profile> --out <hdf>`.
- **K1 card disks:** `tools/build-raw-source.sh --author` / `--populate`
  (needs the emulated build box and the donor disks from `amix-images`, not
  published). The card itself is assembled from those disks and the Z3660
  firmware outside this repository; `tools/card-audit.py <card> <pins>`
  checks a built card against its pin file in `profiles/cards/`.
- **Emulator acceptance:** `tools/install-matrix.sh <cell>` (`--list` for
  the cells); needs Amiberry, the driver scripts and a bench network
  (`bench/local.env`).

## Validation

Every change is proven on the bench before it is trusted: a repo-pinned
Amiberry build boots the media under construction and drives it over
telnet/FTP, with `tools/install-matrix.sh` running full unattended installs
and gating the result against attested, byte-exact installed-tree digests.
The 68040/68060 metal-port line (the Blizzard FP fix for FPU-less UFS among its
recent milestones — see `docs/blizzard-fp.md`) takes the same profiles onto
real A4000+Z3660 hardware once a step is bench-proven. The operator runbook
for the maintainer's own machines is kept locally and is not published.

## Licensing

The original tooling, documentation and configuration in this repository are
MIT-licensed (`LICENSE`); `NOTICE` has the trademark wording and the
third-party material. Everything below concerns the Amix media it operates on.

On 2026-09-23 Amiga Corporation approved distributing the Commodore Amiga
binaries this project builds on, which the project reads as lifting the
restriction on releasing Amiga UNIX to the public. The 1.0 install media are
published as release files on amigaux.org, never from this repository.

The Amix distribution itself — floppy/ADF/tape/CD images, ROMs — is
Commodore material and is **never committed here**: `.gitignore` excludes
every binary media format and the directories that hold them (`hdf/`,
`floppies/`, `tape/`, `roms/`, and build-time staging under `payload/21c/`,
`install-tree/`). Two gates back that at build time: `tools/build-iso.sh`
refuses to write an image into a git-tracked path and stamps every disc
`release-cleared 2026-09-23` with a `publication:` line, and
`tools/licensing-gate.sh` re-proves those stamps against any built `.iso`.
The builder operates on **user-supplied** Amix 2.1 media.

## More

- `CHANGELOG.md` — what each public release contains.
- `docs/releases/1.0.md` — the 1.0 release record: every shipped hash and the
  evidence it was accepted on; `docs/release-notes-amigaux-1.0.md` — what
  users see.
- `docs/installer.md` — the installer driver, step by step, plus the current
  canonical installed-tree digests.
- `docs/miniroot.md`, `docs/install-iso.md`, `docs/universal-bootfloppy.md`
  — the three media builders, in detail.
- `docs/blizzard-fp.md` — the FP-elimination patch that makes UFS installs
  work on FPU-less 68060 hardware.
- `docs/ufs-target-scoping.md` — s5 vs. UFS as the target root filesystem.
- `docs/address-by-card.md` — one image for several Z3660 machines: `zen0`'s
  address, nodename and `hosts` row picked from the card's MAC at boot
  (`/etc/inet/zen.conf`); the pattern, the firmware MAC-parse bug, the fallback.
- `profiles/README.md` — the per-rig profile format and every key it
  accepts.

---

Active project, under development since 2026-06-22; the public history starts
at 1.0. See `CONTRIBUTING.md` before sending a change.
