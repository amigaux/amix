# Changelog

## 2026-10-31 — P-36 W6: link.d entry; zen0 configured through /etc/inet/interfaces (f0385cb, c69b2bf)

The driver ships its /etc/inet/link.d entry, link.d/z3660eth: `zen	/dev/zen	0	51` (tab-separated, three # header
lines); ifup probes the units; on a module kernel `kbootset major z3660eth` gives the major, 51 is the static-kernel
fallback. userland/S99zen, network-config.zen and the /etc/default/zen text are gone: amix userland/base's ifup chain
replaces them. bringup.sh stays as a bench aid, address from its command line only. README and ZEN0-BRINGUP §3
configure zen0 by an /etc/inet/interfaces line; the S99zen era stays as history (§3.2). src/ and module/ unchanged.

## 2026-10-30 — build notes, evidence voice, NOTICE credit (aa9de1b, 2f350c2, 49a8bba)

BUILD.md drops the old build box's notes and keeps three points as plain advice (FTP push/pull with NFSv2 for large
files, spelling out the types instead of rico.h's, checkunix alone is not a gate). The evidence dossier's first-person
process lines are reworded as neutral documentation; ZEN0-BRINGUP's citations into it follow. NOTICE credits the
STREAMS/DLPI skeleton of src/z3660eth.c: Commodore's aen.c (Keith Gabryelski) by way of Ignacio Soriano's hydra-amix;
no stock code is quoted. NOTICE sha256 7bf25198 → f7c22823; objects unchanged.

## 2026-10-30 — builds inside amix (b1be3ea, ba4fb98, f201889, 164d3bb, c2ea34b)

