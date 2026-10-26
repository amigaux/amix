# C4-1 — `sd_register` and the four-card contract, version 1

- **Status:** agreed 2026-10-26 (orchestrator), version 1. Other
  repositories build against this text; a change from here is a contract
  change with a version bump.
- **Implements:** `docs/spec/30-module-core.md` §5.2–§5.3 (four cards, the
  compacted order, registration, the card-number gate), D-3 §4 and §11;
  core patch 8 (30 §2)
- **Written by:**
  - amix-dlm: `sd_register` in the core (S4-03), the registry's rank
    classes, `kbootset`'s readers;
  - amix-040-060-port: the k46 sd and dd in-place patch and the RTH1
    kernel half (S4-21);
  - amix-kerntools: `templates/sd.c.in`, the k30 dd and ct sources and
    `kinfo030.c` (S4-21).
- **Read by:** the root-class disk controller modules (amix-z3660scsi,
  amix-a4091 with its A4000T 53C710 target, amix-gayle-ide), `kinfo`
  (C2-1's card table), amix-installng and every tool that names a disk.

## 1. Today, the shape this keeps

The stock sd layer (`amiga/alien/sd.c`, `sd.h`; on k30
`amix-kerntools/templates/sd.c.in`, on k46 a binary in the base) routes
every disk request to one controller per card:
- a controller table of AutoConfig product numbers and queue functions;
- `init()`, run by sd's first open, walks it, asks `autocon(pn, n, …)`
  for the n-th board of each product and calls `insert(f, n, base, name)`;
- `insert()` keeps `SDCARDS` (2) slots sorted by `base`, ascending, and
  prints `sd: too many controllers` for a third;
- `sdqueue(cp)` calls `queue[cp->card].f(queue[cp->card].c, cp)`, where
  `c` is the board's index among boards of its product;
- `sdcardbase(card)` and `sdhardwarename(card)` read the slot back.

The Gayle IDE is no AutoConfig board. Today it enters through a glue
that answers an invented product id with a sort key in place of the base
(`amix-040-060-port/src/ide_sd_glue040.s`, key 0xfffffff0 on k46; the
task-file base 0xDD2020 on k30). This contract replaces that glue.

The queue function, `c`, `sdcardbase` and `sdhardwarename` keep their
meaning. What changes is the number of slots, how a controller gets into
one, and the sort.

## 2. Four cards

`SDCARDS` is 4 on both lines.

### 2.1 The minor number

| Bits | Field |
|---|---|
| 0–2 | unit (the SCSI id or IDE drive) |
| 3 | card, low bit |
| 4–6 | slice |
| 7 | card, high bit |

```
sdcard(dev)  = ((dev) >> 3 & 1) | ((dev) >> 6 & 2)
minor(card, unit, slice) = (card & 1) << 3 | (card >> 1) << 7 | slice << 4 | unit
```

Cards 0 and 1 keep today's minor numbers exactly: bit 7 is zero for them.

### 2.2 Names

A disk is `c<N>d<lun>s<slice>` with N = card × 8 + unit, in lowercase
hexadecimal and without leading zeros, as today:
- cards 0–1: `c0`–`cf`, unchanged;
- cards 2–3: `c10`–`c1f` (two digits).

The device nodes are `/dev/dsk/c<N>d0s<slice>` and `/dev/rdsk/…`. A tool
that names, parses or builds a disk name:
- takes N as one or two **hexadecimal** digits; a decimal `c%d` is wrong
  from card 1 on (card 1 unit 6 is `ce`, not `c14`);
- takes the card from the minor with §2.1's formula, never as
  `minor & 0x0F` or `minor >> 3`;
- forms a name from `kinfo`'s card table (C2-1) as `c%x` of 8 × card + unit.

That includes `updbootpart`, the installer, the first-boot dialog, the
`/etc/devnm` readers, `kbootset`, and the RTH1 kernel half's `bo_name`
rewrite, which today writes one character. The sites are enumerated per
repository (the port station's map, 2026-10-26: amix-040-060-port,
amix-kerntools, amix-installng, amix-a4091, amix-dlm), and each is fixed
in its own repository in the same wave as S4-21.

The stock dd prints `c%d` of 8 × card + unit in **decimal** in its console
messages. That is a stock wart, not a name any tool reads; the stock
bytes keep it.

### 2.3 What is rebuilt for four cards

Everything indexed by the sd card:
- sd: the slot table, four entries; `sdopen`'s bound `card < 4`;
- dd: `ddtab[SDCARDS][SDUNITS]`, and every `sdcard()` decode;
- ct (tape): `cttab`, every `sdcard()` of a dev, and the decode of a
  table index (`dp - cttab[0]`), which becomes `(index >> 3) & 3`;
- `sdcardbase()`'s bound;
- `kinfo`'s card-table loop (C2-1 already has room for four);
- the RTH1 kernel half: four cards, the root minor by §2.1's formula,
  and a `bo_name` with a one- or two-digit card;
- every driver array indexed by `cp->card` (the A4091 driver has seven,
  sized 2: S4-31 sizes them 4 or bounds them).

`sdcom.card` stays the card number, 0–3, never a minor-shaped code: sd
and the drivers index tables with it.

Not changed: `sdpart`'s `partab[0x100]` (indexed by the whole minor, so
bit 7 is already in it); the `card[]` and `info[]` arrays of a2091 and
a2090, which are indexed by the board's ordinal among boards of its
product, not by the sd card (they limit two boards of one product, not
four cards); `scsi.o`.

