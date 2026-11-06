# Known issues: the k30 module kernel

What a user of the 68030 kernel may meet, with the cut it was found against. Each entry says what is seen, what is
known about it, and what to do. Measurements are from emulation unless the entry says otherwise.

## Swap

- **A large swap area is refused, at most 16 x maxmem pages per area** (cut -72). `swap -a` prints `SC_ADD failed` and
  `swap: Not enough space`, and nothing is added, when the area's anon array (16 bytes for every 2 KiB page of the
  area) would take more than an eighth of `maxmem`, would not fit in one free run of the kernel's map space (kvseg),
  or would leave kvseg no free run of 1 MiB. The first area, the one the kernel adds at boot, is exempt from the eighth
  and the 1 MiB rule. Sizes measured to work on 68030-261106-72's guard: see `docs/swap-areas.md`. Use smaller areas, or
  several.
- **A refused `swap -a` takes about 4 s** when the array could not be had at once (no run of kvseg that large, or pages
  short): the kernel tries five times a second apart. A refusal by the eighth comes at once.
- **Other errors from `swap -a` can come back as `Not enough space`** (cut -72). The guard decides before swapadd opens
  the device and checks the area against it, so an area past the end of its device (EINVAL), a device that is not
  there (ENXIO), one that cannot be opened (EACCES) or one that fails (EIO) is reported as ENOMEM when the area is also
  too large for the eighth, or when memory or kvseg is short. Check the device name and the area's size first.
- **The 1 MiB rule can be decided on an old reading** (cut -72). The guard reads kvseg's largest run before its first
  try; when a try fails and it waits, other allocations meanwhile can make it refuse an area that would have been
  harmless, or pass one that leaves the run under 1 MiB. A refused add can be tried again.
- **An area of 512 KiB or less can still be refused by the 1 MiB rule** (cut -72). Its array comes from kmem's pools,
  and a pool that has to grow takes a few pages out of kvseg's largest run.
- **The guard reads kvseg's map without blocking interrupts** (cut -72). A large allocation from an interrupt at the
  same moment can make it misjudge the largest run once; the effect is one refused, or one wrongly allowed, add.
- **A `swap -a` racing a `swap -d` of the same area, or interrupted while it opens its device, can stop returning**
  (cut -72). The guard reads the list of areas before swapadd's open, and the delete is not held off; a signal inside
  that open leaves the guard's lock taken. Seen only in review of the code, not in a run. Stock's `swap -a` could hang
  in the same places.
- **Memory for processes (malloc, stack, fork) is limited by swap, whatever the RAM** (stock). Anonymous memory is
  reserved against swap space; with little swap a large-RAM machine still refuses large processes. Add swap.

## Files

- **A large file written at random offsets can read back wrong blocks** (stock and every kernel since). A file that is
  appended to, then rewritten and read at random offsets, as a swap file is, can read back wrong blocks once it
  outgrows the page cache. Seen in emulation on the stock 2.1c kernel and on every kernel since; not yet checked on
  real hardware; under investigation. Until it is fixed, keep such files smaller than free memory.

## Faults and memory protection

- **A raw write from a buffer mapped write-only is refused** with EPERM until a read fault has made the page readable
  (cut -72, `src/segvnprot030.s`). A raw read into one works.
- **Reading one page of a write-only mapping makes the whole mapping readable** (cut -72): the read is allowed by
  adding read permission to the segment, and `/proc` and later core dumps report it readable.
- **Not proved on a real 68030.** The emulator was used throughout; these depend on what the chip does and are written
  to be safe either way: the read half of `tas` and `cas` reporting both the RM and RW bits in the special status word
  (`tools/rmwfault030.py`); the SSW's RW bit on instruction fetches; and the fault storms seen in emulation before the
  emulator's return-from-exception fix, which point to the emulator and not the kernel.

## Networking

- **An NFS server whose hosts file does not map its own node name to its address answers no remote mount**. `mount`
  from another machine times out (`RPC: Timed out`) while `ping` and `rpcinfo -u` to mountd and nfsd answer;
  restarting mountd, nfsd or all of NFS does not help. Give `/etc/inet/hosts` a line `<address> <nodename>` before NFS
  starts, then restart NFS. Seen on k30 and on the 040/060 kernel.
- **A program that writes and then closes a TCP connection without SO_LINGER can lose the last data it wrote** (stock
  `tcpclose`, both kernel lines): data still queued at close is dropped. Seen as short ftp downloads and an ssh session
  that ends without its exit status.

## Programs

- **A login shell hung up at the wrong moment can loop at PC 0 and grow its heap** (stock libc, both kernel lines).
  libc's `sigaction` stores the new handler before it tells the kernel; a signal in between calls address 0, and
  `sh`'s SIGSEGV handler returns to it. `tests/sigrace` shows it on stock 68030-261103-71 and on this kernel alike.

## Not explained

- **One shutdown stalled after `INIT: New run level: 0`** on development build 68030-261105-98 in emulation: no
  further output, the machine still answering on the network. Not seen in the later runs that finished their load on
  this kernel or on 68030-261103-71. Cause unknown; not called fixed.
- **One install hung in `hat_swapout`** on 68030-261103-71 in emulation (16 MiB, a package install under memory
  pressure): one page's mapping chain named the wrong table entry, and the unbounded walk never ended. Not seen again
  in 22 later installs and fork-and-swap stress runs on two emulator builds and two kernels, with the chains checked
  from outside every 20 to 30 s and, on one emulator build, every store to a chain head checked as it was made. Cause
  unknown.
