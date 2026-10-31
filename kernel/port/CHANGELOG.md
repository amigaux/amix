# Changelog

## 2026-10-31 — the pin moves to our fork's k46-module 0d37eb1 (5910d09)

port.pin moves from d0e8857 to amigaux/amix-040-060-port k46-module 0d37eb1 (P-38 S2.3), the sources of cut
68060-261031-52 with the quirk 90/91/92 fixes. The README says the port is built from our fork: we fix it there, the
build pins it, and changes go to Antti's repository as pull requests when we choose to. The k30 kit is byte-identical;
the k46 kit differs only in its PORT_REV and NOTICE lines; kit-test 0 failed.
