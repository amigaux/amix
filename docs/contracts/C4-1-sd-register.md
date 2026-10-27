# C4-1 — `sd_register` and the four-card contract, version 5

- **Status:** agreed 2026-10-26 (orchestrator), version 1; version 2
  (2026-10-26, from the generic 060 target, S4-57): an A3000 with a
  third-party 68060 runs the 040/060 line with an A3000 WD, so the WD
  behind the Zorro boards is an accepted rename on both lines (§4.3, §6);
  version 3 (2026-10-27, from amix-cdfs's module plan): the level at which
  a controller calls a command's completion (§3.2); version 4 (2026-10-27,
  S5-08, from M-S474b; agreed 2026-10-27 by the port and amix-kerntools):
  the Z3660 is one controller in either mode (§5.1); version 5
  (2026-10-27, S5-44, from Bench J4 row M-G3): the device nodes an
  installed root holds, and who makes them (§2.4).
  Other repositories build against this text; a change from here is a
  contract change with a version bump.
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

### 2.4 The device nodes (version 5)

On an installed root whose installed kernel is a four-card one (its
sidecar says `sdcards=4`, C2-3 §2), `/dev/dsk` and `/dev/rdsk` hold:
- `c<N>d0s<S>` for every N from `0` to `1f` and every slice 0–7: all
  four cards, all eight units, 512 nodes. `/dev/dsk` nodes are block
  device 18, `/dev/rdsk` nodes character device 40, the minor as §2.1
  gives it (`c16d0s0` is 134, `c1fd0s7` is 255). The card-0 and card-1
  nodes are core's, as core lays them. The card-2 and card-3 nodes have
  mode 0600, owner root, group root;
- no `c<N>d1s<S>` node. Core's 256 d1 names have minors with bit 7 set,
  which a four-card kernel reads as the card's high bit: `c6d1s0` would
  open the disk `c16d0s0` names.

The set depends on the kernel only, never on the board set: every card a
four-card kernel can number has its nodes, so adding or removing a
board never needs a node change, whichever card numbers it moves. A
fifth card is refused (§7), so the set never grows. The package database
says the same: the card-2 and card-3 nodes are registered to core, and
core no longer names the d1 nodes, so `pkgchk core` stays quiet.

The pristine generation's 1992 kernel reads bit 7 as the LUN, so under
it `c10`–`c1f` open LUN 1 of cards 0 and 1, as the removed d1 names did.
A root that holds only two-card kernels keeps core's stock set.

**Who makes them** (the `/dev/kinfo` pattern, C2-3 §1):
- **`kbootset nodes`** (C2-4 §14) is the one implementation. On the
  running box it makes every node of the set that is missing or wrong,
  removes the d1 nodes, and registers both changes in core with APKG's
  `removef` and `installf`. Under `-R` it makes and removes the nodes and
  leaves the registration to a run on the booted box.
- **`kbootset commit`** runs it on the running box after every commit,
  including one with nothing to commit. A root that already exists
  reaches a four-card kernel only through a kernel-space transaction,
  after which apkg runs `build` and `commit` (C2-4 §3). So the set is
  there before the first boot of that kernel, and installing the
  kbootset that carries this step (`kbootset` -22) fixes a root like
  J4's on its own.
- **The installer** calls `kbootset nodes` on the booted target in
  firstboot. It runs where firstboot's step 4d now runs its own loop, and
  it replaces that loop. Until the installed set carries `kbootset` -22,
  step 4d stays as it is. The install miniroot keeps its own nodes, made
  on demand for the target's card (`ensure_disk_nodes`).
- **`kbootset check`** counts an incomplete set as one problem:
  `nodes: N of the four-card set missing or wrong, M d1 nodes left: run
  kbootset nodes`.

No package lists nodes per board: card numbers follow the board set
(§4), so a node list per driver package would be wrong whenever the set
changes.

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

### 3.2 The completion's level

