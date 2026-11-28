# libsockfix — the stock socket libraries without their per-socket heap leak

Amix 2.1's socket library comes in two variants:
- `/usr/lib/libsockhost.so` takes host names from `/etc/hosts` only;
- `/usr/lib/libsockdns.so` also asks DNS.

`/usr/lib/libsocket.so`, the name programs load, is one of them. amix-base's `ifup` links it to `libsockdns.so` when a name server is set. This package ships both files, each with 55 bytes changed in one function, `_s_alloc_bufs`, so that the library no longer loses a buffer every time a descriptor number is reused for a socket. Everything else is the stock file, byte for byte.

| | sha256 | size | `sum -r` |
|---|---|---|---|
| stock `libsockhost.so` (core; `system/MANIFEST.sha256`) | `29975421b4e4cb0066c9877b13b44dcbce0eb9bc41599c3dc79691d92516a67d` | 54032 | 47564 |
| fixed `libsockhost.so` | `f37c4fac4081ae3fda44e2ba02dcd3f7b1fc8945254c94d22e7085bf1453fba9` | 54032 | 64706 |
| stock `libsockdns.so` (core) | `607477a5385db153450d717a02ba7c013ae2fb660768f6a3e5a7988be6bdc816` | 67636 | 14470 |
| fixed `libsockdns.so` | `798b1ae661d9288a66e913d7873df6c0cc9c55eea72170c416c65e1e8bd74832` | 67636 | 49390 |

Package: `libsockfix` (instance `libsockfx`), category `library`, set `base`.
- **Removable.** Removing it puts the stock files back.
- **Nothing is compiled, and no binary is kept here.** `build.sh` takes the two stock files from amix-system at its pin and checks each against `system/MANIFEST.sha256`. It checks the 60 bytes it rewrites, rewrites them, reads them back, and checks the result's sha256.

## Licence

The libraries are Commodore's, AT&T's and Amiga Corporation's, published like the rest of the Amix system files under the approval described in amix-system's README (section "Licensing"): `LicenseRef-Amix-System`. The changed bytes, the recipe, the `libsockfix` command and this README are ours, under MIT (`LICENSE.amix` in `/opt/amix/doc/libsockfix`).

## The fault

For every socket it creates, the library keeps a link (56 bytes, one per descriptor number, on a hash chain) and a buffer that `_s_alloc_bufs` allocates for it. The buffer is 48 bytes plus two of the transport's sizes plus 4.

Only the library's own `_s_close` frees the buffer, and only its error paths call that. A program closes a socket with `close(2)`, which is the C library's, so the link and its buffer stay behind. The next `socket()`, `accept()` or DNS lookup that gets the same descriptor number finds the old link (`add_silink` returns it) and allocates a new buffer into it. The old buffer's pointer is overwritten and the buffer is lost.

Measured on a 68030 and a 68060, as the growth of the process's break, with the same numbers on both:

| operation, then `close(2)` | lost per operation |
|---|---|
| `socket()`, Internet UDP or TCP | 199–208 bytes |
| `socket()` or `connect()`, UNIX domain | about 4.4 Kbytes |
| `accept()`, TCP | about 200 bytes |
| `accept()`, UNIX domain | about 4.4 Kbytes |
| `gethostbyname()` through `libsockdns.so` | about 200 bytes |

`shutdown()` releases nothing. The growth lasts until the program exits. On a 68030 the break counts against the swap reservation, and a box whose reservation is full can no longer fork.

Who notices:
- **The X server.** An X server kept by `dtlogin` or `xdm` loses about 4.4 Kbytes for every local client connection, roughly 1 Mbyte for a day of desktop use and tens of Mbytes a month.
- **inetd and dropbear:** about 200 bytes for every connection they accept.
- **Any program** that opens and closes sockets in a loop loses memory at that rate. Two such loops filled a 68030's 64 Mbyte swap reservation in about 15 minutes, after which logins failed.

## The bytes

Offsets are file offsets, which are the library's own addresses (its text is mapped at offset 0). The changed range is the 60 bytes from the function's GOT load to its `errno` store.

| file | range | stock bytes | fixed bytes |
|---|---|---|---|
| `libsockhost.so` | `0xb2ee`–`0xb329` | `4bfb 0170 0000 376c 246e 0008 206e 000c 7030 d0a8 0008 2400 d4a8 0004 5882 2f02 4878 0001 61ff ffff 9d60 2548 0010 6600 0014 720c 2875 0170 0000 0010` | `4bfa 376c 246e 0008 2f2a 0010 6100 9da0 206e 000c 7030 d0a8 0008 2400 d4a8 0004 5882 2f02 4878 0001 61ff ffff 9d5c 2548 0010 6600 0010 720c 286d 0010` |
| `libsockdns.so` | `0xe37e`–`0xe3b9` | `4bfb 0170 0000 3af4 246e 0008 206e 000c 7030 d0a8 0008 2400 d4a8 0004 5882 2f02 4878 0001 61ff ffff 80bc 2548 0010 6600 0014 720c 2875 0170 0000 0010` | `4bfa 3af4 246e 0008 2f2a 0010 6100 80fc 206e 000c 7030 d0a8 0008 2400 d4a8 0004 5882 2f02 4878 0001 61ff ffff 80b8 2548 0010 6600 0010 720c 286d 0010` |

