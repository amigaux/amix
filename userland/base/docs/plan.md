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
| `rc.subr` | `/usr/lib/amix/rc.subr` | code | the helper library every one of our boot scripts sources: `rc_log` (to `/var/adm/rc.log`), `rc_bg` (run in the background with a time bound), `rc_enabled <svc>`, `rc_conf <svc> <key>`, `rc_mknod` (a missing device node made with the major `kbootset major <module>` reads from the kernel's registry; the caller's major is the fallback, or `-` for none: `link.d`'s column is needed only for a driver the registry does not name, such as the stock `aen`; a disagreement is reported as a packaging error). Page: `rc.subr(1M)`; the file format: `rc.conf(4)` |
| `devnodes` | `/etc/init.d/devnodes` = `rc2.d/S20devnodes` | code | D-N21's one boot step: the `c`/`b` records under `/dev` in `/var/sadm/install/contents` are the nodes that should exist; a missing one is made with its record's minor, mode and owner, at the registry's major (`kbootset major <class>`) when its class names its module, else at its record's. A stock node that differs is logged and left. 831 records in 4 s on E1. Page `devnodes(1M)`. Driver packages put their nodes in a class named for the module (C3-5 §1.2, dlm) |
| `rc.conf` handling | reads `/etc/rc.conf` | — | one file, owned by no package, written by the installer and edited by the administrator: `<svc>=yes\|no` and `<svc>_<key>=<value>` lines. A service's default (on or off) is in its own script, so an update that recreates an `S` link never turns a service back on |
| swap step | `/etc/init.d/swap` = `rc2.d/S90swap` (and `rc0.d/K05swap`), in the stock script's place and shape | code | folds the 030 installer's `S89rootswap` into one step read from `/etc/vfstab`: each swap slice's length from its disk's RDB (`/usr/amiga/bin/rdb`, as the stock script read it); no area listed, the whole slice; one area from block 0 (the kernel's boot area: 20476 blocks on k30), the tail from the next 16-block boundary when 2048 blocks or more are left; anything else left alone; swap files as before. `swap -a` takes the offset. On a fresh k30 install with `S89rootswap` removed: the same tail (20480, 40960 blocks) added at boot; E1's bench kernel swaps the whole slice, so nothing is added there. Written |
| `/etc/display` | admin file, owned by no package | config | P-36 W9 (D-N19): `card` (or `auto`), `mode`, `depth`, `start manual\|xdm`, `session`, `monsw`. Page `display(4)` |
| `display.d` | `/etc/display.d/<card>`, one per card, shipped by the card's package | vendor data | node, module, server, modes (the card's one mode list), depths, server `args` with `%m %w %h %d %n`, `env`, `limits`, `monsw`, `monswtool`. Under `/etc`, not D-N19's `/usr/lib/X11`, which on 2.1 is core's symlink into the stock R4 tree (seat, 2026-10-31). amix-base ships `native` (the chipset, stock mono X11R4); the A2410 and DMI Resolver have none until someone can try them. Page `display.d(4)` |
| `xstart` | `/usr/amix/bin/xstart`, `/usr/lib/amix/display.subr`, `/usr/lib/amix/xsession` | code | D-N20's one launcher: card (auto: the first whose node opens, `native` last), mode and depth checked, limits, the monitor switch when monsw does not own it, then X11R6's `xinit` (else the stock one) with `~/.xsession`, `~/.xinitrc`, `session`, the system session; `-n` dry run; `-xdm` runs xdm with `-server` from the same line. Page `xstart(1)`. On E1 (`native`): `xstart -n` under the 1991 sh, and `xstart :10` brings up the stock `xinit` and server. Open: no session client was seen to connect within 45 s on the emulator (the stock server may wait for its Alt-F screen group to be shown); the X keymap from `/etc/default.kmap` (§7) is not derived yet |
| `display` | `/etc/init.d/display` = `rc2.d/S95display` | code | D-N22: off unless `/etc/display` says `start xdm`; `display=no` in `rc.conf` is the hard off; then `xstart -xdm`, X11R6's `xdm -server` with the card's line. The system's xdm is a SAF port monitor (`_sactab`, `amixadm`) and exits when started any other way (E1), so it is not used; until X11R6's xdm is packaged, `start xdm` is logged and does nothing |
| `syslog` package | `/etc/init.d/syslogd` = `rc2.d/S70syslogd` (and `rc0.d/K50syslogd`), `/etc/syslog.conf`, `/var/log`, `/dev/conslog` | code + conffile | P-36 §7: own package `syslog` (set base, needs amix-base). On unless `rc.conf` says `syslogd=no` (replaces the installer's `exit`-line edit); makes each missing file `syslog.conf` names before starting the daemon, which appends only to existing files; says when `/usr/ccs/bin/m4` is missing, through which the daemon reads its configuration. `syslog.conf` is the stock file (amix-system), a conffile. The daemon stays the system's: the installer's 2.1c `syslogd` overwrite is not in amix-system |
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
| `dlpi-mac` | `/usr/sbin/dlpi-mac` | C, GCC 14 (T-56 D6), stock `libc.so.1` only | prints the station address of any DLPI Ethernet node, by the §4.4 rules: from the `DL_INFO_ACK` of a slot already bound, else from a `DL_BIND_ACK`; unbinds before it closes. The installer's `zenmac`, generalized (device, PPA and SAP as arguments). Page: `dlpi-mac(1M)` |
| `link.d/aen` | `/etc/inet/link.d/aen` | vendor data | the stock A2065's entry: `aen /dev/aen 0 18` plus `aen -S` as a presence command until a boot without the card is timed. Other drivers ship their own entry in their own package; the file is named for the driver's module, which `rc_mknod` asks the registry about. Written |
| `network-config`, `rc.inet` | `/etc/inet/network-config`, `/etc/inet/rc.inet` | conffiles | empty, commented hooks kept so that third-party instructions ("append to network-config") still work; the stock `rc.inet` runs nothing either (inetd comes from the SAF). Written |

### DHCP: `dhcpc/`

| Piece | Installed as | Kind | Stage |
|---|---|---|---|
| `probe/dhcprobe`, `probe/tapdhcpd.py` | not installed | test tools | S0, done: `dhcp-probe.md` |
| `dhcpc` | `/usr/sbin/dhcpc` | C, GCC 14 (T-56 D6), stock libraries only, own package `dhcp-client` (`pkg/dhcp-client`); page `dhcpc(1M)` | S1: written; on the emulator: lease, INIT-REBOOT, renew, rebind, NAK, lease end, release, no-server exit 2 and `ifup`'s fallback; a one-hour soak. S3: before binding (INIT and INIT-REBOOT), two ARP probes from 0.0.0.0 on a stream bound to 0x0806; another station answering, or probing for the same address, is a conflict: DHCPDECLINE, INIT again after 10 s. The A2065 driver's stream takes no data part under 60 bytes (ERANGE), so the probe is padded |
| lease state | `/var/inet/dhcpc/<if>.lease`, `<if>.pid`; log `/var/adm/dhcpc.log` | runtime | S1 |
| `ifup` dhcp mode | in `ifup` | code | S2: on the emulator with both packages installed by stock `pkgadd`: DHCP from `inetinit` at boot, `ifdown` releasing, `ifup` taking a new lease, INIT-REBOOT at the next boot |
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
   public install. This directory's half is done: on the emulator, both
   packages installed by stock `pkgadd` over `core`, the network up by DHCP
   from `inetinit` at boot, `ifdown` releasing and `ifup` taking a new lease,
   INIT-REBOOT at the next boot. The installer's half is W7's, to the steps in
   `package-split.md`. Then metal: leases on the Z3660 Ethernet, two
   renewals seen.

Testing: the shell parts are tested on the host under a Bourne-compatible
shell, then on the emulator against the 1991 `/bin/sh`; the C parts on the
emulator through the project's test rig.