On k30 they come from source (`sd.c.in`, the stock `dd.c` and `ct.c` in
the relink kit, `kinfo030.c`). On k46 sd, dd and ct are patched in place
by the port, now (Q4-3), as a merge request: relocations retargeted to
four-row tables, the bounds raised, the inline decodes replaced by calls
of the same length. The static families stay byte-identical.

## 3. `sd_register`

```c
int sd_register(bool (*queuefn)(), uint c, char *base, char *name, uint rank);
```

| Argument | Meaning |
|---|---|
| `queuefn` | the controller's queue function, called as `queuefn(c, cp)` (§1) |
| `c` | the board's index among the boards this module drives, handed back to `queuefn` |
| `base` | the board's base address as the kernel maps it, returned by `sdcardbase()`; for a motherboard controller its register base |
| `name` | the hardware name `sdhardwarename()` returns; the module's storage, kept for the kernel's life |
| `rank` | the rank class, §4 |

Returns 0, or:

| Error | When | Console line |
|---|---|---|
| `EBUSY` | sd's first open has closed registration (§3.1) | `sd: %s registered after the controllers closed` |
| `EINVAL` | `rank` is not 1–4, or differs from the calling module's `.moddata` `rank` (§4.1); `queuefn` or `name` is 0 | `sd: %s: bad rank or entry` |
| `ENOSPC` | four controllers are already registered by modules | `sd: too many controllers` |

`sd_register` is a DDI v1 name (C3-2), in the root-class context of
C3-6 v4 §1.3: level 7, the clock stopped, no sleep. It allocates nothing:
the pending table has `SDCARDS` entries in the core's `.data`.

### 3.1 When registration is open

Registration is open from `marc_root` until sd's first open, which
`rth1_apply` forces (30 §3). Every root-class controller registers from
its `_load` inside `marc_root`, once per board it found.

At sd's first open, `init()`:
1. walks its controller table as today, giving each board the rank
   class of its row (§4.2);
2. adds the pending module registrations;
3. sorts all of them by (rank class, base), ascending;
4. keeps the first four, and prints `sd: too many controllers` once
   for each controller it drops, naming it:
   `sd: too many controllers, %s dropped`;
5. closes registration.

