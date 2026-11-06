#!/bin/sh
# test-keep.sh -- host test of dhcpc's bound states, compiled from dhcpc.c
# itself: keep() and sleepuntil() on a clock of their own, against a
# scripted server. A lease of 120 s (T1 60, T2 105) renews by unicast at T1,
# rebinds by broadcast at T2, ends at 120 with EXPIRE; an ACK extends it
# (RENEW, REBIND), a NAK ends it at once. The wall clock may be set after
# the lease is bound (the time sync at boot, which needs the lease first):
# the times stay the lease's own, back or forward.
#
#   sh userland/base/dhcpc/test-keep.sh [cc]     (default cc)
#
# DHCPC_C=<file> tests another copy of dhcpc.c.
#
# MIT licence, see LICENSE at the top of the repository.
set -u
here=$(cd "$(dirname "$0")" && pwd)
CC=${1:-cc}
T=$(mktemp -d "${TMPDIR:-/tmp}/test-keep.XXXXXX")
trap 'rm -rf "${T:?}"' EXIT
pass=0 fail=0
same() { # same <name> <want> <got>
	if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL %s:\nwant:\n%s\ngot:\n%s\n' "$1" "$2" "$3"; fi
}
SRC=${DHCPC_C:-$here/dhcpc.c}

# the defines, struct lease, and the functions named, as dhcpc.c has them
{
	grep '^#define' "$SRC"
	awk '/^struct lease \{/ { on = 1 } on { print } on && /^};/ { exit }' "$SRC"
	for f in sleepuntil keep
	do
		awk -v f="$f" '
		$0 ~ "^" f "\\(" { on = 1; print prev }
		on { print }
		on && /^}/ { exit }
		{ prev = $0 }' "$SRC"
	done
} > "$T/parts.c"
same "keep() and sleepuntil() found in dhcpc.c" 2 "$(grep -c '^keep(l)$\|^sleepuntil(t)$' "$T/parts.c")"

cat > "$T/main.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/time.h>
static long now;			/* the clock: seconds since the lease */
static long off;			/* the wall clock's step, made after binding */
static volatile int stop;
static unsigned long xid;
static int errno;
static char *mode;			/* the server: see main */
static int sends;
static long time(long *p) { return now + off; }
static long mono(void) { return now; }
/* select() with no descriptors: a wait of tv */
static int t_select(int n, fd_set *r, fd_set *w, fd_set *e, struct timeval *tv)
{
	now += tv->tv_sec;
	return 0;
}
#define select t_select
static int udpopen(void) { return 3; }
static int close(int s) { return 0; }
static int unlink(const char *p) { return 0; }
static void say(const char *f, ...) { }
static char leasefile[] = "lease";
static char *ipstr(unsigned long a)
{
	static char b[4][16];
	static int i;

	i = (i + 1) & 3;
	sprintf(b[i], "%lu.%lu.%lu.%lu", a >> 24, (a >> 16) & 255, (a >> 8) & 255, a & 255);
	return b[i];
}
struct lease;
static void writelease(struct lease *l) { }
static int hook(char *why, struct lease *l, unsigned long old);
static int udpsend(int s, int type, unsigned long ciaddr, unsigned long dst, unsigned long sid);
static int udprecv(int s, int secs, struct lease *l);
#include "parts.c"

static int hook(char *why, struct lease *l, unsigned long old)
{
	printf("%ld hook %s %s\n", now, why, ipstr(l->addr));
	if (now > 200)
		stop = 1;
	return 0;
}
static int udpsend(int s, int type, unsigned long ciaddr, unsigned long dst, unsigned long sid)
{
	printf("%ld send %s %s from %s\n", now, type == DHCPREQUEST ? "REQUEST" : "?",
	    dst == 0xffffffffUL ? "broadcast" : ipstr(dst), ipstr(ciaddr));
	sends++;
	return 0;
}
/* the server: mode "silent" never answers; "ack<n>" ACKs the n-th request
 * (a lease of 120 s again), "nak<n>" NAKs it */
