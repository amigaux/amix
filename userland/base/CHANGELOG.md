# Changelog

## 2026-11-02 — xstart ends the server with the session; amix-base 1.0-27 (45fe98a)

- A session's server now gets the card's display.d `once` option (X11R6's -terminate, the system server's -once, or none), so it exits when the session ends instead of resetting first.
- On a 68LC060 that reset took up to 30 s, and xinit killed the server after 10 s without its hand-back to the Amiga video.
- xstart now waits up to XSTART_WAIT (60 s) for an X server still on the display and then refuses, instead of starting a second server that fails with "Cannot establish any listening sockets".
- amxbase-1.0-27 md5 2580dd91.

## 2026-11-02 — dhcpc lives on when -b stopped waiting; dhcp-client 1.0-7 (2c058ba)

The daemon told the foreground dhcpc -b of its first lease only after the BOUND hook. When -b had already returned (a hook longer than the wait, or a lease that came late), that write raised SIGPIPE and ended the daemon without a log line, so the lease was never renewed. tell() now ignores SIGPIPE for that write. test-tell.sh tests it on the host. dhcpc-1.0-7 md5 878d3d2a.

## 2026-11-02 — ifup: the kernel's domain, a lease still being applied; amix-base 1.0-26 (8e185fd, 064ae88, 960e8fd)

- With DNS on, the kernel's domain was rpcdomain after every boot: the stock sysinit's `domainname` does nothing with an empty /etc/domain, and the resolver appended the kernel's default to lookups. ifup's DNS step now clears the kernel's domain whenever it is set.
- When the BOUND hook outlasted ifup_dhcpwait (21 s against 20 on a 16 MB 68030), ifup applied the line's static fallback over the lease just applied. ifup now asks `dhcpc -q` first, and a held lease counts.
- ifup(1M) says DNS is never turned off, that /etc/resolv.conf must then stay, and how to go back (libsocket.so linked to libsockhost.so, resolv.so taken out of /etc/netconfig).
- amxbase-1.0-26 md5 d39399eb.

## 2026-11-02 — the man directories are root sys; amix-base 1.0-25, dhcp-client 1.0-6 (6e83c56)

The shared /opt/amix/man directories (man, the section directories, whatis.d, replaces.d) are 0755 root sys, the same as in every other package. Stock pkgadd stops on a d entry whose attributes differ from the registry. man.md rule 4 now states the attribute. On a disk that already has these packages, apkg's install of the new amix-base rewrites the directories' registry entries. amxbase-1.0-25 md5 5c827fc6, dhcpc-1.0-6 md5 2369ad74.

## 2026-11-01 — amix-base 1.0-24 (7c25608)

man shows a package's own page for a stock program the package has replaced. The package lists the program in /opt/amix/man/replaces.d/<pkginst>, one line per program: "<binary path> <section> <page name>". When the program PATH runs is listed there and the page exists, that page is shown and cached under the page's own name; -a then adds the stock page. The table is keyed by the binary's path, so another package's page for the same name still serves its own binary. amxbase-1.0-24 md5 69bb46c9.

## 2026-11-01 — amix-base 1.0-22 and 1.0-23 (017ed49, 370d66b)

- 1.0-22: rc_bg no longer leaves its timer behind. When the command ended it killed only the watcher subshell, so the sleep ran out the whole bound: S69inet left a `sleep 120` for two minutes after every boot. The timer's sleep now records its own pid and is killed as soon as the command ends. The swap step logs the kernel's refusal text again (stock sed dropped the unterminated line tr left; it now joins with awk).
- 1.0-23: six stock services are installed but run only when /etc/rc.conf turns them on: rpc.rwalld, rpc.rusersd, rpc.sprayd, mthreads, smtpd, and lpsched (which starts lpNet); keys rwalld, rusersd, sprayd, mthreads, smtpd and lpsched, default no, documented in rc.conf(4). Each stock script is built from amix-system, sha256-checked, behind a gate; the stock text below the gate is intact and the stock stop scripts run unchanged. Local mail through /bin/mail needs no smtpd. About 2.4 MiB more free memory and 9 fewer processes at boot on both lines. amxbase-1.0-23 md5 743cb37e.

## 2026-11-01 — amix-base 1.0-21 (734b458, fa6a35c)

The swap step reads a 68040/68060 kernel's boot area at its real length. swap -l counts 2 KiB pages, so on those 4 KiB-page kernels it lists half of each area, and the tail the step added past the boot area overlapped it and failed at every boot. The step now doubles the listed length when uname -a's build id starts 68040- or 68060-; a kernel without a CPU in its build id is read as before. bootswap(1M) says so, and gives the 68040/68060 kernel's limits: 256 MiB added on a 64 MB machine, 512 MiB on a 16 MB one. amxbase-1.0-21 md5 19f6f658.

