# The Installer-NG driver

The driver is what turns a booted install miniroot + an install CD into a
running Amix system on the target disk. It replaces the stock interactive Amix
install script with a spec-driven, non-interactive transplant. **W5.3** built
the driver, the first-boot payload, the profile specs, and the ISO re-master
that populates `/install/`; **W5.4** was the first end-to-end on-box run. Every
wave since is a further section below.

> **This document is wave-chronological.** Every `W…` section records what was true
> **when that wave landed** and is deliberately left standing. The five sections
> immediately below are *current state* and **win over any figure or s5 statement
> quoted inside a wave section**.

## The target filesystem — current (P-35, 2026-10-30)

**ufs is the only target filesystem**, on every line (owner decision P-35, Option C;
there is no install base on s5).

- `install.sh`: `TARGET_ROOT_FSTYPE` defaults to `ufs`; `s5` is refused with that
  reason. The root and the 1.1 data slice are laid by the miniroot's stock
  `mkfs_ufs -o free=2,opt=s` on the block node; there is no `mkfs_s5`, `fsck_s5` or
  `labelit` call left in the driver.
- **Prebuilt mode is retired.** `INSTALL_TARGET_PREBUILT=1` mounted an s5 root
  `tools/mkroot.sh` had minted host-side; the driver refuses the key. Every install
  is **author** mode.
- `setup.sh` no longer asks *"What file system type is the root partition?"*; the
  composed answer is always `TARGET_ROOT_FSTYPE=ufs`.
- The upgrade install, which mounted the old root as ufs only, is gone too (P-36,
  next section).
- `install-matrix.sh`: the eleven prebuilt cells (`cd`, `cd-interactive`,
  `cd-interrupt`, `cd-suomi`, `cd-standard`, `cd-public`, `cd-public-r6`, `raw`,
  `fd-a4091-aga`, `fd-a4091-pub-r6`, `fd-ide-raw`) are **RETIRED** with their reason;
  no canned answer types a filesystem name.
- **Still s5, and not targets:** the 030 line's install miniroot (`MINIROOT_FSTYPE`,
  the `/etc/mnttab` seed line), the raw source disks' payload slices, and the
  miniroot repair path's s5 arm. The k30 kernel package keeps its s5 module.

The installed-tree digest has no filesystem field, so every attested set's reference
stands (proven for `minimal` by `cd-ufs`, `full`/`developer`/`x11` on the ufs rig).

## Clean installs only — current (P-36, 2026-10-31)

**1.1 supports clean installs only** (owner: "no update path from 1.0, no migration
code"). A disk that holds Amix is erased and installed afresh.

- `setup.sh` offers no upgrade. A disk that carries an RDB, an installed 1.0 or 1.1
  disk included, is asked stock's erase question and nothing else; the answers block
  has no `INSTALL_UPGRADE` or `UPGRADE_DROP_HOME` line.
- `install.sh` refuses `INSTALL_UPGRADE` set to anything but `no`: *"1.1 requires a
  fresh install, P-36"*. The capture, restore and put-in-place (`l11_upgrade_*`), the
  kept 1.1 layout, the held swap, `S17upgrade` and `/var/adm/upgrade` are removed, and
  so is the unattended erase guard's exemption for an upgrade.
- `firstboot.sh` has no `FB_UPGRADED` branch: the first boot always writes the node
  name, zone, root password, hosts, repository and `zen.conf`.
- `install-matrix.sh`: `l11-k30-upg`, `l11-k46-upg`, `l11-k46-upg-ia` and
  `l11-k46-upg11` are **RETIRED**, their profiles deleted. The interactive l11
  vectors lose the leading `2` that answered the offer (`y 105 30 1 n n`).
  `tools/l11-target-check.py` asserts on every 1.1 target that there is no
  `/var/adm/upgrade`, no `S17upgrade` and no `FB_UPGRADED`.
- **Not touched:** `apkg upgrade` and kbootset's generations on a running 1.1 system.

The disk itself: `docs/l11-disk.md`. The removed upgrade install
(`docs/upgrade-install.md` and its code) is in git up to 3ac92fb.

## The 1.1 install from packages — current (2026-10-31)

The installer lays the 1.1 system down from packages; it writes only what no package owns.

- **Tools.** Nothing in 1.1 reads the frozen amix-packagemanager: `build-l11-inputs.sh`
  builds amix `userland/pkgtools` at the set's `pkgtools` revision (the host pkgtrans,
  the miniroot's static pkgadd set, apkg, `make dist`'s APKG and APKGENG, held to their
  md5) into `work/l11/pkgtools`, which every 1.1 tool reads.
- **The set.** `tools/l11-set.conf`: the kernel-space candidate root of amix-packages,
  and amix-base, dhcp-client and syslog rolled at the set's `base` amix revision
  (reproducible; their sha256 pinned).
- **The install.** After core and the base set, the base packages under the target's
  chroot (seeded baselines, `removef core`); the admin files `/etc/inet/interfaces`,
  `/etc/rc.conf`, `/etc/display`; no S99zen, S20monsw, syslog unit, S89rootswap,
  S01kbnamelist or S99zkbootset (their packages carry them). `docs/l11-disk.md`.
- **The first boot** (`FB_L11=y`): DHCP or one static interface, the answers into
  `/etc/inet/interfaces` and `/etc/rc.conf`, an empty name allowed.
- **Checks.** `tools/l11-target-check.py` reads all of it host-side; the first-boot rig's
  answers include the DHCP and DNS questions.
- **Slice sizes.** A ufs slice may be up to 2047 MiB (4194303 blocks, measured on k46;
  the old cap was 1024); `docs/l11-disk.md`.
- **The pre-installed images**: `tools/build-preinstalled.sh` masters the image
  medium (`profiles/image-k46-4g`, `image-k30-4g`, set x11), installs it in the
  `l11-img-<line>` cell onto a 3600 MiB target (root 2047, swap 256, store 64, /home
  1232 MiB), proves it with `bootstore`, first-boots a copy, and keeps the unbooted
  target with its manifest in `work/images`. `l11-img-k30-r2048` asks for a 2048 MiB
  root and is expected to fail at mkfs.

## Canonical digests — current

The installed-tree digest is the attestation the installer is judged by: the same
base set installed from any source medium, on the bench or on metal, must produce
a byte-identical tree.

| digest | objects | what it is |
|--------|--------:|------------|
| **`a650dd79b71de25bfd023335c1bfbded`** | **4859** | **THE canonical installed-tree digest**, re-attested **2026-10-02** (P-15 I1): the same eight packages with **APKG 0.2.2** on the release CDs (release media must not carry the retired host string). Only APKG's files moved; the count and the base-5 digest did not. Matrix `cd` 10/10, `work/install-matrix/20261002-120849-cd`. |
| ~~`e483b0cb25dfaf4087b1f783335d520d`~~ | 4859 | superseded 2026-10-02 (APKG 0.1). Was **THE canonical installed-tree digest**, re-attested **2026-08-11** — the **eight**-package base set `core bsd net text sysadm cdfs APKGENG APKG` as the **P5.4 r3 packages** actually ship it. Reproduced identically by two independent bench runs on freshly mastered media (`work/install-matrix/20260811-103107-cd` and `…-104927-cd`), with two *different* drivers, then gated green by the matrix's **`cd` cell 9/9** (`work/install-matrix/20260811-110806-cd`, 2026-08-11). See *Re-attestation 2026-08-11* below for why it moved. |
| `86e1ceb144f1328bf441c5df38fc2798` | 4793 | the **base-5 continuity** digest — what `altroot-attest --only core,bsd,net,text,sysadm` still reproduces out of the *current* eight-package install. **UNCHANGED by the 2026-08-11 re-attestation** (and unchanged since Wave 2): it is the continuity check across waves, **not** the shipped set. |
| **`bd91105e493297cdf40c94efd0a5741a`** | **11012** | the **`standard` set** (17 packages), **re-attested 2026-10-02/03** (P-15 I1) with APKG 0.2.2 on the release CDs; count unchanged, base-5 + base-8 containment exact. Matrix `cd-standard` 10/10, `work/install-matrix/20261002-192444-cd-standard`. |
| ~~`4ad8e17b69b32208c9fffa600596a428`~~ | **11012** | the **`standard` set** (17 packages), attested **2026-08-11** by the matrix's new **`cd-standard` cell 9/9** (`work/install-matrix/w3b3-std`). The SECOND attested set (plan §5.7, W3b). Its base-5 and base-8 subsets are **contained by object count** (4793 / 4859 exactly) but **not** by digest — see *W3b bench finding 2*: five shared paths are legitimately re-declared by `uucp`, `man` and `public`. | *(superseded 2026-10-02)*

| **`3093f40b8dddc89bc749a6a12da8cfd5`** | **11497** | the **`developer` set** (19 packages), **re-attested 2026-10-02/03** (P-15 I1) with APKG 0.2.2 on the release CDs; count unchanged, base-5 + base-8 containment exact. Matrix `cd-developer` 10/10, `work/install-matrix/20261002-211113-cd-developer`. |
| ~~`ebd61ce15699fbb34cf0f6a2d0a07024`~~ | **11497** | the **`developer` set** (19 packages), attested **2026-08-12** by the W6 `cd-developer` cell 9/9 (`work/install-matrix/w6-cd-developer`). Standard plus `xdev`/`oldev`, `conf` deliberately excluded (§8.4). Ran against the 400 MB target; base-5 and base-8 containment exact by object count | *(superseded 2026-10-02)*
| **`054e4b8e31464cd7b2f5aada5530f20b`** | **11546** | the **`x11` set** (18 packages), **re-attested 2026-10-02/03** (P-15 I1) with APKG 0.2.2 on the release CDs; count unchanged, base-5 + base-8 containment exact. Matrix `cd-x11` 10/10, `work/install-matrix/20261002-201856-cd-x11`. |
| ~~`5439f78fc1caf4da46af82db360f5d13`~~ | **11546** | the **`x11` set** (18 packages), attested **2026-08-12** by the W6 `cd-x11` cell 9/9 (`work/install-matrix/w6-cd-x11`). Standard plus `xtras`; same 400 MB target, same containment | *(superseded 2026-10-02)*
| **`b1b55aae473b6fb870170054617c76ef`** | **28709** | the **`full` set** (30 packages), **re-attested 2026-10-02/03** (P-15 I1) with APKG 0.2.2 on the release CDs; count unchanged, base-5 + base-8 containment exact. Matrix `cd-full` 10/10, `work/install-matrix/20261002-220132-cd-full`. The install took 6420 s (vs 1132 s on 08-14) on a host shared with kerntools' parallel rigs. |
| **`85bfb9256885d78d31778973ec1bd4b2`** | **28711** | the **`full-r6` set**: `full` from the public classic full disc (r6d), attested **2026-10-09** by `cd-full-pub-r6` 10/10 (`work/install-matrix/20261009-cd-full-pub-r6d-c`), 512 MB ufs. Two objects over `full`: `/usr/apkg/lib` and `/usr/apkg/lib/apkg.conf` (APKG 0.2.3). Measured, not gated: SET_REFS keeps `-` as for every r6 set (the media builder does not advertise them; installer-selftest audit X), so each run re-attests with `--attest-set`. |
| **`b7c2be7de8834e63b10c06f4326ed8d5`** | **28711** | the **`full-060-r6`** and **`full-060-r6-a4091root`** sets: the 060 full discs (SD and A4092 root), attested **2026-10-09** by `cd1-full-pub-r6` and `cd2-full-pub-r6` 10/10 (`20261009-cd1-full-pub-r6d`, `20261009-cd2-full-pub-r6d`). Differs from `full-r6` only in `/stand/unix` (the KD060-ZA kernel). Measured, not gated: SET_REFS keeps `-` as for every r6 set (the media builder does not advertise them; installer-selftest audit X), so each run re-attests with `--attest-set`. |
| **`43b94ef2ab6b4bd9e70d9ada24a4e430`** | **11014** | the **`standard-r6` set**: `standard` (17 packages) from the public classic full disc, attested **2026-10-10** by `cd-std200-pub-r6` 10/10 (`20261010-cd-std200-pub-r6d`) on a 200 MB disk (166 MB ufs root); on the default 100 MB disk it runs out of space (`20261009-cd-std-pub-r6d`). Measured, not gated: SET_REFS keeps `-` as for every r6 set (the media builder does not advertise them; installer-selftest audit X), so each run re-attests with `--attest-set`. |
| ~~`68de888084500aef703a9ccd3eeaa0e5`~~ | **28709** | the **`full` set** (30 packages) — **the whole distribution**, attested **2026-08-14** by `cd-full` 10/10 (`work/install-matrix/ufs-full-2`) on the **512 MB ufs** rig, author mode. The last set to have no reference, and the only one that needed both a filesystem change and a disk change to get one. **28,709 was PRE-REGISTERED, not read off the run**: `amix-packagemanager`'s `s5-collision-scan.py` predicts the contents-DB object count exactly from the mastered disc's own pkgmaps, and it was published (and re-derived against this very disc) before the box was booted. base-5 / base-8 containment exact by object count (4793 / 4859) | *(superseded 2026-10-02)*

**Per-set references** live in `tools/install-matrix.sh`'s `SET_REFS` and are
paired with `ATTESTED_SETS` in `tools/build-install-iso.sh` (what the medium tells
the interview); `installer-selftest` audit X refuses any disagreement between
them. **`full` now has a reference digest**, `68de8880…` / **28709**, and it took
two changes to get one: the UFS route (which lifted the 14-character name limit)
and then a bigger disk (`pkgadd`'s datastream spool overran the 400 MB rig by
8.5 MiB — see *The `full` set fits the filesystem and not the disk* below). The
original blocker, for the record:
the 30-package set cannot be installed as declared **on s5**, because **five
groups / ten objects** in `gnusrc2` and `X11r5src` collide under s5's
14-character name limit — see *The `full` set cannot be installed as declared*
below, where that count is corrected (W6's own scan said three, and was
directory-blind) and the **UFS route** — which removes the limit instead of
working around it — is set against the packagemanager's Option A.

**Superseded — historical only, never an acceptance target:**

| digest | objects | when it was canonical |
|--------|--------:|-----------------------|
| `29a1ae6192e4c64947a0cd14f9bfd149` | 4796 | the **six**-package set at **W6.2** (`cdfs` had just joined; `APKGENG`/`APKG` had not) |
| `a2467c6958dba203d399c4441d77f338` | 4858 | the eight-package set at **W6.4b** — one object short of the current figure, before W6.4c's `/usr/bin/apkg` symlink added the 4859th |
| `ec31a72291e01382ab4b97403f6dad13` | 4859 | the eight-package set from **W6.4c until 2026-08-11** — the pre-r3 `APKG`/`APKGENG` mints. **SUPERSEDED 2026-08-11; never quote it as current** (same hygiene as the six-package `29a1ae61…` figure). It is still the right number when reading any record written before that date. |

### Re-attestation 2026-08-11 — `ec31a72…` → `e483b0cb…`

**What moved.** Exactly two package files, both re-minted in
`../amix-packagemanager/build/repo-staging/base/` on **2026-08-06** as part of the
reviewed **P5.4 r3** arc:

| package | pre-r3 (minted `ec31a72…`) | r3 (mints `e483b0cb…`) |
|---------|---------------------------|------------------------|
| `APKGENG-1.12.0.pkg` | `fb2f08f46c6921e979e265c36cece000`, 2 436 608 B | `4ba1512113628aba19fdf14e7e9392cd`, **2 347 520 B** (−89 KB — a real content change) |
| `APKG-0.1.pkg` | `ea72218a454ae57700d254b16e1540b8`, 115 200 B | `8caa7b42dbce8170e93bdac211ae8a75`, 115 200 B |

**What did not move.** Every `stock/*.pkg` and `cdfs` is **byte-identical** between the
old and new media (verified by md5-ing the package payloads extracted from both ISOs).
The **object count is unchanged at 4859** — nothing was added or removed, only recorded
sizes changed — and the **base-5 continuity digest `86e1ceb144f1328bf441c5df38fc2798`
/ 4793 is EXACT**, which is precisely the property that makes this a contained
re-mint rather than a regression.

**Why it surfaced only now.** The 2026-08-06 and 2026-08-07 `cd` runs were green
against `ec31a72…` because they booted the **2026-07-23 ISO**, which still carried the
pre-r3 packages. Nobody had re-mastered since. The first fresh-media runs after the
re-mint (2026-08-11) exposed the drift immediately — **exactly what the fresh-media
rule exists to do**; see *Media hygiene* below.

**Why re-attest rather than restore.** The r3 packages are the shipped, reviewed
reality; reverting to the July mint artifacts to chase an older number would be
regressive churn. The old canonical predates them.

**Evidence quality.** `e483b0cb25dfaf4087b1f783335d520d` was produced by two
independent full runs on separately mastered media with two different drivers (an
instrumented diagnostic build and the fixed shipping build) — so the value is a
property of the *package set*, not of any one driver or run. It was then gated
green as the acceptance target: `tools/install-matrix.sh cd` **9/9**, run
`work/install-matrix/20260811-110806-cd` — `digest PASS … canonical
e483b0cb25dfaf4087b1f783335d520d (4859 obj) + base-5
86e1ceb144f1328bf441c5df38fc2798 (4793 obj)`.

**Metal is not yet re-validated against this value.** M-RUN2/M-RUN3 attested
`ec31a72…`. Re-confirming `e483b0cb…` on real hardware rides the next metal session
(`docs/metal-install-runbook.md`).

## The tracked acceptance rig — `configs/accept-bench-a3000-a4091.uae`

The canonical **CD-arm** acceptance run — the *W5.4 runbook* below, and every
attestation that reproduces the canonical digest from a disc — is driven by a
**tracked** Amiberry config, so the rig never has to be rebuilt from prose again.

| | |
|---|---|
| config | `configs/accept-bench-a3000-a4091.uae` |
| profile it serves | `profiles/bench-a3000-a4091.profile` (`SOURCE_KIND=cdfs`) |
| machine | A3000 + A4091, KS 2.04 / ECS, 68030 + MMU + 68882, **64 MB** (`a3000mem_size=64` — the standing bench value; the old "16 MB Amix ceiling" was inherited, never measured — the real limit is the frame-arena law, ~80 MB networked max on metal) |
| DF0 | `floppies/build/amix_21_boot-universal.adf` (the fd0unix universal boot floppy). At the *root floppy* prompt, swap DF0 to `floppies/build/amix_21_root-ng.adf` — the miniroot is a **separate** ADF and the stock flow expects it in the **same** drive |
| install source | the install CD at `scsi3_a4091` ⇒ the driver's `CD_SPEC=1,3` |
| install target | a blank disk at `scsi6_a3000` ⇒ `c6d0`, matching the profile's `ROOTDEV=0x00480016` |
| network | a2065 on `tap0`, MAC `…:38` ⇒ the profile's `FB_IP=192.0.2.38` |

**`scsi_a3000=true` (with `scsi_a3000_rom_file=:ENABLED`) is load-bearing.**
Enabling the A3000's onboard WD33C93 makes it **card 0** and the A4091 **card 1** —
which is simultaneously (a) what makes the CD answer at cdfs `1,3`, and (b) what
puts the target in the `cXd0` block namespace. W5.4b proved the second half the
hard way: on an otherwise identical rig with the target on `scsi6_a4091` the
miniroot cannot open `c6d0` at all. (The older tape rig
`configs/install-blank-a4091.uae` has the A3000 SCSI **off** — correct there,
wrong here.)

**Both media are per-run artifacts** — see *Media hygiene* below. The config pins
stable names; rebuild them **fresh before every run**:

```sh
# target: 100 MB blank, RDB root/swap/boot, s5 root. Run the driver with
# INSTALL_TARGET_PREBUILT=1 to take the low-risk prebuilt path (see W5.4 runbook).
# No --sole-disk: this disk shares the machine with the CD unit.
tools/mkroot.sh --out hdf/accept-target.hdf --size-mb 100 --scsi-id 6
tools/build-install-iso.sh --out work/iso/amix21-install-accept.iso
```

Neither path is committable: `hdf/` and `work/` are gitignored, and `build-iso.sh`
Gate 1 refuses to write an image to any path git would track.

The **RAW arm** (`profiles/bench-a3000-a4091-raw.profile`, `SOURCE_KIND=raw`) is a
*different* rig — a second source disk at id 5, no CD at all — and is **not** wired
by this config. See *W6-RAW.1*.

## The A3000-SCSI synthesis gate — why the install kernel must be patched

The A3000's internal SCSI is not an AutoConfig board, so stock Amix 2.1 *guesses*
it: `amiga/kernel/support.c` synthesizes the controller at `0xDD0000` only when
the kernel's own BSS `end` lands above `0x07000000` — a **RAM-size guess**. At
`a3000mem_size=16` the bench's Fast RAM is `[0x07000000,0x08000000)` so the
kernel necessarily loads above the line and the guess is true *by accident*; at
the standing **64 MB** budget RAM is `[0x04000000,0x08000000)`, the kernel loads
low, the guess goes false, and the A3000 controller silently disappears — the
SCSI cards renumber (the install CD then answers cdfs at `0,3`, not the `1,3`
this whole document assumes) and the install target `c6d0` does not exist at all
(install gate `rc=1`). The fix is `../amix-a4091/src/kernel-patches/support.c.patch`:
a VPOSR chipset gate (ECS/OCS ⇒ A3000-class, AGA ⇒ A4000, skip) plus a
two-register WD33C93 write/readback probe through `0xDD0041`/`0xDD0043`, i.e. the
hardware answering instead of arithmetic guessing. **Build the install kernel with
`tools/build-install-kernel.sh`**, which passes the driver repo *unfiltered* to
kerntools' cross-builder (the old hand recipe made a filtered copy whose only job
was to delete this patch) and then proves the probe reached the boot payload —
source, `support.o`, the ET_REL link and `unix.brel`. `build-universal-bootfloppy.sh`
re-checks the framed payload and refuses to build a floppy without it, so the
failure can never come back as a mysterious "no target disk" an hour into a run:

```sh
tools/build-install-kernel.sh          # fd0unix + a4091, support.c PATCHED, gated
tools/build-universal-bootfloppy.sh    # frames it; refuses an unpatched kernel
```

### The glob-vs-conf gap, and why this repo's one build arm never had it (2026-08-16)

kerntools found that `build-cross-kernel.sh` §2b applies kernel-patches **by glob
over the driver dirs it is passed**, while `kernel-patches.conf` expresses "this
patch rides every kernel" as an `always:<repo>` row — a *conf* concept the cross
builder does not read. A cross build therefore gets an `always:` patch only if some
passed dir happens to carry the file. The metal-mix configs pass `amix-z3660scsi`
and **not** `amix-a4091`, so the r2/r3 `c0s1unix`/`c6s1unix` kernels were built with
**stock `support.c`**; kerntools closed it at r4 with `work/patch-carrier-r4`, a bare
dir carrying a4091's `a3091`/`a2091`/`support` patches.

**This repo audited its own arms against that and does not share the gap.**
`tools/build-install-kernel.sh` (line ~324) is the **only** place in amix-installng
that assembles a kernel — `grep -rn build-cross-kernel` finds no other invocation,
and the old hand recipe that made a *filtered* copy is gone. It passes `$A4091`
**unfiltered**, so §2b globs all four a4091 patches plus kerntools' own `aen.c.patch`,
and the four-stage marker gate then proves the probe reached source, `support.o`, the
ET_REL link and `unix.brel`. There is no conf lookup to get wrong. Two honest
qualifications:

- **the gap reached our *media* anyway, through the kernels we do not build.**
  `build-raw-source.sh` and `build-bootslice.py` consume `c0s1unix`/`c6s1unix` from
  kerntools' work tree and gate them by `sum -r` against the profile pin — a strong
  *identity* gate, but identity is only as good as the number a human put in the
  profile; neither tool checks the probe *property* the way
  `build-universal-bootfloppy.sh` does for `fd0unix`. That asymmetry is deliberate
  for now: on the A4000 metal the probe is **inert** (no A3000 internal SCSI; the
  patch's VPOSR gate skips on AGA), so making it a hard requirement there would
  gate on a property that rig does not need. Recorded rather than silently fixed;
- `tools/build-install-kernel.sh --config c6s1unix` is offered in the usage but
  would build a c6s1unix against **a4091** rather than z3660scsi — a wrong-composition
  metal kernel. Nothing uses it; it is a latent foot-gun, not a live defect.

### P5.4 r4 — the media re-master (2026-08-16)

The fresh-install kernel line moved to the r4 cross set. `fd0unix` was rebuilt **here**
(`tools/build-install-kernel.sh`) and came out **byte-identical** to kerntools'
`work/cross-kernel-fd0-r4` — same `unix` (md5 `4cd2a93f…`, `sum -r` 59287) and same
`unix.brel` (md5 `8bcda01b…`, `sum -r` **09433**, note the leading zero) — which
converts kerntools' *prediction* of harness/pin determinism into a measurement. Pins
moved: metal raw profile `SRC_KERNEL_BREL_SUMR` 51865 → **28387**, `KERNEL_BREL_SUMR`
49227 → **50544**; `KERNEL_RELOCUNIX_SUMR` **stayed 55482** and was re-derived rather
than carried (it is the `core` package's own 1992 `/stand/unix`, 1,475,108 B — not a
kernel we build). Bench proof on the new media: `install-matrix cd` **10/10**
(`work/install-matrix/20260816-124118-cd`), CD at the stock `1,3` addressing at 64 MB,
digest **unmoved** at `e483b0cb25dfaf4087b1f783335d520d` / 4859 with base-5
`86e1ceb144f1328bf441c5df38fc2798` / 4793 exact. Artifact identity: runbook §0.

## The regression matrix — `tools/install-matrix.sh` (P6.1)

The rig above is *what to boot*; the matrix is *the run itself, unattended, gated*.
One command performs a full from-scratch install for one **cell** and produces a
single verdict computed only from its gate ledger.

> **★ Run the matrix before every media re-master, and again after it.** See
> `docs/metal-install-runbook.md` §0.1. A re-master changes what the installer lays
> down; the matrix is what says the installed tree is still byte-canonical.

```sh
tools/install-matrix.sh --list            # the cell matrix, incl. why a cell cannot run
tools/install-matrix.sh cd                # the canonical CD-sourced acceptance arm
tools/install-matrix.sh cd-author         # same media, on-box author target build
tools/install-matrix.sh --selftest        # fail-closed logic; no bench, no media
```

**A cell is (rig, profile, source medium, target-build mode)**, and the point of the
matrix is that every cell must reproduce the **same installed-tree digest** from a
different path — that identity *is* the regression test.

| cell | status | source | target build | note |
|------|--------|--------|--------------|------|
| `cd` | RETIRED (P-35: prebuilt s5) | cdfs install CD at `1,3` | prebuilt (`mkroot.sh`) | the canonical acceptance arm |
| `cd-interactive` | RETIRED (P-35: prebuilt s5) | cdfs install CD at `1,3` | prebuilt | the same media and the same target-build path as `cd`, driven through the **whole operator flow** — since W4 that starts at the miniroot's own `/etc/profile` (keymap, install-or-repair, the source auto-probe) and continues into the interview. Gated on the answers beacon *before* the transplant runs |
| `cd-suomi` | RETIRED (P-35: prebuilt s5) | cdfs install CD at `1,3` | prebuilt | `cd-interactive` with **keymap 11 (Suomi / Svenska)** instead of 12. Proves the keymap reaches the target (`default.kmap` hard-linked to `kmap/s`, same inode; `FB_KMAP=s` in `firstboot.conf`) **and** that it does not fork the attestation — the link is driver-written, so the digest must not move |
| `cd-interrupt` | RETIRED (P-35: prebuilt s5) | cdfs install CD at `1,3` | prebuilt | **W5's resilience cell**, and the only one that can prove the contract: the same install as `cd-interactive`, but the first cold boot is **power-cycled part-way through the first-boot dialog**. The next boot must come up healthy (S16 applied the mechanical keys anyway), the dialog must re-run **from the top** (`chmod -x` fires only at the clean exit), completing it must leave a clean third boot — and the digest must not move |
| `cd-standard` | RETIRED (P-35: prebuilt s5) | cdfs install CD mastered `--set standard` | prebuilt | the second attested set (17 packages), and the heaviest-I/O memory-headroom measurement for it |
| `cd-public` | RETIRED (P-35: prebuilt s5) | cdfs install CD mastered for the **public** profile | prebuilt | **W6 / P8.3.** `cd-interactive` on a disc mastered from the distro-neutral profile — no nodename, no address, no netmask, no gateway, no resolver, no repository address, no disk size, dialog armed. The disc names `public-a3000-a4091` in `/install/profiles/BASE`, so the miniroot hands off to it with no argument, exactly as a stranger booting the disc would. The assertion is that **nothing moves**: same answers, and the installed tree is still the canonical `minimal` digest. A profile is data; if emptying the `FB_*` seam moved one installed byte, the seam was not where we thought it was |
| ★ `cd-full` | RUNNABLE (**10/10 2026-08-14**) | cdfs install CD mastered `--set full` | **author** (**512 MB**, ufs) | All thirty packages, ~276 MB declared / 292.8 MiB realised. The heaviest install, the first run *with* W5.5's real swap, and the only set s5 cannot hold at all. The rig was 400 MB and **overran it by 8.5 MiB on 2026-08-14** — `pkgadd` spools each datastream onto the target, so peak = tree + largest package, and the largest installs last. 512 MB puts ~97 MiB over that peak |
| `cd-developer` | RUNNABLE (**owed a re-run**) | cdfs install CD mastered `--set developer` | **author** (**512 MB**, ufs) | **W6.** 19 packages — standard plus `xdev`/`oldev`, with `conf` deliberately excluded (§8.4) |
| `cd-x11` | RUNNABLE (**owed a re-run**) | cdfs install CD mastered `--set x11` | **author** (**512 MB**, ufs) | **W6.** 18 packages — standard plus `xtras` |
| `cd-author` | RUNNABLE | cdfs install CD at `1,3` | **author** (on-box `/etc/rdb` + `mkfs_s5`; `mkfs_ufs` since P-35) | the other target-build path: the blank target is partitioned + `mkfs_s5`-ed **on the box** and must still reach the same digest. Was RED on 2026-07-30 — its first run exposed three shipped defects; green since 2026-07-31, see *What the author cell found* below |
| ★ `cd-ufs` | RUNNABLE (**green 2026-08-14, 10/10**) | cdfs install CD at `1,3` | **author** (on-box `/etc/rdb` + `mkfs_ufs`) | **the UFS lane.** Same media, same rig, same 100 MB target, same `minimal` set as `cd` — the operator answers the restored stock s5/ufs question and gets a **Berkeley** root. It *must* be author mode: `mkfs_ufs` runs on the box, there is no host-side UFS writer, and the driver refuses a `ufs` prebuilt target rather than mounting `mkroot`'s s5 root under the wrong type. The assertion is that **nothing moves** — still `e483b0cb…` / 4859 with base-5 exact, because the digest is contents-DB-derived and the contents DB has no filesystem field. What *does* move is the disk, and the new `rootfs` gate is the only one that can see it. Read against two neighbours: `cd-author` is the same author path on s5, `cd-interactive` the same interview on prebuilt s5 |
| `raw` | RETIRED (P-35: prebuilt s5) | raw distribution slice (`apkg SRC_RAW`) | prebuilt | implemented; needs a **bench** raw source disk (`--src-hdf`). None exists — W6-RAW.1 built one and did not keep it, and building one is *mastering media* |
| `z3660-raw` | INFEASIBLE | self-booting metal source `.hdf` at id 0 | author | the bench cannot boot the metal source disk **by design** (runbook §0). Bench proves its contents; metal proves its boot |
| `tape` | RETIRED | dist tape on the A4091 | stock | timeout-prone, and the stock tape path does not run this driver at all |

An infeasible cell stays **in** the table with its reason. A cell that is merely
absent reads as "we covered everything we could", which is how coverage quietly
shrinks.

**Coverage the P-35 retirement took with it** (not wanted back for now, orchestrator
2026-10-30): the Suomi keymap reaching the target (`cd-suomi`) and the interrupted
first-boot dialog (`cd-interrupt`). Both were prebuilt only because their rig was;
either can come back as an **author-mode** cell on the same profile (`cd-ufs`'s shape,
`PREBUILT=0`, `EXPECT_FSTYPE=ufs`) with its old `INTERVIEW_PRE` and dialog keys.

**The 68060 cells run on an emulated LC060.** Every 060 rig
(`configs/accept-z3660-060-*.uae`, `configs/boot-z3660-060-*.uae`) pins
`cpu_model=68060`, `fpu_model=0` (no FPU), `cpu_no_unimplemented=true`,
`fpu_no_unimplemented=true` (it matters only if a rig adds an FPU) and `cachesize=0`.
Amiberry clears both knobs under JIT. The integer knob makes the CPU take vector 61 for
the forms a real 68060 leaves to software: 64-bit `mul.l`/`div.l`, `movep`,
`cmp2`/`chk2` and `cas2`. Without the knob they run natively, and a binary that needs
them passes in emulation and dies on metal. On 2026-10-14 this was checked from inside
the guest:
- the 1.0 kernel's ISP counter moves by the probe's 100 forms;
- a pre-r6 kernel kills the 9 forms it does not emulate;
- floating point traps into the kernel's FPU emulator.

★ **Three cells run against a 512 MB target, and that is arithmetic, not a second
rig.** The canonical bench target is 100 MB, whose stock plan gives a **79 MB
root**. The catalog's own `#isize` block says otherwise for three of the five
named sets:

| set | packages | installed | ×1.10 (s5 footprint) | fits a 79 MB root? |
|---|--:|--:|--:|---|
| `minimal` | 8 | 23.6 MB | 25.9 MB | yes |
| `standard` | 17 | 60.8 MB | 66.8 MB | yes |
| `x11` | 18 | 69.5 MB | 76.5 MB | by 2.5 MB — **no** |
| `developer` | 19 | 65.4 MB | 71.9 MB | by 7 MB — **no** |
| `full` | 30 | **276.0 MB** | **303.6 MB** | not remotely |

So `cd-full`/`cd-developer`/`cd-x11` take a 512 MB target and the **two**-key
`bench-a3000-a4091-big` profile (`TARGET_DISK_MB=512` plus, since 2026-08-14,
`TARGET_ROOT_FSTYPE=ufs` — `full` cannot be laid on s5 at all).

> ★ **Read that table with the spool in mind.** The pin was **400 MB** until
> 2026-08-14, and 400 was **8.5 MiB short** for `full` on ufs — even though the
> ×1.10 column says 303.6 MB against a 367 MB root, which looks like 60 MB of
> headroom. The ×1.10 column is a *declared-tree* estimate; the actual demand is
> **tree + the largest single package**, because `pkgadd` spools each datastream
> onto the target before installing it. See *The `full` set fits the filesystem
> and not the disk* below for the measurement. 512 MB gives a 480 MB root,
> ~450 MiB of ufs data area and ~97 MiB over the measured peak.

Disk size is not part of the installed tree, so a set's digest is the same on
either target — which is exactly why this is a profile key and not a second
validation rig. The pin and the cell's `mkroot` size are **one fact written
twice**, so both `--selftest` and the `workset` gate require them to agree: a
disagreement would build a target whose slice map the driver does not believe in,
and would do it silently, because each half is internally consistent.

### The gates

`preflight` (repo amiberry on its branch, no second emulator, the rig pins
`cycle_exact=false` at 64 MB with `scsi_a3000=true`, rate guard armed, every input
readable) → `workset` (**fresh** media: a new `mkroot`'d target and disposable copies
of every floppy/ISO, plus the two generated `.uae` rigs) → `mediaboot` (install
kernel up, root floppy inserted at the prompt, **miniroot shell confirmed**) →
`source` (source mounted **and proven readable**) → `install` (the driver's **exit
status**) → `coldboot` (target cold-booted **twice**: identity baked, first-boot
once-only — and since W5, on an interactive cell, the **first-boot dialog typed on
the console before the box can reach run level 2 at all**, plus the assertion that
it disarmed itself and that an unattended cell never armed one) → `digest` (the
attestation) → `bootchain` (host-side boot-slice re-verify) → `teardown` (emulator
and `tap0` **confirmed** gone).

Fail-closed: each gate appends exactly one line to `gates.tsv`, and the verdict
demands every required gate is present exactly once and says `PASS`. A gate that
failed, was skipped, ran twice, or never ran because the harness died is a **FAIL**
— including when the harness is killed mid-run, because the EXIT trap still tears
the bench down and still prints a verdict from what the ledger actually contains.

> ⚠ **Do not edit `install-matrix.sh` while a run is in flight.** Bash reads a
> script *incrementally*, keeping a byte offset into the open file, so rewriting
> it in place mid-run makes the shell resume from that offset into shifted text.
> W6 did exactly this and lost a `cd` run to it: the harness had just passed
> `mediaboot` when it printed `install-matrix.sh: line 2162: gate: command not
> found` and fell straight through to the verdict — `source:NEVER-RAN
> install:NEVER-RAN …`. The fail-closed ledger behaved perfectly (a run that did
> not execute its gates is a FAIL), and the failure was entirely self-inflicted:
> nothing was wrong with the driver, the media or the cell. **Freeze the harness
> before launching a batch**, and re-run any cell that was in flight across an
> edit.

### How a blind console is gated: the marker channel

The install miniroot has **no network** — the only channel to it is the emulated
console, and nothing host-side can read that screen back as text. So no phase is
ever satisfied by "the keystrokes were sent". Every phase is confirmed by a marker
the **guest** writes to a medium the **host** can read: the run's own copy of the
root floppy. `echo <NONCE>shell > /matrix.up; sync` lands in the `.adf` file within
a minute, and the host byte-scans for it.

- the nonce is **per run**, so a marker left by an earlier run cannot be mistaken
  for this one, and `workset` refuses if the fresh floppy already contains it;
- the install line writes a **start** marker before the driver runs (a mistyped line
  is caught in minutes, not at the full budget) and the driver's **`rc`** after —
  `echo <NONCE>rc$? > /matrix.rc`;
- a missing marker yields *no* rc, never `rc=0`: a dropped keystroke is a FAIL, not
  a false pass;
- the driver's stdin is `/dev/null` (**METAL-FIX.3**: an inherited stdin is what hung
  M-RUN1 on the 1991 `pkgadd`'s prompt).

Screenshots are taken throughout and are **artifacts for a human, never a gate**.
The one thing the harness reads off the screen is `amicon.py ink` — a count of lit
pixels, used *only* to time "the guest has printed something". (PNG file size was
tried for that and is useless: one line of text on a black screen is a ~2 KB PNG,
barely above an empty one.)

### The attestation

`digest` pulls `/var/sadm/install/contents` + `/etc/passwd` + `/etc/group` off the
booted box and runs `../amix-packagemanager/tools/repo/altroot_attest.py` over them
— the same three inputs, from the box's own contents DB and its own name service,
that the M-RUN2 metal install was attested from, so bench and metal answers are
comparable by construction. Both the **full base-8** digest and the **base-5
continuity** subset must match, *and* so must the object counts; a matching digest
with a wrong count is a harness fault to investigate, not a pass.

### Throttle safety

Every box interaction is one held `amixrun.py --script` session, poll loops are
≥ 20 s, telnet is attempted only after ICMP answers, and the rate guard must be
**armed** at preflight (counts recorded at both ends). The install phase itself opens
zero connections — it is console-only. See
`../amix-kerntools/docs/inetd-telnet-throttle.md`.

### What the author cell found — `/etc/rdb -c` ANSWERED (2026-07-30), FIXED (2026-07-31)

*The host/on-box split* below used to record author mode's create/geometry primitive as
"the one on-box unknown — **still open**", and the 2026-07-26 sweep deliberately left
that claim standing because no run log could close it. The `cd-author` cell closed it in
171 seconds, on its first run, with the miniroot's own words:

```
+ /etc/rdb -c -s 64 /dev/rdsk/c6d0s0
rdb: -c requires -d disksize
usage: rdb [-v] [-w] [-H] device
       rdb -a device name start length
       rdb -c [-s n] device [name start length]*
       rdb -p partition [-b] [-B] [-m] [-M] [-C n] [-N] [-P n] [-R n] device
install.sh: STOP: command failed (rc=1): /etc/rdb -c -s 64 /dev/rdsk/c6d0s0
```

*(The usage block is quoted from `work/install-matrix/20260730-211314-cd-author/shots/005-install-end.png`
and cross-checked against the literal in the binary. An earlier revision of this section
transcribed it by eye and got four of the flag letters wrong — `-n`/`-l` for `-v`/`-w`,
and a `-c` line that was really the `-p` line. The error line itself was transcribed
correctly, and it is the one that matters: **`-c` requires `-d`**. Note also that `-d`
does not appear in the usage text at all, which is why the grammar could not be read off
that block alone.)*

So the answer was not "unconfirmed" but **wrong as shipped** — and once the cell had put
the driver in front of the real `rdb`, the rest of the author path could be settled the
same way. **Three lines were wrong; all three are now fixed and the whole path is
bench-proven.**

**Where the semantics actually come from.** `/etc/rdb` on the NG miniroot is
**byte-identical** (md5 `6cacf95f738abea7cfddc6bb9ebf28e7`, 18 416 B) to the `/etc/rdb`
on the stock Amix 2.1 root floppy — and **the stock install script is `/etc/profile` on
that same floppy**, readable host-side with this repo's own `tools/lib/s5.py`. So the
authoritative caller of this exact binary was available all along:

| line | stock `/etc/profile` | what it means |
|------|----------------------|---------------|
| create | `/etc/rdb -c -s 64 -L 2 -d $DISKLEN $DISK` | `$DISKLEN` = `` `/etc/ddsize $rDISK` `` — the disk length in **512-byte blocks** (the script's own `DISKMB = DISKLEN / 2048` proves the unit). `-s` = sectors/track = blocks per cylinder. |
| add | `/etc/rdb -a $DISK UNIX_Root $OFFSET $ROOTLEN` | offset + length in 512-byte blocks, root→swap→boot in order; both must be cylinder-aligned (`rdb: partition start and length blocks must lie on a cylinder boundary`). |
| stamp | `/etc/rdb -p $BOOTPART -M -B -C 2 -P 2 -F 0x554e4900 $DISK` | `$BOOTPART` is a **partition NUMBER** (`` `rdb -h 5 $DISK` ``, 1-based — `rdb: partitions are numbered from 1`), not a device path. The stock script uses the same value as the `sN` suffix of `$BPART`, so partition N *is* slice N. |
| mkfs | `mkfs_${ROOT_FSYS} $ROOT_OPT $UPART $ROOTLEN` | the size operand is in **512-byte blocks**; `mkfs_s5` converts to logical blocks itself (its own `total logical blocks` line), so at the 1 KB default it mints `ROOTLEN/2` of them. |

**The three defects, and the empirical proof each is fixed** (bench run
`work/install-matrix/20260731-042745-cd-author`, `install.sh … rc=0`, target read back
host-side out of `target.hdf`):

1. **`-c` had no `-d`.** Now `/etc/rdb -c -s "$SECS" -L 2 -d "$DISKLEN" "$DISK_RAW"`.
   *Proof of the unit:* the authored RDSK block carries `rdb_Cylinders = 3200`, and
   3200 = 204800 ÷ 64 — i.e. rdb divided the `-d` value by `-s` to get cylinders, so
   **`-d` is in 512-byte blocks**. (`rdb_Sectors = 64`, `rdb_Heads = 1`.) A guess of MB
   or cylinders would have produced 1 or 50 cylinders and an unusable disk.
2. **`-p` was given a device path.** `atoi("/dev/rdsk/…")` is 0 and partitions are
   numbered from 1, so every type/flag stamp would have been refused. Now the profile's
   slice numbers go in directly. *Proof:* the produced map is
   `UNIX_Root` cyl 2..2529 `UNI\1` flags 0x2 · `UNIX_Swap` 2530..3105 `resv` 0x2 ·
   `UNIX_Boot` 3106..3169 `UNI\0` flags 0x1 (bootable) — byte-for-byte the map
   `tools/mkroot.sh` mints host-side, and the box cold-booted from it twice.
3. **`mkfs_s5` was handed the 1 KB count** (`ROOTLEN/2`), which would have built a
   filesystem over **half** the root slice. Now it gets `ROOTLEN`. *Proof:* the s5
   superblock on the authored root reads `fsize=80896 blocks, type=2` — 80 896 logical
   1 KB blocks = the full 82 837 504-byte slice, identical to mkroot's.

`-L 2` is carried verbatim from the stock line. Its effect is not separately identified
here (the authored `rdb_LoCylinder` is 0, so it is not the low-cylinder knob); what is
established is that the stock installer passes it and that the RDB produced with it is
structurally the one `mkroot.sh` produces. Two harmless divergences from `rdbtool`'s
output are worth knowing before someone "fixes" them: rdb writes `rdb_Flags = 0x08`
(NORESELECT) and `rdb_LoCylinder = 0` where `mkroot.sh`/rdbtool write `0x00` and `1`.
Both disks boot.

**The whole author path is now exercised**, not just the create line: `-a` ×3, `-p` ×3,
`mkfs_s5`, `labelit`, `fsck_s5`, the mount, the eight `pkgadd -R`s, the boot-slice write
and its on-target verify. Evidence: the **9/9** run
`work/install-matrix/20260731-044244-cd-author` (798 s; driver `rc=0` in author mode, two
cold boots to run-level 2, first-boot once-only, canonical + base-5 digests, bootchain
PASS), also recorded under **Canonical digests — current**. The run before it,
`work/install-matrix/20260731-042745-cd-author`, is the same install stopped by a
transport flake — `install`/`coldboot` green, then `amixsync` refused a **truncated**
FTP pull of the contents DB (`got 352240 want 354934`, 3 attempts) and the `digest` gate
FAILed closed on it. Worth keeping in view for two reasons: the length gate is what kept
a valid-prefix file from being attested as if it were whole, and its tree was attested
anyway — read straight out of `target.hdf` host-side with `tools/lib/s5.py`, giving
`ec31a72291e01382ab4b97403f6dad13` / 4859 and `86e1ceb144f1328bf441c5df38fc2798` / 4793.
An s5 walk of the image is a bench-free second opinion whenever the box's own transport
is the thing that failed.

This is the argument for the matrix in two paragraphs. The primitive had been "open" in
three documents for weeks; the first time a harness actually ran that path it took under
three minutes to produce the exact error string — and the fix that error pointed at
turned out to be *two further* silent defects deep, neither of which any amount of
reading would have surfaced, because nothing had ever run the code.

### RDB at LBA 0 — the author path's `-L`, and the re-lay tool (2026-09-26)

**Every medium this repo produces carries its RDSK block at block 0.** Stock Z3660 firmware
(upstream `piscsi_parse_rdb`) reads an image in 64 KB strides and tests only the first four
bytes of each read, so it finds an RDB at byte 0 and never at block 2; only the fork firmware's
blocks-1..15 scan finds the latter (`../Z3660/docs/rdb-location-policy.md`).

**Why block 2 existed at all.** The stock create line `/etc/rdb -c -s 64 -L 2 -d …` — `-L` is
the RDSK block. Disassembly of the stock `/etc/rdb` (md5 `6cacf95f…`): `-L n` stores the block
the RDSK is written at (default 0 in `.data`); the RDB is written with `lseek(n << 9)` and the
PART blocks follow at `n+1…`; and before `-c` runs, the tool scans blocks 0..15 for an existing
RDSK and, if it finds one, **rewrites the RDB where it found it, ignoring `-L`**. Hence the two
populations in the workspace: disks authored onto a *blank* target (the metal goldens, the demo
cards `saku-desktop-*`, the from-scratch base) have RDSK at 2 with blocks 0–1 zero; disks
whose target was pre-minted by `tools/mkroot.sh` (rdbtool, RDSK at 0 — the bench golden,
card-3 060) kept block 0 even though `-L 2` was passed. Blocks 0–1 hold nothing on an Amix
disk: the boot chain is in the `UNI\0` slice, which Kickstart, boot1/boot2 and `sdpart.c` all
reach through the RDB, and all of them scan 0..15.

**What changed.**
- `install.sh` author path: new key `TARGET_RDB_BLOCK` (default **0**; `2` = legacy stock;
  anything else dies). It clears blocks 0..15 (`dd if=/dev/zero … count=16`, past the erase
  guard, below the first partition at block 128) so `-L` is honoured even on a reinstall over
  an old RDSK-at-2 disk, passes `-L "$TARGET_RDB_BLOCK"`, and reads the magic back at byte 0 —
  a miss **dies**. Installer-selftest audit **RB** executes the key's validation and pins the
  clear → create → read-back order.
- `tools/lib/rdb.py` `check_rdsk_location()`: RDSK at block 0, alone in 0..15, checksum closing.
  Enforced by `mkroot.sh`'s read-back gate, `build-raw-source.sh`'s read-back gate, and
  `write-bootchain.py` (refuses an RDSK-elsewhere target; `--legacy-rdb-block` admits one
  loudly). Readers (`find_rdsk`) still scan, so donors and old images read as before.
- `tools/relay-rdb-lba0.py --in SRC --out DST`: converts an existing image. Two 512-byte writes
  (RDSK bytes → block 0, zeros over the old block); nothing else moves because every RDB
  pointer is an absolute block number and none points at the RDSK. Writes a new file only,
  refuses a non-empty front (hybrid / VHD cookie), a non-closing checksum, two RDSK
  authorities, an existing `--out`; verifies the location gate, an identical slice map, and a
  full block compare (only the two touched blocks differ); prints and records
  (`<out>.relay.txt`) RDSK block, slice map, sha256 and crc32 (the firmware's `sd_crc`)
  before/after. `--report IMG` is the read-only census.

## Pieces

| piece | path | role |
|-------|------|------|
| driver | `src/installer/install.sh` | pre-POSIX SVR4 sh; runs on the miniroot |
| first-boot | `payload/firstboot/{firstboot.sh,root.shadow}` | armed into the target; bakes identity on first boot |
| profiles | `profiles/*.profile` | per-rig spec (kernel, CD, disk, first-boot identity) |
| boot slice | `tools/build-bootslice.py` | extracts the gated boot chain + loader + `sum -r` manifest |
| order | `tools/gen-install-order.py` | core-first topological install order from `deps.conf` (base set: `core bsd net text sysadm cdfs APKGENG APKG` — W6.4b; case preserved) |
| ISO re-master | `tools/build-install-iso.sh` + `build-iso.sh --install-src` | assembles `/install/`, masters the disc |
| structural proof | `tools/installer-selftest.py` | run-checks.sh check 8 |

## The disc `/install/` layout (what the driver consumes)

```
/install/bin/pkgadd pkgtrans pkginfo pkgchk   static CD engine (amix-packagemanager)
/install/bin/pkginstall                        static pkginstall  <-- the miniroot shim exec's THIS
/install/bin/sum                               genuine SVR4 sum (from core)  <-- on-target verifier
/install/bin/apkg                              static apkg (optional; NOT in the install loop)
/install/bin/install.sh                        the driver
/install/admin/pkgadd                          permissive pkgadd -a policy
/install/admin/default                         the 183-B stock admin (seeded to the target)
/install/order                                 install order for the MASTERED set (core first)
/install/order.<set>                           one per named set this medium satisfies IN FULL
/install/sets                                  the interview's three-tier menu, as data
/install/profiles/*.profile                    target specs
/install/boot/<profile>/bootslice.img          the boot chain the driver dd's
/install/boot/<profile>/boot2.boot             flags-based /stand/boot2.boot loader
/install/boot/<profile>/bootslice.manifest     sum -r regions for on-target verify
/install/firstboot/{firstboot.sh,root.shadow}  first-boot payload
/install/stand/boot1.boot                      framing source laid to /stand (41892/1024)
/install/stand/makeiblk                        2.1c framing tool laid to /stand (58483/14924)
/install/syslog/syslog.conf                    2.1c syslog unit, laid down by the driver
/install/syslog/syslogd.init                   ... init ENABLED (vendor exit commented)
/install/syslog/syslogd                        ... the 2.1c daemon (53154/22728)
```

The miniroot's `/usr/apkg/sadm/install/bin/pkginstall` shim exec's
`/cdrom/install/bin/pkginstall`, so the static pkginstall MUST live at exactly
`/install/bin/pkginstall` (asserted by `build-iso.sh --install-src`).

## The driver flow

1. **profile** — `install.sh <profile-name | /path/to/answers.profile>` (default
   `bench-a3000-a4091`). A **name** resolves to
   `/cdrom/install/profiles/<name>.profile`; an argument containing `/`, or
   naming an existing file, is taken as a **path** (W1 — the medium is read-only,
   so the W2 interview's `/tmp/answers.profile` needs the path form).
2. **plan** — the stock partition arithmetic (`BREAKPT=120 LGSWAP=30 SMSWAP=18
   BOOTSIZE=2 …`) in `expr`, fed by a real `/etc/ddsize` probe of the target
   unless the profile pins `TARGET_DISK_MB` (W1), with optional
   `TARGET_ROOT_MB`/`TARGET_SWAP_MB` overrides bounded by the stock floors.
   `installer-selftest.py` proves this arithmetic is **byte-identical to
   `tools/mkroot.sh`** across disk sizes, including the BREAKPT boundary, and
   that the overrides unset reproduce that layout exactly.
3. **target-root build** — see *the host/on-box split* below.
3b. **open the install log** (W1) — right after the target root is mounted, the
   driver creates `<target>/var/adm/install.log` and everything from there on is
   persisted to it. The pre-mount window is console-only by nature and the log
   says so in its opening marker.
4. **mount source** — `/usr/lib/fs/cdfs/mount <card>,<unit> /cdrom`, retry-once
   on the errno-5 media-change quirk (a safety net: the driver is launched from
   the already-mounted CD).
5. **seed** — the proven `pkgadd -R` pre-conditions: `<root>/etc/passwd`+`group`
   byte-identical to core's (copied from the miniroot, whose copies ARE core's),
   `<root>/var/sadm/install/admin/default` (the 183-B stock admin),
   `<root>/var/sadm/pkg`, `<root>/tmp` mode 1777, and `TMPDIR` onto the target.
6. **install** — `pkgadd -R /mnt -n -a <admin> -d <pkg> <name>` down the order
   file (core first, Gate 13). The base set is **eight** packages —
   `core bsd net text sysadm cdfs APKGENG APKG` (W6.2 added `cdfs`; **W6.4b added
   `APKGENG` + `APKG`** so an installed box has a working package manager out of
   the box). All three of `cdfs`/`APKGENG`/`APKG` ship under `/pkgs/base/`, and the
   driver resolves each `stock/`-then-`base/`, **case-sensitively** —
   `gen-install-order.py` preserves case (our base packages are uppercase, stock +
   cdfs lowercase) while matching the lowercase `deps.conf` DAG case-insensitively.
   The base-5 subset still produces the continuity tree digest
   `86e1ceb144f1328bf441c5df38fc2798`. The driver installs `APKG` but never
   **invokes** apkg during the install.
6b. **contents-DB integrity check** (W6.4b) — run the CD-resident **static**
   `contents-fsck /mnt/var/sadm/install/contents` (CHECK-ONLY, never `-r`) over
   the freshly built contents DB, **fail closed**: any non-zero exit is a hard
   `die` before first-boot is armed (a fresh DB with findings means the install is
   wrong). It is statically linked, so it runs on the thin miniroot.
6c. **write `/etc/apkg.conf`** (W6.4b) — the driver writes the target's package-
   client config on the miniroot (identity-independent → not first-boot) with
   `repo=$FB_REPO_URL` + `cachedir` + `admin`. W1 de-hardcodes that URL into the
   profile key; its default is the same `http://files.example.net/html/amix`
   literal that used to be in the driver. *(Since 2026-09-14 the default is
   `http://pkg.amigaux.org`; the files.example.net repo is retired.)*
7. **boot2** — overwrite `<root>/stand/boot2.boot` with the flags-based loader
   the medium carries (`f287ff3a…` on the 030 line; the 68040/68060 line's media
   carry `fd7dacf6…`, the contract identity `good_040`, selected per-profile with
   `BOOTSLICE_BOOT2_IDENTITY` — see `profiles/README.md`). core ships the
   name-based `5ab360b1…` loader, which D245/RELA-Guros flags-based ET_REL
   kernels — the same swap the kerntools pipeline does before rebuilding a boot
   partition. The driver copies whatever `build-bootslice.py` gated and shipped;
   the identity decision is made once, host-side, at assembly time.
8. **boot slice** — `dd` the pre-built, gated chain image onto the target's
   UNI\0 boot slice. No chain reconstruction in sh.
9. **verify** — for each manifest region, `dd` it back out of the written slice
   and compare `sum -r` (via the CD-resident SVR4 `sum`) to the shipped value.
   All regions are block-aligned, so reads are `dd bs=512` (no bs=1 crawl).
10. **arm + wire first-boot** (drop the payload + `PENDING`, write the
    `/etc/rc2.d/S16firstboot` hook, and `chmod -x` the stock `system.setup`
    dialog — see *W5.4f* below), **bake the keymap** and **preseed
    `/lost+found`** (both stock steps, restored in W1), then **final fsck +
    summary**.

## The host/on-box split (mkroot.sh ↔ the driver)

`tools/mkroot.sh` authors a target disk **host-side**: partition arithmetic →
`rdbtool` RDB → `s5` mkfs → read-back gate → `layout.json`. The driver does the
**on-box** equivalent with the miniroot's own tools. Two supported modes:

> **Since P-35 (2026-10-30) only author mode exists, and it lays ufs**
> (`/bin/mkfs_ufs`); the prebuilt mode below is retired and the driver refuses it.
> The text below is the record of how both modes came to be.

- **author** (default): the driver partitions + `mkfs_s5` the blank target with
  `/etc/rdb` + `/bin/mkfs_s5` + `/usr/lib/fs/s5/labelit`, using the stock
  installer's exact `/etc/rdb -c` / `-a` / `-p -F` / `mkfs_s5` command sequence.
  `/etc/rdb`'s **create/geometry** primitive was the one on-box unknown; it is
  **closed** — found wrong as shipped by the `cd-author` matrix cell on 2026-07-30
  (*"-c requires -d disksize"*), fixed and driven to a green 9/9 `cd-author` run on
  2026-07-31, together with two further defects the same path was hiding (`-p` was
  handed a device path instead of a partition number; `mkfs_s5` was handed half the
  slice). Semantics, evidence and proof: *What the author cell found* above.
  **Author mode reproduces the canonical digest from a blank-slate on-box build**;
  the prebuilt path below is still the one every metal install has used.
- **prebuilt** (`INSTALL_TARGET_PREBUILT=1`): the target was fully built
  host-side by `tools/mkroot.sh` (RDB + s5 root, read-back-gated); the driver
  skips authoring/mkfs and only fscks + mounts. **This is the low-risk path
  recommended for the W5.4 canonical run** — `mkroot.sh` is proven, has its own
  read-back gate, and runs identically for metal.

## Two admin files (deliberate)

- `/install/admin/pkgadd` — **permissive** install-time policy (`instance=overwrite`,
  all `nocheck`), passed to `pkgadd -a`. Non-interactive, no prompts/stalls.
- `<target>/var/sadm/install/admin/default` — the **183-B stock** admin (all
  `ask`, `mail=root`) the finished system carries. Seeded from
  `/install/admin/default`. core would install it anyway; seeding makes the
  target's `/var/sadm/install/` structurally complete before the first pkgadd.

## First-boot tool exceptions (`sed`, `uname`) — evidence-backed

`payload/firstboot/firstboot.sh` runs on the **fully installed target** (core + the
base set already transplanted), not on the thin miniroot, so the complete SVR4
userland is present. `tools/installer-selftest.py` reflects this with a
per-script allowlist split: `install.sh` gets the **strict** miniroot allowlist
(no extras, `DRIVER_EXTRA=set()`), while `firstboot.sh` is granted the documented
`FIRSTBOOT_EXTRA = {sed, uname, true}` — tools the miniroot itself lacks but the
installed target carries. Those two tool references are **evidence-backed**: both
are members of the first-installed package, `core` (`core-2.1.pkg`), confirmed in
its pkgmap (`build/repo-staging/stock/.t/core/…/pspool/core/pkgmap`):

| tool | pkgmap entry | package |
|------|--------------|---------|
| `sed`   | `1 f none /usr/bin/sed 0555 bin bin` (SVR4 sum 63259) | `core` |
| `uname` | `1 f none /sbin/uname 0555 bin bin` (sum 60566) + symlink `1 s none /usr/bin/uname=/sbin/uname` | `core` |

Because `core` is the **first** `pkgadd -R` in the install order (Gate 13,
core-first), `sed` and `uname` are on the target long before its first multiuser
boot runs `firstboot.sh`. (`true` is a shell builtin on the target `/bin/sh`.)

## On-target boot-chain verification: why `sum` ships on the CD

The miniroot has **no** `od`, `cmp`, or `sum`. The on-target check needs a
genuine SVR4 `sum -r` (the family's canonical checksum). Rather than rebuild the
boot-proven miniroot to add `/bin/sum` (a proto amendment + a re-boot-proof),
the driver uses the genuine **core `/usr/bin/sum` shipped on the CD** at
`/install/bin/sum`. It is dynamically linked against `/usr/lib/libc.so.1`, which
the miniroot has (`miniroot.proto`), so it runs there. This keeps the miniroot
**untouched** and is fully self-contained on the disc. (The manifest sums are
generated host-side by `tools/lib/sumr.py`, the BSD-`sum -r` algorithm; proven
equal to the box's `sum -r` first field — `docs/install-iso.md` E1.)

*Alternative, not taken:* add `/bin/sum` to `miniroot.proto` and rebuild the
miniroot. Cleaner conceptually (the driver's verifier lives on the miniroot), but
it forces a miniroot rebuild + re-boot-proof for no functional gain, and the CD
already carries the same binary.

## Re-mastering

```
tools/build-install-iso.sh --profile bench-a3000-a4091 --profile metal-a4000-z3660
```

assembles `work/install-tree/` (engine + sum + admin + order + profiles + boot
slices + first-boot + driver) and masters the disc via `build-iso.sh
--install-src`. The disc stays **gitignored** (never committed; publishing it is a
per-artefact owner decision); the release gate refuses a tracked path. All Wave-4 gates (8 catalog / 9 name / 17 licensing) re-fire on
the re-mastered disc.

## W5.4d folds the driver hardening + the engine-side pkgadd fix together

`work/iso/amix21-install-base-w54{b,c}-20260722.iso` were mastered from the driver
**before** the W5.5b host-only hardening: the `basename`/`sed`/`touch` purge (the
miniroot carries none of them), the **fail-closed** boot-chain verify (W5.4c saw
`sed` absent and printed vacuous per-region OKs on empty-vs-empty), and the
`installer-selftest.py` miniroot-tool allowlist regression armor. The **W5.4d**
re-master folds those in together with the resolution of the old miniroot
`pkgadd -R` blocker, which is now fixed **engine-side**, not in the driver:

- **pkgadd -R blocker (RESOLVED engine-side; hardened driver-side in METAL-FIX.2).**
  amix-packagemanager `0d3a21c` makes `get_mntinfo()` **synthesize** the `/` root
  entry when `/etc/mnttab` lacks one, so `pkgadd -R /mnt … core` resolves the target
  root with only the cdfs line present; `3b9b7a1` (METAL-FIX.1) extends that to a
  wholly **absent** file (ENOENT → synthesize). The driver's `/etc/mount` writes no
  mnttab entry. **Reversed by METAL-FIX.2:** engine tolerance alone is *not* enough
  on fresh media — a freshly built miniroot ships **no `/etc/mnttab` at all**, and
  pkgadd/apkg `open()` it before installing, so the transplant aborts with `ERROR:
  unable to open mount table (/etc/mnttab)` (M-RUN froze exactly here). The seed step
  now writes the `/` root line **unconditionally** (`echo "/dev/root / s5 rw 0" >
  /etc/mnttab`, OVERWRITE). A `/mnt` line does NOT satisfy `get_mntinfo` (shortest
  mount point must be `/`). See **“## METAL-FIX.2”** at the end of this doc.
- **Stale-CD guard (W5.5a).** The boot-time cdfs `/cdrom` mount can come up rc=0
  but EMPTY, with no errno-5 unit-attention to retry on. The driver now verifies
  `/cdrom/catalog` after the mount step and, if unreadable, does a best-effort
  `umount` + one re-mount before a hard STOP.

The W5.4d re-master ships the **fixed static engine** (`pkgadd`/`pkgchk`/`pkginstall`
rebuilt from `0d3a21c`) at `/install/bin/`.

## W5.4e: subshell-safe loop counters (the last driver defect)

The W5.4d on-box run was green on everything upstream — 5/5 `pkgadd -R` rc=0, all
three boot regions read back with the right `sum -r` — yet it aborted before arming
first-boot. Root cause: the miniroot's **1991 SVR4 `/bin/sh` runs a
`while read … ; do … ; done < FILE` loop in a SUBSHELL**, so a variable mutated
inside the body reverts to its pre-loop value at `done` (host-repro-confirmed: a
modern `sh` keeps the counter; an explicit `( … )` wrapper reproduces the box). Two
loops were bitten:

- the **pkgadd loop** — `npkgs` reset to 0, so the summary said "installed **0**
  package(s)" while all five packages sat in `<target>/var/sadm/pkg`; and worse, an
  in-loop `die` would have killed only the subshell, letting the parent arm a
  half-installed disk;
- the **boot-chain verify loop** — `vok`/`vfails` reset to 0, so after three real
  `OK` lines the aggregate guard `[ "$vok" -gt 0 ]` false-fired ("checked ZERO
  regions … refusing to arm") and the driver stopped.

**Fix (subshell-safe idiom).** Each redirect-fed loop now records to append-only
temp **files** inside the body (`echo … >> $t`, which survive the subshell) and
every go/no-go decision is made **after** the loop, in the parent, counting tokens
with `set -- \`cat $t\`; n=$#` (no `wc` — the miniroot lacks it). The fail-closed
semantics are unchanged and now count correctly: a boot region that fails still
hard-fails, zero verified regions still hard-fails, and any `pkgadd` failure (or a
package missing from the disc) is recorded and hard-fails the whole install after
the loop instead of silently continuing.

`installer-selftest.py` **audit H** locks the pattern out: it flags any
`done < FILE` loop whose body assigns a variable referenced after the loop
(negative fixtures reproduce the exact W5.4d `npkgs`/`vok` shapes), and passes the
temp-file idiom. NB the self-test's `_strip_quotes` runs before inline-comment
stripping, so **inline comments must not contain a stray apostrophe** (it opens a
phantom single-quote span) — a lesson from armoring this fix.

**Second-order trap: `set --` with an empty arg list (W5.4e bench run 1).** The
first re-master's `pkgadd` count was correct (5) but the boot-chain verify
false-failed with "FAILED (3 region(s))" *after* printing three `OK` lines. Root
cause: the post-loop count `set -- \`cat FILE\`; n=$#` is a TRAP on the miniroot
sh — an **empty** `set --` is a **no-op** on `$@` there (confirmed on-box:
`set -- a b c; set -- \`cat /dev/null\`` leaves `$#=3`), so counting the empty
`vfails` file returned the stale `vok` count (3). The fix is the `count_tokens`
helper: `[ -s FILE ]`-guard so `set --` is only ever fed a non-empty list (empty →
0 without touching `$@`). **Audit I** flags any unguarded `set -- \`cmd\`` count in
the driver. With `count_tokens` the full acceptance is green: 5 `pkgadd` rc=0,
"boot chain verified on-target (3 region(s))", first-boot armed, final fsck clean,
"packages installed : 5"; host-side the installed tree digest is
`86e1ceb144f1328bf441c5df38fc2798` (4793 objects) and `bootchain-verify` PASSes
(flags-based `f287ff3a` boot2).

## W5.4f: WIRE first-boot into the target init (the last Wave-5 gap)

W5.4e was the first run to get *past* the boot-chain verify and cold-boot the
target, and it surfaced the last defect: the payload was **armed** (all of
`/var/adm/firstboot/{firstboot.sh,root.shadow,firstboot.conf}` + `PENDING` present
with `FB_NODENAME=uaeamix …`) but **nothing in the stock target init invoked it**.
On cold boot #1 the *stock* dialog ran ("What is the nodename of this machine?
[localhost]"), `PENDING` remained, `/etc/nodename` stayed `localhost`.

### The stock mechanism (read off an s5 dump of the installed target)

`/etc/inittab` runs the identity-setup at **sysinit**, before run level 2:

```
S2::sysinit:/etc/sysinit </dev/syscon >/dev/syscon 2>&1
...
s2:23:wait:/etc/rc2 >/dev/console 2>&1 </dev/console      # (later in the file)
con:123:respawn:/etc/getty console console                # (later still)
```

`/etc/sysinit` (a `core` member) contains, verbatim:

```
# Perform installation configuration, if needed
if [ -x /usr/amiga/bin/system.setup ]
then
    sh /usr/amiga/bin/system.setup
fi
```

`system.setup` sources `/usr/amiga/lib/amixnode` — the "What is the nodename…?"
prompt — plus hosts/date/password/monitor dialogs, and **ends with**
`chmod -x /usr/amiga/bin/system.setup`: its **own once-only disarm**. So the stock
dialog is gated by exactly one thing — the **execute bit on `system.setup`** — and
it fires at *sysinit*, i.e. **before** run level 2 and the console getty. Baking a
nodename does *not* suppress it (the script prompts unconditionally); only clearing
the `-x` bit does.

### The wiring (two moves, both in `install.sh`'s arm step)

1. **Disarm the stock dialog** — `chmod -x` the target's
   `/usr/amiga/bin/system.setup` (the stock's own once-only lever). Mode-only;
   content/cksum untouched. This is the **single package-file touch** of the whole
   install and it is the intended end-state of any configured Amix box. Because
   `altroot-attest` is a pure function of the `pkgadd` **contents DB** (owner/group
   resolved through the target name service — it never lstats live modes), the
   digest `86e1ceb144f1328bf441c5df38fc2798` (4793 objects) is **unaffected**.
   *(Editing `/etc/sysinit` or `/etc/inittab` content instead was rejected: both
   are checksummed `core` members — `1 f none … 0755 bin bin` / `0664 root sys` —
   so a content edit dirties `pkgchk`, whereas a mode bit on a script the box is
   meant to retire does not perturb the contents DB.)*
2. **Add the rc2 hook** — the driver **writes** `/etc/rc2.d/S16firstboot` (a NEW,
   non-package file; `emit_firstboot_hook`), which runs `firstboot.sh` iff
   `PENDING` exists. `/sbin/rc2` runs each `rc2.d/S*` via `/sbin/sh S* start`, and
   `/etc/inittab` runs `s2:…:wait:/etc/rc2` to **completion** before spawning the
   `con` getty — so identity is baked (and `PENDING` removed) **before** the login
   prompt appears. Placed at `S16` (after `S15mkdtab`, before `S69inet`), so
   nodename/hosts are set before networking starts.

The hook is **driver-written, not shipped on the CD** and not staged by
`build-install-iso.sh`; it never reaches the `pkgadd` contents DB. `firstboot.sh`
does the `rm -f "$MARK"` disarm, so cold boot #2 is a clean no-op.

`installer-selftest.py` **audit J** locks this: the arm step writes the rc2 hook
and disarms `system.setup`; a **drift-lock** extracts the driver's
`emit_firstboot_hook` and re-runs it, asserting it reproduces the tracked
`payload/firstboot/S16firstboot` byte-for-byte; the hook is pre-POSIX + parses +
references only target-present tools (`/sbin/sh`); and `firstboot.sh` removes
`PENDING`.

## W5.4 runbook (the end-to-end run)

- **Rig:** the canonical `bench-a3000-a4091` profile — Amiberry, A3000+A4091,
  KS2.04/ECS, 68030, **64 MB** Fast RAM (the standing bench value; the old "16 MB
  Amix ceiling" was inherited, never measured — the real limit is the frame-arena
  law, ~80 MB networked max on metal).
- **Media:** the fd0/miniroot install kernel + root (W5.2), a **blank target
  disk on the A3000's onboard SCSI at id 6** (`scsi6_a3000` → `c6d0`; use
  `tools/mkroot.sh` to pre-build it and run the driver with
  `INSTALL_TARGET_PREBUILT=1` — the low-risk path), and the re-mastered install
  CD on the **A4091** at cdfs `1,3`. **W5.4b established the split:** the `cXd0`
  block namespace binds to the *primary* (A3000) SCSI, not the A4091 — the target
  must hang off the A3000 controller to answer at `c6d0`; the A4091 carries only
  the CD (by card index).
- **Steps:** boot the miniroot → `/usr/lib/fs/cdfs/mount 1,3 /cdrom` (errno-5,
  retry) → `sh /cdrom/install/bin/install.sh bench-a3000-a4091` → halt →
  boot the target (`c6d0`).
- **Expected:** 5 `pkgadd -R` all rc=0; installed tree digest
  **`86e1ceb144f1328bf441c5df38fc2798`** (the Wave-2/3 reference); boot chain
  verified on-target; first boot bakes `uaeamix` identity and reaches multiuser.
  *(These figures are W5.4-era and left standing per the wave convention — the
  shipped set is no longer five packages; for what a run must reproduce today see*
  **Canonical digests — current** *at the top.)*
- **W5.4b diagnostic evidence (the target-HBA fix):** with the target on
  `scsi6_a3000`, `dd if=/dev/rdsk/c6d0s0 bs=512 count=8` → `8+0 records in/out`
  and `/bin/fsck_s5 /dev/rdsk/c6d0s1` → Phases 1–5 clean; the identical rig with
  the target on `scsi6_a4091` failed both (`Can't open` / I/O error, `0+0
  records`). The `rootdev` `0x00480016` (`c6d0s1`) is therefore correct as shipped.
- **Confirm on-box (author mode only, still open):** the exact `/etc/rdb`
  create/geometry primitive — W5.4b validated the install via the recommended
  `INSTALL_TARGET_PREBUILT=1` prebuilt path, which does not exercise author mode.
  *(Wave text left standing per the document convention. **Answered 2026-07-30** by
  the `cd-author` matrix cell: the miniroot's `rdb` needs `-d size` and refuses the
  driver's `-c -s 64` line — and **CLOSED 2026-07-31**: `-d` is the disk length in
  512-byte blocks, the driver is fixed, and `cd-author` is green end-to-end. See*
  **What the author cell found** *above.)*

## W6.2: `cdfs` joins the base set + the first-boot TZ fix

Two Wave-6 outcomes integrated and proven end-to-end from a pristine target.

> **Historical.** The `BASE_SET` arrays this section and the W6.4b one below
> describe were **deleted by W3b** — set membership now comes from
> `../amix-packagemanager/tools/repo/sets.conf` through its own resolver. The
> *content* of the base-8 set is unchanged (that is the point: `sets.conf`'s
> `minimal` is these eight packages, in this order). See
> "W3b: multi-set package selection goes live".

- **`cdfs` in the base set (six packages *at W6.2*; eight since W6.4b).**
  `build-install-iso.sh`'s `BASE_SET`
  becomes `core bsd net text sysadm cdfs`. `cdfs` (the `/usr/lib/fs/cdfs/mount`
  helper + `/cdrom` mount point; the kernel side already ships in `core`) is our
  own package under `repo-staging/base/`, so its `.pkg` rides onto the disc via
  `build-iso.sh`'s `base/*.pkg` glob — it is **not** added to `build-iso.sh`'s
  `BASE_SET` (that array selects `stock/` packages by name and would STOP on a
  missing `stock/cdfs-*.pkg`). Naming it in the **install-order** `BASE_SET` is
  what makes the driver run the 6th `pkgadd -R`; `deps.conf`'s `cdfs: core` edge
  keeps it ordered after `core`, and the driver resolves it `stock/`-then-`base/`.
  Result: an installed box can `mount -F cdfs <card>,<unit> /cdrom` with the full
  mount front-end + our userland — no miniroot required.
- **The first-boot TZ fix (W6.3).** `firstboot.sh` wrote `TZ=US/Eastern` to
  `/etc/TIMEZONE` **without** the leading colon. SVR4 `ctime`/`tzset` only reads a
  tzfile when `TZ` is `:<pathname>`; the colon-less string is parsed as a POSIX
  rule, walks off into garbage, and every consumer (`date`, `who -r`, `ls -l`,
  `cron`, `sac`) takes a **BUS ERROR at 474D5400** on cold boot — and the crashed
  `who -r` cascades into the rc2 `test: unknown operator S` errors. The one-byte
  fix `TZ=:US/Eastern` maps to `/usr/lib/locale/TZ/US/Eastern` (present, and
  byte-identical to the golden's); `date`/`who -r`/`ls -l` all work and the rc2
  errors vanish. `installer-selftest.py` audit F now fails closed on the
  colon-less form. (Refuted along the way: not a `passwd`/`getpwnam` issue — `id
  root` survives the colon-less TZ.)
- **Digests.** The base-5 subset digest is **unchanged** —
  `86e1ceb144f1328bf441c5df38fc2798` (4793 objects) — proving continuity. The full
  **six-package** installed-tree digest `29a1ae6192e4c64947a0cd14f9bfd149` (4796
  objects) was recorded as the Wave-6 reference here, in `CHANGELOG.md` / the W6.2
  report. **It is superseded** — the base set grew to eight at W6.4b/c and the
  current canonical is `e483b0cb25dfaf4087b1f783335d520d` (4859 objects, re-attested
  2026-08-11; it was `ec31a72291e01382ab4b97403f6dad13` from W6.4c until then). See
  *Canonical digests — current*.

## W6.4b: installer completeness — the package client, out of the box + a fail-closed contents-DB gate

Two completeness gaps closed so a freshly installed box is a *finished* system:
it carries a working package manager and its contents DB is proven intact before
the disk is ever armed to boot.

### The package client rides the base set (eight packages)

`build-install-iso.sh`'s `BASE_SET` becomes
`core bsd net text sysadm cdfs APKGENG APKG`. `APKGENG` (the heirloom pkg engine)
and `APKG` (the remote client) are our own `repo-staging/base/` packages, so — like
`cdfs` — their `.pkg` files already ride the disc via `build-iso.sh`'s `base/*.pkg`
glob; naming them in the **install-order** `BASE_SET` is what makes the driver
`pkgadd -R` them. `deps.conf`'s `apkg: apkgeng` edge orders **APKGENG before APKG**.

**Case.** Our base packages are **uppercase** (`APKG`, `APKGENG`); stock + `cdfs`
are lowercase. The driver passes each order line verbatim to a case-**sensitive**
`pkgadd -d <file> <NAME>` and resolves a case-sensitive `pkgs/{stock,base}/<NAME>-*.pkg`
glob on the Rock-Ridge disc. So `gen-install-order.py` now **preserves the caller's
original spelling** in the emitted order while matching the lowercase `deps.conf`
DAG **case-insensitively** — a lowercased `apkg` would match neither the `.pkg` file
nor the SVR4 instance name. (All-lowercase selections are byte-unchanged: `orig ==
canonical`, so the base-6 order is identical.)

### libnsl precondition (why no extra package is needed)

The **APKG** package delivers the **dynamic** apkg (`/usr/apkg/bin/apkg`,
interpreter `/usr/lib/libc.so.1`). Its `NEEDED` list (cross `objdump -p`) is exactly
`libnsl.so` + `/usr/lib/libc.so.1`. **Both are `core` members** —
`/usr/lib/libnsl.so` is `1 f none /usr/lib/libnsl.so 0664 root root` in `core`'s
pkgmap (and the contents DB attributes it to `core`), and `libc.so.1` is the base C
library. `core` is first in the set, so the dynamic apkg's runtime deps are
satisfied with **no extra package added**.

### The contents-DB integrity check (fail closed)

After the `pkgadd -R` loop and **before** arming first-boot, the driver runs the
CD-resident **static** `contents-fsck /mnt/var/sadm/install/contents` (CHECK-ONLY,
never `-r` repair). It is statically linked (`objdump -p` shows no `NEEDED`), so it
runs on the thin miniroot with no libc/libnsl dependency. **Fail closed:** `exit 0
= clean`, `1 = findings`, `2 = error`; **any non-zero is a hard `die`** — the arm
must never run on a bad contents DB (a *freshly built* DB with findings means the
install itself is wrong). `contents-fsck` joins the frozen CD engine set staged into
`/install/bin` by `build-install-iso.sh` (`sum -r 23366`, 29468 bytes); the
re-master prints a staged-engine sum table. `installer-selftest.py` **audit K**
locks the call fail-closed (no `|| true` softening; a `die` on the non-zero branch;
CHECK-ONLY) and ordered after the pkgadd loop / before the arm step; a negative
fixture proves a softened `contents-fsck … || true` is caught.

### `/etc/apkg.conf` — the driver writes it (overwrite, with evidence)

The **APKG** package already ships a default `/etc/apkg.conf` (class `e`, editable)
whose `repo=` line is exactly the live repo. The driver nonetheless **writes**
`/etc/apkg.conf` post-install (`repo=http://files.example.net/html/amix` — `http://pkg.amigaux.org`
since 2026-09-14 +
`cachedir=/var/apkg/cache` + `admin=/var/apkg/admin`, matching the package's fields),
**deliberately overwriting** the package copy. Rationale (overwrite, not respect):

- it makes "the installed box's client points at the live repo" a **driver-guaranteed
  invariant**, provable in the s5 check, rather than contingent on `pkgadd`'s
  editable-file placement (which our install contract never verifies);
- `/etc/apkg.conf` is a class-`e` **editable** member, so `pkgchk` exempts it from
  content verification — a post-install edit is the SVR4-sanctioned mechanism and
  does not dirty `pkgchk`;
- the **contents-DB digest** is a pure function of what `pkgadd` *recorded* (the
  package's shipped cksum), not the live bytes, so overwriting the file leaves the
  full-set digest deterministic.

It is written on the **miniroot** against the mounted target (identity-independent),
**not** at first-boot, with `echo` + redirection only (allowlist-clean). Gated on
`[ -x <root>/usr/apkg/bin/apkg ]` so a future APKG-less set skips it cleanly.

### Digests

The base-5 continuity digest is **unchanged** — `86e1ceb144f1328bf441c5df38fc2798`
(4793 objects) — via `altroot-attest --only core,bsd,net,text,sysadm`. The full
**eight-package** installed-tree digest `a2467c6958dba203d399c4441d77f338` (4858
objects) was the W6.4b canonical, recorded in `CHANGELOG.md` / the W6.4b report.
It stood for exactly one wave: W6.4c's `/usr/bin/apkg` symlink adds the 4859th
object (below), giving the **current** canonical.

## W6.4c: repo-host baking — the package manager, *zero-touch* out of the box

W6.4b proved `apkg update` works over the network, but only after a **manual**
`/etc/inet/hosts` edit: the fresh box has no DNS on the bench LAN, and `firstboot.sh`
baked only the box's **own** nodename (`§5`), so it could not resolve the repo host
(`files.example.net`) that `/etc/apkg.conf`'s `repo=` names. W6.4c closes that last
manual step so a fresh install runs `apkg update` with **zero** hand-holding.

### The mechanism (spec-driven, three seams)

1. **Profile** — each profile carries a paired **`FB_REPO_HOST` + `FB_REPO_IP`**
   (bench + metal both `files.example.net` / `192.0.2.2` — the NAS serving
   `/html/amix` on the shared LAN, matching the `repo=` in the driver-written
   `/etc/apkg.conf`; *since 2026-09-14 both are `pkg.amigaux.org` / `52.59.174.203`*). They ride the same profile→`firstboot.conf` plumbing as
   `nodename`/`tz`/`FB_IP`.
2. **`install.sh`** — the arm step writes `FB_REPO_HOST` + `FB_REPO_IP` into the
   target's `/var/adm/firstboot/firstboot.conf` (empty when a profile carries no
   repo).
3. **`firstboot.sh` (`§5b`)** — at identity-bake time, appends
   `"<FB_REPO_IP>	<FB_REPO_HOST>"` to `/etc/inet/hosts` (the **same** file and the
   **same** rule as `§5` — **never** `network-config`). It is:
   - **guarded** — both vars must be non-empty; either empty ⇒ **skip, but log**
     (`"no repo host in profile … skipping"`). A profile without a repo is legal.
   - **duplicate-safe** — a `sed` line-strip removes any prior line naming the repo
     host (as a whitespace-delimited token) **before** appending exactly one, so a
     re-run (or a host already present) can never accumulate duplicate lines.
   - **allowlist-clean** — `sed`/`echo`/`mv` only (all already on the target;
     `firstboot.sh`'s documented `FIRSTBOOT_EXTRA`), pre-POSIX-safe.

With the repo host resolvable, bare **`apkg`** (the `/usr/bin/apkg` symlink the
W6.4c APKG mint adds, on the default `PATH`) runs `apkg version` / `apkg update` /
`apkg list` on cold boot #1 with no manual prep.

`installer-selftest.py` **audit L** locks all three seams: `firstboot.sh` appends
the repo host under a two-var guard, strips duplicates first, and logs-and-skips
when empty; `install.sh` passes both vars through `firstboot.conf`; the profiles
carry them **paired** (bench pinned to the canonical values). It **fires on a
missing `firstboot` append whenever a profile carries the vars** (no dead-letter
bake), with a negative fixture proving the append check fires.

### Digests

The base-5 continuity digest stays `86e1ceb144f1328bf441c5df38fc2798` (via
`altroot-attest --only core,bsd,net,text,sysadm`). The W6.4c **APKG** mint adds the
`/usr/bin/apkg` **symlink** (an `s` entry in the contents DB), so the full
eight-package installed-tree digest shifts by exactly that one object versus W6.4b:
**`ec31a72291e01382ab4b97403f6dad13`** (4859 objects, `a2467c69…`+1). That was the
canonical from W6.4c onward, and every arm and medium of that era (cdfs, RAW, metal
M-RUN2/M-RUN3, the P1.1e parity run) reproduced it exactly. Also recorded in
`CHANGELOG.md` / the W6.4c report. **It was superseded on 2026-08-11** by
`e483b0cb25dfaf4087b1f783335d520d` (same 4859 objects) when the P5.4 r3 `APKG`/
`APKGENG` re-mints reached freshly mastered media — see *Re-attestation 2026-08-11*.
The object arithmetic in this section is unaffected: the r3 change is recorded sizes,
not membership.

## W6-RAW.1: the RAW source arm (the metal path under the no-burn rule)

Everything above sources the base packages from a **cdfs CD** mounted at `/cdrom`.
The **RAW arm** adds a second source medium — a **raw distribution slice** driven by
the CD-resident static **apkg** (`SRC_RAW`) — so the installer's metal path (a
bootable install disk, no CD burned) can be exercised on the bench. **The proof is
digest identity across media**: the same base set installed from a raw slice must
reproduce the **byte-identical** installed tree the cdfs arm produces. Only the
source medium changes.

### The source dimension (`SOURCE_KIND`)

Profiles gain a `SOURCE_KIND` key — `cdfs` (default; every pre-W6-RAW.1 profile is
cdfs) or `raw`. `install.sh` reads it, validates it, and **fails closed on an
unknown kind**. The two source kinds require different profile keys:

| key | `cdfs` | `raw` |
|-----|--------|-------|
| `CD_SPEC` | required (`card,unit`) | — |
| `SRC_SCSI_ID` / `SRC_PAYLOAD_SLICE` / `SRC_RAW_SLICE` | — | required |

The driver branches in exactly two places — **§3 mount/verify the source** and **§5
install the base OS**. Everything else (seed, contents-fsck gate, `/etc/apkg.conf`
write, boot-slice `dd`, on-target boot-chain verify, first-boot arm) is
**source-kind-independent** and byte-unchanged: it all reads from `/cdrom/...` paths,
and in the RAW arm `/cdrom` is the payload slice, so those paths still resolve.

### The two-slice source disk (resolved layout)

`bench-a3000-a4091-raw` sources from a **second disk at A3000 SCSI id 5** (`c5d0`,
the Wave-3-proven raw device), authored by `tools/build-raw-source.sh`:

| slice | dostype | contents | how the driver uses it |
|-------|---------|----------|------------------------|
| **1** | `UNI\1` (s5) | the **`/install` payload tree** — the *same* tree `build-install-iso.sh` stages | mounted **at `/cdrom`** (`/etc/mount /dev/dsk/c5d0s1 /cdrom 0 s5`) so every `/cdrom/install/...` path is byte-unchanged and the miniroot pkginstall shim's hard-coded `/cdrom/install/bin/pkginstall` still resolves — **no proto churn, no re-boot-proof** |
| **2** | `DATA` | the **raw distribution** `raw.img` (apkg self-describing layout) | apkg's `raw.conf` names it `repo=raw:/dev/rdsk/c5d0s2` |

> **Wave-3 archaeology note.** The retired `amix-packagemanager/build/wave3/deploy/`
> holds a `raw.conf` that says `c5d0s1` **and** `ddraw*.sh` scripts that wrote
> `c5d0s0` — an unresolved conflict. Neither is copied. `build-raw-source.sh`
> **defines** the fresh layout (payload = slice 1, raw = slice 2) and the profile,
> the driver's `raw.conf`, and the builder all derive the devices from the same
> `SRC_*` keys, so they cannot diverge.

Because `/cdrom` is the payload slice and the raw slice carries no filesystem, the
RAW arm has **no `/cdrom/pkgs`** and **no `/cdrom/catalog`** — the packages come
straight out of the raw slice via apkg, byte-addressed by the catalog's offset
column (`RAW_DATA_OFF = 65536`, then each package at its 512-aligned offset).

### `apkg` drives the *same* pkgadd (`SRC_RAW`)

The RAW branch of `§5` replaces the per-file `pkgadd -R` loop with the CD-resident
static apkg driving the **same** engine into the **same** target:

```sh
# raw.conf (written on the target's tmp — writable, real headroom):
repo=raw:/dev/rdsk/c5d0s2          # the raw distribution slice
cachedir=/mnt/tmp/apkgcache/cache  # disk-backed, on the target (double-materializes)
admin=/cdrom/install/admin/pkgadd  # the SAME permissive install-time admin
pkgadd=/cdrom/install/bin/pkgadd   # the SAME CD-resident static pkgadd

apkg -c raw.conf update                              # catalog out of the raw slice (byte 0)
apkg -c raw.conf -R /mnt install <order-file tokens> # stage+md5-verify each, then pkgadd -R
```

**The two roots (`../amix-packagemanager src/apkg/conf.c`).** `-R /mnt` is the
**install target** — it prefixes only the `/var/sadm/pkg` "is it installed?" DB and
passes through to `pkgadd -R`. `APKG_ROOT` is the **client's own root** and **stays
unset** — the engine runs *from* the payload slice and installs *into* the target;
pointing the client root at the target would be the classic bootstrap bug. The
conf's `cachedir`/`admin`/`pkgadd` are **literal** (never `APKG_ROOT`-prefixed), so
they name absolute payload/target paths directly. md5 verification and byte-offset
extraction come **for free** — apkg's `src_stage` does both. The branch **fails
closed**: a nonzero rc from `apkg update` *or* `apkg install` (apkg stops on the
first `pkgadd` failure) hard-`die`s — the disk is never armed half-installed.

The apkg install list is the **order-file tokens verbatim**. That works because the
raw catalog's **names match the tokens exactly**: `build-raw-source.sh` writes a
`names.conf` that **preserves the uppercase pkginst case** (`APKG`, `APKGENG`), so
`apkg install APKG` finds catalog name `APKG` (apkg's `catalog_find` matches on
`name`). The lowercase-named packages (`core`…`cdfs`) map to themselves.

### `tools/build-raw-source.sh` (two phases)

There is **no host-side s5 writer that populates files** (`s5.py` mints only *empty*
filesystems — see `build-miniroot.sh`'s header), so the builder splits:

1. **`--author`** (host, box down) — authors the RDB (`rdbtool`) with an **empty s5**
   payload slice (`s5.py`) + a `DATA` raw slice, runs
   `gen-catalog.py --raw` over the 8-package set to pack `raw.img`, writes `raw.img`
   into the raw slice at its byte offset, and **gates**: slice-map read-back
   (`rdb.py`, the `sdpart.c` walk), the payload s5 parses (`s5.py`), and the raw
   slice **starts with the catalog at offset 0** (the `SRC_RAW` contract). It also
   emits a host `sum -r` manifest of every payload file.
2. **`--populate`** (box up, `.hdf` attached) — `fsck`+mounts the payload s5 on a
   full-Amix box, `cpio`s the `/install` tree in (modes preserved), `sync`/`umount`/
   `fsck` clean, then re-mounts read-only and emits a per-file `sum -r` manifest
   **off the built slice**, which the tool compares byte-for-byte to the host
   manifest. (The box is the "s5 reader" — `s5.py` reads only metadata/small files,
   so a real content gate needs the box's `sum`.) s5.py-authored s5 filesystems are
   **proven to mount rw on Amix** — W5.4b mounted a mkroot-prebuilt s5 root — so this
   is a known-good path.

`build-install-iso.sh` gained a **`--stage-only`** flag (stage `/install/`, master
no ISO); `build-raw-source.sh` calls it so the payload slice carries the *identical*
tree the CD arm ships.

### s5's 14-char filename limit (bench finding, W6-RAW.1)

The payload slice is **s5**, and Amix s5 is the classic System-V filesystem with a
**14-character filename limit** (`DIRSIZ=14`; confirmed on the box — `bootslice.manifest`
lands as `bootslice.mani`, and the three long profile filenames truncate, with the two
`bench-a3000-a4091*.profile` even **colliding** at `bench-a3000-a4`). The CD arm's
ISO9660+RockRidge carries long names fine, but on s5 they break — and the driver reads
the profile and the boot-slice manifest **by name**. This is why `build-raw-source.sh`
makes the payload tree **s5-safe** before populating: it keeps **only the target
profile** (as a `≤14`-char `raw.profile`), renames `bootslice.manifest` →
`bootslice.man`, patches the profile's `BOOTSLICE_MANIFEST` key to match, and **fails
closed** on any staged filename `>14` chars. So the acceptance runs **`install.sh raw`**
(the on-slice profile filename), not `install.sh bench-a3000-a4091-raw`; the profile's
`PROFILE_NAME` is still the descriptive `bench-a3000-a4091-raw`. This adaptation is
confined to the s5-authoring tool — the CD arm and the tracked profiles are untouched.

### Digests

Same content, different medium ⇒ **same digests**. **Bench-proven (W6-RAW.1, Amiberry,
16 MB):** a full pristine→install→cold-boot run reproduced the eight-package canonical
**`ec31a72291e01382ab4b97403f6dad13` (4859 objects)** — **byte-identical to the cdfs
arm's** — and the base-5 continuity digest **`86e1ceb144f1328bf441c5df38fc2798`** (via
`--only core,bsd,net,text,sysadm`). That identity, reproduced across two source media,
*is* the whole proof. The install ran the 8 packages via apkg `SRC_RAW` (`rc=0`),
contents-fsck clean, boot chain verified on-target, first-boot armed; cold boot #1
reached multiuser with the `uaeamix` identity and a **zero-touch `apkg update`** over
the network (`catalog updated: 31 packages`), cold boot #2 confirmed once-only. The RAW
double-materialization (cache + pkgadd spool) fit **16 MB** with no wedge — the standing
bench = metal config. The metal RAW run (a *bootable* install disk) is W6-RAW.2.

`installer-selftest.py` **audit M** locks the arm: the `SOURCE_KIND` dimension on
every profile; the driver's default-cdfs/validate/`die`-on-unknown branch; the RAW
branch's `raw.conf` write, `apkg update`+`apkg -R install` both `|| die` (with a
negative fixture proving a softened `apkg … || true` is caught); **no `APKG_ROOT`
assignment**; the subshell-safe order→apkg name list; the documented
payload-at-`/cdrom` mount; and the builder's presence.

## W6-RAW.2b: the *bootable* metal source disk (`--bootable`)

W6-RAW.1 proved the RAW *content* path on the bench with a two-slice source disk
(payload + raw). **W6-RAW.2b** turns that into the actual **metal deliverable**: a
single self-booting `.hdf`, mapped at **SCSI id 0**, whose slice-1 miniroot the
machine boots — so the metal install needs no tape, no CD, no boot floppy.
`tools/build-raw-source.sh --bootable` (profile **`metal-a4000-z3660-raw`**) authors
the five-slice disk, in `sdpart.c`/PartitionList order (**slice N == the Nth PART
block**):

| slice | dostype | what |
|------:|---------|------|
| 1 | UNI\1 | miniroot s5 — **c0s1unix roots here** (`rootdev C0D0S1 = 0x00480010`, id 0 slice 1) |
| 2 | resv  | swap **placeholder — STRUCTURAL** (this is what keeps BOOT at slice 3; do not omit) |
| 3 | UNI\0 | boot chain `boot1\|boot2(f287ff3a)\|c0s1unix-brel`, **bootable, bootpri 0** |
| 4 | UNI\1 | payload s5 == `SRC_PAYLOAD_SLICE` (mounts at `/cdrom`) |
| 5 | DATA  | raw distribution == `SRC_RAW_SLICE` (apkg `SRC_RAW`) |

The slice-3 chain is **framed by `tools/write-bootchain.py`** (c0s1unix brel + the
metal-golden donor's proven flags-based boot2), so amix-kerntools' own
`bootchain-verify.py` round-trip gate runs on the *source* disk — installng writes,
kerntools validates. The framed kernel's `sum -r` is gated against the profile's
`SRC_KERNEL_BREL_SUMR` (**04333**), so a wrong/renamed brel cannot ship silently.

**Boot priority is the post-install handoff, with no config edits.** The source's
boot chain is authored **bootpri 0**; the installer authors the id-6 target's boot
slice **bootpri 2** (`install.sh: /etc/rdb -P 2`). Kickstart boots the highest-bootpri
UNI\0 partition across all disks, so once install completes the **id-6 disk wins**.
Asserted at author time (`SRC_BOOT_BOOTPRI < TARGET_BOOT_BOOTPRI`) and, on the bench,
proven by proxy: the golden box (its own boot slice pri 2) kept booting *itself* with
this pri-0 source attached.

`--author --bootable` runs entirely host-side (padding the proven miniroot image to a
cylinder for `addimg`, sizing the boot slice from the kernel, the 5-slice `rdbtool`
author, `write-bootchain` framing, then read-back gates: 5-slice map + bootpri,
slice-1 miniroot md5-identical to the proven image, boot-slice map + kernel `sum -r`,
payload s5, raw catalog@0). `--populate --bootable` on the golden box cpios the payload
in *and* **smokes** the other slices without a bench boot (which the metal-mix kernel +
Phantom-Z3660 card-shift forbid): mount slice 1 read-only and `sum -r` a few members
against the host-extracted reference, and re-attest slice 3 host-side against the
boot-slice manifest. `installer-selftest.py` **audit N** locks all of this.

**Operator runbook for the metal session: `docs/metal-install-runbook.md` (maintainer-local, not in the public tree)** —
SD upload (`deploy-image-kvm.sh`, on-device CRC-verify), `z3660cfg.txt` mapping
(`scsi0` source / `scsi6` blank target), the boot dance, `install.sh raw`, the
bootpri handoff, `validate-metal.sh --cycles 5`, the canonical digest
`e483b0cb25dfaf4087b1f783335d520d` (re-attested 2026-08-11; the metal runs cited
below attested the superseded `ec31a72…`), rollback, and the **metal unknowns** list — the
pre-metal unknowns annotated with what the metal runs settled. **Closed by M-RUN2/M-RUN3**
(2026-07-24): the c0s1unix id-0 boot, the c6s1unix post-install id-6 boot, and the
`scsiN→cXd0` naming seam at id 0. The `/etc/rdb -c` create primitive is **closed on the
bench** (2026-07-31, `cd-author` green; *What the author cell found* above) — the metal
side of it is now only a confirmation that the fixed line behaves the same there. **Still
open**: triple-unit presentation and the full-27-set 16 MB headroom; base-8 only.

## W6-I.1: the three card-1 blockers, and why they were invisible

`updbootpart` could not install a kernel on a **card-1 (`ced0s1`) image** at all until
2026-09-09. Three independent defects, each alone sufficient, all fail-closed — which is
why they presented as a tool politely refusing rather than as a bug:

| # | defect | what it looked like |
|---|---|---|
| A | the controller regex was **decimal-only**: `c\([0-9][0-9]*\)d0s1` | `ced0s1` yielded an EMPTY `CN`, so the tool refused with *"root device … is not /dev/dsk/cNd0s1 — refusing to guess the boot slice"*. Correct behaviour on a wrong reading, which is exactly why it read as a missing device rather than a parse bug |
| B | the boot2 gate pinned **only** `good` (`sum -r` 14193) | a `good_040` slice (27860) — i.e. every 68040/68060 image — was refused, **and the message named the wrong culprit as fact**: *"the name-based loader D245s"* |
| C | the `--pkg` ROOTDEV gate compared a `hexval`'d id (14) against the **CN string** (`"e"`) | a mismatch that can never be satisfied |

**N is one HEX digit, not decimal.** It carries the CARD INDEX, which the kernel packs into
the minor's low nibble, so it spans 0..f: card 1 / target 6 is `ced0s1`, never `c14d0s1`.

**Both proven flags-based loaders are legitimate**, and which one is right depends on the
KERNEL LINE the disk boots — that is the caller's business, not a slice-framer's. The
refusal now says only what is known: *neither proven loader, therefore UNPROVEN*, which is
the distinction `amix-kerntools`' `contracts/bootchain-v1.json` `unknown_policy` exists to
preserve. Naming one specific culprit as fact is the failure it warns against.

Both sums were verified with real `sum -r` before being pinned. ⚠ `tools/lib/bootchain.py`'s
`svr4_sum()` is the **SysV fold, not the BSD rotate** `sum -r` prints — it answers
37995/57120 for these two blobs and is the wrong tool for this pin.

Gated behaviourally in `installer-selftest` audit O, not by pattern-matching: the tool's own
device-derivation and boot2 gate are extracted and RUN (`ced0s1` -> CN=`e`, CN_VAL=14;
`c6d0s1` still 6/6; `c0`/`cf` cover the nibble ends; `c6d0s3`, `cgd0s1`, `c10d0s1`, `hd0`
refused; both proven loaders accepted, an unknown one refused as unproven). All three
fault-injected. (C) is gated statically only — there is no behavioural ROOTDEV fixture yet.

## W6-I: `updbootpart` — kernel upgrade via a package

The install writes the boot slice once and arms the box. But a kernel is not
special-cased in the package world: to **upgrade the kernel later**, on a running,
fully-installed box, you `pkgadd` a kernel package and then re-frame the boot slice —
because **the machine boots from the raw `UNI\0` boot slice, not from `/stand/unix`**
(the `/stand` files are only the *framing sources*). `payload/updbootpart`
(`/usr/sbin/updbootpart` on every installed target) is that on-box finisher.

**The complete story, exactly as a user runs it:**

```
updbootpart --backup                        # rotate the running kernel aside first
pkgadd -d /tmp/KERNBENCH-…​.pkg KERNBENCH     # lands /stand/unix + /stand/boot2.boot
updbootpart --pkg KERNBENCH                  # gate, re-frame the boot slice, read back
/etc/uadmin 2 0 ; <cold boot>                # the running kernel is now the new one
```

`--backup` runs **before** `pkgadd` because pkgadd overwrites `/stand/unix` **in
place** — once it runs, the old kernel is gone unless it was copied to
`/stand/OLDunix`. `--rollback` restores `/stand/OLDunix` over `/stand/unix` and
re-frames, so a bad kernel is one command + one boot away from undone.

**`--rollback` gates before it writes** (corrected 2026-08-15). It reads
`sum -r /stand/OLDunix`, compares it against the expected `KSUM_R`, and only then
copies — a wrong `OLDunix` leaves `/stand/unix` **untouched**. Until this was fixed
the order was inverted, and it bit on metal: a `--backup` had rotated a *truncated*
`/stand/unix` into `OLDunix`, and `--rollback --ksum 55482` printed

```
updbootpart: rollback: restoring /stand/OLDunix (sum -r 61907) over /stand/unix
updbootpart: STOP: kernel identity gate FAILED … refusing to frame the wrong kernel
```

*in that order*. The tool correctly refused to **frame** the bad kernel — after it
had already written it over `/stand/unix`. The box survived only because it was
still running off the intact boot frame; the next reframe would have shipped the
truncated blob to the boot slice. A gate that fires after the write is not a gate.
The expected-sum resolution therefore now runs **above** the rollback block (it is
needed by both modes and depends on neither), and the reframe's own identity gate
still re-sums `/stand/unix` *after* the copy — that second look is what catches a
short write, not redundancy for its own sake.

### The reframe recipe (W6-U probe — codified, not re-derived)

Full byte-for-byte conformance with the boot-chain contract, driven **directly** (no
`make bootpart` — `/stand/CONFIG` is *absent* on installed boxes, so the stock rule
cannot run):

```
cd /stand
( cat boot1.boot; ./makeiblk boot2.boot; cat boot2.boot; \
  ./makeiblk unix;  cat unix ) | dd conv=sync of=/dev/dsk/cNd0s3
sync; sync
```

Traps the tool **owns** (each proven on-box in W6-U): `makeiblk` is invoked
`./makeiblk` (it is `/stand/makeiblk`, not on `PATH`); the boot slice is **s3 of the
root disk** with **N derived** from the `/` line of `/etc/vfstab` (root `cNd0s1` →
boot `cNd0s3`), *never* hardcoded; and `/stand/boot2.boot` must be the **flags-based
loader** — the name-based loader D245s the flags-based ET_REL kernels.

### Fail-closed gates (before a single block is written)

| gate | check | why |
|------|-------|-----|
| kernel identity | `sum -r /stand/unix` == expected `KSUM_R` (from `--ksum N`, a bare `N`, or `pkgparam <PKG> KSUM_R`) | never frame the wrong kernel; refuse without an expected sum |
| kernel identity, **rollback** | `sum -r /stand/OLDunix` == the same expected `KSUM_R`, **before** the copy | never *restore* the wrong kernel either: on a refusal `/stand/unix` must be byte-untouched (see above) |
| boot2 loader | `sum -r /stand/boot2.boot` == **14193** | the name-based loader D245s; refuse anything else |
| rootdev | `pkgparam <PKG> ROOTDEV` decodes (minor `= (slice<<4)\|id`) to the derived root `cNd0s1` | the kernel's baked-in rootdev must name *this* disk |
| readback | frame → temp file → `dd` to the slice → `sync;sync` → `dd` the slice **back through the raw node** → `cmp` | trust the write only when the *disk* is byte-identical to the frame |

It runs on the **full installed target**, so it uses `sum`/`wc`/`cmp`/`pkgparam` —
tools the thin miniroot lacks. Like `S16firstboot`, it is **additive**: it is **not**
a package member, so it never reaches the contents DB (`pkgchk`/altroot-attest
unaffected).

**Since W5.5 it travels on the MEDIUM, not inside the driver.** `build-install-iso.sh`
stages `payload/updbootpart` at `/install/updbootpart` (and stops unless the staged
copy is byte-identical to the master), and the arm step is a plain
`cp "$INST/updbootpart" "$TARGET/usr/sbin/updbootpart"` that fails closed on media
mastered before W5.5. It used to be a quoted here-doc inside `install.sh` — which the
1991 `sh` materializes as a real file on the 880-block install floppy the moment it
*parses* the script, measured at 15,427 bytes = **16 of that floppy's 46 free 1 KB
blocks, on every install** (see W5.5 below). Being copied rather than emitted changes
nothing about attestation: the digest is a function of what `pkgadd` **recorded**.

**Audit O** scans `payload/updbootpart` independently — target pre-POSIX + parse, the
target-tool allowlist (`sum`/`wc`/`cmp`/`pkgparam`/`./makeiblk`), every gate fail-closed
(no `|| true` softening), the vfstab-derived slice (no hardcoded `cNd0s3`) — and the
**drift lock** now lives where both files are still visible: the builder's byte-identity
gate, which audit O requires to be there.

The `KERNBENCH` kernel package (`../amix-packagemanager`) is the counterpart: its
`pkginfo` carries `ROOTDEV`/`CONFIG`/`KSUM_R`/`BOOT2_SHA`, readable on-box via
`pkgparam` for exactly these gates.

**The current handoff pair — P5.4 r4, pinned here 2026-08-16.** `updbootpart` never
hardcodes a sum (it reads `KSUM_R` off the installed package), so this is documentation,
not a gate value — but it is what an operator types after `--ksum`, and what
`validate-metal.sh --expect-sum` expects on a handed-off box:

| package | `VERSION` | `KSUM_R` | `/stand/unix` size | family |
|---|---|---|---|---|
| `KERNBENCH` | `49667-2026.08.16` | **49667** | 1,586,312 B | a4091 bench (A3000+A4091) — bench-smoke 8/8, not metal-flown |
| `KERNZ3660` | `60364-2026.08.16` | **60364** | 1,587,524 B | A4000+Z3660 metal — **metal-proven 2026-08-15**, the last metal-validated kernel identity |

`BOOT2_SHA` is `f287ff3a…` in both, unchanged since W6-P — the boot2 loader gate
(`sum -r` **14193**) is untouched by a kernel re-mint. **r4 is additive, not a
retraction:** the r3 pair (`KERNBENCH-64049-2026.08.07` / `KERNZ3660-45833-2026.08.07`)
was never defective, is metal-green from the 2026-08-07 calibration, and its `.pkg` files
stay valid-in-place — hand off an r3 package and `45833`/`64049` is still the right
expected sum. Source of truth for both lines: `../amix-packagemanager`
`docs/kernel-packages.md` §8 and `../amix-kerntools` `docs/kernel-packages.md` §4a-quater.

**None of this touches fresh-install semantics.** On a *fresh* install `/stand/unix` is
the inert payload-staged core file the media lays down (`55482`), and the kernel that
actually boots is the slice-3 brel — the KERN identities above appear only *after* a
`pkgadd` + `updbootpart` cycle. Moving these pins changes no shipped byte; the media pins
move only at a re-master.

**And `55482` is not one of those media pins — it is the `core` package's own file.**
The r4 re-master (2026-08-16) re-derived it instead of carrying it forward: the stock
`core` package ships `/stand/unix` as a 1,475,108-byte 1992 binary (hardlinked to
`/stand/2.1_unix`), and `pkgadd` lays it down like any other package member. **No kernel
this project builds is ever written to `/stand/unix` by the installer** — the media's own
kernels live in boot slices — so a kernel re-master cannot move this number, and it did
not: at r4 the framed brels moved (`49227` → **`50544`** target, `51865` → **`28387`**
source) while `55482` stayed exactly where it was. It moves only if `core` is re-minted.
Any statement that `55482` "is the rN kernel" is a mis-attribution, not a version pin.

## METAL-FIX.2: the seed writes `/etc/mnttab` (fresh-media mnttab bug)

**Symptom (M-RUN, metal).** On the first true metal run from **freshly built**
install media, the base-OS transplant froze the instant the first `pkgadd`/`apkg`
tried to install:

```
pkgadd: ERROR: unable to open mount table (/etc/mnttab)
```

**Root cause.** `pkgadd`/`apkg` `open()` the RUNNING system's `/etc/mnttab` (via
`get_mntinfo()`) before installing. A freshly built miniroot's `/etc/mount` is a
direct `mount(2)` that records **no** mnttab entry — and the fresh miniroot ships
**no `/etc/mnttab` file at all**. The engine tolerance added earlier
(`0d3a21c` synthesize-when-line-missing, `3b9b7a1`/METAL-FIX.1 synthesize-on-ENOENT)
handles a *readable* table that merely lacks the `/` line; it cannot help when the
`open()` itself fails first. So the transplant never starts.

**Why it hid for two waves.** Every prior acceptance run reused the same **bench
floppy**, whose `/etc/mnttab` had been left behind (stale/contaminated) by an
earlier run. Its mere presence let `open()` succeed, and the engine's synthesize
path then papered over the missing/`wrong` line — so the class was invisible until
a genuinely fresh medium exposed it.

**Fix (driver-side, this repo).** The **seed step** (`install.sh` §4, both source
arms, before any `pkgadd`/`apkg`) now writes the root line unconditionally:

```sh
echo "/dev/root / s5 rw 0" > /etc/mnttab
```

- **OVERWRITE (`>`, never `>>`)** — a stale/contaminated table is *replaced*, not
  appended to (killing the exact leftover that masked the bug).
- **The `/` root entry** — `get_mntinfo` keys off the **shortest** mount point being
  exactly `/`; a `/mnt` line does not satisfy it.
- **`echo` + redirection only** — miniroot-allowlist-clean (audit G / `SH_BUILTINS`).
- Belt-and-suspenders with the engine tolerance: the box installs whether or not the
  engine also synthesizes.

`installer-selftest.py` **audit F** now asserts the seed writes the line, that it is
an OVERWRITE of the `/` entry, that it sits in the seed **before** the install loop,
and a **negative fixture** proves the check fires when the line is removed.

### Media hygiene — acceptance runs MUST use FRESH media

The two-wave masking above is the lesson: **a reused install medium can carry a
stale `/etc/mnttab` (or any other leftover state) that hides a real defect.** Every
acceptance / attestation run must therefore start from **freshly built source media
and a freshly `mkroot`'d target** — never a floppy/`.hdf` recycled from a previous
run. (The driver's OVERWRITE now neutralizes *this* specific leftover, but the
general rule stands: fresh media is the only way to reproduce the true first-boot
conditions a real installer meets.)

## METAL-FIX.4: the metal install comes up network-live (`zen0`, not `aen0`)

**Symptom (M-RUN2, metal).** The first full metal install (attested byte-canonical)
came up multiuser but with **no working ethernet**: `firstboot`'s `/dev` regen logged
`atdevs returned nonzero`, and `aen0` refused to plumb (`SIOCGIFFLAGS: Invalid
argument`). It also baked **no `amixmetal → IP` line** into `/etc/inet/hosts`.

**Root cause (two independent gaps — both settled, not re-investigated here).**

1. **Wrong interface.** Metal ethernet is **`zen0`** — the Z3660's on-board
   `z3660eth` (cdevsw major **51**, `/dev/zen0 c 51 0` — **renumbered from 48 on
   2026-07-30**, see the ordering constraint below). The installed metal kernel
   (golden 00961 / brel 21467) *already contains* `z3660eth`; what a **base install**
   ships is only the **stock a2065/`aen0`** inet userland, which is **inert on metal**
   (there is no A2065 board). So nothing ever brings `zen0` up. The golden box works
   only because it was *hand-built* with `/etc/rc2.d/S99zen` + `/dev/zen0` laid in.
   The bring-up is SVR4.0: `slink addaen /dev/zen0 zen0` then `ifconfig zen0
   <LITERAL-IP> up -trailers` — **never `plumb`, never `uname -n`** (the name path
   triggers a boot-stalling DNS lookup on SVR4.0).
2. **Empty `FB_IP`.** Both metal profiles shipped `FB_IP=` (empty), so `firstboot`
   (which appends `"$FB_IP $FB_NODENAME"` to `/etc/inet/hosts`) baked nothing.

**Fix (driver-side, this repo).**

- **The `zen0` bring-up laydown.** The arm step (`install.sh` §9) now lays down
  `/etc/rc2.d/S99zen` on the target — **driver-written and additive**, exactly like
  `S16firstboot` / `updbootpart`: **not** a package member (invisible to the contents
  DB / `pkgchk` / `altroot-attest`), and it **never** edits `/etc/inet/network-config`
  (the hard rule). It is **guarded on `FB_ETHER_IF=zen0`** so the a2065/`aen0` bench
  path is untouched; a `zen0` profile with an **empty `FB_IP`** is a **fail-closed**
  `die` (the bring-up needs a literal IP). The body is emitted from the tracked master
  `payload/S99zen` with the profile's `FB_IP`/`FB_NETMASK` substituted for its
  `@FB_IP@`/`@FB_NETMASK@` placeholders (the same selective-`echo`-expansion idiom the
  driver already uses for `firstboot.conf`); the body is the proven **z3660net**
  bring-up (`../amix-z3660net/userland/S99zen`): self-heal `/dev/zen0` via `mknod`, a
  bare `slink` first, then `slink addaen` in a retry loop, `ifconfig zen0 <ip> up
  -trailers`, all **backgrounded** so a datapath fault can never hang the boot.
- **Metal IP = `192.0.2.39`.** Both metal profiles now set `FB_IP=192.0.2.39`
  (**METAL-FIX.4b**: `.39` *is* the established metal-box address — every golden's
  `zen0` comes up there and all z3660net userland hardcodes it; `.38` is the
  **bench/Amiberry** emulator, a different box. There is only one physical
  A4000+Z3660, booted one disk at a time, so a from-scratch install *is* the metal
  box and there is no clash to avoid) and correct
  `FB_ETHER_IF` from the misleading `aen0` to **`zen0`**. The non-empty `FB_IP` also
  makes `firstboot` bake the `<FB_NODENAME> → 192.0.2.39` hosts line — since the
  2026-08-06 nodename decision the metal RAW profile bakes **`z3660amix`** (the
  established metal-box name; the M-RUN2/M-RUN3-era media baked `amixmetal`).

**The `zen` binary — deliberately NOT laid down (not a blocker).** `/usr/amiga/bin/zen`
is a *diagnostic/status* tool (compiled from `../amix-z3660net/userland/zen.c`); it is
**not on the bring-up path** — the z3660net `S99zen` never invokes it (`mknod` +
`slink` + `ifconfig` + `route` only). No **compiled `zen` binary is host-available**
anywhere in the workspace (only the C source, whose header comment says *build on-box*
`cc -o zen zen.c`), so building or extracting one is out of this media-builder's scope
and would need the cross toolchain + an ABI matched to the installed kernel. The clean
long-term home for `zen` (and a packaged `zen0` userland) is a **Z3660NET userland
package** (packagemanager-owned) — flagged, not built here. Network-liveness does not
depend on it.

`installer-selftest.py` **audit P** locks all of this: the driver lays `S99zen` under
the `FB_ETHER_IF=zen0` guard (`chmod 0744`, empty-`FB_IP` `die`, driver-emitted not a
CD copy); a **drift-lock** runs the driver's own `emit_zen_hook` and proves it
reproduces `payload/S99zen` byte-for-byte with the IP substituted **and tracks
`$FB_IP`** (a second distinct IP flows through — a hardcoded IP is caught); the master
is pre-POSIX + parses + self-heals `/dev/zen0` + backgrounds + uses a literal IP (never
`uname -n`) + is target-tool-allowlist-clean; the metal profiles carry
`FB_IP=192.0.2.39 + FB_ETHER_IF=zen0`, every `zen0` profile has a non-empty `FB_IP`,
and the bench profiles keep `aen0`. Negative fixtures prove the empty-IP + hardcoded-IP
checks fire.

### The `z3660eth` major is **51** — media and kernels must match (2026-07-30)

`z3660eth` was renumbered **48 → 51** source-side in `../amix-z3660net` on 2026-07-30
(`c949380`). 48 had only ever been "an empty `nostr` row on the stock/a4091 kernel", and the
2026-07 community sweep showed it **contested** — `zz9000-amix`'s `integration/kernel.c.txt`
documents an unpublished dev tree using 48 for `random`. **51** is the lowest slot of the
ecosystem-verified-free set 51–67/69 (`CDEVSIZE` = 70). Evidence and the full cross-tree claim
table: `../grimoire-amix/docs/reference/major-number-registry.md`; the authoritative why-51 note
lives in `../amix-z3660net/driver.conf` + `BUILD.md`.

**The ordering constraint.** This repo emits the `/dev/zen0` *node*; the kernel supplies the
*cdevsw row*. They must agree or `zen0` opens an empty row and the interface is dead:

- media re-mastered from **this tree** emit **`c 51 0`** and therefore **require a kernel that
  registers `z3660eth` at 51** — the **P5.4** kernel set;
- **do not re-master this tree against a 48-registering kernel.** Shipped kernels (and every
  `/dev/zen0` node on an already-installed root) carry **48** until that P5.4 rebuild;
- `S99zen` only `mknod`s when the node is **absent**, so an existing root upgraded to a
  51-registering kernel keeps its stale `c 48 0` node — it must be **removed or re-`mknod`'d**
  at P5.4. That is a z3660net/P5.4 concern, not something a fresh install hits (a fresh install
  has no node until `S99zen` makes one).

`installer-selftest.py` audit P asserts the `c 51 0` literal *and* fails on any residual
`c 48 0` in the master, so the two sides of the renumber cannot drift apart silently.

### Bench limitation — the laydown is bench-provable, the LINK is metal-only

There is **no `z3660eth` under emulation**, so Amiberry cannot bring `zen0` up. The
**laydown** (that `S99zen` is written, IP-correct, allowlist-clean, drift-locked) is
fully host/bench-provable and is what `audit P` covers. The **actual link** — `zen0`
up + bidirectional traffic — is **metal-only-testable**, and **M-RUN3 (2026-07-24)
proved it from a fresh install**: `zen0` UP, host ping 3/3, bidirectional telnet,
surviving 4 cold boots. That run predates METAL-FIX.4b, so it proved the (address-agnostic)
bring-up at `.38`; the runbook's zen0 link-validation step now re-confirms the shipped
`.39` rather than proving the link for the first time. Re-master note: to bake
a driver/profile change into the media the next metal session boots, the RAW source media must be
**re-mastered** (the profiles + `install.sh` changes ride the staged driver + profiles)
— that is a separate operations step, not run here.

## P5.4-FT: /stand framing tools + the syslog unit (two M-RUN-P5.4 field findings)

Both were ferried to the metal box by hand during M-RUN-P5.4 (2026-08); both are now
laid down by the installer, fingerprint-gated end to end. `installer-selftest.py`
audits **Q** (framing tools) and **R** (syslog unit) cover them; both pieces are
staged by `build-install-iso.sh` and ride the RAW payload slice unchanged
(`build-raw-source.sh` consumes the same staged tree). **They reach shipped media at
the NEXT re-master** — the r3 media (`8842B572`) predate them.

### The framing tools (updbootpart's gate 5a, driver-guaranteed)

`updbootpart`'s reframe pipeline needs `/stand/boot1.boot`, `/stand/boot2.boot` and
an executable local `/stand/makeiblk`, and its gate 5a fails closed without them. On
**M-RUN4b** the KERN-package handoff on the fresh metal base-8 install died exactly
there ("framed image is empty") until `boot1.boot` + `makeiblk` were ferried from the
bench golden (1 KB-chunk split-pull; `amixsync` GET deterministically truncates
`makeiblk` at 10912/14924 — reassembled byte-perfect, `sum -r` 58483).

The driver now **lays both down in the arm phase**, right after `updbootpart`
itself:

| file | bytes | `sum -r` | provenance |
|------|-------|----------|------------|
| `/stand/boot1.boot` | 1,024 | 41892 | the 2.1 original — the 2.1c patch never touched it, so the extracted core tree's copy IS the golden's |
| `/stand/makeiblk` | 14,924 | 58483 | the **2.1c patched** build every golden runs — the pair the metal reframe was PROVEN with |

With the section-6 flags-based `boot2.boot` overwrite, **every framing source gate 5a
checks is now driver-guaranteed** (audit Q proves the coherence). The `cp` overwrites
any core-delivered 2.1 `makeiblk` — the `boot2.boot`-class content touch: invisible
to the contents-DB digest (a pure function of what pkgadd recorded), visible to a
full-content `pkgchk` exactly as the boot2 overwrite already is.

**A divergence worth recording:** the tracked `core-2.1.pkg` DOES ship
`/stand/boot1.boot` + `makeiblk` (2.1 vintage), and a bench CD-cell install from the
08-07 matrix run has them on the target — yet the metal fresh base-8 install did
not (the M-RUN-P5.4 ledger record is unambiguous). The root cause of that absence
was never isolated; the laydown makes the question moot by making presence AND
provenance deterministic on every fresh install, whatever the transplant delivered.

### The syslog unit (base-8 ships none — laid down ENABLED)

A base-8 install carries core's `/usr/sbin/syslogd` **binary** (2.1, 22,368 B) and
core's `/dev/log`, but **no unit**: no `/etc/init.d/syslogd`, no rc links, no
`/etc/syslog.conf`, no `/var/log` at all — `syslog(3)` writes are silently
discarded. The approved one-line enablement (kerntools
`docs/inetd-telnet-throttle.md` §5) therefore applies only to full installs; base-8
needed the unit itself. **Decision: installer laydown** (the `S99zen` pattern —
driver-written at install time, sourced from the user-supplied 2.1c patch media,
same licensing posture as everything staged), NOT a package: a SYSLOG package would
enter the contents DB and change the canonical digest (`e483b0cb…`/4859 since the
2026-08-11 re-attestation) that anchors every cross-media continuity proof, for zero
functional gain.

What the driver lays down (all from `/install/syslog`, fingerprint-gated at
staging; unconditional — bench profiles need logging as much as metal):

| piece | mode | notes |
|-------|------|-------|
| `/etc/syslog.conf` | 0444 | 2.1c conf 1.1 (63870/1,928) — `*.notice;kern.none → /var/log/notice` already selects inetd's `daemon.err`; no edit needed |
| `/etc/init.d/syslogd` | 0544 | the **ENABLED** copy (28819/967): the vendor disable — one bare `exit` — was commented **at media staging** (the miniroot has no `sed`); §5's enablement, pre-applied. Start and stop also trust `/etc/syslog.pid` only when `ps -p` shows that pid is a syslogd, and remove a stale file: the vendor `kill -0` test let an earlier boot's pid, held by another process now, keep syslogd from ever starting (S3-31) |
| `/etc/rc2.d/S70syslogd`, `/etc/rc0.d/K50syslogd` | — | **hard links** (`ln`) to the init script — the stock one-inode **3-link** topology. Any later edit must be **`cp` in place, never `mv`** (throttle doc §4): `mv` would orphan the rc links and the fix would work once, then never again after a reboot |
| `/usr/sbin/syslogd` | 0100 | the 2.1c "major revisions" daemon (53154/22,728) over core's 2.1 copy — the `boot2.boot`-class content touch; keeps the exact combination the goldens run and the throttle doc validated end to end |
| `/var/log/{alert,bus-errors,console,critical,kernel,news-urgent,notice,security}` | 0644 | eight zero-length stubs (syslogd appends to existing files; the vendor patch ships exactly these) |
| `/dev/conslog` | 0222 | `c 25 0` — the vendor patch's own "device node added to support syslogd" (`/dev/log` is already a core member) |

The vendor pieces come from the **user-supplied Amix 2.1c patch archive**
(`archive.lha` → `var/patch/archive.cpio`), extracted host-side by
`tools/extract-21c-payload.sh` into the gitignored `payload/21c/` and verified
against pinned fingerprints — a wrong or damaged archive is a hard STOP, and
`build-install-iso.sh` re-runs the (idempotent) extractor on every staging. Nothing
proprietary is tracked; everything is referenced by checksum (the repository's
licensing rule).

Behavioral proof of the enablement, host-side: `sh -x` on the vendor copy prints
`+ exit` and stops; on the staged ENABLED copy it proceeds into the `start` case
(pid probe → `-x /usr/sbin/syslogd -a -r /etc/syslog.conf` → daemon start). On the
box, cold boot #1 runs `S70syslogd start` from rc2 and the box logs from day one;
expected on-box verification is the throttle doc's: `syslogd` in `ps`, and
`logger -p daemon.err` landing in `/var/log/notice`.

**syslogd needs m4.** syslogd builds its table by running `echo 'define(LOGHOST, 1)' | /usr/ccs/bin/m4 -
/etc/syslog.conf`. `/usr/ccs/bin/m4` is a Cdev member, and no package ships `/usr/bin/m4`. Without it the shell
prints `/usr/ccs/bin/m4: not found`, every table row is UNUSED, and nothing is filed, although syslogd runs and
receives the messages (the Bench's `syslogd -d` capture, 2026-10-26). The `standard` and larger sets carry Cdev.
A `minimal` install has a syslogd that files nothing, and so has every 1.0 install of the minimal sets. A 1.1
medium carries m4 in its base (see the 1.1 section).

---

## W1: driver plumbing — the input keys the interview will land on

**Wave W1 of the installer-UX rework** (`docs/installer-ux-rework-plan.md` §9).
The rework is a *veneer*: an interview that produces an answers-profile, executed
by this proven driver. W1 is the driver half — it adds nowhere-else-to-land input
keys, restores two stock steps the NG driver had dropped, and gives the install a
persistent log. **Everything here is non-interactive and behaviour-preserving:**
every new key's default is the literal it replaced, and all four tracked profiles
carry today's effective values, so existing flows are byte-for-byte unchanged.
The acceptance run (`tools/install-matrix.sh cd`, fresh media) reproduces the
canonical `e483b0cb25dfaf4087b1f783335d520d` / 4859 objects (re-attested 2026-08-11 —
the fresh media this wave mastered is what surfaced the r3 package drift).

### 1. A profile by **path**, not just by name

```sh
sh /cdrom/install/bin/install.sh bench-a3000-a4091      # NAME (unchanged)
sh /cdrom/install/bin/install.sh /tmp/answers.profile   # PATH (new)
```

Resolution order: an argument containing `/` is a path; a bare argument naming an
existing file is a path; anything else is
`/cdrom/install/profiles/<name>.profile`. The install medium is read-only, so an
answers profile can never live under `/install/profiles` — the path form is what
makes the W2 interview possible without touching the transplant engine.
`installer-selftest.py` audit S **runs** the extracted resolution block on all
four argument shapes rather than grepping for it.

### 2. The install log, and what "verbose" actually means

Every install now writes a complete transcript to **`<target>/var/adm/install.log`**
(= `/var/adm/install.log` on the finished system). It is driver-written, so it is
**not** a package member: invisible to the contents DB, `pkgchk` and
`altroot-attest` — the same additive class as `S16firstboot`, `updbootpart`,
`S99zen` and the syslog unit. (The digest-neutrality argument holds for
DB-invisible paths **only**; do not generalise it.)

There is **no `tee(1)` on the miniroot**, so "show it and log it" is a temp file
`cat`'d twice (`cat` is on the proto):

| | console | log |
|---|---|---|
| **quiet** (`INSTALL_VERBOSE=n`, default) | stage messages only | stage messages + every `+ cmd` echo + all child output |
| **verbose** (`INSTALL_VERBOSE=y`) | everything the log gets | identical |

A **failing** child's output is printed on the console in *both* modes — a quiet
run must never hide why it stopped. `run` is now a thin wrapper over `runq`, which
routes the output and **returns the child's rc** (so `contents-fsck`, `pkgadd` and
`apkg` keep their existing fail-closed branches).

Two boundaries, both declared in the log itself rather than left to be discovered:

- the **pre-mount window** (banner, profile echo, disk probe, RDB authoring,
  `mkfs`, the pre-mount `fsck`) is console-only — there is no target filesystem to
  write to yet;
- the log **closes before the final unmount**, because the file lives on the
  filesystem being unmounted; the post-unmount `fsck` and the `INSTALL COMPLETE`
  summary are console-only and the closing marker names them.

`<target>/var/adm` and `<target>/tmp` are created at the log-open step (the log
needs the first, `runq`'s scratch file the second). The seed in §4 therefore no
longer `mkdir`s `<target>/tmp` — the miniroot's 1991 `mkdir -p` returns 2 on an
existing leaf (W5.4f).

### 3. Stock stage strings

Where a stage has an equivalent in the original installer, the driver now prints
the original's string **verbatim** and unprefixed (`stage`), instead of its own
`install.sh: …` line (`msg`, still used for NG-only stages):

| stage | string | source |
|---|---|---|
| author-mode `mkfs` | `Making filesystems.  This will take a few minutes.` | stock `/etc/profile` |
| pre-mount `fsck` | `Please wait while the partitions are checked...` | stock `/etc/profile` |
| per package | `Installing <pkg>` | `amixpkg`'s `Installing %s` |

All three live on the stock root floppy (`floppies/orig/amix_21_root.adf` — the
stock install script *is* its `/etc/profile`, readable host-side with
`tools/lib/s5.py`), and audit S checks them against that image's bytes when it is
present (SKIP, never a silent pass, when it is not).

### 4. The keymap bake — a stock step we had dropped

Stock's last act before halting was to persist the keyboard chosen at the very
start:

```sh
rm -f /mnt/usr/amiga/lib/kmap/default.kmap
if [ "$KMAP" != "" ]; then
    ln /mnt/usr/amiga/lib/kmap/$KMAP /mnt/usr/amiga/lib/kmap/default.kmap
fi
```

`/etc/id_kmap` leaves `$KMAP` **unset** for the American map, so `usa` links
nothing — the map is compiled in. `/etc/sysinit` loads `default.kmap` on every
boot, so that one hard link *is* the persistence mechanism.

The NG driver dropped the step entirely, and research found **no `default.kmap` on
any golden** — every NG-installed box has been running the compiled-in American
map regardless of belief. `FB_KMAP` restores it with the same empty/`usa` == none
semantics. The maps are **`core` members**
(`/usr/amiga/lib/kmap/{cdn,ch1,ch2,d,dk,e,f,gb,i,n,s,usa,usa0,usa1,usa2}`), so a
named map that does not exist on the target is a profile error and fails the
install closed. **Hard** link, as stock — a dangling symlink would fail silently
at `sysinit`.

### 5. The real disk size, and the two size overrides

Stock sized its plan from the disk in front of it:

```sh
DISKLEN=`/etc/ddsize $rDISK`   ;   DISKMB=`expr $DISKLEN / 2048`
```

`/etc/ddsize` **is on our miniroot** (`miniroot.proto`) — it was simply unused, so
a profile *hint* drove the plan and a 500 MB disk would have got whatever layout
the hint described. W1 restores the stock input **for the case the hint cannot
cover** — a disk nobody wrote a profile for:

- `TARGET_DISK_MB` set → it **wins and the probe is not run at all**. Every
  tracked profile, runbook and `mkroot`-prebuilt target pins it, so no shipped
  flow calls `ddsize`;
- `TARGET_DISK_MB` empty → the **probe** drives the plan (stock behaviour; this is
  the path the W2 interview will use);
- probe unusable → 100 MB, the historical fallback.

The probe is `is_num`-guarded: an unreadable device yields empty output, which is
not a number, so a dead disk can never be read as "0 MB".

#### ★ Bench finding: `/etc/ddsize` is **not** safe on the a3091 path (2026-08-11)

The first cut of this code probed **unconditionally**, purely to log the real size
and warn when it disagreed with the pin. That **wedged the install** on the bench
rig: matrix run `20260811-094255-cd` printed the driver's profile banner, the
kernel printed

```
a3091: 0x1 0 0x0
```

and the driver never advanced past that line — the `install` gate failed after
its 300 s go-marker budget with the box otherwise healthy. The stock installer
ran `ddsize` on *stock* kernels and *stock* rigs; that is not what we boot, and
the A3000 onboard-SCSI (`a3091`) path under Amiberry does not tolerate it against
`/dev/rdsk/c6d0s0`.

There is **no timeout tool on the miniroot**, so a hang here cannot be bounded.
The posture is therefore: *never call it when we do not have to*. A pinned
`TARGET_DISK_MB` short-circuits the probe entirely (selftest audit S fires on an
unconditional probe), and the driver prints its "probing …" message **before** the
call so a future wedge is diagnosable from the console instead of silent.

**W2 must re-verify this before it builds on it.** §2.4 of the rework plan specs
the destination screen as a per-id table of *real `ddsize` probes* — on this
evidence that scan would hang the interview on the first id. Treat "make `ddsize`
usable on our kernels (or find another size source)" as a W2 prerequisite, not a
detail.

`TARGET_ROOT_MB` / `TARGET_SWAP_MB` are the two answers stock **asked** for,
bounded by the same four stock limits the interactive prompts enforced — root
`>= MINROOT` (16) and `<= ROOTMAX` (what leaves `MINSWAP` free); swap
`>= MINSWAP` (5) and `<=` what actually remains after root. Unset, the arithmetic
is the pre-W1 code path unchanged; audit E proves that by re-running the extracted
`plan_partitions` with the keys empty and diffing the layout, then proves each of
the four bounds (and a non-numeric value) actually refuses.

### 6. De-hardcodes

| was | now | note |
|---|---|---|
| `TZ=:US/Eastern` literal in `firstboot.sh` | `TZ=:$FB_TZ` | the **colon is emitted by code**, never carried in data — a colon-less `TZ` bus-errors `date`/`who -r`/`ls -l`/`cron` at cold boot (W6.3). The driver strips a leading colon off the profile value so `TZ=::zone` is unreachable too. Audit F's W6.3 guard was extended to the parametrized emission, with negative fixtures for both broken shapes. |
| `route add default 192.0.2.1 1` in `emit_zen_hook` | `FB_GATEWAY` | the tracked master `payload/S99zen` gained an `@FB_GATEWAY@` placeholder; audit P's drift-lock resolves it and proves a **second distinct** IP/gateway pair flows through. A `zen0` profile with an empty `FB_GATEWAY` fails closed, exactly like the existing empty-`FB_IP` gate. |
| `repo=http://files.example.net/html/amix` in §5c | `FB_REPO_URL` | default = that literal, so the installed `/etc/apkg.conf` is byte-identical. *(Default `http://pkg.amigaux.org` since 2026-09-14.)* |
| — | `FB_DNS1` / `FB_DNS2` | **plumbed only**: recorded into `firstboot.conf`, applied nowhere. Audit S fails if `firstboot.sh` starts writing `resolv.conf`/`netconfig`/`libsockdns`/`/etc/domain` — that is W5, and on `aen0` flavors it collides with the never-edit-`network-config` rule. |

### 7. `/lost+found` — the other stock step we had dropped

```sh
for i in 0 1 2 3 4 5 6 7 8 9; do
    for j in 0 1 2 3 4 5 6 7 8 9; do  > /mnt/lost+found/$i$j; done
done
/mnt/usr/bin/rm /mnt/lost+found/*
```

An s5 directory never **shrinks**, so creating and deleting 100 entries
permanently grows `lost+found` to hold 100 slots — which is what lets `fsck`
reconnect orphaned inodes on a *full* filesystem, when it cannot allocate a new
directory block. No NG-installed box has ever had that. Restored in the stock
position (after the package transplant, before the final unmount/fsck).
`lost+found` is a **directory**, not a package member, so it is DB-invisible and
digest-neutral like the log; `mkfs_s5` already creates it, and the `mkdir` only
covers its absence.

### Selftest lockstep

`tools/installer-selftest.py` gained audit **S** and extended **E**, **F**, **K**
and **P**; the check count goes **213 → 307**, `tools/run-checks.sh` fully green.
Two of S's proofs are behavioural rather than textual — the profile-by-path
resolution and the quiet/verbose logging split are **executed** (extracted from
the driver, run under `dash`, console and log compared) rather than grepped for.

## W2: the interview — `/install/bin/setup.sh`

**Wave W2 of the installer-UX rework** (`docs/installer-ux-rework-plan.md` §9).
W1 gave the driver the input keys; W2 is the thing that fills them from a human.
`src/installer/setup.sh` runs on the miniroot after the source is mounted, asks
the questions the *original* installer asked, composes `/tmp/answers.profile`
over the media-resident base profile, and hands it to the unchanged driver:

```
miniroot shell
  └─ sh /cdrom/install/bin/setup.sh [base-profile]
       ├─ destination disk   (stock table, stock question, stock erase confirm)
       ├─ partition sizes    (stock arithmetic, stock floors, stock messages)
       ├─ root fs type       (NOT asked since P-35: always ufs; until then the
       │                      stock s5/ufs menu with its default moved to [ufs])
       ├─ package set        (data-driven from /install/order*)
       ├─ verbose install?
       ├─ confirmation + "Do you wish to change any of these? [n]"
       └─ exec sh install.sh /tmp/answers.profile < /dev/null
```

It is a **veneer**: nothing in it partitions, mkfs's, pkgadd's or writes a boot
chain. The only artifact it produces is a profile.

### The UX spec is the stock installer, quoted rather than imitated

Three stock artifacts supply every word:

| Artifact | Where | Supplies |
|---|---|---|
| `/etc/profile` | `floppies/orig/amix_21_root.adf`, 19,351 B, md5 `97f800ec7bcd627bfed2322fdc19f86b` | `readask()`, bracketed defaults, y/n case globs, the `WARNING:  ` prefix, the restart idiom, the disk table, every size prompt and validation message |
| `/bin/amixpkg` | same floppy, 12,216 B, md5 `d63408968f87027313dc9115a6756d55` | the package-menu line and `Choose: [1] ` |
| `system.setup` | the repackaged `core` package | the summary screen's `Do you wish to change any of these? [n] ` |

Extract any of them host-side with `tools/lib/s5.py` (direct + single-indirect
blocks — `/etc/profile` is 19 KB, so a direct-blocks-only reader silently
truncates it at 10,240 bytes).

`installer-selftest.py` audit **U6** checks all 18 quoted strings **byte-for-byte
against those artifacts**, and the table spells out the three places stock
parameterised what we resolve — stock asked about "the disk you want to `$MODE`"
because it also did repairs (repair mode is W4, on the miniroot), and its two
size prompts interpolate its own default variables. Declaring the deviations
beats a fuzzy match that would quietly accept a drifted string.

### ★ The scan never calls `/etc/ddsize`

This is the wave's load-bearing constraint, and it exists because of a
measurement, not a worry. W1 added **one** unconditional
`/etc/ddsize /dev/rdsk/c6d0s0` to the driver and it **wedged the install** on the
bench A3000 onboard-SCSI (a3091) path: the console printed `a3091: 0x1 0 0x0` and
nothing ever advanced (matrix run `20260811-094255-cd`, install gate FAIL after
the 300 s go-marker budget). The miniroot has no timeout tool, so a hang there
cannot be bounded — and a *scan* would run the call once per SCSI id, multiplying
the exposure by six.

So the scan reads **one 512-byte block** from each id's `/dev/dsk/cNd0s0` with
`dd`. That is not an invention. Stock's own `/etc/atdevs` (2,404 B, extracted from
the same root floppy) is a tiny ELF whose **only** format string is
`/dev/dsk/c%dd0s0` and whose only libc calls are `open`/`read`/`close`/`printf` —
i.e. exactly this probe, in C, on the block node. We do it in `sh` because the
failure mode is then inspectable, and because `atdevs` has already been observed
returning nonzero on metal (firstboot's `/dev` regen).

`ddsize` survives in exactly one place: behind the `DDSIZE_SAFE` base-profile key,
for the **one** disk the operator already chose, **after** the choice. Audit U1
extracts the four scan-path functions and requires them to be `ddsize`-free, and
counts `ddsize` as a *command* (the chooser also names it in the line it prints
before running it, so the console says where a wedge happened; a substring count
would read that as a call).

### How a disk's size is decided — first hit wins

1. **The base profile's `TARGET_DISK_MB`**, when the chosen id is the profile's
   own `TARGET_SCSI_ID` — the medium's declaration about its own rig. Same
   precedence the W1 driver applies, and what keeps a pinned rig deterministic.
2. **The RDB's extent** — the largest `start + length` over its partitions, read
   with `/etc/rdb -h 5` (last partition number) and `/etc/rdb -p N`
   (`name start length`, the exact three-token shape the stock script parses with
   `set --`). This **understates** a disk whose RDB does not span it, which is
   the **fail-safe** direction: the plan then lays partitions inside a region we
   have proof exists. Overstating would run the last partition off the end.
3. **`/etc/ddsize`**, iff `DDSIZE_SAFE=y`.
4. **The operator** — `How many megabytes is this disk? [100] `.

Whatever wins is written into the answers profile as `TARGET_DISK_MB`, so the
driver's own probe is short-circuited and **`install.sh` never calls `ddsize`
either**.

`/etc/rdb -p N` is also read via a temp file rather than straight into `set --`:
an empty command substitution leaves `set --` a **no-op** on this shell (audit I's
trap), so a partition `rdb` declined to print would silently re-use the *previous*
partition's numbers — the nastiest form of that bug, because it still produces a
plausible size.

### Eligibility, exclusions, and the two new base-profile keys

An id is offered only when the medium carries a **matching-`ROOTDEV` TARGET
kernel** for it. `INSTALLABLE_IDS` defaults to the base profile's own
`TARGET_SCSI_ID` — today a medium is mastered for exactly one root device, and
offering any other id would install a kernel that cannot find its root. When P6.3
(root-by-identity) lands, that constraint dies and the key opens up.

* The **mounted source disk** (`SRC_SCSI_ID`) is always listed as
  `source -- not installable`. Without it the metal RAW medium would happily
  propose erasing the disk it is reading itself from. Mirrors stock's
  `SCSI device 4 must be used for the tape drive` refusal.
* Ids with no kernel are listed as `no kernel on this medium for id N` — visible,
  not silently absent.
* **SCSI id 4 is structurally unreachable**: `miniroot.proto` ships no `c4d0`
  node, so stock's tape reservation needs no code at all. Audit U2 derives
  `SCAN_IDS` from the proto and fails if the default drifts from it — or if 4
  ever appears in either.
* Exactly one eligible disk ⇒ the question is **skipped** (stock behaviour).

| Key | Default | Meaning |
|---|---|---|
| `DDSIZE_SAFE` | `n` | may the probe run at all, once, after the choice? `n` on both bench profiles (the rig the wedge was measured on — audit U7 refuses `y` there), `y` on both metal profiles, where the *stock* installer ran it on every install |
| `ANSWERS_ECHO` | `n` | write the composed profile to `ANSWERS_ECHO_PATH` (`/matrix.ans`) before the transplant |

### The answers profile

`/tmp/answers.profile` is the base profile **byte for byte**, with the answers
**appended**. A profile is sourced by `sh`, so a later assignment wins — that is
the entire merge mechanism, and it means every key the medium declares (kernel
sums, `CD_SPEC`, boot-slice paths, `FB_*`) survives untouched. The appended block
is fenced by `# W2-ANSWERS-BEGIN` / `# W2-ANSWERS-END` and carries
`TARGET_SCSI_ID`, `TARGET_DISK_MB`, `TARGET_ROOT_MB`, `TARGET_SWAP_MB`,
`INSTALL_VERBOSE`.

`/install/profiles/BASE` (written by `build-install-iso.sh` from the first
`--profile`) names the family the medium was mastered for, so the W4 miniroot
handoff *is* a bare `exec sh /cdrom/install/bin/setup.sh`. An explicit argument
still overrides it, so every existing runbook line is unaffected.
★ **On a RAW payload slice the name in `BASE` does not resolve**: the slice is s5,
s5 truncates every name at 14 characters, and `build-raw-source.sh` therefore
writes the profile under an s5-safe short name (`raw.profile`). W4 taught the
resolver to fall back to that short name when `BASE`'s own name is not on the
medium — without it the argument-less handoff would die on exactly the media the
metal runbook uses. (A cleaner fix is for `build-raw-source.sh` to rewrite `BASE`
itself when it renames the profile; queued.)

**stdin discipline.** The interview owns the console; the transplant must not.
`setup.sh` execs `install.sh` with `< /dev/null`, preserving METAL-FIX.3 — an
inherited stdin is what hung M-RUN1 on the 1991 `pkgadd`'s prompt. Anything still
queued in the tty when the interview ends is therefore discarded rather than fed
to the transplant. Audit U3 pins the redirection.

`setup.sh` also runs **no `stty`** (audit U5). Stock's own `stty` lines are
commented out, and an `stty` here would flush the answers the install matrix types
into the tty queue ahead of the prompts — the run would hang with no diagnosis.

### The package screen is a data table, not a branch

Sets are enumerated from the medium's `/install/order*` files into a table of
`<n> <orderfile> <label>` rows; the menu prints rows and `Choose: [1] ` reads the
answer. Today there is exactly one order file, so there is one row. When W3b ships
per-set order files the same loop prints three and the same prompt reads the
choice — more rows, no new code.

The MB column comes from the catalog's **opt-in** `#isize` extension block
(`gen-catalog.py --isize`, which `build-iso.sh` does not pass today, so no current
medium carries it and no figure is printed). It is deliberately
**all-or-nothing**: package names differ between the order file (`pkginst`, e.g.
`APKGENG`) and the catalog (lowercase `apkgeng`), so the catalog's own entry lines
map one to the other, and if **any** wanted package lacks an `#isize` line the
column is omitted entirely. A partial sum printed as a figure is worse than no
figure, because the operator cannot tell the difference — and it is never `0.0`.

### Two real defects the new audits found

Both are in *stock's* arithmetic, and both are unescapable prompts rather than
wrong numbers:

* **Under ~23 MB the stock `ROOTMAX` goes negative.** Stock's own loop would then
  reject every possible answer — `You must leave at least 5 megabytes free for
  swap space.` forever, with no way out but Ctrl-C. The disk is refused up front
  now: if no answer can satisfy both stock floors at once, there is no question to
  ask.
* **Between ~23 and ~36 MB the stock default lands under `MINROOT`** while a legal
  answer still exists. Stock would offer that illegal default and accept it on a
  bare RETURN; our driver then dies at its own `MINROOT` gate. The **offer** is
  clamped to the floor; the operator can still type anything up to `ROOTMAX`.

### The matrix cell `cd-interactive` and the answers beacon

Same media, same prebuilt target and the **same nine gates** as `cd` — driven
through the interview instead of a canned profile name. The point of the cell is
the **identity**: interactive and unattended must land on the same tree, or the
veneer is not a veneer.

The console is blind, so the canned answers (`y 79 18 1 n n`) are typed into the
tty queue. Lines typed before a prompt appears are *not* lost — the line
discipline buffers them and `read` takes them in order — so the pacing is for the
human reading the screenshots, not for correctness. What is load-bearing is the
**count**: one line per prompt. A dropped keystroke leaves the last prompt waiting
and the run times out, which is the failure mode we want.

The answers are **explicit rather than bare RETURNs on purpose**. `79` and `18`
*are* the computed defaults for the 100 MB bench disk, so an accepted default
would look identical whether the keystroke arrived or not; an explicit value that
reappears in the beacon proves the typed line was read and parsed. The `y` is
mandatory either way — stock's erase confirmation has no default.

Before the transplant starts, `setup.sh` writes the composed profile to the
marker floppy as `/matrix.ans`; the install gate extracts it from the `.adf`
(a byte scan between the two fence markers, like every other marker on this
channel) and asserts each expected key **whole-line** — a substring test would let
`TARGET_ROOT_MB=790` satisfy an expectation of `=79`. So a mis-parsed answer costs
seconds instead of five minutes plus a digest mismatch. `workset` additionally
refuses a root floppy that already carries a beacon, so a previous run's answers
can never be read as this one's.

The **keymap** is not `setup.sh`'s: it is pre-mount, so it is the miniroot's own
prompt. *(W2 left it there and the `mediaboot` gate Ctrl-C'd past it, which meant
`FB_KMAP` could only come from a canned profile. **W4 closes that loop** — the
miniroot's own menu hands the answer over as `$KMAP` / `/tmp/kmap` and `setup.sh`
records it; see *W4: the miniroot respin* below.)*

### Selftest lockstep

Audits **A/B/G/H/I/T** all extended to `setup.sh` under the **same strict miniroot
allowlist as the driver** (no target-side extras: no `sed`, no `touch`, no
`basename`, no `grep`, no `od`). Three new audits:

* **U — structure.** Scan is `ddsize`-free; `SCAN_IDS` derived from
  `miniroot.proto`; stdin discipline; no `stty`; the answers-profile shape and
  both beacon fences; stock wording byte-for-byte; and both W2 keys present and
  valid in all four tracked profiles.
* **V — the interview's sizing defaults *are* the driver's plan.** Both blocks are
  **extracted and executed** under `dash` on nine disk sizes and required to
  agree. If they ever drift the interview lies to the operator — it offers a
  default the driver then computes differently, and nothing downstream notices
  because both numbers are individually legal. Audit E already pins the driver's
  half against `mkroot.sh`, which is itself the stock arithmetic, so agreement
  here chains `setup.sh` → driver → mkroot → stock.
* **W — the interview actually run.** 24 sandboxed conversations against a fake
  bus (disks are regular files whose block 0 carries or lacks the `RDSK` magic;
  `/etc/rdb` and `/etc/ddsize` are stubs answering from a table; `install.sh` is a
  stub recording the profile path it was handed). Covers the bench shape end to
  end, every dead end reaching the restart idiom, both `DDSIZE_SAFE` directions,
  all four stock size-validation messages provoked *and recovered from* (a
  validation that cannot be re-answered is a hang), the `#isize` all-or-nothing
  rule, `BASE` resolution and the beacon's arming conditions.

Check count **320 → 378**; `tools/run-checks.sh` fully green.

### Bench acceptance — the identity claim, measured

Fresh media (`amix21-install-base-w2-20260811.iso`, mastered from this tree with
`setup.sh` and `profiles/BASE` staged), both cells **9/9**:

| cell | run | install gate | digest |
|---|---|---|---|
| `cd` (control) | `work/install-matrix/w2-cd` | `install.sh bench-a3000-a4091 rc=0` | `e483b0cb25dfaf4087b1f783335d520d` / 4859 obj + base-5 `86e1ceb144f1328bf441c5df38fc2798` / 4793 |
| `cd-interactive` | `work/install-matrix/w2-cdi` | `setup.sh interview -> install.sh rc=0, answers beacon verified` | **identical** |

The beacon the guest wrote before its transplant (`w2-cdi/matrix.ans.txt`),
recovered from the root floppy `.adf`:

```
# install set: Standard Amiga UNIX installation (order /cdrom/install/order)
TARGET_SCSI_ID=6
TARGET_DISK_MB=100
TARGET_ROOT_MB=79
TARGET_SWAP_MB=18
INSTALL_VERBOSE=n
```

That is the whole claim in one table: the same tree, from the same media, whether
a human answered the questions or a profile did.

## The stock `amixpkg` screens (recovered — the W3b screen freeze)

W3b reimplements amixpkg's menus over our catalog, so the exact rendering had to
stop being an open question. `/bin/amixpkg` was extracted from the stock root
floppy (12,216 B, md5 `d63408968f87027313dc9115a6756d55`) and analysed
**statically** — `strings` over the ELF's `.rodata`, no execution. Every string
below is a literal from that binary.

**The three-tier menu** (the format strings, verbatim):

```
(1)  Standard Amiga UNIX installation    %6.1f MB
(2)  Everything on the tape              %6.1f MB
(3)  Custom selection
Choose: [1] 
```

Row 2's `tape` becomes `disc` for us — the one changed word (plan §2.7). W2 uses
row 1 and the `Choose: [1] ` prompt as-is.

**The custom-selection table.** The row format is

```
%-8s %-10s %-40s %6.1f
```

and the header/rule use `%-8s %-10s %-40s %8s` with the literals, in `.rodata`
order, `Size  ` / `Description` / `Name` / `Inst` and `====  ` / `-----------` /
`----`. The rule strings pair by length with the headers they underline
(`-----------` = 11 = `Description`, `----` = 4 = `Name`/`Inst`, `----  ` = 6 =
`Size  `), which fixes the assignment:

| Column | Width | Contents |
|---|---|---|
| 1 | `%-8s` | **Inst** — `yes` / `no` (both literals are in the binary) |
| 2 | `%-10s` | **Name** — package name |
| 3 | `%-40s` | **Description** |
| 4 | `%6.1f` | **Size**, in MB, right-aligned **last** |

So the plan's working assumption — *Inst/Name/Description/Size, Size last* — is
**confirmed**, and the widths are now pinned too. The `Size  `/`====  ` literals
carry two trailing spaces so that `%8s` in the header lines the word up over the
`%6.1f` number underneath. The totals line is `%53s Total: %6.1f MB`, whose
right-alignment is consistent with the same ~67-column row.

Surrounding text, all verbatim:

```
Tape contents:  %s
Enter package name to install or ignore; enter GO when ready.
Unknown package:  %s
```

Selection keywords: `all`, `standard`, `none`, plus `GO` / `go` / `restart`.

**The overcommit override** — two forms, MB in the tier menu and blocks in the
custom screen, both keeping stock's "go ahead anyway" escape:

```
WARNING:  
Your allocated space for installation 
is %d MB,
but you have selected to install %d MB.
```
```
is %d block%s,
but you have selected to install %d block%s.
Go ahead with the installation anyway? [n] 
```

The tape `List` header amixpkg parses uses the keys `pkg=`, `name=`, `size=`,
`opt=`, `zcat=` and `Version` — our catalog's `#isize` block is the equivalent
input, which is why W3b needs it (plan §5.3) and why W2 already reads it when a
medium carries one.

Per-package progress is `Installing %s` — the string the W1 driver already prints
in quiet mode.

## W3b: multi-set package selection goes live

W2 gave the installer a human. W3b gives the human something to choose. The
packagemanager half landed first (`gen-catalog.py --isize`, `cats.conf`,
`sets.conf` + `sets.py`); this is the media/installer half, and it turns
amixpkg's three-tier menu from a one-row table into the real thing.

### What was actually wrong before

Three defects, all of them the same defect wearing different hats — **the
membership of a package set had no single definition**:

| where | what it said | consequence |
|---|---|---|
| `build-iso.sh` | `BASE_SET=(core bsd net text sysadm)` | the disc's five stock packages |
| `build-install-iso.sh` | `BASE_SET=(core bsd net text sysadm cdfs APKGENG APKG)` | the install order's eight |
| `build-install-iso.sh --set full` | every `stock/*.pkg` | **a Full install shipped no cdfs, no package manager** — the disc carried them and the order file never named them |

All three are gone. Both builders resolve every set from
`../amix-packagemanager/tools/repo/sets.conf` through that repo's own
`sets.py` — one grammar, one resolver, exactly as there is one catalog format
and one generator. `--set full` now installs 30 packages, `--set standard` 17,
`--set base` (kept as this repo's spelling of `minimal`) the proven base-8.

A fourth defect was found on the way in and fixed with them:
`tools/lib/isocheck.py`'s `parse_catalog` was **9-fields-exactly** and counted
every `#isize` line as a malformed entry. amix-packagemanager's `docs/design.md`
named it as *the* known non-conforming consumer of catalog v1 and made `--isize`
opt-in because of it. It skips `#` lines now, so the media path can carry the
block — and a new `check_catalog_isize` verifies the block against the mastered
image (a name that is not a catalog row, a duplicate, a non-numeric size, or
lines with no `#ext` header are all refused; **no block at all is silent**,
because the block is opt-in).

### ★ The authored order IS the install order

`gen-install-order.py` breaks topological ties by **input order**, so whatever
order the builder feeds it becomes the order packages are laid down in. `sets.py`'s
`resolve()` returns a **sorted** membership — right for "is this package in the
set", wrong here: feeding it straight into the order generator silently re-ordered
the base-8 install to `core APKGENG APKG bsd cdfs net sysadm text`, on the one
wave whose acceptance is that the base-8 tree does **not** move.

`build-install-iso.sh` therefore expands sets in **sets.conf's own file order**
(`core bsd net text sysadm cdfs apkgeng apkg` — which is exactly the historical
hand-written `BASE_SET`), and then asserts that its expansion equals `sets.py`'s
`resolve()` **as a set**, so the two can never disagree about membership while
differing in order. `installer-selftest` audit X pins the `minimal` order against
the historical eight independently.

### The medium's set metadata

`build-install-iso.sh` now stages three things beside the order file:

```
/install/order              the MASTERED set (unchanged name, unchanged meaning:
                            install.sh reads it when INSTALL_ORDER is unset, so
                            every existing profile/runbook/matrix cell is untouched)
/install/order.<set>        one per named set the medium satisfies IN FULL
/install/sets               <num> <setname> <orderfile> <attested> <label...>
```

A set is offered only when the medium carries **all** of it — an order file
naming a package the disc does not hold would fail at `pkgadd` time, which is far
too late to learn the disc was mis-mastered. On a base-8 disc that means one
offered set (`minimal`); on a `--set standard` disc, two.

`gen-install-order.py --set NAME` records the name as a **header comment**
(`# set: standard (17 package(s))`). Every consumer already skips `#`, so it is
documentation — and the driver reads it back, which is how an unattended profile
run over standard-set media logs `standard` without the profile knowing anything
about sets.

### The three-tier menu (amixpkg's, activated)

```
(1)  Standard Amiga UNIX installation      33.5 MB
(2)  Everything on the disc                37.9 MB
(3)  Custom selection
Choose: [1]
```

Row 1 is the `standard` set when the medium carries all of it — that is what
"Standard Amiga UNIX installation" *meant* on the tape — and the medium's own
mastered set otherwise (on a base-8 disc there is no larger truth to offer).
Row 2 is everything on the disc. Row 3 is a UI constant and is emitted by
`setup.sh`. On a minimal medium rows 1 and 2 are the same set and the menu says
so **twice** rather than hiding a row: a menu whose numbering depends on the
medium is a menu the blind-console matrix cannot type into. A medium mastered
before W3b has no `/install/sets` and the two tiers are synthesized from its
single `/install/order` — three rows, same numbering, either way.

**The MB figures are BUDGETED at ~1.10×.** The `#isize` block is a payload byte
sum; an s5 filesystem charges 1 KB blocks plus indirect blocks plus directories,
measured at ~1.08× against the original tape's own 512-byte-block accounting. So
the figure the menu shows is the **footprint**, directly comparable to the root
partition the operator has just sized — which is what the free-space check
compares. Written as `b + b/10` and never `b*11/10`: the full set is ~290 MB,
`b*11` is 3.2e9, and a signed 32-bit `expr` would hand back a **negative** budget
that every comparison downstream would happily accept. **Absence of the block
prints no figure at all, never 0.0.**

### The custom table (frozen widths, live)

```
Disc contents:  minimal
Inst     Name       Description                                Size
----     ----       -----------                                ----
yes      core       Amiga Unix essentials                      20.9
...
                                                               ====
                                                      Total:   33.5 MB

Enter package name to install or ignore; enter GO when ready.
```

`%-8s %-10s %-40s %6.1f`, Size last — the layout frozen by W2's static analysis
of `/bin/amixpkg`, reproduced with `padr()` because the miniroot has no `printf`.
Header and rules use `%-8s %-10s %-40s %8s` with `Size  ` / `----  ` / `====  `,
and the total is `%53s Total: %6.1f MB`; the numbers land in columns 62–67 in
every row. Keywords are amixpkg's: `all`, `standard`, `none`, `GO`/`go`,
`restart`; an unrecognised word gets `Unknown package:  %s`.

Three properties are worth stating because each of them is a decision:

- **`core` is mandatory.** amixpkg greyed it; we refuse the deselection with a
  line saying why. Gate 13 in the driver would refuse the resulting order anyway,
  and refusing at the menu is a diagnosis instead of a failure.
- **Closure runs in ONE direction per keystroke.** Selecting a package pulls its
  dependencies in; deselecting one pushes its dependents out. Run together the
  two rules fight — one wants A in because A is selected, the other wants A out
  because a dep of A is not — and the screen oscillates. Six passes is a fixed
  point: the longest chain the catalog can express is `oldev → {olcore,xdev} →
  xcore`, three deep.
- **The selection is a FILTER, never a solve.** The universe is `/install/order`,
  which is topological; a subset of a topological order is still topological, so
  the custom screen writes `/tmp/setup.order` by dropping lines. No dependency
  solver ever runs on the miniroot.

### The free-space check, with stock's own override

```
WARNING:  Your allocated space for installation is 30 MB,
but you have selected to install 37 MB.

Go ahead with the installation anyway? [n]
```

Verbatim from amixpkg (assembled from its four `.rodata` fragments). Declining
returns to the menu; accepting installs anyway, exactly as stock did. An
**unknown** size is no gate at all — refusing an install because the medium
declined to say how big a set is would be treating "unknown" as "too big", which
is the same class of mistake as treating it as 0.

### Digest policy — attested, or explicitly waived (plan §5.7)

| selection | digest gate |
|---|---|
| named set **with** a reference digest | gated, as always |
| named set **without** one | **waived**, and said out loud |
| Custom, always | **waived**, and said out loud |

"Said out loud" is the whole mechanism. The interview writes `INSTALL_ATTESTED=n`
into the answers profile, prints `Package set:  <name> -- unattested selection`
on the confirmation screen, and the driver copies it into
`/var/adm/install.log`. A waiver nobody was told about is the failure mode; a
tree nobody can compare to a reference must not be mistaken later for one that
was compared.

Which sets are attested is a **promise the matrix has to keep**, so it is stated
in two places that are mechanically pinned to each other:
`ATTESTED_SETS` in `build-install-iso.sh` (what the medium tells the interview)
and `SET_REFS` in `install-matrix.sh` (the actual digests). Audit X requires that
every advertised set has a real digest and every real digest is advertised; a `-`
row is a set awaiting its first attestation run and is correctly **not**
advertised.

### The driver's three new keys

| key | default | meaning |
|---|---|---|
| `INSTALL_ORDER` | *(empty)* | empty ⇒ `$INST/order`, i.e. **byte-for-byte** the pre-W3b behaviour. A bare name resolves on the medium; a value with `/` is a path — which is how a Custom selection arrives, because the medium is read-only. |
| `INSTALL_SET` | *(empty)* | the set's name for the log; empty ⇒ read the order file's `# set:` header. |
| `INSTALL_ATTESTED` | `y` | `n` softens no gate; it records that the gate was waived. |

**Core-first stays in the driver.** Gate 13 already refuses any non-core package
into a bare root, package by package, and W3b does not move it — but
`INSTALL_ORDER` now lets a file the driver did not generate name the packages, so
the first package is checked up front as well. Subshell-safe, of course: the
probe records to a file inside the redirect-fed loop and the parent decides.

### Known limitation: RAW media get the tiers, not the table

On a **RAW** source the catalog lives at byte 0 of the distribution slice (the
`SRC_RAW` contract), not as `/cdrom/catalog`, so the interview finds no catalog
file. It degrades exactly as designed rather than lying: the tier menu prints its
rows **with no MB figures** (absence is unknown, never 0.0) and Custom answers
`This medium carries no package catalog, so packages cannot be listed.` and
returns to the menu. Named sets still install normally — `/install/sets` and the
per-set order files ride the payload slice like the rest of the `/install` tree.
Giving RAW media a readable catalog copy is a `build-raw-source.sh` change and
belongs with W6's RAW catalog-region measurement.

### ★ Bench finding 1: a redirected `read` is a FORK on the miniroot sh

W3b's first `cd-interactive` run (`w3b2-cdi`) died on its own guard, and the
console said exactly why:

```
setup.sh: STOP: internal: /cdrom/install/sets has no usable first row
```

The interview read the medium's two set-table rows with the obvious idiom:

```sh
{ read R1N R1SET R1ORD R1ATT R1LBL
  read R2N R2SET R2ORD R2ATT R2LBL ; } < "$SET_F"
```

The 1991 SVR4 sh **forked** for it. Both reads happened in a child, the parent
saw empty variables, and the run burned 420 s waiting for a beacon that could
never come. It is the same shell behaviour that makes every
`while read … done < FILE` loop a subshell here — **a redirected compound
command is a fork** — and the lesson generalises exactly the way the `: >`
lesson did.

The surviving idiom is the one this repo has used all along: write the value to
a **file** and `cat` it back in the parent. `installer-selftest` audit **H2** now
forbids `} <` and `read VAR… < FILE` outright in all three miniroot scripts,
with three negative fixtures and three positive controls. A redirected `read` on
a *simple* command is not known to fork, but it is banned alongside the compound
form on purpose: nothing here needs it, the two look identical at a glance, and
one of them costs a ten-minute blind console run to diagnose.

### ★ Bench finding 2: containment is by OBJECT COUNT, not by digest

The `cd-standard` attestation run was gated on the base-5 and base-8 subsets
matching their reference **digests**, on the reasoning that `minimal ⊂ standard`.
They did not match — and the assumption, not the install, was wrong.

**SVR4 packages share paths, and the contents DB records the last declaration.**
Exactly five objects differ between a base-8 tree standing alone and the same
base-8 tree inside a standard install, and every one of them gained a second
owning package:

| path | packages: minimal → standard | what changed |
|---|---|---|
| `/usr/bin/uudecode` | `core` → `core uucp` | size 5484 → 5324 (uucp ships its own) |
| `/usr/bin/uuencode` | `core` → `core uucp` | size 4468 → 4260 |
| `/usr/ucblib/doctools` | `bsd text` → `bsd text man` | owner `bin:bin` → `root:root` |
| `/usr/ucblib/doctools/tmac` | `text` → `text man` | owner `bin:bin` → `root:root` |
| `/var/spool/news` | `core` → `core public` | mode `0777` → `0755` |

The **path set and the object count are exact in both directions** — 4793/4793
base-5, 4859/4859 base-8, zero paths present on one side only. So the containment
gate for a **superset** run compares the object count (a missing or extra base-8
object still fires) and records the subset digest without comparing it. A
`minimal` cell keeps the strict digest comparison: standing alone, there is no
later package to overwrite anything.

This is a property of the *distribution*, not of the installer, and it is worth
knowing before anyone tries to gate a set on a subset digest again.

### ★ A W2 latent bug found and fixed: `: >` inside a *function* called from a loop

The 2026-08-11 finding was "never `: > file` inside a loop". W3b widens it: **a
function called from a loop body is a loop body.** Every question in the
interview sits inside the stock `Do you wish to change any of these?` re-ask
loop, so W2's straight-line `: >` truncations in `scan_disks`, `choose_disk`,
`set_size_mb` and `build_set_table` were only straight-line on the *first* pass.
A second pass would have appended to a scratch file it believed it had emptied,
and the operator would have been shown **the disk table and the package menu
twice over**. All six are `cp /dev/null` now.

### Bench acceptance

Fresh media, mastered from this tree by `tools/build-install-iso.sh`
(`amix21-install-base-w3b-20260811.iso`, `amix21-install-standard-w3b-20260811.iso`).
All three cells **9/9**:

| cell | run | set | install | digest |
|---|---|---|---|---|
| `cd` | `work/install-matrix/w3b3-cd` | minimal (8) | `install.sh bench-a3000-a4091 rc=0`, 297 s | `e483b0cb25dfaf4087b1f783335d520d` / 4859 + base-5 `86e1ceb144f1328bf441c5df38fc2798` / 4793 |
| `cd-interactive` | `w3b3-cdi` | minimal (8) | interview → `install.sh rc=0`, beacon verified, 440 s | **identical** |
| `cd-standard` ★ | `w3b3-std` | standard (17) | `rc=0`, 537 s | **`4ad8e17b69b32208c9fffa600596a428` / 11012** + base-5 4793 / base-8 4859 CONTAINED |

The interview's beacon, recovered from the root floppy `.adf` before its
transplant ran, now carries the W3b keys as well:

```
# install set: Standard Amiga UNIX installation
TARGET_SCSI_ID=6
TARGET_DISK_MB=100
TARGET_ROOT_MB=79
TARGET_SWAP_MB=18
INSTALL_VERBOSE=n
INSTALL_SET=minimal
INSTALL_ORDER=/cdrom/install/order
INSTALL_ATTESTED=y
```

**The base-8 tree did not move** — which is the acceptance for this wave: a whole
new metadata pipeline, a new menu, a new custom screen and three new driver keys,
and the canonical digest is the same on both base cells.

### ★ Standard is the SECOND attested set — and the 16 MB headroom question is answered

`standard` now has a reference: **`4ad8e17b69b32208c9fffa600596a428` / 11012
objects**, from `w3b3-std`. Beside the digest, the run settles an open unknown the
plan flagged (§5 item 8): **nobody had ever installed 17 packages in one run on a
16 MB box.** It works, and it is not even close to the edge —

- the transplant ran **537 s** (vs 297 s for the base-8), all 17 `pkgadd -R`s rc=0;
- `contents-fsck` clean on an 11 014-line contents DB;
- **two** cold boots to run-level 2 + LAN, first-boot once-only;
- boot chain verified host-side afterwards;
- 63 715 109 B of payload → a ~66.8 MB budgeted footprint in a 79 MB root.

No memory-pressure symptom appeared at any point (the class to watch for is the
RAW double-materialisation livelock, which reads like a SCSI or network hang).
`Full` (30) / `Developer` (19) / `X11` (18) stay **offered-but-unattested** and
ride W6 with the headroom measurement they depend on — 30 packages is another
~210 MB of source trees and a different question from this one.

The one operational consequence: a medium mastered **before** the reference was
recorded advertises `standard` as `attested=n`, because `ATTESTED_SETS` is a
mastering-time fact. Re-master to flip it — which the fresh-media rule requires
anyway.

## The a4091-sole-HBA cdfs wedge — re-verified **STALE** (plan §8.11)

The installer-UX plan's source-exclusion table carried one hardware exclusion:
*CD on an a4091-sole-HBA rig wedges*. The observation predates the stack-sdcom
(`amix-z3660scsi a5af58a`) and cdfs page-crossing-DMA (`fa9db1a` / `31e8c3b`)
fixes, so §8.11 made re-verifying it a W2 bench item **before** the exclusion got
hard-coded into the interview.

**Rig** (generated into `work/wedge-verify/<ts>/`, never a tracked config — the
tracked `configs/accept-bench-a3000-a4091.uae` with three lines changed):
`scsi_a3000=false` + an empty `scsi_a3000_rom_file`, and the `DH0` target lines
dropped, because that disk hung off `scsi6_a3000`, which no longer exists. What
is left is an A4091 as the machine's **only** HBA, carrying the install CD at
`scsi3_a4091`, and DF0.

**Method.** The same blind-console discipline the matrix uses: reach the miniroot
shell, prove it with a nonce the guest writes to its own root floppy, then type
one mount line per candidate address, each recording **its own rc** to the
floppy, and read the disc's own `/install/order` back through the mount. **Every
deadline lives on the host** — a wedge was the expected outcome, the miniroot has
no timeout tool, and the whole probe ran under an outer `timeout` with an EXIT
trap owning teardown.

**Result — STALE.** Markers the guest wrote (run `20260811-124559`):

```
WDG2359shell         miniroot shell reached
WDG2359m0_3rc1       cdfs mount 0,3 -> rc 1  (refused, promptly)
WDG2359m1_3rc0       cdfs mount 1,3 -> rc 0  (mounted)
```

and the disc's order file came back through that mount, byte for byte:

```
core bsd net text sysadm cdfs APKGENG APKG
```

No wedge, at either address: both mount attempts **returned**, one refusing and
one succeeding, and the successful one was readable. **The exclusion can be
retired from the plan's source-exclusion table** — CD-sourced installs are not
categorically off the table on an A4091-sole rig.

**Secondary finding worth keeping.** The A4091 stays at **card index 1** even
with the A3000 controller switched off — `0,3` is refused and `1,3` is the CD.
The natural assumption (drop the first controller, everything shifts down) is
wrong, so an a4091-sole profile keeps `CD_SPEC=1,3`. The miniroot's own probe
order (W4 hardcodes `1,3` → `0,2` → `1,2`) already tries the right one first.

Not claimed by this run: that a full *install* from that rig succeeds. The
exclusion this retires is about the source medium being mountable and readable,
which is what was measured.

## W4: the miniroot respin — the install script becomes ours

Until this wave the NG miniroot booted the **stock** install script (`/etc/profile`
on the stock root floppy, 19,351 B) and the operator escaped it: `Ctrl-C` at the
first prompt, mount the CD by hand, run the driver. Everything the last three waves
built — the interview, the sets menu, the driver's input keys — sat behind that
manual dance. W4 replaces the one file, and the dance is gone.

`src/miniroot/profile` (15,998 B) is now `/etc/profile` on the built miniroot. The
anatomy is in `docs/miniroot.md`; what matters here is the seam:

```
console login shell sources /etc/profile          [miniroot, ours since W4]
  ├─ "Amiga UNIX install script"  + the stock Ctrl-C trap (FIRST)
  ├─ keymap menu (stock's, entry 11 relabelled "Suomi / Svenska")
  │     -> /etc/sioc 5 …  and  $KMAP + /tmp/kmap handed forward
  ├─ "Do you want to install or repair? [install] "   (repair restored)
  ├─ source auto-probe: the dd-gated RAW payload slices, then cdfs 1,3 / 0,2 / 1,2
  │     -> the first that answers is left mounted at /cdrom
  └─ exec sh /cdrom/install/bin/setup.sh             [medium: the interview]
        └─ exec sh …/install.sh /tmp/answers.profile < /dev/null   [the driver]
```

### The five things that were easy to get wrong

1. **The trap goes in before the first prompt.** It is stock's own ordering, and it
   is also load-bearing for this repo: the matrix's `mediaboot` gate reaches a
   miniroot shell by sending `Ctrl-C` at the first prompt. Audit **Y** fails the
   build if the trap ever sinks below a `readask`.
2. **The probe decides on CONTENT, never on a mount return code.** A cdfs mount can
   return 0 and be *empty* (the stale-mount case the driver already carries), and a
   mount over an already-mounted `/cdrom` returns `EBUSY` while the source under it
   is perfectly readable. The test is `[ -f /cdrom/install/bin/setup.sh ]`, plus the
   errno-5 retry with an umount between the attempts.
3. **One attempt per address, and stop at the first answer** — see *The probe
   that panicked the kernel* below. The candidate that answers is left mounted;
   nothing probes past a working source, and a RAW candidate is existence-gated
   by a bounded `dd` before it is mounted at all.
4. **The keymap has to survive two execs.** It is exported *and* written to
   `/tmp/kmap`; `setup.sh` prefers the file (it is the channel that survives a
   Ctrl-C into a shell and back) and an **empty file is an answer** — `usa`, i.e.
   bake nothing — which must override a base profile that names a map. The two
   files are pinned to each other by audit Y (`KMAPFILE` == `KMAP_FILE`).
5. **`/etc/id_kmap` is not edited.** Our menu is *inlined* in `/etc/profile`, so the
   one changed label lives in our file; the stock artifact stays on the image
   byte-identical (md5 `4bdbe25645cccd0c64e8fdbee5aca5a1`), and
   `miniroot-selftest.py` fails if the proto ever claims it as ours.

### What the matrix does differently now

`cd` and `cd-standard` are **unchanged** — they still `Ctrl-C` past the first prompt
into a shell and type the driver line, which is exactly the compatibility claim: the
preserved trap means the unattended arms never notice the new script.

`cd-interactive` was upgraded from "drive the interview" to "drive the whole flow".
One typed line runs it:

```sh
echo <nonce>go > /matrix.go; sync; INSTALL_TARGET_PREBUILT=1 sh /etc/profile; echo <nonce>rc$? > /matrix.rc; sync; sync
```

`sh /etc/profile` is the same file the login shell sources at boot; running it as a
**child** is what gives the gate an exit status to record (a sourced profile that
`exec`s leaves nothing behind) and leaves the parent shell alive to halt the box.
The boot-time entry is still exercised — it is what `mediaboot` Ctrl-Cs out of. The
`source` gate now **unmounts `/cdrom` again** on interactive cells after proving the
disc readable, so the probe has to find and mount it for itself.

`cd-suomi` is the same cell with keymap **11** instead of 12, and it exists to prove
two separate things:

* the answer **reaches the target** — `/usr/amiga/lib/kmap/default.kmap` exists and
  has the **same inode** as `/usr/amiga/lib/kmap/s` (stock persisted the choice with
  exactly one `ln`; only an inode identity distinguishes a link from a copy), and
  `firstboot.conf` records `FB_KMAP=s`;
* the answer **does not fork the attestation** — that link is driver-written and so
  invisible to the contents DB, so the installed-tree digest must still be the
  canonical base-8. A keymap choice is not a distribution variant.

The `cd` and `cd-interactive` runs assert the *opposite* half of the same gate:
`default.kmap` must be **absent** and `FB_KMAP=` empty, which is what stock did for
`usa`. `kmap_check` in the matrix drives both shapes, and `--selftest` fires it seven
ways (copy instead of link, missing link, unrecorded link, stray link, empty
transcript, …).

### ★ The keymap law — why nothing types a path after the first answer

The moment the keymap answer is accepted the **console map has changed**, and the
console driver (`tools/lib/amicon.py`) types US key *positions*: under the Swedish
map `/` arrives as `-`. Everything the harness types after answer 1 is therefore
letters, digits and RETURN only — including the miniroot halt, which became three
punctuation-free lines (`sync`, `sync`, `uadmin 2 0`) instead of
`sync; sync; /etc/uadmin 2 0`. `--selftest` enforces it over both halves of the
canned conversation and over the halt lines.

This is not a harness workaround. It is the same law the KVM discovered on metal on
2026-08-11 (`/` → `-` when the KVM keymap and the AMIX map disagree), and the reason
the W4 flow is worth having: **it asks for no paths at all.**

### Selftest lockstep

`src/miniroot/profile` joins the driver and the interview under the **same** audits
— **A** (pre-POSIX), **B** (`sh -n`), **G** (the `miniroot.proto`-derived tool
allowlist, with its own vacuity guard), **H**/**H2** (subshell loops, redirected
reads), **I** (`set --` counting), **T** (`: >` in a loop) — and gets one of its
own:

* **Y — the W4 miniroot script.** The screen ORDER (banner → trap → keymap →
  install-or-repair → probe → hand-off) and the trap before the first `readask`;
  the hand-off is `setup.sh` and never `install.sh` directly; the keymap menu has
  14 rows, default 12, no `usa1`, entry 11 relabelled and stock's own entry 11
  gone, `usa` unsetting `$KMAP`; **the 13 unchanged rows byte-for-byte against the
  stock floppy**; the keymap channel pinned ACROSS FILES (`KMAPFILE` ==
  `KMAP_FILE`, plus the three `setup.sh` sites that consume it); the probe order,
  the content-not-rc decision, the errno-5 retry, the ask-only-when-ambiguous rule
  and the restart dead end; no `stty`, no `ddsize`; `SCAN_IDS` derived from the
  proto with id 4 structurally absent; 18 stock strings byte-for-byte with two
  declared deviations; and that the file is **Latin-1, not UTF-8**.

`miniroot-selftest.py` gains the `installng` source-class gates (five crafted
violations), and `install-matrix.sh --selftest` gains the keymap-bake parser
(`kmap_check`, eight cases including the real transcript that found its bug) and
the **keymap law** check over every canned answer and halt line. **443 → 481**
installer-selftest checks; `run-checks.sh` fully green.

★ **The bug the first `cd` run found was in the new assertion, not the installer.**
`kmap_check` parsed the box's boot-2 transcript with `grep '^FB_KMAP='` and an awk
reading `$1` as an inode — but a telnet transcript glues the box's `# ` prompt to
the front of each command's first output line, so `FB_KMAP=` was never at the start
of a line and the inode was never `$1`. It is the `/PENDING$` lesson exactly: an
assertion that looks like it is checking and can never fire (here it fired the
*wrong* way, which is how it was caught). The parser strips CR **and** a leading
prompt now, and every fixture carries the prompt.

### ★ The probe that panicked the kernel (and what it cost)

The first `cd-interactive` run on the W4 miniroot **panicked the box** in the
source probe, a few seconds after `Searching for the installation source...`:

```
proc = 400DA800 (pid 17, sh)  psw = 2204
pc = 70002E8
Fault addr: 47201BAC
PANIC: KERNEL FAULT psw=0x2204, pc=0x70002E8, fmt=0xA, vector=0x2 (Bus Error)
```

Three lab boots isolated it, and the result inverted a rule this repo thought it
knew.

| lab | what was run | result |
|---|---|---|
| A | each probe **once**, 25 s apart: cdfs `0,2`, cdfs `1,2`, `mount c0d0s4`, `mount c5d0s1` | all four returned cleanly (`errno 5`, `errno 5`, `I/O error`, `I/O error`) |
| B | `umount /cdrom` unmounted / mounted / unmounted again | all fine (`Invalid argument` twice, as expected) |
| C | the real sequence, **back to back**: `mount 1,3; umount; mount 0,2; umount; mount 0,2` | **PANIC**, same `pc=0x70002E8` |

**The killer is the SECOND mount attempt on a unit that is not there** — i.e.
the errno-5 retry itself. And the trap is that an absent unit fails with exactly
the same `errno 5` a genuine media-change unit-attention gives, so from sh the
two are indistinguishable: *the retry that recovers a media change is the retry
that kills the box.*

The fix is a design change, not a workaround:

* **one mount attempt per address per pass** — `probe_cdfs` mounts once and
  checks content;
* **the media-change retry becomes the operator's RETURN.** Nothing found ends
  at `Insert the installation CD and press RETURN to try again.` + the restart
  idiom, which re-runs the whole probe. Stock's own affordance, and it can never
  hit an address twice inside one pass;
* **stop at the first answer, and leave it mounted** — no separate "mount the
  winner" step, and no poking past a working source (the A4091 answers a missing
  unit with a `slow: poll=0 rc=-1 …` recovery line; that is a driver error path,
  not a probe);
* **RAW candidates are existence-gated first.** A block device can be tested
  with the one probe this miniroot has proven harmless — a bounded 512-byte
  `dd`, the same thing the interview's disk scan does — so RAW moved *ahead* of
  the CDs in the order. The practical consequence is the one that matters for
  metal: **on the self-booting source rig the probe finds its own slice 4 and
  never issues a cdfs mount at all.**

What it cost the plan: the "offer an override when more than one candidate
answered" idea is **gone**, because probing past a working source is exactly the
behaviour that panicked the box, and every candidate that could answer carries
the same `/install` tree anyway. The operator's escape is unchanged and still
one keystroke: `Ctrl-C`, then mount by hand.

Audit **Y5** now pins the inverted rule — `probe_cdfs` must mount **exactly
once** and must not umount+remount — so the "safer-looking" retry cannot come
back by refactoring.

### The RAW payload slice's own trap: `BASE` names a profile that is not there

The W4 hand-off is argument-less (`exec sh /cdrom/install/bin/setup.sh`), so it
depends on `/install/profiles/BASE`. On a **RAW payload slice** that file names a
profile the slice does not carry:

```
$ cat  <payload>/profiles/BASE          -> metal-a4000-z3660-raw
$ ls   <payload>/profiles/              -> BASE  raw.profile
```

The slice is **s5**, s5 truncates every name at 14 characters, and
`build-raw-source.sh` therefore rewrites the profile to the s5-safe short name
`raw.profile` — but it does not rewrite `BASE`. On a CD (Rock Ridge) the same
`BASE` resolves fine, so this only bites the medium the metal runbook uses.
`setup.sh` now falls back to `raw.profile` when `BASE`'s own name does not
resolve; the cleaner fix (have `build-raw-source.sh` rewrite `BASE` when it
renames the profile) is queued rather than done, because that tool was outside
this wave's blast radius.

### ★ The other thing W4 measured: the interactive path was six blocks from death

The second `cd-interactive` run got all the way through the flow — probe, hand-off,
interview, **answers beacon verified** — and then the transplant died:

```
Floppy fd0: no space
pkgadd: ERROR: unable to make packaging directory (/usr/apkg/sadm/install/script)
install.sh: FAIL core  pkgadd returned nonzero (rc=1)
install.sh: STOP: base-OS install FAILED for package(s): core -- refusing to arm a half-installed disk
```

The root filesystem in an install is **the 880-block floppy**, and the static
`pkgadd` needs room on it for its packaging directory. An s5 walk of the run's own
`root.adf` against the pristine image says exactly where it went:

| file | size | why it is there |
|---|---|---|
| `/tmp/answers.profil` | 12 180 B (12 blk) | the composed profile — the base profile copied **whole** (the medium is read-only), and the driver sources it |
| `/matrix.ans` | 12 180 B (12 blk) | the beacon — *the same profile again* |
| `/tmp/setup.*`, `/matrix.*` | ~10 blk | the interview's scratch + the harness markers |

**46 free → 8 free**, and `pkgadd` wanted more than that. The W3b runs did the same
thing and passed with **six** blocks to spare — the same s5 walk of `w3b3-cdi`'s
floppy proves it. That was luck, not headroom; W4 spent four of those blocks and
the margin was gone.

Two changes, both in `setup.sh`, and neither of them a workaround:

* **the beacon is the ANSWERS BLOCK, not the whole profile.** It exists to prove
  the *answers* parsed; `answers_extract` only ever reads between the two fence
  markers. −12 blocks.
* **the interview hands its scratch back** before exec'ing the driver (`$ANSWERS`
  and a Custom selection's order file survive — the driver reads both). −5 blocks.

Audit **U** now pins both, including a direct refusal of
`cat "$ANSWERS" > "$ANSWERS_ECHO_PATH"`, so the oversized beacon cannot come back.
The lesson generalizes past this wave: **on the miniroot, the root filesystem is a
floppy with tens of blocks free, and anything an interactive path leaves in `/tmp`
is taken directly out of the installer's own working room.**

### W4 bench acceptance (fresh media, 2026-08-11)

Miniroot: `sum -r` **62398**, 901 120 B, proto-conformant (212 entries), its
`/etc/profile` byte-identical to `src/miniroot/profile` (md5 `f36c5033…`) read back
out of the built ADF. Media: `amix21-install-{base,standard}-w4b-20260811.iso`,
re-mastered from this tree (the tree's `setup.sh` is byte-identical to the disc's).

| cell | verdict | install | attestation | keymap on the target |
|---|---|---|---|---|
| `cd` | **9/9** | `install.sh` rc=0, 297 s | `e483b0cb…` / **4859** + base-5 `86e1ceb1…` / 4793 | none — `default.kmap` absent, `FB_KMAP=` |
| `cd-interactive` | **9/9** | interview → rc=0, 372 s | `e483b0cb…` / **4859** + base-5 exact | none (answered 12) |
| `cd-suomi` | **9/9** | interview → rc=0, 371 s | `e483b0cb…` / **4859** + base-5 exact | **`default.kmap` and `kmap/s` are inode 2073**, `FB_KMAP=s` |
| `cd-standard` | **9/9** | `install.sh` rc=0, 537 s | `4ad8e17b…` / **11012**, base-5 4793 + base-8 4859 contained | none |

The two claims the wave exists for, both green:

* **the Ctrl-C compatibility path is untouched** — `cd` and `cd-standard` reached
  the miniroot shell through the preserved trap exactly as before;
* **the keymap does not fork the attestation** — `cd-suomi` installed with a
  different keyboard baked onto the target and produced **the same canonical
  digest**, because the `default.kmap` link is driver-written and therefore
  invisible to the contents DB.

⚠ **One flake worth recording, and it is not W4's.** The first `cd-standard`
attempt panicked at package 12/17 with `PANIC: swapinub: segu_fault() failed to
swap in the u area` — memory pressure, on a miniroot whose only swap is
`/dev/fakeswap`. The re-run installed all 17 in 537 s with no symptom. W3b's entry
("the 16 MB headroom question is ANSWERED for 17 packages") rests on a single run;
this says the answer is **marginal, not comfortable**, and a 17-package install at
16 MB should be expected to fail occasionally until something changes.

### Repair mode, proven by hand (there is no matrix cell for it)

The matrix only drives installs, so repair was exercised as a scripted console
session against an **already-installed** target (the `cd-standard` run's own
disk), everything typed being letters and digits:

```
Which keyboard are you using? [12] 12
Do you want to install or repair? [install] repair

Scanning SCSI bus for hard disks...
Hard disks attached to this system:
6
What is the SCSI id of the disk you want to repair? 6
 #  Name        Start   Blocks  Size
 1: UNIX_Root     128  161792   79 MB
 2: UNIX_Swap  161920   36864   18 MB
 3: UNIX_Boot  198784    4096    2 MB
Which partition has the root filesystem? 1

/dev/dsk/c6d0s1 mounted on /mnt
Running interactive shell...
Logout with ctrl-D when you are finished
# ls /mnt
bin  cdrom dev  etc  home lost+found mnt opt proc sbin stand tmp usr uu.io.Z var
# cat /mnt/etc/nodename
uaeamix
# exit

Shutting down, please wait...
The system is halted; you may reboot or turn off power.
```

The installed root really is mounted and readable (`uaeamix` is the box the
`cd-standard` cell built), and leaving the sub-shell runs stock's own exit path —
`sync`, `umount /mnt`, `uadmin 2 0`. `fsck` was not exercised: this filesystem was
clean, so the offer did not appear (stock only asks when the mount fails).

## W5: the first-boot configuration dialog — two stages, one application path

Until this wave a freshly-installed box never asked its owner anything. The
installer disarmed the stock sysinit dialog (`chmod -x
/usr/amiga/bin/system.setup`, the stock's own once-only lever) and
`/etc/rc2.d/S16firstboot` baked whatever the **profile** said — nodename,
timezone, address, the shipped root password. That is exactly right for the
unattended tier and useless for anybody installing from a disc onto their own
machine. W5 gives that person the original's first-boot conversation back,
without giving up a single one of the mechanical steps the profile path
guarantees.

### The shape (plan v3 §3)

```
cold boot #1 of the installed system
  /etc/sysinit                                     [core, unmodified]
     └─ sh /usr/amiga/bin/system.setup  iff -x     <- a 3-line STUB, when armed
          exec sh /var/adm/firstboot/firstboot.sh --dialog
          COLLECTS: nodename, domain, timezone, network, repo, passwords,
                    users, monitor, X11, netnews, syslog
          LIVE:     uname -S, the stock ksh TZ menu, passwd/passwdall,
                    amixmkuser, the A2024 relink, amixcolorx, amixnews
          WRITES:   its answers into /var/adm/firstboot/firstboot.conf
          DISARMS:  chmod -x on ITSELF -- only at the clean exit
  /etc/rc2 -> /etc/rc2.d/S16firstboot              [driver-written, both tiers]
     └─ firstboot.sh  APPLIES firstboot.conf
          /etc/nodename, /etc/TIMEZONE, /etc/vfstab, /etc/inet/hosts,
          the repo host + URL, /dev via atdevs, syslog on/off, root-telnet,
          and (dialog only) the default route / zen0 laydown / DNS
```

The dialog **collects**; S16 **applies**. That split is the whole design, and it
is what keeps the interactive tier from silently losing a boot-critical step: an
interrupted dialog still leaves a box with a `/etc/vfstab`, regenerated devices
and its hosts entries, because those never depended on the dialog in the first
place. Unattended installs ship `firstboot.conf` pre-filled, never arm the
dialog, and are **byte-unchanged** — `FIRSTBOOT_DIALOG` defaults to `n` and every
tracked profile says so explicitly.

### Which tier a run is in

| | unattended (`FIRSTBOOT_DIALOG=n`) | interactive (`=y`) |
|---|---|---|
| written by | every canned profile | `setup.sh`, for every interview run |
| the sysinit slot | `chmod -x` (stock's own disarm) | our dialog, `chmod 0755` |
| identity | the profile's `FB_*` keys | the operator's answers, over them |
| S16firstboot | applies | applies |
| root password | the payload `root.shadow` hash | `passwd root`, forced |

**Shutting an installed box down.** Request shutdown/reboot from a root shell on the console, or keep one logged in while issuing it over telnet; a stalled box still answers telnet — sync twice, then power-cycle. (Stock init: a run-level change requested over telnet while the console sits at the getty `login:` prompt stalls at "INIT: New run level: 6"; GI-1, 2026-09-29, reproduced on the stock kernel.)

### Where the dialog lives, and why it is not in the driver

The dialog is the **`--dialog` entry point of `payload/firstboot/firstboot.sh`** —
the same file that carries the apply half. What the driver writes into the stock
slot is a **three-line stub** that execs it. That is not tidiness; it is the
floppy (finding 1 below): a here-doc in a miniroot script is a **real file on the
880-block install floppy from the moment the shell parses the script**, and the
~29 KB dialog could not be one. `firstboot.sh` is already staged on the medium
and already copied onto the target by the arm step, so this costs no new medium
file, no builder change, and no here-doc — and one file now holds both halves of
the two-stage design, sharing one set of `FB_*` variables.

### The accepted wart, recorded

Arming replaces a `core` package member with the stub. The installed-tree
digest does not move — `altroot-attest` is a pure function of what `pkgadd`
*recorded*, not of the live bytes — but `pkgchk`/`--verify` will report
`/usr/amiga/bin/system.setup` as modified. It is the same class as the
`/etc/shadow`, `/etc/TIMEZONE`, `/etc/default/login` and `boot2.boot` edits the
installer already performs, and it was locked as acceptable in plan §8.3 — for a
*replaced body*. What actually ships is the smaller shape the plan kept on file
as its alternative: **a three-line exec wrapper**, with the dialog delivered by
the first-boot payload. The four matrix cells that install the base
set all still attest **`e483b0cb25dfaf4087b1f783335d520d` / 4859**.

### The resilience contract, and what enforces it

| rule | mechanism | audited by |
|---|---|---|
| an interruption re-runs the WHOLE dialog | `chmod -x` fires only in the summary loop's clean-exit branch | Z: exactly one `chmod -x`, and it is in that branch |
| the answers survive a crash after them | `write_conf` runs *before* the disarm | Z: the write precedes the disarm |
| the root password is FORCED | `PW_DONE` gate sits between the summary and the disarm | Z: an unset password exits before the disarm |
| Ctrl-C never exits un-armed | `trap 'INTR=y' 2` + `readask` re-asks | Z: the trap sets a flag, never exits |
| an unreadable console cannot hang the boot | EOF exits, armed | Z: readask's EOF path |
| a re-run cannot accumulate keys | `write_conf` strips its own block first | Z: every key written is stripped first |
| a half-finished dialog still boots | S16 applies the mechanical keys, keeps `PENDING` | Z + the `cd-interrupt` cell |

### Five bench findings this wave paid for

Each was found by **running** the thing — the dialog on a real installed box, and
the installer on the real miniroot (2026-08-12). None of them is visible to
`sh -n`, to a tool allowlist, or to any amount of reading.

1. **★ A here-doc is a FILE on the install floppy, from the moment the shell
   PARSES the script.** The dialog was originally emitted from a quoted here-doc
   in `install.sh` — the `emit_updbootpart` pattern. Both the interactive **and
   the unattended** cell then died before the driver printed its first line:
   `Floppy fd0: no space` → `pkgadd: ERROR: unable to make packaging directory` →
   `STOP: base-OS install FAILED for package(s): core`. Proven on the box
   afterwards: a here-doc inside a function that is **never called** still leaves
   `/tmp/sh<pid>` there for the life of the shell —

   ```
   === A: /tmp at the very first command of the script
   hdtest.sh
   === B: /tmp after the (never called) function containing a here-doc
   hdtest.sh  sh1810
   ```

   and on the miniroot that `/tmp` **is** the 880-block install floppy, which has
   46 free blocks. The updbootpart body cost **16 of those 46 blocks on every
   install since W6-I** — which is the real reason this floppy has been "six
   blocks from death" for three waves. Adding 29 KB of dialog on top asked for
   more than the floppy had. So the dialog moved into `firstboot.sh` behind a
   `--dialog` entry point, the slot gets a three-line stub the driver emits with
   plain `echo` lines, and `installer-selftest` enforces the law.

   > **Two corrections, both W5.5 (2026-08-12).** The figure above read "15,818
   > bytes = 31 of those 46 blocks" when this was written, and **both halves were
   > wrong**. The scanner that produced 15,818 counted the *comment* that
   > described the here-doc as part of it (it began matching at the prose
   > `<<'UPDBOOTPART_EOF'` and ran to the real closing delimiter, swallowing 391
   > bytes); the real body is 15,427 B, which is what `ls -l /tmp/sh250` says on
   > the box. And 31 was that inflated byte count divided by **512**, while the
   > floppy's 46 free blocks are **1 KB** blocks — so the true cost is 16 of 46,
   > not 31 of 46. `_heredoc_bodies` skips whole-line comments now, and the law
   > is **zero here-docs**, because W5.5 moved the last one onto the medium.

2. **The interview was spending 26 of the floppy's 46 free blocks on
   *comments*.** `/tmp/answers.profile` was a byte copy of the base profile, and
   a profile is 90% prose: 13,556 bytes of which about 1,000 are assignments —
   on the same 880-block filesystem the static `pkgadd` needs for
   `/usr/apkg/sadm/install/scripts`. W4 got away with it by **two blocks**; W5's
   profiles grew by twenty lines of comment and the first full run died exactly
   where W4's first one did: `Floppy fd0: no space` → `pkgadd: ERROR: unable to
   make packaging directory` → `STOP: base-OS install FAILED for package(s):
   core`. The interview now copies the **assignments only** (a `case` glob in a
   redirect-fed loop — there is no `grep` or `sed` on the miniroot), which is the
   identical merge mechanism, since `sh` ignores comments when it sources a file.
   ~24 blocks back, and the margin the last three waves were living on is gone.

3. **s5 truncates every name at 14 characters, and `firstboot.conf` is exactly
   14.** The obvious temp name `firstboot.conf.new` therefore *is*
   `firstboot.conf` — and the consequence was not a failed rename but the total
   loss of the file: `sed … "$CONF" > "$NEWCONF"` truncated its own input before
   `sed` read a byte, and `mv` then found source and destination identical and
   took what was left. The next boot would have had no `FB_ROOTDEV` and no
   `/etc/vfstab`. The temp is `fbconf.new` now, and audit Z rejects any pair of
   on-target paths that collide under 14-character truncation.
4. **SVR4 `sed` has no `\|` alternation**, and its failure mode is silence.
   Both of `firstboot.sh`'s duplicate guards were written as
   `\([ TAB]\|$\)` — measured on the box, that expression matches **nothing**, so
   neither guard has fired since W6.4c and a re-run appended the repo-host line a
   second time. (Nobody noticed: the resolver takes the first match.) Both are
   two `-e` expressions now — one for "token followed by whitespace", one for
   "token at end of line" — and audit Z forbids `\|` in any on-box `sed`.
5. **`passwd root` accepts the 4-character bench credential.** SVR4's
   length/complexity rules ("Password is too short — must be at least 6
   characters") are skipped for the superuser; `passwd root` with `pass` returned
   0 and wrote a fresh salt. This is what makes the canned dialog answerable at
   all, and it is why the matrix can still log in afterwards. It also writes a
   `lastchg` of the box's own day, exactly as stock's `passwdall` always did.

### The questions (stock order; ★ = ours)

1. **Nodename** — `amixnode`'s wording; `uname -S` live, `/etc/nodename` is S16's.
2. **Domain** — `amixnode`'s wording, **but the value never reaches
   `/etc/domain`**: this resolver appends a set domain to *every* lookup,
   fully-qualified ones included, so the domain lands only in the
   `/etc/inet/hosts` FQDN alias. A leading dot (stock prepended one, for
   `/etc/domain`) is stripped.
3. **Timezone** — the genuine stock `ksh /usr/amiga/etc/TZ` menu, 56 zones in
   three columns, invoked exactly as `amixdate` invoked it. `TZ` is seeded from
   the profile first so the menu's own default is the medium's zone. The zone is
   read back **colon-stripped** into `FB_TZ`, and `FB_TZ_KEEP=y` tells
   `firstboot.sh` to leave the file the stock tool wrote (which also created the
   `TZ/localtime` alias). The menu's "Other (nonstandard)" escape yields a POSIX
   rule string, which is a valid `TZ` that must **not** get a colon — so that
   case clears `FB_TZ` entirely and no data path can ever produce `TZ=:GMT0`.
   **No date/time question**, deliberately, with the reason printed on screen.
4. ★ **Network** — `Do you want to configure networking? [y]`. Interface
   detection uses what an installed box carries *today*: `aen -S` for the A2065
   (stock's own convention — `network-config` gates itself on it), and for `zen0`
   a `mknod` followed by a pure-sh open test. **Measured**: on a kernel without
   `z3660eth` the shell prints `/dev/zen0: cannot open` and returns 1, and that
   is *all* it reports — no errno reaches the script, so the probe answers
   exactly one question (can this kernel open the device) and nothing more. Then
   address, netmask (classful default), gateway `[none]`, DNS, repository.
5. **Passwords** — stock's two lines, then stock's own `/usr/amiga/bin/passwdall`
   (which runs `passwd root` and propagates the hash to the ~20 SECURELIST
   accounts with one `ed` pass, touching only the hash field). Declining the
   system-accounts question does **not** decline the root password: that one is
   asked either way, and the dialog re-arms until it succeeds. Then the guest
   question (asked only when the account exists) and ★ root-over-the-network,
   **default enabled** — `CONSOLE=` gates root only, and telnet is the only
   remote login this system has.
6. **User creation** — stock's loop around `amixmkuser`.
7. **A2024/Moniterm** — stock, including the `/usr/bin/true`/`false` relink.
8. **X11 colour** — stock, asked unconditionally (`amixcolorx` handles a missing
   `Xcore` itself).
9. **Netnews** — stock, gated on `inews` exactly as stock gated it.
10. ★ **System logging** — the unit is laid down unconditionally by the driver;
    this question only decides the vendor `exit` line. `y` writes **nothing**.
11. **Summary + `Do you wish to change any of these? [n]`** — stock's loop,
    stock's Monitor and NetNews lines, and the only exit that disarms.

### DNS: five parts or none

The enablement is `resolv.conf` + the `libsockdns` relink + `netconfig.DNS` +
an **empty** `/etc/domain` + **literal-IP boot ifconfigs**, and a half-applied
one costs ~3 minutes on every boot (each name-taking `ifconfig` runs before the
default route exists and burns the full resolver retransmit). Part five is why
this is `zen0`-only in W5: our `S99zen` already uses a literal address, but on
`aen0` the bring-up line lives in `/etc/inet/network-config` — **the one file
this project never edits** — so the dialog refuses DNS there out loud rather
than serving half of it. The loopback half of part five (`S69inet`'s `ifconfig
lo0 localhost`) is edited **in place**: that file is a hard link to
`/etc/init.d/inetinit`.

### The aen0 default route — the ed half-patch, and the file it patches

`/etc/inet/rc.inet` was uncaptured until this wave; it is 1,290 B, mode 0444, a
`net` member, and it *ends* with the invitation:

```
# Add lines here to set up routes to gateways, start other daemons, etc.
# For example,
#/usr/sbin/route add default your_nearest_gateway hops_to_gateway
#/usr/sbin/in.named


#return status to /etc/init.d/inetinit
exit $exitcode
```

So the writer follows the ed half-patch discipline exactly: **pre-probe** (one
`^exit ` line, no live route already there), **one `ed` run** (`/^exit /i`),
**post-verify** (the line present exactly once, `exit $exitcode` still there) —
and restores the original if it does not verify. The metric argument (`1`) is
mandatory on this SVR4. It fires only when the dialog collected a gateway
(`FB_NET_CONFIGURED=y`), so no unattended install grows a step it never had.

### New keys

| key | written by | meaning |
|---|---|---|
| `FIRSTBOOT_DIALOG` | profile / `setup.sh` | arm the dialog? Default `n`. |
| `FB_DIALOG` | the driver | the tier, recorded in `firstboot.conf` |
| `FB_ROOT_TELNET` | profile, then the dialog | `y` = `#CONSOLE=` (default) |
| `FB_SYSLOG` | profile, then the dialog | `n` restores the vendor `exit`, in place |
| `FB_NET_CONFIGURED` | the dialog only | gates the network extras |
| `FB_TZ_KEEP` | the dialog only | the stock zone menu already wrote `/etc/TIMEZONE` |
| `FB_REPO_URL` | the driver, then the dialog | re-points `/etc/apkg.conf` when it differs |

### The interrupted-dialog cell, and the s5 fact it turned up

A hard power cut in the middle of the dialog does not merely interrupt the
dialog: on this filesystem it can damage files that have nothing to do with it.
**Measured** (run `w5c-cd-interrupt`, 2026-08-12) — the box was killed nine
seconds after the stock TZ menu's `ed` had written `/etc/TIMEZONE`, and the
recovery boot came up saying:

```
Timezone set to :US/Eastern.
'
' appended
/var/adm/firstboot/firstboot.sh: syntax error at line 2: `'n^LEù^X' unexpected
/etc/rc2: syntax error at line 2: `'n^LEù^X' unexpected
```

Two files that neither the dialog nor S16 ever writes, both garbled at line 2
with binary. s5 has no journal; `/sbin/bcheckrc` answers a dirty root with
`fsck -y` and an automatic reboot, and fsck's free-list salvage is free to hand a
doubly-allocated block to the wrong file. That is a property of the **filesystem**,
not of the dialog, and no arrangement of `chmod -x` can defend against it.

So the cell takes its cut **90 seconds after the last keystroke**, once the
kernel's own delayed writes have landed — which is also the realistic shape of
the accident it models: an operator who walks away and *then* pulls the plug.
What it proves is then exactly the contract, and nothing about fsck.

### Matrix

`cd-interactive` and `cd-suomi` now drive the dialog on their first cold boot
(the box cannot reach run level 2 until it has been answered — which makes
"multiuser" the proof that the conversation completed). `cd`/`cd-standard` assert
the **opposite**: `system.setup` not executable and `FB_NET_CONFIGURED` empty,
which is the mechanical proof that arming is opt-in. New cell **`cd-interrupt`**
power-cycles the box mid-dialog and then requires a healthy boot, a dialog that
re-runs from the top, a clean third boot — and the same digest.

## W5.5: the `swapinub` panic — the install miniroot's only swap is a bit bucket

`cd-standard` — the 17-package `standard` set — stopped being installable. W3b
attested it once; W4 saw one panic and one green re-run; on W5 media it was **2/2
reproducible**, always at the same place:

```
Installing man
Installing public
PANIC: swapinub: segu_fault() failed to swap in the u area
```

Package 12 of 17, every time. The wave began by refusing to guess.

### What `/dev/fakeswap` actually is (measured, not reasoned)

The first thing to do was ask the box. At the miniroot shell, before any install
work (run `w55-m1`, reproduced identically in `w55-repro`):

```
# swap -l
path                 dev  swaplo blocks   free
/dev/fakeswap       19,0       0  20476  20188
```

Three facts fall out of those two lines:

* there is exactly **one** swap area, and it is `/dev/fakeswap` — the name the
  install kernel's `swapfile` bootobj carries, because a floppy miniroot has no
  disk of its own to swap to (`../amix-kerntools/docs/root-by-identity.md` §1.1);
* it is **~10 MB** (20,476 × 512-byte blocks);
* it is on **block major 19**, and block major 19 is **`dummydisk`**
  (grimoire `docs/reference/major-number-registry.md` §3).

`dummydisk` is not storage. A read of 512 bytes from a private `mknod`'d node on
that major transfers **zero bytes** — the output file comes back 0 long. And note
the accounting in `swap -l`: 20,476 total, 20,188 free, so **288 blocks had
already been written there** before the installer even started.

So the install miniroot swaps into a **bit bucket**. Nothing goes wrong while
nobody wants a page back. The failure is a *swap-in*, not a swap-out, and that is
exactly what the panic says: `segu_fault()` asked for a u area that had been
written to a device which stores nothing. It also explains the shape of the
history — whether a swapped-out u area is ever wanted again is a scheduling
accident, so one package set passes, another panics once and then passes, and
seventeen packages make it near-certain.

### The fix is the original installer's own

The stock install script did this, and the comment above it is Commodore's:

```sh
#
#  Add the user declared swap partition as swap space
#
set `swap -l`
if [ "$6" = "/dev/fakeswap" ]
then
	swap -a $SPART 0 $SWAPLEN
	swap -d /dev/fakeswap 0
fi
```

(`/etc/profile` on `floppies/orig/amix_21_root.adf`, between reading the real
partition geometry back out of the RDB and `mkfs`.) It hands the kernel the
**target's own swap slice** — which exists by then and which nothing else opens
during an install — and then **deletes the fake**, so no page can ever land in
the bit bucket again. Our driver had simply never had this step: the NG installer
reimplemented stock's partition arithmetic and its `rdb` grammar, and dropped the
five lines in between.

`install.sh` now carries it as **section 2c**, immediately after the install log
opens:

| step | what it does |
|---|---|
| guard | `swap -l` → is `/dev/fakeswap` still the swap? (stock's `$6` test, as a read loop) |
| length | `/etc/rdb -p $TARGET_SWAP_SLICE $DISK_RAW` → `UNIX_Swap 161920 36864`, field 3 is the truth (the planned `$SWAPLEN` is only the fallback) |
| add | `swap -a /dev/dsk/cNd0s2 0 36864` — 18 MB on the bench 100 MB layout |
| drop | `swap -d /dev/fakeswap 0` |
| record | `swap -l` before **and** after, into `<target>/var/adm/install.log` |

Two deliberate choices:

* **Position.** Stock ran it in its pre-mount window; we run it right after the
  install log opens, so the whole transaction is *in the log* instead of
  console-only. Everything memory-hungry — the seed, the `pkgadd` loop,
  `contents-fsck` — is still far downstream.
* **Fail-open, and asserted from outside.** Swap is a resource, not a contract:
  every install this project has ever completed ran without it, so a driver that
  `STOP`ped here would turn "no swap" into a total failure for the minimal tier
  that does not need it. A failure is loud — a `WARNING` naming the panic it
  invites — and the matrix's new **`swap_check`** reads the two lines back off
  `/var/adm/install.log` on the installed box at cold boot 2, so a silent
  fallback to the fake is a red cell, not a green one. It requires **both**
  halves: adding real swap while leaving `/dev/fakeswap` in the table would still
  let pages land in it.

Nothing about the installed tree moves: no file is written, and attestation is a
function of what `pkgadd` **recorded**.

## W5.5: `updbootpart` moves onto the medium — 16 blocks back on every install

W5's finding 1 — *a here-doc is a file on the install floppy from the moment the
shell parses the script* — left one here-doc standing: `emit_updbootpart`'s. This
is the wave that removes it, and the cost it was charging was measured first, on
a real run, by starting the driver in the background and listing `/tmp`:

```
# ls -l /tmp
total 34
-rw-rw-rw-   1 root     root       15427 Mar 25 04:04 sh250
```

15,427 bytes — byte-for-byte the size of the tracked `payload/updbootpart` — held
on the 880-block install floppy for the whole life of the install shell. That is
**16 of the floppy's 46 free 1 KB blocks** (`ls`'s `total 34` counts 512-byte
units, 16 data blocks + one indirect). Measured free space on the live miniroot
mid-run, by filling the root filesystem until `ENOSPC`: **41,984 bytes** free
with the matrix's own markers already written — so an install used to run with
about **25 KB** of floppy left for the static `pkgadd`'s packaging directory, and
now runs with about **41 KB**.

The move is the staging pattern the medium already uses for `firstboot.sh` and
the `/stand` framing tools:

* `build-install-iso.sh` copies `payload/updbootpart` to `/install/updbootpart`
  and **stops** unless the staged copy is byte-identical to the master — the
  drift lock the here-doc used to give for free, re-established in the one place
  that can still see both files;
* `install.sh`'s arm step is `cp "$INST/updbootpart" …` + `chmod 0755`, and it
  **fails closed** if the medium has no `updbootpart` (media mastered before W5.5
  cannot silently produce a target without the reframe tool);
* the RAW arm inherits it for free — `build-raw-source.sh` stages the payload
  tree by calling `build-install-iso.sh --stage-only`.

**The here-doc law tightens to zero.** All three miniroot scripts (`install.sh`,
`setup.sh`, the miniroot `/etc/profile`) now carry no here-doc at all, so the
budget is 0 bytes rather than W5's "one, at most 16 KB". On the miniroot you
write a file with `echo` lines, or you stage it on the medium and `cp` it. The
scanner behind the law was fixed in the same pass: it skips whole-line comments
now, having previously counted the prose *describing* a here-doc as part of it
(that is where W5's 15,818-byte figure came from), and it carries both a
non-vacuity fixture and a negative one for the comment case.

## W6: the public flavor, the whole set matrix, and two holes surfaced in-product

W6 is the closing wave of the installer-UX rework, and it is mostly about
*honesty*: a disc a stranger can install from, a measured answer for the three
package sets nobody had ever installed, and two in-product messages for the two
classes of machine this installer cannot serve.

### The distro-neutral public flavor (P8.3) — `profiles/public-a3000-a4091.profile`

Every profile in this tree described a machine on one particular LAN. That is
right for the unattended tier — the matrix has to reproduce a byte-identical tree
with nobody at the console, so every answer must be on the disc in advance — and
wrong for a disc handed to somebody else. W6 splits a profile's two dimensions
explicitly:

* the **rig** dimension (boot slice, kernel + sums, SCSI id, `ROOTDEV`) — a
  mastering-time fact about the *media*, gated by ROOTDEV/KSUM. Every profile
  carries it.
* the **`FB_*` answer** dimension (nodename, address, netmask, gateway,
  resolvers, repository + its address, timezone, keymap) — facts about *one
  machine*.

The public flavor keeps the first and empties the second, and sets
`FIRSTBOOT_DIALOG=y` so the answers come from the person at the console on the
first boot. It is a **pure data change on the `FB_*` seam** — not one code path
differs between the flavors, which is what the `cd-public` matrix cell exists to
prove: same interview answers, same dialog answers, and the installed tree must
still be the canonical `minimal` digest.

Three decisions inside it are worth stating in full, because each one looks like
a gap until you see the mechanism behind it:

**The root password is documented, not secret.** Every disc mastered from this
tree carries the same hash in `payload/firstboot/root.shadow` (`pass`), so
secrecy was never on the table and pretending otherwise would be the actual
hazard. What makes it safe is the first-boot dialog's **re-arm**: the
`system.setup` slot is disarmed (`chmod -x`) only at the clean exit of the
summary loop, and that loop cannot be reached without passing the root-password
step. An interruption, a power cut or an EOF leaves the slot executable and the
whole dialog runs again from the top. So a box that ever *finished* its first
boot has an owner-chosen root password, and one that did not is still asking for
one. That is a mechanism, and the `cd-interrupt` cell is what proves it.

**Root-telnet defaults to ENABLED and is never silently disabled** (decision
§8.6). `CONSOLE=` in `/etc/default/login` gates *root* only — ordinary users can
telnet in whichever way it is set — and telnet is the only remote login this
system has until ssh exists. A buyer who cannot reach the box they just installed
has no way to find out why, so the dialog asks, with `y` as the default.

**The repository has a host and no address.** `FB_REPO_HOST=pkg.amigaux.org`,
`FB_REPO_IP=` — we know where the packages live and cannot know that name's
address on a stranger's LAN. The dialog settles it three ways, and says which:
DNS resolves it; or the operator gives the address and `S16firstboot` bakes the
`<ip> <host>` pair into `/etc/inet/hosts`; or neither, and the dialog states out
loud that `apkg update` will not resolve the repository until somebody adds it by
hand. Half a resolver is worse than none.

> ★ **Not pinning the disk size changes the sizing screen, and that is the
> feature.** A LAN profile pins `TARGET_DISK_MB=100`, so the interview shows
> "Your disk is 100 megabytes" and offers root `[79]`. The public flavor pins
> nothing, so the interview falls through to its honest second source — the
> RDB's own extent (`rdb -h 5` + `rdb -p N`, largest start+length). On the
> matrix's mkroot target that extent ends at cylinder 3169, i.e. 202,880 blocks,
> and 202880/2048 truncates to **99**. One megabyte less of disk moves the stock
> default root to `[78]` and caps swap at 18 — so `cd-public` types 78/18 where
> every LAN cell types 79/18, and asserts `TARGET_DISK_MB=99 TARGET_ROOT_MB=78`
> in its beacon. Nothing else about the beacon differs, and `--selftest` requires
> exactly that: the two size keys, and no other. (The first `cd-public` run typed
> the LAN cell's 79 and the interview correctly refused the follow-on swap of 18
> — "You only have 17 remaining megabytes available." — which is the arithmetic
> working, not failing.) In prebuilt mode the plan does not repartition anything:
> the driver mounts slice 1 whatever its size, and W5.5's swap step reads the
> real slice length out of the RDB, so the installed tree is untouched.

> ★ **The empty default was a hang.** Writing the flavor exposed a real defect in
> the shipped dialog: the repository-address loop re-asked until `valid_ip`
> accepted, and against an *empty* default an empty answer became an empty
> `$ask`, which `valid_ip` refuses — forever. Every LAN profile bakes an address,
> so the loop had never been entered without one. A public disc would have hung
> its own first boot at a question with no answerable value. Fixed, and audited:
> `installer-selftest` requires the empty-default escape *and* the sentence that
> states its consequence.

**The negative guarantee is audited, key by key.** "This disc knows nothing about
your network" is exactly the kind of promise that rots without anyone noticing:
nothing goes wrong when `FB_IP` comes back, every gate still passes, and the disc
ships with one household's LAN on it. So `installer-selftest` refuses any
`FIRSTBOOT_DIALOG=y` profile that carries a non-empty `FB_IP`, `FB_NETMASK`,
`FB_GATEWAY`, `FB_DNS1/2`, `FB_DOMAIN`, `FB_REPO_IP` or `TARGET_DISK_MB`, that
defaults to a nodename this tree has shipped on a real box, that turns
root-telnet off, or whose `FB_REPO_URL` names a different host than
`FB_REPO_HOST` — each with its own negative fixture. It also requires that **at
least one** public flavor exists: if the last one were deleted, every disc this
tree can master would bake somebody's LAN, and that is a failure rather than a
silent absence.

### Two coverage holes, surfaced in-product (plan §6)

Both are classes of machine stock 2.1 served and this installer does not. The
plan's requirement was not to fix them but to stop them failing *undiagnosed*.

**No IDE driver.** When the destination scan finds no disks at all, the stock
line — `No hard disks are attached to this system.` — is now followed by the
sentence stock never needed to write, because in 1991 nobody tried to install
UNIX on an IDE machine. Today the most likely reader of that line is somebody
with a stock A4000 or A1200 whose hard disk is working perfectly well and is
simply invisible to this kernel; "no disks" and a dead end leaves them to
conclude their drive is broken. The message names IDE, says no Amiga UNIX IDE
driver has ever existed, and lists what does work (A3000/A4000T onboard, A2091,
A590, A4091).

**★ The OLD_BOOT class — the one that failed silently.** Kickstart 1.3 machines
and A2090 controllers cannot be booted by the modern boot chain at all; stock
handled them with the "old Johann ROM magic cookie" method (RDB moved to block 8,
patched boot block). Nothing in this tree does that, and until W6 nothing
*noticed*: the install would run to completion, write a perfectly good root
filesystem and a boot slice those ROMs cannot read, and the machine would simply
never boot. Unlike the IDE hole, which at least announces itself as "no disks",
this one has no symptom until the disc comes out.

The detection is stock's own, verbatim, using the two probes the miniroot has
carried all along for exactly this purpose (`/etc/romsize`, `/etc/dioc` — both in
`miniroot.proto`, both unused since 1991):

```sh
ROMSIZE=`/etc/romsize`         # < 524288 => a 256 KB ROM => Kickstart 1.3
set `/etc/dioc 1 < $rDISK`     # $1 == "A2090" => the old controller
OLD_BOOT = (small ROM) OR (A2090)
```

The interview (`setup.sh check_old_boot`) **refuses** — printed by name, with the
pointer to the original 2.1 distribution, at the point stock ran the same test:
after the disk is chosen and before a single size is asked for. The driver
(`install.sh` §1b) only **diagnoses**, loudly, and continues: an unattended run
has already been pointed at a profile by somebody who knows the rig, and this is
the last point before the first write, so refusing there would turn a diagnosis
into a new way for a working install to stop.

It **fails open in every direction**. A probe that is missing, unreadable, silent,
or that answers with anything other than a plain number or a controller name
leaves `OLD_BOOT` unset and the install proceeds. The cost of a false positive is
refusing every machine this installer *can* do; the cost of a false negative is
the situation we were already in.

#### What the bench actually reports (measured 2026-08-12)

Run `work/install-matrix/w6-oldboot`, typed at the miniroot shell of the
canonical A3000+A4091 rig through the matrix's own marker channel:

| probe | answer |
|---|---|
| `ls -l /etc/romsize /etc/dioc` | both present, `-rwxrwxrwx`, 2404 B and 4040 B |
| `/etc/romsize` | **`524288`** |
| `/etc/dioc 1 < /dev/rdsk/c6d0s0` | **`A3000 Internal SCSI`** |
| `/etc/dioc 1 < /dev/rdsk/c0d0s0` | `A3000 Internal SCSI` (same answer, other id) |
| `/etc/dioc 1 < /dev/rdsk/c7d0s0` (no disk) | *nothing at all* |
| `/etc/dioc 99 < …` (bad command) | `/etc/dioc: Invalid command: 99` |

★ **The modern arm clears stock's threshold by exactly zero.** A Kickstart 2.04
ROM is 512 KB, and 512 KB *is* 524288, so `[ "$ROMSIZE" -lt 524288 ]` is false by
one byte. That is stock's own constant and we keep it, but it is worth knowing
that the margin is not a margin.

`/etc/dioc`'s two failure shapes are both harmless to the test: an absent disk
produces no output (the `[ -s ]` guard leaves the controller unknown — `set --`
with an empty list is a **no-op** on this shell, the trap `rdb_extent_mb`
documents), and a bad command produces a diagnostic whose first token is not
`A2090`.

#### What is proven, and what is not

The **negative** arm is hardware-proven by the table above. The **positive** arms
are not, and cannot be: there is no IDE-only Amiga and no A2090 on this bench, and
Amiberry cannot present one. So the decision logic is proven host-side instead,
in the `installer-selftest` interview sandbox, which **runs** `setup.sh` against
stub `/etc/romsize` and `/etc/dioc` — seven cases:

* no disks at all → stock's line **and** the IDE pointer;
* `romsize` 262144 → refused by name, before any size question;
* `dioc` → `A2090 Controller` → refused by name;
* the **measured** bench pair (`524288` / `A3000 Internal SCSI`) → *not* refused,
  install proceeds and composes a normal answers profile;
* `romsize` printing its own `Can't get ROM size` error → fails open;
* `dioc` printing nothing → fails open;
* neither probe installed → fails open.

A real KS1.3 or A2090 machine remains **untested end to end**. What is claimed is
narrower and true: the classification is stock's, the refusal fires on stock's
inputs, and nothing this bench can produce makes it fire wrongly.

**Neither message costs the install floppy anything.** `setup.sh` and `install.sh`
live on the CD, not on the 880-block floppy; both additions are `echo` lines and
comments, and there is no here-doc anywhere (the law is zero). The only floppy
traffic is the driver's `/tmp/dioc.$$` — one short line, written and removed
inside the probe — so the ~41 KB of free floppy W5.5 bought back is untouched.

### ★ The `full` set cannot be installed as declared — s5 truncates at 14 characters

`cd-full` is the first time all thirty packages have ever been laid down, and it
found something that is **not** a defect in this installer: two of Commodore's
own 1991 source packages contain filename pairs that cannot coexist on the
filesystem the 1991 installer creates.

Amix's s5 has the classic System V `DIRSIZ = 14`. This project has been bitten by
it twice already — the RAW payload slice (W6-RAW.1) and `firstboot.conf` vs
`firstboot.conf.new` (W5) — and `installer-selftest` audits every on-target path
this tree writes for it. Nobody had ever audited the *package content*.

Observed on the bench, mid-run, exactly as the console printed it:

```
Installing gnusrc2
ERROR: content verification of </mnt/usr/src/pub/gnu/gcc_2.0/typescript.stage1> failed
    file size (20540) expected (16896) actual
    file cksum (22542) expected (52794) actual
pkgadd: ERROR: unable to create unique temporary file <>: (17) File exists
Installation of <gnusrc2> partially failed.
install.sh: WARNING:  FAIL gnusrc2  pkgadd returned nonzero (rc=2)
```

and the cause, read straight out of `gnusrc2`'s own `pkgmap`:

```
1 f none /usr/src/pub/gnu/gcc_2.0/typescript.stage1 0644 bin bin 20540 22542 ...
1 f none /usr/src/pub/gnu/gcc_2.0/typescript.stage2 0644 bin bin 16896 52794 ...
```

Both basenames truncate to **`typescript.sta`**. `stage2` is written second, onto
the same directory entry; pkgadd then verifies `stage1` and finds `stage2`'s
bytes. **The numbers in the error are the two pkgmap lines**: 20540/22542 is
stage1's declaration, 16896/52794 is stage2's.

**The whole-set measurement**, host-side over every `pkgmap` on the disc:

| | |
|---|--:|
| distinct paths in the `full` set | 27,876 |
| basenames longer than 14 characters | 152 |
| **groups that actually COLLIDE** (same directory, same first 14 chars) | **5** |
| **colliding objects** | **10** |

| colliding name | the pair | directory | package |
|---|---|---|---|
| `typescript.sta` | `typescript.stage1` / `typescript.stage2` | `/usr/src/pub/gnu/gcc_2.0/` | `gnusrc2` |
| `amixInitExtDMI` | `amixInitExtDMI.c` / `.o` | `…/ddx/amix/WORK/` | `X11r5src` |
| `amixInitExtMon` | `amixInitExtMono.c` / `.o` | `…/ddx/amix/WORK/` | `X11r5src` |
| `amixInitExtDMI` | `amixInitExtDMI.c` / `.o` | `…/ddx/amix/ZAPHOD/` | `X11r5src` |
| `amixInitExtMon` | `amixInitExtMono.c` / `.o` | `…/ddx/amix/ZAPHOD/` | `X11r5src` |

> ★ **CORRECTION (2026-08-14): this table used to say THREE groups and four
> files to exclude.** W6's scan was **directory-blind** — it grouped on the
> truncated *basename* alone, so the two `amixInitExt*` pairs that exist in
> **both** `WORK/` and `ZAPHOD/` each collapsed into one row. The six filenames
> it named were right; the fix is per-**path**, and there are ten paths. Acting
> on the old figure would have left `ZAPHOD/` broken and `full` still
> unattestable — a whole bench cycle to discover it. The authority is
> **`../amix-packagemanager/docs/s5-14char-collisions.md`** (5 groups, 10
> objects, minimum 5 to drop), independently reproduced by the UFS scoping scan.
> The trap that caused it is worth keeping: pkgmap `s`/`l` records encode
> `path=target`, so a basename analysis that does not split on `=` first
> undercounts.

The other 142 long names are harmless: a *lone* long name round-trips through
truncation, because the kernel truncates on lookup as well as on create, so
`open("typescript.stage1")` finds `typescript.sta`. Only a genuine collision
corrupts anything — which is why 152 over-long names produce exactly 5 problems.

**Only `full` can hit this.** All five groups live in `gnusrc2` and `X11r5src`,
which are source packages present in no other set — and `minimal`, `standard`,
`developer` and `x11` all attested clean this wave, which is the same statement
from the other side. (Those three *do* each write 7–12 files under silently
truncated names; the digest is blind to it, because it attests the declared path,
not the realised one.)

**This is a distribution defect, not an installer defect**, and it would have
bitten in 1991 exactly as it bites now.

### ★ …and it is an **s5** defect, which UFS does not have

Every one of those collisions is a property of the filesystem, not of the
packages: UFS has no 14-character limit, and no 65,535-inode ceiling either (the
1991-installed golden's ufs root carries 229,376 inodes across 448 cylinder
groups; a 400 MB ufs target at the default `nbpi=2048` got ~150,000 against
`full`'s ~29,000 objects). **On a UFS target `full` installs whole and attests at
its natural object count** — nothing dropped, nothing re-minted.

So the two routes are **alternatives, not steps**:

| route | what it does | cost | |
|---|---|---|---|
| packagemanager Option A | drop 5 objects, re-mint `gnusrc2` + `X11r5src`, attest `full` at 28,704 | one build transcript lost; two packages diverge from Commodore's | **NOT TAKEN** |
| **UFS target** | attest `full` as declared, on a filesystem without the limit | one bench cycle on the large-set rig (it cost two — the rig also had to grow) | ★ **TAKEN 2026-08-14** |

**Do not land both** — a `full` that is neither the natural set nor the
documented one is worse than either.

★ **The UFS route was taken and `full` is attested at its NATURAL object count,
28,709** (`68de8880…`, `cd-full` 10/10, 2026-08-14). Option A's 28,704 was the
count of a `full` with five objects deliberately dropped to survive s5; it exists
only as a workaround for a limit this project no longer runs into, so **it should
now be retired rather than sequenced** — landing it would re-mint two packages
away from Commodore's originals to solve a problem that is solved. That is
`amix-packagemanager`'s call to make, but nothing here is waiting on it any more.

### ★ The `full` set fits the filesystem and not the disk (2026-08-14)

The UFS route was taken, and it **worked as a filesystem answer and failed as a
rig**. `work/install-matrix/ufs-full-1`, `cd-full` on the flipped
`bench-a3000-a4091-big` rig, author mode:

- `mkfs_ufs -o free=2,opt=s` authored a 367 MiB Berkeley root on the box and the
  driver mounted it (`/etc/mount /dev/dsk/c6d0s1 /mnt 0 ufs`), with no pre-mount
  fsck — stock's own behaviour on either filesystem.
- W5.5's real swap replaced the dummydisk fake; the `/etc/mnttab` seed line
  stayed the literal `s5`, describing the miniroot as it must.
- **29 of the 30 packages went down in under 14 minutes.** Not one 14-character
  collision: the limit genuinely is not there on ufs.
- Then, inside the thirtieth, the kernel began printing `NOTICE: /mnt: file
  system full` and never stopped. The driver never recorded an exit status and
  the install gate expired at its 240-minute budget. **Nothing was attested** —
  no contents DB was ever written, and an unmeasured digest is an absent one,
  not a pending one.

**The arithmetic is closed, and the culprit is `TMPDIR`.** `pkgadd` spools each
datastream before installing it, and the driver deliberately points `TMPDIR` at
`$TARGET/tmp` (§ the miniroot's own `/tmp` *is* the floppy). So the peak demand
is **the installed tree plus the largest single package** — and the largest,
`X11r5src` at 60.0 MiB, is installed **last**, the worst possible order:

| | MiB |
|---|--:|
| `full` installed tree, realised (computed from the disc's own pkgmaps) | 292.8 |
| `X11r5src` datastream, spooled into `/mnt/tmp` | 60.0 |
| **peak requirement** | **352.8** |
| data area `mkfs_ufs` actually produced on the 367 MiB root (`fs_dsize`) | 344.3 |
| **shortfall** | **8.5** |

Two independent checks say the model is right rather than merely arithmetic.
It predicts the wall **inside `X11r5src` and nowhere earlier** — which is exactly
where the console hit it. And it implies `pkgadd` *frees* each spool: had they
accumulated, 285 MiB of datastreams would have filled the disk around package 20.

**The rig was always marginal; ufs only exposed it.** On the identical 400 MB
disk, s5 leaves 363.0 MiB free at `mkfs` (`w6-cd-full`'s own `layout.json`)
against a 356.4 MiB s5 peak — a **6.6 MiB** margin nobody had ever noticed. ufs
costs **22.7 MiB** of metadata (6.2 % — 148,480 inodes × 128 B = 18.1 MiB of
inode tables, plus cylinder-group overhead) where s5 costs about 4 MiB, and that
18.7 MiB difference turned a 6.6 MiB margin into an 8.5 MiB deficit.

**So this is a disk-size finding, not a filesystem finding.** `full` on ufs needs
a bigger target:

| option | effect | cost | |
|---|---|---|---|
| **`TARGET_DISK_MB=512`** | 480 MB root ⇒ ~450 MiB data area, ~97 MiB over peak | one profile key + the cell's `TARGET_MB` pin, and a bench cycle | ★ **TAKEN** |
| install the largest package **earlier** | drops the peak toward tree-only | changes the **product's** install order, and the order file is generated | refused |
| free each spool before the next `pkgadd` | same, structurally | changes `pkgadd` behaviour — packagemanager's call | refused |

The first is the honest bench fix and touches nothing a user sees; the other two
change the **product** and are not things to reach for to save 8.5 MiB on a bench
rig. **`TARGET_DISK_MB=512` is applied** (profile + the cell's `TARGET_MB` — one
fact in two places, which `--selftest` holds together). The ~97 MiB of resulting
slack is about one and a half `X11r5src` spools, deliberately not a number chosen
to just clear the wall: the demand grows with whatever the largest package
becomes, and the last time this was sized to the tree alone it was wrong by 8.5.
`cd-developer` and `cd-x11` never needed the room — realised trees of 71.3 and
75.5 MiB — but they ride this rig, so each is owed a re-run at the new size.

### ★ 512 MB, and the prediction held to the object (2026-08-14)

The fix was applied and the run is **`work/install-matrix/ufs-full-2`, 10/10**.
Every number above was a prediction before it, and the disk answered each one:

| | predicted | measured | source of the measurement |
|---|--:|--:|---|
| root slice | 479 MiB | **479.0 MiB** | `mkroot.sh --size-mb 512`, host-side, before any bench time was spent |
| ufs data area | 449.4 MiB | **449.4 MiB** | the target's own final `fsck_ufs`: 306,074 used + 154,080 free = 460,154 frags |
| headroom over the 352.8 MiB peak | ~97 MiB | **96.6 MiB** | the same two numbers |
| `full` object count | **28,709** | **28,709** | the run's contents DB, via `altroot-attest` |

The object count is the one that matters, because it is the one that could have
been fudged. **It was pre-registered**: `amix-packagemanager`'s
`tools/repo/s5-collision-scan.py` derives the contents-DB object count exactly
from a set's pkgmaps (verified with zero residual against all four earlier
references — 4859 / 11012 / 11497 / 11546), the figure was written down at
`05ab67a` when nothing was measurable, and it was re-derived against **this
disc** — all seven pinned constants matching — before the box was booted. A
prediction that gets edited to match its measurement was never a prediction.

So: **`full` = `68de888084500aef703a9ccd3eeaa0e5` / 28,709 objects**, base-5 and
base-8 contained exactly by object count (4793 / 4859), `rootfs` gate `ufs`,
bootchain verified, two cold boots. The install took **1132 s** — nineteen
minutes for the entire distribution, against the s5 attempt that spent 96 minutes
inside a single package and never finished.

Two smaller things the run settled:

- **The 8.5 MiB model was right about the mechanism, not just the magnitude.**
  `fsck_ufs` reports 298.9 MiB used for the finished tree, so the X11r5src spool
  really was the difference between fitting and not.
- **`pkgadd` frees each spool**, confirmed rather than inferred: 449.4 MiB of
  data area could not have held 285 MiB of accumulated datastreams *plus* a
  298.9 MiB tree.

### ★ A profile is a rig; a set is a medium (the `attested=y` that was not)

The same failed run printed one more thing worth keeping. Its console said

```
install.sh: install set: full  order: /cdrom/install/order  (attested=y)
```

— for a set that is **not** in `ATTESTED_SETS` and carries `full|-|-` in
`SET_REFS`. The question is whether the flag means something narrower than it
looks, or whether the medium was misinforming the interview. **Neither.**

Both halves of the machinery were correct and were reading each other correctly:

- `tools/build-install-iso.sh` authors `/install/sets` from `ATTESTED_SETS`, so
  the `full` disc's own table said, verbatim, `2 full order n`.
- `src/installer/setup.sh` reads that table and writes `INSTALL_ATTESTED=$SET_ATT`
  into the answers profile. An **interactive** install is therefore always told
  the truth by the disc it is installing from.

The gap is that `cd-full` is **unattended**. There is no interview, so
`INSTALL_ATTESTED` came from the only other source there is — the canned profile
— and `bench-a3000-a4091-big.profile` says `INSTALL_ATTESTED=y`, as every tracked
profile does. **The unattended path never asked the medium at all.**

The reason it was ever plausible to hardcode `y` is written in the key's own
comment: *"the install matrix only ever drives attested sets"*. That was true
when it was written and this run falsified it. The category error underneath is
worth naming, because it generalises: **a profile is a RIG and a set is a
MEDIUM.** One rig profile serves many media, and `bench-a3000-a4091-big` serves
three cells whose postures differ — `cd-developer` and `cd-x11` (attested) and
`cd-full` (not, until it has a green run behind it). No per-rig constant can be
right for all three.

**Fixed, in the direction that cannot lie.** After the driver resolves
`INSTALL_SET` it now reads the medium's own `/install/sets`, and **downgrades
`y`→`n`** if the disc does not vouch for that set:

```
install.sh: attestation: /cdrom/install/sets marks set 'full' UNATTESTED;
            the profile said attested=y -- THE MEDIUM WINS
```

The direction is the whole design. `n`→`y` is refused by construction — a disc
must never be able to talk a run *into* claiming an attestation, and a profile
that deliberately waived the gate keeps its waiver. A medium with **no** table
(pre-W3b, or a raw slice) and a set the table does not mention are both left
alone: absence is *unknown*, never `n`.

**It cannot move a digest**, which is why it was safe to land on the same media
as the 512 MB rig fix rather than waiting for its own cycle. `INSTALL_ATTESTED`
changes nothing the driver *does* — the driver never gated on a digest, the
matrix does — and its only outputs are two `msg` lines in
`/var/adm/install.log`, which is driver-written and invisible to the contents DB.
Audit **X4b** gates it with five negative fixtures, the sharpest being the
"symmetrised" `INSTALL_ATTESTED=$satt`, which reads tidier and quietly opens the
upgrade path. Audit **X6** keeps requiring `y` in every tracked profile, with its
reasoning corrected: `y` is the *default posture* of a canned run, and a blanket
`n` there would waive the gate for every medium that rig ever runs.

There is a pleasing consequence. The very next `cd-full` run — the one that
*measures* `full` for the first time, from a disc mastered before any reference
existed — is now the first run to say `attested=n` about itself, and it is right.

### ★ An s5 filesystem cannot hold more than 65,535 inodes

Building the 400 MB target the large-set cells needed *at the time* — the rig
is 512 MB since 2026-08-14, and s5, which this finding is about, is no longer
what it lays down — walked straight into a limit nothing in this project had met
before. `mkroot.sh --size-mb 400` died with:

```
struct.error: 'H' format requires 0 <= number <= 65535
```

out of `mkfs_s5`'s free-inode-cache pack — a true message about the wrong thing.
The cause is **spec, not policy**: an inode number is **sixteen bits** everywhere
it is written down. A directory entry is `{ ino: 2 bytes big-endian, name: 14 }`,
the superblock's free-inode cache is `ushort s_inode[NICINOD]`, and the
free-inode count `s_tinode` is a `ushort` too. Inode 65536 has no way to be
referenced, cached or counted.

What overflowed was the *ratio*, which is policy: `default_inode_count` asks for
one inode per four blocks, and a 367 MB root wanted **94,208**. The rule now
**saturates** at `MAX_INODES = 65520` (the largest whole i-list block count that
fits — 4,095 blocks × 16). The knee is at a **288 MB root**; below it nothing
moves at all, and that is asserted rather than assumed:

> The canonical 100 MB bench target is **byte-identical** before and after the
> change once `s_time`, `s_state` and every inode's a/m/ctime are masked — 0
> differing bytes, same `isize=1266 fsize=80896 inodes=20224 tfree=79628`. The
> cap cannot move any filesystem this project has already minted.

The 400 MB target now mints cleanly: **375,808 blocks, 65,520 inodes, 371,709
free blocks** (363 MB) — comfortably more than `full`'s 304 MB.

**Is 65,520 enough for the biggest set?** Measured, not assumed: the thirty
`full`-set packages declare **28,965 objects** across their `pkgmap`s. That
figure *over-counts*, because every directory shared between packages is
declared by each of them — and the size of the over-count is knowable from the
two sets we have already attested:

| set | Σ pkgmap objects | attested tree | over-count |
|---|--:|--:|--:|
| `minimal` | 4,937 | 4,859 | 1.6 % |
| `standard` | 11,204 | 11,012 | 1.7 % |
| `full` | **28,965** | *(this wave)* | ~2 % expected |

So a full install lands inside **half** the ceiling. A workload that genuinely
needed more inodes would need a different filesystem, not a different constant.

`mkfs_s5` now also refuses an explicit over-large count with a message that names
the limit and the reason, instead of letting `struct` do it. Six new checks in
`s5.selftest` pin the knee, the saturation, the 100 MB no-op and the ceiling's
shape; one more mints the 400 MB root and reads it back.

### The RAW catalog region at 30 packages — measured, and not close to the cap

The RAW source layout (`gen-catalog.py --raw`, the `SRC_RAW` contract) puts the
catalog at **offset 0** with a hard `RAW_CAT_MAX` of **32,768 bytes**, then
`catalog.md5` at 32768 (`RAW_MD5_MAX` 512 B) and the package datastreams from
65536. Every set so far has been small; thirty packages is the first time the
region was worth measuring. Read off the mastered discs (the same generator
writes the CD's `/catalog` and the RAW region's, over the same rows):

| set | package rows | catalog lines | catalog bytes | of the 32,768 B region |
|---|--:|--:|--:|--:|
| `minimal` | 8 | 18 | 1,402 | 4.3 % |
| `standard` | 17 | 36 | 2,784 | 8.5 % |
| `x11` | 18 | 38 | 2,918 | 8.9 % |
| `developer` | 19 | 40 | 3,103 | 9.5 % |
| **`full`** | **30** | **62** | **4,819** | **14.7 %** |

At ~78 bytes per line the region would take roughly 400 lines — on the order of
**200 packages** — before it filled. `catalog.md5` is one hex digest and a
newline (33 B) whatever the package count. So the RAW arm needs no change for
the full set, and the "32+ rows" question is answered with room to spare rather
than with an assurance.

### The device-major decode defect (W5.5 queue, closed)

`tools/lib/s5.py` had no device decoder; `miniroot-selftest.py` read the major out
of the **high byte of `di_addr` L3 slot 0**, as if a device inode stored a packed
16-bit `o_dev_t` there. It does not. The layout — observed identically across all
124 device nodes of the genuine 1991 `amix_21_root.adf` *and* of both of our
on-box-authored miniroots, and first written down by `tools/s5-setdev.py` in July —
is four L3 slots:

```
di_addr L3[0] = minor      L3[1] = 0x000001 (constant)
di_addr L3[2] = MAJOR      L3[3] = minor (duplicate)      L3[4..12] = 0
```

Every minor in a stock miniroot is < 256, so the old spelling returned the **right
minor and major 0 for every node in the tree** — and `miniroot.proto` had recorded
those zeroes, so the conformance check agreed with itself. A gate that compares two
copies of the same mistake.

Closed in lockstep: `s5.decode_dev()` (fail-closed — it refuses any `di_addr` whose
constant slot, duplicate minor or zero tail does not match), `miniroot-selftest`
uses it, and **123 of the proto's 124 device lines** gained their real major. Every
**minor is unchanged** — the signature of a major-only defect — and the one line
that did not move is `/dev/console`, which is genuinely char major 0.

The decoded values cross-check exactly against the grimoire major-number registry:
`/dev/dsk/*` block **18** (`dd`), `/dev/rdsk/*` char **40** (`dd`), `/dev/fakeswap`
block **19** (`dummydisk` — the bit bucket W5.5 named), `/dev/dsk/fd*` block **16**
and `/dev/rdsk/fd0f` char **17** (`fd`), `/dev/rmt/*` char **16** (`ct`),
`mem`/`kmem`/`null`/`zero` char **3**, `/dev/tty` **2**, `/dev/amiga` **6**,
`/dev/scsi` **11**, `/dev/machid` **12**. The corrected proto conforms against both
built miniroot images (`fd0` and `slice1`), 212 entries / 124 device nodes.

A new structural gate (`gate_dev_majors`) pins the well-known majors and refuses
the all-zero signature outright, so the proto cannot drift back in either
direction; each rule has a negative fixture.

### `/install/profiles/BASE` on a RAW slice named a file that was not there

`build-install-iso.sh` writes `/install/profiles/BASE` with the long repo profile
name. `build-raw-source.sh` then makes the payload tree s5-safe — s5 truncates at
14 characters, so it keeps exactly one profile under the short name `raw.profile`
and deletes the rest — and left `BASE` naming the file it had just removed.
Nothing ever failed, because `setup.sh` carries a fallback (`raw.profile` when
`BASE` does not resolve) written for precisely this reason. W6 writes the truth
and keeps the fallback for pre-W6 media, so the fallback stops being
load-bearing; the builder now also refuses to finish if `BASE` names a profile it
did not stage.

### W6 bench acceptance — ten cells, nine green

Media mastered from the committed tree (`…-w6-20260812r3.iso`, one per set);
every cell a full from-scratch install on fresh media.

| cell | verdict | install | installed-tree digest |
|---|---|--:|---|
| `cd` | **9/9** | 297 s | `e483b0cb…` / 4859 + base-5 exact |
| `cd-interactive` | **9/9** | 372 s | `e483b0cb…` / 4859 |
| `cd-suomi` | **9/9** | 372 s | `e483b0cb…` / 4859; `default.kmap` = `kmap/s`, inode 2073 |
| `cd-interrupt` | **9/9** | 372 s | `e483b0cb…` / 4859, through the mid-dialog power cut |
| `cd-standard` (1st) | **9/9** | 537 s | `4ad8e17b…` / 11012 |
| `cd-standard` (2nd) | **9/9** | 537 s | `4ad8e17b…` / 11012, identical |
| ★ `cd-public` | **9/9** | 372 s | `e483b0cb…` / **4859 — UNMOVED** |
| ★ `cd-developer` | **9/9** | 599 s | **`ebd61ce1…` / 11497** (attested) |
| ★ `cd-x11` | **9/9** | 598 s | **`5439f78f…` / 11546** (attested) |
| `cd-full` (s5, 400 MB, W6) | **RED** | — | not attestable on s5; see the 14-character finding above |
| `cd-full` (ufs, 400 MB, 08-14) | **RED** | — | **ran out of disk**, not out of names: 29/30 packages in <14 min, then `/mnt: file system full` inside the thirtieth. Nothing attested — see *The `full` set fits the filesystem and not the disk* below |
| ★★ `cd-full` (ufs, **512 MB**, 08-14) | **10/10** | 1132 s install | **`68de888084500aef703a9ccd3eeaa0e5` / 28709 — ATTESTED**, and 28,709 was the pre-registered prediction. The whole distribution, installed and cold-booted. `work/install-matrix/ufs-full-2` |

★ **The public flavor's whole claim, tested.** `cd-public` installed from a disc
that bakes no nodename, no address, no netmask, no gateway, no resolver, no
repository address and no disk size, driven through the same interview and the
same first-boot dialog — and produced **byte-for-byte the canonical `minimal`
tree**. Emptying the `FB_*` seam moves nothing. That is what makes the flavor a
data change rather than a second product.

**The `standard` soak verdict: stable.** Four consecutive greens on freshly
mastered media across two waves and two driver generations — 2× in W5.5 and 2×
here — at the identical digest and, both times, the identical 537 s. Before
W5.5's real-swap fix the same cell reproduced `PANIC: swapinub` **3 times out of
3**. The set is no longer flaky, and the fix is the reason.

**What `cd-full` cost, and what it measured.** The run reached `Xsource` (the
second-largest package, 49 MB / 4,312 objects) about 24 minutes in and was still
inside it when the install gate's **120-minute budget expired** — with the
emulator pinned at ~116 % CPU throughout, so it was working, not wedged. For
scale, the entire 17-package 61 MB `standard` install takes **537 s**. The
slowdown is not proportional to bytes or objects and the most likely cause was
thought to be the contents DB: by `Xsource` it holds ~19,000 entries, and SVR4
`pkgadd` rewrites and re-scans it per package.

> ★ **CORRECTION (2026-08-14): that theory is refuted, and the cause was the
> filesystem.** The ufs run put **29 of the 30 packages down in under 14
> minutes** — past `Xsource` entirely and into `X11r5src` — with the same
> contents DB growing exactly the same way. Whatever the s5 run was spending
> 96 minutes on inside one package, it was not the contents DB. The plausible
> remaining cause is s5 itself: 1 KB blocks and a linear free list against ufs's
> 8 KB blocks and cylinder groups, on a filesystem already ~230 MB full.

## ★ UFS as the default target filesystem (2026-08-14)

**UFS is now what a person installing from this disc gets.** The stock s5/ufs
question is back, verbatim except for one word — its default — and it lands in a
new driver key, `TARGET_ROOT_FSTYPE`.

Two read-only investigations settled this before a line was written, and between
them they contain every measured fact behind it:

- `docs/ufs-target-scoping.md` — the media/tooling half (this repo).
- `../amix-kerntools/docs/ufs-root-kernel-capability.md` — the kernel half.

### The finding that made it cheap: almost none of it had to be built

| question | answer |
|---|---|
| does the miniroot carry `mkfs_ufs` / `fsck_ufs`? | **yes, since W5.2** — proto members, byte-identical to the stock root floppy's, every undefined symbol resolving against the miniroot's own `libc.so.1`. The build starts from a byte copy of the stock image and the proto preserves them |
| does the install kernel have `ufs`? | **yes** — `ufsinit` at `vfssw[2]` in all ten kernels examined, `fd0unix` included |
| does it need configuring? | **no** — `rootfstype` is compiled **empty** (*"Empty means try them all"*), so `vfs_mountroot` probes `s5` first, gets `EINVAL` on a ufs root, and takes `ufs` on the second try |
| does the installed system have the ufs back end? | **yes** — `core-2.1.pkg` ships `mkfs/fsck/mount/labelit` + 17 more; a *larger* suite than the s5 one |
| kernel cost | **zero bytes, zero boot allocation** |

The floppy budget makes the first row load-bearing rather than lucky: the
miniroot has **46 free blocks**. Had those two binaries not already been on it,
65 KB of new ELF would not have fitted and the whole lane would have been blocked
on the medium.

### Why `[ufs]` and not `[s5]` — the one deliberate divergence

Stock's prompt read `[s5]`; ours reads `[ufs]`. Everything else — the menu text,
the blank lines around it, the branch structure, `UFS_OPT="-o free=2,opt=s"`, the
position in the flow — is **stock's, extracted rather than remembered**: the
whole block was read out of `/etc/profile` on `floppies/orig/amix_21_root.adf`
(ino 166, 19,351 B, md5 `97f800ec7bcd627bfed2322fdc19f86b`) with
`tools/lib/s5.py`, and it is quoted in full in `setup.sh` beside our version.
That extraction also confirmed, line by line, every choice the driver makes:
`mkfs_${ROOT_FSYS} $ROOT_OPT $UPART $ROOTLEN` with `UPART=/dev/dsk/…` (the
**block** node), `/etc/mount $UPART /mnt 0 ${ROOT_FSYS}` immediately after with
**no fsck between them**, no `labelit` anywhere, `MARGIN=ROOTLEN/50` before
package selection, and a vfstab whose column 4 is `${ROOT_FSYS}` — stock
parameterised that column; the literal `s5` in our `firstboot.sh` was **our own**
hardcode, not an inherited one.

Three reasons for moving the default, in order of weight:

1. **The 1991 documentation recommends ufs over s5**, and whoever built the Amix
   install this project *inherited* took that advice: both `amix-images` goldens
   carry a UFS1 big-endian root whose superblock reads back `fs_minfree=2` /
   `fs_optim=SPACE` — the exact fingerprint of `mkfs_ufs -o free=2,opt=s` — and
   `fs_size × fs_fsize` equal to the slice size to the byte.
2. **s5's limits are real and we have hit both**: 14-character names (which is
   why `full` is unattestable, and why `standard`/`developer`/`x11` each write
   7–12 files under silently truncated names) and 65,535 inodes.
3. **The bench has been running a ufs root all along.** The golden *build box* —
   the image every metal-proven Amix kernel was linked on — roots on ufs and
   boots one of our own recent kernels off it. The probe-then-mount path is
   proven by daily operation, not only by disassembly.

★ **"Stock forced s5" is half a myth.** The force is real but it lives in
`if [ "$OLD_BOOT" = "0" ]`'s *else* arm — `ROOT_FSYS="s5"  # Johann ROM can only
boot s5 filesystem` — and OLD_BOOT is a machine class we refuse outright, by
name, before any of this runs. The branch that forces s5 is one we never take.

### What the type reaches, and the two places it must not

| reaches | how |
|---|---|
| `mkfs` | ufs: `mkfs_ufs -o free=2,opt=s <BLOCK node> $ROOTLEN` — stock's line verbatim. s5: unchanged, raw node |
| `labelit` | s5 only. There is no `/usr/lib/fs/ufs/labelit` on the medium — and **stock ran `labelit` on neither filesystem**; the s5 call is our own addition |
| the pre-mount `fsck` | s5 only. Stock fscks only in `repairdisk()`, never between `mkfs` and `mount`. On ufs it would also mean reading through the *raw* node for bytes `mkfs` wrote through the *block* node |
| the mount | `/etc/mount $ROOT_BLK /mnt 0 <type>` — passed straight to `mount(2)`; `/etc/mount` has no type table |
| the final `fsck` | both, after the unmount — where the raw node is the correct one, and on ufs the only fsck of the run |
| `/etc/vfstab` column 4 | via `FB_ROOT_FSTYPE` in `firstboot.conf` |
| `/etc/vfstab` column 6 | **`no`, on both rows, whatever the type** — the kernel mounts root itself from its baked-in `rootdev`, so a `yes` only orders `mountall` to re-mount an already-mounted filesystem and earns `mount: Device busy` / `mount: /dev/dsk/cNd0s1 on /: Device busy` / `mount: giving up on: /` on **every** boot (metal, 2026-08-15). Stock's own here-doc ends `1  no  -`; the `yes` was ours, and it is gone. The swap row was always `no` — a swap slice is handed to the kernel's swap layer, never mounted |

| must NOT reach | why |
|---|---|
| the `/etc/mnttab` seed line | it describes the **running miniroot** — the floppy, which is s5 whatever the target is — for `pkgadd`'s `get_mntinfo`. Parameterising it is the most plausible wrong "fix" in this whole change, so `installer-selftest` audit AA pins it with a negative fixture |
| swap and the boot slice | both **raw**. `swap -a` hands a block device to the kernel's swap layer; the ROM and `boot1` read the boot slice as raw sectors. No filesystem is involved in either |
| the installed-tree **digest** | attestation is `(contents DB, passwd, group)` and none of it has a filesystem field. **A ufs install of a set must reproduce that set's existing digest exactly.** A difference is a bug, not a new baseline — which is what makes the acceptance criterion unusually strong *and* free |

### Everything downstream of `vfstab` was already type-generic

`/usr/sbin/bcheckrc` (read out of the golden ufs root) asks the **kernel** first —
`set \`/sbin/df -n /\`` — falls back to `vfstab`, and builds `fstyp="-F $3"` for
`/sbin/fsck`, which execs `/usr/lib/fs/<type>/fsck`. So boot-time fsck and the
root remount needed no change beyond the one column. The `fsckdev` column being
the **char** node (while column 1 is the block node) was already right, and it
matters more on ufs: that is the fsck that actually runs at every boot.

### `ufs` needs AUTHOR mode, and that is a design decision, not a limitation

`mkfs_ufs` is a 20 KB C program **on the box**. A host-side UFS *writer* would
need cylinder groups, per-cg bitmaps, `csum` summary blocks, the `FS_42POSTBLFMT`
rotational tables, four superblock backups per group and `lost+found`
preallocation — realistically 600–900 lines with genuine correctness risk. It is
not being written. Consequences, all fail-closed:

- `tools/mkroot.sh` mints s5 and only s5, so `INSTALL_TARGET_PREBUILT=1`
  **refuses** a non-s5 target rather than mounting an s5 filesystem under a
  vfstab that says ufs;
- the interview does not *ask* in prebuilt mode — that would be the locked
  question the stock idiom forbids — and composes `s5` explicitly, so the four
  prebuilt interactive cells (`cd-interactive`, `cd-suomi`, `cd-interrupt`,
  `cd-public`) have byte-identical typed conversations to before;
- a real install onto a real blank disk is author mode anyway, which is where
  the question belongs and where `mkfs_ufs` actually runs.

A host-side **reader** is a different matter and was measured, not estimated: a
102-line UFS1 reader spike walks the golden's whole tree in 0.10 s and reproduces
**726 of 729** same-size files' 1991 pkgmap checksums (the three misses are
`/etc/nodename`, `/etc/saf/tcp/_pmtab` and `/stand/boot2.boot` — files that are
*supposed* to differ). It is a nice-to-have; the digest never needed it.

### The new `rootfs` gate — the only one that can see the filesystem

`tools/rootfs-type.py` walks a target `.hdf`'s RDB with `tools/lib/rdb.py`, seeks
to the root slice and identifies the filesystem from its **superblock magic** —
host-side, box down, no loop mount, no root, no host-kernel filesystem support.

It exists because the other nine gates are blind to this. The digest has no
filesystem field *by design*; the boot chain is raw sectors; the cold boots prove
the box runs. So a `cd-ufs` run whose author step silently did nothing would
re-use the s5 root `mkroot.sh` minted host-side and **pass all nine** — a perfect
forgery with no ufs anywhere. Reading the disk is the only thing that separates
those two runs, which is why the check reads the disk and not the install log.

It is `REQUIRED` for **every** cell (`EXPECT_FSTYPE`, default `s5`): an s5 cell
that quietly produced something else is exactly as wrong, and the s5 arms are
what keep the ufs claim a *comparison* rather than a measurement. It also asserts
the kernel's own root-mount preconditions, read out of `mountfs` by disassembly —
`fs_magic == 0x00011954`, `1380 ≤ fs_bsize ≤ 8192`, `fs_frag ≤ 8` — so a green
means "this disk carries a filesystem this kernel family will accept as root",
not merely "the magic number is present".

### Why every tracked profile still says `s5`

The key's default is `s5` and every profile declares `s5`, while the *product*
default is `ufs`. That is not a contradiction, it is two different defaults doing
two different jobs:

- the **key's** default is the compatibility floor — the seam law every W1 key
  follows, so a profile or a medium written before this key installs the
  byte-identical tree it always did;
- the **profiles** are the pinned rigs every attested digest was measured on.
  Keeping them at s5 leaves the whole existing matrix an s5 regression arm and
  gives `cd-ufs` a single-variable comparison against `cd-author`.

Flipping a rig is a deliberate per-rig act with its own bench run behind it. Two
are queued and both are out of scope here: `bench-a3000-a4091-big` for the first
`full` attestation, and the metal rigs — which additionally need a metal session,
because **a UFS root has never booted on real A4000+Z3660 hardware**. The
residual risk there is low (the root-mount code is byte-identical across all ten
kernels; `rootdev` carries no fs information; UFS read/write over the metal-lineage
`z3660scsi` driver is already soaked clean, 40/40 digests) but it is not zero,
and it is not a claim to make from the bench.

### What proves it, host-side

- `installer-selftest` audit **AA** — the driver's four fs-dependent steps, the
  two traps, the first-boot handoff, the proto's coverage, and every profile's
  key; each with a negative fixture (six of them, all plausible wrong versions of
  this change rather than nonsense ones).
- `installer-selftest` audit **W** — the interview is *run*: the menu appears in
  the stock position, a bare RETURN takes `ufs`, `s5` is still typeable, a typo
  re-asks (stock's own `*` arm was quoted, so it matched a literal asterisk and
  never fired), a prebuilt target is never asked, and the **2 % superuser reserve
  is charged on ufs and only on ufs** — proven by a pair of cases differing in
  one typed word, over a catalog sized to exactly the megabyte where the reserve
  decides the answer.
- `tools/rootfs-type.py --self-test` — the classifier's gates fire on a zeroed
  slice, a wrong magic, a truncated slice, and each of the kernel's three
  root-mount bounds.

### Bench acceptance — `cd-ufs` 10/10, and `cd` unmoved beside it

Media mastered from the committed tree (`amix21-install-base-ufs-20260814b.iso`);
both cells a full from-scratch install on fresh media, same disc, same rig, same
100 MB target, same `minimal` set.

| cell | verdict | target build | install | root slice, read host-side | installed digest |
|---|---|---|--:|---|---|
| ★ `cd-ufs` | **10/10** | **author**, `mkfs_ufs` on the box | 314 s | **ufs** — bsize 8192 / fsize 1024 / frag 8, minfree **2 %**, optim **SPACE**, 63 cyl groups | `e483b0cb…` / **4859** + base-5 `86e1ceb1…` / 4793 |
| `cd` | **10/10** | prebuilt (`mkroot.sh`) | 297 s | **s5** — `s_type=2`, `s_fsize=80896` | `e483b0cb…` / **4859** + base-5 `86e1ceb1…` / 4793 |

**The digest did not move by a single byte.** That was the whole claim, and it is
now a measurement rather than an argument: attestation is contents-DB-derived, so
the same set on two different filesystems attests identically. `cd` beside it is
the regression arm — the s5 path is byte-unchanged.

★ **`mkfs_ufs` had never been executed in this project before this run.** Every
claim in the scoping report about it was static: file identity, ELF headers,
symbol resolution, the stock call site, and a superblock somebody else's
`mkfs_ufs` wrote in 1991. The console records the first execution:

```
Making filesystems.  This will take a few minutes.
+ /bin/mkfs_ufs -o free=2,opt=s /dev/dsk/c6d0s1 161792
Warning: 46 sector(s) in last cylinder unallocated
/dev/dsk/c6d0s1:        161792 sectors in 63 cylinders of 9 tracks, 18 sectors
        82.8Mb in 63 cyl groups (16 c/g, 1.33MB/g, 512 i/g)
```

and it produced, on a 79 MB slice it had never been fed before, **exactly stock's
recipe**: `minfree=2` and `optim=SPACE` read back off the disk host-side, with
`fs_size × fs_fsize = 82,837,504` equal to the slice size **to the byte** — the
same fingerprint as the 1991-installed golden, from our own installer. The
512-block size operand is confirmed by that equality (161792 = 79 × 2048).

Everything else the run settled, in order:

- **`/etc/mount … 0 ufs` mounted it** with no kernel change, exactly as the
  capability paper predicted (`ufs` at `vfssw[2]`, `rootfstype` empty).
- **No pre-mount fsck was needed** — stock's sequence works, as it did in 1991.
  The console prints the driver saying so, then mounts.
- **The `/etc/mnttab` seed line stayed `s5`** (visible on the console), and
  `pkgadd` transplanted all eight packages through it.
- **`lost+found` preseeded to 100 slots on ufs** — the stock step is
  filesystem-agnostic after all.
- **The post-unmount `fsck_ufs` came back clean**: phases 1–5, `4771 files, 27936
  used, 47905 free (1047 frags, 5857 blocks, 1.4% fragmentation)`.
- **The box cold-booted off it, twice**, to run level 2 + LAN, through the
  first-boot dialog and its once-only disarm — the first time a from-scratch
  *installed* UFS root has ever booted in this project.
- **The installed `/etc/vfstab` says `ufs`** — byte-searched out of the target
  image afterwards; exactly one root row, and no `s5`-typed root row anywhere on
  the disk. The `cd` target under the identical search says `s5`. The
  `FB_ROOT_FSTYPE` handoff is proven on the disk, not just in the code.

Run directories: `work/install-matrix/20260814-062517-cd-ufs` and
`…/20260814-064401-cd`. (An earlier `cd-ufs` at `…/20260814-060702-cd-ufs` was
also 10/10, on media whose menu text was one string away from stock's; the disc
was re-mastered once the stock bytes were extracted, and the acceptance run above
is the one whose media matches the committed tree.)

## ★ P5.4-R2: the bench runtime golden, minted by the installer (2026-08-14)

**The bench golden is no longer an inherited disk.** Every golden this project has
run on the bench descends from `amix-images/masters/amix-uaebase-golden-2026-07-11.hdf`,
which is itself a copy of a user-prepared `Amix_UAE.hdf` whose own provenance is
"someone installed Amix onto it, once, years ago". That was fine while we had no
installer. We have one, it is attested, and P5.4-R2 replaces the inherited lineage
with an image whose every object is accounted for by a package digest.

The deliverable is a **candidate** — blessing it into `amix-images/masters/` happens
separately, after the R3 metal session, so nothing here writes that store.

### The cell IS the recipe

`tools/install-matrix.sh cd-standard-ufs` — added by this packet, and the reason it
is a matrix cell rather than a one-off script is that a golden whose provenance is a
transcript is a golden nobody can re-mint. The run's own `target.hdf` is the image;
re-running the cell reproduces it gate for gate.

It is `cd-standard`'s **set** on `cd-full`'s **rig**:

| axis | `cd-standard` (the regression arm) | `cd-standard-ufs` (the golden) | why |
|---|---|---|---|
| package set | `standard`, 17 packages | **the same** | user decision; the reference must not move |
| root fs | s5 | **ufs** | the default since 2026-08-14 — a golden should be what an installer ships |
| target build | prebuilt (mkroot host-side) | **author** (on-box `mkfs_ufs`) | there is no host-side UFS writer; `mkroot.sh` mints s5 and only s5 |
| disk | 100 MB (79 MB root) | **512 MB** (479 MiB root) | see the arithmetic below |
| result | an attestation | **a working box** | 379 MiB free instead of 12 |

### Why 512 MB and not the canonical 100

The `cd-full` lesson applies to every set, not just the big one: `pkgadd` **spools
each datastream into `TMPDIR`**, which the driver points at the target, so the demand
is not the tree — it is **tree + largest single package**. Measured off this disc's
own catalog `isize` block:

```
installed tree      63,715,109 B  =  60.8 MiB   (17 packages)
largest .pkg spool  core          =  10.7 MiB
peak                              =  71.5 MiB
```

against the two candidate rigs:

```
100 MB rig   79.0 MiB root  ->  ~74.0 MiB ufs data area   margin  2.5 MiB
512 MB rig  479.0 MiB root  ->  ~449.4 MiB ufs data area  margin 377.9 MiB
```

A 2.5 MiB margin is the same shape of margin that killed `cd-full` on the 400 MB rig
(8.5 MiB short, measured). It is also beside the point: a runtime golden that comes
up with 12 MB free is not a bench box. The 512 MB rig was already proven three times
(`full`, `developer`, `x11`), so the golden rides a measured arrangement rather than
a new one.

### The run (`work/install-matrix/r2-golden`, 2026-08-14)

**10/10, and the digest did not move.**

```
preflight  PASS    0  cell=cd-standard-ufs amiberry=amix-v830 nonce=MTX71283662
workset    PASS    3  fresh target+floppies+ISO, 2 rigs generated
mediaboot  PASS  169  install kernel booted, root floppy mounted, miniroot shell confirmed by nonce
source     PASS   64  source mounted at /cdrom and proven readable
install    PASS  412  install.sh bench-a3000-a4091-big rc=0 (author target)
coldboot   PASS  120  2 cold boots to run-level 2 + LAN; identity uaeamix baked, first-boot once-only
digest     PASS  100  set 'standard' 4ad8e17b69b32208c9fffa600596a428 (11012 obj) + base-5 86e1ceb144f1328bf441c5df38fc2798 (4793 obj)
bootchain  PASS   69  target boot slice verified host-side (flags-based boot2)
rootfs     PASS    0  root slice 1 verified host-side: ufs, mountable as root
teardown   PASS    3  emulator confirmed gone, tap0 confirmed gone
```

`standard` = **4ad8e17b69b32208c9fffa600596a428 / 11,012 objects**, byte-exact against
the W6 reference — which was measured on **s5**, **prebuilt**, **100 MB**, from the
`…-standard-w6-20260812r3` disc (run `work/install-matrix/w6-cd-standard`), i.e. four
things different at once and a freshly mastered medium besides. That is the digest's
filesystem- and size-independence
measured a *third* time, on a *third* set, and it is what makes this a regression test
rather than the minting of a new baseline.

Media: `work/iso/amix21-install-standard-512-20260814.iso`, freshly mastered from the
committed tree with `--profile bench-a3000-a4091-big --set standard` (the fresh-media
rule; the W6 standard disc predates the UFS default). Note the medium is usable by
**both** standard cells: `build-install-iso.sh` stages every `profiles/*.profile`
verbatim, and the two bench profiles name the same `BOOTSLICE_IMG` with the same
`ROOTDEV`, so they differ only in the two keys the driver reads at install time.

Install time is 412 s against `cd-standard`'s 537 s on s5 — the same seventeen
packages, ufs, and another data point against the "contents DB at ~19k entries"
slowness theory `cd-full` already refuted.

### The network-ready-ification is the installer's, not a post-step

The 2026-07-14 recipe (**never** edit `/etc/inet/network-config`; bake only hosts, the
password and `CONSOLE=`) is not applied to this image by hand — `firstboot.sh` *is*
that recipe, and has been since W5. Read off the candidate itself on a **third** cold
boot (`work/golden-candidate/netready-check.out`, one held telnet session):

| fact | measured |
|---|---|
| identity | `uname -a` → `UNIX_System_V uaeamix 4.0 2.1c 0800430 Amiga (Unlimited) m68k`; `who -r` → run-level 2 |
| interface | `aen0: flags=23<UP,BROADCAST,NOTRAILERS> inet 192.0.2.38 netmask ffffff00` |
| the law | `/etc/inet/network-config`: `sum -r` **33904**, **685 bytes**, mtime **Nov 22 1991**, mode `-r--r--r-- root sys` — byte-identical to `core-2.1.pkg`'s shipped copy. **Untouched**, and that is now a measurement |
| hosts | `192.0.2.38 uaeamix uaeamix.example.net` + the repo host `192.0.2.2 files.example.net` |
| root pw | `root:ROOT_HASH_PLACEHOLDER:::::::` — the bench credential `pass`, and **every aging field empty**: the RTC-1978 `lastchg` trap cannot bite this image |
| root telnet | `#CONSOLE=/dev/console` (commented = permitted) |
| vfstab | `/dev/dsk/c6d0s1 /dev/rdsk/c6d0s1 / ufs 1 yes -` — left as measured. That `yes` is the mount-at-boot defect fixed on 2026-08-15; this image predates the fix, so it still grumbles `Device busy` at every boot. Media mastered after it write `1 no -` |
| TZ | `TZ=:US/Eastern` — with the leading colon (the W5 `getpwnam` cascade fix) |
| filesystem | `/sbin/df -n /` → `ufs`; `df /` → 779,364 blocks / 183,902 files free |
| kernel | `sum -r /stand/unix` → **55482 2882** — **not a kernel of ours at all**: it is the stock `core` package's 1992 `/stand/unix` (1,475,108 B), which every medium lays down unchanged. Corrected 2026-08-16 at the r4 re-master, where this row *stayed* while both framed brels moved (49227 → 50544, 51865 → 28387) — the earlier wording "the r3 kernel exactly as the media installs it" read a package member as a media pin. **R2 does not carry r4**, and still does not: R3 flew the r4 combined kernel on metal **2026-08-15** and the `VER_KERN*` mint pins moved to the r4 pair on **2026-08-16** (`KERNBENCH` 49667 / `KERNZ3660` 60364, *W6-I* above), but those are **post-handoff** identities, reached only via `pkgadd` + `updbootpart` |
| packages | `pkginfo` piped to `wc -l` → 17 |
| dialog | `system.setup` `-rw-r--r--` (disarmed), `/var/adm/firstboot/PENDING` absent |
| both directions | box → host: `/usr/sbin/ping 192.0.2.17` → `192.0.2.17 is alive` |

There is **no default route**, and that is the unattended tier working as designed:
`/etc/inet/rc.inet`'s route lines are still stock's commented examples, because
installing a gateway is something the first-boot *dialog* does. Bench and host share
the /24, so LAN reachability is complete without one.

### One finding this run surfaced (not a golden defect, but do not lose it)

`swap -l` on the installed box reports **102,400 blocks** for `/dev/dsk/c6d0s2`
(18,38), while the disk's own RDB — parsed host-side off the delivered image — gives
that slice **61,440 blocks / 30.00 MiB**:

```
slice 1  UNIX_Root  low=2      high=15329  off=65536      502,267,904 B  479.00 MiB  UNI\1
slice 2  UNIX_Swap  low=15330  high=16289  off=502333440   31,457,280 B   30.00 MiB  resv
slice 3  UNIX_Boot  low=16290  high=16353  off=533790720    2,097,152 B    2.00 MiB  UNI\0
```

The installer is consistent with the disk (`install.sh: swap: added /dev/dsk/c6d0s2 0
61440`, read out of the RDB); the discrepancy appears only once the *installed kernel*
is running, so the suspect is the target kernel's compiled-in swap parameters rather
than anything the driver did. Nothing here is at risk — the box has used 6,496 of
those blocks across three boots and the partition device bounds its own I/O — but a
kernel that believes it has 20 MiB more swap than the slice holds is a thing to close,
not to leave measured-and-shrugged-at. It is **not** specific to this cell: every
profile in the tree leaves `TARGET_SWAP_MB` empty, so every NG-installed box has
whatever this is. This appears to be the first time anyone ran `swap -l` on an
installed NG box rather than on the miniroot.

### The candidate

```
work/golden-candidate/amix-bench-golden-2026-08-14.hdf
  536,870,912 bytes
  md5     ccb8cd16ba696ad5c71d948b3db476e6
  sha256  119c3a463002dacf18f0899840f5a2b0a79f3ee9e90d547fda86310b0764ee54
```

byte-identical (`cmp`) to `work/install-matrix/r2-golden/target.hdf`. The
verification boot above ran on a **copy**, so the delivered bytes are exactly what
the harness produced and nothing outside the gate ledger ever wrote to them.

## ★ Wave C3: the 68040 line installs — the `bench-040` cell (2026-08-19)

The 040/060 campaign's **C1** produced a medium that *boots* the 68040 installer
(`work/metal-040-source/metal-040-source-20260819.hdf`, bench-booted the same day to
the keyboard prompt). C3 is the wave that turns that into a completed install: a
matrix cell, on the bench, driven by the same harness that ran the r2 batch, with a
digest attestation taken off the installed box's own contents DB.

Three things about that cell are firsts, and each one moved something in the harness.

### The source medium IS the boot medium — the `SELFBOOT` arm

Every other cell boots a floppy. This one has **no floppy at all**: the machine boots
slice 3 of the id-0 disk (boot1 + `boot2-040` + the 040 miniroot kernel) and roots the
**UFS** install miniroot on slice 1. The miniroot's own `/etc/profile` probe then finds
`/dev/dsk/c0d0s4` first — it is the first entry in the hardcoded probe order,
precisely because a raw payload slice can be settled by one bounded 512-byte read — so
no cdfs probe ever runs on this rig.

That single fact forces three harness changes, and they are consequences rather than
options:

* the workset builds **no floppies**, and both generated rigs declare none. A
  `nr_floppies=1` with an empty slot is still a drive the guest probes.
* the guest→host **evidence channel** is the miniroot's own root filesystem, exactly
  as it always was — which on this cell means the **source `.hdf`**, not the root
  `.adf`. Same blind-console rule (no gate is ever satisfied by "we typed it"), same
  per-run nonce, different medium.
* the **post-install rig drops the source disk entirely**. There the source disk is
  the installer, and leaving it attached would let *"the target booted"* be satisfied
  by the installer booting a second time. It is the same rule, and the same reason, as
  the floppy cells' empty `floppy0=`.

### The evidence channel is a SLICE, not a file — and the run that proved it

The first attempt (`bench-040-run1`) was **refused by the workset gate**: *"the fresh
evidence channel already carries an answers beacon"*. The gate was right and the design
was wrong. On a selfboot cell the channel and the source are one physical medium:

```
slice 1 UNIX_Root    +0x0010000  45,088,768 B   <- the miniroot's root fs = the CHANNEL
slice 4 InstPayload  +0x2e60000   8,388,608 B   <- the /install payload   = the SOURCE
  APKGENG         first at 0x2e81524  -> slice 4
  W2-ANSWERS-END  first at 0x308c29a  -> slice 4   (inside setup.sh's own source)
```

A byte scan of the whole image therefore finds every marker string in the payload's own
copy of the installer. Two consequences, and the second is the dangerous one: the
freshness checks refuse a perfectly fresh medium, **and** the answers-beacon extractor —
which reads between `# W2-ANSWERS-BEGIN` and `# W2-ANSWERS-END` — would happily return a
slab of `setup.sh`'s own text as if it were a beacon the interview wrote. A gate reading
the installer's source code as the operator's answers is a false PASS waiting for an
occasion.

`ev_bounds` resolves the channel's byte range from the medium's **own RDB** (slice 1,
512-aligned, fail-closed) and `ev_sync` re-snapshots it before every marker read, so a
marker is always judged against bytes read after the last poll. The payload slice is the
SOURCE; it is never the channel.

The source-readable token moves for the same reason. `APKGENG` is a perfect proof on a
floppy — the channel and the source are different media, so the only way that string can
appear on a fresh root `.adf` is the guest having copied it across. Bounding the scan to
slice 1 makes it honest here too, but only for exactly as long as the bound is exactly
right, and a token whose validity rests on a byte range is one arithmetic slip from
vacuous. The selfboot gate emits `${NONCE}srcok` instead, and **only if the copy came
back non-empty** — it proves one thing more, with a string that cannot pre-exist on any
medium.

### Markers need a padding write — amiberry's hardfile path is buffered stdio

`sync` gets a marker out of the guest's buffer cache and onto the emulated drive. What
carries it into the file the host greps is amiberry's own write path, and for a
**hardfile** that is buffered stdio: `hdf_write_2()` does `fseeko` then `fwrite`, with no
`fflush`. A write therefore reaches the host file when some *later* disk operation seeks
— so the last write of a quiescent guest can sit in the host's stdio buffer
indefinitely. Floppy cells never met this because the `.adf` path flushes differently.

The fix is one more write after the marker: its seek flushes the marker, and the only
thing left unflushed is padding nobody reads.

```
FLUSH="sync; echo evidencepad > /matrix.pad; sync; sync"      # selfboot
FLUSH="sync; sync"                                            # floppy cells, unchanged
```

### The target needed its own 68040 kernel — and the producer already had it

`metal-a4000-z3660-040` carries the donor's 030 target chain by declared intent (its
★C4 note): on metal that is a deferral, because an 030 z3660scsi chain at least exists
there. On the bench it is a **wall** — that chain cannot boot the emulated A3000 at all.

Minting a bench target kernel turned out to be free. amix-kerntools' 040 producer emits
`unix-040` **already rooted at id 6 slice 1**:

```
kernel-rootdev-stamp show   rootdev 0x00480016 (/dev/dsk/c6d0s1)
                            swap    /dev/dsk/c6d0s2
                            rootfstype EMPTY  -> vfs_mountroot probes s5 then ufs
kernel-cputype-stamp show   cputype 0x28 (40), pcr_boot sentinel intact
stamp --id 6                0 byte(s) changed          <- a no-op, and proved so
```

So the whole mint is: copy the producer artifact into this repo's `work/`, run the
sibling's stamp on **our** copy (never into kerntools), frame it, and put it in a donor.

| artifact | identity |
|----------|----------|
| `../amix-kerntools/work/040-kernel/260818-02/out/unix-040` (ET_REL) | 1,795,058 B · `sum -r` 10442 · svr4-sum 0xadd1 · md5 `bc154818ff7c05bccd280148b0687127` · sha256 `3c057357…2291` |
| `work/040-target/unix-040-target-c6s1.brel` (framed) | 1,332,440 B · `sum -r` **52867** · sha256 `4021a679…e6af` |
| `work/bootslice-donor/bench-golden-040-target-c6s1.hdf` | boot1 + `good_040` + the 52867 brel; `bootchain-verify --identity good_040` PASS |

`profiles/bench-a3000-040.profile` is then `metal-a4000-z3660-040`'s **source** side on
`bench-a3000-a4091`'s **rig**, with the target keys re-pinned to that chain and a payload
boot dir of its own (`boot/bench040/`) so two 040 media can never stage two kernels under
one name.

### Two gates stopped assuming the 030 line

* **bootchain** now verifies against the profile's `BOOTSLICE_BOOT2_IDENTITY`. The
  contract default `good` is correct for every 030 medium and wrong for a 68040 one.
  Selection stays by NAME — `proven` answers *"does this loader run on metal"*, never
  *"may it ship on THIS medium"* — so a gate asked for `good_040` still refuses `good`.
* **rootfs** asserts the 040/060 `fs_bsize` floor when `INSTALL_CPU` says so.
  `rootfs-type.py` grew `--min-bsize` for it: the kernel's own root-mount gate accepts
  1380 upward, and on the 040/060 line a `fs_bsize` in **2048..4095** is mis-routed into
  the large-block `ufs_allocmap` arm and comes back with an under-allocated block list.
  Such a filesystem mounts, passes every other gate, and corrupts under load.
  `mkfs_ufs`'s default geometry is 8192/1024 and clears it — which is exactly why the
  assertion costs nothing until somebody passes `-b`, and catches precisely that.

### The digest is MEASURED, not asserted

The cell's set is `minimal-040`, a **CPU-line variant**: the same eight packages, off a
medium that still calls the set `minimal` in its own `/install/sets`. The suffix records
which kernel line laid the tree down. Its `SET_REFS` row is `-`, so the run requires
`--attest-set`, is gated on the base-5 and base-8 **containment counts**, and its own
digest becomes the 040 line's first baseline.

The contents DB has no CPU field and no filesystem field, so `e483b0cb` is the *expected*
answer — and that is exactly why it must not be pinned in advance. A run that gates on the
answer it was built to discover confirms its own premise. `installer-selftest` audit X4
learns the variant rule: the medium advertises the **base** set, and a variant with no
attested base is an orphan.

### ★ THE RUN, AND THE WALL — `work/install-matrix/bench-040-run2`, 2026-08-19

```
GATE        STATUS     SECS  DETAIL
preflight   PASS          0  cell=bench-040 amiberry=amix-v830 nonce=MTX04169318
workset     PASS          1  fresh target (no floppies -- selfboot)+source, 2 rigs generated
mediaboot   PASS        154  source disk self-booted, miniroot shell confirmed by nonce
source      PASS         74  source mounted at /cdrom and proven readable
install     FAIL        425  interview produced no answers beacon
INSTALL-MATRIX: FAIL -- install:FAIL coldboot:NEVER-RAN digest:NEVER-RAN
                        bootchain:NEVER-RAN rootfs:NEVER-RAN teardown:NEVER-RAN
```

Four gates green, and each is a first: the **first 68040 installer boot under harness
control** (banner `68040-260818-02 Version 2.1c`, keymap menu, UFS root), the first
selfboot mediaboot, and the first source gate served off a raw payload slice the machine
booted from. Then `setup.sh` died, and it died the same way every time:

```
NOTICE: User BUS ERROR at 4AFC0003, PC:800023FC FAULT:6 PID:19 CMD:sh /cdrom/install/bin/setup.sh
   ... eleven times, byte-identical ...
/cdrom/install/bin/setup.sh: no space
```

`no space` is the 1991 Bourne shell's message for a failed arena growth. The parent
miniroot shell survived — the queued interview answers came back as `y: not found`,
`79: not found`, which is how the console shows a child that exited early.

#### What it is NOT (measured, `work/diag040/shots16`)

The obvious suspects were the medium and the filesystem, since this is the first cell
whose installer is read off an **s5 payload slice mounted by a 68040 kernel**, and the
040/060 line is UFS-root precisely because s5 is unconverted there. Both are refuted:

```
sum -r /cdrom/install/order            46208    1   == payload manifest 46208
sum -r /cdrom/install/bin/setup.sh     53455  151   == payload manifest 53455  (77,039 B)
sum -r /cdrom/install/bin/install.sh    8062  232   == payload manifest  8062  (118,500 B)
cp /cdrom/install/bin/setup.sh /tmp/s.sh
sum -r /tmp/s.sh                       53455  151   == the same, off UFS
```

s5 reads on the 040 kernel are byte-exact, **including files large enough to need
indirect blocks**; the UFS miniroot round-trips them byte-exact; and the 1991 `sum`
binary itself runs fine. Then the decisive one — the **same bytes from UFS**:

```
NOTICE: User BUS ERROR at 4AFC0003, PC:800023FC FAULT:6 PID:15 CMD:sh /tmp/s.sh
   ... twenty times ...
/tmp/s.sh: no space
```

Same faulting address, same PC, different PID, different filesystem. So the medium, both
filesystems, and the installer's own content are all exonerated: this is `/bin/sh`
executing a large script on the 68040 kernel line.

Two details make the signature worth reading closely. The faults **repeat identically and
make no progress** — the same PC and the same address, over and over — which is the
signature of a fault the kernel "handles" without changing the mapping, so the
instruction retries and faults again; a plain SIGBUS would kill the process on the first
one. And `4AFC0003` is not a plausible data address: it is odd, unmapped, and `4AFC` is
the m68k `ILLEGAL` opcode, so it reads like *instruction bytes interpreted as a pointer*
— junk where a freshly grown anon page should be.

That fits two open campaign items and it is worth naming both rather than picking one:
the study's **eight-site 2 KiB anon-map mismatch** in the 040 port (`segvn_create anon_map
size`; the queued `shmget` probe is the same class), and **E5**, the faithful 68040
format-$7 bus-error frame Amiberry does not yet produce. The second matters for where the
answer lives: if the frame is unfaithful, the wall is the emulator's and may not exist on
silicon. Nothing here can tell those apart — that is a kernel/emulator investigation, not
a media one.

#### WHERE it dies — `sh -x`, redirected, names the line (`work/diag040/shots5`)

The console cannot show this: the kernel's repeated `NOTICE` lines scroll the trace off
before it can be read (`shots4` is that failed attempt, kept because the next person will
try it too). Send the trace to a file on the miniroot's own root and `cat` it afterwards —
the last page that stays on screen IS the last thing the shell did:

```
   ... the whole base profile sourced and echoed: SRC_*, TARGET_*,
       KERNEL_BREL_SUMR=52867, BOOTSLICE_BOOT2_IDENTITY=good_040, FB_* ...
+ [ -n n ]
ANSWERS_ECHO_PATH=/matrix.ans
+ [ -n 6 ]
INSTALLABLE_IDS=6
+ [ -f /tmp/kmap ]
+ [ -n  ]
ECHO_ANSWERS=
+ [ -f /matrix.up ]
+ [ -f /matrix.go ]
/cdrom/install/bin/setup.sh: no space
```

That is `setup.sh` **lines 383-385** — the last two traced commands are the pair of
harness-marker tests in the `ECHO_ANSWERS` block — and then nothing. The profile loaded
completely and correctly (every key is right there in the trace, including this wave's own
`52867` and `good_040`); the interview never asked its first question.

**So it dies at PARSE time, not at command execution.** What immediately follows line 385
in the file is a run of function definitions — `restart()`, then `scan_disks()`, then the
rest — and a Bourne shell reads its script incrementally, parsing and *storing* each
function into its own arena as it goes. The last thing traced is the command before that
block; the failure is the shell growing its arena to hold what comes next. `no space` is
that growth failing, and the eleven-to-twenty identical bus errors are the faults it takes
while trying.

This also corrects the reading of the prefix bisection above, and the correction matters:
`p32`/`p48`/`p64` and the full 77 KB file all stopped at the **same early `die`** (the
profile check, with `/cdrom` unmounted), so none of them ever parsed past roughly line 300.
They do **not** show that the whole script parses — they show that everything up to that
point is clean, and that the fault lives beyond it. The `sh -x` trace is what located it.

The destination-disk scan — one 512-byte read of every id in `SCAN_IDS="0 1 2 3 5 6"`, most
of them **absent units**, which is the origin of two recorded hazards on this bus already
(the `ddsize` wedge, and the cdfs absent-unit second-mount panic) — is defined in
`scan_disks()` but is never reached: the shell dies parsing the definition, before any of
it runs. Worth knowing, so nobody spends a session hunting the SCSI path.

#### A third symptom, same word: `mount` itself returning ENOSPC

One boot of a **re-used** medium copy refused the payload mount outright:

```
mount: mount of /dev/dsk/c0d0s4 as /cdrom failed: No space left on device
```

ENOSPC from `mount(2)`, on a filesystem with 8,060 free blocks. **This one is almost
certainly the medium's own fault, not the kernel's**, and it is recorded because it cost
a diagnostic boot to work out: that copy had been left mounted when the previous
diagnostic's emulator was killed, so its s5 superblock was dirty. A **fresh copy of the
same master mounted cleanly on the very next boot**, which is the control that settles it.

The operational lesson is the one the fresh-media rule already states and this is a new
way to trip over it: a selfboot medium is written to by every run — the miniroot's root is
on it — so a diagnostic must copy the master again rather than re-use the previous run's
copy. `install-matrix.sh` already does exactly that; the hand-driven diagnostic did not.

#### ★★ THE BENCH 040 LINE'S OWN 16 MB LIMITATION — measured, and NOT an Amix ceiling

This is a property of the **040 *bench* line's stock `support.c`**, not of Amix's memory ceiling:
the real 060 line installs and boots at **128 MB** (metal-proven 2026-09-14/15), and the "16 MB
Fast-RAM limit" as a general Amix rule is an inherited, never-first-party-measured claim
(`../amix-kerntools/docs/ram-limits-reconciliation.md`). What is measured *here* is only that THIS
040 bench rig cannot go above 16 MB until its own `support.c` answer (D7) lands. The rig's 16 MB was
picked as "one variable at a time" (it is what the first native 040 boot was proven on). Re-running
the same diagnostic at **64 MB** turned that into a law FOR THIS LINE:

```
s5mountroot VOP_OPEN error 6
WARNING: nfs_mountroot called
PANIC: vfs_mountroot: cannot mount root: errno 89
```

`VOP_OPEN error 6` is ENXIO — the root device could not be opened at all, so
`vfs_mountroot` walked s5 → ufs → nfs and panicked. This is **campaign fact 7 arriving on
schedule**: the 040 line inherits **stock `support.c`**, our source-level `always:` probe
patch does not apply to a binary-override kernel, and stock's line 305 gates A3000-SCSI
synthesis on the kernel ending above `0x07000000`. At 16 MB the bank is
`0x07000000..0x08000000` and the kernel clears it; at 64 MB the bank grows *down* from
`0x08000000`, the kernel loads low, the A3000 controller is never synthesised and the root
disk vanishes. 32 MB would fail for the identical arithmetic.

So the 040 *bench* line has **no reachable memory configuration above 16 MB on THIS rig** until D7
(the 040 line's own `support.c` answer) lands — a limitation of this line's stock `support.c`, NOT
an Amix memory ceiling (the 060 line runs 128 MB) — and the memory-pressure explanation for the
`setup.sh` wall cannot be tested away on this rig by adding RAM. That is a real
constraint, and it is the first bench measurement of a defect the plan predicted from
reading alone.

#### What the 040/060 lane gets from this

The wall is **not in this repo's lane**. Everything media-side is proven correct by the
run itself: the medium boots, the loader is `good_040`, the UFS miniroot roots, the s5
payload mounts and reads byte-exact, and the profile this wave wrote loads completely and
correctly. What fails is the 1991 Bourne shell growing its arena on a 68040 kernel.

Handed on, with the evidence path beside each:

| claim | evidence |
|-------|----------|
| `/bin/sh` faults growing its arena while parsing, at a FIXED PC and address | `User BUS ERROR at 4AFC0003, PC:800023FC FAULT:6` — four independent runs, three different PIDs |
| not the filesystem, not the medium | identical failure with the identical bytes read from **s5** and from **UFS**; `sum -r` byte-exact off both |
| located at `setup.sh:383-385`, at parse time | `work/diag040/shots5/61-trace-tail.png` |
| the faults REPEAT without progress | same PC and address 11-20 times per run — the mapping is not being fixed, so the instruction retries; a plain SIGBUS would kill it on the first |
| `4AFC0003` is not a plausible pointer | odd, unmapped, and `4AFC` is the m68k `ILLEGAL` opcode — it reads as junk where a fresh anon page should be |
| the bench cannot answer it with more RAM | 64 MB does not boot at all (stock `support.c`, below) |

Two open campaign items fit, and they live in different repos, which is exactly why the
next step is theirs and not this one's: the study's **eight-site 2 KiB anon-map mismatch**
in the 040 port (`segvn_create anon_map size`; the queued unprivileged-`shmget` probe is
the same class and would now be a cheap confirmation), and **E5**, the faithful 68040
format-$7 bus-error frame Amiberry does not yet produce. If the frame is the cause, the
wall is the emulator's and may not exist on silicon — which is a question the A3640 can
answer and this bench cannot.

## IN-rtc / IN-rtc-2: the battery clock and the zone files (2026-09-29)

**The convention.** The Amiga battery clock (RP5C01 on the A3000/A4000) keeps **local time**,
as AmigaOS expects. `/etc/sysinit` runs `/usr/amiga/bin/setclk` at every boot; it reads
`/dev/clock` (the RTC's wall time as seconds, as if it were GMT) and interprets it in the zone
named in **`/etc/clkzone`** (`:<zone>`, the tzfile form; a POSIX rule string works too).
`RTC=setclk` (the default) lays our setclk over the stock one and writes `/etc/clkzone` from
`FB_CLKZONE` (default `:<FB_TZ>`); the interactive dialog rewrites it with the zone the operator
picks, then **reads the clock again** in that zone, so the first boot is already right (the
sysinit read ran before the dialog, in the image's default zone).

**Our setclk** (`src/setclk/setclk-y2k.patch` over Commodore's source, built by
`tools/build-setclk.sh`, pinned `SETCLK_SHA`):

- the community Y2K fixes (`%03d` year scan, 12-byte buffers, a 4-digit year);
- a plausibility gate: an RTC outside **1992..2037** leaves the system clock alone, with a
  console line (a clock set back past the password ages makes every login "expired",
  grimoire quirk 20; past 2037 a 32-bit `time_t` overflows);
- **to the second** (IN-rtc-2): stock handed the time to `date MMDDhhmmYYYY`, and SVR4.0
  `date` has no seconds, so the box booted up to 59 s slow. Ours breaks the RTC value down
  with `gmtime`, reads it in the clkzone zone with `mktime`, and sets it with `stime` — no
  `date`, no shell. **This libc's `mktime` takes `tm_isdst = -1` as standard time** (measured
  on the box: `timezone`/`altzone`/`daylight` are right, `tm_isdst = 1` is honoured), which
  put a summer-time clock one hour ahead; setclk reads the value as standard time first and,
  if `localtime` says that instant is in summer time, again with `tm_isdst = 1`. Console: `setclk: RTC MM/DD hh:mm:ss YYYY (:ZONE) -> system clock set`;
- it never writes the RTC.

**The year encoding (measured on metal, T-16 F4).** The RTC's year register holds the
AmigaOS battclock encoding — years since 1900, so the tens digit runs past 9 (nibble
0xA–0xC; 2026 = tens 12, units 6). It is the kernel's `/dev/clock` driver that encodes and
decodes it (setclk only reads and writes a `time_t`, which the source shows). The K1 metal
acceptance (T-K1CM step 4) found both this and the plain-BCD form read back correctly, so a
clock set from AmigaOS and one set from Amix agree.

**The zone files (`TZFILES=tzdata`, the default).** Amix's `/usr/lib/locale/TZ` holds 1991
tzfiles with 1991 rules: EET/MET/WET/CET end summer time on the last Sunday of **September**
(EU since 1996: October), the US zones use the pre-2007 rule, and so on — so in 2026 a Finnish
box read EET (UTC+2) from 27 September while the country was on EEST. `tools/build-tzfile.py`
regenerates **every** compiled zone the image ships (92; the zic source files beside them and
the `localtime` link stay stock) from the vendored tzdata (`src/tz/tzdata.zi`, 2026c, public
domain) with the host `zic`, and rewrites each in the **1991 layout** the Amix libc reads:
44-byte header (24 reserved bytes, then ttisstd/leap/time/type/char counts), 32-bit
transitions, no magic, no leap seconds, no footer. Its constraints and choices:

- only transitions in 1970..2038 are kept; the reader's limits (`TZ_MAX_TIMES` 370,
  `TZ_MAX_TYPES` 10, `TZ_MAX_CHARS` 50, from the sysroot `tzfile.h`) are enforced;
- before the first transition the 1991 `localtime` uses the first non-DST type, so the
  types are ordered to make that the zone's 1970 type (a zone in DST at 1970 gets a
  transition at 0). Every file is checked against tzdata's own answer at every transition,
  ±1 s and ±1 h, with the 1991 lookup algorithm;
- the **1991 meanings** are kept: EET/WET/MET/CET stay the rule zones they were (today's
  tzdata links them to Athens/Lisbon/Brussels), and `GMT+N` stays N hours **east** of GMT
  (today's `Etc/GMT+N` has the opposite sign). Dropped names map to their successors
  (`US/Pacific-New` → Los Angeles, `US/Yukon` → Anchorage, `Canada/East-Saskatche` →
  Regina, `Australia/Broken-Hill`/`Sturt` → Broken Hill);
- the stock set hard-links names whose meanings have since parted (`EST` = `US/East-Indiana`,
  `CET` = `MET`), so `install.sh` removes each name before copying it and every name becomes
  its own file; each copy is verified by `sum -r`. The set is pinned by the sha256 of its
  MANIFEST (`TZSET_SHA` in `tools/build-install-iso.sh`); `TZFILES=stock` keeps the 1991 files.

Against the stock set (`build-tzfile.py --compare <stock dir>`): 34 zones are byte-identical
(every fixed-offset one: GMT, the 25 `GMT±N`, Japan, EST, MST, HST, US/Arizona, US/Hawaii,
Canada/East-Saskatche), 5 change only their abbreviation (UTC/UCT/Universal `GMT`→`UTC`,
Iceland `WET`→`GMT`, Australia/North `CST`→`ACST`), 8 differ only before 2026, and 45 give a
different answer from 2026 on (every European, US, Canadian, Australian DST zone and more).
A zone database package for later tzdata releases belongs to amix-packages.


## 1.1: the Gayle-IDE two-device follow-up (PARKED, owner 2026-09-29)

The IDE lane is 1.1 in full; the CF kit is not in the initial release download set. When un-parked:
first the **slave-enabled CF kit** (K030-IDE-S, chain 98b12f76, kerntools 4da32c4: the slave appears as
unit 5 → `c5d0`, root stays `c6d0s1`; one profile change + a cd-ide run); the **on-machine install from an
IDE drive** (source on the slave, target on the master) only together with P-11 — it needs an answer to
which device boots the installer, since K030-IDE-S roots on the master (a slave-rooted install kernel from
kerntools, or the roles flipped). Amiberry models the slave (`hardfile2=…,ide1`; gayle.cpp: two drives
per channel), so both are bench-testable.

**Owner note:** a CF card as IDE slave is often unstable on Amigas, so the **master-only CF kit is the
product** and the slave-enabled kit is low value. K030-IDE-S stays a bench knob, not a shipped kit.

## E-BIG: the on-box root ceiling (P-15 I1, 2026-10-02)

D12's "at least 900 MB should work" is revised to **600 MB proven; larger roots after the kernel
fix**. kerntools KT-32 bracketed on-box `mkfs` on both kernel lines: 600 MB passes, 640 MB and up
fail with `wtfs: No such device or address`. The cause is stock: sdpart.c `sddevsize()` returns
1234567 for a partition whose length it does not know, and dd.c clamps raw I/O to it, so nothing
can be written past block 1234567 through the raw device. Host-minted images are unaffected.

Until a kernel carries the fix, `install.sh` (`plan_partitions`) and `setup.sh`
(`plan_root_default`) cap the root at **602 MB** = 1234567 / 2048 whole MB: the default is clamped
with a console note, the interview's bound becomes 602, and a profile's `TARGET_ROOT_MB` above it
is refused with "this kernel limits an on-box root to 602 MB". The space above the cap is left
unallocated. The cap is lifted per medium by `KERNEL_SDDEVSIZE=fixed` in a profile whose pinned
kernel family carries the fix (`profiles/README.md`); installer-selftest audit V executes both
planners on a 1000 MB disk and requires 602 (stock) and the uncapped plan (fixed).


## SEC-1: world-writable first-boot state (fixed 2026-10-03, 2b63f15 + e593fba)

**Release-notes text.** Amix installs made from media built before 2026-10-03 leave
`/var/adm/firstboot` world-writable (0777, its files 0666). The first-boot script runs as root
at boot whenever `/var/adm/firstboot/PENDING` exists, so any local user could arrange for code
to run as root at the next boot. The same media leave `/opt/amix` and `/opt/amix/bin`
world-writable (the RTG desktop kit, a directory on root's PATH) and `/etc/inet/hosts` 0666
after the first boot. Media built from 2b63f15 / e593fba on lay all of these root-only and
remove the seeded `root.shadow` once first boot completes. On a system installed from earlier
media, run as root once:

    chmod 700 /var/adm/firstboot
    chmod 600 /var/adm/firstboot/firstboot.conf /var/adm/firstboot/DIALOG-DONE
    rm -f /var/adm/firstboot/root.shadow /var/adm/firstboot/PENDING
    chmod 755 /opt/amix /opt/amix/bin; chmod 444 /etc/inet/hosts

The first line closes the hole. The `chmod 755` line applies to systems that have the RTG
desktop kit (`/opt/amix`).

**What changed in the installer.** The miniroot and the boot-time scripts run with umask 0, so
every directory or file the installer or first boot creates is world-writable unless it is given
a mode. These now get explicit modes:
- install.sh: `/var/adm/firstboot` 0700, `root.shadow`, `firstboot.conf` and `PENDING` 0600,
  `/opt/amix{,/bin}` and `/usr/include/sys` 0755, and `install.log` 0644. The RAW arm's apkg
  cache is removed from the target's `/tmp`.
- firstboot.sh re-tightens its state on every run and deletes `root.shadow` at completion. It
  puts `/etc/inet/hosts` back to 0444 (core's mode) after each rewrite, sets `/etc/tz.index` to
  0644, and stages the `/etc/shadow` rewrites under umask 077.
- S99zen puts `hosts` back to 0444 after its own-row rewrite.
- installer-selftest audit AU checks these modes, and checks that every target path install.sh
  creates is either chmod'ed or on a reviewed list of package-owned or scratch paths.

`root.shadow` only ever held the shared, documented placeholder hash. The password chosen in
the first-boot dialog goes straight into `/etc/shadow` through `passwd`, and first boot leaves
it alone.

Stock runtime files (`/etc/syslog.pid`, `/etc/dfs/sharetab`, `/var/saf/_log`,
`/var/spool/smtpq/LOG`) are created 0666 by stock daemons under init's umask. That is 1991
behaviour, outside the installer, and is not changed here.

## CD-1: the `cd1-emu` cell and the 060 line's `minimal-060` reference (2026-10-05)

`cd1-emu` is the A4000D CD install (profile `metal-a4000-z3660-060-a4092cd`) on the emulator. Its twin profile
`bench-a4000-z3660-060-a4092cd` uses fd060-cd's bench identity (installer-selftest AX8), and its rig
`configs/accept-z3660-060-a4091cd.uae` is kerntools E40 plus the install disks:

- the CD-1 boot .hdf (`tools/build-boot-hdf.sh`; the K1 UFS miniroot + KD060-ZA-CD c0-u6) sits at Z3660 unit 6. It
  is the SELFBOOT evidence channel.
- Kickstart boots a WD vehicle copy of that disk (`INSTALL_VEHICLE`), because the emulated Z3660 ROM boots nothing.
- The CD is on the A4091 at cdfs 1,3.
- The target is the blank Z3660 unit 0. The N17b cold boots move it to unit 6.

**First green:** run `20261005-cd1-emu-run3`, 10/10 gates. Two harness facts came out of it.

- **`SWAP_KIND=disk`.** A k0 disk-root miniroot kernel swaps on its own disk's slice 2 from boot. install.sh's real
  swap step then rightly logs "/dev/fakeswap is not in the swap table", and the cold-boot gate now accepts exactly
  that line for such a cell. Floppy kernels keep the default `fake`.
- **`minimal-060` = `21c4e2623c34e1fae38674e8829682ae` (4859 objects).**
  - Since Q-4.15 (75cb681, 0cf2bca) a 040/060 install lays the framed kernel as `/stand/unix` and re-registers it at
    first boot, so its contents row carries the r5 kernel's size, not the 1992 one. `minimal` (`a650dd79`, measured
    on fd060-cd on 2026-10-03, before that change) can no longer match.
  - The new reference was recorded with `--attest-set`, with base-5 and base-8 containment exact. It was measured
    on the K1 r5 package bytes (the v7.1 staging: APKG 0.2 and the r3 APKGENG 1.12.0).
  - The July APKGENG 1.12.0 (the I1 staging) traps in `installf -f` on the 060 (vector 0xF4, run 2). That leaves
    `/stand/unix ? ? ? +core`, and the row drops out of the digest. amix-packagemanager has a fixed 1.12.1, not yet
    adopted.

**APKGENG 1.12.1 trial (`cd1-emu-eng1121`, run `20261005-cd1-emu-eng1121-run1`, 10/10).**
- **Media:** the same rig, profile and boot disk as `cd1-emu`. The disc is mastered from a pinned staging with
  amix-packagemanager's 060-clean APKGENG 1.12.1 (md5 19905d2a) and the static CD engine rebuilt at 32798b6 (`STAGING`
  and `STATIC` copies, kept locally).
- **Result:** first boot re-registers `/stand/unix` with no vector-0xF4 trap, and scan060 finds 0 hits on the
  installed `/usr/apkg/bin`.
- **`minimal-060-eng1121`** measured `94effdf4ddebc34d6643b44dda8c3928` (4859 objects). It is recorded here, not as a gated SET_REFS row: installer-selftest audit X admits digests only for advertised sets and their CPU-line variants, so a re-run takes `--attest-set`.
- **Not on release media:** the release media keep the r5 bytes (`minimal-060`) until the owner decides.
- **Hazard:** `heirloom/build-amix-static` was rebuilt in place. Any ISO mastered without `STATIC=` now carries the
  new engine.

**APKGENG 1.12.2 trial (`cd1-emu-eng1122`, run `20261005-cd1-emu-eng1122-run1`, 10/10).** 1.12.2 supersedes 1.12.1 and
is the engine r6 carries. It is the same engine, re-minted through gcc-cross-amix 2ab2b22, which rewrites the 64-bit
multiplies (amix-packagemanager 119c2db).
- **Media:** the same rig, profile and boot disk. The disc is mastered from a local staging tree:
  - `staging`: the v7.1 staging with APKGENG 1.12.2 (md5 f5858094);
  - `static`: a pinned copy of `heirloom/build-amix-static-1.12.2` (pkgadd ccf305dd, pkginstall 4ab504fa).
- **Result:** scan060 finds 0 hits on the installed `/usr/apkg/bin` (13 ELFs), and no `u_trap` appears in the logs.
- **`minimal-060-eng1122`** measured `65ee19ffff1a1c3804fbabf7b5dcedd3` (4859 objects): a trial digest, not gated
  (`--attest-set`), with base-5 and base-8 containment exact.
- Never master an r6 medium without an explicit `STATIC=`: the default `heirloom/build-amix-static` still holds the
  1.12.1-era set.

## CD-2: a card-1 target -- install onto, and root on, a disk behind the A4091/A4092 (2026-10-05)

The A4000D CD install with the TARGET on the Zulu disk at id 1 behind the A4092 (card 1 unit 1 = `c9d0`, rootdev
`0x00480019`), not on the Z3660 SD. Profiles: `metal-a4000-z3660-060-a4092cd2` (AX9) and the emulator twin
`bench-a4000-z3660-060-a4092cd2` (AX10), each its CD-1 twin with only the target keys changed. The installed kernel
is KD060-ZA c1-u1 (sum -r 27291, 2 MiB slice); the donor is `tools/build-k1-donor.sh` ->
`work/bootslice-donor/cd2-KD060-ZA-c1-u1.hdf`. Its chain equals kerntools' KT-50 `c1set` bootslice byte for byte.

**Installer change** (installer-selftest audit CD2 runs every case under dash):
- **`TARGET_SCAN_IDS`** (profile key): when set, the interview's disk scan opens exactly those ids. For CD-2 it is
  `9`, so the owner's other disks on that bus (the AmigaOS disk, an MD-1 root) are never opened.
- **`scan_safe_ids`** (always): every scan drops, without opening it:
  - the cdfs source's own unit (`CD_SPEC` <card>,<unit> -> c<card*8+unit>). Only cdfs may talk to a CD behind an
    A4091/A4092; a 512-byte dd-layer read of it wedges that bus;
  - the host ids 7 and f.
- **`install.sh`** refuses those ids as a target. It makes the target's `/dev/[r]dsk` nodes when the miniroot lacks
  them: the K1 miniroot carries card-1 nodes only for c8 and ce. The majors are 18/40 (miniroot.proto, pinned by the
  audit) and minor = slice*16 + X (c9d0s1 = 18,25, as the stock /dev). `setup.sh` and `install.sh` carry
  byte-identical copies of the helpers.

**`cd2-emu`** (run `20261005-cd2-emu-run1`, 10/10):
- the cd1-emu rig with the target on the A4091 at unit 1 (`configs/accept-z3660-060-a4091cd2.uae`), and cold boots
  behind a WD vehicle copy of the target with the root on the A4091 (`configs/boot-z3660-060-a4091root.uae`);
- `minimal-060-a4091root` = `b33b6287225f858cc78cbf2d297c2199` (4859 objects), recorded with `--attest-set`;
- the installed contents DB equals cd1-emu run 3's except the `/stand/unix` row (the c1-u1 kernel);
- an offline pkgchk of every installed file's SVR4 sum against the contents DB gives the same 69 deliberate edits
  as cd1-emu, so every file written through the A4091 is byte-correct.

Metal: the maintainer's notes (route R1: a pri-5 boot-only disk on the Z3660 SD carries the
c1-u1 chain; the A4092 ROM boot R2 is not run).

## 1.1: the generation-store disk (stage 2, amix-dlm S2-30, 2026-10-25)

`INSTALL_LAYOUT=1.1` (default `1.0`, so every 1.0 profile and medium is unchanged) lays the disk of amix-dlm spec
40 §2.1:
- s1 root, s2 swap, s3 the 64 MiB boot store, and an optional s4 data slice;
- the kernel comes in as an apkg 0.3 kernel-space package;
- `kbootset` writes and checks the pristine generation.

The 1.1 half of the driver is `src/installer/l11.sh`, staged on the medium at `/install/l11` with a static
apkg 0.3 and the kernel-space FILE source. The disk is described in `docs/l11-disk.md`. (The upgrade install of a
1.0 disk described there until 2026-10-31 is removed, P-36: 1.1 requires a fresh install.)

What a 1.1 medium carries is one tracked file, `tools/l11-set.conf` (S3-31):
- the amix-dlm and amix-packagemanager revisions;
- the package staging and the APKG datastream that replaces its own;
- one `pkg NAME VERSION` line per package: kbootset, modtools, loader-amix, the kernels and the module packages.

`tools/build-l11-inputs.sh --set tools/l11-set.conf` takes each package from amix-packages' `build/kspace`. The
catalog is gen-catalog's (amix-packagemanager at the set's revision), never hand-written rows. `INPUTS` records
every revision and hash, and whether gen-catalog's rows equal amix-packages' own. `tools/build-install-iso.sh`
refuses a 1.1 profile whose `KERNEL_KPKG` is not a kernel row of the medium's catalog. For a module kernel
(`kabi=` not `static`) it also refuses one without modtools, or with a `KERNEL_MODPKGS` entry that is not a
`role=module` row of the kernel's line.

A 1.1 medium's stock set is `minimal` plus **m4** (2026-10-26). The 2.1c syslogd reads `/etc/syslog.conf` only
through `/usr/ccs/bin/m4` (23,004 B). Without it the conf parses empty and syslogd files nothing, kernel lines
included. The m4 package (amix-packagemanager b70500c, 26,112 B) is that one file of Cdev's, with the same pkgmap
row, so either package or both may be installed. `tools/l11-set.conf` adds it to the staging (`stock-pkg`),
`build-install-iso.sh` adds it to the set of a medium with a 1.1 profile, and `install.sh` refuses a 1.1 install
order with neither m4 nor Cdev. Until m4 existed, the 1.1 base carried the whole of Cdev (10,370,048 B on the
disc).

Matrix cells:
- `l11-k30`, `l11-k46`: the two lines;
- `l11-k30-upg`, `l11-k46-upg`: the upgrade of a seeded r7 disk (RETIRED 2026-10-31, P-36).
- `l11-k46-reinstall-ia`: a fresh install over a seeded r7 disk, nothing of it kept (P-36, `docs/l11-disk.md`).

Each cell installs, halts, and is judged by the gate `bootstore` (`tools/l11-target-check.py`):
- the store and its pristine generation;
- every package installed with its record;
- each module in generation 1's manifest and at `/stand/gen/1/mod/<name>`;
- the dlm inittab line;
- `S99zen` for the z3660eth module;
- no `/stand/unix`, and `S01kbnamelist`;
- `/usr/ccs/bin/m4` from m4 or Cdev (size and sum of its contents row), and the conf filing `kern.info` in
  `/var/log/bus-errors` and `kern` on `/dev/console`.

It also runs `kbootset status` and `kbootset namelist` with a version-3 kinfo made for generation 1. The status
must say the namelist is missing, and the namelist call (what the first boot runs) must write it. The boot through
the new loader is a Bench row: N19's shape for k30, N23's for k46.

### Four cards (amix-dlm contract C4-1)

A stage-4 kernel drives four sd cards. A disk is `c<N>d0s<slice>` with N = card × 8 + unit in lowercase hex: `c0`–`cf`
for cards 0–1 as before, `c10`–`c1f` for cards 2–3. In the minor, the card's high bit is bit 7 (C4-1 §2.1), so
minor = slice × 16 + N mod 16, plus 128 for cards 2–3.
- The installer and the interview take a controller number of one or two hex digits (`hexval`, `hexname`). The host
  adapter is unit 7 of every card (7, f, 17, 1f). The root record's `unit=` is N mod 8, and `tools/mkroot.sh` names
  disks with `%x`.
- The first boot runs atdevs only for a card-0 root.
- A kernel package's sidecar says `sdcards=4` on a four-card kernel (absent = 2). `l11.sh` reads it (FB_SDCARDS
  still drives the first boot's root-name rewrite). Core's 256 `c<N>d1s<S>` nodes have minors 128 and up, which name
  card-2/3 disks on such a kernel. The first boot's step 4d runs `/sbin/kbootset nodes` (kbootset -22, C2-4 v12 §14;
  S5-44 R2): kbootset reads the sidecar itself, makes the 256 `c10`–`c1f` nodes, removes the d1 nodes and registers
  both to core with APKG's removef/installf, so `pkgchk core` stays quiet on /dev. On a two-card kernel it says
  core's nodes stand. Its line goes to the first boot's log; a failure is a WARNING there.
- The first boot names the root as the running kernel does: `/etc/devnm /` maps the mounted root's device number to
  its node by stat, opening nothing. vfstab, the swap name and the atdevs gate follow it. So when the install kernel
  and the target kernel number the controllers differently, the installed names are the target kernel's.
- A four-card kernel orders the controllers by rank class (z3660 < zorro < mobo < ide), then base, where 1.0 ordered
  them by base. On the A3000 with an A4091 the A4091 becomes card 0 and the WD card 1, so the root c6d0s1 becomes
  ced0s1. A 1.1 profile keeps its two-card values and names its rig's controllers: `SD_BOARDS` (in base order),
  `TARGET_HBA`, `CD_HBA`. On a CD-boot disc the install kernel is the line's kernel package. When its sidecar says
  `sdcards=4`, `build-install-iso.sh` appends the names that move (TARGET_SCSI_ID, CD_SPEC, ROOTDEV) to each staged
  1.1 profile of that line; `tools/sdnames.py` derives them. A floppy-booted 1.1 disc installs under fd0unix
  (two-card), so nothing moves there. The 1.0-layout media stay on the r7 kernels.
- The disk nodes are checked after the first boot (S5-44 R1). The install-matrix cells of the current media (RAM-disk
  CD, floppy pair, netinstall, raw image) carry the gate `firstboot`. It boots a copy of the target once on a rig
  slot (`tools/firstboot-rig.sh`: kerntools' rig-run in the first-boot rows' shape, each dialog answer typed at a
  detected prompt, `tools/lib/conprompt.py`). On the box it reads `c1fd0s7` = c 40,255, `c10d0s0` = b 18,128, no
  d1 node, 256 c1x nodes, and `pkgchk core` naming no /dev path (a configured box's editable files always differ
  from core's rows). Host-side, `tools/l11-nodes-check.py` reads the slot copy the shutdown left: all 512 nodes at
  their C4-1 minors, the card-2/3 nodes 0600 root root and registered to core, no d1 row in the contents file.
  A two-card kernel's root must keep core's set.
- A root installed before step 4d existed keeps core's d1 nodes even after apkg brings a four-card kernel. The
  A4000D root of bench J4 (M-G3, 2026-10-27) was one: the S4-55 disk (`l11-k46.hdf` 9b2edb36, installed 2026-10-26
  19:22 with kern46m -61, kabi k46.1.0 and no `sdcards=`; its firstboot.sh had no 4d and its firstboot.conf no
  `FB_SDCARDS`). Copies of it later got kern46m -82 (`sdcards=4`) through apkg. The current media all lay
  `FB_SDCARDS=4` and step 4d. Such old roots get the set from `kbootset` -22's commit (C2-4 §14), not from the
  installer.
- Since the kernel-space catalog b1f564f4 (2026-10-28: kern30m -20, kern46m -51, kbootset -23, modtools -7) the
  kernels have no built-in ufs, and k30 none of s5 either (k46 has no s5 at all, S5-37). The kernel package carries
  them as core-tier modules in `/etc/conf/mod.d` (C2-3 v8), and kbootset composes every generation from them: the
  `rootfs` filesystem is promoted to a root record (`module ufs root … tier=core build=<cut> safe=1`), any other one
  stays boot class. An installed disk roots on the ufs module on both lines (on k30 s5 is boot class beside it). A
  RAM-disk medium's generation roots on its image's filesystem: k46 promotes ufs; k30 promotes s5, so ufs is a
  boot-class record there that the miniroot's `modadmin -B` loads from the image's `/stand/gen/1/mod/ufs`, and
  without it the k30 miniroot cannot mount the ufs target. The images therefore carry every boot-class record of
  their generation: `build-ramdisk-cd.sh --boot-mods DIR` (and `build-netinstall.sh --boot-mods DIR`) hand out the
  objects kbootset records (cdfs, and ufs on k30; z3660eth, and ufs on k30), and each composer gates its images
  with `tools/ramdisk-image-check.py` (every boot record's object byte for byte, a ufs image's block size at least
  4096: the k46 ufs module refuses smaller blocks at mount, S5-13). A k46 CDBOOT cell's evidence floppy is ufs, made
  by the guest (`mkfs_ufs` on the zeroed floppy), since k46 can no longer mount s5. The `firstboot` gate also reads
  `modadmin -s` (ufs loaded as a module) and `kbootset check` (0) on the booted box.

### Booting the 1.1 install CD (S3-31 part 3, amix-dlm D-3 §10)

A 1.1 install CD can also boot by itself through an A4091 or A4092 boot ROM that has a
CD filesystem. The disc is a plain ISO9660 data CD with System ID `AMIGA BOOT` and Rock
Ridge:
- `S/Startup-Sequence` runs `BOOT/amix-cdboot`, which is boot2 built as an AmigaDOS
  program;
- `BOOT/K30` or `BOOT/K46` holds the generation (`CONTROL`, `G1.GMF`, `G1K.BIN`).
  `tools/build-install-iso.sh --cd-boot TREE` puts it there; amix-dlm's
  `kbootset media --cd` and `mkstore -C … -x amix-cdboot` build the tree.

The CD carries the loader and the kernel. The modules load from the root disk's
`/stand/gen/<id>/mod`, checked against the CD's manifest. `/install/l11/INPUTS` records
`amix-cdboot`'s hash, or why there is no CD boot tree.

**The installed disk boots first.** The installer gives the disk's `UNIX_Boot` boot
priority 2, and the ROM gives the disc priority 2 as well. On that tie the disk's node
wins, so a box with a disc in the drive still boots its disk: a disc left in the drive
must not take a box over. To boot the CD, pick it in the Kickstart early-startup boot
menu. An administrator may lower the disk's priority instead, as a choice of their own.

## The DosEnvec Mask by the controller's DMA reach (2026-10-28)

The loaders take their DMA buffers by the boot partition's DosEnvec, as FFS does
(amix-dlm a6a1511/053c417, spec 10 §3.1/§3.2): boot1 allocates `de_BufMemType` memory and
takes chip memory when the buffer lies beyond `de_Mask`; boot2 reads straight into any
buffer the Mask allows. Until now every disk here said Mask `0xFFFFFFFC`. Each partition's
Mask now says what its controller's DMA really reaches, from one table,
`tools/lib/dmamask.py` (orchestrator decision 2026-10-28, matching the kernel's DMA reach,
amix-dlm `DMA_REACH 0x08000000` and C4-5; C4-2 / OQ-80.5):

| Controller (SD_BOARDS name) | Mask | Why |
|---|---|---|
| `a4091`, `a4092` | `0x07FFFFFE` | Zorro III DMA: chip + motherboard fast, never the Z3660 DDR at `$08000000+` |
| `a3000` (SDMAC) | `0x07FFFFFE` | motherboard DMA, held to the kernel's DMA reach |
| `a2091`, `a2090` | `0x00FFFFFE` | 24-bit Zorro II DMA |
| `a4000t` (alias `a4kt710`) | `0xFFFFFFFC` | the onboard 53C710 reaches the Z3660 DDR and hangs the A4000T in chip memory |
| `gayle`, `z3660scsi` | `0xFFFFFFFC` | PIO / emulated |
| unknown or unnamed | `0x07FFFFFE` | conservative, with a warning |

`de_BufMemType` stays 0 (MEMF_PUBLIC). Where the Mask is written:
- **Host builders**: `mkroot.sh --hba`, `build-bootonly-hdf.sh --hba`, `build-source-hdf.sh --hba`,
  `build-netinstall.sh --raw-hba` (the raw image goes to whatever disk the user has, so it
  defaults to the unknown Mask), and the profile-driven `build-boot-hdf.sh` /
  `build-raw-source.sh` (`--hba`, else the profile's source controller: `SRC_HBA`, else
  `TARGET_HBA` on the target's card, else its `SD_BOARDS` entry). `install-matrix.sh` mints
  its targets with the profile's `TARGET_HBA`. Each builder reads its image back with
  `tools/dmamask.py check` before publishing it.
- **On the box**: stock `/etc/rdb` writes `0xFFFFFFFC` and has no flag for it, so author mode
  stamps every PART block after the RDSK read-back (`dm_target_mask`, install.sh): the row
  for `TARGET_HBA` in the medium's `/install/dmamask` (staged by `build-install-iso.sh`),
  the PART checksum moved by the difference, both longwords read back. A medium without the
  table leaves `/etc/rdb`'s Mask, with a warning.
- **Read-back**: `tools/dmamask.py check IMAGE --hba NAME` (or `--profile P --role
  target|src`) prints every PART's BufMemType, MaxTransfer and Mask and fails on any
  mismatch or open checksum. run-checks carries its self-test; installer-selftest `DMASK`
  executes `dm_target_mask` under dash on synthetic RDBs and on the stock-authored metal
  golden's.

An interactive install that picks a disk on another controller than the profile's
`TARGET_HBA` gets `TARGET_HBA`'s Mask, as the 1.1 layout's `KBOOTSET_BOOTDEV` does.

### TARGET_HBA names where the disk runs; the A4000T onboard 53C710 (2026-10-28)

Since the Mask, `TARGET_HBA` belongs to the destination, not to the rig an image is authored
on: the Gayle IDE CF kit (`public-a4000-ide*`, authored on the A3000 WD) says `gayle`, the
hand-over image (`handover-a4000-z3660`, authored on the A3000, rooted on the A4000+Z3660's
piscsi as `TARGET_VFSTAB_SCSI_ID=e`) says `z3660scsi`. The A4000T onboard 53C710 has its
key: `TARGET_HBA=a4000t` (alias `a4kt710`) gives the Mask `0xFFFFFFFC` and, in the 1.1
layout, `KBOOTSET_BOOTDEV=mobo:a4000t-710`, a4kt710's match key (C4-2 §8). Kickstart boots
such a disk through the A4000T ROM's `NCR scsi.device`; the root record is the motherboard
form (C4-1 §5.2, motherboard id 3), which kbootset writes from the `mobo` record l11.sh
derives. The 1.1 media carry `a4kt710-k30`/`-k46` (and `paula-k30`/`-k46`) for a profile's
`KERNEL_MODPKGS` or `apkg install`; no profile of record installs them yet.

The first boot of each media cell shows the Mask at work: boot2's boot-device line names its
buffer (`amix-boot 3: 68060, boot device z3660_scsi.device, partition at …, buffer 807c2d0`
on a Z3660 target, Mask `0xFFFFFFFC`: Z3660 DDR; `… scsi.device, …, buffer 4037598` on the
A3000 WD, Mask `0x07FFFFFE`: below `0x08000000`).

The netinstall image's installer is a copy of the stage's (`build-ramdisk-miniroot.sh
--install`), and until 3d8f34f that copy left `/install/dmamask` behind: install.sh then warned
and the target kept `/etc/rdb`'s `0xFFFFFFFC` whatever its controller. It showed only off the
Z3660 (the netinstall `l11-ni-k30` target on the A3000 WD read back `0xFFFFFFFC`, ni10; on a
Z3660 the two Masks are equal). The copy takes it now, and `ramdisk-image-check.py --zen0` (the
netinstall images' gate in `build-netinstall.sh`) demands the medium table byte for byte.
