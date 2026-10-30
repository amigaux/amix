# The driver contract — how to write a driver `kernel/k30` can build

This is the contract for **driver authors**. If your repo follows it, `amix-build` discovers your
driver, generates the kernel wiring, applies your patches, and links it into an Amiga UNIX (Amix
2.1) kernel alongside the other drivers — with no edits to the hub (`kernel/k30`).

Amix is Commodore's port of AT&T SVR4.0 to the 68030 Amiga. The kernel is built **on the Amix box**
with its native `cc`/`ld`/`make` against the `/usr/sys` source tree. The hub never ships Amix; it
patches the builder's own stock files. Your driver must do the same.

## What you ship vs. what kernel/k30 generates

A driver repo ships **only**:

- `driver.conf` — your one-line-per-driver identity (grammar below).
- `src/` — your own MIT driver source (`*.c` / `*.h`). For a net driver, all of `src/` is pushed.
- `kernel-patches/*.patch` — the substantive edits to **shared** stock kernel files that your
  driver needs, as unified diffs (paths relative to `/usr/sys`, applying to a stock Amix 2.1 tree
  with `patch`). One patch per stock file. Ship only edits that kernel/k30 cannot generate.
- `LICENSE` (MIT) and a `README.md`.

A driver repo **never** ships:

- `amiga/alien/sd.c` or the alien `Makefile` — **generated** by the hub from every selected
  `driver.conf`.
- Any full Amix source file. A `kernel-patches/*.patch` is a *diff*; the context lines it quotes
  from a stock file remain under their original Commodore/AT&T SVR4 copyright, and your repo's MIT
  license covers only the added/changed lines. Add a short `NOTICE` in `kernel-patches/` saying so.

## The patch manifest — `kernel/k30/kernel-patches.conf`

Every `src/kernel-patches/*.patch` of the driver dirs a build is given is applied to the stock tree
before the clean-gate. [`kernel/k30/kernel-patches.conf`](../kernel-patches.conf) (parsed by
`kernel/k30/tools/kpatch-lib.sh`) records, per patch, what the builders need beyond the diff:

```
kpatch <driver-repo> <patch-rel-to-repo> <onbox-target> <marker> <stock> [exp=<path>]
```

- `<driver-repo>` names the owning driver; it matches a driver dir when the basenames agree after
  stripping a leading `amix-` (`amix-a4091` matches `kernel/drivers/a4091`). A row applies only
  when that driver is part of the build. `always:<repo>` applies to every build and then requires
  the driver to be present (a build dir, else under `kernel/drivers/`); `k30` is kernel/k30's own.
- `<marker>` is a fixed token present in the target if and only if the patch is applied (the
  on-box idempotency guard); `<stock>` is the pristine file the patch applies to, normally
  `usr/sys/<onbox-target>` in the `AMIX_SYSTEM` input (amigaux/amix-system).

A driver adding or revising a patch under `src/kernel-patches/` asks kernel/k30 for the matching
row. The file's header comment is the full reference.

## `driver.conf` grammar

One driver per line; `#` starts a comment. Two dialects.

### SCSI driver

```
<product-number>  <queue-func>  "<hardware name>"  <source under src/>  [probe=<fn>]
```

- `<product-number>` — the AutoConfig product ID (manufacturer<<16 | product), e.g. `0x02020054`.
- `<queue-func>` — your driver's SCSI queuing function. The hub emits an `extern` for it and a
  `scsicard[]` row pointing at it.
- `"<hardware name>"` — shown by `sdhardwarename()`.
- `<source>` — the `.c` under `src/` that defines `<queue-func>`. Its `.o` goes into the alien
  `Makefile` `OBJ` list.
- `probe=<fn>` *(optional)* — a direct-probe fallback your driver exports, called by `sd.c`'s
  `init()` when the bootinfo autocon table misses the board (fixed-base boards, or the unreliable
  2.1 table on real metal). The probe must verify its own hardware safely.

From these the hub generates, in `sd.c`: the `extern <queue-func>()` declarations, the `scsicard[]`
rows (`{ pn, &queue-func, "name" }`), the `@DRIVER_PROBES@` fallback calls, and in the alien
`Makefile` the `OBJ` entries.

