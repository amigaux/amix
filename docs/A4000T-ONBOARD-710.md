# A4000T onboard 53C710: design note (A1)

Status: **design only, no code** (2026-10-02). It covers the fixed-address mode of the a4091 driver for the A4000T's
onboard 53C710: the presence probe, registration and card order, interrupts, DMA reach, the ROM-driver handover, the
relink shape (KD060-ZT) and the test plan. Effort is estimated at the end.

Confidence tags: **[S]** read in source (path:line given), **[M]** a metal record, **[I]** inferred, unmeasured.

## 1. The hardware, and how it differs from the A4091

| | A4091 / A4092 (today) | A4000T onboard |
|---|---|---|
| Discovery | AutoConfig. Base from autocon() via the sd.c rows, `sdcardbase()` | **None.** Fixed base `$DD0000` [S a4091.h:23; ncr7xx.c:466-485 "No Zorro config for 53C710 in A4000T"] |
| Registers | base + `0x800000` | base + **`0x40`** [S a4091.h:24; ncr7xx.c:5919] |
| DIP switches | base + `0x8c0003`, byte | base + **`0x3000`**, read as a longword [S a4091.h:25; attach.c:396-397] |
| Register writes | ours: every write to reg + `0x40` (`WRSHADOW`) | **direct**. The reference driver writes registers directly for every board (siop.c:806-826). Its TEMP/SCRATCH write shadows sit at rp + `0x80` on the A4000T and are used only by its self-test (attach.c:527-536) |
| DCNTL | `0x00` (ours, a4091init) | **`0x20` EA**, "A4000T: Connect _SLACK/_STERM" [S attach.c:636-640] |
| SCLK | 50 MHz, DCNTL CF = SCLK/2 | 50 MHz, the same divisor [S a4091.h:69, :76] |
| DMODE / CTEST7 | `0xE0` (burst 8, FC2) / CDIS | the same [S siop.c:816-818; attach.c:630] |
| Host ID | ours: constant 7 | DIP & 7 [S attach.c:404-414]. All switches off reads 7 |
| Bus master | Zorro III, through Buster | **motherboard master**, the same class as the A3000 SDMAC [I] |

The driver therefore needs per-card values for: physical base, register offset, write offset (`0x40` for the A4091,
`0` for the A4000T), DCNTL, and host ID. The SCRIPTS, the DSA table, the bounce and the D42 seam are unchanged.

Out of scope: the reproduction boards' 53C770 (`A4000T770`, registers at `$DD0000 + 0`, a different register map
[S a4091.h:27-29]). The probe must answer "absent" for one (§2, G2).

## 2. What sits at `$DD0000`, and the safe probe

| Machine | `$DD0000`-`$DD1FFF` | Touching `$DD0040` |
|---|---|---|
| A3000 (ECS) | SDMAC + WD33C93, with WD ports `$DD0041`/`$DD0043` [S kerntools docs/040-support-c-d7.md §1] | **writes the WD.** Never probe there |
| A4000D (AGA) | nothing documented. A4000 IDE starts at `$DD2020` [S amiberry gayle.cpp:61-63, :88] | **unknown on metal**: a bus error, or floating data [I] |
| A4000T (AGA) | 53C710 at `$DD0040`, DIP bank at `$DD3000` | the chip |
| Amiberry, `scsi_a4000t` on | mirrored every `0x100` up to `$DD201F`: `+0x00..0x3f` read 0, `+0x40..0x7f` registers, `+0x80..0xff` alternate window; DIP reads `0xff` [S gayle.cpp:647-745, NCR_OFFSET/ALT/MASK :68-70] | the emulated chip |
| Amiberry, A4000 config | falls through to the A4000 IDE decode (`gayle_read`) [S gayle.cpp] | IDE decode, no chip |

VPOSR cannot separate the A4000D from the A4000T: both are AGA Alice [S 040-support-c-d7.md §6c]. The Kickstart
cannot be the discriminator either. The A4000T box boots A4kOS323 through `.d6` today, which has no NCR driver
[S tmp/2026-10-02-a4092-metal/Z3660-T-vs-D-diff.md §4], and a user may run any ROM. So presence is decided by asking
the chip, in this order. Each step only runs if the previous one said "maybe":

