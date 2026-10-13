# Kernel packages — the W6-P mint (PRIVATE-only)

The `amix-packagemanager` side of **"kernel + drivers as packages."** This is the
consumer of the build-hub contract `amix-kerntools/docs/kernel-packages.md` (W6-K):
it mints the two **installable-system kernel packages** an Amix install pkgadd's onto a
target's system disk. Those packages are **PRIVATE-only** — they ship proprietary-derived
bytes and may **never** reach the redistributable repo. This doc records the mint, the
private-flag mechanics, and the discrepancies with the W6-K draft that this mint corrects.

## 1. The two packages

| PKG | Driver mix | rootdev / config | `/stand/unix` `sum -r` | `/stand/unix` size |
|-----|-----------|------------------|------------------------|--------------------|
| `KERNBENCH` | `a4091` + `z3660eth` + `cdfs` + `a3091`/`a2091` fix + `scsi.c` GSIO; **PROBED** `support.c` | `0x00480016` / `c6s1unix` | **49667** | 1 586 312 B |
| `KERNZ3660` | `z3660scsi` (piscsi) + `z3660eth` (net) + `cdfs` (A4000+Z3660 metal) | `0x00480016` / `c6s1unix` | **60364** | 1 587 524 B |

> The table shows the **current** (P5.4 **r4**, 2026-08-16) identities — see §8. Every
> earlier identity is **superseded, not destroyed**: the r3 pair (`64049`/`45833`, §7),
> the r2 pair, and the original W6-P pair (`45473`/`00961`, 2026-07-23) all keep their
> `.pkg` files in the private staging, and §§5–7 record their mints as history. Only the
> r1 pair is quarantined (`build/kernel-private/POISONED/`).

Both PKG names are exactly **9 chars** (the SVR4.0 ceiling; stock Amix pkgadd silently
drops longer). Both share `rootdev 0x00480016` (`c6d0s1`, SCSI id 6 slice 1) and differ
only in driver mix — that is the whole point of a *family* of kernel packages.

### Payload — exactly three objects, class `none`

```
d none /stand           0755 root root
f none /stand/unix       0644 root root      # the finished kernel
f none /stand/boot2.boot 0644 root root      # the flags-based second-stage loader
```

Modes/owners are read straight from the **stock `core` package's `/stand` entries**
(`core.cont` on the 2.1 tape: `/stand` = `0755 root root`, `/stand/unix` and
`/stand/boot2.boot` = `0644 root root`). Every payload file is class `none` (plain pkgadd
file copy). There is **no** class-action script, **no** postinstall, and **nothing** that
writes a raw device — see §4.

