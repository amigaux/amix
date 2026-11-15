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
baseline; `mkabi --check` gives abi 18c0a1c9; relsim finds no relocation the boot loader would refuse. What the
three guards do on a running box is shown by the rows recorded with the package.

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
