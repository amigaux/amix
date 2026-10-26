# Bench and metal rows: inputs and expected results

This directory holds the inputs for loader rows that run on the emulator
or on real machines, not on the build host. Each script builds the
vehicles and writes the expected outcome next to them. The rows run on
the project's emulator rig, which holds the slots, lifecycle cells, input
schedules and serial capture (see `amix-kerntools/docs/rig-slots.md` §5).
Evidence classes and IDs: `docs/spec/90-measurements.md`. Work items:
`docs/plan/stage-1.md`.

| Script | Rows | Item |
|---|---|---|
| `m-ld1.sh` | bootblock variants on DF0 and on disks (M-LD1, which header fields the strap checks) | S1-20 |
| `ld-rows.sh` | W1–W3 (M-LD4, control-block and tally writes); vehicle M (M-LD5, menu input) | S1-22, S1-21 |
| `m-ld9.py` | our loader against the stock loader, same kernel and root (M-LD9 bench half) | S1-25 |
| `df0-pair.sh` | the DF0 floppy pair per line (M-FD1, M-FP2) | S1-27 |
| `../../tools/measure/m-ld7.sh` | axtime runs (M-LD7, M-LD8) | S1-23 |

## M-LD1: which bootblock fields the strap checks (S1-20)

`m-ld1.sh <workspace> <outdir>` writes seven bootblocks: the good one, and
six that each differ in one field (`bbframe -x`). The changed fields are
the magic (`DOS\1`, `UNI\0` or `BAD\0`), the checksum, the third longword
and the trailer. It also writes one floppy per line and per bootblock (the
good floppy with only its first 1024 bytes replaced). For disks it prints
the `dd` line that writes a bootblock over the boot slice of a slot copy
of a proven vehicle. Run one boot per variant on DF0 and on each disk
controller, with Kickstart 3.1 and 3.2.x. Each row ends in one word:

- **ACCEPTED**: the serial log shows `amix-boot 1:`. boot1 never checks
  its own framing, so a bootblock the strap runs boots like the good one.
- **REFUSED**: no `amix-boot 1:` line. The frame shows what Kickstart did
  instead.

`<outdir>/EXPECTED` repeats this with the offsets.

## M-LD9: our loader against the stock loader (S1-25)

`m-ld9.py OURS STOCK` compares two rig evidence directories. OURS is a
loader row; STOCK is the row with the same machine shape, kernel and root
booted by the stock loader. It checks:

- both rows passed;
- every loader stage passed;
- each batch command both rows ran gives the same output, with the parts
  that change from boot to boot removed (`mount` dates, `df` free counts);
- the RTH1 unit on the serial log is the controller number of the root
  device both rows mounted.

It prints SAME or DIFFERENT (exit status 0 or 1). It does not judge a
batch command that only one row ran, so give both rows the same batch:
at least `mount`, `uname -a`, `sum -r /stand/unix`, `swap -l` and `df`.

Pairs from the rig matrix:

| Loader row | Stock row |
|---|---|
| N19 | E1 |
| N20 | E12u |
| N21 | N6 |
| N22 | N9u |
| N23 | a stock Z3660 autoboot row (to be named) |
| N25 | E1's floppy boot of K030-U-FD |
| N26 | E29 |

N24 has no root (the 030 line has no Z3660 driver) and ends at the kernel
banner, so there is nothing to compare. Tried on the S1-19 evidence, N21
against N6 gives SAME. N20 against N6 gives DIFFERENT, because the kernels'
uname build tags differ; that is the wrong pair, and the check catches it.

## M-LD4: writes, read back on the next boot (S1-22)

`ld-rows.sh` rewrites the store of a proven loader vehicle (rows N19–N26)
for each row. Run each row as a **lifecycle cell of 2 boots** with serial
capture, on each disk controller of the bench half: A3000 WD, A4091 with
its ROM, Gayle IDE. The Z3660 boot ROM half is metal.

| Row | Store | Boot 1 | Boot 2 |
|---|---|---|---|
| W1 try-once | gen 1 good (default), gen 2 trial | attempt recorded, gen 2 boots | `L8 … (generation 2)`, gen 2 marked bad, gen 1 boots |
| W2 one-shot | gens 1 and 2 good, default 2, request: gen 1 | request cleared, gen 1 boots | gen 2 boots |
| W3 loader trial | primary boot2 on trial, same boot2 as the secondary | boot1 records the start in the tally, `boot1 choice 0` | `boot1 choice 201` and `B4 new loader already started once, previous loader used` |

`<row>.expected` lists the serial lines per boot and the store as it must
be read after the cell. The serial lines are those `axsim` prints, using the
loader's own selection rules. The store state is `lsstore <slot image>
<offset>`, which must match the `#` block at its end: the control
block's sequence number, the states and attempts, the one-shot request and
the tally. That read-back is the M-LD4 result. A 1.0 kernel never marks
anything good, so each row's second boot is the one that shows the first
boot's write.

## M-LD5: menu input (S1-21)

Vehicle `M.hdf`: generations 1 and 2, both good, default 2, menu window
60 s (`-m 600`). With nothing pressed, generation 2 boots after 60 s. One
schedule per row, played from reset. `T` is the time from reset to the
`amix-boot 1:` line on the serial log, known from the N19–N26 runs on the
same controller. Every first event below is at 25 s, which must lie
between `T` and `T + 60`: move it if `T` is longer. Keys are typed with
the rig's US keymap.

| Row | Schedule (after `0 reset hard`) | Expected on the serial log |
|---|---|---|
| M1 digit + Return | `25 type x`, `27 type 1`, `29 tap return` | the menu (`>2  generation 2  good  (default)`), redrawn with `>1  generation 1`, then `amix-boot: generation 1, kernel` |
| M2 rollback key | `25 type p` | no menu; `amix-boot: generation 1, kernel` |
| M3 mouse | `25 mouse L`, `27 mouse -`, `28 mouse L`, `28.5 mouse -`, `30 mouse L`, `33 mouse -` | the menu; one redraw with `>1  generation 1` (click = next entry); `amix-boot: generation 1, kernel` once the 2 s hold ends |
| M4 toggles | `25 type x`, `27 type s`, `28 type d`, `30 tap return` | redraws with `safe mode: on`, then `development load: on`; `amix-boot: generation 2, kernel`, then `amix-boot: DEVELOPMENT LOAD: modules outside the manifest allowed this boot` and `amix-boot: safe mode` |
| M5 r key | `25 type x`, `27 type r`, `29 tap return` | `amix-boot: returning to Kickstart would only reset the machine; reset by hand`; then generation 2 boots |
| M6 serial input | `x`, `1` and CR sent to the serial port at 25, 27 and 29 s | as M1 |

The key that opens the menu (`x` here) only opens it, and the hold that opens it never
selects: mouse actions count only after the first release (10 §7.4). M6
needs the rig to *send* bytes on the serial port. Serial capture alone
cannot do it, so until the rig can send, M6 stays open.

## Metal (S1-26, S1-27)

Metal rows run the same images as their bench rows (80 §1). The scripts
here fix `SOURCE_DATE_EPOCH`, so a vehicle rebuilt from the same inputs
has the same bytes. Rebuild every vehicle once after a boot2 change and
run both the bench and the metal rows from that set. boot2 prints
`no fast memory: the loader runs from chip memory` only on a chip-only
machine. The lines to judge by are those of the bench rows.

| Row | Vehicle | On metal | Judged by |
|---|---|---|---|
| M-LD1, the Z3660 boot ROM | `m-ld1.sh`: each `bb-<variant>.img` written over the boot slice of the card's store | one cold boot per variant | ACCEPTED (`amix-boot 1:` on the serial console) or REFUSED, as on the bench |
| M-LD3, the Z3660 ROM and both boxes | `m-ld1.sh`: `fd-<line>-b2bad.adf`, or a disk store with each boot2 copy damaged (EXPECTED) | one cold boot | `amix-boot1: B3 no valid boot2` on the serial console, and boot1 stops rather than returning |
| M-LD4, the Z3660 ROM and both boxes | `ld-rows.sh` W1–W3 on the box's boot disk or card | two power cycles per row; a real 68060 is power-cycled, never reset | `<row>.expected`: the serial lines per boot, then `lsstore` of the store read back on the host |
| M-LD5, the HID half | `ld-rows.sh` vehicle M | the M1–M5 keys and mouse through the box's own keyboard and mouse converters | the serial lines of `README` M1–M5 |
| M-LD6, a real 68060 | any vehicle | every cold boot | `amix-boot 1: 68060 (AttnFlags …)`; AttnFlags printed beside the probe, including without SetPatch |
| M-LD7, M-LD8 on a 68060 | `tools/measure/m-ld7.sh` | `axtime` and `axtime-chip` under AmigaOS on the 68060 | the EXPECTED digests; the timings go into the record |
| M-LD9, cold boots | the controller's loader vehicle and its stock-loader image | a cold boot of each, from every controller of each box | `m-ld9.py OURS STOCK` → SAME |
| M-FD1, M-FP2 (S1-27) | `df0-pair.sh` | below | below |