`pkginfo` carries the machine-checkable lock so a consumer/gate can read it without
unpacking: `ROOTDEV=0x00480016`, `CONFIG=c6s1unix`, `KSUM_R=<sum -r of the shipped
/stand/unix>`, `BOOT2_SHA=f287ff3a…`, `KMIX=<driver mix>`, and a `APKG_DESC` naming the mix
and the PRIVATE/updbootpart posture. `VERSION` is the house `<REV>-<date>` form where
`REV = KSUM_R` (so the package identity carries the binary's checksum): currently
`KERNBENCH=49667-2026.08.16`, `KERNZ3660=60364-2026.08.16` (**r4**; `60364` is
metal-proven 2026-08-15 and is the last metal-validated identity) — §8.

Earlier identities, in lineage order, **none of which is current**: the r3 pair
`64049-2026.08.07` / `45833-2026.08.07` (metal-green at the 2026-08-07 calibration;
superseded **additively** by r4, kept valid-in-place — §§7–8), the r2 pair
`53963-2026.08.06` / `14821-2026.08.06` (**never deploy** — latent cdfs stack-sdcom
defect), the first P5.4 mint `45343-2026.08.06` / `05929-2026.08.06` (**never deploy**,
**quarantined**), and the W6-P pair `45473-2026.07.23` / `00961-2026.07.23` (`00961` was
the last metal-validated identity until the r3 calibration) — §7.

## 2. The shared boot2 (proprietary; acquired, never committed)

Both packages ship the same `/stand/boot2.boot`: the **flags-based** loader,
`sha256 f287ff3a759d6f80304fa35bb53e1479fc98056836b44a16824bd3e3f8fdba78`, size 8192. It is
acquired at build time through the kerntools gate
(`amix-kerntools/tools/boot2-sha-gate.sh --boot2 <src> --out …`), which **REFUSES** the
name-based Amix-2.1 install-media loader (`sha256` prefix `5ab360b1…`, which D245s on metal)
and any unknown sha. The blob is copied into the gitignored build staging and **never
committed** (contract identifies it by hash only).

## 3. Private-flag mechanics — how they can NEVER reach the public repo

The kernel and boot2 are proprietary-derived (`/stand/unix` links Commodore SVR4 objects;
`boot2` is a Commodore blob), so a kernel package is the same license class as the stock
factory packages. Three independent mechanisms enforce PRIVATE-only:

1. **Physical separation.** `build-packages.sh --kernbench/--kernz3660/--kern` mint into a
   **separate** private staging dir (`$KERNEL_STAGING`, default `build/kernel-private`), not
   the redistributable `build/repo-staging`. The kernel arms are **never** part of `--all`
   or the bare default (which build only the redistributable set).

2. **Catalog refusal (`gen-catalog.py`).** A package whose **pkginfo carries the
   kernel-package markers** (`KSUM_R` and/or `BOOT2_SHA` — the params W6-P mints onto
   `KERNBENCH`/`KERNZ3660`) is refused **fatally** from a catalog build — the catalog is not
   written at all (no partial catalog that blesses the rest). Defense in depth: a private
   package can never even appear in the redistributable catalog.

3. **Publish refusal (`publish.sh`).** Before it rsyncs, publish runs
   `gen-catalog.py --scan-private <staging>` and **refuses** (exit 4, nothing written) if any
   `*.pkg`/`*.pkg.Z` in staging carries those markers. This is the load-bearing gate: publish
   rsyncs *every* `*.pkg`, so a hand-added or stale-catalog kernel package that slipped past
   the catalog step is still caught here.

All three are **fail-closed with no `--force`/override**. This mirrors `amix-installng`'s
Gate-17 licensing posture, applied to the package/remote-repo publish path. The definition of
a private kernel package lives in exactly one place — `gen-catalog.py` `KERNEL_MARKER_PARAMS`
— which both the catalog build and the publish scan consult.

> **Re-key (METAL-FIX.2b, 2026-07-23).** The gate originally keyed on the pkgmap
> **pathnames** `/stand/unix` + `/stand/boot2.boot`. That was wrong: **stock `core` ships
> those same members as original Amix content** and has always been in the (LAN-private)
> catalog, so the pathname gate condemned every regen of the real 32-row catalog — and the
> explicitly-private installng raw-source build, which legitimately clones the golden kernel
> but is no *package*. The gate now keys on the **pkginfo markers `KSUM_R`/`BOOT2_SHA`**,
> which OUR minted kernel packages carry and no stock/other package does. This refuses
> exactly `KERNBENCH`/`KERNZ3660` (as intended) while stock `/stand` content catalogs and
> publishes normally. No override flag was added: the marker re-key makes flags unnecessary,
> since the redistributable/base staging contains no kernel packages. Regression-locked in
> `tools/repo/tests/run-tests.sh` T13 (kernel-marker package → refused; a markerless
> `/stand`-shipping package → passes).

### Why they are not in *any* catalog

The kernel packages are consumed by **pkgadd of a local `.pkg`** on the install medium
(installng's flow), not by `apkg` over HTTP, so they need no catalog at all. Keeping them
out of every catalog (rather than inventing a private catalog) means there is no code path
that could serve them off-LAN. The `deps.conf` edges `kernbench: core` / `kernz3660: core`
are recorded for documentation and for any future private/local resolver; gen-catalog never
looks them up because the packages are never in its input.

## 4. Consumption — what pkgadd does, and what it does NOT do

`pkgadd` of `KERNBENCH`/`KERNZ3660` onto a live box (or a mounted target root under `-R`)
**copies three ordinary files into the target root filesystem**: `/stand/unix`,
`/stand/boot2.boot`, and the `/stand` directory, and records them in that root's
`contents` DB. **That is all it does.** It does not rotate the previous `/stand/unix`, it
does not touch the RDB, and it does not write the raw boot slice — a package install can
never brick the boot chain.

Making the installed kernel **bootable** is a separate, gated step owned by **`amix-installng`
(`updbootpart`, W6-I)**: framing `boot1 + boot2 + unix` into the RDB `UNI\0` boot slice — a
raw-device write pkgadd never performs. That step re-runs `boot2-sha-gate` (refuse
`5ab360b1…`) and `rootdev-assert` before the write and `bootchain-verify` after it. Any
rotation/backup of the prior kernel, and the raw reframe itself, are updbootpart's to own —
**not** the package's.

## 5. Discrepancies with the W6-K draft (kerntools doc amendment owed)

Two deliberate corrections vs. `amix-kerntools/docs/kernel-packages.md` as drafted; both
should be reconciled into that doc at wave close:

- **KERNBENCH payload is the slice-proven booting bytes, not the relocunix.** The W6-K draft
  staged KERNBENCH as the ET_REL `relocunix` representation (`sum -r 42265`, 1 577 468 B).
  Per the W6-U bench probe, the bytes that actually **boot** (pushed to `/stand`,
  stock-`makeiblk`-framed, cold-booted ×2) are `sum -r 45473`, 1 252 347 B. These are two
  representations of the **same** kernel; the package ships the proven-booting slice bytes,
  so `KSUM_R` and the `VERSION` REV are **45473**, not 42265. Recorded in
  `build/kernel-packages/bench/unix.provenance`.

- **`ARCH=Amiga`, not `m68k`.** The draft's proposed pkginfo used `ARCH=m68k`. This mint uses
  **`ARCH=Amiga`** to match all 27 stock factory packages and every other package this repo
  ships (the arch the on-box `pkgadd` is proven to accept). Since these packages MUST pkgadd
  cleanly onto the box, matching the proven convention is the safe engineering choice.

## 6. Proofs recorded at mint (2026-07-23, host-side)

- `pkgtrans` round-trip both packages: unpacked `/stand/unix` is **md5-identical** to the
  staged payload (KERNBENCH `0f9e8a94…`, KERNZ3660 `b12bcdb3…`), `sum -r` 45473 / 00961, sizes
  match; unpacked `/stand/boot2.boot` re-verifies `sha256 f287ff3a…`.
- pkgmap of both: `/stand` `0755 root root`, `/stand/unix` and `/stand/boot2.boot`
  `0644 root root`, class `none`, no class-action/postinstall lines.
- Licensing gate fires: `--scan-private` and normal catalog build both **refuse** (rc 3, no
  catalog); `publish.sh --dry-run` **refuses** (rc 4, destination untouched) on a staging
  carrying either package; clean redistributable staging passes. Regression-locked as
  `tools/repo/tests/run-tests.sh` T13.

## 7. P5.4 re-mints r1–r3 (2026-08-06/07) — HISTORY, superseded by r4 (§8)

> **Not current.** This section records the r1–r3 mints as they stood on 2026-08-07.
> The current identities are the **r4** pair in **§8** (`49667`/`60364`, 2026-08-16).
> r3 is superseded **additively** — it was never defective and its `.pkg` pair stays
> valid-in-place — so "current" below should be read as "current at r3".

The **P5.4 kernel rebuilds** (the `z3660eth` major **48→51** renumber and the `aen`
security patch actually in the link) supersede the W6-P identities. Same package names, same
three-object payload, same rootdev/`CONFIG`, same private-flag mechanics (§3, unchanged);
what moves is the `/stand/unix` bytes, `KSUM_R`, `VERSION`, and — for `KERNBENCH` — the
`KMIX`, which **gains `z3660eth`**. Three mints happened (r1 2026-08-06, quarantined;
r2 2026-08-06, superseded; **r3 2026-08-07, current at the time**):

| PKG | supersedes (never deploy) | **`VERSION` (r3)** | `sum -r` | size | md5 |
|-----|-----------|--------------------|----------|------|-----|
| `KERNBENCH` | r2 `53963-2026.08.06`; r1 `45343-2026.08.06` (quarantined); W6-P `45473-2026.07.23` (kept) | **`64049-2026.08.07`** | 64049 | 1 585 656 B | `3df0a0d5045edc106857a8ea83ede7ad` |
| `KERNZ3660` | r2 `14821-2026.08.06`; r1 `05929-2026.08.06` (quarantined); W6-P `00961-2026.07.23` (kept — last metal-validated before the r3 calibration) | **`45833-2026.08.07`** | 45833 | 1 586 680 B | `150d7c5a8262e6c466ab1f1c54d18edd` |

Payload sources (provenance siblings beside each artifact, mirrored into the staged
`build/kernel-packages/{bench,onbox}/unix.provenance`):
`amix-kerntools/work/p54r3-bench-smoke/relocunix` (KERNBENCH — a full bench-smoke run
dir, manifest `provenance.txt` + `gates.tsv`) and
`amix-kerntools/work/kernel-packages/p54r3-combined/unix` (KERNZ3660).

> **POISONED first mint (same day, 2026-08-06).** The first P5.4 successors —
> `KERNBENCH 45343-2026.08.06` (1 585 284 B) and `KERNZ3660 05929-2026.08.06` (1 586 308 B) —
> were minted from the Wave-1 build batch that had **silently linked `amix-cdfs`'s
> unvalidated `upstream-sync-2026-07` `libcdfskern.o`** (95 826 B, md5 `a01c7396…`; the
> amix-cdfs tree sat on the sync branch). On metal (M-RUN4) that batch's installed kernel
> **panicked the remount canary** in one cycle (Bus Error, fault addr `482F87AC` — the cdfs
> corruption class); Packet D formally FAILED and the sync line is frozen. Those identities
> must **never be deployed**: their `.pkg` files are quarantined out of every `*.pkg` glob at
> `build/kernel-private/POISONED/*.pkg.POISONED` (README beside them), kept for forensics
> only. The r2 rebuilds carry the **metal-proven `8de83cf`-line cdfs** (`libcdfskern.o`
> 96 126 B, md5 `80635a1b…`, `sum -r` 52157), now **pin-enforced at staging** by kerntools'
> `fstypes.conf` md5 provenance pin (kerntools `2ec2b19`; build logs record "(pin OK)").
> Record: `amix-kerntools/docs/kernel-packages.md` §4a-bis;
> `amix-cdfs/docs/upstream-rebase-plan.md` (Packet D / §5.1).
> **Correction (2026-08-07, P5.4 attribution revision).** The causal story above is
> superseded. The M-RUN4 panic mechanism was the cdfs **stack-sdcom defect** (see the r2
> record below; fixed in `amix-cdfs` `main` @ `9360542`), which was present in **both**
> cdfs lines at the time — **not** the `upstream-sync-2026-07` content per se (the sync
> line is exonerated for the panics), and **not** the cross toolchain. The r1 quarantine
> stands regardless: those packages carry the defect and must never be deployed. Metal
> calibration 2026-08-07 confirmed the attribution — 15/15 cycles + 25/25 rapids green
> on both r3 kernels.

> **r2 superseded (2026-08-07) — the stack-sdcom root cause.** The r2 successors
> (`KERNBENCH 53963-2026.08.06`, `KERNZ3660 14821-2026.08.06`) are **NOT** poisoned-cdfs-line
> kernels: they carry the proven `8de83cf`-line cdfs **with a latent stack-sdcom defect** —
> `amix_kern_submit()` handed the sd layer a **stack-allocated `sdcom`**; the AMIX kernel
> stack lives in the per-process **u-area window**, so the HBA's completion ISR dereferenced
> it in a foreign process context (scribbling that process's stack, jumping through garbage
> `cp->intr`). **Not the cross toolchain.** Fixed in `amix-cdfs` `main` @ **`9360542`**
> (per-call `kmem_zalloc`/`kmem_free`); the fixed object is `libcdfskern.o` 96 198 B, md5
> `58ff932f00634806d79f9ed97c6b6efe`, `sum -r` 32976, **pin-enforced at staging** (kerntools
> `6258301`, "(pin OK)" in both r3 build logs). **Bench falsification flipped both
> kill-recipes green** (cross-kernel 5-cycle battery PASS ×2; native rapid mount/umount
> 25/25 clean — kerntools §4a-ter, `work/p54-cdfs-repro/`). The r2 `.pkg` pair stays
> **superseded-in-place** in `build/kernel-private/kernel/` (never deploy; kept like the
> July predecessors, unlike the quarantined r1 pair). The r3 KERNBENCH payload is
> additionally **bench-smoke validated**: 8/8 PASS incl. four-arm buildgate, d245
> relinkguard clean, **cold boot to run-level 2 + LAN**, digest 3/3
> (`amix-kerntools/work/p54r3-bench-smoke/gates.tsv`). KERNZ3660 r3 is gate-green +
> host-oracle-clean (not bench-booted). At mint neither was metal-validated; the
> **2026-08-07 metal calibration closed this GREEN** — 15/15 cycles + 25/25 rapids on
> **both** r3 kernels — so both r3 kernels are now metal-validated (`00961` was the last
> metal-validated kernel until then).

- **The §5 slice-vs-relocunix representation split is dissolved.** W6-P shipped KERNBENCH as
  the slice-proven booting bytes because they *differed* from the relocunix representation.
  The P5.4 bench builds proved `/stand/unix` on the golden build box **== the gated relocunix
  BYTE-EXACT** (pulled length-gated, box `sum -r` == host on the r2 and r3 builds alike), so both packages now ship the
  gated **ET_REL relocunix bytes verbatim** — the representation KERNZ3660 has always
  shipped — and `KSUM_R`/`REV` = the relocunix `sum -r`. §5's first bullet is historical.
- **Predecessors kept, not destroyed:** `KERNBENCH-45473-2026.07.23.pkg`,
  `KERNZ3660-00961-2026.07.23.pkg` (July, W6-P) and the superseded r2 pair
  `KERNBENCH-53963-2026.08.06.pkg` / `KERNZ3660-14821-2026.08.06.pkg` remain in
  `build/kernel-private/kernel/` beside the r3 successors (the r1 pair is quarantined in
  `../POISONED/`). `00961` was the last **metal-validated** kernel until the 2026-08-07
  r3 metal calibration.
- **Validation status at the r3 mint:** KERNBENCH is **bench-smoke GREEN** (8/8, cold boot
  to run-level 2 + LAN); KERNZ3660 is clean-gate-green + host-oracle-clean (d245-judge
  CLEAN), not bench-booted. Neither was metal-validated at mint — closed by the
  **2026-08-07 metal calibration: GREEN** (15/15 cycles + 25/25 rapids on both r3
  kernels); **both r3 kernels are now metal-validated**.
- **Proofs at mint (host-side, same battery as §6):** `pkgtrans` round-trip of both `.pkg`s
  yields `/stand/unix` **md5-identical** to the staged payloads (table above), `sum -r`
  64049 / 45833, sizes match; `/stand/boot2.boot` re-verifies `sha256 f287ff3a…`; pkgmap =
  `/stand 0755 root root`, both files `0644 root root`, class `none`, no class-action lines.
  The licensing gate fires on **both successors**: `gen-catalog.py --scan-private` refuses
  rc 3 (`PRIVATE CONTENT … is a kernel package (pkginfo marker(s) BOOT2_SHA, KSUM_R)`), and
  the normal catalog build refuses rc 3 with **no catalog written**. Suite: repo tools
  94/94 (T13 included).

## 8. P5.4 r4 (2026-08-16) — the full-regeneration-batch mint

**r4 is additive, not a retraction.** r3 (`64049`/`45833`, §7) was **not** defective — it is
metal-green from the 2026-08-07 calibration and its `.pkg` pair stays **valid-in-place** in
`build/kernel-private/kernel/` as the previous line. What r4 adds is the whole P5.4
regeneration batch that accumulated after r3 was cut, built as **one line**: the bench kernel
was linked from the *same* patched image the combined build produced, so both r4 kernels
carry byte-identical batch inputs.

| PKG | **`VERSION` (r4)** | `sum -r` | `/stand/unix` size | payload md5 | `.pkg` size | `.pkg` md5 |
|-----|--------------------|----------|--------------------|-------------|-------------|------------|
| `KERNBENCH` | **`49667-2026.08.16`** | 49667 | 1 586 312 B | `8072e610afa7060fb0c96b8536280b42` | 1 598 464 B | `89a34e2c699a88a397dea64381314d2e` |
| `KERNZ3660` | **`60364-2026.08.16`** | 60364 | 1 587 524 B | `23b4b8983435acdf900fa343cb33281d` | 1 599 488 B | `a8a025d0c39f1bc5473be23d802d6638` |

> The **payload** md5/`sum -r`/size are the gate — they are what `gate_kernel` enforces and
> what `KSUM_R` publishes. The **`.pkg`** md5 identifies *these* built artifacts only: `pkgmk`
> stamps a wall-clock `PSTAMP` into `pkginfo`, so a re-mint of the same payload yields a
> different `.pkg` md5. Never treat the `.pkg` md5 as a reproducibility check; check the
> round-trip payload instead.

Payload sources (provenance siblings beside each artifact, mirrored into the staged
`build/kernel-packages/{bench,onbox}/unix.provenance`):
`amix-kerntools/work/p54r4-bench-smoke/relocunix` (KERNBENCH — a full bench-smoke run dir,
manifest `provenance.txt` + `gates.tsv`) and
`amix-kerntools/work/kernel-packages/p54r4-combined/unix` (KERNZ3660). Registry rows:
`amix-kerntools/docs/kernel-packages.md` §4a-quater (`43c54e7`).

### The batch — what r4 carries that r3 did not

| element | source | proof |
|---|---|---|
| **probed `support.c`** | `amix-a4091` `support.c.patch` (adf3875 line); `kernel-patches.conf` row live @ kerntools `5183993` | `autocon()` disassembly = the **two-register anti-alias** probe (0x55/0xAA through SASR `0xDD0041` + SCMD `0xDD0043`, behind the VPOSR AGA gate); `0x7000000` — the retired RAM-size guess — occurs **zero** times in either kernel |
| **`z3660scsi` direct map** | `amix-z3660scsi` `8293cdc` — **never flown before r4** | symbol `z3660_direct_map`; direct arm sets the flag and does plain window arithmetic with **no `sptalloc` call**; `sptalloc` arm retained. Combined kernel only |
| **`z3660net` direct map** | `amix-z3660net` `b89c5d2` | symbol `z3660eth_direct_map`; same shape. With the row above, **98 sptmap pages** (33 + 65) return to the map |
| **cdfs errno de-laundering** | `amix-cdfs` `e0ef11a`; pin @ kerntools `811dd0c` | `exp` md5 `673cd9f43a928d0e57e3a9c32cecb9a4`, 96 366 B, `sum -r` 56869; both build logs record "(pin OK)" |
| **`z3660eth` major 51** | source-side since P5.2 | baked **binary-side**: `(0xada4 − 44 − 0xa31c)/52 = 51` exactly, stride corroborated by `(cdevcnt − cdevsw)/52 = 70 = CDEVSIZE` |
| a3091/a2091 start-queue lifecycle fix | `amix-a4091` `be2f5e3` | rode in for free — kpatch read the golden's stale `.kprev` and re-established both from pristine stock (`4 target(s) checked, 3 applied (1 already present)`) |

> **★ `KMIX` change — `support-stock` is RETIRED from the `KERNBENCH` line.** The r4 bench
> kernel links the **probed** `support.c`, so the tag would now be a false assertion. The
> kerntools vocabulary deliberately has **no `support-probed`/`support-fixed` tag yet**
> (registering one is a vocabulary change, and the vocabulary is closed), and an **absent**
> group-4 tag asserts nothing either way — so the tag is simply **dropped**:
> `KMIX=a4091,z3660eth,cdfs,a3091-fixed,a2091-fixed,scsi-gsio`. `KERNZ3660`'s
> `KMIX=z3660scsi,z3660eth,cdfs` is **unchanged** (it never carried group-4 tags; adding
> them now would be a contract change this mint does not own). This is the first `KMIX`
> that describes a kernel by what it *omits*.

### Validation status at the r4 mint

- **`KERNZ3660` 60364 is METAL-PROVEN** (2026-08-15, P5.4 R3): the
  `updbootpart` reframe was byte-clean, **two** cold power-to-network boots (~270 s each),
  and `adb` read `z3660_direct_map = 1` **and** `z3660eth_direct_map = 1` live on the
  hardware — so the 98 reclaimed sptmap pages are hardware fact, not a gate result.
  **60364 is now the last metal-validated kernel identity.** Record:
  `amix-kerntools/CHANGELOG.md`, 2026-08-15 metal postscript.
- **`KERNBENCH` 49667 is bench-smoke GREEN** — 8/8: four-arm buildgate STABLE after 2 builds
  (`sum=49667`), d245 relinkguard clean (new ref key `d59fdc6d5d96`), **cold boot to
  run-level 2 + LAN** with on-box `/stand/unix` `sum -r` 49667, digest 3/3 against host
  truth, teardown confirmed. Not metal-flown — it is the **a4091 bench family**, which the
  Z3660 metal box is not; the r4 metal proof belongs to the combined kernel.
- Gate detail for the combined kernel: clean-gate STABLE after 1 builds (undef=0,
  checkunix-clean, relgate-clean), pull byte-exact (box 60364 == host 60364), `nm -u` =
  `{edata,end,etext}`, relsim COMPLAINTS=0 (29 310 `R_68K_32`), d245-judge CLEAN,
  rootdev-assert PASS `0x00480016` + scsi-slice media pairing.

### Proofs recorded at the r4 mint (host-side)

- **Input gate, both directions.** `gate_kernel` accepted each staged input at its expected
  identity (`49667`/1 586 312 B, `60364`/1 587 524 B) — and was **falsified**: a wrong-kernel
  source refused on the size arm, and a **one-byte-flipped** copy of each correct kernel
  (identical size, different `sum -r`) refused on the sum arm (`40718`, `01010`). No `.pkg`
  was produced by any refused run.
- **★ Hardening found by that falsification.** The arms copied the source over
  `build/kernel-packages/{bench,onbox}/unix` **before** gating, so a *correctly refused* mint
  still left known-bad bytes in the staging area. Both arms now **gate the source first**,
  then copy, then re-gate the copy (the second call still catches a truncated copy). Re-proved:
  after a refused run the staged payloads still read `sum -r` 49667 / 60364.
- **Round-trip.** `pkgtrans` unpack of both `.pkg`s yields `/stand/unix` **byte-identical**
  (`cmp`) to the staged payloads — md5/`sum -r`/size all match the table above;
  `/stand/boot2.boot` re-verifies `sha256 f287ff3a…`. Datastream member magic at offset 512
  is `070701` (newc) on both.
- **pkgmap.** Exactly `d none /stand 0755 root root`, `f none /stand/unix 0644 root root`,
  `f none /stand/boot2.boot 0644 root root`, `i pkginfo` — class `none` only, **no**
  class-action or postinstall line, nothing that writes a raw device.
- **Licensing gate fires on both r4 successors** (§3, unchanged): `--scan-private` refuses
  rc 3 naming each package; the normal catalog build refuses rc 3 with **no catalog written**;
  `publish.sh --dry-run` refuses **rc 4** with the destination left with **zero files** —
  while the same staging *without* the kernel package publishes rc 0, proving the refusal is
  caused by the r4 packages themselves and not by the staging's shape.
- **Suites:** repo tools **178/178** (T13 included), apkg **87/87**, contents-fsck **19/19**.