## 2026-11-01 — amixrt 1.0-1; amix-base 1.0-20, dhcp-client 1.0-5 (e758ca8, 974f485)

- amixrt 1.0-1: /usr/lib/libamixrt.so.1 (set base, essential) for GCC 14 shared libraries, with libamixc99's MIT licence and GCC's runtime exception under /opt/amix/doc/amixrt.
- amix-base 1.0-20 and dhcp-client 1.0-5 rebuilt with gcc14-cross-amix 43825b2: every program they link gains the constructor runner; both still link only libc.so.1 (and libnsl for dhcpc). No source change.

## 2026-11-01 — every delete guarded; the swap step reads both streams; amix-base 1.0-19 (0ba9739, 65d1322, 9759ed0)

Every delete on a variable path, in the shipped scripts and the tests, takes ${var:?}, so an empty variable stops
the command instead. The swap step recognises a refused area by swap's "Not enough space" on either output stream (a
guarded kernel prints "SC_ADD failed", then "swap: Not enough space", exit 2, a status other failures share).
bootswap(1M) gives the measured limits: an area of about 50 MiB fits on a 64 MB 68030 machine, about 248 MiB on 16 MB.

## 2026-11-01 — the swap step-down; licences shipped; amix-base 1.0-18, dhcp-client 1.0-4, syslog 1.0-2 (5ab5e60, 5cf092b, 0601ab0)

The swap step reads `swap_add` from /etc/rc.conf: the sizes to try for a swap slice, each `all` or MiB counted from
the slice's start, tried in order, stepping down only when the kernel refuses with ENOMEM, each size at most once;
the size used goes to rc.log. With no line, 30 MiB, which fits any kernel. New page bootswap(1M). All three packages
ship /opt/amix/doc/<name>/LICENSE (MIT), and the shipped scripts name it. The plan lists the run-level numbers in use.

## 2026-11-01 — /etc/group is a base conffile with the audio group; amix-base 1.0-17 (5dd8050)

The stock file with `audio::20:` added after `daemon`, the group of the sound device's node (0660 root audio); a
package that lays a node owned by a group needs the group present when pkgadd installs it. Built from the stock
bytes (etc/mkgroup.sh, sha256-checked). New page group(4): the format, adding a login (`usermod -G audio <login>`,
naming its other groups too), and `groupadd -g 20 audio` for a system whose kept file lacks the group.

## 2026-10-31 — display.d(4): the Z3660 example drops -fp; amix-base 1.0-16 (8d05ace)

X11R6.3 from 6.3-2 on finds its fonts by its own default path, so the example's args are `-mode %m -ac -kb`.

## 2026-10-31 — display.d(4): the Z3660 example lists only the modes the card takes; amix-base 1.0-15 (a865427)

The modes line is 1024x768 (default) 640x480 800x600 1280x720 1280x800 1280x1024 1920x1080; 1920x800 is gone.

## 2026-10-31 — xstart keeps a card's env to its server and runs restore after a crash; amix-base 1.0-14 (5a70fe4)

On the xinit path too, a card's `env` reaches the server alone (a wrapper that exists only while the session runs).
The optional card key `restore` runs after a session whose server ended on its own (e.g. a keyboard hand-back).
display.d(4) gives the exact card-file contract, with the Z3660 RTG card file as its worked example.

## 2026-10-31 — syslog builds with TOOLCHAIN=none (6b43224)

syslog compiles nothing, so it sets up no cross toolchain and no longer depends on a compiler checkout. Payload
unchanged; syslog 1.0-1 re-rolls with a new PSTAMP and timestamp.

## 2026-10-31 — docs, comments and recipe headers state facts without internal ids; amix-base 1.0-13 (b64aa88)

C objects unchanged (comments only). amix-base 1.0-13 because /etc/profile's comment line and devnodes' header
changed; dhcp-client re-rolls with a new timestamp at the same version.

## 2026-10-31 — /etc/display can start CDE's dtlogin; amix-base 1.0-12 (cabcec9)

/etc/display takes `start dtlogin`: S95display runs `xstart -dtlogin`, which starts dtlogin with `-server` and the
card's server line, as for xdm; no Xservers file is written. When dtlogin isn't installed it is logged and the box
stays at text logins. CDE ships no boot script of its own. display(4), xstart(1). amix-base 1.0-12.

## 2026-10-31 — /etc/default/login sets ULIMIT=4194303; amix-base 1.0-11 (e89b9cf)

