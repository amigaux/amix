# Changelog

## 2026-11-16 — together-1.1: packages a release must carry together (8ed5810c)

together-1.1 lists pairs a release must carry together (`<name> <version>: needs <name> <version>`), seeded with z3660rtg-k30/-k46 1.1.2-1 needing amix-base 1.0-35. The README describes the file.

## 2026-11-15 — README: the lock's `source userland` line (cf99407e)

The lock carries a `source userland` line for each FORKDIRS directory.

## 2026-11-15 — the 1.1.1 locks (75ef713f..75abc4ea)

amix-1.1.1.lock (the public rebuild, sha256 29f765ae…) and amix-1.1.1-published.lock (on the published 1.1 tree, b37fb273…), both from make dist at amix 7d9e944f with every RAM-disk image fetched by URL. The README names xsurf 1.0.0-3 and both locks with their sha256 and how they differ.

## 2026-11-14 — 1.1.1 on the published 1.1 tree; kbootset -43 carried (a83e00bc)

carried-1.1 lists kbootset 1.1.0.261105-43 (c75f62d5, built at the tag 1.1), which 1.1.1's kbootset -45 moves to the older block. The README says how a point release is built, on the published tree with RELEASE_PREVIOUS, and names 1.1.1's two locks.

## 2026-11-10 — the 1.1 locks (c1d4a11)

amix-1.1.lock (671008ee) is what a public rebuild of the tag 1.1 gives; amix-1.1-published.lock (caeca530) records what pkg.amigaux.org/1.1 holds. The README names both by sha256 and explains the difference.

## 2026-11-07 — carried-1.1 keeps dhcpc -8, ldramix -13 and zscsi -8 (ff7f6b4)

carried-1.1 also keeps dhcpc-1.0-8, ldramix-1.0.261104-13, zscsi30-1.0.0-8 and zscsi46-1.0.0-8, published in 1.1 and no longer built; each is byte for byte what make dist built at 6029ab5. The list now holds all 25 of the published tree's older versions.

## 2026-11-05 — x11r63-6.3-7 carried (f077a89)

`release/carried-1.1` gains x11r63-6.3-7 (21 rows), and the amixbench-1.3 lock exception is gone.

## 2026-11-05 — carried-1.1 (3e72129)

`carried-1.1` lists the older versions the 1.1 repository keeps, each with the commit that rebuilds it; `make lock` refuses a tree whose older versions are not exactly those, and records the published tree's catalog digest.

## 2026-11-02 — NOTICES.md (76494f9)

NOTICES.md lists the acknowledgements the release notes carry: the Gordon Ross clause of the k46 kernel's floating-point emulation (kern46m) and the Caldera clause of Heirloom tar (/usr/sbin/tar, heirtar), each with where its full texts are.