### Net driver

```
net  <subdir>  <src>  <streamtab-symbol>  <cdevsw-major>  <iface>  "<description>"
```

- `<subdir>` — on-box driver subtree: `/usr/sys/amiga/driver/<subdir>/`.
- `<src>` — main source file (all `*.c`/`*.h` in `src/` are pushed).
- `<streamtab-symbol>` — the `struct streamtab` placed in `cdevsw[<major>].d_str`.
- `<cdevsw-major>` — the `cdevsw[]` slot to claim (verified free at build).
- `<iface>` — the `slink`/`ifconfig` interface name.

A net driver is **not** a `scsicard[]` row. It is wired into `master.d/kernel.c`'s `cdevsw[]` by the
driver's own idempotent `tools/patch-*.sh` (adds the `streamtab` extern + claims the major). Keep
that script idempotent (detect "already patched" and exit 0) — the hub may re-run it.

## Dedup — many IDs, one object

A `driver.conf` may map several product IDs to the **same** queue function and source. That yields
several `scsicard[]` rows but exactly **one** object in `OBJ` — the hub de-duplicates. Example
(A4091 plus its 53C710-compatible siblings, all one driver):

```
0x02020054  a4091queue  "A4091 SCSI"  a4091-wr.c
0xc0de0001  a4091queue  "A4092 SCSI"  a4091-wr.c
0xc0de0002  a4091queue  "A4770 SCSI"  a4091-wr.c
```

To drive several such boards **at once** (each at a different base) a driver maps each board's
register window from its per-card AutoConfig base — see `sdcardbase()` in the ABI below.

## The kernel-symbol ABI

A SCSI driver may call **only** these symbols exported by the kernel / generated `sd.c`:

| symbol | purpose |
|---|---|
| `autocon` | walk the AutoConfig table for a product ID |
| `sptalloc` | allocate kernel-mapped DMA-able memory |
| `bcopy` | block copy |
| `printf` | kernel printf |
| `timeout` | schedule a callback |
| `sdcardbase(card)` | the per-card physical AutoConfig base recorded for this card, so one queue function can drive several boards routed to it |

Needing a symbol outside this set is a **kernel/k30 change**, not something a driver patches in
unilaterally — open it against the hub so the ABI stays a known surface.

## Canonical repo shape

### SCSI driver repo

```
driver.conf                     # <pn> <queue-func> "<name>" <src> [probe=<fn>]  (one+ lines)
src/<driver>.c                  # your MIT driver; defines <queue-func> (+ probe fn)
src/kernel-patches/<file>.patch # diffs vs stock /usr/sys files you must change
src/kernel-patches/NOTICE       # "diffs only, not Amix source" note
LICENSE                         # MIT
README.md
```

### Net driver repo

```
driver.conf                     # net <subdir> <src> <streamtab> <major> <iface> "<desc>"
src/<driver>.c, .h              # your MIT STREAMS/DLPI driver (all of src/ is pushed)
src/Makefile                    # builds the driver in amiga/driver/<subdir>/
tools/patch-kernel.sh           # idempotent: wires streamtab into master.d/kernel.c cdevsw[]
tools/patch-makefile.sh         # idempotent: adds the driver subtree to the kernel Makefile
LICENSE                         # MIT
README.md
```

(The hub reads `kernel-patches/*.patch` under `src/kernel-patches/`.)

## Checklist for a buildable driver

- [ ] `driver.conf` present, one valid line per driver, correct dialect.
- [ ] `<source>` exists under `src/` and defines the named `<queue-func>` (SCSI) / driver (net).
- [ ] Every shared stock-file edit is a unified diff in `kernel-patches/`, paths relative to
      `/usr/sys`, applying cleanly to stock Amix 2.1. No full Amix files committed.
- [ ] No `sd.c` / alien `Makefile` in the repo (the hub generates them).
- [ ] SCSI: driver calls only the ABI symbols above. Net: `patch-*.sh` scripts are idempotent.
- [ ] `LICENSE` (MIT) present; a `NOTICE` in `kernel-patches/` if you quote stock context lines.
