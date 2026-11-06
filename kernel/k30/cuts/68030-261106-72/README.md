# Cut 68030-261106-72

The k30 module kernel, kabi k30.1.4 (abi 18c0a1c9), cut from amix `9cd652d` with -71's recipe. Against -71:

- **kvseg is 8 MiB.** The kernel's map space (syssegs..kvsegmap, handed out through sptmap) was a fixed 4 MiB, of
  which kvm_init's page array takes 60 bytes per page of memory; on a 64 MB machine little was left for kmem's pools,
  swap areas' anon arrays and every kmem request over 4 KiB. `tools/arena8m030.py` moves the five sites that hold
  the size together (mlsetup's sptmap seed, sysseginit's page tables, kvm_init's segment, kvsegmap and kvsegu), keeps
  the segmap window's width, and points kseg and unkseg at a 64-byte run table (`src/arena8m030.c`). The page
  tables behind it take 8 KiB more low memory.
- **kmem_freepool and kmem_free wake the sleepers.** A kmem request over the pool size that found no free run
  slept on Km_OsizeWanted, and the two places meant to wake it never did (`tools/kmemwake030.py`).
- **The swap guard caps an area.** An add that swapadd answers from its list (an area being deleted added back, the
  same area again, an overlap) gets no new array. Otherwise an area whose anon array would take more than an eighth of
  `maxmem` is refused with ENOMEM at once; one that finds no free run of kvseg is tried 5 times a second apart (about
  4 s); and one whose array out of kvseg would leave no free run of 1 MiB is refused, so kmem's other large requests
  are not left sleeping. The first area, swapconf's at boot, is exempt from the eighth and the 1 MiB rule. A first area
  clamped to its device is resized without letting go of the run (`src/swapguard030.c`).
- **A denied access is a signal or EFAULT, never a fault taken for ever.** segvn refuses a fault on a page with no
  permission and a write without write permission (`src/segvnprot030.s`); a read of a write-only page succeeds.
  The read half of `tas` and `cas` faults as a write in usrxmemflt, so it gets the copy on write or SIGSEGV
  (`tools/rmwfault030.py`). A core dump leaves pages with no permission as holes instead of ending at the first one
  (`src/coreseg030.c`).
- **IP's lower read queue mark is 0x10000** (`--ip-lrhiwat-fix`, the port's `patch_ip_lrhiwat.py` at `0508945`):
  stock 0x2000 is less than the fragments of one 8 KiB NFS reply, and the A2065 driver dropped frames when canput
  failed. Measured in emulation on an 8 MiB host-to-guest ftp push: 197 to 198 drops at 0x2000, 70 at 0x4000, 0 at
  0x10000.

| File | What |
|---|---|
| `SHA256SUMS-68030-261106-72` | the seven files of record, paths relative to the cut's `usr/sys` |
| `cut.sh` | the recipe: `cut.sh OUT` with the inputs below; its sums must equal the file above |
| `port.pin`, `paula.pin` | the port (`0508945`) and paula (`1b2736d`) commits the cut takes, which `../build.sh` fetches |

Inputs (`cut.sh` names each by an environment variable):

- amix `9cd652d`, `kernel/` only (git archive): `kernel/k30`, `kernel/drivers` (z3660scsi and a4091 as patch
  directories), `kernel/dlm` (the module core, its tools and the k30/k46 kits, KIT_REV `9cd652d`);
- amix-system (the relink kit), gcc-cross-amix (`33ebadc`) and gcc14-cross-amix at the `toolchain/*.pin` commits;
- amix-040-060-port at `port.pin` (`0508945`: `rth1.c`, `patch_ttcompat_init.py` and `patch_tcp_hiwat.py` as at
  `31edbc6`, and `patch_ip_lrhiwat.py` with `kelf.py`);
- amix-paula at `paula.pin` (`1b2736d`, `--audio-paula`: audio.c 1f43c5ff).

`unix.brel` (1543028 bytes) is the shipped form (as `/stand/k30/unix`), `kabi` is its sidecar, `unix.sym` holds its
symbols, and `unix` is the ET_REL it was made from. `mod.d/ufs` and `mod.d/s5` are the carved core-tier modules
bound to this build. Its sums were reproduced by `../build.sh` on the host (gcc-cross-amix `33ebadc`) and in the
build container (`amix-toolchain:dist`), and by `cut.sh` twice on the host with the host's own m68k binutils.