In each file 55 of the 60 bytes differ (`cmp -l`). `_s_alloc_bufs` in `libsockhost.so`, stock on the left and fixed on the right. `libsockdns.so` is the same code at `0xe376`, with its own displacements:

```
stock                                         fixed
b2e6 4e56 0000      link   fp,#0              b2e6 4e56 0000    link   fp,#0
b2ea 48e7 202c      movem  d2/a2/a4-a5,-(sp)  b2ea 48e7 202c    movem  d2/a2/a4-a5,-(sp)
b2ee 4bfb 0170 ..   lea    (GOT,pc),a5 [8 B]  b2ee 4bfa 376c    lea    (GOT,pc),a5 [4 B]
b2f6 246e 0008      movea  8(fp),a2   si      b2f2 246e 0008    movea  8(fp),a2   si
                                              b2f6 2f2a 0010    move.l 16(a2),-(sp) si->buf
                                              b2fa 6100 9da0    bsr.w  free@plt (0x509c)
b2fa 206e 000c      movea  12(fp),a0          b2fe 206e 000c    movea  12(fp),a0
 ...  size = 48 + two udata sizes + 4  ...     ...  the same, 4 bytes later ...
b312 61ff ffff 9d60 bsr.l  calloc@plt         b316 61ff ffff 9d5c bsr.l calloc@plt (0x5074)
b318 2548 0010      move.l a0,16(a2)          b31c 2548 0010    move.l a0,16(a2)
b31c 6600 0014      bne.w  0xb332             b320 6600 0010    bne.w  0xb332  (same target)
b320 720c           moveq  #12,d1  ENOMEM     b324 720c         moveq  #12,d1
b322 2875 0170 ..   movea  (errno,a5),a4 [8B] b326 286d 0010    movea  16(a5),a4 [4 B]
b32a 2881           move.l d1,(a4)            b32a 2881         move.l d1,(a4)  (stock from here)
```

- **The two 8-byte loads take their 4-byte forms with the same operands,** the way libcfix found its room. That frees the 8 bytes for `move.l 16(a2),-(sp); bsr.w free`, so the old buffer is freed before the new one is allocated.
- **On a new link the field is 0:** `add_silink` gets its links from `calloc`. The stock `free(NULL)` returns at once.
- **The pushed argument needs no pop.** The epilogue restores the registers relative to `fp` and `unlk` restores the stack.
- **From `0xb32a` (`0xe3ba`) on, every byte is stock.**
- **Checked on the host:**
  - no relocation lands in the range;
  - `bsr.w` reaches `free`'s PLT slot (0x509c and 0x6488);
  - the 68060 scanner passes both files.

## Install, removal, and `/usr/lib/libsocket.so`

The two files go in under the stock names, the way libcfix lays `libc.so.1`. Nothing is written in place:
- pkgadd lays each file under a temporary name and renames it over the stock one;
- the package's scripts work the same way.

core keeps its claim on both paths. While the package is installed, the contents database lists them under both packages, with the fixed files' size and sum.

**Why the stock names and not a third file.** amix-base's `ifup` decides by inode, at every boot and at every DHCP renew:
- when a name server is set and `libsocket.so` is not the same file as `libsockdns.so`, it runs `ln -f libsockdns.so libsocket.so`;
- `ntpsync` reads "DNS on" from the same inode test.

A fixed library under a third name would be undone at the next boot and would read as DNS off. Under the stock names, whatever `ifup` links is already fixed, so amix-base needs no change.

**The postinstall** runs `libsockfix link`:
- pkgadd's rename separates `libsocket.so` from the file it was linked to.
- The script links `libsocket.so` back, again by rename, to the fixed file of the variant it was:
  - **DNS:** the same file as `libsockdns.so`, or `libsockdns.so`'s bytes (stock or fixed);
  - **hosts-only:** anything else, including core's own separate copy.
- So a DNS box stays DNS without a reboot, and `ifup` and `ntpsync` agree at once.
- It records `libsocket.so` in the contents database under the package.

**The preremove** runs `libsockfix unfix`:
- It reads the variant `libsocket.so` is at that moment, not at install time: `ifup` may have turned DNS on in between.
- It rebuilds each stock file from the fixed one: the first part, the 60 stock bytes from `/opt/amix/lib/libsockfix/*.stock`, then the rest. It checks the result's `sum -r` and size against stock and renames it over the fixed file.
- It links `libsocket.so` to the stock file of that variant, and records all three files. Then `pkgrm` leaves the two files to core, which still claims them.
- So the box has exactly what Commodore shipped.
- One difference: where core had a separate copy as `libsocket.so` (DNS never turned on), it is now a link to `libsockhost.so`. The bytes and sum are the same, and it is the form `ifup(1M)` itself uses to turn DNS off.

