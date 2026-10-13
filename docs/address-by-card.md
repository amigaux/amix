# Address by card: one Amix image, several Z3660 machines

Amix has no DHCP client, and this project keeps it free of DNS. Before this change,
a machine's network address was written into the installed image itself, so an image
belonged to one machine. With address by card, **the image picks its address at boot
from the Z3660 card it is running on**. The same `.hdf` works on the A4000D and on
the A4000T, and each comes up at its own address with its own hostname.

It is one small table plus about a hundred lines of Bourne shell. You can use the same
pattern for your own machines.

## How it works

At every boot `/etc/rc2.d/S99zen` does this:

1. It runs `/usr/amiga/bin/zenmac`, which prints the MAC address of the card's
   ethernet (`zen0`) as the `z3660eth` driver sees it.
2. It looks that MAC up in `/etc/inet/zen.conf`.
3. When the MAC is in the table, S99zen:
   - brings `zen0` up at that row's address. The netmask and gateway come from the
     install, not from the table.
   - sets the nodename (`uname -S` now, `/etc/nodename` for later boots) to the
     row's short name.
   - rewrites the machine's own row in `/etc/inet/hosts`: `<address> <name>
     <name>.<domain>`. Any old row for that address, and any old alias of the
     previous or the new name, is removed. Every other row is left as it was.
4. When the MAC is not in the table, S99zen uses the `default` row's address. It
   keeps the nodename it has and prints one line on the console that names the
   unknown MAC:

       S99zen: WARNING: zen0 card MAC 00:80:51:01:02:07 is not in /etc/inet/zen.conf -- using 192.0.2.38

   If the table has no `default` row, S99zen uses the address from the install.
5. When `/etc/inet/zen.conf` does not exist, S99zen works as it always did. It uses
   the address from the install and doesn't read the MAC, change the nodename or
   edit `hosts`.

The address is always a literal IP. `ifconfig` is never given a name, because on
SVR4.0 a name makes it do a DNS lookup, and that stalls the boot when no resolver is
reachable. The interface bring-up still runs in the background, as it did before, so
a fault in the network path can't hang the boot.

## The table

`/etc/inet/zen.conf` has one line per card:

```
# <MAC as the driver sees it>  <address>  <short-name>
00:80:51:01:02:03  192.0.2.39  a4000d
00:80:51:01:02:04  192.0.2.40  a4000t
default            192.0.2.38
```

- Fields are separated by blanks or tabs. `#` starts a comment. MACs match in any
  letter case, but each octet must be written as two hex digits.
- The short name is optional. With no short name, or with `-`, the machine keeps
  its installed nodename. A short name may use letters, digits and `-`.
- The first row that matches wins. A row with an address that isn't a dotted quad
  is ignored, so a typo can't give `ifconfig` a name.

## Key on the MAC the driver sees, not the one you configured

The Z3660 firmware (upstream and fork, in `get_mac_address_type()`) misreads hex
letters in the `mac_address` line of `z3660cfg.txt`. It takes a letter's ASCII
value instead of its hex value. A card configured as `00:80:1A:01:02:04` therefore
reports `00:80:51:01:02:04` to the driver and on the wire. `1A` becomes `0x51`,
which matches `1*16 + 'A'` (65). Octets written with digits only are read correctly.

**The table must hold the MAC the driver reports.** To find it, run this on the box:

    /usr/amiga/bin/zenmac

If the firmware is fixed later, a card's effective MAC changes to the configured
one. At the next boot that card falls back to the `default` row and prints the
warning, which tells you to update its row.

## Why MAC keying

- **No DHCP.** Amix has no client, and writing one isn't worth it for a handful of
  machines.
- **No firmware identity.** Stock Z3660 firmware tells the guest nothing about which
  machine it is in. The MAC is the one value that differs per card and that the
  guest can already read.
- **No per-card file on the SD card.** Amix can't read the card's FAT or exFAT
  partitions.
- **It's small.** It needs one file you can edit with `vi`, and the fallback
  behaviour is easy to predict.

## How S99zen reads the MAC: `zenmac`

