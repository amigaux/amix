# userland/base: the plan

What this directory holds, where each piece lands on the system, and the
order it was built in: the boot steps and their helpers, the network set-up
with its DHCP client, and the base config files that move here from the
stock `core` package. Release 1.1 supports clean installs only, so no piece
converts an older system's files.

## Pieces

### Boot: `rc/`

| Piece | Installed as | Kind | What it does |
|---|---|---|---|
| `rc.subr` | `/usr/lib/amix/rc.subr` | code | the helper library every one of our boot scripts sources: `rc_log` (to `/var/adm/rc.log`), `rc_bg` (run in the background with a time bound), `rc_enabled <svc>`, `rc_conf <svc> <key>`, `rc_mknod` (a missing device node made with the major `kbootset major <module>` reads from the kernel's registry; the caller's major is the fallback, or `-` for none: `link.d`'s column is needed only for a driver the registry does not name, such as the stock `aen`; a disagreement is reported as a packaging error). Page: `rc.subr(1M)`; the file format: `rc.conf(4)` |
| `devnodes` | `/etc/init.d/devnodes` = `rc2.d/S20devnodes` | code | the one boot step that re-creates device nodes: the `c`/`b` records under `/dev` in `/var/sadm/install/contents` are the nodes that should exist; a missing one is made with its record's minor, mode and owner, at the registry's major (`kbootset major <class>`) when its class names its module, else at its record's. A stock node that differs is logged and left. 831 records in 4 s on the emulated 2.1c system. Page `devnodes(1M)`. Driver packages put their nodes in a class named for the module (contract C3-5 §1.2, `kernel/dlm/docs/contracts/`) |
| `rc.conf` handling | reads `/etc/rc.conf` | — | one file, owned by no package, written by the installer and edited by the administrator: `<svc>=yes\|no` and `<svc>_<key>=<value>` lines. A service's default (on or off) is in its own script, so an update that recreates an `S` link never turns a service back on |
| swap step | `/etc/init.d/swap` = `rc2.d/S90swap` (and `rc0.d/K05swap`), in the stock script's place and shape | code | folds the 68030 installer's `S89rootswap` into one step read from `/etc/vfstab`: each swap slice's length from its disk's RDB (`/usr/amiga/bin/rdb`, as the stock script read it); no area listed, the whole slice; one area from block 0 (the kernel's boot area: 20476 blocks on the 68030 kernel), the tail from the next 16-block boundary when 2048 blocks or more are left; anything else left alone; swap files after the slices, so the partition has the kernel's memory first. `swap -a` takes the offset. On a fresh 68030 install with `S89rootswap` removed: the same tail (20480, 40960 blocks) added at boot; a kernel that swaps on the whole slice gets nothing added. On the 68040/68060 kernels `swap -l` lists half of each area (it counts 2 KiB pages; those kernels page in 4 KiB), so the step doubles the listed length when `uname -a`'s build id starts 68040- or 68060-: their boot area of 61440 blocks on a 61440-block slice 2 (listed 30720) leaves nothing to add. How far the added area reaches is rc.conf's `swap_add`: sizes in MiB from the slice's start (the kernel's area included) or `all`, the first asked; default `all`; `30` (which fits any kernel), whatever the list, when the kernel has no guard, told by the guard's marker `swg_magic` (53574721) read with adb from the booted namelist (cuts 68030-261101-67 and 68060-261101-56 on). `swap -a` needs an array of 16 B a page for the area in kernel memory; a kernel with the guard refuses a whole area that does not fit (ENOMEM), and the step then steps down, for files too: to the largest size below among the rest of the list and the kernel's limit (68040/68060: maxmem/8 MiB; 68030 from cut -72, told by its symbol `swg_keep`: maxmem/32 MiB; maxmem read with adb; the 68030 map space can refuse less, with no figure), else half in whole MiB, not under 8 MiB, 8 tries an area at most; an area added smaller than asked, or not at all, is one line on the console and in rc.log, with the limit when known. A kernel without the ENOMEM guard waits forever on a request that does not fit, hence the `30` there, as such a kernel boots as a fallback with a list set for another; the installer writes no list. More swap than one area is `/SWAPFILE`, which the page explains. Page `bootswap(1M)`. Written |
| stock services off by default | the stock `init.d/rpc` (`S75rpc`, `K50rpc`), `init.d/smtpd` (`rc3.d/S88smtpd`, `rc2.d/S88smtpd`), `init.d/lp` (`S80lp`, `K20lp`), `init.d/news` (`S91news`), each installed at the path stock records as the file, its stock links re-made to it (pkgadd gives it a new inode) | code, built from amix-system (`rc/mkgated.sh`, sha256-checked) | rpc.rwalld, rpc.rusersd, rpc.sprayd, mthreads, smtpd and lpsched (with lpNet) run only when `rc.conf` says `rwalld=`, `rusersd=`, `sprayd=`, `mthreads=`, `smtpd=`, `lpsched=` yes; default no. The stock script follows a gate that sources `rc.subr`; rpc and news gate only their daemons (rpcbind and the rest of the news start run as before). The stock stop scripts run unchanged; `K74smtpd` is a separate file and is not touched. Local mail (`/bin/mail`, cron) needs no smtpd. Page `rc.conf(4)`. Written |
| `/etc/display` | admin file, owned by no package | config | `card` (or `auto`), `mode`, `depth`, `start manual\|xdm\|dtlogin`, `session`, `monsw`. Page `display(4)` |
| `display.d` | `/etc/display.d/<card>`, one per card, shipped by the card's package | vendor data | node, module, server, modes (the card's one mode list), depths, server `args` with `%m %w %h %d %n`, `env`, `limits`, `monsw`, `monswtool`, `restore`. The Z3660's file is the worked example in `display.d(4)`, shipped by its driver package. Under `/etc`, not `/usr/lib/X11`, which on 2.1 is core's symlink into the stock R4 tree. amix-base ships `native` (the chipset, stock mono X11R4); the A2410 and DMI Resolver have none until someone can try them. Page `display.d(4)` |
| `xstart` | `/usr/amix/bin/xstart`, `/usr/lib/amix/display.subr`, `/usr/lib/amix/xsession` | code | the one X launcher: card (auto: the first whose node opens, `native` last), mode and depth checked, limits, the monitor switch when monsw does not own it, then X11R6's `xinit` (else the stock one) with `~/.xsession`, `~/.xinitrc`, `session`, the system session; `-n` dry run; `-xdm` and `-dtlogin` run a display manager with `-server` from the same line. A card's `env` reaches the server alone (a wrapper `xstart` writes in `/tmp`, since the stock `xinit` takes no env prefix), and a card's `restore` command runs when the server ended on its own (a crash, a kill) rather than at the session's end. Page `xstart(1)`. On the emulated 2.1c system (`native`): `xstart -n` under the 1991 sh, and `xstart :10` brings up the stock `xinit` and server. Open: no session client was seen to connect within 45 s on the emulator (the stock server may wait for its Alt-F screen group to be shown); the X keymap from `/etc/default.kmap` is not derived yet |
| `display` | `/etc/init.d/display` = `rc2.d/S95display` | code | the graphical login at boot: off unless `/etc/display` says `start xdm` or `start dtlogin`; CDE ships no boot script of its own; `display=no` in `rc.conf` is the hard off; then `xstart -xdm` (X11R6's `xdm`) or `xstart -dtlogin` (CDE's `dtlogin`), each given `-server` with the card's line, which outranks its own configuration; one not installed is logged and the box stays at text logins. The system's xdm is a SAF port monitor (`_sactab`, `amixadm`) and exits when started any other way, so it is not used; until X11R6's xdm is packaged, `start xdm` is logged and does nothing |
| `syslog` package | `/etc/init.d/syslogd` = `rc2.d/S70syslogd` (and `rc0.d/K50syslogd`), `/etc/syslog.conf`, `/var/log`, `/dev/conslog` | code + conffile | own package `syslog` (set base, needs amix-base). On unless `rc.conf` says `syslogd=no` (replaces the installer's `exit`-line edit); makes each missing file `syslog.conf` names before starting the daemon, which appends only to existing files; says when `/usr/ccs/bin/m4` is missing, through which the daemon reads its configuration. `syslog.conf` is the stock file (amix-system), a conffile. The daemon stays the system's: the installer's 2.1c `syslogd` overwrite is not in amix-system |
| band list | in `docs/` at the top of the repository | doc | the fixed `S`/`K` number bands (`S01`–`S09` mounts, `S10`–`S19` first boot, `S20`–`S29` devices, `S69` network, `S70`–`S89` daemons, `S90`–`S98` late, `S99z*` the mark-good step), which the packaging gate checks link names against |
| numbers in use | the add-on packages' run-level links, so a new one picks a free number | doc | `S20devnodes`; `S69inet`, `K69inet` (rc0, rc1); `S70syslogd`, `K50syslogd` (syslog); `S76dropbear`, `K40dropbear` (rc0, rc1; the dropbear package, keys `dropbear`, `dropbear_port`, `dropbear_rsa`, `dropbear_flags` in its dropbear(8)); `S77ntp`; `S90swap`, `K05swap`; `S95display`. Stock `rc2.d` already holds `S75cron` and `S75rpc` |

The stock `rc0`–`rc6`, `/etc/sysinit` and every stock `rc2.d` script except
the network chain stay untouched.

### Network: `net/`

| Piece | Installed as | Kind | What it does |
|---|---|---|---|
| `inetinit` | `/etc/init.d/inetinit` = `rc2.d/S69inet` (and the `K69inet` links) | code; its hard links are declared with it, so an update re-makes them | `slink`; `ifconfig lo0 127.0.0.1 up`; `ifup -a` through `rc_bg` (bound: `rc.conf`'s `ifup_bound`, default 120 s; output in `/var/adm/rclog/ifup`); then the two legacy hooks below. Written |
| time sync | `/etc/init.d/ntp` = `rc2.d/S77ntp`, `/usr/sbin/ntpsync` | code | SNTP through the rdate package (`/opt/amix/sbin/rdate`, set base), no daemon. Boot: `ntpsync -i` puts root's hourly crontab line in, at a minute picked once per machine, or takes it out under `ntp=no` (no package install script: rc.conf stays the one switch, and `pkgadd -R` at install time has no running cron to tell); then `ntpsync -b` through `rc_bg`, which waits for `ifup.primary` up to `ntp_wait` (120 s). Servers: DHCP option 42 (dhcpc's `DHCP_NTP`), the primary interface's first, then `ntp_servers` (default `0.pool.ntp.org 1.pool.ntp.org 2.pool.ntp.org`), all in one rdate run, `-t ntp_timeout` (15) `-r ntp_retries` (1). Hourly runs slew (`-a`) and log only when the outcome changes. After a sync, `setclk -s` at the start of a minute (it writes whole minutes); never the stock `setclk` (SysV sum 60596, 7120 B), whose `-s` writes 2012 for 2026. Page `ntpsync(1M)` |
| `ifup`, `ifdown` | `/usr/sbin/ifup`, `/usr/sbin/ifdown` | code | per interface: read its MAC (`dlpi-mac`), pick its line in `interfaces` (MAC line, then name line, then `*`; none = off), `slink addaen <node> <if>` once (one retry after the base `slink`), then `static` or `dhcp`, then the shared apply step; `ifup -n` says what it would do. Written; page `ifup(1M)` |
| `ifup.subr` | `/usr/lib/inet/ifup.subr` | code | the `interfaces` parser (one awk program, no shell read loops; written, page `interfaces(4)`) and the apply step: `ifconfig` with literal addresses, the default route (the first interface to set one keeps it), this host's line in `/etc/inet/hosts` (for that interface, else the first one up), `/etc/nodename` when a line says `name`, `/etc/resolv.conf` (nameservers only) and the other DNS parts, each only when it changes. Written |
| `dhcpc-hook` | `/usr/lib/inet/dhcpc-hook` | code | the entry point the DHCP client calls; it runs the same apply step as a static line (contract: `package-split.md`, fixed before the client was written). Written |
| `dlpi-mac` | `/usr/sbin/dlpi-mac` | C, GCC 14, stock `libc.so.1` only | prints the station address of any DLPI Ethernet node, by the rules in `dhcp-probe.md`: from the `DL_INFO_ACK` of a slot already bound, else from a `DL_BIND_ACK`; unbinds before it closes. The installer's `zenmac`, generalized (device, PPA and SAP as arguments). Page: `dlpi-mac(1M)` |
| `link.d/aen` | `/etc/inet/link.d/aen` | vendor data | the stock A2065's entry: `aen /dev/aen 0 18` plus `aen -S` as a presence command until a boot without the card is timed. Other drivers ship their own entry in their own package; the file is named for the driver's module, which `rc_mknod` asks the registry about. Written |
| `network-config`, `rc.inet` | `/etc/inet/network-config`, `/etc/inet/rc.inet` | conffiles | empty, commented hooks kept so that third-party instructions ("append to network-config") still work; the stock `rc.inet` runs nothing either (inetd comes from the SAF). Written |

### DHCP: `dhcpc/`

| Piece | Installed as | Kind | State |
|---|---|---|---|
| `probe/dhcprobe`, `probe/tapdhcpd.py` | not installed | test tools | the DLPI probe, done: `dhcp-probe.md` |
| `dhcpc` | `/usr/sbin/dhcpc` | C, GCC 14, stock libraries only, own package `dhcp-client` (`pkg/dhcp-client`); page `dhcpc(1M)` | on the emulator: lease, INIT-REBOOT, renew, rebind, NAK, lease end, release, no-server exit 2 and `ifup`'s fallback; a one-hour soak. Before binding (INIT and INIT-REBOOT), two ARP probes from 0.0.0.0 on a stream bound to 0x0806; another station answering, or probing for the same address, is a conflict: DHCPDECLINE, INIT again after 10 s. The A2065 driver's stream takes no data part under 60 bytes (ERANGE), so the probe is padded |
| lease state | `/var/inet/dhcpc/<if>.lease`, `<if>.pid`; log `/var/adm/dhcpc.log` | runtime | written |
| `ifup` dhcp mode | in `ifup` | code | on the emulator with both packages installed by stock `pkgadd`: DHCP from `inetinit` at boot, `ifdown` releasing, `ifup` taking a new lease, INIT-REBOOT at the next boot |
| several interfaces at once | in `dhcpc`, `ifdown` | code | later |

The client follows the rules in `dhcp-probe.md` with no per-driver code; the
probe confirmed them on the A2065.

### Manual pages: `man/`

| Piece | Installed as | Kind | What it does |
|---|---|---|---|
| `man.sh` | `/usr/amix/bin/man` | code | one `man` for the add-on pages and the stock ones (`man.md`) |
| `man.1` | `/opt/amix/man/1/man`, index line in `/opt/amix/man/whatis.d/amxbase` | page | its manual page |
| which page | in `man.sh` | rule | a command's page (1, 1m, 8) follows the binary `PATH` runs; other sections ours first; `-a` both |
| cache directories | `/var/opt/amix/catman/<sect>`, root, 0755 | `d` objects | the formatted-page cache |
| PATH drop-in | `/etc/profile.d/` | code | puts `/usr/amix/bin` after `/usr/local/bin` and before `/usr/bin` |

### Base config files: `etc/`

The stock config files `core` owns that we ship different bytes for, or that
our scripts rewrite, move into the base package as conffiles, and the
installer transfers their ownership on a new install (`removef core <path>`,
then `removef -f core`), as it does for the network chain. The list:

| File | Why it moves |
|---|---|
| `/etc/inittab` | carries the `dlm` line, `modadmin -B` as the first `sysinit` entry (contract C3-5 §5). Ours, built at package time: amix-system's stock bytes (sha256-checked) with that one line after the `initdefault` entry (`etc/mkinittab.sh`, test `etc/test-inittab.sh`); `modtools` no longer edits the file |
| `/etc/TIMEZONE` | the colon form is mandatory; validated wherever it is written |
| `/etc/nodename` | written by `ifup` when an `interfaces` line says `name`, or by the install dialog |
| `/etc/inet/hosts` | `ifup` rewrites this host's own line |
| `/etc/default/login` | `CONSOLE=`; ours, built at package time: the stock bytes with `ULIMIT=4194303` for the commented `#ULIMIT=4096` (`etc/mklogin.sh`, test `etc/test-login.sh`), so a login can write a file up to the ufs ceiling (2 GiB less 512 bytes) and not only the kernel's 256 MiB. Page `default(4)` |
| `/etc/profile` | gains the one guarded line that sources `/etc/profile.d/*.sh`. Ours, built at package time: amix-system's stock bytes (sha256-checked) followed by `etc/profile.add`, the only lines this repository holds (`etc/mkprofile.sh`, test `etc/test-profile.sh`) |
| `/etc/inet/strcf` | read by `slink`; ours as the network chain's |
| `/etc/group` | carries the groups packages lay files with: `audio::20:` for the sound device's node (0660 root audio), as `pkgadd -R` refuses a group name the target cannot resolve. Ours, built at package time: the stock bytes (sha256-checked) with that one line after `daemon` (`etc/mkgroup.sh`, test `etc/test-group.sh`). A fresh install seeds its baseline, so the new default goes in; a system whose file was changed, or that was installed before the file moved here, keeps its file and gets `/etc/group.new` (the class has no baseline for it), and the group is added with `groupadd`. Page `group(4)` |

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

1. **The DLPI probe** (done, this directory's first commit).
2. **`rc.subr`, `rc.conf` handling, the `interfaces` parser and `dlpi-mac`**
   (written, host-tested and run on the emulator). No packaging dependency
   beyond a plain package.
3. **`ifup`/`ifdown`, `ifup.subr`, `link.d/aen`, `dhcpc-hook`, the new
   `inetinit`** (written, host-tested, `ifup` run on the emulator against the
   live `aen0`).
4. **The base config files**, once the conffile scripts handle a file the
   system edits every boot without writing a `.new` each update.
5. **`dhcpc` 1.0**, against the hook contract fixed after the probe.
   Tested on the emulator: lease, reuse of the last address (INIT-REBOOT),
   renew, rebind, NAK, lease end, release, no server and the static
   fallback. Soak passed: one hour with a 60 s lease, 112 renewals, 4
   rebinds, no ICMP, and the daemon was still the same process at the end.
6. **`ifup` dhcp mode** and, in the installer, DHCP as the default of the
   public install. This directory's half is done: on the emulator, both
   packages installed by stock `pkgadd` over `core`, the network up by DHCP
   from `inetinit` at boot, `ifdown` releasing and `ifup` taking a new lease,
   INIT-REBOOT at the next boot. The installer's half follows the steps in
   `package-split.md`. Then real hardware: leases on the Z3660 Ethernet, two
   renewals seen.
7. **The ARP check before binding** (DHCPDECLINE on a conflict), done.

Testing: the shell parts are tested on the host under a Bourne-compatible
shell, then on the emulator against the 1991 `/bin/sh`; the C parts on the
emulator through the project's test rig.
