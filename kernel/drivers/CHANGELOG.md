# Changelog

Changes to the shared kernel/drivers README and the fork pins. Each source driver keeps its own CHANGELOG in its
directory.

## 2026-11-16 — va2000 1.1.0-2: the card file /etc/display.d/va2000 (eca4df61)

The package installs /etc/display.d/va2000 (display.d(4)), so xstart starts Xrtg -card va2000 on the card. It has no probe line (the node opens only when a board answers), no monitor switch and no limits. The module is unchanged (1.1.0). Packages va200030 a2363193, va200046 a662f898, two rolls identical, the same bytes on master.

## 2026-11-15 — va2000-k30/-k46 1.1.0-1: the kbootset floor (9f03dcd1)

APKG_KBOOTSET=1.1.0.261115-46, so the catalog row carries kbootset= and apkg 0.3.12 installs kbootset -46 first; the descriptions drop the manual step.

## 2026-11-15 — va2000: the fork pin and the va2000-k30/-k46 packages (51663042, cd4e93ae)

va2000/ pins our fork of Antti Sokero's va2000-amix (amigaux/va2000-amix dbb5b4f, module 1.1.0-1) with the recipe of va2000-k30/-k46 1.1.0-1: /dev/va2000 (c 68, demand class), va2000.h, va2000(7). The node is 0660 root sys, as z3660rtg's /dev/zz9000, since it maps the card's registers and framebuffer. Needs kbootset -46; the descriptions give the step after a late kbootset upgrade. Tested in emulation without a board.

## 2026-11-14 — README rows for xsurf and the buddha flavour (1ffc4613)

The README lists xsurf among the source drivers, and gayle-ide as the A4000 and A1200 Gayle IDE plus the Buddha / Catweasel Z-II flavour (buddha).

## 2026-11-01 — paula and z3660rtg rolled from amix (b63a859, b05fb92)

- paula-k30/-k46 1.1.0-2: the module 1.1.0-1 (amix-paula a111e57) on the gcc-2.7.2.3-33ebadc kit: /dev/paula (c 54 0, 0660 root audio), /usr/include/paula.h, depend on amix-base.
- z3660rtg-k30/-k46 1.1.1-3: the module 1.1.1-1 (amix-z3660rtg a9d39a1, startx-rtg runs /opt/amix/X11R6/bin/Xzz9000) on the 33ebadc kit: /dev/zz9000 and /dev/zz9000i, display.d/z3660, zz9k_monsw, rtg-kbdback, ztop and startx-rtg; xztop moved to its own package.

## 2026-11-01 — gayle and cdfs 1.1.0-6 on the 33ebadc kit (e53c106)

gayle-k30/-k46 1.1.0-6 (module 1.1.0-3) and cdfs-k30/-k46 1.1.0-6 (module 1.1.0-4) built with the gcc-2.7.2.3-33ebadc kit; only the cc= tag changes.

## 2026-10-31 — the four forks pinned from amigaux (99a6d8a)

The forks other developers started are pinned from our amigaux forks (P-38 S3.1, D-d): cdfs (main fd6cad8, new),
gayle-ide (main 24ed009), paula (dlm-module 1b2736d) and z3660rtg (dlm-module 7dd6d67), each in
kernel/drivers/<name>/<name>.pin with a README. kernel/drivers/README.md says the forks are ours: we fix them there,
the build takes them by pin, and pull requests go upstream when we choose to.
