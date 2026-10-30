# A4000T onboard 53C710: design note (A1)

Status: **design only, no code** (2026-10-02). **§10 (2026-10-27) supersedes §3 and §7 for the module form (S5-06, was S4-33; metal S5-07):**
the sd rows, the glue and the sort key are replaced by `sd_register` with rank `mobo`, and the static relink
(KD060-ZT) is not pursued. It covers the fixed-address mode of the a4091 driver for the A4000T's
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
[S, bench comparison of the two boxes, 2026-10-02], and a user may run any ROM. So presence is decided by asking
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
| A4000D, Z3660 (060), no 53C710 | `ddpeek-t` at `$DD0000`, first longword pass | **froze at the first read**: no reply, no network, hard power-off [M, 2026-10-02]. The exact address is unnamed (the DB25 tap carries no bytes), but it is at or near `$DD0000`, before any `+0x40` register |
| A4000T (ReAmiga), Z3660 (060), 53C710, run 1 | the same dump | **hangs at the first read, `$00DD0000`** [M, Z3660 firmware trace] |
| A4000T, run 2 | `ddpeek-t2` starting at `$DD0040` (longword, the 710 register base), after halting the OS | **hangs at the first read, `$00DD0040`** [M, 2026-10-02]. No address answered in either run |
| A4000T, variant 3 | bench OS on Kickstart A4000T 47.115 (`.d6`) + the normal `kick060_scsi` shim, so `NCR scsi.device 47.4` ran (no device on the onboard bus). After halting the OS: table-driven supervisor reads, byte and long, each DB25-traced first, no writes | **all 21 reads answered**, zero faults, box up [M, 2026-10-02] |

In runs 1 and 2 the Kickstart was A4kOS323, the A4000D ROM in MAPROM, with no NCR scsi.device, and the bench OS
loads none either. **So on the ReAmiga 4000T the onboard 710 window hangs while uninitialised, and answers byte and
longword reads once the A4000T ROM's NCR driver has initialised it** (variant 3). Reading (ii) holds, and it is the
init that opens the window. Width is not the problem (iii is ruled out).

**Variant 3 values** (the first real-chip calibration of G2; register names per our A4091 map, which this dump
confirms):

| Read | Value | Reading |
|---|---|---|
| ISTAT `$DD0062` (byte) | `00` | idle, reserved bits clear |
| DSTAT `$DD004F` (byte) | `80` | DFE: DMA FIFO empty |
| CTEST8 `$DD0061` (byte) | `20` | chip revision 2 |
| SSTAT0 `$DD004E` (byte) | `00` | |
| SCRATCH `$DD0074` (long) | `00000000` | |
| `$DD0040` (long) | `AF4020D4` | SIEN `AF` (**left enabled**), SDID `40`, SCNTL1 `20`, SCNTL0 `D4` |
| `$DD0044` (long) | `00000080` | SCID `80` = host ID 7 |
| `$DD0050` / `$DD005C` | `0800BF38` / `0800BFE8` | DSA / TEMP point into Z3660 RAM (`0x0800xxxx`) |
| `$DD0064` / `$DD006C` | `54000000` / `0800C274` | DCMD:DBC / DSP: SCRIPTS in Z3660 RAM |
| `$DD0070` | `00000468` | DSPS |
| `$DD0078` (long) | `21003DE0` | DCNTL `21` (**EA set**, as §1 says), DWT `00`, DIEN `3D` (**left enabled**), DMODE `E0` |
| `$DD0060` (long) | `FFFF02FF` | differs from the byte reads of CTEST8/ISTAT (`20`/`00`). The longword read of this byte-register group is not trustworthy, or ISTAT latched between reads. **Use byte reads for byte registers**, as the driver already does (the widths gate) |


