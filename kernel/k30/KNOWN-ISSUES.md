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

- **A write of whole pages that did not start at an 8 KiB boundary of the file could leave the pages before it in that
  8 KiB reading old memory contents** while the disk held the right data (stock, both kernel lines; fixed in cut -73).
  ufs writes through 8 KiB windows of the file (segmap) aligned to 8 KiB offsets; for a whole-page write at a nonzero
  offset into its window (2, 4 or 6 KiB in) it created the window's first pages instead of its own, without reading
  them, so they kept their frames' old contents: a read of the window's start then returned an earlier block of the
  file, zeros or another file's data until those pages left the cache. Seen with 2 KiB and 4 KiB writes once the file
  outgrew the page cache, never with 8 KiB writes at 8 KiB offsets. The trigger is the offset within the window, not
  within a filesystem block: on a filesystem of 4 KiB blocks a block-aligned 4 KiB write can meet it too. Amix's ufs
  rwip passed the window's base to segmap_pagecreate instead of base + offset, as SVR4's source does. Fixed in the ufs
  module (4 bytes, `tools/rwippc030.py`); on -72 and earlier, write in whole 8 KiB pieces at 8 KiB offsets or keep such
  files smaller than free memory.
- **A whole-page write into a hole in the middle of a file could leave the rest of the newly allocated block reading
  the disk's old contents**, possibly another file's former data (stock, both kernel lines; fixed in cut -75, whose
  rule replaces the one of cut -74, a cut that was not released). For a write of whole pages as_iolock granted
  pagecreate: the pages written were created without being read, and ufs_bmap allocated the new block alloc-only,
  without reading or zeroing it, so the block's other pages were read from the disk block later. Among a file's first
  12 blocks (the first 96 KiB with 8 KiB blocks) this happened wherever in the block the write landed; past them only
  when the write reached the block's last page. From cut -75 rwip's call of ufs_bmap looks the block up first
  (`src/ufs_bmap_hf.c`, `tools/bmaphf030.py`; ufs_bmap with S_READ, which allocates nothing, under the inode lock rwip
  holds for the real call). For a hole alloc-only is turned off, so ufs_bmap reads the new block before setting it in
  the inode: what it allocates -- the whole block, or up to the fragment the write ends in when the block is the
  file's last -- is zero-filled, the write's pages are copied over it, and the rest of a last block, past the end of
  the file, is zeroed by rwip when the file grows over it, as stock. A block already allocated keeps alloc-only: a full
  block allocates nothing, so the pages written are created unread and the others are read from the file's own block,
  as stock (correct because rwip gives segmap_pagecreate the write's address, the -73 fix above, which the hole fix
  needs: the build refuses it without); the file's last block, held as a fragment, is grown by realloccg and read
  whatever alloc-only says. `ufs_hf_holes` and `ufs_hf_kept` count the two. Cut -74 had kept pagecreate only for a
  write that starts at its 8 KiB window and covers it or runs to the end of the file, as Solaris's ufs_wrip does, which
  made rewrites of pages not in the cache read them first. Not changed: `swap -a` on a sparse regular file
  (ufs_allocstore) still allocates its holes without zeroing them, so the swap file holds old disk data until swapping
  overwrites it. `tests/sparsehole` in emulation, 16 files after a removed filler file of 0x5a: with 2 KiB written 2
  KiB into each of six direct and six indirect holes, stock 2.1c had 188 and 206 of 288 direct pages wrong, -73 40,
  and 0 indirect on both; with the writes on each block's last page, stock had 176 of 288 indirect pages wrong, -73
  122 direct and 205 (16 MiB) or 242 (64 MiB) indirect; -74's rule 0 at 16 and 64 MiB, -75 0 at 16 MiB. Its `eof` mode (a
  write 2 KiB past the end into a new block) and `keep` mode (a write from a new block's start to the end, then the
  file extended past it) found 0 of 48 on -73, -74 and -75 alike: they are regression cases, and a 0 there cannot show
  that the new blocks landed on the filler's. Its `rewrite` mode, 2 KiB rewritten 2 KiB into blocks already
  allocated whose other pages are not in the cache (the case -75 leaves alloc-only), found 0 of 288 direct and 0 of
  288 indirect pages wrong on -73 and on -75, read at once and again after the cache was pushed out; on -72, whose
  rwip gave segmap_pagecreate the window's base, 96 and 96 read wrong at once (each block's first page) and 0 after.
  On -75, with `ufs_hf_holes` and `ufs_hf_kept` read from the running box after each mode, the rewrite mode's 192
  writes (16 files of 12 blocks) went the kept way (`ufs_hf_kept` up 193) and every hole mode's writes the zero-fill
  way (`ufs_hf_holes` up by them and by the 6144 whole new blocks of the test's own filler and eviction files, `kept`
  up 1). The cost of -75's rule, from `tests/wcost` at 64 MiB with time()
  in whole seconds, one boot of each kernel, two passes, 20000 random 4 KiB rewrites of pages not in the cache of a 96
  MB file: 27 and 26 s on -73 against 24 and 25 s in the same run on a trial build with -75's ufs module (byte for byte
  but its build id; its kernel lacked -72's IP read queue mark), and 24 and 25 s on the -75 cut in a run of its own;
  -74's rule took 30 and 29 s against -73's 23 and 23 s. So -75's rewrites are not measurably slower than -73's. 64 MB
  written by 4 KiB pages cost the same on all three; copied by 8 KiB, whose new blocks -75 now zero-fills in memory
  before writing them too, it took 49 and 47 s on the trial against -73's 46 and 43 in the same run (47 and 46 on the
  -75 cut), within -73's own spread between runs (52 and 42 s). On -73 and earlier, fill holes in the middle of a file
  with whole 8 KiB blocks, or write such files from start to end.

