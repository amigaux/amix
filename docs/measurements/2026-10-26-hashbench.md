# M-GEN2 follow-up — the hashing rate apart from I/O (bench, 2026-10-26)

- **Question:** M-GEN2 (`2026-10-26-m-gen2.md`) found the box kbootset
  hashing at about a third of the rate axtime measured for the same C
  (M-SIG2, M-LD7). Is it the compiler or kbootset's I/O?
- **Class:** bench, on the cycle-exact 25 MHz 68030 model (the M-GEN2 k30
  vehicle, 8 MiB of fast memory), plus host codegen inspection.
- **Tool:** `tools/measure/hashbench.c`, `make hashbench`: the loader's
  SHA-256 and CRC-32, and a `memcpy`, over 2 × 1 MiB in memory, timed with
  `times(2)`. Five builds from one source:
  - GCC 14 at `-O2` (kbootset's flags and objects), `-O1`, `-O3` and
    `-Os`;
  - gcc-cross-amix (GCC 2.7.2.3) with the loader's flags, the code axtime
    timed.
- **Recipe:** `tests/bench/README.md` "M-GEN2 follow-up".
- **Evidence:** the workspace's `tmp/2026-10-26-hashbench/run/N40/`

## 1. Run 1: the shifting round (sha256.c before this change)

KiB/s from user time; every build printed the host's SHA-256 and CRC-32.

| Build | SHA-256 | CRC-32 | memcpy |
|---|---|---|---|
| gcc-cross-amix, `-O2 -m68020` | **534** | 3 413 | equal across builds |
| GCC 14 `-O2` (kbootset) | **270** | 3 413 | |
| GCC 14 `-O3` | 252 | 3 413 | |
| GCC 14 `-O1` | 190 | 1 683 | |
| GCC 14 `-Os` | 135 | 3 413 | |

- The GCC 2.7.2.3 build matches axtime's 540 KiB/s.
- GCC 14 runs SHA-256 at half that, and no optimisation level recovers
  it. CRC-32 and the copy are the same under both compilers.
- **Verdict: the cause is GCC 14's code for the SHA-256 round, not
  kbootset's I/O.** The rest of M-GEN2's gap, 270 here against roughly
  170 there, is kbootset's own reads, copies and second hash pass.

**Why, from the code** (both compilers' assembly of `block()`):
- Both run about 102 instructions per round. The difference is not the
  count but which instructions they are.
- The round shifted the eight working variables
  (`hh = g, g = f, … , a = t1 + t2`), so most of them had to live in
  memory, and indexed the schedule circularly (`w[(i + n) & 15]`).
- The loop is longer than the 68030's 256-byte instruction cache under
  either compiler, so it is fetched from memory on every round.

## 2. The change

`loader/common/sha256.c` now:
- computes the whole 64-word schedule first;
- runs eight rounds per pass, with the working variables renamed in the
  macro's arguments instead of shifted;
- uses the cheaper Ch and Maj forms.

On the host, the new form matches Python's `hashlib` at the padding edges
(0, 1, 55, 56, 63, 64, 65 and 1000 bytes) and the hashbench pattern, and
the repository's host tests pass. Static count per round, from the
assembly:

| | instructions per round | stack references per round |
|---|---|---|
| before, GCC 2.7.2.3 / GCC 14 | 102 / 102 | 10 / 8 |
| after, GCC 2.7.2.3 / GCC 14 | 42 / 45 | 2.3 / 4.4 |

boot2 does not link `sha256.c`, so its size gate is untouched. The code
also serves kbootset, axtime, the host tools, and the kernel's module
checks of stage 3.

## 3. Run 2

Pending: the same cell with the rebuilt binaries. GCC 14 should reach
the GCC 2.7.2.3 rate or better, and GCC 2.7.2.3 should not lose. If GCC
14 stays well below, the fallback is to accept the factor. A `check` is
seconds on the slowest machine and runs once per kernel-space
transaction.
