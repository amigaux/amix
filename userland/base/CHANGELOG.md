# Changelog

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
