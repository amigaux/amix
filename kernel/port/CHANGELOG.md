# Changelog

## 2026-10-31 — pkg/build.sh passes a recipe's exit 3 through (f9f59db)

kern46m exits 3 with a [MISSING] line naming P-38 S2.3 (the port station) when K46M_SRC is unset or holds no cut; with
the cut, the bytes are unchanged.

## 2026-10-31 — pkg/: the kern46m recipe moves in (b7f0715)

The kern46m recipe (kernel-k46-m) moves in from amix-packages 450ba6a (P-38 S3.3), the twin of kernel/k30/pkg.
K46M_SRC names the port's cut output. Re-rolled, kern46m k46.1.3.261031-52 matches the minted one but for the control
stamps (D-g). Two runs byte-identical.

## 2026-10-31 — the pin moves to our fork's k46-module 0d37eb1 (5910d09)

port.pin moves from d0e8857 to amigaux/amix-040-060-port k46-module 0d37eb1 (P-38 S2.3), the sources of cut
68060-261031-52 with the quirk 90/91/92 fixes. The README says the port is built from our fork: we fix it there, the
build pins it, and changes go to Antti's repository as pull requests when we choose to. The k30 kit is byte-identical;
the k46 kit differs only in its PORT_REV and NOTICE lines; kit-test 0 failed.
