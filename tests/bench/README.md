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

## The DF0 pair (S1-27, metal)

`df0-pair.sh <workspace> <outdir>` builds one pair per line with the 1.0
floppy kernel stored uncompressed, so the kernel runs on from volume 1
into volume 2. Boot from DF0 with volume 1. At `amix-boot: L11 insert boot
volume 2 of 2` insert volume 2 (a wrong disk is refused first). After
`amix-boot: starting the kernel` the kernel roots on `fd0` as in 1.0, so
DF0 then takes the 1.0 root floppy of that line. A stage-1 loader refuses
RAM-disk generations, so the RAM-disk profile (M-FP1) boots only from
stage 4 on.
