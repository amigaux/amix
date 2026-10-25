# C2-5 — the checksum contract, version 2 (draft)

- **Status:** draft for agreement, 2026-10-26 (OQ-40.5)
- **Replaces:** the `sum_gate_interplay` part of `amix-kerntools/contracts/bootchain-v1.json` for 1.1 boot stores
- **Implements:** `docs/spec/40-generations-and-composer.md` §3 (`check`), `60-signing-and-publishing.md` §3

## 1. Identity

A generation's identity is its manifest:
- every member is named with its size, its CRC-32 and its **SHA-256**
  (of the bytes after decompression);
- the manifest itself carries the `end crc32=` line;
- the control block holds the manifest's length and CRC-32.

`kbootset commit` writes a `sha256=` on every member it stores (from
2026-10-26, `kbootset/ks.c`).

## 2. Readers

| Reader | Checks | When |
|---|---|---|
| the loader | the CRC-32 of the control block, the manifest and each member it loads (medium damage) | every boot |
| `kbootset check` (the second reader) | the SHA-256 of every member in the store and in `/stand/gen/<id>/` against its manifest, and every member against its apkg record (C2-2); never writes | on demand, and by the installer after it writes a store |
| the kernel (stage 3) | each module it loads against the booted manifest's SHA-256 | every module load |

The 1.0 `sum -r` gate on the kernel bytes in the boot slice no longer
applies to a 1.1 store: the manifest's SHA-256 replaces it. A rig row that
compares booted bytes against the image takes the SHA-256 from the
manifest.

## 3. To agree

- with amix-kerntools: the rig's booted-bytes check reads the manifest
  (`lsstore`, or `kbootset status`) instead of the slice;
- `bootchain-v1.json` stays for 1.0 media.