- **G0, the chipset gate.** VPOSR (`$DFF004`) bits 8..14, low nibble ≥ 2 means AGA. This is the same expression as the
  KT-09b probe and ide.c (amix-gayle-ide src: `IDE_VPOSR_IS_AGA`). Not AGA means **absent, and nothing under `$DD0000`
  is touched**. This is what keeps the probe off the A3000's WD33C93.
- **G1, a read-only first touch through `bprobe`.** Read ISTAT at `$DD0040 + 0x22` (the same `a4091_probe8` the KVA arm
  uses for U62). A fault means absent ("bus error at 0xdd0062: no onboard 710"), with no panic.
- **G2, a read-only fingerprint.** It only reads registers whose reads have no side effects, or whose side effects are
  harmless on an idle chip:
  - ISTAT reserved bits (`0x10 | 0x04`) are 0, and the value is not `0xff`. Floating data usually reads all-ones, and
    Amiberry's A4000 decode reads `0xff`.
  - With ISTAT SIP/DIP clear, DSTAT bit 7 (DFE, DMA FIFO empty) is 1 on an idle 710.
  - CTEST8's high nibble is the chip revision. Record it, and match it once the metal value is known.
  - The same reads repeated twice give the same answer, which rejects floating data.
  - A 53C770 does not have the 710 layout at `+0x40`, so it fails here.
- **G3, a write fingerprint, only after G2 passed.** Rotate patterns through SCRATCH (`0x34`) with direct writes
  (write offset 0), as the reference self-test does (attach.c:540-575). Every access goes through `bprobe`. A G2 pass
  means a 710 answers, so this write reaches a real chip. On an A4000D, G2 has already said absent and no write
  happens.

The thresholds in G2 are **calibrated, not guessed**. Cell T0 (§9) dumps `$DD0000`-`$DD00FF` read-only on the
A4000D and on the A4000T under AmigaOS, and Amiberry gives the A4000 / A4000T / three `unmapped_address_space` rows.
G2 is only frozen once those four readings exist.

### T0 result (2026-10-02): the G1 premise fails under the Z3660

| Box | Read | Result |
|---|---|---|
| A4000D, Z3660 (060), no 53C710 | `ddpeek-t` at `$DD0000`, first longword pass | **froze at the first read**: no reply, no network, hard power-off [M tmp/2026-10-02-a4092-card2/t0/frozen-screen.jpg]. The exact address is unnamed (the DB25 tap carries no bytes), but it is at or near `$DD0000`, before any `+0x40` register |
| A4000T (ReAmiga), Z3660 (060), 53C710 | the same dump | **hangs at the first read, `$00DD0000`** [M, Z3660 station trace]. An A4000D Kickstart ran in MAPROM, and no 710 driver had touched the chip. A second run starting at `$DD0040` is queued |

**Mechanism** [M, Z3660 station answer, 2026-10-02]:
- **The Z3660 CPLD does forward Amiga /BERR to the 060.** On the real-CPU path, P119 → nRBERR, and in BUSCON
  state Z/SB it drives nTEA (P13) while the 060 owns the bus. Proof: the 2026-09-30 A4092 ROM-cycle hang came back
  as a format-$4 access fault after Buster's Zorro III timeout of about 280 ms.
- **The card has no cycle timeout of its own.** TERM.vhd waits for DSACK, AVEC or BERR indefinitely.
- **So a read hangs only where the motherboard never terminates it.** Zorro III space gets Buster's timeout. Local
  I/O space, `$D80000`-`$DFFFFF`, evidently gets none on either box, so an undecoded `$DD00xx` cycle waits forever
  and no fault handler can run.

This also re-explains MG8: the stock a3091 poked `$DD0041`/`$DD0043` on an A4000T without W-D7, and the boot
stalled on a hung cycle, not just on "the wrong chip".

**Consequences:**
- **G1 cannot be the first gate.** `bprobe` catches a bus error; it cannot catch a cycle that never ends.
- **New gate GD, presence by declaration, before G1.** The kernel touches `$DD00xx` only when the build says the
  board is an A4000T. That means a patchable `.data` knob, `a4091_a4kt` (default 0), set to 1 only by the
  KD060-ZT / A4000T media stamp (kerntools). Without it, `a4ktpresent()` returns "absent" without a single access.
