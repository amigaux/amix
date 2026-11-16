# kernel/drivers/va2000

The driver of the MNT VA2000 RTG graphics card, `/dev/va2000`, as a loadable
module for both kernel lines. It is built from our fork of Antti Sokero's
va2000-amix, amigaux/va2000-amix, on its `next` branch. We fix it in our fork,
the build takes it by pin, and changes go to the original repository as pull
requests when we choose to.

This directory holds this README, `pkg/`, the recipe of the kernel-space
packages va2000-k30 and va2000-k46 that make dist rolls from the driver, and
`va2000.pin`, which names the fork and the exact commit the build uses. A pin
file is one line, `<git URL> <full commit hash>`; the build fetches that exact
commit. The driver can move in later with its history.

The module is demand class: it loads at the first open of `/dev/va2000`
(character major 68) and stays only when it finds a board. It needs a kbootset
whose registry has major 68, 1.1.0.261115-46 or later. What the module does
and does not do (the console stays on the Amiga's own display) is in the
fork's `module/README.md`; the page is va2000(7).

The packages also install `/etc/display.d/va2000` (`pkg/va2000.display`), the
card's file for xstart (amix-base display.d(4)): with `card auto`, or
`card va2000` in `/etc/display`, xstart runs the X server `Xrtg -card va2000`
(x11r63 6.3-10 or later) on the card. The file has no probe line, because the
node opens only when a board answers, and no monitor switch, because the card
passes the Amiga picture through and the driver puts it back at the last close.

**Status: not tested on a real card.** The VA2000 cannot be emulated, so the
packages are tested only for their install and for a boot with the module in
the boot set and no board present.
