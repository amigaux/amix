# 60 — Integrity, signing and publishing

- **Status:** draft (S0), 2026-10-25; changed after the freeze by D-3 §13 — **signing is not in 1.1**
- **Implements:** D-3 §7 as amended by D-3 §13 (kernel, loader and module packages in the public catalog, marked kernel-space; the ABI kit published in amix-dlm; integrity by per-package SHA-256; no catalog signature, no key custody and no refusal of unsigned kernel space in 1.1; a verification hook kept so signing can be added later without a format change)
- **Builds on:** P-28 D10, D12, D13, D30, D48

Paths are relative to the Amix project workspace. `PM/` =
`amix-packagemanager/`.

## 1. What 1.1 does

| Item | 1.1 |
|---|---|
| Integrity | every kernel-space catalog entry carries the package's **SHA-256**; apkg 0.3 checks it after download, `kbootset` checks every member against it, the kernel checks every module load against the booted manifest (§3) |
| Signature | **none** (D-3 §13): no catalog signature, no signing key, no public key in the installer or client, no refusal of unsigned kernel space |
| Hook | the catalog format, apkg and `kbootset` keep a defined place for a signature check (§4), so a later release adds signing without changing a format |
| Userland packages | unchanged |

Fact for the record: today's catalog entries carry an MD5 and a size, and an
optional MD5 of the whole catalog; apkg has no SHA-256 code yet
(`PM/src/apkg/source.c:140-160`; `PM/src/apkg/main.c:125-147`). The SHA-256 on
kernel-space entries is new in apkg 0.3.

## 2. Threat, and what the hook is for

The package repository is served over plain HTTP, because the 1992-era client
has no TLS (`grimoire-amix/docs/how-it-works/package-repository.md:27-43`). A
kernel or module altered on the network path is written into the boot store
and survives a userland reinstall
(`tmp/2026-10-14-modules-study/C1-longterm-critique.md:282-296`). SHA-256 in
the catalog detects damage, not an attacker who also alters the catalog. The
owner accepted that for 1.1 (D-3 §13, the second deliberate exception beside
§5); the signing design in §5 is kept for the release that adds it.

## 3. What is checked in 1.1

**Kernel-space entries** sit in the hidden `#ext kpkg 1` block of the catalog
(every line under 2048 bytes, `#` in column 0, the `#apkg-catalog 1` header
unchanged, so deployed clients skip it and never see kernel space,
`tmp/2026-10-22-modules-proposal/refute-apkg-stage-and-comment-skip.md`). Each
entry carries, beside the normal fields, `role=kernel|loader|module`, the
line, the kabi tag, the compiler pin and the package's **SHA-256**.

| Who | Checks | Refuses |
|---|---|---|
| apkg 0.3 (box and installer) | each kernel-space package's SHA-256 after download, against its catalog entry | a kernel-space package whose SHA-256 differs or is missing |
| apkg 0.3 | records, per installed kernel-space package, the catalog entry it was installed from (`/var/apkg/kpkg/<pkg>`, with `verified=no` while no signature exists) | — |
| `kbootset build/commit` | each kernel-space member's SHA-256 against its recorded entry (`40-generations-and-composer.md` §3.1, gate 1) | composing a generation from a member without a recorded entry or with a different SHA-256 — files placed by hand or by a bare `pkgadd` included |
| the loader | CRC-32 of each member (medium integrity); places the booted manifest in the arena | — |
| the kernel (module core, `30-module-core.md` §2 patch 17) | every module load against the booted manifest's member list and SHA-256 | any module that is not a member of the booted generation or whose hash differs — unless the development-load flag was set for this boot, which the loader and the kernel both print |

## 4. The verification hook

Kept in 1.1 so that adding signing changes no format:

- **Catalog:** the kernel-space block may carry one line
  `#ksig <key-id> <file>` naming a detached signature file beside the
  catalog. 1.1 catalogs omit it; a 1.1 client reads and records it if present
  but does not act on it.
- **apkg:** one verification step runs after the catalog is fetched and
  before the kernel-space block is read. In 1.1 it records "unverified" and
  passes; a later release puts the signature check there and, by policy,
  refuses.
- **apkg records:** the `verified=` field of `/var/apkg/kpkg/<pkg>` (above).
- **kbootset:** gate 1 reads the recorded entry and its `verified=` field; a
  policy setting `require-signature` (absent in 1.1, default off when it
  arrives) turns an unverified entry into a refusal.

## 5. Signing — not in 1.1 (kept for a later release)

The design below was part of S0 and is suspended by D-3 §13. It is kept so
the release that adds signing starts from it.

| Item | Rule |
|---|---|
| Algorithm | Ed25519 detached signatures (proposed; a small portable verifier in C89, no FPU, 68060-safe); verification time measured (M-SIG1 = STUDY U17) |
| Signing key | one; held by the owner offline; never on a build host, never in a repository |
| Public key | baked into apkg, the installer's static apkg, `kbootset`, and every medium, each with its key id |
| Keyring | the verifier accepts a list of key ids |
| A second key | only by the owner's decision, through a new release of apkg, the installer and `kbootset` signed by the existing key |
| Compromise | a release signed by the remaining key that removes the compromised id |
| Signed object | the catalog; the signature file named by `#ksig` covers the catalog bytes exactly |

## 6. Offline media

CD, tape, netinstall media and install disk images carry the catalog; the
installer checks each kernel-space package's SHA-256 against it before
installing, exactly as over the network. Floppies carry no packages
(D-3 §2). A medium built by the host `kbootset --image` composes its
generations only from packages whose SHA-256 matches the catalog.

## 7. What the public catalog and site show

- The catalog marks each kernel-space package with its role, line and kabi
  (§3); apkg 0.3 tells the user before a transaction that kernel space is
  involved and that a generation build and a power cycle follow.
- The repository's private-package gate, which refuses kernel packages today
  (`PM/tools/repo/gen-catalog.py:128-130,358-368`), is re-scoped so that
  kernel-space packages enter the public catalog's hidden block, on the
  owner's per-action publish decision (P-28 D13).
- The public site lists kernel-space packages in their own section with the
  line and kabi, and links the ABI kit.
- The repository keeps exactly one previous kabi's kernel-space packages
  served after a kabi change (P-28 D55).

## 8. Publishing the ABI kit

The ABI kit (`20-module-format-and-abi.md` §5) is published in this
repository and as one package per kernel line. It includes the stock Amix
kernel headers a module build needs (D-3 §7: "the ABI kit (headers + module
tooling) is published in amix-dlm"; distribution permission of 2026-09-23);
they are added at kit build time and are not tracked in this repository's
history. Every publication — repository, catalog, site — remains a per-action
owner decision.

## 9. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-60.1 | For the release that adds signing: Ed25519 (proposed) or another scheme, and the signature file format (minisign/signify-compatible proposed). | us; owner holds the key |
| OQ-60.4 | Which hashing tools exist on the box for administrators (none recorded besides `sum`). `kbootset` carries its own SHA-256 either way. | us |

Closed by D-3 §13 as moot for 1.1: OQ-60.2 (admitting a second key by a
repository-fetched statement) and OQ-60.3 (signed userland packages).

## 10. Measurements

M-SIG2 (SHA-256 throughput on 68030 and 68060), M-SIG3 (manifest-only
loading in the kernel); M-SIG1 (signature verification time) is deferred
with signing — `90-measurements.md`.
