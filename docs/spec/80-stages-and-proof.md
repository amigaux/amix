# 80 — Stages and proof

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §8 (one 1.1 release, internal proof order, nothing ships until all of it is done on both lines and every medium; where the code lives; the collaboration asks), D-3 §3 (both lines first-class), D-3 §2 (emulation runs the same bytes as metal)
- **Replaces:** P-28's stage table (S1a/S1b-core/S2/S3 inside 1.1; S4 in 1.2; S5 in 1.3; separable tape and network) and P-24's staged releases

Paths in this file are relative to the Amix project workspace (see `00-overview.md`, "Sources").

## 1. Release shape

There is one release, 1.1. The only release before it is the 1.0.1 media
refresh (r7), which carries no part of this work. Inside 1.1 the work runs in
a fixed *proof order*: each stage is proven on the emulator and then on metal,
on both CPU lines, before the next stage starts building on it. A stage that
is proven is not shipped; nothing ships until stage 5 is proven on both lines
and on every medium of `50-media.md`.

Two rules hold across all stages:

- **Every box can come back.** No stage may produce a state from which a box
  cannot be returned to a booting generation without the step that broke it.
  Rollback is proven on static kernels (stage 2) before the first module loads
  (stage 3).
- **Same bytes on the emulator and on metal.** A bench row runs the image that
  a metal row runs; a medium is never rebuilt for metal.

## 2. The stages

| # | Stage | Builds | Proven on the emulator by | Proven on metal by | Exit gate |
|---|---|---|---|---|---|
| 0 | Specification | this directory | — | — | every D-3 item mapped (`00-overview.md`); every measurement listed with its evidence class (`90-measurements.md`) |
| 1 | **Loader** | boot1, boot2, the boot-store and ISO9660 readers, the menu, the loader record (`10-boot-loader.md`) | boots today's static kernels (one generation, no modules) from every boot device the emulator offers: Z3660 hdf, A4091, A3000 WD, Gayle, DF0 floppy on both lines, CD on the A4091 ROM; menu, rollback key and safe-mode key driven over the emulator's input; every failure mode of `10-boot-loader.md` §9 provoked and its message checked | the same images, cold-booted on both boxes from each controller they carry; serial console and keyboard/HID menu input; the try-once write on each boot ROM | the static kernels boot from our loader exactly as from the stock loader (same root naming, same devices); no stock loader on any 1.1 medium |
| 2 | **Lifecycle and rollback on static kernels** | `kbootset`, `kinfo`, generations, the manifest, apkg 0.3 (kernel-space marking with SHA-256, the signature hook, transaction journal), kernel and loader packages, the upgrade install (`40-generations-and-composer.md`, `60-signing-and-publishing.md`) | upgrade, commit, mark-good, rollback, one-shot previous, try-once fallback, pristine boot, power cut at each commit step (emulator kill), refusal of a kernel-space package whose SHA-256 differs, upgrade install from a 1.0 image | one upgrade + rollback + power-cut row per box per line; one upgrade install of a 1.0 box per box | a box upgraded and rolled back with apkg alone; every power-cut point leaves a booting generation |
| 3 | **Modules** | the module core patch queue, `marc_post`, copied boot-class and demand modules (z3660eth, z3660rtg + monitor switch), the ABI kit, the allowlisted symbol table (`20-…`, `30-module-core.md`) | load, unload refusal, dependency, kabi refusal, bad-object refusal, 128 MB machines, the relocation oracle against the cross linker | z3660eth and z3660rtg as modules on both boxes; interrupt attachment on metal | the network and graphics drivers ship only as modules; no regression against the static drivers' throughput figures |
| 4 | **Root as a module** | resident root-class loading (`marc_root`), the sd registry and card-number contract, `intr_attach`, the halt pass; z3660scsi, A4091/A4092, Gayle IDE as root modules; safe mode | the card-number gate over the board sets of record (`30-module-core.md` §5.3): unchanged sets keep their 1.0 names, changed sets give exactly the listed names, three- and four-controller sets the contract's names; safe mode on each root controller; a damaged root module selects the menu | each root controller as a module, cold boots on both boxes; the A4000T onboard-controller probe gate; cache/DMA rows per HBA | the 1.0 kernel families retire; one kernel image per CPU line |
| 5 | **Filesystems as modules** | ufs, s5, cdfs as modules on our line, with Antti's base as the merge target (`30-module-core.md` §6) | root on ufs and on s5 as modules; cdfs as a demand module and as the CD root-class module | root filesystem modules on both boxes; CD boot and install | the kernel image contains no root filesystem; every medium of `50-media.md` built from the final packages and proven |