static int udprecv(int s, int secs, struct lease *l)
{
	int n = atoi(mode + 3);

	if (n == sends && strncmp(mode, "ack", 3) == 0) {
		memset(l, 0, sizeof(*l));
		l->addr = 0xc0000226UL;
		l->secs = 120; l->t1 = 60; l->t2 = 105;
		now += 1;
		mode = "silent";
		return DHCPACK;
	}
	if (n == sends && strncmp(mode, "nak", 3) == 0) {
		now += 1;
		return DHCPNAK;
	}
	now += secs;
	return 0;
}

int main(int argc, char **argv)
{
	struct lease l;

	mode = argv[1];
	memset(&l, 0, sizeof(l));	/* bound at 0, on both clocks */
	l.addr = 0xc0000226UL;		/* 192.0.2.38 */
	l.server = 0xc0000201UL;	/* 192.0.2.1 */
	l.secs = 120; l.t1 = 60; l.t2 = 105;
	l.got = time((long *)0);
	if (argc > 2)
		off = atol(argv[2]);	/* then the clock is set */
	printf("keep %d\n", keep(&l));
	return 0;
}
EOF
if ! $CC -std=gnu89 -w -o "$T/t" -I"$T" "$T/main.c" 2> "$T/cc.err"; then
	cat "$T/cc.err" >&2
	echo "test-keep: cannot compile"
	exit 1
fi

# a retry waits half the time left, but at least 60 s (RFC 2131 4.4.5): a
# 120 s lease is asked once by unicast, once by broadcast
same "no server: renew at T1, rebind at T2, EXPIRE at the end" "60 send REQUEST 192.0.2.1 from 192.0.2.38
105 send REQUEST broadcast from 192.0.2.38
120 hook EXPIRE 192.0.2.38
keep 0" "$("$T/t" silent)"
same "ACK at T1: RENEW, the next T1 from it" "60 send REQUEST 192.0.2.1 from 192.0.2.38
61 hook RENEW 192.0.2.38
121 send REQUEST 192.0.2.1 from 192.0.2.38
166 send REQUEST broadcast from 192.0.2.38
181 hook EXPIRE 192.0.2.38
keep 0" "$("$T/t" ack1)"
same "ACK to the broadcast: REBIND" "60 send REQUEST 192.0.2.1 from 192.0.2.38
105 send REQUEST broadcast from 192.0.2.38
106 hook REBIND 192.0.2.38
166 send REQUEST 192.0.2.1 from 192.0.2.38
211 send REQUEST broadcast from 192.0.2.38
226 hook EXPIRE 192.0.2.38
keep 0" "$("$T/t" ack2)"
same "NAK: EXPIRE at once" "60 send REQUEST 192.0.2.1 from 192.0.2.38
61 hook EXPIRE 192.0.2.38
keep 0" "$("$T/t" nak1)"
# the wall clock set 7 hours back after binding (a clock that ran on the
# host's zone): the renew at T1 still
same "clock set back: renew at T1" "60 send REQUEST 192.0.2.1 from 192.0.2.38
61 hook RENEW 192.0.2.38
121 send REQUEST 192.0.2.1 from 192.0.2.38
166 send REQUEST broadcast from 192.0.2.38
181 hook EXPIRE 192.0.2.38
keep 0" "$("$T/t" ack1 -25200)"
# set 20 years forward (a battery clock that had stopped): no EXPIRE at once
same "clock set forward: renew at T1" "60 send REQUEST 192.0.2.1 from 192.0.2.38
61 hook RENEW 192.0.2.38
121 send REQUEST 192.0.2.1 from 192.0.2.38
166 send REQUEST broadcast from 192.0.2.38
181 hook EXPIRE 192.0.2.38
keep 0" "$("$T/t" ack1 631152000)"

echo "test-keep: $pass passed, $fail failed ($CC)"
[ "$fail" -eq 0 ]
