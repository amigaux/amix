## 2026-11-16 — packages 1.1.2-1: MNT ZZ9000 cards, two units, zz9k_probe (e1df8849, 723f2763, f1d999b5)

The fork is pinned at 5b9d49b (module 1.1.2-1): a real MNT ZZ9000 in Zorro II and Zorro III beside the Z3660, two units. The packages gain /dev/zz9001 and /dev/zz9001i (0660 / 0444 root sys), zz9000(7), zz9k_probe with zz9k_probe(1M), and the card files /etc/display.d/zz9000 and zz9001 with probe lines; the z3660 file is the package's own copy. The zz9001 file passes -dev /dev/zz9001 and needs x11r63 6.3-10 or later. k30's description names kern30m -78 for a Zorro III ZZ9000. Major 49 is 1.1's, so there is no kbootset floor.

## 2026-11-04 — packages 1.1.1-4 (408e557)

The copyright file's licence heading names the component; objects unchanged.

