# Universal-SCSI install boot floppy

`tools/build-universal-bootfloppy.sh` frames the driver-augmented Amix 2.1 install
kernel into a bootable `boot.adf`. It is a thin wrapper around the proven host-side
framer `../grimoire-amix/tools/build-bootfloppy.sh`; it **does not build or modify the
kernel** — `tools/build-install-kernel.sh` does that (it drives the `amix-kerntools`
cross-build with the `amix-a4091` kernel-patches applied, writing only into this repo's
`work/`). This tool only frames an existing kernel.

The kernel it frames must be the **brel** boot form (`e_type=0xff00` / `ET_LOPROC`,
`unix.brel`) produced by `elf2brel` — **not** the raw ET_REL cross-link output `unix`.
See [Kernel must be brel, not ET_REL](#kernel-must-be-brel-not-et_rel) below; the tool
guards this so the trap cannot return silently.

## What the tool does

1. Copies the install kernel into `payload/unix-universal.brel` (gitignored; `payload/`
   is where the media builders read it). Stops with a clear message if the source is
   missing — it never builds a kernel itself. **Since P-15 I1 (2026-10-02) the kernel is
   the kerntools family K030-U-FD**, passed as
   `KERNEL_SRC=../amix-kerntools/work/k0-chains/K030-U-FD/K030-U-FD-c0-u6`; the default
   (`work/install-kernel-fd0unix/usr/sys/unix.brel`, `build-install-kernel.sh`'s output)
   is the pre-T-9 August line and is superseded.
1b. **Guards the brel invariant**: reads the copied kernel's ELF `e_type` (offset 16,
   big-endian u16) and **aborts if it is not `0xff00`**. Framing a raw ET_REL kernel
   boots to a D245 4C41 Guru during relocation (see below), so this refusal makes the
   whole class of bug impossible to reintroduce silently.
2. Hands the donor + kernel to the grimoire framer, which:
   - copies the donor's AmigaDOS bootblock + `compress`-era bootstrap **verbatim**
     (first ZOFF bytes);
   - `compress -b16`'s (LZW, 16-bit, block mode) the kernel into the `.Z` payload;
   - rewrites the `IBLK` boot descriptor's three fields (compressed length `+0x8`,
     decompressed size `+0xc`, folded 16-bit checksum `+0x10`) so the bootstrap reads
     *our* stream — a stale descriptor otherwise causes a "Kernel decompression overrun";
   - self-tests by decompressing the framed `.Z` and byte-comparing to the input kernel.
3. Reports the compressed `.Z` size against the floppy budget.

## Inputs

| Role | Path | Notes |
|------|------|-------|
| Kernel (brel) | `../amix-kerntools/work/k0-chains/K030-U-FD/K030-U-FD-c0-u6` (via `KERNEL_SRC`) | **K030-U-FD**: kerntools' floppy form of the K030-U family, post-T-9 sources, CD-06 cdfs — **brel** (`e_type=0xff00`), `fd0unix` config (`rootdev = FD0P = 0x00400008`), a3091 + a2091 (bounce fixes), **a4091**, **Gayle IDE** (registers only as the sole controller), **cdfs**, **`support.c` PATCHED** (the VPOSR-gated probe below). KT-37 cut (the sddevsize fix): sha256 `7fb1ed4f…`. **r6 (KT-55, kerntools a695553):** `../amix-kerntools/work/k0-chains/r6/K030-U-FD/K030-U-FD-c0-u6`, sha256 `a5be8b68…`, sum -r 03306, 1,267,121 B — + the ttcompat init fix and A4-24 (`a4091.o`), no RTH1 (the installer boots from floppy); framed boot floppy `ec6e8449…` (the r5 floppy `a46166c7…` is kept as `floppies/build/r5/`). **No z3660scsi.** E20c uses the slave-enabled twin K030-U-FD-S (`79084f84…`) on a floppy of its own (`floppies/build/amix_21_boot-universal-S.adf`). Never committed. **Not** the raw ET_REL (see D245 note). |
| Donor | `floppies/orig/amix_21_boot.adf` | Stock Amix 2.1 boot floppy (901,120 bytes). Bootblock + bootstrap reused verbatim. Proprietary — not committed. |
| Framer | `../grimoire-amix/tools/build-bootfloppy.sh` | Reverse-engineered layout/compression/IBLK/checksum tool; read/exec sibling. |

## Output

`floppies/build/amix_21_boot-universal.adf` (901,120 bytes = 880 KB DD floppy).
Gitignored build artifact — not committed.

## Measured size vs budget

| Quantity | Value |
|----------|-------|
| Kernel K030-U-FD `brel` (decompressed) | 1,266,585 bytes |
| Compressed `.Z` (`compress -b16`) | **735,353 bytes (718 KiB)** |
| Donor header (bootstrap, ZOFF) | 10,240 bytes (`0x2800`) |
| Available on floppy (880 KB − header) | 890,880 bytes |
| **Headroom** | **155,527 bytes (~151 KiB)** |