- **G1-G3 still run after GD,** as a check of a declared board. They touch only `+0x40` onwards, never
  `$DD0000`-`$DD003F`, and only after the A4000T half of T0 shows that the 710 window itself answers on that board
  (reading (i) of the A4000T question). If the 710 window also hangs, A1 waits on the board, not on code.
- **Open lead for bringing auto-detection back: Gary's bus-timeout registers `$DE0000`/`$DE0001`** (from the Z3660
  station). On the A3000 these are documented as timeout enable and mode. The questions:
  - Do the A4000D's motherboard chips and the ReAmiga 4000T implement a timeout for `$D80000`-`$DFFFFF`?
  - If so, does enabling it around the probe (enable, G1, restore) turn a dead `$DD` window into a fault that
    `bprobe` catches?
  Until that is measured on both boxes, GD stays the first gate. A system-wide timeout change is not an option
  either way: it would touch every slow motherboard device. Only a probe-scoped enable and restore is.
- **U62 still holds for Zorro III.** A dead Zorro III window gets Buster's timeout, which reaches the 060 as a
  fault, so `bprobe` catches it after about 280 ms and the attach degrades to "no board". The hang is specific to
  undecoded local I/O space.
- **W-D7 is unaffected.** On AGA it reads only VPOSR and never touches `$DD0000`.

**The phantom must not claim `$DD0000`.** That is W-D7's job and it is already a rule. Stock autocon() synthesises the
A3000 SDMAC at `$DD0000` (id `0x0202F003`) unless the support.c probe rejects it. On an A4000T without W-D7, the stock
a3091 then pokes the 710's address space and the boot stalls [M review/D-1 2026-09-28 MG8, 2/2 cold boots]. W-D7 skips
`$DD0000` on AGA. The onboard row (§3) has its own id, so the 710 is never registered as the phantom, and the phantom
never as the 710. **KD060-ZT must carry W-D7**, which the media gate already enforces ("wd7 required").

## 3. Registration and card order

**How sd counts cards.** `init()` walks the controller table. For each row it calls `autocon(id, n, &addr, &aux)`,
and every answer goes to `insert()`. `insert()` keeps **SDCARDS = 2** slots sorted ascending by `addr`, and drops the
newcomer once both slots are full [S amix-040-060-port src/ide_sd_glue040.s header; kerntools 040-support-c-d7.md §5b].
The card number is therefore the rank by address.

The onboard 710 is not an AutoConfig board, so it reuses the **Gayle IDE glue pattern** (P-15 P2, port
`src/ide_sd_rows.py` + `src/ide_sd_glue040.s`):

- `a4kt_sd_rows`: the base's table with every existing row (by relocation), plus **one row** carrying an id no board
  has. I propose `0x0710a400`.
- `a4kt_sd_glue040.s` wraps init()'s single `jsr autocon`. That id is answered by `a4ktpresent(&base)`, the GD + G0-G3
  gates (§2), which live **in the a4091 object**. Every other id goes to autocon unchanged.
- **Sort key, not bus address.** As with `ide_sd_key`, the glue hands insert() a rank:
  - default `0xffffffe0`: sorts after every real board and before IDE's `0xfffffff0`. So the **Z3660 stays card 0
    and the onboard 710 is card 1**, the shape the brief asks for.
  - key `0`: rank by the real base `$DD0000`, so the onboard 710 is **card 0**. This is the shape for a stock
    A4000T rooting on its own SCSI, with no Z3660.
- **Driver side.** `sdcardbase(card)` then returns the key. The driver owns the key in `.data` as `a4091_a4kt_key`,
  and the glue reads it. `a4091attach` takes onboard mode when `base == a4091_a4kt_key || base == 0xDD0000`:
  physical `$DD0000`, registers `+0x40`, write offset 0, DCNTL EA, host ID from the DIP bank (read only after the
  probe passed), and `ctlid` = the onboard id in the D42 record. Every other base keeps today's Zorro path
  byte-for-byte.

**Constraints the design inherits:**

- **One glue per `jsr autocon` site.** ide_sd_rows.py refuses a site naming anything but `autocon`/`ide_sd_autocon`,
  so it fails closed. A kernel with both IDE and the onboard 710 needs **one chained glue** answering both ids.