**Mechanism** [M, from the Z3660 firmware side, 2026-10-02]:
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
- **G1-G3 cannot stand as designed, even behind GD.** The A4000T half of T0 hung at `+0x40` too (reading (ii) of
  the A4000T question). On this board, a declared A4000T whose 710 nothing has initialised hangs the boot at the
  first register read. Three ways forward, from most to least preferred:
  - **(a) The A4000T Kickstart's own NCR init before Amix.** This is the preset 7 route: A4000T ROM 47.115 via
    `.d6` plus `kick060_z3660scsi_noncr` (the F13 note). If the ROM's scsi.device leaves the 710 (and whatever
    gates its decode) in a state where `+0x40` answers, then KD060-ZT = GD + "the ROM has initialised the chip",
    and G1-G3 run as written. It also keeps the boot route (b) of §6 open. **Open:** which state the ROM leaves the
    chip in, and whether a `+0x40` read answers after it (T0 variant 3).
  - **(b) Gary's timeout lead: CLOSED NEGATIVE** (below, 3b). It was meant to turn the hang into a fault, so G1
    would be safe again. With TOENB set, the A4000D still froze on the same read.
  - **(c) No auto-detection at all.** KD060-ZT = declaration plus the ROM-initialised path only. Without an A4000T
    Kickstart that has initialised the chip, the onboard 710 is unsupported: the driver never touches it and says so
    once on the console.
- **Design state, after variant 3: (a) + (c), confirmed.** The presence rule is GD (declaration) **and** "the
  A4000T ROM's NCR init has run". G1-G3 then run at `+0x40` as written, with byte reads for byte registers. Without
  the ROM init, the onboard 710 is unsupported on Z3660 machines. The driver never touches it and says so once.
  - **How "the ROM init has run" is known** (design choice, open): the boot loader passes it in, from AmigaOS, which
    sees `NCR scsi.device` in its device list; or the media stamp declares it, A4000T Kickstart required. I lean to
    the stamp plus a documented requirement. A boot-loader hand-over is port work.
- **T0 variant 3 (done 2026-10-02, result above).** The recipe as run (with the normal `kick060_scsi` shim; `kick060_z3660scsi_noncr` would have displaced the NCR driver):
  1. Boot AmigaOS on the A4000T ROM. Record that its scsi.device really ran: the resident/device list, its version,
     and the units it found if a drive is on the onboard bus (none is needed).
  2. Read **one byte**: ISTAT at `$DD0062` (`+0x40 + 0x22`). Record answered/hung and the value.
  3. If it answered: bytes DSTAT `$DD004F`, CTEST8 `$DD0061` (revision in the high nibble), SSTAT0 `$DD004E`. Then one
     **longword** at `$DD0074` (SCRATCH). Then the dump `$DD0040`-`$DD007F`, longwords. Never `$DD0000`-`$DD003F`, and no
     writes.
  4. If step 2 answered and step 3's longword hangs, it is a width problem (reading (iii)). Then repeat step 2 under
     preset 5 (A4kOS323, no NCR init): a hang there means the init is what opens the window.
  Record per read: address, width, answered/hung, value, plus the Kickstart, the preset and the scsi.device version.
- **Open lead for bringing auto-detection back: Gary's bus-timeout registers `$DE0000`/`$DE0001`** (from the Z3660
  firmware side).
  - **The model:** WinUAE/Amiberry `gayle.cpp` `mbres_write`/`mbres_read` and `memory.cpp` `gary_nonrange`/`dummy_put`.
    This is an emulator's behavioural model, not Commodore documentation [S-emu].
    - `$DE0001` bit 7 = **TOENB**: an access to a Gary "non-range" address raises a bus error. The non-range includes
      `$DD0000`-`$DDFFFF`.
    - `$DE0000` bit 7 = **TIMEOUT**: a wait/DSACK-timeout mode.
    - `$DE0002` bit 7 = COLDBOOT.
    - The low 7 bits read 1.
  - **The A4000D matches that read-back** [M, cell 3a, AmigaOS, byte reads]: `$DE0000` = `FF` then `7F`, and
    `$DE0001` = `7F` `7F`, so TOENB = 0 and the timeout is off. Both reads terminated with no fault.
  - **The cell (3b), on the A4000D:**
    1. Write `$DE0001` = `0x80` (TOENB on) immediately before ONE byte read of `$DD0000`. Nothing else runs in
       between.
    2. Expect either a bus-error Guru (80000002), meaning the lead works and the probe could use it, or a hang,
       meaning it does not.
    3. A reset clears TOENB in the model. Power-cycle either way.
  - **Result: CLOSED NEGATIVE on a Z3660 box** [M, cell 3b, A4000D, AmigaOS, 2026-10-02].
    1. Before: `$DE0000` = `FF`, `$DE0001` = `7F` (TOENB 0).
    2. `ddpoke $DE0001` = `$80` was written, and read back `FF` (TOENB set, per the model).
    3. One byte read of `$DD0000` immediately after **froze the box exactly like T0**, with no Guru. It was
       power-cycled.
  - So even with Gary's timeout enabled, no fault reaches the 060. Either the Z3660's cycle into `$DDxxxx` never
    reaches Gary's timeout logic, or the resulting BERR is not forwarded for local I/O. The Z3660 firmware side's
    BERR answer covers Zorro III via Buster; local-I/O BERR from Gary is a separate, open question.
  - **Auto-detection by CPU probing of `$DD00xx` is out** on Z3660 machines.