## The DF0 pair (S1-27, metal)

`df0-pair.sh <workspace> <outdir>` builds one pair per line with the 1.0
floppy kernel stored uncompressed, so the kernel runs on from volume 1
into volume 2. Boot from DF0 with volume 1. At `amix-boot: L11 insert boot
volume 2 of 2` insert volume 2 (a wrong disk is refused first). After
`amix-boot: starting the kernel` the kernel roots on `fd0` as in 1.0, so
DF0 then takes the 1.0 root floppy of that line. A stage-1 loader refuses
RAM-disk generations, so the RAM-disk profile (M-FP1) boots only from
stage 4 on.

## Stage 2: the lifecycle rows (S2-41, S2-42, S2-46) and M-GEN2

**`commit --again` in these rows** (C2-4 v7, kbootset from 1.1.0.261025-7
on). These rows build a generation from the same packages as the
default, so it equals the default, and a plain `commit` writes nothing
("the default generation M already has these members; nothing to
commit"). `--again` writes it all the same: a row needs the generation.
An older kbootset rejects `--again` as a usage error (status 2), so a row
on kbootset -6 or earlier uses a plain `commit`.

The rows run the box kbootset (`make box`, copied to the box as
`/tmp/kbootset` until the kbootset package exists) on a kinfo kernel's row
under our loader (the port's E5 shape, KD060-Z). One rig lifecycle cell
spans the boots of a row. The rig runs `kbootset mark-good` after its
login, standing in for the end of run level 2 until the rc hook is
installed. Until the kernel packages exist, `s2-standin.sh` gives a kernel
package and its apkg record. The row copies the tree onto the box's root,
then:

```
sh tests/bench/s2-standin.sh <KD060-Z kernel> k46 zorro:144b:01 ufs,s5 68060-261025-50 <outdir>
```

### S2-41 — M-GEN5: upgrade, mark-good, rollback, one-shot, try-once

| Boot | Before power-cycling | Expected on the serial log / from kbootset |
|---|---|---|
| 1 | `kbootset build; kbootset commit --again` | `generation 2 committed; power-cycle to boot it` |
| 2 | `kbootset mark-good` | `amix-boot: generation 2, kernel …`; then `generation 2 is good and the default` |
| 3 | `kbootset rollback` | boots 2; then `the default is generation 1 (was 2)` |
| 4 | `kbootset next previous` | boots 1; then `the next boot only is changed` |
| 5 | `kbootset mark-bad 2; kbootset commit --spec bad.spec` (below) | boots 2, once, the one-shot; then `marked bad and collected`, then `generation 3 committed …` |
| 6 | — | boots 3, the trial. It cannot mount its root (`PANIC: vfs_mountroot: cannot mount root`), so it never reaches mark-good. The kernel reboots by itself after the panic, and in the same boot: `amix-boot: L8 trial generation did not reach multi-user (generation 3)`, then generation 1 boots to login. The rig's login watch waits longer here |
| 7 | `kbootset status` | generation 1 boots; status shows default 1, no trial, 3 as bad with 1 attempt (or already collected) |

`bad.spec` names the line's own installed kernel, with a root on a SCSI
unit where the vehicle has no disk. The kernel boots, cannot mount its
root and panics, a true mountroot failure, on either line. It uses the
line's kernel and sidecar `bss=`, with unit 5 (the vehicles carry their
disk at unit 6 only):

```
line k46                                      line k30
rootfs ufs                                    rootfs ufs
root sd id=144b0100 unit=5 slice=1            root sd id=00000000 base=00000000 unit=5 slice=1 mobo
kernel unix /stand/k46/unix bss=<its bss>     kernel unix /stand/k30/unix bss=<its bss>
```

`bss=` is the one in `/stand/k<line>/kabi`. The record's controller id
is the vehicle's root controller: the Z3660 `144b0100` on k46, the A3000
WD (`mobo`) on k30.

`commit --spec` runs no gates and writes the root line as given. That is
the point here: it is how a row gets a trial that panics before rc.

Do not use another kernel family for the trial. A family whose sd layer
keeps the stock rows still drives the vehicle's controller and mounts
root: K030-IDE does on the A3000 (row N43). A 1.0 kernel has no `kinfo`
either, so its "fallback" comes from `mark-good` refusing, not from the
root.

The first k46 run (row N36, `2026-10-26-m-gen5.md`) used KD060-A, whose
A4091 root controller the Z3660 vehicle lacks. That works on k46, but
the unit-5 spec is the recipe from now on.

**Why mark-bad on boot 5.** The vehicle's 4 MiB store holds two raw k46
generations. At boot 5 both are in the kept set: generation 1 is good
(the vehicle's spec made it good, not pristine) and the default, and
generation 2 is one of the two newest good ones. So `kbootset collect`
frees nothing, and the third generation does not fit (gate 5).
`mark-bad 2` is allowed, because 2 is not the default; it collects 2 and
frees its extents for generation 3. That also exercises `mark-bad`.

The installer's 1.1-layout disks (64 MiB stores) hold the whole row
without it.

### S2-42 — M-GEN3: a power cut at each commit step

These rows run on the rig's cut (`rig-run --cut-at`, amix-kerntools
`docs/rig-slots.md` §5), with the stand-in kernel package; the commit
path is kbootset's own, so the rows need no apkg.
- Vehicle: the kinfo row's (the KD060-Z kernel, generation 1 good, a
  4 MiB store), with `/tmp/kbootset` from `make box`.
- The stand-in tree from `s2-standin.sh`, made from that same KD060-Z
  kernel, copied onto the root. That way generation 2 boots when its
  commit completes.
- Five rows, N = 1, 2, 4, 5, 7. Each is a lifecycle cell of two boots on a
  fresh slot copy:

```
--boots 2 --cut-boot 1 --cut-at 'kbootset: holding before step N'
--extra '/tmp/kbootset build > /dev/term/ser 2>&1; (KBOOTSET_HOLD=N /tmp/kbootset commit --again > /dev/term/ser 2>&1 &)'
boot 2 batch: /tmp/kbootset status > /dev/term/ser 2>&1
--post-cell 'lsstore "$RIG_FIRST" <slice offset>'
```

| N | Cut before | Boot 1 serial: the step markers up to N, then the hold | Boot 2: the loader boots | Boot 2: `kbootset status`, first line | lsstore after the cell |
|---|---|---|---|---|---|
| 1 | the journal | `generation 2 built …`; step 1; `holding before step 1` | `amix-boot: generation 1, kernel …` | the store listing (no journal message) | `ok`; generation 1 only |
| 2 | the members | steps 1, 2; `holding before step 2` | generation 1 | `kbootset: the commit of generation 2 was interrupted before its commit point; nothing of it remains` | `ok`; generation 1 only |
| 4 | the manifest | steps 1, 2, 4; `holding before step 4` | generation 1 | as N = 2 | `ok`; generation 1 only |
| 5 | the control block | steps 1, 2, 4, 5; `holding before step 5` | generation 1 | as N = 2 | `ok`; generation 1 only |
| 7 | clearing the journal | steps 1, 2, 4, 5, 7; `holding before step 7` | `amix-boot: generation 2, kernel …` (the trial, its attempt recorded) | `kbootset: the commit of generation 2 had completed when it was interrupted` | `ok`; generation 1 good, generation 2 trial with 1 attempt |