- **Two slots.** On an A4000T with a Z3660, the Z3660 and the 710 fill the table. A Zorro A4091/A4092 or the IDE is
  then dropped with "sd: too many controllers" (the DL-07 wording). Which one is dropped is decided by **row order**
  (rows are walked in table order, and the newcomer loses). I recommend the 710 row **after** the A4091/A4092 rows:
  a fitted Zorro card is a deliberate choice, and new rows last never displace a board the base registers (the
  a4091_sd_rows.py rule). **Owner decision.** Raising SDCARDS is a binary change to sd.o: named, out of scope.
- **rootdev.** The default key leaves the Z3660 root stamps (card 0) untouched. Key 0 puts the onboard root on
  card 0 (the `c6d0s1` stamp family); default-key data disks are card 1 (`ced0*`). Stamping is kerntools'.
- **W-D7 has no conflict.** It decides only the A3000 phantom and never touches `$DD0000` on AGA. The 710 probe runs
  later, inside init()'s row walk.

## 4. Interrupts

The driver stays **polled**, like the rest of the KD line: `a4091queue` polls ISTAT under a bound, and `a4091intr`
is empty. SIEN and DIEN stay 0. One addition: **quiesce at attach**. Write SIEN = 0 and DIEN = 0 right after G3,
before anything else, and clear latched SIP/DIP the way a4091init already does. An A4000T Kickstart scsi.device may
leave the 710's interrupts enabled at handover, and an unclaimed level on the 710's interrupt line would repeat until
the first I/O reaches a4091init. I believe that line is INT2 (PORTS) [I], but polling makes the answer irrelevant
once the chip is quiesced. The same applies in principle to the A4091/A4092 ROM's handover [I]; it is low risk on an
idle chip, and the metal cells will show it.

## 5. DMA reach into Z3660 DDR

- **The A4000T's 710 is a motherboard master**, like the A3000 SDMAC, not a Zorro III master through Buster like the
  A4092 [I]. Antti's letter 11 shows the motherboard case working: A3000 SDMAC DMA into a Z3660's CPU-local
  `$08000000` aperture, 6147 segments, all must-stay-zero counters 0 [M review/D-1 2026-10-01]. Separately, AmigaOS
  has booted from this A4000T's onboard 710 on its real 060 [M review/P-4, 2026-09-25].
- **The A4092 cells answer the other question** (Zorro III through Buster, A4000D), so their result does not transfer
  either way. **The onboard case needs its own coherence cell (T2).** Once the Bench station's A4092 DMA reading lands
  (tmp/2026-10-02-a4092-metal, question 2), record it next to T2 as the Buster data point.
- **The data path is unchanged.** `sdcom.addr` is physical, the 710 drives 32-bit addresses, and the D42 seam, the
  bounce and the invariants apply as on the A4092 (one record per card).
- **Box caveat.** The A4000T is a ReAmiga reproduction with **open build items, including the stage-13 termination
  packs** [S Z3660-T-vs-D-diff.md §4]. Settle SCSI termination on the onboard bus before any T-cell; a bad terminator
  looks like a driver fault.

## 6. The ROM-driver side: Kickstart scsi.device vs ours

- **There is no runtime coexistence.** Once the Amix kernel runs, AmigaOS is gone. What matters is the state at
  handover:
  - **Synchronous agreements.** Handled by A4-22 (ff7ee6a): one SCSI bus reset per card before its first command. It
    applies to the onboard card unchanged.
  - **A running script or enabled interrupts.** a4091init's abort + soft reset runs on every command, plus the attach
    quiesce in §4.
  - **Host ID.** Both sides use the DIP host ID (7 by default).
- **Boot routes.**
  - (a) **Root on the Z3660 (KD060-ZT, card 0), onboard 710 for data.** No 710 ROM driver is needed. With today's
    A4kOS323 the chip is untouched since reset, which is the cleanest handover.
  - (b) **Root on the onboard bus.** Kickstart must load boot1/boot2 through a scsi.device for the 710. That means an
    A4000T ROM (registry R073 3.2.1 47.102, R074 3.2.2 47.111, R075 47.115, R076 3.1 r40.70), or the reference's
    `scsi710.kick` module (Makefile:38, :409, `OEM_KICKMODULE`).