README points at amix's kernel/k30, kernel/dlm and ../z3660scsi, with a builds-inside-amix paragraph (`amix-build
z3660eth`, the dlm kit). module/Makefile defaults DLM to $(TOP)/../../dlm, as a4091 and z3660scsi do. Sibling paths in
BUILD.md, driver.conf, docs, NOTES, src comments and tools/ use amix's dirs; the z3660scsi cite 9ceada6 is now 90d03ae.
Old review ids are worded for outside readers. The userland samples carry no address: ZEN_ADDR, ZEN_NETMASK and
ZEN_GATEWAY come from the box's /etc/default/zen. Objects unchanged (KIT_REV 084dc21): module k30 af24613d, k46
86fe050b; static k30 c9370806, k46 37185507.

## 2026-10-30 — moved in from amix-z3660net

jusii/amix-z3660net rx-backpressure 93fd0d3 (79 commits) moved into amix kernel/drivers/z3660eth by subtree merge after
a filter-repo rewrite: lab addresses → 192.0.2.x, the project domain → example.com, local paths → repository names,
the station files removed and the one commit that touched only them pruned (78 commits); the tip differs only in 8
documentation/sample files, the driver, module and tools are byte-identical; old→new map in docs/history-map.txt
(tip 93fd0d3 → a2d7e88). privacy-check --all: 0 hits (was 42).

## 2026-10-29 — module/Makefile: DLM defaults to ../amix/kernel/dlm (ab8eeda)

The dlm kit moved into the amix monorepo; `?=` kept. BUILD.md §9 and the README show the new kit location. Built
objects byte-identical to an explicit-DLM build (8/8 files).

## 2026-10-26 — z3660eth module 1.0.0-5: every board register access is armed (ZS-05) (c5f7a46)

The Z3660 FPGA's address capture delivers back-to-back accesses at (previous AND this). In this driver that lost the INT6
acknowledge (R $1A8 → W $104 landing on MODE $100, the "[RTG] Error mode: 255" on both boxes), the ETH_RX strobe (R $1A4 →
W $194 landing silently on ACC_OP $184 — one of the two ways into the ring wedge), the TX trigger (R $1A4 → W $190 → $180),
the station MAC at attach (R $198 → R $19C reading $198) and gave false rx_overrun breaks (W $194 → R $1A4). Every register
access is now one asm block at IPL 7 with a covering read before it (CONFIG armed by $1A4, ETH_RX by MAC_LO $19C, ETH_TX by
itself with the result read in the block; MAC/cursor/INT_STATUS reads preceded by a same-register read). Shared code: the
static objects change too (k30 c9370806, k46 37185507; the kernels of record take them at the stage-4 cut). Modules k30
022c012b, k46 ca3a2b05 (19751 B file, 13537 B image). Object gate module/check-zs05.py (`make zs05`; mutants caught). Round
trips: RX frame 2→4, poll tick 1→2, TX 2→3, INT6 2→4. Future firmware must keep the $19C/$1A4/$190/$198/$1A8 reads side-effect-free.

## 2026-10-26 — z3660eth module 1.0.0-4: the RX ring resyncs past a wedged sentinel (2a15a4c)

On metal (S3-46, A4000D, intr=6) zen0 died under a 5 ms ping flood: the firmware showed "backlog 32 fetched 0" — the
cursor sat at slot 0 carrying the serial the driver had already consumed, so every drain took the ring as empty while the
firmware filled the other 31 slots and dropped the rest; permanent, and intr=0 can die the same way. Two ways in: a lost
ETH_RX strobe, or the firmware's catch-up race (10c7501 ethernet.c:734-744, unlocked against the RX ISR). With intr=6 the
drain now detects it (z3660eth_rx_wedged: at slot k > 0 always a lost strobe; at slot 0 only when slot 1 holds serial+1 or
+2 and slot 0 reads the same twice), strobes once past the slot, loses at most one frame; counters z3660eth_rx_resyncs,
z3660eth_rx_resync_last. Objects k30 8d0e75f0, k46 a928fd2b (19379 B file, 13177 B image); static unchanged. The two
stray -1 stores are not this driver (its stores are offsets 0x104/0x190/0x194, values 0/1/24/pktsize).

## 2026-10-26 — z3660eth module 1.0.0-3: the intr=6 self-test passes inside the IPL-4 open (3e6b696)

The stock qattach() calls a driver's open with SR 0x2400 (k46 0x4ee1c, k30 0x5190c), so the PORTS that the level-6 test
handler raises stayed pending for the whole spin and 1.0.0-2 always printed "zen: interrupt self-test failed; polled",
emulator and metal alike (S3-44-3, N86/N87). The open now spins on the level-6 flag only and waits for the level-2 flag
with up to 4 one-tick timeout/sleep rounds (the stock delay() idiom). Module objects k30 abf530d7, k46 9dfe0294 (12945 B,
modcheck ok); static objects unchanged (k30 c2d6225e, k46 142e2486). NOTES.md: the IPL-4 fact.

## 2026-10-26 — z3660eth module: refusal lines, _unload undoes _load, parser test (be0ef63)

`_load` prints a `zen:` console line before every failure return (if_attach used to fail silently; the probe-failure lines
end "module not loaded" in the module form). `_unload` (unload=never, reached only by the core's lf_fail) undoes `_load`
before any open: board interrupt off, if_detach, unmap — it used to return EBUSY, leaving the ifstats link to the core's
backstop and the sptalloc pages mapped. `make -C module test` runs a host test of the parameter parser (18 cases; no bug
found). Static objects unchanged. Modules k30 0c5c3580, k46 8356712a. The first module boot's error 22 is the core's
(a boot-class STREAMS driver gets no slot), not the driver's.
Module release 1.0.0: module/VERSION holds the package version (`1.0.0-1`, the same on both lines) for
z3660eth-k30 / z3660eth-k46, pkginst zeth30 / zeth46 (amix-dlm C3-5 v4 §1.1); amix-packages reads it.
Package revision `1.0.0-2` (module release still 1.0.0): the package gains the device node /dev/zen0 (c 51 0) as a
pkgmap device entry (C3-5 v4 §1.2, amix-dlm 568b9ac); module object unchanged (k30 0c5c3580, k46 8356712a).

## 2026-10-26 — z3660eth module on kit d197198: one Master, $match added (e510330)

The kit's mk/module.mk does the per-line work: module/Master (no $cpu; DEFCPU gives 68030/68040), per-line Master generation
and the custom object rule gone; the Master carries `$match zorro:144b:01,mobo:z3660-window` (C3-6 §2, amix-dlm 393d1cd).
Modules k30 3628335f, k46 e83b097e (18397 B; only .moddata changed); COMMON warnings now only ifnet and rawintrq; static
objects unchanged.

## 2026-10-26 — z3660eth module built with amix-dlm's ABI kit (3a89f54)

`make -C module` builds build/<line>/mod.d/z3660eth for k30 and k46 through the kit's mk/module.mk (kits from amix-dlm
6ef133e); Master from module/Master.in; the module form includes sys/amixddi.h; modcheck ok on both lines (34 COMMON warnings:
ifnet/rawintrq from <net/if.h> plus the driver's own globals); modules 18365 B, k30 8c5cad3c, k46 2bd8654c; static objects
unchanged (k30 c2d6225e, k46 142e2486). tools/build-module.sh and src/z3660eth.modkeys removed.

## 2026-10-26 — z3660eth as a loadable module, source half (859dfc1, bee712c; amix-dlm S3-25, C3-6)

Building with -DZ3660ETH_MODULE turns the same source into the module form: z3660eth_load(params) / _unload (EBUSY,
unload=never) / _halt and MOD_DRV_WRAPPER; major 51 is data in z3660eth_drvdata (d_str only); if_attach replaces the ifstats
link. INT6 receive is optional behind intr=6 (default polled): the level-6 handler only acknowledges, masks and flags; the drain
stays at IPL 4, from a level-2 handler raised through PORTS (intrl2=1) or the poll tick (intrl2=0); attaches at the first open
after a software EXTER self-test, polled on any failure. Static objects byte-identical (k30 c2d6225e, k46 142e2486).
tools/build-module.sh builds one object per line and checks it against amix-dlm's DDI v1 lists (32 imports, all listed).

## 2026-10-21 — RX back-pressure: hold frames in the card's backlog when IP's queue is full (b896afc, 120cab3, 9787f88; review T-47)

The receive service no longer frees a frame that canput() refuses: it leaves the slot in the card's backlog and
resumes on the next poll once the queue drains. Before, every full IP queue cost an uncounted drop below IP (about
115 per 4 MiB push on the tower). Kernel-memory counters rx/delivered/couldnt_put/holds/resumed. Backlog slots are
counted by stepping, never by a constant shift (060 line rule). Metal-proven in the 261021-71/-72 kernels on both
boxes: push 25–30 → ~350 KB/s together with the port's 16 KB TCP queue-limit patch and the firmware's receive ring.

## 2026-10-13 — Publication scrub before the first push since August (fb2059e)

README licence section and a new NOTICE carry the Amiga Corporation trademark wording; NOTES marks the AB-04 evidence
as local-only and relink-040-z3660.sh as private port tooling; ZEN0-BRINGUP links amix-installng by its GitHub URL.

## 2026-09-27 — AB-04: free the mapping windows on a failed probe; cache the verdict (a3571ed, 586ba6f, 8449d53)

z3660eth_map() now sptfree()s both kernel-VA windows on every failure path; before, each failed probe on
the sptalloc arm leaked 33 pages (65 on the 030 line) and S99zen's 16 boot opens exhausted sptmap:
the rig's "DL-13 stall". A failed probe is cached per board (later opens return the errno without
mapping or probing again), one console line, real errno (ENXIO absent / ENOMEM no VA), z3660eth_reprobe
forgets one verdict. Object z3660eth_040.o a1f49c54 (sum -r 20612). Metal-proven inside KD060-Z (T-10).

## 2026-09-27 — Interrupt masking made real (4e75876, a33bb6c, 47092ee; review T-9)

The header no longer no-ops `spl6`/`splx` on the wrong "AMIX has none" premise: it includes the stock
`<sys/inline.h>` (spl5..7 map to `_spl4`, SR 0x2400). Three masked sections: M1 the `tx_busy` claim in
xmit; M2 open's slot publication (the RX demux could route frames up a new stream under the previous
occupant's sap/RAW flag); M3 the GET_STATUS snapshot. The hydra-idiom whole-wput mask and the mask on the
`tx_busy` release were deliberately not added. Design in NOTES.md "Interrupt masking". Rebuilt with
gcc-cross-amix 7a1d727: z3660eth_040.o b93ce42d… (sum -r 57252).

## 2026-09-09 — docs: the field-proven zen0 bring-up procedure; GRIMOIRE-HANDOFF cross-reference corrected (74d8564, ae808a7)

`docs/ZEN0-BRINGUP.md` records the bring-up as it was actually done on metal (major 51 verified on the
box 2026-09-09), so the next person does not rediscover it; the handoff's stale 48→51 renumber
cross-reference is corrected.

## 2026-09-01 — docs-currency sweep: README, BUILD, ETHERNET-SCOPING, BLIZZARD-F3

No code change; the public docs are brought level with HEAD.

- `BUILD.md` (`8a714a1`): §4 claimed the committed clean-gate script "predates" the `nm -u` bar
  and cited `GRIMOIRE-HANDOFF.md` §8 — contradicting the same file's own tail note, and citing a
  gitignored file no reader can open. `../amix-kerntools/tools/build-clean-net-kernel.sh` opens
  "THE BAR IS nm -u, NOT sum-recurrence", so the tail note was the true one. Both references to
  that script also spelled it as this repo's `tools/`, where it does not exist. "the locked
  two-tier routine in the project notes" now points at §7, which spells it out. The build box was
  described two ways (Amiberry + amix-golden.uae in §0, WinUAE + a config that resolves to
  nothing at the tail); the tail block is now marked the historical record. New §8 documents the
  cache gate, the kmem-readable verdict and counters, and why the direct-map arm is required.
- `README.md` (`9324b91`): cdevsw major **51** and the `/dev/zen0` (`c 51 0`) node — the two facts
  another driver author or packager needs first — appeared nowhere on the page; now in Scope.
  Layout gained `tools/`, `docs/BLIZZARD-F3.md` and `CHANGELOG.md`. "How it works" now names the
  mapping arm (direct dereference below VSECT1, `sptalloc` only above it), which the 040/060 DTT0
  free ride depends on.
- `docs/ETHERNET-SCOPING.md` (`9498305`): the banner still said the datapath was untested and
  named Phase 2/3 as NEXT — retitled to PROJECT STATUS — SHIPPING ON REAL HARDWARE with the metal
  result. §10.1's heading claimed the driver "does explicit line-granular 030 cache ops, always",
  which it has never done; heading and DECISION bullet now record that the prescribed 030 ops were
  designed and never shipped, and why. §5's Q-COHERENCY block and the §0 confidence table/verdict
  are annotated in place (the as-written review record is preserved). §8 gains a head note naming
  Q5 and Q6 as the only two items still open and a per-item marker on the nine that closed. §4.3
  said "seven" over a list of six and never acquired the DL_ERROR_ACK/DL_BADPRIM arm (`364333c`);
  both fixed. Four sites still carried 2026-07-27 for work that landed 2026-07-30 (`c949380`,
  `f12b2d5`) — `b9991e3` had fixed only driver.conf. The private `wip-ethernet` memory pointer is
  dropped and the `wip-ethernet`/`amix-base` branch plan marked superseded.
- `docs/{BLIZZARD-F3,ETHERNET-SCOPING-evidence}.md` (`98e269c`): `3b97dca` missed five
  `amix-z3660` → `amix-z3660scsi` sites in the evidence dossier and the SCOPING sources footer.
  BLIZZARD-F3's four **measured** citations — including both of the pass line's own anchors —
  pointed at the gitignored `GRIMOIRE-HANDOFF.md`; the values are inlined and re-cited to
  README §"Status" and `src/z3660eth.c:46-47`, with the handoff line numbers kept as internal
  provenance.

## 2026-08-24 — z3660eth: 040/060 cache maintenance behind a run-time gate (BLIZZARD F3 round 2)

The dead `Z3660ETH_CACHE_FLUSH` `#ifdef` is gone. `src/Makefile` never passed the -D, so the
block it hid had been compiled out of every kernel that ever booted and was four defects deep
when finally read. Maintenance is now always compiled and gated at run time by `z3660eth_cache`
(0 = off, the shipping default; 40 = 68040 DC, 60 = 68060 DC, poked through /dev/kmem), so the
same relocunix serves the 030 and the 040/060 lines and the code is reviewable rather than
invisible.