- Every row must boot (M-GEN3; 80's "every power-cut point leaves a
  booting generation").
- After the journal message, kbootset has cleared the journal: a second
  `status` shows no message.
- **With the rc2 hook** (the installer's disks from v7, C2-4 §9), the
  first kbootset run of boot 2 is the hook's `mark-good`, at the end of
  run level 2. It reports and clears the journal, and its output goes to
  the console, not the serial log. So the row's own `status` shows no
  journal message: read the journal line from the console frames, or
  judge the row by the boot and the store state.
- kbootset creates `/var/kbootset` itself when the system has none.

### S2-46 — the exit row: upgrade and roll back with apkg alone

The packages are amix-packages' S2-12 set: `kbootset`, `loader-amix` and
`kernel-k46-z`, catalogued by `gen-catalog`, with the kernel-space block.
The kernel sidecar must carry `bss=` (C2-3 v4) and the kbootset package
must be built from amix-dlm 1230e8b or later. Vehicle: the kinfo row's.
The box has apkg 0.3 and `/dev/kinfo` (kbootset makes it if missing), its
catalog source reachable, and no `/etc/default/bootset` (auto is the
default).

| Boot | Commands | Expected |
|---|---|---|
| 1 | `apkg update; apkg install kbootset loader-amix kernel-k46-z` | apkg installs the three. `/var/apkg/kpkg/` gets records for loader-amix and kernel-k46-z, named by pkginst; kbootset has none. The trigger runs `/sbin/kbootset build` and `commit`, and apkg ends with `apkg: generation 2 committed; power-cycle to boot it` |
| 2 | `kbootset mark-good` | `amix-boot: generation 2, kernel unix 1459584 bytes`; then `generation 2 is good and the default` |
| 3 | `kbootset rollback` | boots 2; then `the default is generation 1 (was 2)` |
| 4 | `kbootset status` | `amix-boot: generation 1, kernel …`; status shows default 1, and 2 still good |

The row passes when:
- the box was upgraded by apkg alone, with no file placed by hand;
- `kbootset check` reports 0 problems after boot 2;
- the rollback brings generation 1 back.

That is stage 2's exit gate (80 §2) on the bench.

### The k30 line: S2-46, S2-41 and one S2-42 cell

The same rows on the 030 line, with the real kernel package
`kernel-k30-u` (pkginst `kern30u`). Its kernel is K030-U with `kinfo`,
build id `68030-261026-01`, a brel of 1 270 676 bytes,
`bss=344916`.

**Vehicle: the installer's l11-k30 disk**, rig row N19's shape (A3000,
the disk as WD unit 6), with its 64 MiB store, `/dev/kinfo` and the
`retry` line in `bcheckrc`. The disk must be minted with `kernel-k30-u`
as its pristine kernel. The v6 disk, with the stand-in `kernel-k030u`
(the 1.0 r7 kernel), does not serve, for two reasons:
- generation 1 then has no `kinfo`, so on its boots `mark-good` refuses
  and `status` cannot say which generation booted;
- `kernel-k030u`'s record and `kernel-k30-u`'s would both name
  `/stand/k30/unix`, and gate 1 refuses a path named twice.

The facts come from `kinfo`, so no command takes options. No stand-in
package is needed: `kbootset build` composes from the installed
`kernel-k30-u`.

**S2-46 on k30.** On the installer's v10 disk. Three things make that
disk the one:
- its record for the installed kernel is named by its pkginst
  (`kern30u`, C2-2 v4);
- it carries APKG 0.3.0. The 1.0 media's APKG 0.2.3 cannot read
  kernel-space entries;
- kbootset and the loader are installed as packages, not as bare files.
  On v9, `apkg upgrade` rightly refused: "loader-amix is not
  installed".

The catalog serves `kbootset`, `loader-amix` and `kernel-k30-u` at
revisions above the installed ones (amix-packages mints them; the kernel
bytes may be the same). Then the S2-46 table above applies with:
- **on boot 1, one call:** `apkg update; apkg upgrade kernel-k30-u
  loader-amix kbootset`.
  - apkg 0.3 makes one transaction of an `upgrade` with several names,
    with one trigger, so the row's new generation is 2.
  - `apkg install` of a package already installed at an older revision
    refuses without `-f`.
  - Each kernel-space transaction triggers its own build and commit, a
    loader-only one included. Separate calls therefore spend a commit
    and a generation number each: in the renamed-record variant (N45)
    the loader's call committed generation 2 and the kernel's generation
    3, and generation 2 never booted.
- apkg reports `loader-amix` -2 and `kbootset` -6 as up to date, and
  upgrades the kernel -1 → -2, in that one transaction;
- the kernel's record replaced by the upgrade, not doubled;
- `amix-boot: generation 2, kernel unix 1270676 bytes` on boot 2;
- `amix-boot: generation 1, kernel unix 1270676 bytes` on boot 4.

**From kbootset -7 on** (C2-4 v7), an upgrade to a kernel with the same
bytes changes nothing the default holds. The trigger then answers
`apkg: the default generation 1 already has these members; nothing to
commit`, and no generation 2 is made. That is the right answer for apkg.
A re-run of this row on kbootset -7 needs a `kernel-k30-u` whose bytes
differ from the installed one, a rebuild with a new build id, say. The
row of record (N45) ran on kbootset -6.

**The variant for a 1.1 disk installed before the packages existed**
(kbootset and the loader as bare files, as on v8 and v9) is
`apkg -f install kbootset loader-amix kernel-k30-u`. It is also one
transaction ("kernel space: 2 packages"), with `-f` as the Bench ran
it over the bare files. The Bench's v8a and v9f runs
passed the whole row this way. It is supporting evidence, not the row of
record.

**S2-41 on k30.** The S2-41 table above applies with:
- boot 1: `kbootset build; kbootset commit --again`;
- the kernel lines: `kernel unix 1270676 bytes` for every generation,
  the trial included (it is the same kernel);
- boot 5: the 64 MiB store has room, so `mark-bad 2` is not needed for
  space. Keep it, because it exercises `mark-bad`. Then
  `kbootset commit --spec bad.spec` with the k30 column above
  (`bss=344916`).
- **Boot 6:** `amix-boot: generation 3, kernel unix 1270676 bytes`, then
  `PANIC: vfs_mountroot: cannot mount root: errno <n>` (k46 gave 89; the
  030 value is the row's to record).
- **If the kernel reboots by itself,** as k46 did, the L8 line and
  generation 1 follow in the same boot. If it stops, power-cycle, and L8
  shows on boot 7.
- **Either way the end state:** default 1, generation 3 bad with 1
  attempt. Generation 2 is gone, because `mark-bad 2` collected it.

**One S2-42 cell on k30 (N = 7).** As the S2-42 table above, on the
l11-k30 disk, with `build` composing from the installed package (no
stand-in). Boot 2:
- the loader boots generation 2 (the trial, `kernel unix 1270676
  bytes`);
- if the root fsck reboots, `retry` gives the attempt back, and the
  trial boots again (M-GEN3 §4);
- at the end of run level 2 the hook's `mark-good` marks it good.
  "had completed" is printed then, on the console (see "With the rc2
  hook" above).

### M-GEN2 — `kbootset commit` time, bench upper bound

M-GEN2 times one `kbootset commit` after a `kbootset build`, three times
per line, without rebooting. The commit does all of its work whether the
generation came from a build or from `--spec`: it writes the members,
computes their SHA-256 for the manifest, reads every write back, and
flips the control block (40 §3.2). The time is taken inside the guest with
`/usr/bin/time`: its resolution is the clock tick, and a commit takes
seconds. On the cycle-exact model the guest clock runs on the model's
time, not the host's. (axtime's E-clock is an AmigaDOS tool, so it cannot
time a program under Amix.)

| Line | Model | Vehicle | kbootset | Kernel package |
|---|---|---|---|---|
| k30 | the cycle-exact 25 MHz 68030 with a 68882 (M-LD7's model) | the A4091 68030 vehicle of M-LD1, under our loader | `/tmp/kbootset` from `make box` | `s2-standin.sh <its K030 kernel> k30 zorro:0202:54 ufs,s5 <its build id> <outdir> <its bss>` now (`bss-of.sh` gives the bss; `uname -m` dumps core on the 1.0 K030 kernels, so the build id is `uname -a`'s last field); the k30 kernel package once it exists |
| k46 | the 68060 model | the kinfo row's (KD060-Z, a 4 MiB store) | `/sbin/kbootset` from the package, or `/tmp/kbootset` | the S2-46 set, or the stand-in made from the same KD060-Z kernel |

A 2 MiB boot slice holds the k30 trial only beside a deflated generation 1.
The 1.0 K030 kernels have no `kinfo` until S2-11, so the k30 build names
the box facts instead: `--line 30 --bootdev zorro:0202:54 --rootdev
zorro:0202:54 --rootfs ufs --mem <the model's fast memory>`. kbootset
finds the store by its scan of the disks (C2-4 §2). The k46 build needs no
options.

One boot on a fresh slot copy, as the cell's batch. `KB` is the kbootset
above and `F` the k30 facts, empty on k46. The vehicle holds generation 1
only, so the three new ones are 2, 3 and 4 (the box's `/bin/sh` has no
arithmetic, hence the list):

```
$KB status > /dev/term/ser 2>&1
for g in 2 3 4; do
  $KB build $F > /dev/term/ser 2>&1
  /usr/bin/time $KB commit --again > /dev/term/ser 2>&1
  $KB mark-bad $g > /dev/term/ser 2>&1
done
/usr/bin/time $KB check > /dev/term/ser 2>&1
ls -l /stand/k*/unix > /dev/term/ser 2>&1
```

- `mark-bad` takes the new trial, never booted, back out ("marked bad and
  collected"), so the next commit has room in a 4 MiB store. It is
  allowed because the trial is not the default. Checked on a host image:
  a 2 MB generation 1 and three 1.4 MB passes.
- Each pass prints `generation N built`, the step markers 1, 2, 4, 5, 7,
  `generation N committed`, and `time`'s `real`, `user` and `sys` lines.
- `check` is timed too. That is a second reader of the same bytes, and
  M-SIG2 predicts its SHA-256 part.

The record gives per line:
- the kernel's size;
- `real`, `user` and `sys` of each of the three commits, and their median;
- the check's time.

**What the figures bound.**
- The k30 figure is an upper bound for the CPU: no supported machine is
  slower than the 25 MHz 68030.
- It is not a bound for the disk. The emulated disk answers faster than a
  real SCSI disk, and a commit writes the kernel once and reads it back
  once (about 2.6 MB of transfer for a k30 kernel).
- The 68060 model runs at the emulator's speed, so its figure is for the
  record only, as M-SIG2's was.
- The disk-inclusive figures, and the 68060 figure, are metal (S2-47).

### M-GEN2 follow-up — the hashing rate apart from I/O (hashbench)

M-GEN2 found the box kbootset hashing at about a third of axtime's rate
(`docs/measurements/2026-10-26-m-gen2.md`). `tools/measure/hashbench.c`
times the loader's own SHA-256 and CRC-32, and a `memcpy`, over a fixed
buffer in memory, with `times(2)`. `make hashbench` builds it five times
from the one source:

| Binary | Compiler and flags | What it stands for |
|---|---|---|
| `build/box/hashbench` | GCC 14, `-O2`, the box kbootset's flags and objects | kbootset as shipped |
| `build/hb14-O1/hashbench`, `hb14-O3`, `hb14-Os` | GCC 14 at the other levels | whether the level is the remedy |
| `build/hb27/hashbench` | gcc-cross-amix, the loader's flags (`-O2 -m68020 -fno-builtin -fomit-frame-pointer`), dynamically linked | the code axtime timed |

One boot on the M-GEN2 k30 vehicle: the A4091 68030 vehicle on the
cycle-exact 25 MHz 68030 model, 8 MiB of fast memory. Copy the five to
`/tmp`, then:

```
for b in g14 g14-O1 g14-O3 g14-Os gcc27; do
  echo "== $b" > /dev/term/ser; /tmp/hashbench.$b 1024 2 > /dev/term/ser 2>&1
done
```

Each prints three timing lines and
`hashbench: sha256 d20eb937c9f60f43f57e926c16d86929e34ea273c23ad296e6c9b66a3b4fb7c7 crc32 fff55677 over 2 x 1024 KiB`.
The host build prints exactly that too
(`cc -Iloader/common tools/measure/hashbench.c loader/common/{sha256,crc32}.c`).
A different line means a wrong build, not a slow one.

**Reading it.**
- The reference is axtime on the same model: SHA-256 540 KiB/s, CRC-32
  and copy 3.4 MiB/s (M-LD7).
- If `gcc27` gives about 540 and `g14` about 170, the compiler is the
  cause. The best GCC 14 level is then the remedy, or a change to the
  source of `sha256.c`'s round.
- If both give about 540, the cost is in kbootset's I/O and copies, and
  the next step is timing its commit by phase.
- The 68060 model runs at emulator speed, so a run there is for the
  record only.

## Stage 3: the module kernel's boot rows (S3-20, S3-21)

The acceptance rows of `docs/plan/stage-3-kernel-brief.md` §4. Each line's
module kernel boots a generation with an `arena` and an `ident` record and
no modules: under loader version 2, the core finds the arena that boot2
filled. Three controls show the other loaders do no harm: under loader
version 1 or the stock loader, the system boots and modules are refused.

**Inputs**, all from amix-dlm 124b86c or later (the kbootset sidecar v5
read, loader version 2):
- `/tmp/kbootset` (`make box`);
- `/tmp/boot2.bin`: `build/boot2.bin` (`make boot2`), loader version 2,
  28 100 bytes at 124b86c;
- the stand-in tree. `s3-standin.sh` takes the module kernel as shipped
  and the sidecar its build wrote. The fourth argument is the vehicle's
  root record, copied from its generation 1 manifest (`lsstore`):

```
sh tests/bench/s3-standin.sh <unix> <kabi> <outdir> "<root record>"
RECNAME=kern30u sh tests/bench/s3-standin.sh …    # the k30 installer disk
```

On a vehicle that already has a kernel record for the line (the k30
disk's `kern30u`), `RECNAME` gives the stand-in that record's name, so the
copied tree replaces it. Otherwise gate 1 refuses: `/stand/k30/kabi is
named by two apkg records`.

| Line | Kernel | Vehicle |
|---|---|---|
| k46 | KD060-Z module kernel, ET_REL, 2 426 952 bytes, build `68060-261026-51` | the kinfo row's (the port's E5 shape, KD060-Z): generation 1 good and **deflated** (the vehicle built with `--deflate`), a 4 MiB store, loader version 1 |
| k30 | K030-U module kernel, brel, 1 712 168 bytes, `bss=349320`, build `68030-261026-01` | the installer's l11-k30 disk (rig row N19's shape: A3000, WD unit 6), its 64 MiB store, loader version 1 |

A 4 MiB store holds the module generation only beside a deflated
generation 1. A raw KD060-Z generation 1 (1 998 273 bytes) and the
2 426 952-byte module kernel do not fit (gate 5: `needs 2428928, 2127872
free`); the host rehearsal had used a smaller stand-in generation 1. It
holds no third generation. Each row starts from a fresh slot copy, and
every box command runs `/tmp/kbootset`, or `/sbin/kbootset` where the
Bench installs it so that the rc2 hook and `bcheckrc` run the same binary.

**The rc2 hook marks good first** on disks that carry it (the installer's
from v7): its `generation N is good and the default` goes to the
console, and is the line of record. A manual `kbootset mark-good` after
it prints `generation N is good; nothing to mark`.

The kernel prints the arena line first, then `dlm: 80 kernel symbols` on
k46 and `dlm: 78 kernel symbols` on k30. These are the names of
`abi/<line>/ddi.list` (`core.list` is empty in stage 3).

To read kinfo, `kbootset status` shows the booted generation and build.
The kabi and the module count are read directly:

```
dd if=/dev/kinfo bs=1 skip=24 count=24 2>/dev/null; echo     # kabi: k46.1.0 / k30.1.0
dd if=/dev/kinfo bs=4 skip=134 count=1 2>/dev/null | od -x    # modules at 536: 0000 0000
dd if=/dev/kinfo bs=4 skip=144 count=1 2>/dev/null | od -x    # kinfo version 3 (the -58 cut on): at 576
```

### S3-B1 — loader version 2, the module generation (three boots)

| Boot | Commands | Expected |
|---|---|---|
| 1 | copy the tree; `kbootset loader-install /tmp/boot2.bin --version 2` | `loader version 2 installed on trial; power-cycle to boot it` |
| 2 | `kbootset mark-good`; `kbootset build`; `kbootset commit` | `amix-boot 2: 680x0 …`; generation 1 boots. Then `generation 1 is good; nothing to mark; the new loader is accepted` (`pristine` on the k30 disk); `generation 2 built …`; `generation 2 committed; power-cycle to boot it` |
| 3 | `kbootset mark-good`; `kbootset status`; the two `dd` reads | `amix-boot 2:`, `amix-boot: generation 2, kernel unix 2426952 bytes` (k30: `1712168`), `amix-boot: starting the kernel`. On the console: `dlm: modules from generation 2's manifest`, then `dlm: 80 kernel symbols` (k30: 78). Then multi-user as the static family. `generation 2 is good and the default`; `booted: generation 2, by the primary loader; kernel 68060-261026-51` (k30: `68030-261026-01`); kabi `k46.1.0` (k30: `k30.1.0`); module count 0 |

On the 4 MiB store, `kbootset status` after boot 3 also warns
`a generation the size of the default does not fit (976896 bytes free):
kbootset collect`. That is right: the store holds no third generation.

The loader must be accepted before build. While the new loader is on
trial, gate 7 also counts the secondary boot2, which is version 1. The
gate refuses until then.

### S3-B2 — loader version 1 refuses the generation (L9)

| Boot | Commands | Expected |
|---|---|---|
| 1 | copy the tree; `kbootset build`; `kbootset commit --spec <outdir>/l9.spec` | build: `gate 7 (loader): the installed loader is version 1, the kernel needs 2: run kbootset loader-install first`, exit status 4; then `generation 2 committed …` (`--spec` runs no gates) |
| 2 | `kbootset status` | `amix-boot 1: …`; `amix-boot: L9 generation needs a newer loader (generation 2)`; then `amix-boot: generation 1, kernel …` in the same boot. Status: generation 2 `trial`, 1 attempt: the attempt is spent before boot2 reads the generation (10 §7.2), and the L9 line is the reason of record |
| 3 | — | `amix-boot: L8 trial generation did not reach multi-user (generation 2)`, generation 2 marked bad, generation 1 boots (10 §7.2) |

### S3-B3 — loader version 1, the core finds no arena

| Boot | Commands | Expected |
|---|---|---|
| 1 | copy the tree; `kbootset commit --spec <outdir>/noarena.spec` | `generation 2 committed …` |
| 2 | `kbootset mark-good`; the two `dd` reads | `amix-boot 1:`, `amix-boot: generation 2, kernel unix …`. On the console: `dlm: no valid arena directory; modules are refused this boot`, then `dlm: 80 kernel symbols` (k30: 78). Then multi-user. `generation 2 is good and the default` (the hook's line); kabi `k46.1.0` / `k30.1.0`; module count 0 |

`noarena.spec` is the same kernel as a version-1 generation: no `arena`,
no `ident`, `loader-min 1`. Loader version 2 boots it the same way, so
S3-B3 also holds after S3-B1.

### S3-B4 — the stock loader

The line's stock-loader row, with the module kernel as the kernel it
loads: on k46, a stock-loader row of the kinfo kernel's shape; on k30,
E1. Expected on the console:
`dlm: no valid arena directory; modules are refused this boot`, then
`dlm: 80 kernel symbols` (k30: 78), then multi-user. The kinfo reads as
above (kabi, 0 modules). The stock media carry no boot store, so
`kbootset status` stops at gate 8; instead, kinfo has no loader record:

```
dd if=/dev/kinfo bs=1 skip=84 count=4 2>/dev/null | od -c     # not "A X L 1"
```

### S3-B5 — the first module: z3660eth from the generation (S3-16)

The first composed module generation. The module kernel boots with
z3660eth as a boot-class member, and the network comes from the module.
z3660eth goes alone: z3660rtg's `depend=monsw` needs a monsw member, and
no monsw module exists yet (S3-27).

- **Inputs:**
  - the kernels of the cut with kinfo version 3 (C2-1): KD060-Z -58
    (`8459eaee…`, 2 431 362 bytes) and the K030-U cut that ships
    `unix.sym` (C2-3 version 6), each through `s3-standin.sh`; on k30
    the stand-in tree also carries `/stand/k30/unix.sym`, and the sidecar
    its `sym=` line;
  - `/tmp/kbootset` from amix-dlm cf49440 or later (`make box`): kbootset
    -12, with `kbootset namelist` (C2-4 §12);
  - core patch 0022 or later in the kernels: a boot-class STREAMS driver
    registers its own major (the first run's `error 22`);
  - the module the z3660net station built with the kit of the cut
    (`build/<line>/mod.d/z3660eth`, z3660net be0ef63 on kit e84878e):
    k30 `0c5c3580…`, k46 `8356712a…`, 18 787 bytes; the earlier build
    against the dirty kit gave the same bytes. Its stand-in package:

```
sh tests/bench/s3-modpkg.sh <z3660eth> k46 <outdir>          # or k30
```

- **Vehicle:** a fresh slot copy, as S3-B1's. On the 4 MiB k46 store the
  module kernel's generation fits only once: so S3-B5 composes the module
  generation as the first one after generation 1, in place of S3-B1's
  generation 2. On the k30 disk's 64 MiB store it can follow S3-B1.

| Boot | Commands | Expected |
|---|---|---|
| 1 | copy both trees (s3-standin's and s3-modpkg's); install `build/box/modadmin` (amix-dlm with core patch 0017 or later) as `/sbin/modadmin`, and put `dlm::sysinit:/sbin/modadmin -B </dev/console >/dev/console 2>&1` in `/etc/inittab` before every other `sysinit` line; install `/tmp/kbootset` as `/sbin/kbootset` and `/etc/rc2.d/S01kbnamelist` (its one line, C2-4 §12); `ls -li /stand/unix /stand/2.1_unix`; `kbootset loader-install /tmp/boot2.bin --version 2` | the two names one inode (the stock kernel, as 1.0 left it); `loader version 2 installed on trial; power-cycle to boot it` |
| 2 | `kbootset mark-good` (or the hook's); `kbootset build`; `kbootset commit` | the loader accepted, as S3-B1. Early in run level 2, from `S01kbnamelist`: `kbootset: no namelist: kinfo version 2 gives no bind address` (generation 1 is the vehicle's static kernel, whose kinfo is version 2). `build`'s generation has, after the kernel's record, `module z3660eth boot <size> path=/stand/gen/<id>/mod/z3660eth sha256=… match=zorro:144b:01,mobo:z3660-window`, `param z3660eth.intr=0` and `param z3660eth.intrl2=1` (in `/stand/gen/<id>/build`); `generation <id> committed` |
| 3 | `kbootset status`; `ls -li /stand/unix /stand/2.1_unix`; `netstat -i`; `ifconfig -a`; `ifconfig zen0` (or the vehicle's network check); the two `dd` reads | `amix-boot: generation <id>, kernel unix …`. On the console: `dlm: modules from generation <id>'s manifest`, `dlm: 80 kernel symbols` (k30: 78), `dlm: boot-class modules load from the first sysinit entry (modadmin -B)`; then, from init's first sysinit entry, `dlm: boot module z3660eth loaded`; then, from `S01kbnamelist`, `kbootset: namelist /stand/unix written for generation <id>, bound at 0x…`. `/stand/unix` is now its own inode, `/stand/2.1_unix` unchanged with a link count of 1. `netstat -i` lists aen0 and zen0 with sane counters and no `read error on ifstats element`; `ifconfig -a` lists both with no `SIOCGIFFLAGS` error. zen0 up by the module (polled, `intr=0`): telnet and ftp reach the box. `kbootset status`: `module z3660eth (boot): loaded` and `namelist: /stand/unix is generation <id>'s, bound at 0x…`. kinfo: kabi as S3-B1, module count 1, read at offset 576 now (version 3): `dd if=/dev/kinfo bs=4 skip=144 count=1 2>/dev/null \| od -x` gives `0000 0001` |

**Needs the final cut's kernels** (core patch 0017). On a kernel without
it the hook loads in process 0 and panics (the S3-B5 exploratory run on
the old k30 cut, N50): `PANIC: KERNEL FAULT psw=0x2700 … (Bus Error)`
under `lf_hashload`.

If the console says `dlm: boot module z3660eth not loaded: no board
matches …` or `… error <n>`, the reason is on that line. The row then
fails, and the number goes in the report.

### S3-B6 — modadmin on the box (S3-11), after S3-B5

modadmin is built for the box (`make box`: `build/box/modadmin`, GCC 14,
static, the core's own modadmin with core patch 0015). The row copies it
as `/tmp/modadmin` onto S3-B5's box after boot 3, with z3660eth loaded:

| Command | Expected |
|---|---|
| `/tmp/modadmin -s` | `ID REFS DEPS NAME`, then one line for z3660eth |
| `/tmp/modadmin -Q z3660eth` | its status: name, id, path `/stand/gen/<id>/mod/z3660eth`, size, base address, revision 2 |
| `/tmp/modadmin -k z3660eth_intr_mode bootinfo` | an address for each: the module's global (from its own table), then the kernel's exported `bootinfo` |
| `/tmp/modadmin -p z3660eth_intr_mode z3660eth_int6_n:2` | `z3660eth_intr_mode+0 0x…: 0x00000000 (0)` (polled), then the two claim counters |
| `/tmp/modadmin -w z3660eth_rx_holds 0`, then `-p z3660eth_rx_holds` | written, then read back as 0 (as root) |
| `/tmp/modadmin -a <the address -k printed for z3660eth_intr_mode>` | `0x… z3660eth_intr_mode+0x0` |
| `/tmp/modadmin -k no_such_name` | `modadmin: no symbol no_such_name: symbol not found`, exit status 1 |

The z3660net station's M-INT1 reads `z3660eth_intr_mode`, `z3660eth_int6_n`
and `z3660eth_int2_n` this way (the module's globals move with each load).

### Host rehearsal (2026-10-26)

Both kernels were checked on the host:
- `axrel` (the loader's relocator) binds each at 0x00200000 and
  0x07F00000. In both images, `AXK1` at the sidecar's `ident` passes
  boot2's own check: magic, version, check, kabi, line, arena offset and
  capacity. The 0x60000 arena is zero.
- `s3-standin.sh` with `kbootset create`, then a static generation 1, then
  `build` and `commit`, in a 4 MiB store. The rehearsal's generation 1
  was a 1 459 584-byte stand-in, smaller than the vehicle's raw
  1 998 273, which is why the Bench needed the deflated one. Generation 2's manifest carries
  `loader-min 2`, `arena` and `ident`, and `lsstore` gives `ok`.
- With a version-1 store, `build` is refused by gate 7.

## S3-43 — the stage-3 emulator rows (80 §3)

The rows that break the module rules on purpose, after S3-B5 and S3-B6
of record pass, on both lines, in one campaign per line. Each row names
the line of record; a different line, or a box that stops, fails the row.

**Where a line of record is read.** Lines printed while the box boots,
up to and including init's sysinit entries (`modadmin -B`), are on the
console and the serial port. Lines the kernel, the core or a module print
later, after a `modadmin` action in multi-user, reach only the kernel's
message buffer (`putbuf`), not the console (S3-43's first run). Read them
with `modadmin -L` (core patch 0024, modtools with it), the buffer oldest
first, after the action: `modadmin -L | tail -5`. `modadmin -L` finds the
buffer through `/stand/unix`, so `kbootset status` must show a current
namelist first. modadmin's own output (`cannot load …: <errno text>`) is
on the terminal as always.

`-L`'s first line also tells the vehicle from the kernel: `conslogging
0` while no syslogd is in `ps` means the console logger never started on
that boot, which is the vehicle's start-up, not the kernel (S3-43: the
log driver and syslogd's I_CONSLOG work under both module kernels).
The likely cause: the stock `/etc/init.d/syslogd` trusts a stale
`/etc/syslog.pid`. It runs `kill -0` on the previous boot's number, and
the dlm `sysinit` line together with `S01kbnamelist` shift the early pids
so that number is a live process, and syslogd is not started. Either
addition alone misses it (6 of 6 boots on the k46 vehicle). The
installer's unit is fixed in amix-installng.

From core patch 0025, `modadmin -L` starts with one line of the ring's
words: `putbuf 0x… (2000 bytes), putbufsz …, wpos …, rpos …,
conslogging …, prt_where 0x…`. Never read them with `dd skip=`: dd reads
its way through `/dev/kmem` from 0 and hangs the box. `prt_where` 0x2 is
the stock kernel after boot: printf writes the ring, not the console. The
ring holds text only in `-L`'s output, because the log driver's copies
(`logcons`) also put binary header bytes there. A `cmn_err` line can
appear twice, once from printf and once from the log driver's copy.

**`modadmin -K` (core patch 0026), on a box without a console logger.**
After boot the stock kernel's `prt_where` is 0x2: printf goes to the
console only. A message reaches `putbuf` only when a process has
registered the console logger (`conslogging 1` in `-L`'s first line, as
on the k30 v10 vehicle). Then the log driver copies it there. Without
one (`conslogging 0`, the k46 vehicle) run-time lines go to the console
screen and are stored nowhere, so `-L` finds nothing. Run, as root, once
per boot after `S01kbnamelist` has made `/stand/unix` current:

```
/tmp/modadmin -K        # prt_where 0x2 -> 0x3: kernel messages are kept in putbuf too
```

From then on every kernel, core and module line also goes into `putbuf`.
`-L`'s first line shows `prt_where 0x3`, and the console still gets every
line as before. The ring is 2000 bytes and wraps, keeping the newest.
Read `-L` after each action (`| tail -5`), not once at the end of a long
row. On a box with a console logger, `-K` makes printf store each line
directly as well, so a line can then appear up to twice more. `-K` is a
bench and admin command, not run by any shipped script: the two vehicles
differed only by the stale syslogd pid above, not by the kernel.

**Inputs:**
- the kernels of S3-B5 (k46: KD060-Z -58, `8459eaee…`, kinfo version 3;
  k30: the K030-U cut with `unix.sym`), each through `s3-standin.sh`;
  kbootset -12 and modadmin as S3-B5;
- the module set, built with the line's kit (`make kit`, KIT_REV
  e84878e):

```
KERNEL=<the line's ET_REL kernel> sh tests/bench/s3-43/mkset.sh build/kit/<line> <outdir>
```

  KERNEL is the k46 kernel itself, or the k30 kernel before `elf2brel`.
  It gives `<outdir>/tree/` (copy onto the box's root: the stand-in
  packages of the six members), `<outdir>/s43/` (copy to `/tmp/s43`:
  t43ext and the ten rule-breakers) and `<outdir>/verdicts.txt` (each
  rule-breaker's refusal by the kit's checker and by the host loader);
- the loader rows' inputs:

```
sh tests/bench/s3-43/boot2.sh <unix> <kabi> <outdir> "<root record>" [<boot slice bytes>]
```

  It gives `l14.spec`, and `l5.img`, a whole store for the boot slice
  (kbootset refuses to write that generation: gate 4).

**The hand-over**, one directory per line, from:

```
sh tests/bench/s3-43/handover.sh k46 <-58 unix> <-58 kabi> <-58 unix> "sd id=144b0100 unit=6 slice=1" 4194304 <outdir>
sh tests/bench/s3-43/handover.sh k30 <K030-U unix.brel> <its kabi> <its .etrel> "sd id=00000000 base=00000000 unit=6 slice=1 mobo" 67108864 <outdir>
```

Each holds `tree/`, `s43/`, `verdicts.txt`, `l14.spec`, `l5.img` (the
vehicle's boot slice size: the 4 MiB k46 store, the 64 MiB k30 v10
store) and `SHA256SUMS`. The relocation oracle runs on the host after
S3-43-2, from the repository root:

```
sh tests/bench/s3-43/oracle.sh <outdir>/tree/etc/conf/mod.d/t43rel <unix> <kabi> <bind> q p
```

with the kernel and sidecar as shipped, the bind address from kinfo,
and the box's `q` and `p` files (S3-43-2's last row). It needs
`build/axrel` and `build/core/test-bin/reloc` (`make test`, `make core`).

**The set** (`tests/bench/s3-43/src/`):

| Member | Class | What it is for |
|---|---|---|
| `monsw` | demand, `c:52`, pinned | stand-in for S3-27: the dependency, the pinned unload |
| `z3660rtg` | demand, `c:49`, `depend=monsw`, `unload=allowed` | stand-in for S3-26: the dependency order, the allowed unload, the first open |
| `t43boot` | boot, `match=always`, `unload=allowed`, `param tag` (modreg.d `s3-43`), `count` (3) | load, parameters, the allowed unload, M-SIG3 at `modload` |
| `t43leak` | boot, `unload=allowed` | its `_unload` forgets its level-6 handler: the backstop |
| `t43fail` | boot | its `_load` attaches a handler and fails (EIO): the kernel as it was |
| `t43rel` | boot, `unload=allowed` | the relocation oracle |

`monsw` and `z3660rtg` carry the real modules' names, because the
registry gives their majors to those names. The rows run on a slot copy
that has no real `monsw` or `z3660rtg` package.

**The vehicle:** a fresh slot copy in S3-B5's state after its boot 1:
- loader version 2 accepted;
- `/sbin/modadmin`, the `modadmin -B` inittab line, `/sbin/kbootset` and
  `S01kbnamelist` installed.

On the 4 MiB k46 store only one module generation fits beside
generation 1. So the S3-43 generation takes the place of S3-B5's, and a
row that commits another generation first marks the previous one bad and
runs `kbootset collect`. The 64 MiB k30 store needs neither.

### S3-43-1 — the generation (boot 1)

| Commands | Expected |
|---|---|
| copy the stand-in trees and `<outdir>/tree/`; copy `<outdir>/s43/` to `/tmp/s43`; `mknod /dev/t43rtg c 49 0`; `mknod /dev/t43monsw c 52 0`; `kbootset build`; `kbootset commit` | the build's records, after the kernel's: `t43boot`, `t43fail`, `t43leak`, `t43rel` (boot class, by name), then `monsw` and `z3660rtg … majors=c:49 depend=monsw` (demand class); `param t43boot.tag=s3-43`, `param t43boot.count=3`; `generation A committed` |

### S3-43-2 — load, the backstop, unload, the dependency (boot 2, generation A)

From init's first sysinit entry, in this order:

```
t43boot: loaded, params "tag=s3-43 count=3"
dlm: boot module t43boot loaded
t43fail: handler attached, failing with EIO
dlm: t43fail left 1 registration(s) pointing into it (an interrupt handler, network interface or console hook): removed
dlm: boot module t43fail not loaded: error 5
t43leak: level-6 handler attached (0)
dlm: boot module t43leak loaded
t43rel: loaded at 0x…
dlm: boot module t43rel loaded
```

Then multi-user as S3-B5 (the keyboard and the timers keep working: the
level-6 chain is as it was after t43fail).

| Row | Commands | Expected |
|---|---|---|
| load | `modadmin -s`; `kbootset status` | t43boot, t43leak, t43rel; no t43fail. Status: the four boot members, t43fail `not loaded (the console says why)`; monsw and z3660rtg `not loaded (loads at the first open of its device)` |
| allowed unload | `modadmin -U t43boot` | `t43boot: goodbye`; gone from `modadmin -s` |
| backstop | `modadmin -U t43leak` | `t43leak: unloading without intr_detach`, then `dlm: t43leak left 1 registration(s) pointing into it (an interrupt handler, network interface or console hook): removed`; the keyboard still works |
| M-SIG3, `modload` | `modadmin -l t43ext` | `dlm: t43ext is not a member of the booted generation`; modadmin `cannot load t43ext` (EPERM) |
| M-SIG3, `modload` | `cp /stand/gen/A/mod/t43boot /tmp/t43boot.keep`; `echo x >> /stand/gen/A/mod/t43boot`; `modadmin -l t43boot`; then `cp /tmp/t43boot.keep /stand/gen/A/mod/t43boot`; `modadmin -l t43boot` | `dlm: t43boot: SHA-256 differs from the booted manifest`, modadmin `cannot load t43boot` (EPERM); after the copy is restored, `t43boot: loaded, params "tag=s3-43 count=3"` |
| M-SIG3, dependency | `cp /stand/gen/A/mod/monsw /tmp/monsw.keep`; `echo x >> /stand/gen/A/mod/monsw`; `cat /dev/t43rtg`; then restore it | `dlm: monsw: SHA-256 differs from the booted manifest`; `cat` cannot open `/dev/t43rtg` (ENXIO); neither module in `modadmin -s` |
| M-SIG3, first open | the same with `/stand/gen/A/mod/z3660rtg`; `cat /dev/t43rtg`; then restore it | `dlm: z3660rtg: SHA-256 differs from the booted manifest`; ENXIO |
| dependency | `cat /dev/t43rtg`; `modadmin -s` | `monsw: the S3-43 stand-in, loaded`, then `z3660rtg: the S3-43 stand-in, loaded` (the dependency first); an empty read; both listed, monsw with one dependent (DEPS 1) |
| allowed unload, demand | `modadmin -U z3660rtg` | `z3660rtg: the S3-43 stand-in, unloaded`; gone |
| pinned | `modadmin -U monsw` | modadmin `cannot unload monsw` (EBUSY); still listed |
| relocation oracle | `modadmin -Q t43rel > /tmp/q`; `modadmin -p t43rel_first:64 t43rel_fns:64 > /tmp/p`; `dd if=/dev/kinfo bs=4 skip=135 count=1 2>/dev/null \| od -x` (the bind address, kinfo bootdata's text vaddr); copy `/tmp/q` and `/tmp/p` to the host | on the host, `sh tests/bench/s3-43/oracle.sh <tree>/etc/conf/mod.d/t43rel <unix> <kabi> <bind> q p`: `oracle: t43rel at 0x…: 83 words, 332 bytes of 332, identical to the host loader` |

### S3-43-3 — development load (boot 3)

Before the reboot, `echo x >> /stand/gen/A/mod/t43boot` (the copy kept as
above), then `kbootset next devload` and power-cycle. The flag is for
this boot only.

| Row | Commands | Expected |
|---|---|---|
| a changed member | (sysinit) | `dlm: DEVELOPMENT LOAD: t43boot, its SHA-256 not checked`, then `t43boot: loaded, …`; the same `DEVELOPMENT LOAD` line for each boot member |
| outside the generation | `modadmin -l /tmp/s43/t43ext` | `dlm: DEVELOPMENT LOAD: t43ext, outside the booted manifest`; `t43ext: loaded` |
| kabi family | `modadmin -l /tmp/s43/kfam` | `dlm: kfam: built for another kernel (kabi, compiler pin or build)`; modadmin `module wrapper revision mismatch` (EBADVER, 167) |
| kabi major, a minor above, another pin | `kmaj`, `kmin`, `kpin` the same way | the same line for each |
| `SHT_REL` | `/tmp/s43/bshtrel` | `dlm: bshtrel: not a module object as C3-1 says (error 165)` |
| a type outside the list | `/tmp/s43/brtype` | `dlm: brtype: its relocations are refused (error 165)` |
| a zero match key | `/tmp/s43/bzkey` | `dlm: bzkey: .moddata refused, a malformed or missing key, or an unknown critical one (error 168)` |
| a name over 14 | `/tmp/s43/blong` | `dlm: blong: .moddata refused, a name over 14 (error 78)` |
| revision 1 | `/tmp/s43/bv1` | `dlm: bv1: .moddata refused, not version 2 (error 167)` |
| a symbol outside the allowlist | `/tmp/s43/bsym` | `dlm: bsym: its symbols are refused, an undefined name outside the allowlist or a bad symbol table (error 165)` |
| nothing left | `modadmin -s` | the boot members and t43ext; none of the ten |

Each rule-breaker's line is preceded by its own `DEVELOPMENT LOAD: …,
outside the booted manifest`. Restore t43boot's copy afterwards.
`verdicts.txt` gives the same refusals from the kit's checker, and the
host loader's step and errno for the six it refuses at load:
`bshtrel` hdr 165, `brtype` reloc 165, `bzkey` moddata 168, `blong`
moddata 78, `bv1` moddata 167, `bsym` syms 165. The kabi breakers pass
the host loader, which has no kernel to compare against: the core's
check is `md_check`.

### S3-43-4 — a dependency outside the generation (boot 4)

Generation B is A without monsw, written as given:

```
mkdir -p /stand/gen/B/mod
cp /stand/gen/A/mod/* /stand/gen/B/mod/
BSS=`sed -n 's/^bss=//p' /stand/<line>/kabi`
sed -e '/^module monsw /d' -e 's|/stand/gen/A/|/stand/gen/B/|g' \
    -e "s|^\(kernel unix [^ ]*\).*\$|\1${BSS:+ bss=$BSS} z=deflate|" \
    /stand/gen/A/build > /tmp/nodep.spec
kbootset commit --spec /tmp/nodep.spec
```

The build file's kernel line has no `bss=` (`commit` adds it from the
sidecar), so the spec's line takes it from `kabi`: a `brel` (k30) without
it boots with `no bss= for this brel: 512 KiB assumed` (`a brel kernel
without bss= in its manifest: …` before boot2 at 001b04a). `z=deflate` needs kbootset -14 (amix-dlm 72ed9c2) or later: the
box's kbootset had no deflate before (it ignored the flag, so gate 5 counted
the raw kernel).

B is the next numeric id, A + 1. B's kernel is deflated, so it may fit
beside generations 1 and A on the 4 MiB k46 store. If gate 5 refuses
there, the row runs on k30 only, and the report says so. After the row,
`kbootset mark-good` on B: B is then the generation L14 falls back to
(S3-43-5), on both lines.

| Commands | Expected |
|---|---|
| (boot B) `cat /dev/t43rtg` | `dlm: monsw is not a member of the booted generation`; ENXIO. A first open of a module that is in no generation cannot happen: only a member's majors are registered for one |

### S3-43-5 — L14 (boot 5)

| Commands | Expected |
|---|---|
| copy `l14.spec`; `kbootset commit --spec l14.spec` (on k46, if the store refuses it for space: `kbootset mark-bad A`, `kbootset collect`, commit again); power-cycle | `amix-boot: generation N, kernel unix …`, `amix-boot: L14 kernel identity does not match the manifest (generation N)`; the default generation, B, boots in the same boot. Next boot: `L8 trial generation did not reach multi-user (generation N)`, N marked bad (as S3-B2) |

### S3-43-6 — L5 (boot 6, last: it replaces the store)

| Commands | Expected |
|---|---|
| on the host, write `l5.img` over a slot copy's boot slice (the campaign's last, or a fresh copy: the image replaces the whole store); boot | `amix-boot: generation 2, kernel unix …`, `amix-boot: the arena needs 337 bytes, it has 64` (k30: 367; 32 + the manifest, which `lsstore l5.img 0` gives: 305 and 335 bytes with the hand-over's root records), `amix-boot: L5 module arena overflow (generation 2)`; then generation 1 boots (`dlm: modules from generation 1's manifest`) |

L5 is handled as L2 (10 §9, ruled 2026-10-26): the next generation in
the order boots, with no menu. That fallback is the line of record.

### S3-43-8 — Zorro III memory: the kernel binds below 0x40000000

The finding of S3-43-7's first run (N69, N70). With the emulator's
`+z3=128`, a 128 MB Zorro III board at 0x40000000 was the largest fast
region. Loader version 1 and the stock rule bound the kernel there, and
it never started on either line. boot2 from amix-dlm 9f6f0bb on (28 136
bytes, loader version 2) counts only memory below 0x40000000 (10 §3).

| Commands | Expected |
|---|---|
| the slot copy with the fixed boot2 installed (`kbootset loader-install /tmp/boot2.bin --version 2`, accepted at the next boot), the emulator with `+z3=128` beside the CPU board's fast memory; boot | `amix-boot: kernel bound at <an address below 0x40000000: the CPU board's region>`, the banner, multi-user. kinfo's fast memory (`kbootset status`) is the bind region alone (k46 with a 32 MB mbres bank: 33 554 400 bytes; k30 in its 64 MB a3000 bank: 67 108 832): Zorro III RAM beside is never kernel memory on either line (10 §3) |
| the same with the Zorro III board as the only fast memory, if the emulator allows it | `amix-boot: no fast memory below 0x40000000 to run the kernel in`, `amix-boot: L4 not enough memory (generation N)`; the next generation in the order, or the menu |

### S3-43-9 — k30 in a region over 64 MB

| Commands | Expected |
|---|---|
| k30 with boot2 from amix-dlm 001b04a on, the emulator with a 128 MB bank at 0x08000000; boot | `amix-boot: kernel bound at 08000000`, the banner, multi-user; kinfo's fast memory 64 MiB less the MemHeader's 32 bytes (67 108 832, `kbootset status`). Before the fix this box never started the kernel (N70) |

### S3-43-7 — 128 MB

The emulator with 128 MB in the CPU board's bank at 0x08000000 (not
Zorro III memory, which is never kernel memory: S3-43-8), the S3-43-2
rows `load`, `dependency` and `relocation oracle` again: the same lines.
kinfo's fast memory (`kbootset status`): about 128 MB on k46; on k30 64 MB,
the line's maximum, which boot2 caps the bank to (S3-43-9). On k46 the
relocation oracle's base is then above 64 MB.

## S3-41 — bench measurements on the module kernels (U1, U2, U4)

After the S3-43 sweep, on the same kernels of record and the same slot
copies. U15 is answered (S3-B5, core patch 0017; 90 §3) and has no row.
Each row gives a number for 90 §3.

### U1 — the context at dmainit and at the hook

U1 is not a module: it needs the kernel's own early context. The core
has a measurement build behind `-DDLM_U1` (core patch 0023; without the
flag `dlm.o` is byte for byte the shipped one). amix-040-060-port and
amix-kerntools build each line's kernel of record once more, with
`-DDLM_U1` added where the core's objects are compiled. These are **U1
kernels**, never kernels of record and never packaged.

| Commands | Expected |
|---|---|
| the U1 kernel as a generation by spec (`noarena.spec`'s form, `kernel unix <the U1 kernel> z=deflate`); `kbootset commit --spec`; power-cycle; afterwards mark it bad | after `dlm: … kernel symbols`, from the end of `dlm_init` (dmainit): `dlm: U1 dmainit: sr 0x…, u_procp 0x…, the clock ticked\|stood still after N spins`, then `dlm: U1 dmainit: kmem_zalloc(<n>, KM_NOSLEEP) gave memory\|failed` for 4096, 65536, 262144, 1048576 and 2097152. Then, from the kernel's hook in `rth1_mountroot` after `vfs_mountroot`, the same six lines with `hook` (the status register there was 0x2700 in S3-B5's panic) |

**The numbers:** the status register at each point, whether the clock
ticks there, and the largest size `KM_NOSLEEP` gives. **The reading
(30 §3):**
- `KM_SLEEP` at the hook is safe only if the clock ticks there and the
  priority level lets a wakeup in. With 0x2700 and a clock that stands
  still, a sleep could never end, so stage 4's root-class `_load` keeps
  `KM_NOSLEEP`, as 30 §3 has it.
- `marc_root` will run earlier in the same function (before
  `rth1_apply`), in the same process-0 context.

### U2 — kernel memory for copied modules at 128 MB

The probes are built with the line's kit:

```
sh tests/bench/s3-41/mkprobes.sh build/kit/<line> <outdir>     # <outdir>/s41/u2kva, u4big
```

| Commands | Expected |
|---|---|
| the emulator with 128 MB in the CPU board's bank (as S3-43-7; on k30 the kernel gets 64 MB of it, the line's maximum); copy `<outdir>/s41` to `/tmp/s41`; `kbootset next devload` only once the installed loader is accepted (a loader on trial boots the default generation and spends the one-shot request) and the kernel of record's generation is good and the default (a one-shot request boots the default, never a trial: 10 §7.3); that generation carries the arena (`l14.spec`'s form with the kernel's own `arena` and `ident`, or `kbootset build`'s): development load widens what may load, it does not replace the manifest, so a generation in `noarena.spec`'s form refuses every load (`dlm: u4big: no booted manifest, so no module loads this boot`, modadmin `Not owner`); power-cycle; on that boot `modadmin -K` first (a box without a console logger); run U4 first, then `modadmin -l /tmp/s41/u2kva`; `modadmin -U u2kva` | `dlm: DEVELOPMENT LOAD: u2kva, outside the booted manifest`; `u2kva: N chunks of 65536 bytes (K KiB) with KM_NOSLEEP, from 0x… to 0x…`; `u2kva: all N given back`; the box carries on |

Run U2 in a boot of its own, without U4: a stuck `KM_SLEEP` request
holds memory and makes U2's figure low (the first run). The chunk is
64 KiB, below every line's process-context ceiling (U4: 256 KiB on k46).

**The number:** K KiB, with the address range, at 128 MB. That is what
the core could take for module images, beside the arena. Run it on a
quiet box: for that moment the kernel has no memory to spare.

### U4 — large kmem requests return

| Commands | Expected |
|---|---|
| in the same development-load boot, before U2: `modadmin -l /tmp/s41/u4big`; `modadmin -U u4big` | ten pairs `u4big: kmem_zalloc(<n>, KM_NOSLEEP\|KM_SLEEP) ...` / `u4big: ... memory\|failed at 0x… after T ticks`, for 64 KiB up to 2 MiB, KM_NOSLEEP first. Every request returns (a line `...` with no answer is the hang the row looks for); KM_SLEEP gives memory at each size |

**The numbers:** the ticks for each size and flag, and which sizes fail
`KM_NOSLEEP`. A request that never returns fails U4. Its size is the
last `...` line, and 30 §2's routing of large requests is then the
core's to change.