- **ZuluSCSI on the onboard bus.**
  - The driver already suits it: async, IDENTIFY `0x80` (no disconnect), no tagged queueing.
  - Its SCSI ID must not be 7.
  - Termination per the box caveat in §5.

## 7. Relink shape: KD060-ZT

KD060-ZT = KD060-Z (Z3660 card 0, cdfs) + the a4091 object with the onboard mode + `a4kt_sd_rows` and the glue + **W-D7**.

| Repo | Piece |
|---|---|
| amix-a4091 | onboard mode in `a4091-wr.c` (KVA arm and 030), `a4ktpresent()`, `a4091_a4kt_key`. New exports only; the import set stays the gated one |
| amix-040-060-port | `a4kt_sd_rows.py` (the a4091_sd_rows.py generator with one row), `a4kt_sd_glue040.s`, and a chained IDE+710 glue variant |
| amix-kerntools | family KD060-ZT, c0 stamps (Z3660 root), the key-0 variant for route (b), k0-gates incl. `wd7 required` |

A KD040-T sibling (stock A4000T/040 with an A3640) is the same object on the 040 base. That is kerntools' family
call, later.

## 8. Test plan: emulator first (N12), then the A4000T

T-13 records N12 as blocked because "amiberry does not model the $DD0000 onboard 53C710". That is **superseded**: the
model is in the fork [S amiberry src/gayle.cpp:647-745, ncr_scsi.cpp `ncr710_io_bget_a4000t`]. It is enabled by
`chipset_compatible=A4000T` (`cs_mbdmac == 2` adds ROMTYPE_SCSI_A4000T, cfgfile.cpp:7044-7060) or by
`scsi_a4000t=true`, with units via `scsi<N>_a4000t`, and an A4000T Kickstart taken from roms/ by id (R075 or R076).
Amiberry's DIP bank reads `0xff`, so host ID 7.

| Cell | Rig | Shows |
|---|---|---|
| N12a probe matrix | A4000T config / A4000 AGA config / A3000 ECS / A4000 under the three `unmapped_address_space` settings | found / absent with no fault / G0 skip with the A3000 SCSI boot undisturbed (the DL-08 shape) / absent on all three |
| N12b data | A4000T + 060 (+ R-060Z Z3660 for card 0) | GSIO INQUIRY then READ(10), raw dd and a UFS tree equal to host truth, D42 invariants, Z3660 = card 0 and 710 = card 1; the key-0 variant roots on the 710 as card 0 |
| N12c order | the A4092 + 710 rows; the chained IDE + 710 glue | the drop rule as §3 predicts; both glue ids answer |
| T0 metal | A4000D and A4000T under AmigaOS | read-only dump of `$DD0000`-`$DD00FF`. **A4000D: hang at first touch; A4000T: hang, address pending** (§2, T0 result). Next: the A4000T from `$DD0040`, with a working tap |
| T1 metal | A4000T, KD060-ZT, Z3660 root, ZuluSCSI on the onboard bus | attach line, probe answer, data equal to host truth |
| T2 metal | as T1, copyback (`hat_cm_ram 0x20`) | coherence digest for the motherboard-master path into `$08xxxxxx` |
| T3 metal | A4000T Kickstart with scsi.device (or `scsi710.kick`) | route (b): root on the onboard bus |

## 9. Effort

| Piece | Estimate |
|---|---|
| a4091: the onboard mode (per-card offsets, DCNTL, key translation, G0-G3 probe, DIP host ID, attach quiesce, ctlid), both builds, gates | 1-1.5 station-days (S-M) |
| port: rows + glue, chained IDE + 710 glue (mostly ide_sd_* reuse) | about 1 day (M) |
| kerntools: KD060-ZT family, stamps, gates | 0.5-1 day |
| amiberry rig + N12a-c | about 1 day, if the model behaves as read |
| metal T0-T3 | about 1 bench day; T0 can run any time, read-only |

**Total: M-L, about 4-5 station-days**, matching P-15 K5.

The critical path is T0 (now: does the A4000T's 710 window answer from `$DD0040`, and does the Z3660 deliver BERR at all), then the a4091 code, then the port glue, then kerntools, then N12, then
T1-T3.

**Open owner decisions:**
1. Sort key: default (710 = card 1) vs 0 (710 = card 0).
2. Row order against an A4092 in the same box.
3. Whether a KD040-T sibling is wanted.