/etc/default/login sets ULIMIT=4194303, the ufs per-file ceiling, so a login can write files over the kernel's default
256 MiB. Built from the stock bytes (etc/mklogin.sh: exactly `#ULIMIT=4096` replaced), still a conffile; new page
default(4). amix-base 1.0-11. On the emulator: a fresh login's ulimit is 4194303.

## 2026-10-31 — dhcpc checks an address with ARP before binding (88954e7)

dhcpc: two RFC 5227 probes after the DHCPACK, from INIT or INIT-REBOOT; when another station claims or probes the
address it sends DHCPDECLINE (option 50 and the server id) and starts again after 10 s. The check is skipped and logged
if the ARP stream can't open. tapdhcpd gains a conflict mode. dhcp-client 1.0-3. Passes on the emulator, conflict and normal rounds.

## 2026-10-31 — the syslog package; display.d(4) native best effort (54167d9, bcfeda3)

The syslog package (syslog 1.0-1, set base): init.d/syslogd (S70/K50) on rc.subr, on unless rc.conf says syslogd=no;
it makes each log file syslog.conf names before the daemon starts and says when m4 is missing. The stock syslog.conf as
a conffile, /var/log, /dev/conslog. The daemon itself stays the installer's 2.1c copy for now. display.d(4) says the
native card is a best effort. test-syslogd 15/0; passes over two boots on the emulator.

## 2026-10-31 — the display set-up: /etc/display, display.d, xstart, S95display (9bbbfbb)

The display set-up: /etc/display (display(4)) and /etc/display.d/<card> (display.d(4)), the xstart launcher
(xstart(1)) with the shared display.subr and a default xsession, and S95display for the graphical login.
display.d/native for the chipset display and the stock X11R4 server (best effort). xstart -n is a dry run naming every
mistake; -xdm runs X11R6's xdm with its -server line. amix-base 1.0-10. Host test-display 38/0; on the emulator the stock
server comes up through xstart.

## 2026-10-31 — the swap step; devnodes reads ? as 0 (96c0923, d1cf84c)