- **F3-M0 (`571f4d4`)** — attach-time assert that the free ride is real: `z3660eth_ci_check()`
  captures DTT0/DTT1/CACR and requires `DTT0 = 0x003fc060` to leave the whole low 1 GB, both
  mapped spans included, cache-inhibited. Verdict readable through /dev/kmem as
  `z3660eth_ci_ok` (0 unchecked / 1 verified / 2 FAILED) with `z3660eth_maint_on` and
  `z3660eth_sptalloc_unsafe`; `z3660eth_ci_enforce` decides whether a failure warns or refuses
  the attach with ENXIO. The `sptalloc` mapping arm is declared **unsupported with a live data
  cache** — its VA has no relation to the board's physical address, and CPUSHL/CINVL select a
  line physically, so maintenance disarms there rather than discarding some other subsystem's
  dirty line.
- **F3-M2 (`1bdaecb`)** — the previously identical PUSH/INVAL pair is split into real `cpushl`
  and `cinvl` raw `.word`s (f468 / f448, encodings measured both directions against as 2.8.1),
  because CACR.DPI gates CPUSHL's invalidate on the 68060 and push-as-invalidate silently stops
  invalidating there. Six line-op counters (`z3660eth_push_n`, `_inv_n`, `_push_bytes`,
  `_inv_bytes`, `_sync_n`, `_range_ovf`) are kmem-readable.