- **U62 still holds for Zorro III.** A dead Zorro III window gets Buster's timeout, which reaches the 060 as a
  fault, so `bprobe` catches it after about 280 ms and the attach degrades to "no board". The hang is specific to
  undecoded local I/O space.
- **W-D7 is unaffected.** On AGA it reads only VPOSR and never touches `$DD0000`.

**The phantom must not claim `$DD0000`.** That is W-D7's job and it is already a rule. Stock autocon() synthesises the
A3000 SDMAC at `$DD0000` (id `0x0202F003`) unless the support.c probe rejects it. On an A4000T without W-D7, the stock
a3091 then pokes the 710's address space and the boot stalls [M, 2026-09-28 MG8, 2/2 cold boots]. W-D7 skips
`$DD0000` on AGA. The onboard row (§3) has its own id, so the 710 is never registered as the phantom, and the phantom
never as the 710. **KD060-ZT must carry W-D7**, which the media gate already enforces ("wd7 required").

## 3. Registration and card order

**How sd counts cards.** `init()` walks the controller table. For each row it calls `autocon(id, n, &addr, &aux)`,
and every answer goes to `insert()`. `insert()` keeps **SDCARDS = 2** slots sorted ascending by `addr`, and drops the
newcomer once both slots are full [S amix-040-060-port src/ide_sd_glue040.s header; kerntools 040-support-c-d7.md §5b].
The card number is therefore the rank by address.

The onboard 710 is not an AutoConfig board, so it reuses the **Gayle IDE glue pattern** (port
`src/ide_sd_rows.py` + `src/ide_sd_glue040.s`):

- `a4kt_sd_rows`: the base's table with every existing row (by relocation), plus **one row** carrying an id no board
  has. I propose `0x0710a400`.
- `a4kt_sd_glue040.s` wraps init()'s single `jsr autocon`. That id is answered by `a4ktpresent(&base)`, the GD + G0-G3
  gates (§2), which live **in the a4091 object**. Every other id goes to autocon unchanged.
- **Sort key, not bus address.** As with `ide_sd_key`, the glue hands insert() a rank:
  - default `0xffffffe0`: sorts after every real board and before IDE's `0xfffffff0`. So the **Z3660 stays card 0
    and the onboard 710 is card 1**, the intended shape.
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
before anything else, and clear latched SIP/DIP the way a4091init already does. The A4000T Kickstart's NCR scsi.device **does**
leave them enabled (variant 3: SIEN `AF`, DIEN `3D`), and an unclaimed level on the 710's interrupt line would repeat until
the first I/O reaches a4091init. I believe that line is INT2 (PORTS) [I], but polling makes the answer irrelevant
once the chip is quiesced. The same applies in principle to the A4091/A4092 ROM's handover [I]; it is low risk on an
idle chip, and the metal cells will show it.

## 5. DMA reach into Z3660 DDR

- **The A4000T's 710 is a motherboard master**, like the A3000 SDMAC, not a Zorro III master through Buster like the
  A4092 [I]. The port author's measurement shows the motherboard case working: A3000 SDMAC DMA into a Z3660's CPU-local
  `$08000000` aperture, 6147 segments, all must-stay-zero counters 0 [M, 2026-10-01]. Separately, AmigaOS
  has booted from this A4000T's onboard 710 on its real 060 [M, 2026-09-25].
- **The A4092 cells answer the other question** (Zorro III through Buster, A4000D), so their result does not transfer
  either way. **The onboard case needs its own coherence cell (T2).** Once the A4092 DMA reading lands, record it next
  to T2 as the Buster data point.