The driver keeps the MAC it reads from the firmware registers (`ZZ_ETH_MAC_HI/LO`
into `info->paddress`, `../amix-z3660net/src/z3660eth.c`). A user program can get
it only from the address part of a DLPI `DL_BIND_ACK`. The other routes don't work:

- The SVR4.0 `ifconfig` prints no link address.
- `arp -a` looks the kernel up through `nlist`, which doesn't work on this relocated
  kernel.
- The kmem globals `z3660eth_machi`/`z3660eth_maclo` are COMMON symbols, which
  `nlist` can't place.
- The `Z3660ETH_GET_CONFIG` ioctl is declared but not implemented.

`zenmac` (`src/zenmac/zenmac.c`) opens `/dev/zen0`, binds an unused SAP (`0x88B5`),
prints the address from the acknowledgement and closes the device. It sends no
frames. According to the driver source, every open gets its own stream slot, so
`zenmac` should be safe to run before or after `slink`. That has not yet been
confirmed on real hardware. A 5-second alarm stops it from ever hanging the boot. It is
cross-built with `tools/build-zenmac.sh` and is never committed, because it links
the sysroot's startup objects.

## Where the pieces come from

| piece | fresh install | existing install |
|---|---|---|
| `/etc/rc2.d/S99zen` | `install.sh` writes it (`emit_zen_hook`, drift-locked to `payload/S99zen`) | `tools/apply-zen-conf.sh` |
| `/usr/amiga/bin/zenmac` | `install.sh` copies it from the medium (`/install/zenmac`) | `tools/apply-zen-conf.sh` |
| `/etc/inet/zen.conf` | first boot creates it from the profile's `FB_ZEN_CARDS`. An existing table is never replaced | `tools/apply-zen-conf.sh` |

`FB_ZEN_CARDS` is a profile key: a quoted list of `MAC=ADDRESS=NAME` words, plus
`default=ADDRESS`:

    FB_ZEN_CARDS="00:80:51:01:02:03=192.0.2.39=a4000d 00:80:51:01:02:04=192.0.2.40=a4000t default=192.0.2.38"

To update a box that was installed before this scheme existed, run the following.
The script is idempotent, and each step prints `CHANGED` or `unchanged`:

    # on the host
    tools/build-zenmac.sh
    sh tools/apply-zen-conf.sh --bundle work/zenapply            # table from metal-a4000-z3660-060
    AMIX_HOST=<box> ../amix-kerntools/tools/amixsync.py push work/zenapply /tmp/zenapply  # binary FTP
    # on the box, as root
    sh /tmp/zenapply/apply.sh

Nothing on the running system is reconfigured. The new address, nodename and
`hosts` row take effect at the next boot. The original S99zen is kept as
`/var/adm/S99zen.pre-p3`. A `zen.conf` that has been edited on the box is kept
unless you pass `-f`.

## Things to know

- **Nodename timing.** S99zen is the last rc2 script. On the first boot after an
  image moves to a different card, the daemons started earlier in rc2 (`syslogd`,
  `rwhod`, `smtpd` and others) still carry the previous nodename until the next
  reboot. `/etc/nodename` is already updated, so every boot after that is consistent.
  New telnet sessions see the new name at once.
- **The `default` row.** Our bench uses `192.0.2.38`, which is also the Amiberry
  guest address. Two machines on one LAN can share that address only if one of them
  is an unlisted card.

## Testing

`tools/zen-conf-selftest.sh` runs under `dash` (the box's shell has no bashisms
either). It sends fake MACs through the real `payload/S99zen`: known MACs in either
letter case, an unknown MAC, an unreadable MAC, the `default` row, a missing table,
and malformed rows. It checks the `hosts` rewrite and that a second run changes
nothing. It runs the whole boot path in a sandbox, with every path and tool replaced
by a stub, and it converts a sandboxed pre-P-3 root with `apply-zen-conf.sh`. It is
check 10e of `tools/run-checks.sh`, and `installer-selftest.py` audit P runs it too.
The `zen0` link itself can only be tested on real hardware.
