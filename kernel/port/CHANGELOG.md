# Changelog

## 2026-10-31 — cut 68060-261031-53 is the k46 cut of record; kern46m -53 (0560124)

port.pin moves to 727cbe7 and cuts/CURRENT to 68060-261031-53: the port's cut with gcc14's binutils 2.43.1 and amix
b391504's module core and kit, whose registry carries c 48 random. kabi k46.1.3 and abi 18c0a1c9 unchanged; unix
affe663a. cuts/build.sh reproduces its seven sums from the public port, on the host and in the build container.
kern46m k46.1.3.261031-53 (unminted) packages it and asks for kbootset -30 or later; -52 stays the metal record.

## 2026-10-31 — cuts/build.sh, make dist's kernel-k46 hook (598c4ed)

Rebuilds the port fork's cut of record named in cuts/CURRENT, as the fork has it at port.pin: the fork and paula in
cache repos, NetBSD syssrc through toolchain/fetch-distfile, toolchain/m68k-gnu-bin first on PATH; in the container
gcc-cross-amix is fetched as a git repo at its pin for the port's wrapper check. kern46m reads its output by default.
CURRENT names -52, which needs binutils 2.46; the port's -53 (gcc14 binutils, c 48 random) replaces it.

## 2026-10-31 — pkg/build.sh passes a recipe's exit 3 through (f9f59db)

kern46m exits 3 with a [MISSING] line naming make kernel-k46 when K46M_SRC is unset or holds no cut; with
the cut, the bytes are unchanged.

## 2026-10-31 — pkg/: the kern46m recipe moves in (b7f0715)

The kern46m recipe (kernel-k46-m) moves in from amix-packages 450ba6a, the twin of kernel/k30/pkg.
K46M_SRC names the port's cut output. Re-rolled, kern46m k46.1.3.261031-52 matches the minted one but for the control
stamps. Two runs byte-identical.

## 2026-10-31 — the pin moves to our fork's k46-module 0d37eb1 (5910d09)

port.pin moves from d0e8857 to amigaux/amix-040-060-port k46-module 0d37eb1, the sources of cut
68060-261031-52 with the quirk 90/91/92 fixes. The README says the port is built from our fork: we fix it there, the
build pins it, and changes go to Antti's repository as pull requests when we choose to. The k30 kit is byte-identical;
the k46 kit differs only in its PORT_REV and NOTICE lines; kit-test 0 failed.