- **Docs (`4820333`, `084a945`, `df23adc`, `d71886c`, `b4371d4`)** — round 2 pre-registered
  before it was written (`docs/BLIZZARD-F3.md`); the "no PG_CI bit" claim corrected to an 030
  fact, not a universal one (the 040/060 kernel writes a two-bit leaf CM instead); the three
  ETHERNET-SCOPING §10.1 claims that do not carry to 040/060 marked; the result appended with
  nothing above it edited; README's cache paragraph rewritten.
- **Evidence (object-level, no metal):** `nm -u` byte-for-byte identical to the baseline; all
  six 040/060 instruction sites (`movec` ×3, `cpushl`+`cinvl`, `cinvl`, `nop`) proven dominated
  by a `tstl z3660eth_cache` / `beq` in the disassembly; the comment-only correction commit
  byte-identical at the object level (`z3660eth.o` and `ld -r exp`, sha256 `736afcc2…`);
  `-Wall` unchanged.
- **Nothing here is evidence about a real cache.** The §7 metal A/B soak is still owed, and a
  green run with zero counters would be a failed run.

## 2026-08-18 — z3660eth: page-size-agnostic window geometry (ded6ef4)

The frame-window math is now bytes-primary: ZZ_FRAME_BYTES (0x20000) and
ZZ_REGS_BYTES (0x1AC = register file 0x104..0x1A8 read as longs) are the
constants; ZZ_FRAME_SPAN/ZZ_WINDOW_TOP come straight from ZZ_FRAME_BYTES and
ZZ_FRAME_PAGES/ZZ_REGS_PAGES round UP from bytes over NBPP (sptalloc sizing on
the non-direct-map path only). ZZ_FRAME_SIZE stays 2048 — that is the firmware
per-slot PROTOCOL STRIDE, not a page size, and only coincidentally equals NBPP
on this kernel. The old page-count-first shape put ZZ_WINDOW_TOP — the b89c5d2
direct-map admission bound — one rework away from landing on exactly
ZZ_TXFRAME_OFF on a 4096-byte-page kernel, i.e. no longer covering the TX
staging frame. Five #if/#error assertions now fail the build if the shape is
reversed. Cross-toolchain evidence: 64/0x20000/0x07EF0000 at NBPP=2048 and
32/0x20000/0x07EF0000 at NBPP=4096; z3660eth.o and ld -r exp byte-identical
to the pre-change build (no behavioural change on the shipping kernel).