The swap step: /etc/init.d/swap = rc2.d/S90swap (K05swap), replacing the stock script in its shape and folding the
installer's S89rootswap. Each vfstab swap slice gets its length from the disk's RDB: the whole slice when the kernel
lists no area, the tail past a block-0 boot area when 2048+ blocks are left; swap files as before. amix-base 1.0-9.
devnodes: a `?` major or minor (stock pkgadd's record of 0) is 0, and a `?` mode is 0600. Host tests swap 20/0,
devnodes 27/0; passes over two boots on a fresh 68030 1.1 install.

## 2026-10-31 — dhcpc and dlpi-mac built with GCC 14; inittab(4) (5520414, 63812ca)

dhcpc and dlpi-mac are built with GCC 14 (gcc14-cross-amix b51ff39, -m68020-60 -mno-strict-align) against the stock
libraries only: NEEDED libnsl.so and /usr/lib/libc.so.1, no RPATH, nothing from /opt/amix. dhcp-client 1.0-2,
amix-base 1.0-7. inittab(4): our page for the inittab amix-base ships (the format, the shipped entries, why the dlm line
comes first); amix-base 1.0-8. On the emulator, over two boots: the DHCP protocol checks and the boot path with the
GCC 14 binaries.

## 2026-10-31 — devnodes, the boot step that re-creates nodes; link.d's major column optional (41f4274, 35aab99)

devnodes (/etc/init.d/devnodes = rc2.d/S20devnodes, devnodes(1M)) re-creates a missing /dev node from its c/b record in
the installed-objects DB: at the registry's major (`kbootset major <class>`) when the record's class names its module,
else at the record's; a stock node that differs from its record is logged and left. amxbase 1.0-6. link.d's major
column is optional, needed only for drivers the registry doesn't name (aen keeps 18); rc_mknod takes - for no major.
Host tests devnodes 27/0, rc 51/0, ifup 70/0; on the emulator, over two boots, three removed stock nodes re-created.

## 2026-10-31 — amxbase 1.0-4/1.0-5: inetinit as core records it, /etc/inittab with the dlm line; ifup's dhcp mode (fe3e116, 1866d0f, 66ad365)

amxbase 1.0-4: the network start script is recorded as stock core records it (S69inet the file, inetinit and K69inet
links to it); stock pkgadd ignored the other shape and kept the stock script. docs/package-split.md: the installer's
steps, measured on the emulator. amxbase 1.0-5: /etc/inittab is stock plus C3-5 §5's dlm line as the first sysinit
entry (etc/mkinittab.sh, test-inittab.sh 8/0); still a conffile, no longer STOCK_ETC. ifup's dhcp mode
end to end on the emulator with amxbase and dhcp-client installed by stock pkgadd (boot-time DHCP, ifdown release,
INIT-REBOOT).

## 2026-10-31 — dhcpc 1.0 and the dhcp-client package; profile(4), profile.d(4), nodename(4) (6199cc3, 22e309d, 8a0bddf)

dhcpc 1.0 (/usr/sbin/dhcpc, dhcpc(1M)): DLPI for INIT, INIT-REBOOT and after a lease ends; from BOUND a UDP socket on
port 68 renews at T1 by unicast and rebinds at T2 by broadcast; every change goes through dhcpc-hook; no option 61; CLI
and files as the hook contract fixes them. The dhcp-client package (dhcpc 1.0-1: SET=base, DEPENDS amix-base, not essential). One-hour
soak on the 2.1c bench image: 112 renewals, 4 rebinds, no ICMP. Pages profile(4), profile.d(4) and nodename(4);
amxbase 1.0-3. tapdhcpd.py gains a control file (silent / norenew / nak), --dns and --hostname.

## 2026-10-31 — our own /etc/profile; amxbase 1.0-2 (720849d)

amix-base ships its own /etc/profile: the stock 2.1p2a file plus the guarded line that sources /etc/profile.d/*.sh
built at package time from amix-system's etc/profile (sha256-checked against system/MANIFEST.sha256) and
etc/profile.add; no Commodore bytes in amix. The other six base config files stay STOCK_ETC. amxbase 1.0-2, 87552 B.
test-profile.sh 8/0 (dash, bash); passes on the emulator under the 1991 sh and ksh.

## 2026-10-31 — ifup/ifdown, dhcpc-hook, the new inetinit; the amix-base package (5d31cb3, 17a7587, 382c5e0)

ifup and ifdown (/usr/sbin, ifup(1M)): one apply step in ifup.subr serves a static line and a DHCP lease (address,
default route — the first interface to set one keeps it — host name, this host's hosts line, the five DNS parts), each
only when it changes; drivers from /etc/inet/link.d, units probed by dlpi-mac; DHCP bounded by ifup_dhcpwait with a
static fallback; `ifup -n` dry run. /usr/lib/inet/dhcpc-hook (BOUND/RENEW/REBIND/EXPIRE/RELEASE) to the hook contract.
The new /etc/init.d/inetinit (S69inet/K69inet) runs `ifup -a` through rc_bg. amix-base (amxbase 1.0-1): SET=base,
ESSENTIAL=yes, the seven base config files from stock, nine conffiles; md5 9b90dc1686357983962186b611003b5e, 87040 B. Host
tests 64/0 (dash, bash × three awks); passes on the emulator under the 1991 sh on the live aen0.

## 2026-10-30 — rc.subr, the interfaces parser, dlpi-mac; man follows PATH (e86d073, 5365158, eb8622d, 17fb7d5)

rc.subr (/usr/lib/amix/rc.subr): rc_log, rc_enabled and rc_conf (read /etc/rc.conf, never source it), rc_bg (a
time-bounded background run, output in /var/adm/rclog/<svc>) and rc_mknod (major from `kbootset major`, the caller's
as fallback); pages rc.subr(1M) and rc.conf(4). The /etc/inet/interfaces parser in ifup.subr, with interfaces(4).
dlpi-mac (/usr/sbin) prints any DLPI Ethernet interface's address, with dlpi-mac(1M). man shows a command's page
(1, 1m, 8) for the binary PATH runs; other sections stay add-on first; -a shows both. Host tests 53/0, 46/0, 58/0
(four awks); every run passes on the emulated stock 2.1c.

## 2026-10-30 — the DLPI probe, the skeleton and man (243a729, 258e67d, d179358)

dhcprobe (gcc-cross-amix, stock libc/libnsl/libsocket only) and tapdhcpd.py, a one-client test DHCP responder, prove
the client's DLPI rules 1–4, 6 and 8 on aen0 under Amiberry (docs/dhcp-probe.md): Style 1, ATTACH dropped, MAC in BIND_ACK,
stale bound slots, frames 14 bytes longer than their datagram, and a renew needing a UDP socket bound to 68. The
directory gets its README, MIT LICENSE, plan and the amix-base / dhcp-client package split. man, installed as
/usr/amix/bin/man, shows the add-on pages in /opt/amix/man first and passes the rest to the stock man, with its own
cache in /var/opt/amix/catman; host tests 27/0, passes on the emulator with /usr/catman untouched.