- **The ROM driver already aims the onboard 710 at Z3660 RAM** [M, variant 3]. DSA, TEMP and DSP hold `0x0800xxxx`.
  Whether its DMA **lands** there is the next cell (T0b, §8), and it needs a SCSI device on the A4000T's onboard bus.
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

An earlier plan recorded N12 as blocked because "amiberry does not model the $DD0000 onboard 53C710". That is **superseded**: the
model is in the fork [S amiberry src/gayle.cpp:647-745, ncr_scsi.cpp `ncr710_io_bget_a4000t`]. It is enabled by
`chipset_compatible=A4000T` (`cs_mbdmac == 2` adds ROMTYPE_SCSI_A4000T, cfgfile.cpp:7044-7060) or by
`scsi_a4000t=true`, with units via `scsi<N>_a4000t`, and an A4000T Kickstart taken from roms/ by id (R075 or R076).
Amiberry's DIP bank reads `0xff`, so host ID 7.

| Cell | Rig | Shows |
|---|---|---|
| N12a probe matrix | A4000T config / A4000 AGA config / A3000 ECS / A4000 under the three `unmapped_address_space` settings | found / absent with no fault / G0 skip with the A3000 SCSI boot undisturbed (the DL-08 shape) / absent on all three |
| N12b data | A4000T + 060 (+ R-060Z Z3660 for card 0) | GSIO INQUIRY then READ(10), raw dd and a UFS tree equal to host truth, D42 invariants, Z3660 = card 0 and 710 = card 1; the key-0 variant roots on the 710 as card 0 |
| N12c order | the A4092 + 710 rows; the chained IDE + 710 glue | the drop rule as §3 predicts; both glue ids answer |
| T0 metal | A4000D and A4000T under AmigaOS | read-only dump of `$DD0000`-`$DD00FF`. **A4000D: hang at first touch; A4000T: hang at `$DD0000` and at `$DD0040`, chip uninitialised** (§2, T0 result). Next: variant 3, preset 7 (A4000T ROM init), one byte at `$DD0062` |
| T0b metal, AmigaOS | A4000T, preset with the A4000T ROM (47.115 + `kick060_scsi`), a SCSI disk on the onboard bus (a ZuluSCSI with a known image is ideal), termination settled | the NCR scsi.device lists the unit. Copy a known file or region off it (e.g. a 32 MiB `dd`-style read through the device, or a file whose host checksum is known) and compare with host truth. Record DSA/DNAD after the transfer (byte/long reads at `+0x40`, read-only), to see the `0x08xxxxxx` targets. **Shows: onboard-710 DMA reach into the Z3660 DDR as a motherboard master.** No Amix needed |
| T1 metal | A4000T, KD060-ZT, Z3660 root, ZuluSCSI on the onboard bus | attach line, probe answer, data equal to host truth |
| T2 metal | as T1, copyback (`hat_cm_ram 0x20`) | coherence digest for the motherboard-master path into `$08xxxxxx` |
| T3 metal | A4000T Kickstart with scsi.device (or `scsi710.kick`) | route (b): root on the onboard bus |

### 8a. Decoding the T0b reads

**(1) The lane rule.** The 710 sits big-endian at `$DD0040`. A longword read at `$DD0040 + N` (N a multiple of 4)
returns the registers at byte offsets N, N+1, N+2, N+3 in bits 31:24, 23:16, 15:8, 7:0. The 32-bit registers (DSA,
TEMP, DNAD, DSP, DSPS, SCRATCH, ADDER) read as their natural value. Offsets are from the reference siopreg.h (ARCH_710),
and the variant 3 dump confirms them (`$DD0044` = `00000080`: SCID `80`; `$DD0078` = `21003DE0`: DCNTL `21`,
DIEN `3D`, DMODE `E0`).

| Long at | bits 31:24 | 23:16 | 15:8 | 7:0 |
|---|---|---|---|---|
| `$DD0040` | SIEN | SDID | SCNTL1 | SCNTL0 |
| `$DD0044` | SOCL | SODL | **SXFER** | SCID |
| `$DD0048` | SBCL | SBDL | SIDL | SFBR |
| `$DD004C` | SSTAT2 | SSTAT1 | SSTAT0 | DSTAT |
| `$DD0050` | **DSA** (32-bit) | | | |
| `$DD0054` | CTEST3 | CTEST2 | CTEST1 | CTEST0 |
| `$DD0058` | CTEST7 | CTEST6 | CTEST5 | CTEST4 |
| `$DD005C` | **TEMP** (32-bit) | | | |
| `$DD0060` | LCRC | CTEST8 | ISTAT | DFIFO |
| `$DD0064` | DCMD | DBC (24-bit) | | |
| `$DD0068` | **DNAD** (32-bit) | | | |
| `$DD006C` | **DSP** (32-bit) | | | |
| `$DD0070` | **DSPS** (32-bit) | | | |
| `$DD0074` | SCRATCH (32-bit) | | | |
| `$DD0078` | DCNTL | DWT | DIEN | DMODE |
| `$DD007C` | ADDER (32-bit) | | | |

