# kernel/drivers/z3660rtg

The RTG graphics driver of the Z3660 accelerator and of MNT ZZ9000 cards
(Zorro II and Zorro III). It is built from our fork of Ignacio Soriano's
zz9000-amix, amigaux/amix-z3660rtg; the 1.1 releases take it from its
`release-1.1` branch. We fix it in our fork, the build takes it by pin, and changes go to
the original repository as pull requests when we choose to.

This directory holds this README, `pkg/`, the recipe of the kernel-space
packages z3660rtg-k30 and z3660rtg-k46 that make dist rolls from the driver,
and `z3660rtg.pin`, which names the fork and the exact commit the build uses.
A pin file is one line, `<git URL> <full commit hash>`; the build fetches that
exact commit. The driver can move in later with its history.

The packages also carry X's card files (display.d(4)): `z3660`, `zz9000` and
`zz9001` (a ZZ9000 beside a Z3660, unit 1; it needs x11r63 6.3-10 or later,
whose server takes `-dev`), each with a `probe` line that runs `zz9k_probe`,
which tells the boards apart by the identity the driver gives. With amix-base
1.0-35 or later the automatic card choice uses it; an older base ignores the
line, so on a ZZ9000 there the card is named in /etc/display (`card zz9000`, or
`card zz9001` beside a Z3660). No card file names `%p`, so the files are safe
with either base. The z3660 file is the package's own copy and equals the
example of display.d(4). A Zorro III
ZZ9000 on the 68030 line needs kern30m k30.1.5.261115-78 or later.
