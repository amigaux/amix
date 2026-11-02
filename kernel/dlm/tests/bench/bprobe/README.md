# bprobe at boot: does a Zorro III bus error come back as 1?

Contract C4-2 §2 lets a root-class `_load` call `bprobe`, which `ddi.md`
marks *proc*, once a probe module has shown on both lines that it returns
at level 7 with the clock stopped. The Z3660 SCSI and ethernet modules'
fixed-window probes (`0x10000000`, read on every AGA box that has no
Z3660 AutoConfig entry) are to be guarded with `bprobe`. So the question
here is narrower and harder than C4-2 §2's: **when the CPU takes a real
bus error at an empty Zorro III address, in the root pass and in the boot
pass, does `bprobe` catch it, return 1 and let the boot go on, and how
long does the access take?**

## What was shown before, and what was not

The root-context probe `../s4-71/rprobe.c` ran on 2026-10-27 in emulation
only (Amiberry, rows N107 k46 and N108 k30), and passed: every call
returned at level 7 with the clock stopped, and
`bprobe(0x7fff0000)` gave 1 on both lines. That 1 was not a bus error.
`0x7fff0000` is above `VSECT1` (`0x40000000`), outside the kernel's
identity map (`docs/abi/ddi.md`, "Identity"), so the access had no
translation; the N107 console shows the kernel's translation-fault path
(`DBG krnxflt FAILEXIT w=2 va=7FFF0000`) just before the `-> 1` line. No
row has run on metal. The bus-error path is unproven on both lines.

## The modules

One source, `bprobe.c`, two test modules, each built per line with the
ABI kit:

| Module | Directory | Class | Runs in |
|---|---|---|---|
| `bproot` | `root/` | root, `match=always`, in no safe set | `marc_root`: level 7, the clock stopped |
| `bpboot` | `boot/` | boot, `match=always` | `marc_post` (`modadmin -B`): at the pass's own level, inside `spl7()` (level 4: `ddi.md`, no spl masks level 6), and with the status register at `0x2700` (level 7, the clock stopped) |

Each pass reads one byte with `bprobe(addr, -1)` at:

1. **the custom chips**, `0xdff004` (VPOSR): decoded on every Amiga, so 0;
2. **the empty address**, `0x20000000` (parameter `empty=`), twice. It is
   not probed when a board in the boot list covers it, or when it is at or
   above `VSECT1` (a fault there would be the MMU's again);
3. **the Z3660's `MAC_HI`** (window base + `0x198`), when `autocon`
   finds the Z3660 below `VSECT1`, then the register itself as a long (it
   is 32 bits wide; a word read gives its high half, 0): the read a guarded
   window probe makes.

A line `probing <what> at <addr>` comes before every access that can
fault, so a hang names its address. Each access is timed with CIA-B's
TOD counter, which counts horizontal syncs (64 µs a tick on PAL, 63.56
µs on NTSC, from VPOSR) and runs at any interrupt level. `bpboot` first
checks the TOD against `lbolt` over a spin. Nothing is written anywhere.
`_load` returns `ENXIO`, so neither module is ever linked. `bpboot`'s
`ENXIO` shows as `dlm: boot module bpboot not loaded: error 6`, as
expected.

## Why `0x20000000` is empty on the A4000D with its Z3660

Every claimant of the address was checked:

- **The Z3660 (real-CPU mode).** The FPGA claims only these ranges
  (`Z3660/z3660-firmware/Z-TURN/vivado/z3660.srcs/sources_1/new/z3660.v`
  279-286, dispatch 425-458): CPU RAM `0x08000000-0x0fffffff`; the RTG
  window's 128 MB block at its AutoConfig base, parked at
  `0x10000000-0x17ffffff` with `autoconfig_rtg NO`; its Zorro III RAM's
  256 MB block only when that board is autoconfigured (the bench presets
  run `autoconfig_ram NO`); the Zorro II SCSI board, the AutoConfig pages
  and the MAPROM ranges, all in the low 16 MB. Every other address goes to
  the CPLD and the motherboard (`z3660.v` 457-458).
- **The motherboard.** On the A4000, `0x10000000-0x7fffffff` is Zorro III
  space, driven by Buster. The box's only Zorro III board is the A4092 at
  `0x40000000` (devices.yaml; grimoire, the A4092 DMA record). Kickstart
  places Zorro III boards from `0x40000000`, so nothing answers below
  that except the Z3660 itself.
- **The boot list.** The module checks it too: a board whose range
  covers the address stops the probe (`... lies in board ...: not
  probed`).
- **What an unanswered cycle does: not measured.** The Z3660's CPLD
  waits for the motherboard without limit (quirk 66). What ends an empty
  Zorro III read on a real A4000 has no measured record. The one measured
  case is a different one: the A4092's ROM cycle, a board that was there
  and never terminated, which the A4000 ended with a bus error after about
  280 ms (a frame-format-4 access fault, the FSLW byte read ended by TEA,
  A4000D and A4000T, 2026-09-30/10-01). Gary never turns an unanswered
  motherboard read into a bus error; it ends the cycle with wrong data
  (grimoire, z3660-timings method law 6). So three outcomes are open, and
  the module tells them apart: a bus error caught (`empty=caught`, the
  time printed), a cycle that ends with no fault (`empty=NO-FAULT
  data=<byte>`), or a cycle that never ends (the console stops after
  `probing empty Zorro III`).
- **Why the identity map matters.** The address is below `VSECT1`, so it
  needs no mapping: k30 reaches it through the page tables' early
  termination, k46 through DTT0 (cache-inhibited), and the access reaches
  the bus as the Z3660 drivers' own would. It is a read: no device state
  changes, and nothing waits in the 68060's store buffer.
- **The local-I/O range is not touched.** No address in
  `0xd80000-0xdfffff` is read except the custom chips; quirk 66's
  never-terminating reads are there.

On a box without a Z3660, `0x10000000` is the same kind of address
(Zorro III space with no responder), so the outcome at `0x20000000` here
is the evidence the two driver fixes rest on: only `caught` supports a
`bprobe` guard. It is evidence for this CPU card's
bus path; another accelerator's bus logic would need its own row.

## Build and stage

```
make -C root KIT=<amix>/kernel/dlm/build/kit/k30 LINE=k30     # and boot/, and k46
KABI=k30.1.2 sh ../s3-modpkg.sh root/build/k30/mod.d/bproot k30 <out-k30>
KABI=k30.1.2 sh ../s3-modpkg.sh boot/build/k30/mod.d/bpboot k30 <out-k30>
```

That gives the objects in `<out>/etc/conf/mod.d/` and their apkg records
in `<out>/var/apkg/kpkg/mod-bproot` and `mod-bpboot` (gate 1). The kit's
compiler pin must be the kernel's: the 1.1 kernels (k30 -68, k46 -56/-57)
and the 1.1 kit are gcc-cross-amix 33ebadc. Any kbootset from -34 on
composes it.

## The row: emulation first, then metal, per line

| Step | Command | Expected |
|---|---|---|
| 1 | copy `<out>` onto the root; `kbootset build`; `kbootset commit` | the `build` file has `module bproot root … match=always` (no `safe=1`) and `module bpboot boot … match=always`; `generation N committed` (a trial) |
| 2 | boot it; keep the console (serial, or the frames) | the lines below |
| 3 | after the run: remove both objects and both records, `kbootset build`, `kbootset commit` | the probes are gone from the next generation |

The root pass prints before the root mounts:

```
bproot: level 7, lbolt <x>, VPOSR <v> (PAL, TOD tick 64 us), params ''
bproot: root pass: probing custom chips at dff004
bproot: root pass: bprobe custom chips (dff004, read) -> 0 (no fault) in <t> us (...), level 7, lbolt unmoved
bproot: root pass: probing empty Zorro III at 20000000
bproot: root pass: bprobe empty Zorro III (20000000, read) -> 1 (bus error caught) in <t> us (...), level 7, lbolt unmoved
...                                               (again; then the Z3660 MAC_HI read and its word)
bproot: root pass: RESULT good=ok empty=caught z3660=ok level=ok

(with no fault instead: "empty Zorro III read without a fault: byte <b>"
and "RESULT good=ok empty=NO-FAULT data=<b> ...")
```

The boot pass prints the TOD check, then the same probes three times
(`boot pass`, `boot pass at spl7 (level 4)`, `boot pass at level 7`),
each with its `RESULT` line. Every line goes to the console: on the 1.1
boxes kernel messages reach the message buffer only after `modadmin -K`
(`prt_where` 0x2 at boot), and the buffer keeps 2000 bytes. Keep the
console (serial, or the frames).

**Reading the result.**

| `empty=` | Meaning |
|---|---|
| `caught`, with its time | the bus error came back as 1, in the root pass (level 7) and the boot pass at levels 0, 4 and 7: a `bprobe` guard holds on this line. The time is the bus's timeout (none is measured for an empty address yet) |
| `NO-FAULT data=<b>` | the cycle ended with no fault and returned `<b>`: open bus, Gary-style wrong data, or a board. Expected under Amiberry. On metal it means `bprobe` cannot tell an empty window from a present one here: a driver must also check an identity the open bus cannot fake |
| `MIXED` | the two reads disagreed: report both lines |
| the console stops after `probing empty Zorro III` | the cycle never ended, or the fault was not caught: `bprobe` is not a guard on this line. The trial is not marked good (the hang comes before run level 2's `kbootset mark-good`), so power-cycle and the loader returns to the default generation (try-once, L8). Report the line and the line before it |
| a panic naming a bus error | the same verdict, with the panic text as evidence |

The times hold only if the TOD check agrees with `lbolt` (about 260
TOD ticks a clock tick at HZ 60 on PAL). A check of 0 µs means the TOD
reads did not reach the CIA, and the times are void, but not the
results.

`good=` must be `ok` and, for `bproot`, `level=ok` (it is `FAIL` when a
call left level 7 or `lbolt` moved). `z3660=ok` with `MAC_HI long 80`
on a Z3660 whose MAC starts `00:80` shows the guarded identity read works.

**Emulation proves the good path only.** In Amiberry an empty Zorro III
address reads as open bus, so `empty=NO-FAULT` is the expected emulator
result. Run both lines there first: it shows the modules load, run and
return at level 7 before a metal session is spent. On the Z3660 in an
emulated-CPU mode (the A4000D's 68030 runs), the empty read goes through
the card's ARM emulator, and the result records that emulator's
behaviour, which is what 1.1 gets on that configuration.

## Hashes (built 2026-11-02 against the 1.1 kits, gcc-cross-amix 33ebadc)

| Object | File bytes | SHA-256 |
|---|---|---|
| `root/build/k30/mod.d/bproot` | 5351 | `393956944b2cc30f611e6cdbc09816a87f7d38771012f692532392d8312be865` |
| `boot/build/k30/mod.d/bpboot` | 5545 | `2d27e4bd02fa809a822f6f38df060a82bc8e2838fd36dbed28994e14b0f7b299` |
| `root/build/k46/mod.d/bproot` | 5323 | `eae9dd5bf4e4f1d5b5a76d27e3105408f435a2ed01f856a200477e9f63e7816d` |
| `boot/build/k46/mod.d/bpboot` | 5517 | `1f0bef5ae69a2c1aa9693eb1a58613dc8543c6803452f8a14e15496448ff74a5` |

The 2026-11-02 metal rows ran the previous build (k30 5285f23f/6f0d9802, k46
07c71d1f/c9f83343), which read MAC_HI as a word and printed its high half, 0.