Corrections to the staged read list:
- `$DD005C` is **TEMP**, not DNAD. DNAD is `$DD0068`.
- `$DD006C` is **DSP**, and DSPS is `$DD0070`.
- Read byte registers with **byte** reads; the variant 3 long at `$DD0060` disagreed with the byte reads. The 32-bit
  registers read cleanly as longs.

**(2) SXFER** (byte at `$DD0046`, or bits 15:8 of `$DD0044`). On the 710 [S siopreg.h:321-328]: bit 7 DHP, bits 6:4
TP = sync period code, bits 3:0 MO = sync offset (maximum 8). **Offset 0 means asynchronous; a non-zero offset means
synchronous was negotiated.** SXFER is reloaded at every selection from the driver's per-target value, so it shows
the last selected target. With one unit on the bus, that unit.

**(3) What to expect after a completed READ through the ROM driver.** Z3660 DDR here is `$08000000`-`$0FFFFFFF`
(cpu_ram 128 MB at `$08000000`). The A4000T also has **motherboard fast RAM at `$07000000`-`$077FFFFF`**, and chip RAM
is below `$00200000`.
- **DSA and DSP/DSPS:** the ROM driver's command table and its RAM copy of SCRIPTS. Variant 3 already showed
  `$0800xxxx` (DSA `0800BF38`, DSP `0800C274`, DSPS `00000468` = the last INT code). Expect DSA/DSP in the same area
  after the run.
- **TEMP:** the SCRIPTS call-return address, also in the SCRIPTS area.
- **DNAD after completion is NOT the data buffer.** It is the next address of the last DMA move, usually a SCRIPTS
  fetch or the status/message byte. In variant 3 it equalled DSP. A post-run DNAD therefore proves nothing about where
  the data landed.
- **Stale or garbage looks like:** `00000000` or `FFFFFFFF` in DSA/DSP after a successful transfer; addresses outside
  any RAM (e.g. `$40xxxxxx` Zorro III, `$00Dxxxxx` I/O); lane patterns like the `$DD0060` anomaly (re-read as bytes);
  or a DSA/DSP that does not move between two different commands, when the driver allocates per command.

**(4) The pass criterion for T0b** ("onboard-710 DMA reaches the Z3660 DDR as a motherboard master"):
1. All netdd pieces read through `scsi.device` unit 0 match the truth image `ec8d8d24…` per piece, except a piece named
   in advance as liable to drift (the root block).
2. **The data buffers were in DDR.** Sample DNAD **during** the transfer: a second task loops read-only longs at
   `$DD0068` while netdd runs. Most of the time is data phase, so most samples are data-buffer addresses. At least
   one, and preferably most, samples must fall in `$08000000`-`$0FFFFFFF`.
3. DSA/DSP stay in RAM (no garbage per (3)).

**The caveat, the ROM driver's bounce:** a scsi.device may DMA into its own chip-RAM or motherboard-fast-RAM buffer
and then copy to the caller. The registers show it. Data-phase DNAD samples in `$00000000`-`$001FFFFF` (chip) or
`$07000000`-`$077FFFFF` (motherboard fast) mean the 710 never wrote the DDR. In that case T0b is **inconclusive**,
not failed. Rerun with netdd's buffer forced into DDR (AllocMem from the DDR range), or log netdd's buffer address,
and check whether DNAD follows it. Also log netdd's buffer address in every run, so the samples can be matched to
it.

## 9. Effort

