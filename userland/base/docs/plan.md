# userland/base: the plan

What this directory will hold, where each piece lands on the system, and the
order it is built in. It follows the project's decided plan for unified
configuration (proposal P-36, decided 2026-10-30): work items W4 (boot and
network), W5 (DHCP) and decision D-N24 (the base config files move here from
the stock `core` package). Release 1.1 supports clean installs only, so no
piece converts an older system's files.

## Pieces

### Boot: `rc/`

| Piece | Installed as | Kind | What it does |
|---|---|---|---|
| `rc.subr` | `/usr/lib/amix/rc.subr` | code | the helper library every one of our boot scripts sources: `rc_log` (to `/var/adm/rc.log`), `rc_bg` (run in the background with a time bound), `rc_enabled <svc>`, `rc_conf <svc> <key>`, `rc_mknod` (a missing device node made with the major `kbootset major <module>` reads from the kernel's registry; the caller's major, e.g. `link.d`'s column, is the fallback, and a disagreement is reported as a packaging error). Page: `rc.subr(1M)`; the file format: `rc.conf(4)` |
| `rc.conf` handling | reads `/etc/rc.conf` | — | one file, owned by no package, written by the installer and edited by the administrator: `<svc>=yes\|no` and `<svc>_<key>=<value>` lines. A service's default (on or off) is in its own script, so an update that recreates an `S` link never turns a service back on |
| swap step | `/etc/init.d/swap` + its link in the `S90`–`S98` band | code | folds the installer's `S89rootswap` (68030 swap on the tail of slice 2) into one step read from `/etc/vfstab`; whether the stock swap path takes a slice offset is still to be measured |
| band list | in `docs/` at the top of the repository | doc | the fixed `S`/`K` number bands (`S01`–`S09` mounts, `S10`–`S19` first boot, `S20`–`S29` devices, `S69` network, `S70`–`S89` daemons, `S90`–`S98` late, `S99z*` the mark-good step), which the packaging gate checks link names against |

The stock `rc0`–`rc6`, `/etc/sysinit` and every stock `rc2.d` script except
the network chain stay untouched.

### Network: `net/`

| Piece | Installed as | Kind | What it does |
|---|---|---|---|
| `inetinit` | `/etc/init.d/inetinit` = `rc2.d/S69inet` (and the `K69inet` links) | code, written in place so the hard links survive | `slink`; `ifconfig lo0 127.0.0.1 up`; `ifup -a` through `rc_bg` (bound: `rc.conf`'s `ifup_bound`, default 120 s; output in `/var/adm/rclog/ifup`); then the two legacy hooks below. Written |
| `ifup`, `ifdown` | `/usr/sbin/ifup`, `/usr/sbin/ifdown` | code | per interface: read its MAC (`dlpi-mac`), pick its line in `interfaces` (MAC line, then name line, then `*`; none = off), `slink addaen <node> <if>` once (one retry after the base `slink`), then `static` or `dhcp`, then the shared apply step; `ifup -n` says what it would do. Written; page `ifup(1M)` |
| `ifup.subr` | `/usr/lib/inet/ifup.subr` | code | the `interfaces` parser (one awk program, no shell read loops; written, page `interfaces(4)`) and the apply step: `ifconfig` with literal addresses, the default route (the first interface to set one keeps it), this host's line in `/etc/inet/hosts` (for that interface, else the first one up), `/etc/nodename` when a line says `name`, `/etc/resolv.conf` (nameservers only) and the other DNS parts, each only when it changes. Written |
| `dhcpc-hook` | `/usr/lib/inet/dhcpc-hook` | code | the entry point the DHCP client calls; it runs the same apply step as a static line (contract: `package-split.md`, frozen in T-55). Written |
| `dlpi-mac` | `/usr/sbin/dlpi-mac` | C, period compiler | prints the station address of any DLPI Ethernet node, by the §4.4 rules: from the `DL_INFO_ACK` of a slot already bound, else from a `DL_BIND_ACK`; unbinds before it closes. The installer's `zenmac`, generalized (device, PPA and SAP as arguments). Page: `dlpi-mac(1M)` |
| `link.d/aen` | `/etc/inet/link.d/aen` | vendor data | the stock A2065's entry: `aen /dev/aen 0 18` plus `aen -S` as a presence command until a boot without the card is timed. Other drivers ship their own entry in their own package; the file is named for the driver's module, which `rc_mknod` asks the registry about. Written |
| `network-config`, `rc.inet` | `/etc/inet/network-config`, `/etc/inet/rc.inet` | conffiles | empty, commented hooks kept so that third-party instructions ("append to network-config") still work; the stock `rc.inet` runs nothing either (inetd comes from the SAF). Written |

### DHCP: `dhcpc/`

| Piece | Installed as | Kind | Stage |
|---|---|---|---|
| `probe/dhcprobe`, `probe/tapdhcpd.py` | not installed | test tools | S0, done: `dhcp-probe.md` |
| `dhcpc` | `/usr/sbin/dhcpc` | C, period compiler, own package `dhcp-client` (`pkg/dhcp-client`); page `dhcpc(1M)` | S1: written; on the emulator: lease, INIT-REBOOT, renew, rebind, NAK, lease end, release, no-server exit 2 and `ifup`'s fallback; a one-hour soak |
| lease state | `/var/inet/dhcpc/<if>.lease`, `<if>.pid`; log `/var/adm/dhcpc.log` | runtime | S1 |
| `ifup` dhcp mode | in `ifup` | code | S2 |
| RELEASE at `ifdown`, ARP check and DECLINE, several interfaces at once | in `dhcpc`, `ifdown` | code | S3, later |

The client follows the rules of P-36 §4.4 with no per-driver code; the probe
confirmed them on the A2065 (`dhcp-probe.md`).

### Manual pages: `man/`

| Piece | Installed as | Kind | What it does |
|---|---|---|---|
| `man.sh` | `/usr/amix/bin/man` | code | one `man` for the add-on pages and the stock ones (`man.md`) |
| `man.1` | `/opt/amix/man/1/man`, index line in `/opt/amix/man/whatis.d/amxbase` | page | its manual page |
| which page | in `man.sh` | rule | a command's page (1, 1m, 8) follows the binary `PATH` runs; other sections ours first; `-a` both (owner, 2026-10-30) |
| cache directories | `/var/opt/amix/catman/<sect>`, root, 0755 | `d` objects | the formatted-page cache |
| PATH drop-in | `/etc/profile.d/` | code | puts `/usr/amix/bin` after `/usr/local/bin` and before `/usr/bin` |

### Base config files: `etc/` (D-N24)

The stock config files `core` owns that we ship different bytes for, or that
our scripts rewrite, move into the base package as conffiles, and the
installer transfers their ownership on a new install (`removef core <path>`,
then `removef -f core`), as it does for the network chain. The list (owner,
2026-10-30):

| File | Why it moves |
|---|---|
| `/etc/inittab` | carries the `dlm` line, `modadmin -B` as the first `sysinit` entry (C3-5 §5). Ours, built at package time: amix-system's stock bytes (sha256-checked) with that one line after the `initdefault` entry (`etc/mkinittab.sh`, test `etc/test-inittab.sh`); `modtools` no longer edits the file |
| `/etc/TIMEZONE` | the colon form is mandatory; validated wherever it is written |
| `/etc/nodename` | written by `ifup` when an `interfaces` line says `name`, or by the install dialog |
| `/etc/inet/hosts` | `ifup` rewrites this host's own line |
| `/etc/default/login` | `CONSOLE=` |
| `/etc/profile` | gains the one guarded line that sources `/etc/profile.d/*.sh` (D-N23). Ours, built at package time: amix-system's stock bytes (sha256-checked) followed by `etc/profile.add`, the only lines this repository holds (`etc/mkprofile.sh`, test `etc/test-profile.sh`) |
| `/etc/inet/strcf` | read by `slink`; ours as the network chain's |

`/etc/inet/inetd.conf` moves only in the revision that first changes it. The
other `/etc/default/*` files and `/etc/vfstab` stay with `core`: a file moves
only when we ship different bytes for it or our scripts rewrite it.

The defaults are built from the stock bytes once they are public in
`amix-system` (`etc/`, the whole stock `/etc` of 2.1c p2a, pinned by
`system/MANIFEST.sha256`).

Two of these change on every normal system (`nodename`, `hosts`), so they
differ from the shipped default from the first boot on. The shared conffile
scripts keep such a file silently when the package's new default equals its
baseline (pkgtools 85d4e09), so an update asks nothing unless the default
itself changed.

## Order

1. **S0 probe** (done, this directory's first commit).
2. **`rc.subr`, `rc.conf` handling, the `interfaces` parser and `dlpi-mac`**
   (written, host-tested and run on the emulator; not yet packaged). No
   packaging dependency beyond a plain package.
3. **`ifup`/`ifdown`, `ifup.subr`, `link.d/aen`, `dhcpc-hook`, the new
   `inetinit`** (written, host-tested, `ifup` run on the emulator against the
   live `aen0`; not yet packaged).
4. **The base config files** (D-N24), once the conffile scripts handle a file
   the system edits every boot without writing a `.new` each update.
5. **`dhcpc` 1.0** (S1), against the hook contract frozen after S0 (T-55).
   Tested on the emulator: lease, reuse of the last address (INIT-REBOOT),
   renew, rebind, NAK, lease end, release, no server and the static
   fallback. Soak passed: one hour with a 60 s lease, 112 renewals, 4
   rebinds, no ICMP, and the daemon was still the same process at the end.
6. **`ifup` dhcp mode** (S2) and, in the installer, DHCP as the default of the
   public install. Then metal: leases on the Z3660 Ethernet, two renewals seen.

Testing: the shell parts are tested on the host under a Bourne-compatible
shell, then on the emulator against the 1991 `/bin/sh`; the C parts on the
emulator through the project's test rig.