A controller module calls a command's completion, `cp->intr(cp)`, at
level 4 or below: from its polled path, its deferred call or a level-2
handler, never from a level-6 handler (C3-6 §1.3: a level-6 handler calls
no DDI function). The completion may then `wakeup`, as a filesystem's
`sdqueue` caller does (amix-cdfs) and the stock `gsioctl` does.

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
the Z3660 and the Zorro boards. On the 040/060 line that is an A3000
with a third-party 68060 and a Zorro SCSI board: 1.0 made its WD card 0,
and the class order makes the board card 0 and the WD card 1, so the
WD's disks are renamed (`c6d0` becomes `ced0`). D-3 §11 accepted this
rename on both lines; it is expectation 2 of §6.

## 5. The board set and the card table

- `kinfo`'s sd card table (C2-1, version 3) already has four entries:
  card number, controller id (C2-1 §2.1), base and the motherboard flag.
  sd fills it after registration closes.
- The manifest's `boards` record (10 §5.1) keeps the board set the
  generation was composed for. When the booted set differs, the loader
  prints it and `kbootset check` warns that device names may have moved.
  Nothing new is recorded.

### 5.1 The Z3660 is one controller in either mode (version 4)

The Z3660 is found two ways. In its 68060 mode, and under amiberry, its
extended ROM AutoConfigs it as `zorro:144b:01`. In its 68030 mode it is
not an AutoConfig board, and z3660scsi finds it through the registry
probe `mobo:z3660-window` at the fixed window `0x10000000` (20 §6). One
box, one disk and one Z3660 are booted in both modes (the A4000T,
M-S474a and M-S474b). M-S474b's card was `zorro:0000:00` at
`0x10000000`, so a root record composed as `id=144b0100` matched no card,
and RTH1 fell back to the built-in `c6d0s1`: the right disk by chance,
the wrong one beside a second sd card. So:

1. **kinfo** reports a card that sd took from a registration at the
   window's base as motherboard id 4 (`z3660-window`, C2-1 §2.1) with the
   motherboard flag, never id 0. On k30 `kinfo030.c` keys it on the
   card's base: an unmatched card at `0x10000000` is `MOBO_Z3660WIN` (id 4)
   as `KC_MOBO`, whatever name sd holds. On k46 kinfo already names a card
   with no AutoConfig board by its controller's name; `Z3660 SCSI`, the
   name both the static row and z3660scsi register, gives id 4.
2. **The canonical identity is `144b0100`, base 0.** `kbootset` composes
   a root or swap record on any Z3660 card, whether id `144b0100` or id 4,
   as `sd id=144b0100 base=00000000 …`, the form boot2 already records
   for the Z3660 boot vehicle (`st_identify`). A medium composed under
   amiberry then roots the same box in 030 mode.
3. **RTH1 matches either.** For a root or swap record with
   `id=144b0100`, the kernel half (`src/rth1.c`, one source for both
   lines) takes a card as the Z3660 when the AutoConfig board at its base
   is `144b0100`, or when its base is the window's `0x10000000`; the
   record's base is not compared. Exactly one card may answer: two (an
   AutoConfig row and the window, in a mode that showed both) make the
   hint fall back to the built-in root rather than guess. Every other id
   matches as before.
4. **The gates** (`kbootset`): the canonical record's key is
   `zorro:144b:01`, which z3660scsi's `match=` lists, so gate 3 and the
   safe set (C4-4 §2) see one controller in both modes.

Implemented by S5-15: item 1 in `kinfo` (amix-kerntools `kinfo030.c`,
the port's k46 `kinfo`), item 3 in the RTH1 kernel half (the port, both
lines' sources), item 2 and item 4 in `kbootset` (amix-dlm). The metal
row is S5-16: the A4000T in 030 mode with a second sd card, rooted by the
record.

## 6. The card-number gate

M-SD1 (S4-72) judges every board set of record (30 §5.3) against one of
three expectations:
1. **order unchanged from 1.0:** every disk has its 1.0 name;
2. **accepted changes** (on k30, A3000 onboard + Zorro SCSI, and Gayle IDE
   + Zorro SCSI; on k46, A3000 onboard + Zorro SCSI): exactly the new names
   listed per set in the measurement record and the release notes;
3. **three and four controllers, and sets with a controller 1.0 did not
   drive** (the A4000T 53C710): the names this contract gives.

## 7. Not in this contract

- How a controller probes its board (C3-6, C4-2).
- The root selector (C4-3): it uses §2.1's minor for an sd root.
- A fifth card: refused, as a third is today.