## Faults and memory protection

- **A raw write from a buffer mapped write-only is refused** with EPERM until a read fault has made the page readable
  (cut -72, `src/segvnprot030.s`). A raw read into one works.
- **Reading one page of a write-only mapping makes the whole mapping readable** (cut -72): the read is allowed by
  adding read permission to the segment, and `/proc` and later core dumps report it readable.
- **Not proved on a real 68030.** The emulator was used throughout; these depend on what the chip does and are written
  to be safe either way: the read half of `tas` and `cas` reporting both the RM and RW bits in the special status word
  (`tools/rmwfault030.py`); the SSW's RW bit on instruction fetches; and the fault storms seen in emulation before the
  emulator's return-from-exception fix, which point to the emulator and not the kernel.

- **A 68030 short of memory could hang in `hat_unload` or `hat_swapout`, or find a page it still used freed** (stock;
  fixed in cut -74). Seen as installs at 16 MiB stopping for good, the netinstall every time (5 of 5, from -71 to a
  build with -73's code), the CD and floppy install 1 time in 5. When the swapper shrinks a process's segment table,
  hat_growsdt gave the table's tail back at table + units * 512 instead of table + units * 64: hat_sdtfree then
  cleared bits in whatever page that address fell in, on a data page the head of its mapping chain, so chain walks
  never ended, and a page left with no bits was freed while still mapped. Found in emulation with every store to a
  page's chain head watched (the watch named hat_sdtfree, called from hat_growsdt). No 68k hat source exists to
  compare with: the unit is the one hat_sdtalloc and hat_sdtfree themselves use (64 bytes: bit << 6, (address & 2047)
  >> 6), and hat_growsdt counts its new size in those units (entries * 8 + 63 >> 6) and clears entries up to that many
  units. From cut -74 the second shift is gone (`tools/growsdt030.py`, 2 bytes). With the fix the 16 MiB netinstall
  completed 3 times of 3 (a build with -73's ufs and this fix), and an install under the same watch logged no bad
  store to a chain head.

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
