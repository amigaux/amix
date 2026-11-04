#!/bin/sh
# test-lease.sh -- host test of dhcpc's lease handling, compiled from
# dhcpc.c itself: a DHCPACK's options parsed (the time servers, option 42,
# among them), the lease lines written from it, and the hook given every
# one of them in its environment.
#
#   sh userland/base/dhcpc/test-lease.sh [cc]     (default cc)
#
# DHCPC_C=<file> tests another copy of dhcpc.c.
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
CC=${1:-cc}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-lease.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0
same() { # same <name> <want> <got>
	if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: want '$2', got '$3'"; fi
}
SRC=${DHCPC_C:-$here/dhcpc.c}

# the defines, struct lease, and the functions named, as dhcpc.c has them
{
	grep '^#define' "$SRC"
	awk '/^struct lease \{/ { on = 1 } on { print } on && /^};/ { exit }' "$SRC"
	for f in get32 get16 put32 ipstr dhcpparse leaselines hook
	do
		awk -v f="$f" '
		$0 ~ "^" f "\\(" { on = 1; print prev }
		on { print }
		on && /^}/ { exit }
		{ prev = $0 }' "$SRC"
	done
} > "$T/parts.c"
same "the parts found in dhcpc.c" 7 "$(grep -c '^[a-z0-9]*(.*)$' "$T/parts.c")"

cat > "$T/main.c" <<'EOF'
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static char *ifname = "aen0";
static unsigned long xid = 0x12345678UL;
static unsigned char mac[6] = { 0, 0x80, 0x10, 0xff, 0xff, 1 };
static int logfd = -1;
static void say(const char *f, ...) { }
#include "parts.c"

static unsigned char m[600];
static unsigned char *o;

static void opt(int code, int len, const unsigned char *v)
{
	*o++ = code; *o++ = len; memcpy(o, v, len); o += len;
}

/* argv[1]: the number of time servers in option 42 (0 = no option);
 * argv[2]: "env" runs the hook ($DHCPC_HOOK) instead of printing the lines */
int main(int argc, char **argv)
{
	static unsigned char ack[] = { 5 }, mask[] = { 255, 255, 255, 0 },
	    rt[] = { 192, 0, 2, 1 }, dns[] = { 192, 0, 2, 14, 192, 0, 2, 23 },
	    sid[] = { 192, 0, 2, 1 }, secs[] = { 0, 0, 0x0e, 0x10 },
	    ntp[] = { 192, 0, 2, 123, 198, 51, 100, 7, 203, 0, 113, 5, 192, 0, 2, 9 },
	    host[] = { 'a', 'm', 'i', 'x' };
	struct lease l;
	char buf[1024];
	int n = atoi(argv[1]), t;

	m[0] = 2;
	put32(m + 4, xid);
	memcpy(m + 28, mac, 6);
	put32(m + 16, 0xc0000226UL);		/* 192.0.2.38 */
	put32(m + 236, COOKIE);
	o = m + 240;
	opt(53, 1, ack);
	opt(1, 4, mask);
	opt(3, 4, rt);
	opt(6, 8, dns);
	opt(12, 4, host);
	if (n)
		opt(42, 4 * n, ntp);
	opt(54, 4, sid);
	opt(51, 4, secs);
	*o++ = 255;
	t = dhcpparse(m, (int)(o - m), &l);
	if (t != 5)
		return 3;
	if (argc > 2)
		return hook("BOUND", &l, 0xc0000221UL);	/* an old address: every line */
	leaselines(&l, buf, 0UL);
	fputs(buf, stdout);
	return 0;
}
EOF
if ! $CC -std=gnu89 -w -o "$T/t" "$T/main.c" 2> "$T/cc.err"; then
	cat "$T/cc.err"
	echo "test-lease: cannot compile"
	exit 1
fi

lines() { # lines <ntp line>: the lease as written
	printf 'DHCP_IF=aen0\nDHCP_ADDR=192.0.2.38\nDHCP_MASK=255.255.255.0\nDHCP_ROUTER=192.0.2.1\nDHCP_DNS=192.0.2.14 192.0.2.23\nDHCP_HOSTNAME=amix\nDHCP_SERVER=192.0.2.1\n%s\nDHCP_LEASE=3600\nDHCP_T1=1800\nDHCP_T2=3150' "$1"
}
same "two time servers" "$(lines 'DHCP_NTP=192.0.2.123 198.51.100.7')" "$("$T/t" 2)"
same "no option 42: an empty line" "$(lines 'DHCP_NTP=')" "$("$T/t" 0)"
same "four given: the first three kept" "$(lines 'DHCP_NTP=192.0.2.123 198.51.100.7 203.0.113.5')" "$("$T/t" 4)"

# the hook gets every line, DHCP_OLD_ADDR the last of them, with TZ set
printf '#!/bin/sh\nenv | grep "^DHCP_" | sort > %s/env\n' "$T" > "$T/hook"
chmod +x "$T/hook"
DHCPC_HOOK=$T/hook TZ=:EET "$T/t" 3 env
same "hook: all twelve variables" 12 "$(wc -l < "$T/env" | tr -d ' ')"
same "hook: the time servers" "DHCP_NTP=192.0.2.123 198.51.100.7 203.0.113.5" "$(grep '^DHCP_NTP=' "$T/env")"
same "hook: the old address" "DHCP_OLD_ADDR=192.0.2.33" "$(grep '^DHCP_OLD_ADDR=' "$T/env")"

echo "test-lease: $pass passed, $fail failed ($CC)"
[ "$fail" -eq 0 ]