## 2026-08-13 — z3660eth: direct board mapping below VSECT1 (b89c5d2)

z3660eth_map() takes the physical base as the kernel VA when the whole span stays
under 0x40000000 (section-0 early-termination identity map — AMIX does NOT use the
68030 TT registers; ETHERNET-SCOPING §10.1); sptalloc kept only for a board at/above
VSECT1 (autoconfig_rtg). The metal 0x10000000 case now draws 0 sptmap pages (was 65).
Metal-proven: flew in the Route-A v3/v4 kernels at 88 MB with zen0 up.

## 2026-07-31 — on-box patch scripts made fail-closed (half-patch audit packet B)

- `tools/patch-kernel.sh`, `tools/patch-makefile.sh` (`603c719`): the name-wide
  `grep z3660eth` guard is replaced by ROW-SCOPED / SHAPE-SCOPED pre-flight, each edit
  is its own independently guarded ed invocation, and every arm is POST-VERIFIED in the
  file — ed's exit status is 0 through all three measured failure modes.
  Outcomes are now distinguishable: rc 0 `ALREADY PATCHED` / rc 0 `PATCHED:` /
  rc 4 `REFUSED (<verdict>)` with the file untouched / rc 5 `HALF-PATCHED` naming the
  failed arm and its `.bnkorig`.  Verdicts share kerntools `cdevsw-gate.sh`'s vocabulary
  (FREE, OURS, TAKEN, HALF, MISSING, MOVED, + AMBIGUOUS/NOANCHOR/NOKERNELC).
  Fixes audit F1 (a pre-48→51-renumber tree was reported ALREADY PATCHED, leaving slot 51
  unclaimed while renumbered `/dev/zen0` nodes opened 51 — silent no-ethernet) and both
  F5 half-patches (respelled `aeninfo` extern anchor; stripped `# kdb/exp` OBJ anchor
  leaving the rule-only state the guard then hid forever).  Trees already in either half
  state are now REPAIRED, not reported as done.  The replacement cdevsw row and its
  `/*51=z3660eth*/` tag are byte-unchanged (cross-repo drift-guard contract).