No stripping is needed (2026-10-02, P-15 I1; the August fd0unix kernel was 1,174,960 B /
671,233 B compressed). The brel kernel is smaller than its raw ET_REL because `elf2brel`
drops the symbol table the boot loader does not need.

## Self-check results (host round-trip)

```
kernel: brel confirmed (e_type=0xff00)
kernel: A3000-SCSI probe port SASR 0xDD0041 : 1 occurrence(s)
kernel: A3000-SCSI probe port SCMD 0xDD0043 : 1 occurrence(s)
donor bootblock+bootstrap: 0x0..0x2800 (10240 bytes)
kernel 1266585 bytes -> compress -b16 = 735353 bytes
IBLK @0x2600 (checksum-verified) patched: comp_len=735353 decomp=1266585 checksum=0x9bbb
self-test OK  IBLK @0x2600: comp_len=735353 decomp=1266585 checksum=0x9bbb (matches stream)
            stream decompresses to the IDENTICAL kernel; checksum will MATCH at boot (no warning).
```

Independently confirmed on the built ADF:
- first `0x2800` bytes identical to the donor **except** the 8 low bytes of the three
  `IBLK` fields at `0x2608..0x2613` (the deliberate patch) — bootblock + rest of the
  bootstrap verbatim;
- `.Z` magic `1f 9d` present at `0x2800`;
- `IBLK` `+0x8 = 735353`, `+0xc = 1266585`, `+0x10 low16 = 0x9bbb`;
- built ADF is exactly 901,120 bytes.

Host round-trip is GREEN, and a same-kernel `unix.brel` rebuild has booted in Amiberry to
the root-disk prompt — no D245 (the raw ET_REL kernel D245'd at relocation; see below).

## Kernel must be brel, not ET_REL

The framer must be handed the **brel** boot form of the kernel — `unix.brel`,
`e_type=0xff00` (`ET_LOPROC`), produced by `elf2brel` — **not** the raw ET_REL
(`e_type=0x1`) output of the cross-link.

Both files sit side by side in the kerntools cross-build tree
(`work/install-kernel-fd0unix/usr/sys/`): `unix` (raw ET_REL) and `unix.brel`
(the elf2brel boot format). The Amix bootstrap relocates the kernel in place at boot; only
the brel form carries the relocation layout the bootstrap expects. Framing the raw ET_REL
produces a floppy that boots to a **D245 4C41 Guru during relocation** (found 2026-07-05
under WinUAE: the raw-ET_REL floppy Guru'd; re-framing `unix.brel` booted cleanly to the
root-disk prompt with no D245).

To make that trap unreintroducible, step 1b of the tool reads the copied kernel's ELF
`e_type` (offset 16, big-endian u16) and aborts before framing if it is not `0xff00`:

```
STOP: refusing to frame a non-brel kernel (e_type=0x1); the boot floppy needs
      the elf2brel output unix.brel, else the kernel D245 4C41 Gurus at relocation.
      Run tools/build-install-kernel.sh, which emits unix.brel.
```

If `unix.brel` is missing entirely, the tool STOPs earlier (preflight) — it never builds a
kernel itself. Produce it with `tools/build-install-kernel.sh`, which runs the kerntools
cross-link, then `elf2brel`, and emits `unix.brel` next to `unix`.

## Step 1c: the A3000-SCSI probe gate

Step 1b keeps a *wrongly framed* kernel off the floppy; **step 1c keeps a *wrongly built*
one off it.** Stock `amiga/kernel/support.c` synthesizes the A3000's non-AutoConfig
internal SCSI only when the kernel's own BSS `end` lands above `0x07000000` — a RAM-size
guess that is true by accident at `a3000mem_size=16` and **false at the standing 64 MB
bench budget**, at which point the A3000 controller vanishes: the SCSI cards renumber (the
install CD answers cdfs `0,3`, not `1,3`) and the install target `c6d0` does not exist.
`../amix-a4091/src/kernel-patches/support.c.patch` replaces the guess with a VPOSR chipset
gate plus a WD33C93 write/readback probe through `0xDD0041`/`0xDD0043`. The tool scans the
**framed payload** for those two port addresses — they occur in the patched kernel and in
no stock one — and refuses to build a floppy without them, so "the installer cannot find
the target disk" can never again be discovered an hour into a bench run. See *The
A3000-SCSI synthesis gate* in `docs/installer.md`.

## Emulator config

The canonical **CD**-sourced acceptance rig — the one the `bench-a3000-a4091` profile and
the digest attestations use (and the E20 cell `fd-a3000`) — is
`configs/accept-bench-a3000-a4091.uae`: same floppy in DF0, but the A3000 onboard SCSI
**on** (so the CD answers at cdfs `1,3` and the target at `c6d0`), CD at `scsi3_a4091`,
target at `scsi6_a3000`. See *The tracked acceptance rig* in `docs/installer.md`.

*Historical:* `configs/install-blank-a4091.uae` is the original **tape**-sourced rig
(A3000 + A4091 id 7, KS 2.04, tape at `scsi4_a4091`, target at `scsi6_a4091`). Tape
sourcing works but is timeout-prone; it is no longer an acceptance path.
