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

## Stage 2: the lifecycle rows (S2-41, S2-42, S2-46)

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
| 1 | `kbootset build; kbootset commit` | `generation 2 committed; power-cycle to boot it` |
| 2 | `kbootset mark-good` | `amix-boot: generation 2, kernel …`; then `generation 2 is good and the default` |
| 3 | `kbootset rollback` | boots 2; then `the default is generation 1 (was 2)` |
| 4 | `kbootset next previous` | boots 1; then `the next boot only is changed` |
| 5 | `kbootset mark-bad 2; kbootset commit --spec bad.spec` (below) | boots 2, once, the one-shot; then `marked bad and collected`, then `generation 3 committed …` |
| 6 | — | boots 3, the trial. It cannot mount its root, so it never reaches mark-good: power-cycle when it stops |
| 7 | `kbootset status` | `amix-boot: L8 trial generation did not reach multi-user (generation 3)`, then generation 1 boots; status shows 3 as bad, or already collected, and default 1 |

`bad.spec` names a k46 kernel without the Z3660 driver, such as KD060-A,
whose root controller is the A4091:

```
line k46
rootfs ufs
root sd id=144b0100 unit=6 slice=1
kernel unix /tmp/KD060-A-c0-u6
```

`commit --spec` runs no gates. That is the point here: a trial the gates
would refuse (closure) is the way to get a trial that panics in rc.

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
--extra '/tmp/kbootset build > /dev/term/ser 2>&1; (KBOOTSET_HOLD=N /tmp/kbootset commit > /dev/term/ser 2>&1 &)'
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
