# Changelog

## 2026-10-31 — dhcpc and dlpi-mac built with GCC 14; inittab(4) (5520414, 63812ca)

dhcpc and dlpi-mac are built with GCC 14 (gcc14-cross-amix b51ff39, -m68020-60 -mno-strict-align) against the stock
libraries only: NEEDED libnsl.so and /usr/lib/libc.so.1, no RPATH, nothing from /opt/amix (T-56 D6). dhcp-client 1.0-2,
amix-base 1.0-7. inittab(4): our page for the inittab amix-base ships (the format, the shipped entries, why the dlm line
comes first); amix-base 1.0-8. E1 two boots PASS: the S1 checks and the S2 boot path with the GCC 14 binaries.

## 2026-10-31 — devnodes, D-N21's boot step; link.d's major column optional (41f4274, 35aab99)

devnodes (/etc/init.d/devnodes = rc2.d/S20devnodes, devnodes(1M)) re-creates a missing /dev node from its c/b record in
the installed-objects DB: at the registry's major (`kbootset major <class>`) when the record's class names its module,
else at the record's; a stock node that differs from its record is logged and left. amxbase 1.0-6. link.d's major
column is optional, needed only for drivers the registry doesn't name (aen keeps 18); rc_mknod takes - for no major.
Host tests devnodes 27/0, rc 51/0, ifup 70/0; E1 two-boot run PASS (three removed stock nodes re-created).

## 2026-10-31 — amxbase 1.0-4/1.0-5: inetinit as core records it, /etc/inittab with the dlm line; S2 base half (fe3e116, 1866d0f, 66ad365)

amxbase 1.0-4: the network start script is recorded as stock core records it (S69inet the file, inetinit and K69inet
links to it); stock pkgadd ignored the other shape and kept the stock script. docs/package-split.md: the installer's
(W7) seven steps, measured on E1. amxbase 1.0-5: /etc/inittab is stock plus C3-5 §5's dlm line as the first sysinit
entry (etc/mkinittab.sh, test-inittab.sh 8/0); still a conffile, no longer STOCK_ETC. S2, base half: ifup's dhcp mode
end to end on the emulator with amxbase and dhcp-client installed by stock pkgadd (boot-time DHCP, ifdown release,
INIT-REBOOT).

## 2026-10-31 — dhcpc 1.0 and the dhcp-client package; profile(4), profile.d(4), nodename(4) (6199cc3, 22e309d, 8a0bddf)

dhcpc 1.0 (/usr/sbin/dhcpc, dhcpc(1M)): DLPI for INIT, INIT-REBOOT and after a lease ends; from BOUND a UDP socket on
port 68 renews at T1 by unicast and rebinds at T2 by broadcast; every change goes through dhcpc-hook; no option 61; CLI
and files as frozen in T-55. The dhcp-client package (dhcpc 1.0-1: SET=base, DEPENDS amix-base, not essential). One-hour
soak on the 2.1c bench image: 112 renewals, 4 rebinds, no ICMP. Pages profile(4), profile.d(4) and nodename(4);
amxbase 1.0-3. tapdhcpd.py gains a control file (silent / norenew / nak), --dns and --hostname.

## 2026-10-31 — our own /etc/profile; amxbase 1.0-2 (720849d)

amix-base ships its own /etc/profile: the stock 2.1p2a file plus the guarded line that sources /etc/profile.d/*.sh
(D-N23), built at package time from amix-system's etc/profile (sha256-checked against system/MANIFEST.sha256) and
etc/profile.add; no Commodore bytes in amix. The other six D-N24 files stay STOCK_ETC. amxbase 1.0-2, 87552 B.
test-profile.sh 8/0 (dash, bash); E1 run8 PASS under the 1991 sh and ksh.

## 2026-10-31 — ifup/ifdown, dhcpc-hook, the new inetinit; the amix-base package (5d31cb3, 17a7587, 382c5e0)

ifup and ifdown (/usr/sbin, ifup(1M)): one apply step in ifup.subr serves a static line and a DHCP lease (address,
default route — the first interface to set one keeps it — host name, this host's hosts line, the five DNS parts), each
only when it changes; drivers from /etc/inet/link.d, units probed by dlpi-mac; DHCP bounded by ifup_dhcpwait with a
static fallback; `ifup -n` dry run. /usr/lib/inet/dhcpc-hook (BOUND/RENEW/REBIND/EXPIRE/RELEASE) to the T-55 contract.
The new /etc/init.d/inetinit (S69inet/K69inet) runs `ifup -a` through rc_bg. amix-base (amxbase 1.0-1): SET=base,
ESSENTIAL=yes, the seven D-N24 files from stock, nine conffiles; md5 9b90dc1686357983962186b611003b5e, 87040 B. Host
tests 64/0 (dash, bash × three awks); E1 run7 PASS under the 1991 sh on the live aen0.

## 2026-10-30 — rc.subr, the interfaces parser, dlpi-mac; man follows PATH (e86d073, 5365158, eb8622d, 17fb7d5)

rc.subr (/usr/lib/amix/rc.subr): rc_log, rc_enabled and rc_conf (read /etc/rc.conf, never source it), rc_bg (a
time-bounded background run, output in /var/adm/rclog/<svc>) and rc_mknod (major from `kbootset major`, the caller's
as fallback); pages rc.subr(1M) and rc.conf(4). The /etc/inet/interfaces parser in ifup.subr, with interfaces(4).
dlpi-mac (/usr/sbin) prints any DLPI Ethernet interface's address, with dlpi-mac(1M). man shows a command's page
(1, 1m, 8) for the binary PATH runs; other sections stay add-on first; -a shows both. Host tests 53/0, 46/0, 58/0
(four awks); all E1 runs PASS on stock 2.1c.

## 2026-10-30 — the DHCP stage-0 probe, the skeleton and man (243a729, 258e67d, d179358)

dhcprobe (gcc-cross-amix, stock libc/libnsl/libsocket only) and tapdhcpd.py, a one-client test DHCP responder, prove
P-36 §4.4 rules 1–4, 6 and 8 on aen0 under Amiberry (docs/dhcp-probe.md): Style 1, ATTACH dropped, MAC in BIND_ACK,
stale bound slots, frames 14 bytes longer than their datagram, and a renew needing a UDP socket bound to 68. The
directory gets its README, MIT LICENSE, plan and the amix-base / dhcp-client package split. man, installed as
/usr/amix/bin/man, shows the add-on pages in /opt/amix/man first and passes the rest to the stock man, with its own
cache in /var/opt/amix/catman; host tests 27/0, E1 PASS with /usr/catman untouched.
