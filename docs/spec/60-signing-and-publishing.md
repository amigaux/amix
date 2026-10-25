# 60 — Signing and publishing

- **Status:** draft (S0), 2026-10-25
- **Implements:** D-3 §7 (kernel, loader and module packages in the public catalog, marked kernel-space; one signing key held offline by the owner; the public key in the installer and the client; a box refuses unsigned kernel space; a second key only by decision; the ABI kit published in amix-dlm)
- **Builds on:** P-28 D10, D12, D13, D30, D48

Paths are relative to the Amix project workspace. `PM/` =
`amix-packagemanager/`.

## 1. Threat and scope

The package repository is served over plain HTTP, because the 1992-era client
has no TLS (`grimoire-amix/docs/how-it-works/package-repository.md:27-43`).
Today integrity is an MD5 and a size per package plus an optional MD5 of the
catalog; there is no signature or SHA-256 code in apkg
(`PM/src/apkg/source.c:140-160`; `PM/src/apkg/main.c:125-147`). For userland
packages that is the accepted 1.0 risk. For kernel space it is not: a kernel
or module altered on the network path is written into the boot store and
survives a userland reinstall (`tmp/2026-10-14-modules-study/C1-longterm-critique.md:282-296`).
The attacker considered is on the network path, not root on the box.

## 2. The key

| Item | Rule |
|---|---|
| Algorithm | Ed25519 detached signatures (proposed; a small portable verifier written in C89, no FPU, 68060-safe), verification time on the slowest supported CPU measured (M-SIG1 = STUDY U17) |
| Signing key | one; held by the owner offline; never on a build host, never in a repository |
| Public key | baked into apkg (from 0.3), the installer's static apkg, `kbootset`, and every medium (`/install/pubkey`), each with its key id |
| Keyring | the verifier accepts a list of key ids; 1.1 ships a list of one |
| A second key | only by the owner's decision; it enters the keyring through a new release of apkg, the installer and `kbootset` signed by the existing key — never by a record fetched from the repository (OQ-60.2 records the alternative) |
| Compromise | a key revocation is the same path: a release signed by the remaining key that removes the compromised id |

## 3. What is signed and what is checked

**Signed object:** the catalog. The signature file sits beside it
(`catalog.sig`), covers the catalog bytes exactly, and names the key id.

**Kernel-space entries** sit in the hidden `#ext kpkg 1` block of the catalog
(every line under 2048 bytes, `#` in column 0, the `#apkg-catalog 1` header
unchanged, so deployed clients skip it and never see kernel space,
`tmp/2026-10-22-modules-proposal/refute-apkg-stage-and-comment-skip.md`). Each
entry carries, beside the normal fields, `role=kernel|loader|module`, the
line, the kabi tag, the compiler pin and the package's **SHA-256**.

| Who | Checks | Refuses |
|---|---|---|
| apkg 0.3 (box and installer) | the catalog signature before reading the kernel-space block; each kernel-space package's SHA-256 after download | any kernel-space package from an unsigned or badly signed catalog, or with a hash mismatch; a catalog whose kernel-space block is present but whose signature is missing |
| apkg 0.3 | records, per installed kernel-space package, the signed catalog line it was installed from (`/var/apkg/ksig/<pkg>`) | — |
| `kbootset build/commit` | each kernel-space member's SHA-256 against its recorded signed line (`40-generations-and-composer.md` §3.1, gate 1) | composing a generation from any member without a recorded signed line — including files placed by hand or by a bare `pkgadd` |
| the loader | CRC-32 of each member (integrity of the medium, not authenticity) | — |

Userland packages keep today's checks; their move to signed catalogs is
apkg's own roadmap, not a 1.1 requirement here.

## 4. Offline media

CD, tape, netinstall media and install disk images carry the catalog, its
signature and the public key; the installer verifies before installing kernel
space, exactly as over the network. Floppies carry no packages (D-3 §2). A
medium built by the host `kbootset --image` composes its own generations only
from signed packages, under the same gate.

## 5. What the public catalog and site show

- The catalog marks each kernel-space package with its role, line and kabi
  (above); apkg 0.3 tells the user before a transaction that kernel space is
  involved and that a generation build and a power cycle follow.
- The repository's private-package gate, which refuses kernel packages today
  (`PM/tools/repo/gen-catalog.py:128-130,358-368`), is re-scoped so that
  kernel-space packages are admitted only into a signed catalog (P-28 D13).
- The public site lists kernel-space packages in their own section with the
  line and kabi, and links the ABI kit.
- The repository keeps exactly one previous kabi's kernel-space packages
  served after a kabi change (P-28 D55).

## 6. Publishing the ABI kit

The ABI kit (`20-module-format-and-abi.md` §5) is published in this
repository and as one package per kernel line. It contains no Commodore or
AT&T material unless the owner decides otherwise (OQ-20.1). Every publication
— repository, catalog, site — remains a per-action owner decision.

## 7. Open questions

| ID | Question | Proposed owner |
|---|---|---|
| OQ-60.1 | Ed25519 (proposed) or another scheme; signature file format (a minisign/signify-compatible layout is proposed so standard tools can sign offline). | us; owner holds the key |
| OQ-60.2 | Whether a second key may also be admitted by a key-statement signed by the existing key and fetched from the repository (faster rotation, larger attack surface). Proposed: no. | owner |
| OQ-60.3 | Whether userland packages also require signatures from 1.1 on. | owner |
| OQ-60.4 | Which hashing and signature tools exist on the box for administrators (none recorded besides `sum`). `kbootset` carries its own SHA-256 either way. | us |

## 8. Measurements

M-SIG1 (verify time on 68030 and 68060), M-SIG2 (SHA-256 throughput on
68030 and 68060) — `90-measurements.md`.
