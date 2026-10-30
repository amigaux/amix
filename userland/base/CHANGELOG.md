# Changelog

## 2026-10-30 — the DHCP stage-0 probe, the skeleton and man (243a729, 258e67d, d179358)

dhcprobe (gcc-cross-amix, stock libc/libnsl/libsocket only) and tapdhcpd.py, a one-client test DHCP responder, prove
P-36 §4.4 rules 1–4, 6 and 8 on aen0 under Amiberry (docs/dhcp-probe.md): Style 1, ATTACH dropped, MAC in BIND_ACK,
stale bound slots, frames 14 bytes longer than their datagram, and a renew needing a UDP socket bound to 68. The
directory gets its README, MIT LICENSE, plan and the amix-base / dhcp-client package split. man, installed as
/usr/amix/bin/man, shows the add-on pages in /opt/amix/man first and passes the rest to the stock man, with its own
cache in /var/opt/amix/catman; host tests 27/0, E1 PASS with /usr/catman untouched.
