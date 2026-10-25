# Stage 1 — the loader: work breakdown

- **Status:** plan, 2026-10-25 (S0 frozen at `2506516`)
- **Source:** `docs/spec/80-stages-and-proof.md` §2 stage 1, `docs/spec/90-measurements.md` stage-1 rows, `docs/spec/10-boot-loader.md`
- **Exit gate (80 §2):** today's static kernels boot from our loader exactly as from the stock loader (same root naming, same devices) on every controller of both reference machines; no stock loader on any 1.1 medium

Stage 1 boots **static kernels only**: a generation is a 1.0 kernel plus a
manifest, with no arena and no modules. The kernels need no change — they read
the RTH1 record our loader writes and ignore the new loader record — so the
040/060 port has no stage-1 item.

## 1. Conventions

- **ID** `S1-nn`, listed in dependency order; an item starts when everything
  in its "needs" column is done.
- **Owner repo** is the repository the work lands in. Metal rows run under the
  lab registry from the owning station; hardware is never assumed to be free.
- **Class:** `host` = unit tests or computation on the build machine (bench
  class in the spec's terms); `bench` = the emulator; `metal` = real hardware.
- **Estimate** in working sessions of one station.
- **CD** marks the items the CD mechanism fork (OQ-10.9) decides; they wait
  for the owner and nothing else waits on them.

## 2. Work breakdown

### 2.1 Toolchain, skeleton, formats (host only)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S1-01 | Toolchain pin: build against gcc-cross-amix (GCC 2.7.2.3, binutils 2.8.1, `m68k-cbm-sysv4`) through its `env.sh`; record the toolchain commit in `toolchain.pin`; `make toolchain-check` fails if the pinned tools are missing or report another version | amix-dlm | host | — | every cross build | 0.25 |
| S1-02 | Build skeleton: `Makefile`, `loader/{common,boot1,boot2}`, `tools/`, `tests/host/`; host builds with the system C compiler for unit tests, cross builds for the Amiga objects | amix-dlm | host | S1-01 | all code items | 0.5 |
| S1-03 | Store format (`AXS1` header, `AXT1` tally, `AXC1` control block, extents) and CRC-32 as one portable C89 header and module, shared by boot2, the host tools and `kbootset` | amix-dlm | host | S1-02 | S1-04, S1-05, S1-06, S1-08 | 0.5 |
| S1-04 | Manifest (`GMF1`) parser: record split, required keys, `!` critical keys, CRC line; unit tests including malformed input | amix-dlm | host | S1-03 | S1-08, S1-13 | 0.5 |
| S1-05 | boot1 size gate: the build assembles boot1, frames it as a bootblock (`DOS\0`, checksum, trailer), and **fails if the framed image exceeds 1024 bytes** | amix-dlm | host | S1-02, S1-03 | S1-12 | 0.25 |
| S1-06 | `mkstore`: host tool that builds a boot store from boot1, boot2, manifests and member files, and writes it into an image file at a partition offset (the seed of `kbootset --image`); `lsstore` reads one back | amix-dlm | host | S1-03, S1-04 | S1-16, S1-17, S1-18 | 1 |
| S1-07 | Inflate (raw deflate) decoder, C89, no allocation beyond a caller buffer; unit-tested against zlib output, including the two 1.0 floppy kernels | amix-dlm | host | S1-02 | S1-13 | 0.75 |
| S1-08 | Generation selection logic (default, try-once, one-shot, fallback order L2 of 10 §7.2) as a pure function over the control block; unit tests for every row of 10 §7 and §9 | amix-dlm | host | S1-03, S1-04 | S1-13 | 0.5 |
| S1-09 | Kernel relocators: ET_REL (R_68K_32, PC32/PC16/PC8, range-checked) and `brel` compact pairs; unit-tested against the existing reference outputs (`amix-kerntools/tools/relsim.py`, `elf2brel.py`) on real 1.0 kernels, read-only | amix-dlm | host | S1-02 | S1-13 | 1 |
| S1-10 | `bootinfo`, RTH1 and `AXL1` record builders; RTH1 checked byte for byte against `amix-040-060-port/tools/rth1-record.py` | amix-dlm | host | S1-02 | S1-13 | 0.5 |
| S1-11 | boot2 build tool: link at 0, append the R_68K_32 table, start-up stub that applies it; host test that the table round-trips | amix-dlm | host | S1-01, S1-02 | S1-13 | 0.75 |

### 2.2 The two programs (cross builds, then the emulator)

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S1-12 | boot1 in assembly: header pick, loader-trial tally, extent reads in 2048-byte units, CRC-32, jump; strap-return path | amix-dlm | host (assemble + gate) | S1-05 | S1-19 | 1 |
| S1-13 | boot2 core: CPU probe, console (graphics text + serial), store reader over the IOStdReq, selection (S1-08), manifest (S1-04), inflate (S1-07), relocation (S1-09), `bootinfo` (S1-10), hand-off for 68030 and 68040/68060 | amix-dlm | host (cross build) | S1-04, S1-07–S1-11 | S1-14, S1-19 | 3 |
| S1-14 | Menu and input: keyboard matrix, mouse buttons (first-release rule), serial input; rollback key, safe-mode toggle, development-load toggle; failure messages B1–B4, L1–L13 | amix-dlm | host (cross build) | S1-13 | S1-21 | 1.5 |
| S1-15 | Floppy multi-volume reads (volume prompt, change detection) | amix-dlm | host (cross build) | S1-13 | S1-24 | 0.5 |

### 2.3 Emulator prerequisites

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S1-16 | **M-EMU1**: the emulated Z3660 advertises DIAGVALID through the autoboot option and its boot ROM boots a Z3660 hard-file image (first with the stock chain, then with a store from S1-06) | amiberry | bench | S1-06 (second half only) | S1-20 Z3660 rows | 1 |
| S1-17 | Lifecycle cell: a row that keeps one vehicle image across boots, so a loader write is seen on the next boot (the 1.0 matrix re-copies the vehicle) | amix-kerntools (rig) | bench | S1-06 | S1-22 | 0.5 |
| S1-18 | Input injection and serial capture for loader rows: keyboard and mouse-button events over the emulator's control channel at a given time after reset; serial console log per row | amiberry + amix-kerntools (rig) | bench | — | S1-21 | 0.5 |
| S1-19 | Loader bench rows, existing controllers: A3000 WD, A4091 with its real ROM, Gayle IDE, DF0 floppy (030 and 040/060), each booting a 1.0 static kernel from a store | amix-kerntools (rig) | bench | S1-12, S1-13, S1-06 | S1-20, M-LD1, M-LD3, M-LD6 | 1 |

### 2.4 Measurements and proof rows

| ID | Item | Owner | Class | Needs | Blocks | Est. |
|---|---|---|---|---|---|---|
| S1-20 | **M-LD1** header fields the strap checks (floppy, RDB partition), **M-LD3** strap return, **M-LD6** CPU probe — bench half on S1-19 rows, Z3660 rows after S1-16 | amix-dlm | bench | S1-19, S1-16 | S1-25 | 1 |
| S1-21 | **M-LD5** menu input: injected over the control channel | amix-dlm | bench | S1-14, S1-18, S1-19 | S1-26 | 0.5 |
| S1-22 | **M-LD4** writes (control block, tally) with read-back on the next boot, per controller | amix-dlm | bench | S1-17, S1-19 | S1-26 | 0.5 |
| S1-23 | **M-LD7** CRC-32/SHA-256 time, **M-LD8** inflate time (ratio already measured) — emulator as an upper bound | amix-dlm | bench | S1-13 | S1-26 | 0.25 |
| S1-24 | **M-FP1** floppy-pair fit per line for static kernels; **M-NET1d** store overhead per DD volume | amix-dlm | host | S1-06, S1-15 | S1-27 | 0.25 |
| S1-25 | **M-LD9** bench half: every controller row boots the same static kernel through our loader and through the stock loader, compared (root naming, devices, RTH1 line) | amix-dlm | bench | S1-20 | S1-26 | 0.5 |
| S1-26 | **Metal**: M-LD1/M-LD3/M-LD4 Z3660-ROM halves, M-LD5 HID half, M-LD6 on a real 68060, M-LD7 on a 68060, M-LD9 cold boots from every controller on both machines | amix-dlm (via the lab registry) | metal | S1-21–S1-25 | stage exit | 2 |
| S1-27 | **Metal**: M-FD1 floppy DMA under 040/060 caches, M-FP2 floppy-pair boot on both lines | amix-dlm (via the lab registry) | metal | S1-24, S1-15 | stage exit | 1 |
| S1-28 | If the Z3660 boot ROM refuses the loader's writes (S1-22/S1-26): a firmware change for CMD_WRITE through the boot ROM's device | Z3660 | bench + metal | S1-26 finding | S1-26 | contingent |

### 2.5 Items that wait for the CD fork (OQ-10.9)

| ID | Item | Owner | Class | Needs | Est. |
|---|---|---|---|---|---|
| S1-C1 **CD** | Option A: RDB-style CD image layout (2048-byte RDB, store partition, package partition) and its builder | amix-installng (layout) + amix-dlm (store) | host | owner decision | 1 |
| S1-C2 **CD** | Option B: `amix-cdboot`, boot2 as an AmigaDOS executable with a dos.library file front end, and the ISO with `S/Startup-Sequence` | amix-dlm (program) + amix-installng (ISO) | host | owner decision, S1-13 | 1.5 |
| S1-C3 **CD** | **M-LD2a** or **M-LD2b** (whichever option is kept) on the A4091 ROM in the emulator, then the A4092 on metal | amix-dlm | bench + metal | S1-C1 or S1-C2 | 1 |

Nothing in §2.1–§2.4 depends on the CD items.

## 3. Critical path and totals

`S1-01 → S1-02 → S1-03 → S1-04 → S1-08 → S1-13 → S1-14 → S1-21 → S1-26`,
with S1-07, S1-09, S1-10, S1-11 feeding S1-13 in parallel. The first item
outside amix-dlm on the path is **S1-19** (rig rows, amix-kerntools), and
**S1-16** (amiberry) gates every Z3660 bench row. Both can be dispatched as
soon as S1-06 exists.

Estimate: amix-dlm host and cross items about 12 sessions; emulator
prerequisites about 3 (other repos); measurements and proof rows about 7;
CD items about 3.5 after the owner's decision.

## 4. Not in stage 1

The module arena and its filler (stage 3); `marc_root`, the loader record's
use by the kernel, the root selector and RAM-disk root (stage 4); the
lifecycle commands of `kbootset` beyond writing a store image (stage 2).
