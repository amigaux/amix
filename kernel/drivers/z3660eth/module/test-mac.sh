#!/bin/sh
# Host test of z3660eth_machi_ok(), the MAC_HI shape check of the probe in
# z3660eth_map(): open-bus words (every lane 0xFF or 0x00, or a mix) are
# absent, firmware words (MAC bytes 0-1 in the low half, unicast) present.
# The function is cut out of src/z3660eth.c as it is, so the test runs the
# shipped text.  Usage: module/test-mac.sh
set -e
top=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
awk '/^z3660eth_machi_ok\(hi\)$/ { on = 1; print "static int" }
     on { print } on && /^}$/ { exit }' "$top/src/z3660eth.c" > "$tmp/machi.c"
grep -q '^}$' "$tmp/machi.c" || { echo "test-mac: z3660eth_machi_ok not found"; exit 1; }
cat > "$tmp/t.c" <<'C'
#include <stdio.h>
#include "machi.c"
static int fails, n;
static void
t(unsigned long hi, int want, char *what)
{
	n++;
	if (z3660eth_machi_ok(hi) != want) {
		printf("FAIL 0x%08lx (%s): %s, want %s\n", hi, what,
		    want ? "absent" : "present", want ? "present" : "absent");
		fails++;
	}
}
int
main()
{
	t(0xFFFFFFFFUL, 0, "open bus, 0xFF in every lane");
	t(0x00000000UL, 0, "open bus, 0x00 in every lane");
	t(0x00FF00FFUL, 0, "mixed lanes, upper half set");
	t(0xFFFF0080UL, 0, "mixed lanes, upper half set");
	t(0x0000FFFFUL, 0, "low half 0xFF: multicast bit");
	t(0x00000180UL, 0, "multicast 01:80");
	t(0x00010080UL, 0, "one stray upper bit");
	t(0x00000080UL, 1, "bench MAC 00:80:51:01:02:03, firmware default 00:80:10:00:01:00");
	t(0x00000200UL, 1, "locally administered 02:00");
	t(0x0000FE12UL, 1, "fe:12, unicast");
	if (fails)
		return 1;
	printf("test-mac: ok (%d cases)\n", n);
	return 0;
}
C
${HOSTCC:-cc} -w -std=gnu89 -o "$tmp/t" "$tmp/t.c" -I"$tmp"
"$tmp/t"