The 030 line goes through every stage beside the 040/060 line. Where metal
for the 030 line is limited (the A4000D's stock CPU card is a 68EC030 without
an MMU, `tmp/2026-10-22-modules-proposal/bootchain-facts.md` F8), the metal
evidence for the 030 line is named per measurement in `90-measurements.md` and
the gap is an open question (OQ-80.1), not a silent skip.

## 3. What each stage must not break

| Stage | Invariant carried forward |
|---|---|
| 1 | Root naming is unchanged: the RTH1 root-hint semantics (`review/D-2-root-hint-r6-decisions.md`, row 4) are reproduced by our loader byte for byte. |
| 2 | The pristine generation is never deleted; an unbooted generation never displaces a good one. |
| 3 | A module that fails to load leaves the kernel as it was; the static drivers it replaces stay buildable until stage 3 exits. |
| 4 | Every disk is named as the card-number gate of `30-module-core.md` §5.3 expects for its board set. |
| 5 | Safe mode still reaches a shell on every root controller and root filesystem. |

## 4. Where the code lives

| Code | Repository | How it reaches users |
|---|---|---|
| Loader, module core (patch queue), `kbootset`, ABI kit, this specification | amix-dlm (this repository, public on release) | loader and kernel-space packages |
| Module recipes (one per driver) | the driver repositories (z3660scsi, a4091, gayle-ide, z3660net, z3660rtg, cdfs) against the ABI kit | module packages |
| Kernel-side hooks (the `marc_root` call, the arena, the loader record reader, `kinfo`, four-card sd) and the 040/060 base rebuilt without ufs/s5 | built on our line; offered to amix-040-060-port as merge requests, Antti reviews | the kernel packages |
| apkg 0.3 | amix-packagemanager | the APKG package |
| Installer, media builders, upgrade install, repair menu | amix-installng | the media |

## 5. Collaboration asks

| Who | Ask | When |
|---|---|---|
| Antti Sokero (amix-040-060-port) | Take the module hooks once stage 4 is proven; take the filesystem separation once stage 5 is proven; review the ABI (allowlist, DDI v1, kabi rule) before the ABI kit is frozen. | ABI review at the end of stage 3; hooks after stage 4; filesystems after stage 5 |
| kdedon (ashnazag, the DLM core) | Credit in the README and on every adopted file; a heads-up when the patch queue is first published; each patch offered upstream for him to take or decline. | heads-up at publication; patches whenever he wants them |
| Emre Bastuz (amix-gayle-ide) | Build Gayle IDE as the first outside module against the ABI kit. | after the ABI kit exists (stage 3) and our own integration of his driver is tested |

## 6. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-80.1 | What metal evidence exists for the 030 line? The A4000D's stock card has no MMU and the Z3660's 030 mode was blocked for 1.0 (`bootchain-facts.md` F8). Candidates: an A3000 or a full 68030 card at a collaborator, or the Z3660 030 mode once unblocked. | us; Antti (his A3000) |
| OQ-80.2 | Whether the A4000T onboard 53C710 driver exists in time for stage 4. D-3 §4 lists it "when its driver exists"; if it does not, stage 4 exits without it and the release notes say so. | us |
| OQ-80.3 | What throughput figures stage 3 compares against (the static z3660eth and RTG baselines of record). | us |
| OQ-80.4 | Whether the Gayle IDE author takes the module form into his driver: the root-class wrapper with the positive-ID `mobo:gayle` probe, `intr_attach` in place of the driver's own interrupt-table search, the four-card rank key, the ATAPI CD route — and builds it against the ABI kit as the first outside module (`amix-gayle-ide/docs/module-form.md`). Asked once our integration of his driver is tested. | Emre |

## 7. Measurements

Each stage's emulator and metal rows are listed in `90-measurements.md` with
their evidence class (bench or metal, P-28 D51) and the stage that needs them.
