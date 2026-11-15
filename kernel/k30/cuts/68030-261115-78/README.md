# Cut 68030-261115-78

The k30 module kernel, kabi k30.1.5 (abi 18c0a1c9), cut from amix `215a64ba`: -77's recipe with three guards on
the fault and panic paths, and the module core with dlm cores 0055, 0057 and 0058.

- **A user bus error on a Zorro III board is judged at the board.** When a user access bus-errors on a translation
  the MMU tables call valid, the stock `hardbus` probes the physical address as if it were a kernel virtual address.
  Below `0x40000000` the kernel maps physical memory one-to-one, so the probe reads the device. From `0x40000000` up
  the kernel's own space is page-mapped (the u-area, then the sptalloc arena, then segmap), so for a Zorro III board
  the probe read whatever kernel page had the same number, and a program drawing through a user mapping of a
  Zorro III framebuffer was killed (SIGKILL, "Hardware Bus Error @ va, (pa physical)") at offsets that depended on the
  kernel's layout, not on the board. `src/hardbus030.c` defines `hardbus_z3`, and `tools/hardbus-retarget.py` gives
  usrxmemflt's one call of `hardbus` to it. Below `0x40000000` it calls the stock `hardbus`. From `0x40000000` it maps
  the faulting physical page into the kernel for the probe (sptalloc of one page), reads it there, and unmaps it with
  `sptfree(va, 1, 1)`, which also flushes the whole ATC. A probe that faults is a dead device page: the stock warning
  and SIGKILL, as before. No map space for the probe: a warning and SIGKILL. Otherwise the access is retried; a run
  of 16 retries by one process at one address and pc, each within a second of the last, ends with a warning and
  SIGKILL. adb reads `hbg_magic` ("HBG!"), `hbg_calls`, `hbg_high`, `hbg_retry`, `hbg_kill`, `hbg_nomap`,
  `hbg_cap` and `hbg_last_pa`. The stock `hardbus` body is checked unchanged (the same 0x62 bytes as 2.1c's).
- **A root that cannot be mounted panics once.** `vfs_mountroot` names ufs and fails when the root disk cannot be
  opened, and the panic calls sync; ufs's flush followed the half-set-up root vfs (its `vfs_data` 0) and faulted in
  `ufs_update`, a second panic. The 68040/68060 port's `src/syncguard.s` (port `59e1b77`, byte for byte) replaces the
  stock sync, made weak in `fs/exp` (one byte): it returns at once while `rootdir` is 0, and skips a filesystem switch
  row not yet set up (a panic before vfsinit). Counters `syncg_magic` ("SYNG"), `syncg_calls`, `syncg_skip_root`,
  `syncg_skip_ops`, `syncg_skip_fn`, `syncg_last_i`.
- **The panic backtrace stops at the outermost frame.** The stock backtrace accepted a frame pointer only inside the
  first 64 KiB of the u-area and then read the frame's return address and the call instruction before it. The
  outermost frame's return slot was never written: it reads 0, and the walk read `0xFFFFFFFA`..`0xFFFFFFFF`, which on
  a real 68030 bus is a bus error inside the panic printer, so any panic could become a second one. The port's
  `src/btwalk.s` (byte for byte) is a frame test that accepts the whole u-area and the kernel's data and bss, wants
  each frame above the last, caps the walk at 64 frames and bounds the return address to the kernel's text before
  the walk reads through it. `tools/btwalk030.py` turns the stock test (26 bytes at `backtrace+0x6a`) into
  `bsr.l bt_frame_ok` and NOPs; the rest of the stock body is checked unchanged. Counters `bt_magic` ("BTW!"),
  `bt_walks`, `bt_frames`, `bt_stops`, `bt_laststop`, `bt_badret`, `bt_lastbadret`.
- **kabi k30.1.5.** The module core carries dlm core 0055 (a zorro match key may name product 00), 0057 and 0058
  (where console output goes is put back after a refused load and around a module's `_load`, so later console lines
  are no longer written to the message buffer twice). No new name: abi= is 1.4's.

Against -77 the shipped files differ in `unix` (hardbus030.o, syncguard.o, btwalk.o, fs/exp's weak sync, the
retargeted relocation, backtrace's 26 bytes, the module core, the build id) and so `unix.brel` (1545004 bytes),
`unix.sym` and `kabi`; `mod.d/ufs` and `mod.d/s5` differ only in the build id they carry. audio.c is -77's (3f434f35).

The build's own checks (`cut-68030-261115-78.log`): hardbus030.o, syncguard.o and btwalk.o import and export
exactly their names; the u-area is read at `u+0x730` and `u+0x864` only; one strong sync, the guard's, named from
syssync and xpanic; usrxmemflt names `hardbus_z3` and `hardbus_z3` names `hardbus`, nothing else names either;
backtrace calls `bt_frame_ok`; each checked again after the module core's splice; the 80 stock objects equal the
baseline; `mkabi --check` gives abi 18c0a1c9; relsim finds no relocation the boot loader would refuse.

Evidence, in emulation. The vehicles are the released 1.1.1 k30 image, first-booted, with this cut's files laid and
kern30m's record set to them, then a kbootset generation; the root-mount rows use the released 1.1 k30 IDE image,
because 1.1 has no Buddha root module (1.1.1's image mounts a root on a Buddha, and -78 boots it). The emulator is the
bench's amiberry `d20f842`; the rows that make a page give a bus error use the fork's `buserror_region` option, an
out-of-tree build at `56a7d38` (on `d20f842`).

- **A Zorro III ZZ9000 at 0x40000000** (an A3000, 68030, the z3660rtg object `ee17d34`), a 32-bit 1920x1080 draw
  through the user mapping four times: on this cut 4 of 4 drew their bars and no bus error was reported;
  `hbg_high` 200, `hbg_retry` 200, `hbg_kill` 0. The same row on -77 and the same emulator build: 3 of 4 draws
  killed (`User BUS ERROR ... FAULT:1`); with the board inside the one-to-one map (at 0x10000000) -77 drew 4 of 4.
- **One page of that framebuffer made to give a bus error** (0x40500000): each draw's write to it faulted, the probe
  through the kernel mapping faulted too, and the program was killed at that first fault, `hbg_kill` 2 for the two
  draws, `hbg_cap` 0, `hbg_last_pa` 0x40500000: a dead device page still ends the program, with no retry loop.
- **A Zorro II ZZ9000** (at 0x200000): the same modes, X, maptest and unload results as -77's row; `hbg_calls` 59248,
  all below 0x40000000 (`hbg_high` 0), so the stock probe decided every one of them as before.
- **The Z3660's own RTG** (A4000, the Z3660 in 68030 mode, fixed at 0x10000000): its attach lines, an X session
  that ends and one killed with kill -9, as on -77; `hbg_calls` 0.
- **A root on a Buddha** (an A4000 68030 with the disk on a Buddha, this cut as the trial generation): `PANIC:
  vfs_mountroot: cannot mount root: errno 6`, no second panic, and after Return the loader booted the previous
  generation. Read at the panic: `syncg_skip_root` 1 (`syncg_skip_ops` and `syncg_skip_fn` 0); `bt_walks` 1,
  `bt_frames` 7, `bt_badret` 1, `bt_lastbadret` 0xFFFFFFFA. The emulator logged no access below address 0 from
  backtrace and none from ufs_update while this cut ran; -77 on the same disk and machine made both (backtrace
  reading 0xFFFFFFFA to 0xFFFFFFFE, ufs_update+0x58 reading through the root vfs's empty data).
- **The same with the top page giving a bus error**, as a real 68030 bus would: -77 `DOUBLE PANIC: KERNEL FAULT`
  at backtrace+0x9c; this cut one panic and no access to that page, and after Return the loader's fall-back
  generation (-77) double-panicked the same way.
- **The fault and protection tests** (`tests/segvnprot`): vm30 passes every case it runs (physio not run), pn30's 13
  cases give the same results as on -72.
- **Updating an installed 1.1.1 k30 system**: one `apkg upgrade` (apkg 0.3.11) installed this package with kbootset
  -46, built and committed one generation, every installed module passed the new kernel's gates, the trial was
  marked good and a second boot was plain; a generation whose root record names an absent unit panicked once
  (errno 5) and the loader booted the previous generation after a power cycle; `kbootset default 1` boots -77 again.
  The kbootset of 1.1 and of 1.1.1 both take this cut's sidecar (kabi=k30.1.5).

| File | What |
|---|---|
| `SHA256SUMS-68030-261115-78` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`59e1b77`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `215a64ba`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `215a64ba`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`59e1b77`: `syncguard.s`, `btwalk.s`, and `rth1.c`, `patch_ttcompat_init.py`,
  `patch_tcp_hiwat.py`, `patch_ip_lrhiwat.py` and `kelf.py` as at `0508945`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: its three patchers make audio.c 1f43c5ff, which
  `tools/patch_audio_replies.py` makes 3f434f35).

`unix.brel` is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its symbols, and
`unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules bound to this
build. Its sums were reproduced by `cut.sh` twice on the host with gcc-cross-amix `33ebadc`, and by `../build.sh` on
the host and in the build container (`amix-toolchain:dist`).