| Piece | Estimate |
|---|---|
| a4091: the onboard mode (per-card offsets, DCNTL, key translation, G0-G3 probe, DIP host ID, attach quiesce, ctlid), both builds, gates | 1-1.5 days (S-M) |
| port: rows + glue, chained IDE + 710 glue (mostly ide_sd_* reuse) | about 1 day (M) |
| kerntools: KD060-ZT family, stamps, gates | 0.5-1 day |
| amiberry rig + N12a-c | about 1 day, if the model behaves as read |
| metal T0-T3 | about 1 bench day; T0 can run any time, read-only |

**Total: M-L, about 4-5 days.**

T0 is done (the window answers after the A4000T ROM's NCR init; Gary is closed negative). The critical path is the open A1 decisions, then T0b (needs onboard-bus hardware), then the a4091 code, then the port glue, then kerntools, then N12, then
T1-T3.

**Open decisions:**
1. Sort key: default (710 = card 1) vs 0 (710 = card 0).
2. Row order against an A4092 in the same box.
3. Whether a KD040-T sibling is wanted.

## 10. The module form (S5-06, 2026-10-27; metal half S5-07)

This section is the design for the module world: contracts C4-1 v3 (sd_register, the rank classes), C4-2 v3 (§8's
A4000T row), C4-5 v8 (DMA), C2-1 (motherboard id 3, `a4000t-710`), 20 §6 (the `mobo:` registry). §1, §2 (T0), §4,
§5, §8a still hold. §3 and §7 are superseded.

### 10.1 The target split

- **One source, a second object.** `src/a4091-wr.c` built with `-DA4091_MODULE -DA4091_A4KT` is the module
  `a4kt710`. The A4091 module and the static driver are unchanged; their objects are pinned.
- **Why a separate object:** C4-1 §4.1. A module declares one rank class, and the A4091 is `zorro` while the onboard
  chip is `mobo`.
- **Proposed names:** module `a4kt710`; C3-5 short name `a4kt710`, so the packages are `a4kt710-k30` / `a4kt710-k46`
  (pkginst `a4kt71030` / `a4kt71046`, 9 bytes).
- **The differences are compile-time constants** of the second target, not runtime switches, so neither object
  carries the other's branches:

| | A4091 / A4092 / A4770 (`a4091`) | A4000T onboard (`a4kt710`) |
|---|---|---|
| `.moddata` `match` | `zorro:0202:54,zorro:c0de:01,zorro:c0de:02` | `mobo:a4000t-710` |
| `rank` | `zorro` (class 2) | `mobo` (class 3) |
| Discovery | `autocon()`, up to 4 boards | none: one controller at the fixed base `$DD0000`, behind the gate (§10.2); c = 0 |
| Registers | base + `0x800000` | base + `0x40` |
| Register writes | reg + `0x40` (the write shadow) | direct (offset 0) |
| DCNTL | `0x00` | `0x20` (EA, "connect _SLACK/_STERM") |
| Host ID | 7 | DIP bank: longword at `$DD3000`, `& 7`, read once after the gate (amiberry reads `0xff`, so 7) |
| Attach | first-touch `bprobe` of ISTAT (k46) | the gate, then SIEN = DIEN = 0 and latched SIP/DIP cleared: the A4000T ROM driver leaves SIEN `AF` and DIEN `3D` enabled (variant 3) |
| D42 `ctlid` | `0x02020054` | `0x00000003` (C2-1 id 3) |
| sd name | `A4091 SCSI` etc. | `A4000T onboard SCSI` |
| Map | k46 `dev_kvmap` NCS; k30 `sptalloc` | the same calls, for the `$DD0000` page and the `$DD3000` page. Never the identity alias: the k30 identity map is cacheable (N109's decode) |

### 10.2 The gate (M-A4T1): never touch `$DD00xx` undeclared

T0 (§2) settles the constraint: on a Z3660 box an access to `$DD00xx` hangs the bus forever unless the A4000T ROM's
NCR driver has initialised the chip. No CPU probe, and no `bprobe`, can make that safe (Gary's timeout is closed
negative). A `mobo:` key always matches at load (C4-4 §1, `dlm_plat_match`), so the module's `_load` is the gate.

- **G-D, the declaration (required): the Kickstart's NCR tag** (dlm's choice, contract C4-2 v6 §8.1, 2026-10-27).
  - `_load` maps the 512 KiB Kickstart at physical `0xF80000` read-only (k30 `sptalloc`, k46 `dev_kvmap`).
  - It looks for a valid ROM tag: `0x4AFC` at an even offset, `rt_MatchTag` its own address, `RTF_COLDSTART` set,
    and `rt_Name` inside the image and exactly `NCR scsi.device`.
  - Every A4000T Kickstart in the ROM store has that tag, and no A3000 or A4000 one does. exec runs every
    cold-start tag before the strap, so the tag means the chip was initialised. An A4000T on an A4000 Kickstart
    (A4kOS323) has no tag and is refused.
  - No loader bytes and no DDI name: kabi stays 1.2.
  - **The parameter `declared`** (int, default -1): -1, the scan decides; 0, never touch the window; 1, touch it
    without the scan (the owner's override).
  - **Known limit, unmeasured:** an A4000 running a T ROM passes the scan. `declared=0` is its override.
  - kmem: `a4kt_declared`, `a4kt_tagoff` (the tag's offset), `a4kt_gate` (which gate said no: 1 G-D, 2 G0, 3 the
    map or G1, 4 G2).
- **G0, chipset.** VPOSR AGA. Not AGA means no access at all, which keeps the A3000's WD33C93 untouched.
- **G1, G2: read-only, after G-D.** `bprobe` of ISTAT `$DD0062` (byte), then the fingerprint, all byte reads:
  - ISTAT reserved bits 0 and not `0xff`;
  - DSTAT DFE (`0x80`) set while SIP/DIP are clear;
  - CTEST8's high nibble is the revision (`2` on the tower, variant 3);
  - the same reads twice agree.
- **No gate passes:** `ENXIO`, silent, zero accesses under `$DD0000`. The host test asserts the zero with a mock
  that fails the run on any access to the window.
- **The stock phantom** (`autocon()` answering `0x0202F003` at `$DD0000`) stays the floor's problem: both module
  kernels carry the W-D7 gate (kern30m: support.c.patch `a3kscsi`; kern46m: kernel-support-probe-inject). The
  floor's `mobo:a3000-wd` probe is VPOSR-gated, so it never touches the A4000T's window. M-A4T1 verifies both.

### 10.3 The rank and the card order

`rank=mobo`, C4-1 class 3, after `z3660` and `zorro`, before `ide`. That replaces §3's open decisions (sort key,
row order):

| Box | Cards |
|---|---|
| A4000T + Z3660 root (the tower today) | z3660 card 0; the onboard 710 card 1 (`ced0` for id 6) |
| A4000T, no Z3660 driver (cardless or a stock accelerator) | the onboard 710 card 0 (`c6d0`) |
| A4000T + a Zorro SCSI board (once the tower's Zorro bus is repaired) | z3660, then the board, then the 710 |
| + Gayle IDE | IDE last |

### 10.4 What stays common with the A4091

Everything past discovery is the A4091 path:
- the queue path and its SCRIPTS;
- the DSA table, the `dma_alloc` area (status line, clear line);
- the C4-5 sequence: prepare, `dma_addr`, arm, complete, the refused arm, the clear-line sync;
- the misaligned-read bounce;
- the A4-22 bus reset and the A4-24 re-arm;
- the trace policy (silent selection timeout);
- `_halt` (the init path's abort and soft reset);
- the host harness: two more arms, `a4kt-k30` and `a4kt-k46`, with a mock board at `$DD0000`.

### 10.5 Interrupts

v1 is polled, as the A4091 module is (C4-2 §3 allows it): no `root_defer`, the attach quiesce above. INT2 through
`root_defer` comes with the A4091's, later.

### 10.6 DMA: the open risk

The 710 is a **motherboard bus master** (§5). The port measured an A3000 SDMAC, also a motherboard master,
reaching a Z3660's DDR at `$08000000` cleanly [M, 2026-10-01]. For the A4000T's 710, though:
- T0b, its own DMA reach, has no recorded result that I can find;
- AmigaOS booting from it proves nothing here, because the ROM driver may bounce.

So:
- **k30:** the provider bounces every segment at or above `$08000000`. That is correct whether or not the 710
  reaches the DDR.
- **k46:** the provider is the identity (C4-5), so it **assumes** the 710 reaches the DDR. M-A4T1 must include
  M-DMA1's byte compare: a raw read of a known region equal to host truth, and `cp` + `sync` identical.
- **If k46 fails the compare,** the k46 provider needs a bounce for this controller. That is a C4-5 change, dlm's.

### 10.7 Tests

| Row | Where | Shows |
|---|---|---|
| H-A4T | host, both lines | gate negative: ENXIO with zero window accesses (no declaration; not AGA; declared but the fingerprint fails); gate positive: one registration (c 0, `$DD0000`, rank 3, the name); +0x40 reads, direct writes, DCNTL `0x20`, host ID from the DIP mock, the attach quiesce; the queue cases of the A4091 arms |
| N-A4T1 | amiberry, k46 then k30 | `chipset_compatible=A4000T` (or `scsi_a4000t=true`), units `scsi<N>_a4000t`, an A4000T Kickstart (R075/R076): root on the onboard bus, card 0 without a Z3660, card 1 with one; raw read and `cp` + `sync` byte-identical. **The model answers reads without the ROM init, so it cannot reproduce the hang**: emulation covers the data path and the order, not the trap |
| N-A4T2 | amiberry, an A4000 (D) config | the module in the generation, no declaration: ENXIO, nothing touched, the boot undisturbed |
| M-A4T1 | the A4000T, metal | (a) A4kOS323 (no NCR init), the module in the generation: ENXIO, no hang, cold boots; (b) A4000T Kickstart: attach line, the onboard 710 as card 1 next to the Z3660 root, M-DMA1's byte compare, halt pass; (c) the onboard root as card 0 (no z3660scsi in the generation) |

### 10.8 Status (2026-10-27)

- Built: `a4kt710` (src/a4kt710.c, module/a4kt710/), modcheck ok on k46.1.2 and k30.1.2. The A4091 module and
  the static objects are byte-identical.
- Host: `make -C test/host check`, arms `a4kt-k30` and `a4kt-k46`, 12/12 each (the gate negatives with zero
  window accesses, `declared` both ways, the attach, the host ID, `_halt`), mutation-checked.
- Next: N-A4T1/N-A4T2 in amiberry (the Bench), then S5-07 on the tower with M-DMA1's byte compare mandatory.

### 10.9 Effort, and what was asked

- **Effort:** code and host tests about 1 day; amiberry rows about 0.5 day; the loader declaration is dlm's (size
  theirs); metal is the Bench's.
- **Asked of Amix and dlm, answered 2026-10-27:**
  1. the declaration channel (§10.2): the Kickstart NCR tag, kernel-side (C4-2 v6 §8.1);
  2. the names `a4kt710`, pkginst `a4kt71030` / `a4kt71046`: agreed;
  3. v1 polled: agreed.

### 10.10 Not supported: the Z3660 in 030 mode (2026-10-28)

`a4kt710` is **unsupported** when the Z3660 runs in 030 mode (`UAE_030_MMU`, `amix_mode` on), the k30 boot of
M-S474b. Three blockers, each enough on its own:

1. **No declaration.** The 030 boot runs the A3000 Kickstart (A3kKS31), which has no `NCR scsi.device` tag
   (§10.2). With `declared=-1` the gate refuses before `dma_alloc`: `a4kt710_load` returns `ENXIO` at
   src/a4091-wr.c:1528-1529. `declared=1` does not help: the A3000 Kickstart never initialises the 710, so a read
   of `$DD0040` on the real bus is the §2 (T0) hang; with `amix_mode` on the read reaches blocker 3 instead.
2. **No DMA memory.** In `amix_mode` the firmware hides the real motherboard SIMMs at `$07000000` on purpose (one
   memlist region, no coalesce; Z3660 `Z3660_emu/src/uae/uae_emulator.cpp:1195-1210`). All fast memory is the
   Z3660's bind above `$08000000`, so the k30 provider finds no region a bus master reaches and turns DMA off
   (amix-dlm `core/plat/k30/line.c:186-218`; contract C4-5 v11 §5.4). `dma_alloc` returns 0 and `_load` returns
   `ENOMEM` (src/a4091-wr.c:1534-1539).
3. **The window is not the 710.** In `amix_mode` the firmware maps `$DD0000` to its emulated A3000
   WD33C93/SDMAC (Z3660 `uae_emulator.cpp:1101-1105`), so the CPU cannot reach the real 710 at all.

The supported way to use the onboard 710 is the real-060 k46 line (A4000T Kickstart, §10.7 M-A4T1). On the 030
boot, z3660scsi roots the box (C4-5 §5.4).