A root-class controller is never unloaded (`unload=never`), so there is
no `sd_unregister`. A module whose `_load` fails after `sd_register` has
returned 0 is the one case the core undoes: it removes that module's
pending entries before the failure is reported (C3-6 v3, `_unload` on a
failed load).

## 4. The order

One rule on both lines (D-3 §11), by rank class, then by base within a
class, compacted over the controllers present:

| Class | `rank` | Controllers |
|---|---|---|
| 1 | `z3660` | Z3660 SCSI (piscsi) |
| 2 | `zorro` | Zorro SCSI boards: A4091, A4092, A2091, A2090 |
| 3 | `mobo` | the motherboard SCSI controller: the A3000 WD33C93 or the A4000T 53C710 |
| 4 | `ide` | Gayle IDE |

A box with one controller always has it as card 0, so the stock
single-controller names (`c6d0` for SCSI id 6) are kept. Adding a
higher-ranked controller moves the names of the lower-ranked ones; the
root is found by identity regardless (30 §3, §5.2).

### 4.1 The `.moddata` `rank` key

A root-class disk controller carries `rank=<class name>` (C3-1 §3), one of
`z3660`, `zorro`, `mobo`, `ide`. The core reads it before `_load`, and
`sd_register` refuses (`EINVAL`) a `rank` argument that is not the class
the calling module declared. A module that drives controllers of two
classes declares the one it registers; the A4000T 53C710 target of
amix-a4091 is a separate module object with `rank=mobo`.

The registry (20 §6) lists the four classes and their numbers. The
numbers are this contract's; they never appear in a file.

### 4.2 The table rows' classes

sd's own table (the floor's controllers, and while they are still static,
the controllers the module kernels link in) is ranked by product:

| Row | Class |
|---|---|
| A3000 Internal SCSI (the stock table's 0x0202F003) | 3 `mobo` |
| A2090 (0x02020001), A2091 (0x02020003) | 2 `zorro` |
| Z3660 SCSI (144b:01), static | 1 `z3660` |
| A4091 (0202:54), A4092 (c0de:01), static | 2 `zorro` |
| Gayle IDE (the glue's row), static | 4 `ide`, sorted by its task-file base 0xDD2020 |

The IDE glue's sort key (0xfffffff0) gives way to the class: from S4-21
no address is used as a rank.

### 4.3 Against 1.0

1.0 sorted by base address alone:
- the Z3660 and the Zorro III boards sat above the motherboard
  controllers;
- an A3000 WD that answered (on k46, a kernel bound above 0x07000000)
  was card 0, and the Z3660 card 1;
- a third controller was dropped.

The common sets keep their 1.0 names, because there the address order
and the class order agree: Z3660 alone, and Z3660 + A4091/A4092. Where
1.0 put a motherboard controller first, the class order moves it behind
the Z3660 and the Zorro boards. That case is not a set of record: a
Z3660 sits only in an A4000's CPU slot, and no A4000 has an A3000 WD.

## 5. The board set and the card table

- `kinfo`'s sd card table (C2-1, version 3) already has four entries:
  card number, controller id (C2-1 §2.1), base and the motherboard flag.
  sd fills it after registration closes.
- The manifest's `boards` record (10 §5.1) keeps the board set the
  generation was composed for. When the booted set differs, the loader
  prints it and `kbootset check` warns that device names may have moved.
  Nothing new is recorded.

## 6. The card-number gate

M-SD1 (S4-72) judges every board set of record (30 §5.3) against one of
three expectations:
1. **order unchanged from 1.0:** every disk has its 1.0 name;
2. **accepted changes** (on k30, A3000 onboard + Zorro SCSI, and Gayle IDE
   + Zorro SCSI): exactly the new names listed per set in the measurement
   record and the release notes;
3. **three and four controllers:** the names this contract gives.

## 7. Not in this contract

- How a controller probes its board (C3-6, C4-2).
- The root selector (C4-3): it uses §2.1's minor for an sd root.
- A fifth card: refused, as a third is today.
