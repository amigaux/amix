## 2026-11-16 — packages 1.1.2-2 and 1.1.2-3: the Z3660's RTG in its 68030 mode without a setting (51526e37, 31279c98)

The fork is pinned at 9f66293 (module 1.1.2-3; 1.1.2-2 was 65cf5b4). In its emulated 68030 mode the Z3660's RTG has no AutoConfig entry. 1.1.2-2: with fixed=1 the fixed base is read when the list holds any Z3660 identity (0x144B product 1, 2 or 3), where 1.1.2-1 needed product 1. 1.1.2-3: fixed is an int, 0 (the default) reads the fixed base, guarded by bprobe, when a Z3660 is listed and no AutoConfig entry gave its RTG; 1 as in 1.1.2-2; -1 never; kbootset refuses fixed=yes. pkginfo describes the three values; zz9000(7) updated; the tools are unchanged. Packages zrtg30 f8c6072a, zrtg46 c525a55e, two rolls identical, the same bytes on master.

## 2026-11-16 — packages 1.1.2-1: MNT ZZ9000 cards, two units, zz9k_probe (a1307b08, a304a850, 7bd3ea38)

The fork is pinned at 5b9d49b (module 1.1.2-1): a real MNT ZZ9000 in Zorro II and Zorro III beside the Z3660, two units. The packages gain /dev/zz9001 and /dev/zz9001i (0660 / 0444 root sys), zz9000(7), zz9k_probe with zz9k_probe(1M), and the card files /etc/display.d/zz9000 and zz9001 with probe lines; the z3660 file is the package's own copy. The zz9001 file passes -dev /dev/zz9001 and needs x11r63 6.3-10 or later. k30's description names kern30m -78 for a Zorro III ZZ9000. Major 49 is 1.1's, so there is no kbootset floor.

## 2026-11-04 — packages 1.1.1-4 (408e557)

The copyright file's licence heading names the component; objects unchanged.