- `tools/patch-selftest.sh` (new, `603c719`): benchless host-side battery — 22 fixture
  scenarios per shell under `sh` and `dash`, bashism lint, an `ed` shim that drops an arm
  to exercise the post-verify, and the row-drift check kerntools' gate selftest depends on.
- `BUILD.md` (`d382108`): new §3b documents the outcome table, the verdicts, the optional
  path argument and the selftest; renumber date corrected 2026-07-27 → 2026-07-30.

## 2026-07-30 — cdevsw major renumbered 48 → 51; Q1 (AMIX level-6 servicing) resolved

Renumbered `z3660eth`'s char major **48 → 51** repo-wide (`c949380`, date note corrected
`b9991e3`). 48 was chosen in 2026-06 only because it was an empty `nostr` row on the
stock/a4091 kernel; the 2026-07 community sweep shows it is contested — `zz9000-amix`'s
`integration/kernel.c.txt` documents an unpublished dev tree using "47 for Hydra, 48 for
random, 49 for ZZ9000, 50 for sad", 49 (zz9000) and 68 (va2000) are published claims, and 47
is a live double claim by hydra and the stock 1992 `contrib/mx` driver. 51 is the lowest slot
of the ecosystem-verified-free set 51–67/69 (CDEVSIZE = 70; 7/38/39/44/45 are traps).
Convention and evidence: grimoire-amix's Major-Number Registry.
Sites: `driver.conf`, `tools/patch-kernel.sh`, `userland/{S99zen,bringup.sh,network-config.zen}`,
`BUILD.md` (carries the authoritative why-51 note), `docs/ETHERNET-SCOPING.md`,
`docs/ETHERNET-SCOPING-evidence.md` (supersession banner + prescriptive sites).
**Docs-and-config only — built kernels and shipped `/dev/zen0` nodes still carry 48 until the
next build (P5.4). A 51-built kernel with a stale `c 48 0` node opens an empty cdevsw row, and
`S99zen` only mknods when the node is absent — existing roots need the stale node removed or
re-mknod'd at P5.4.** (resolved: major 51 metal-verified 2026-09-09, see docs/ZEN0-BRINGUP.md)