**The scripts use apkg's `installf` and `removef`** (`/usr/apkg/bin`). The stock `installf` faults (SIGSEGV, leaving a pending entry), and there is no stock `removef`. The package therefore depends on `apkgeng`.

**Install it with `apkg`:** `apkg update`, then `apkg install libsockfix`. As with libcfix, the stock `pkgadd -n` stops at the shared paths ("interaction required"). The APKGENG pkgadd installs it.

Programs already running keep the library they started with until they exit; restart a server to get the fixed one.

**`pkgchk`:**
- After install and after removal, `pkgchk` is clean for core and for the package.
- `libsocket.so` is recorded as it was linked at that moment. When `ifup` later turns DNS on or off, `pkgchk` reports it as changed, as it does on the stock system with DNS on.

## What it does not cover

- **`delete_silink`, the second stock defect.** It never updates `next->prev`, so the second release in the same hash bucket (fd % 10) through `_s_close` writes into freed memory.
  - This package does not touch it and does not make it reachable: the fixed code calls only `free` and `calloc`.
  - Links are still never released on a `close(2)`, as in the stock library, so `delete_silink` runs only on the library's own error paths, as before.
- **The links stay.** One 56-byte link per distinct descriptor number, bounded by the process's descriptor table, as in the stock library.
- **A failed `calloc` of a new link.** The stock and the fixed code both fault at address 0x10:
  - the stock code writes through the NULL link, the fixed code reads through it first;
  - that is the "User BUS ERROR at 10" seen from `in.telnetd` on a box whose swap reservation was full.
- **Copies that keep the stock code:**
  - `/usr/lib/libsocket.a`, linked by the DHCP client and apkg, which neither loop on sockets;
  - `resolv.so`'s private copy (`_rs__s_alloc_bufs`), used by the TLI name-to-address resolver only under `/etc/netconfig.DNS`. The same change fits it (it has 14 free bytes) and could be a third file later.
  - the installer's RAM disks.

## Tests

`tests/smoke.sh` runs on the box as root, with the soak program built from `tests/soak.c`. It checks that:
- both files are the fixed ones, and `libsocket.so` is the variant `ifup` would pick;
- `libsockfix status`, `ping` and `finger @localhost` work;
- the break does not grow over N operations of each kind: UDP, TCP and UNIX-domain sockets, TCP and UNIX-domain accepts, DNS lookups.

The rows ran on the 1.1.3 CDE masters, k30 (68030) and k46 (68060), each with DNS on and with DNS off. The DNS-on row on k46 installed with `apkg install`, the others with the APKGENG `pkgadd`. Each row installed the package, rebooted, removed it and installed it again:

| | k30 DNS on | k46 DNS on | k30 DNS off | k46 DNS off |
|---|---|---|---|---|
| after install and after the reboot, `libsocket.so` is the fixed file of its variant, and `ifup` and `ntpsync` agree | yes | yes | yes | yes |
| after removal, the three files' sha256 equals amix-system's (`libsocket.so` as `libsockdns.so` or `libsockhost.so`) | yes | yes | yes | yes |
| `pkgchk libsockfx` | clean | clean | clean | clean |
| `pkgchk -n core` ERROR lines: before, after removal, installed again | 118, 117, 117 | 118, 117, 117 | 117, 117, 117 | 117, 117, 117 |
| break growth over 20,000 operations of each kind, plus 50 DNS lookups | 0 | 0 | 0 | 0 |

With DNS on, the ERROR line that goes away is core's `libsocket.so`, which the scripts record as linked.

The same soak against the stock library, 300 operations of each kind, the same on both lines:
- 57,344 bytes for UDP sockets, TCP sockets, TCP accepts or DNS lookups (191 each; the break moves in whole pages);
- 1,314,816 bytes for UNIX-domain sockets (4382 each) and 1,310,720 for UNIX-domain accepts (4369 each).

**The X server**, started as `xstart` starts it. An `xclock` is held open so that the server does not reset, as under `dtlogin`. Sizes are `ps -l` SZ, the same figures on both lines:

| | after 10 warm-up TCP connects | after 200 TCP connects | after 200 local connects |
|---|---|---|---|
| stock, k30 | 1833 | 1853 | 2281 |
| stock, k46 | 1840 | 1860 | 2288 |
| fixed, k30 | 1829 | 1829 | 1831 |
| fixed, k46 | 1836 | 1836 | 1838 |

In 2-Kbyte units, that is 205 bytes per TCP connection and 4383 per local one for the stock server, which matches the soak. Host access refused the TCP connects after the server had accepted them; the leak is on the accept path, so they count.

**CDE:** a full login through the greeter into a CDE session, with the package installed, came up with all 23 of its named windows on k30 and on k46. The X server was 2407 pages at the greeter and 3283 with the session on k30, and 2414 and 3296 on k46.

**Stock programs** with the package installed, on all four rows:
- `inetd`, and `ftp`, `telnet`, `finger` and `ping` to localhost;
- three `dropbear` logins;
- `apkg update` and `apkg upgrade` ("every installed package is up to date").