Q1 RESOLVED (`f12b2d5`) — `docs/ETHERNET-SCOPING.md` §2.5 now reads resolved instead of OPEN.
AMIX does wire the level-6 autovector (`vec.s:36` → `p6int`), but `p6int` (`ttrap.s:118-134`) is
hardwired to CIA-B: it gates on Paula `INTREQR` bit 13, dismisses only Paula's latch, and calls
the single fixed handler `aciabintr`. There is no `int6_tbl` and no level-6 registration API.
So the Z3660's `/INT6` passes the gate but nothing ever acks the board, and because `/INT6`→EXTER
is level-sensitive it re-latches on every `rte` — the unbounded IPL6 storm behind the 2026-06-21
hard-lock. Confirms the shipped `ZZ_CONFIG_DISABLE` + bounded polled drain (`028c8d2`) as correct
architecture, not a workaround.

## 2026-07-26 — z3660eth defect packet (P0.3): three deferred STREAMS defects fixed

Found during the 2026-07-13 STREAMS "out of blocks" investigation and deliberately deferred then
to avoid perturbing a live RX-path hunt (that hunt closed: the wedge was the cdfs page-crossing
DMA wild write, since fixed). Host cross-build verified only — **bench/metal validation owed.** (still owed as of 2026-09-26; no run on record)

- **[HIGH] RX trailer-arm removed** (`54729bb`). `toss_packet_up_stream()` carried stock `aen.c`'s
  4.2BSD trailer decode verbatim. An ethertype in 0x1000–0x1010 made `length = (sap-0x1000)*512`
  reach 8192 and read the trailer-count word at offset up to 8208 of the 1518-byte `rxbuff`
  (~6.7 KB out-of-bounds read); the derived `trailn` could go negative, making
  `allocb(length+trailn)` smaller than the following `bcopy(..., length)` — an mblk heap overflow.
  Dead for legitimate traffic (SVR4 IP never negotiates trailers; `IFF_NOTRAILERS`;
  `ifconfig -trailers`) but reachable by any crafted frame off the wire. Deleted rather than
  repaired. **Normal RX is byte-for-byte unchanged** — proven by exhaustive case split on the
  ethertype guard and confirmed by cross-disassembly (the range test, the ×512 shift and the
  indexed OOB read are gone; the former else-arm is now unconditional; nothing else in the
  function changes). Frames in 0x1000–0x1010 now demux on that sap, bind to no stream, and count
  as `rx_no_sap` — correct handling for an encapsulation this stack never negotiated.
- **[MED] ioctl NULL-deref fixed** (`cd97e53`). `Z3660ETH_NUMBER_OF_BOARDS` and
  `Z3660ETH_GET_STATUS` dereferenced `mp->b_cont->b_rptr` with no NULL check (the same defect is
  still live in stock `aen.c`); an `I_STR` ioctl with no data panicked the kernel from any process
  able to open `/dev/zen0`. New `z3660eth_ioc_arg()` / `z3660eth_ioc_nak()` helpers add the NULL
  and short-message checks and give the driver one NAK path.
- **[LOW] three items** (`364333c`): `DL_ERROR_ACK`/`DL_BADPRIM` now emitted for unknown DLPI
  primitives (previously silently freed, hanging the DLS user); `z3660eth_tx_drain()`
  `return` → `break` (one blocked stream no longer starves the other four for a poll tick);
  `Z3660ETH_CLEAR_STATUS` / `Z3660ETH_GET_CONFIG` given explicit EINVAL-NAK case labels.

Build evidence: driver cross-compile diagnostics byte-identical to baseline at every step and
`nm -u exp` symbol set unchanged (27); full kernel cross-link green (`unix` 1575484 B, `nm -u`
resolved, `unix.brel` 29250 relocs, `relsim.py` **0 complaints**).

Owed at the next bench run: RX soak confirming normal IP/ARP unchanged + `rx_no_sap` ticking for a
crafted 0x1000-ethertype frame; the status tool's TRANSPARENT ioctl still correct plus a malformed
`I_STR` returning EINVAL instead of panicking (needs a small test program that does not exist yet);
a bogus DLPI primitive drawing `DL_ERROR_ACK`; multi-stream TX exercising the `break` path.
