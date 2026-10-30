/*
 * dhcprobe -- prove the DHCP client's DLPI rules on a 1991 SVR4.0 Ethernet
 * driver before any real client code is written (P-36 W5 stage S0).
 *
 *   dhcprobe [-a] [-x] [-d secs] [-w secs] [-i ifaddr] <device>  e.g. /dev/aen0
 *
 * It does, in order, and prints one line per step (see README.md for the
 * format):
 *
 *   1. open the node; DL_INFO_REQ under an alarm; print the provider style,
 *      the state and whether the ack carries an address;
 *   2. DL_ATTACH_REQ only if the provider is Style 2 (under an alarm);
 *   3. DL_BIND_REQ for SAP 0x0800, the MAC taken from the DL_BIND_ACK; a
 *      second DL_INFO_REQ once bound.  While waiting for any ack, every
 *      DL_UNITDATA_IND is thrown away and counted ("stray");
 *   4. DHCPDISCOVER (broadcast flag set) to ff:ff:ff:ff:ff:ff through
 *      DL_UNITDATA_REQ, IP and UDP headers built here; wait for an OFFER
 *      whose xid and chaddr match, trusting only the IP and UDP lengths;
 *      then DHCPREQUEST (broadcast flag clear, so the server answers by
 *      unicast) and wait for the ACK the same way;
 *   5. close the stream; open a UDP socket bound to port 68; RENEW by
 *      unicast to the server, then REBIND by broadcast to 255.255.255.255;
 *      wait for each ACK on the socket.
 *
 *   -a   also run the side tests on a separate stream: DL_ATTACH_REQ sent
 *        to a Style 1 provider, and an unknown primitive; each is timed.
 *   -x   stop after step 3 (no DHCP traffic).
 *   -d   wait this long after the open, then count the DL_UNITDATA_IND
 *        already queued on the stream before any request is sent (a
 *        stream slot reused from an earlier bind keeps its SAP), and do
 *        the same after the bind.
 *   -w   seconds to wait for each DHCP reply (default 6).
 *   -i   the address the interface already has; with it the probe asks for
 *        that address (INIT-REBOOT style option 50 in the DISCOVER).
 *
 * The probe applies nothing: no ifconfig, no route, no file is written.
 * Exit 0 when every step that ran passed, 1 on a usage or open error,
 * 2 when a step failed.
 *
 * Built with gcc-cross-amix (m68k-cbm-sysv4, the period compiler) against
 * the stock headers and libc/libsocket/libnsl: build.sh.
 *
 * MIT licence, see LICENSE at the top of the repository.
 */
#include <sys/types.h>
#include <sys/stropts.h>
#include <sys/dlpi.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdio.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <string.h>

/* the stock headers declare none of these */
extern int errno;
extern long time();
extern int getpid(), alarm(), close(), atoi(), getopt(), sleep();
extern int getmsg(), putmsg();
extern int socket(), bind(), sendto(), recvfrom(), setsockopt();
extern char *optarg;
extern int optind;

#define SAP_IP		0x0800
#define ACK_SECS	5
#define BOOTPS		67
#define BOOTPC		68

#define DHCPDISCOVER	1
#define DHCPOFFER	2
#define DHCPREQUEST	3
#define DHCPACK		5
#define DHCPNAK		6

#define STEP(s)		printf("STEP %s\n", s), fflush(stdout)

static volatile int timedout;
static int strays;
static int failed;

static unsigned char mac[6];
static unsigned char bcast[6] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
static unsigned long xid;
static unsigned long leased, server, ifaddr;
static int waitsecs = 6;

union buf {
	long	align;
	char	c[2048];
};

static void
onalarm(sig)
int sig;
{
	timedout = 1;
}

static void
arm(secs)
int secs;
{
	timedout = 0;
	signal(SIGALRM, onalarm);
	alarm(secs);
}

static void
fail(what)
char *what;
{
	printf("FAIL %s\n", what);
	fflush(stdout);
	failed = 1;
}

static char *
ipstr(a)
unsigned long a;
{
	static char s[4][20];
	static int n;

	n = (n + 1) & 3;
	sprintf(s[n], "%lu.%lu.%lu.%lu", (a >> 24) & 255, (a >> 16) & 255,
	    (a >> 8) & 255, a & 255);
	return s[n];
}

static char *
macstr(m)
unsigned char *m;
{
	static char s[20];

	sprintf(s, "%02x:%02x:%02x:%02x:%02x:%02x",
	    m[0], m[1], m[2], m[3], m[4], m[5]);
	return s;
}

static unsigned long
get32(p)
unsigned char *p;
{
	return ((unsigned long)p[0] << 24) | ((unsigned long)p[1] << 16) |
	    ((unsigned long)p[2] << 8) | p[3];
}

static void
put32(p, v)
unsigned char *p;
unsigned long v;
{
	p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

static void
put16(p, v)
unsigned char *p;
unsigned int v;
{
	p[0] = v >> 8; p[1] = v;
}

static unsigned int
get16(p)
unsigned char *p;
{
	return (p[0] << 8) | p[1];
}

/* ones' complement sum over n bytes, folded later */
static unsigned long
csum(sum, p, n)
unsigned long sum;
unsigned char *p;
int n;
{
	while (n > 1) {
		sum += (p[0] << 8) | p[1];
		p += 2;
		n -= 2;
	}
	if (n)
		sum += p[0] << 8;
	return sum;
}

static unsigned int
fold(sum)
unsigned long sum;
{
	while (sum >> 16)
		sum = (sum & 0xffff) + (sum >> 16);
	return (~sum) & 0xffff;
}

/*
 * Wait for a control message other than DL_UNITDATA_IND; return its
 * primitive, or -1 on timeout or error.  Strays are counted, never kept.
 */
static long
getack(fd, u, secs)
int fd;
union buf *u;
int secs;
{
	struct strbuf ctl, dat;
	union buf d;
	int flags;
	long prim;

	arm(secs);
	for (;;) {
		ctl.maxlen = sizeof(u->c);
		ctl.len = 0;
		ctl.buf = u->c;
		dat.maxlen = sizeof(d.c);
		dat.len = 0;
		dat.buf = d.c;
		flags = 0;
		if (getmsg(fd, &ctl, &dat, &flags) < 0) {
			alarm(0);
			if (errno == EINTR && timedout)
				return -1;
			printf("NOTE getmsg errno %d\n", errno);
			return -1;
		}
		if (ctl.len < (int)sizeof(long)) {
			printf("NOTE data-only message (%d bytes) dropped\n",
			    dat.len);
			continue;
		}
		prim = *(long *)u->c;
		if (prim == DL_UNITDATA_IND) {
			strays++;
			continue;
		}
		alarm(0);
		return prim;
	}
}

static int
sendctl(fd, p, n)
int fd;
char *p;
int n;
{
	struct strbuf ctl;

	ctl.maxlen = 0;
	ctl.len = n;
	ctl.buf = p;
	return putmsg(fd, &ctl, (struct strbuf *)0, 0);
}

static void
showinfo(tag, u)
char *tag;
union buf *u;
{
	dl_info_ack_t *ia = (dl_info_ack_t *)u->c;

	printf("INFO %s style=%s state=%lu mac_type=%lu max_sdu=%lu "
	    "addr_length=%lu addr_offset=%lu", tag,
	    ia->dl_provider_style == DL_STYLE1 ? "1" :
	    ia->dl_provider_style == DL_STYLE2 ? "2" : "?",
	    ia->dl_current_state, ia->dl_mac_type, ia->dl_max_sdu,
	    ia->dl_addr_length, ia->dl_addr_offset);
	if (ia->dl_addr_offset && ia->dl_addr_length >= 6)
		printf(" addr=%s",
		    macstr((unsigned char *)u->c + ia->dl_addr_offset));
	printf("\n");
}

static int
info(fd, tag, style)
int fd;
char *tag;
long *style;
{
	dl_info_req_t req;
	union buf u;
	long prim;
	long t0;

	req.dl_primitive = DL_INFO_REQ;
	t0 = time((long *)0);
	if (sendctl(fd, (char *)&req, sizeof(req)) < 0) {
		fail("putmsg DL_INFO_REQ");
		return -1;
	}
	prim = getack(fd, &u, ACK_SECS);
	if (prim != DL_INFO_ACK) {
		printf("INFO %s no DL_INFO_ACK (got %ld) after %lds\n", tag,
		    prim, time((long *)0) - t0);
		return -1;
	}
	showinfo(tag, &u);
	if (style)
		*style = ((dl_info_ack_t *)u.c)->dl_provider_style;
	return 0;
}

/* returns the answering primitive, -1 = no answer */
static long
attach(fd, secs)
int fd;
int secs;
{
	dl_attach_req_t req;
	union buf u;

	req.dl_primitive = DL_ATTACH_REQ;
	req.dl_ppa = 0;
	if (sendctl(fd, (char *)&req, sizeof(req)) < 0)
		return -2;
	return getack(fd, &u, secs);
}

static int
dlbind(fd)
int fd;
{
	dl_bind_req_t req;
	dl_bind_ack_t *ack;
	union buf u;
	long prim;

	memset((char *)&req, 0, sizeof(req));
	req.dl_primitive = DL_BIND_REQ;
	req.dl_sap = SAP_IP;
	req.dl_service_mode = DL_CLDLS;
	if (sendctl(fd, (char *)&req, sizeof(req)) < 0) {
		fail("putmsg DL_BIND_REQ");
		return -1;
	}
	prim = getack(fd, &u, ACK_SECS);
	if (prim != DL_BIND_ACK) {
		printf("BIND no DL_BIND_ACK (got %ld)\n", prim);
		if (prim == DL_ERROR_ACK)
			printf("BIND error_ack errno=%lu unix=%lu\n",
			    ((dl_error_ack_t *)u.c)->dl_errno,
			    ((dl_error_ack_t *)u.c)->dl_unix_errno);
		return -1;
	}
	ack = (dl_bind_ack_t *)u.c;
	if (ack->dl_addr_length < 6 || ack->dl_addr_offset == 0) {
		printf("BIND ack without an address\n");
		return -1;
	}
	memcpy((char *)mac, u.c + ack->dl_addr_offset, 6);
	printf("BIND ok sap=0x%04lx addr_length=%lu mac=%s strays=%d\n",
	    ack->dl_sap, ack->dl_addr_length, macstr(mac), strays);
	return 0;
}

/*
 * Build a BOOTP/DHCP message at p; returns its length.
 * ciaddr, requested and sid are 0 when absent.
 */
static int
dhcpmsg(p, type, bflag, ciaddr, requested, sid)
unsigned char *p;
int type, bflag;
unsigned long ciaddr, requested, sid;
{
	unsigned char *o;
	static unsigned char prl[] = { 1, 3, 6, 12, 15, 28, 51, 54, 58, 59 };

	memset((char *)p, 0, 300);
	p[0] = 1;			/* BOOTREQUEST */
	p[1] = 1;			/* Ethernet */
	p[2] = 6;
	put32(p + 4, xid);
	put16(p + 10, bflag ? 0x8000 : 0);
	put32(p + 12, ciaddr);
	memcpy((char *)p + 28, (char *)mac, 6);
	put32(p + 236, 0x63825363UL);
	o = p + 240;
	*o++ = 53; *o++ = 1; *o++ = type;
	*o++ = 61; *o++ = 7; *o++ = 1;
	memcpy((char *)o, (char *)mac, 6); o += 6;
	*o++ = 57; *o++ = 2; put16(o, 576); o += 2;
	if (requested) {
		*o++ = 50; *o++ = 4; put32(o, requested); o += 4;
	}
	if (sid) {
		*o++ = 54; *o++ = 4; put32(o, sid); o += 4;
	}
	*o++ = 55; *o++ = sizeof(prl);
	memcpy((char *)o, (char *)prl, sizeof(prl)); o += sizeof(prl);
	*o++ = 255;
	return (o - p) < 300 ? 300 : (o - p);
}

/* IP + UDP around a DHCP message of n bytes at ip + 28; returns total */
static int
ipudp(ip, n, src, dst)
unsigned char *ip;
int n;
unsigned long src, dst;
{
	unsigned char *udp = ip + 20;
	unsigned long s;
	int total = 28 + n;

	ip[0] = 0x45; ip[1] = 0;
	put16(ip + 2, total);
	put16(ip + 4, (unsigned)(xid & 0xffff));
	put16(ip + 6, 0);
	ip[8] = 64; ip[9] = 17;
	put16(ip + 10, 0);
	put32(ip + 12, src);
	put32(ip + 16, dst);
	put16(ip + 10, fold(csum(0L, ip, 20)));
	put16(udp, BOOTPC);
	put16(udp + 2, BOOTPS);
	put16(udp + 4, 8 + n);
	put16(udp + 6, 0);
	s = csum(0L, ip + 12, 8);
	s += 17 + 8 + n;
	s = csum(s, udp, 8 + n);
	s = fold(s);
	put16(udp + 6, s ? s : 0xffff);
	return total;
}

static int
dlsend(fd, type, bflag, requested, sid)
int fd, type, bflag;
unsigned long requested, sid;
{
	union buf c, d;
	struct strbuf ctl, dat;
	dl_unitdata_req_t *ud = (dl_unitdata_req_t *)c.c;
	int n;

	memset(c.c, 0, sizeof(dl_unitdata_req_t));
	ud->dl_primitive = DL_UNITDATA_REQ;
	ud->dl_dest_addr_length = 6;
	ud->dl_dest_addr_offset = sizeof(dl_unitdata_req_t);
	memcpy(c.c + sizeof(dl_unitdata_req_t), (char *)bcast, 6);
	n = dhcpmsg((unsigned char *)d.c + 28, type, bflag, 0L, requested, sid);
	n = ipudp((unsigned char *)d.c, n, 0L, 0xffffffffUL);
	ctl.maxlen = 0;
	ctl.len = sizeof(dl_unitdata_req_t) + 6;
	ctl.buf = c.c;
	dat.maxlen = 0;
	dat.len = n;
	dat.buf = d.c;
	if (putmsg(fd, &ctl, &dat, 0) < 0) {
		printf("SEND putmsg errno %d\n", errno);
		return -1;
	}
	printf("SEND dlpi type=%d bflag=%d ip_len=%d xid=%08lx to=%s\n",
	    type, bflag, n, xid, macstr(bcast));
	fflush(stdout);
	return 0;
}

/*
 * Check a DHCP message m of mlen bytes: our xid and chaddr, BOOTREPLY.
 * Fills the lease fields; returns the DHCP type, or 0 = not ours.
 */
static int
dhcpparse(m, mlen, tag)
unsigned char *m;
int mlen;
char *tag;
{
	unsigned char *o, *end;
	int type = 0;
	unsigned long sid = 0, mask = 0, router = 0, lease = 0, t1 = 0, t2 = 0;
	unsigned long dns = 0;

	if (mlen < 240 || m[0] != 2 || get32(m + 4) != xid ||
	    memcmp((char *)m + 28, (char *)mac, 6) != 0 ||
	    get32(m + 236) != 0x63825363UL)
		return 0;
	end = m + mlen;
	for (o = m + 240; o < end && *o != 255; ) {
		if (*o == 0) {
			o++;
			continue;
		}
		if (o + 2 > end || o + 2 + o[1] > end)
			break;
		switch (o[0]) {
		case 53: type = o[2]; break;
		case 54: sid = get32(o + 2); break;
		case 1: mask = get32(o + 2); break;
		case 3: router = get32(o + 2); break;
		case 6: dns = get32(o + 2); break;
		case 51: lease = get32(o + 2); break;
		case 58: t1 = get32(o + 2); break;
		case 59: t2 = get32(o + 2); break;
		}
		o += 2 + o[1];
	}
	printf("DHCP %s type=%d yiaddr=%s sid=%s mask=%s router=%s dns=%s "
	    "lease=%lu t1=%lu t2=%lu\n", tag, type, ipstr(get32(m + 16)),
	    ipstr(sid), ipstr(mask), ipstr(router), ipstr(dns), lease, t1, t2);
	if (type == DHCPOFFER || type == DHCPACK) {
		leased = get32(m + 16);
		if (sid)
			server = sid;
	}
	return type;
}

/*
 * Wait on the DLPI stream for a DHCP reply of the wanted type.  Only the
 * IP total length and the UDP length are trusted; the frame length is
 * printed beside them.
 */
static int
dlrecv(fd, want)
int fd, want;
{
	struct strbuf ctl, dat;
	union buf c, d;
	unsigned char *ip, *udp, *src, *dst;
	dl_unitdata_ind_t *ui;
	int flags, iplen, ihl, udplen, type, other = 0;
	long prim;

	arm(waitsecs);
	for (;;) {
		ctl.maxlen = sizeof(c.c);
		ctl.len = 0;
		ctl.buf = c.c;
		dat.maxlen = sizeof(d.c);
		dat.len = 0;
		dat.buf = d.c;
		flags = 0;
		if (getmsg(fd, &ctl, &dat, &flags) < 0) {
			alarm(0);
			printf("RECV timeout after %ds, %d other frames\n",
			    waitsecs, other);
			return -1;
		}
		if (ctl.len < (int)sizeof(long))
			continue;
		prim = *(long *)c.c;
		if (prim != DL_UNITDATA_IND) {
			printf("RECV unexpected primitive %ld\n", prim);
			continue;
		}
		ui = (dl_unitdata_ind_t *)c.c;
		ip = (unsigned char *)d.c;
		if (dat.len < 28 || (ip[0] >> 4) != 4 || ip[9] != 17) {
			other++;
			continue;
		}
		ihl = (ip[0] & 15) * 4;
		iplen = get16(ip + 2);
		udp = ip + ihl;
		if (iplen > dat.len || ihl + 8 > iplen ||
		    get16(udp + 2) != BOOTPC) {
			other++;
			continue;
		}
		udplen = get16(udp + 4);
		if (udplen < 8 || ihl + udplen > iplen) {
			printf("RECV bad udp length %d (ip %d)\n", udplen,
			    iplen);
			other++;
			continue;
		}
		type = dhcpparse(udp + 8, udplen - 8, "dlpi");
		if (!type) {
			other++;
			continue;
		}
		dst = (unsigned char *)c.c + ui->dl_dest_addr_offset;
		src = (unsigned char *)c.c + ui->dl_src_addr_offset;
		printf("RECV dlpi frame_data=%d ip_len=%d udp_len=%d "
		    "ipsum=%s dst=%s", dat.len, iplen, udplen,
		    fold(csum(0L, ip, ihl)) == 0 ? "ok" : "bad", macstr(dst));
		printf(" src=%s ip_dst=%s other=%d strays_so_far=%d\n",
		    macstr(src), ipstr(get32(ip + 16)), other, strays);
		if (type == want || type == DHCPNAK) {
			alarm(0);
			return type;
		}
	}
}

static int
udpround(s, type, dst, ciaddr, tag)
int s, type;
unsigned long dst, ciaddr;
char *tag;
{
	struct sockaddr_in to, from;
	union buf b;
	int n, fromlen, got;

	n = dhcpmsg((unsigned char *)b.c, type, 0, ciaddr, 0L, 0L);
	memset((char *)&to, 0, sizeof(to));
	to.sin_family = AF_INET;
	to.sin_port = htons(BOOTPS);
	to.sin_addr.s_addr = htonl(dst);
	if (sendto(s, b.c, n, 0, (struct sockaddr *)&to, sizeof(to)) < 0) {
		printf("UDP %s sendto %s errno %d\n", tag, ipstr(dst), errno);
		return -1;
	}
	printf("UDP %s sent REQUEST ciaddr=%s to=%s:%d len=%d\n", tag,
	    ipstr(ciaddr), ipstr(dst), BOOTPS, n);
	fflush(stdout);
	arm(waitsecs);
	for (;;) {
		fromlen = sizeof(from);
		got = recvfrom(s, b.c, sizeof(b.c), 0,
		    (struct sockaddr *)&from, &fromlen);
		if (got < 0) {
			alarm(0);
			printf("UDP %s no reply in %ds (errno %d)\n", tag,
			    waitsecs, errno);
			return -1;
		}
		printf("UDP %s from %s:%d len=%d\n", tag,
		    ipstr(ntohl(from.sin_addr.s_addr)), ntohs(from.sin_port),
		    got);
		n = dhcpparse((unsigned char *)b.c, got, tag);
		if (n == DHCPACK || n == DHCPNAK) {
			alarm(0);
			return n;
		}
	}
}

/* count the DL_UNITDATA_IND waiting on the stream; nothing else expected */
static int
drain(fd)
int fd;
{
	struct strbuf ctl, dat;
	union buf c, d;
	int flags, n = 0, other = 0;

	arm(1);
	for (;;) {
		ctl.maxlen = sizeof(c.c);
		ctl.len = 0;
		ctl.buf = c.c;
		dat.maxlen = sizeof(d.c);
		dat.len = 0;
		dat.buf = d.c;
		flags = 0;
		if (getmsg(fd, &ctl, &dat, &flags) < 0)
			break;
		if (ctl.len >= (int)sizeof(long) && *(long *)c.c == DL_UNITDATA_IND)
			n++;
		else
			other++;
	}
	alarm(0);
	if (other)
		printf("NOTE drain saw %d other messages\n", other);
	return n;
}

static void
sidetests(dev)
char *dev;
{
	int fd;
	long prim, t0;
	struct { long prim; long pad[3]; } bogus;

	STEP("side-tests");
	if ((fd = open(dev, O_RDWR)) < 0) {
		printf("SIDE open errno %d\n", errno);
		return;
	}
	t0 = time((long *)0);
	prim = attach(fd, 4);
	printf("SIDE attach_on_style1 answer=%s after=%lds\n",
	    prim == -1 ? "none" : prim == DL_OK_ACK ? "DL_OK_ACK" :
	    prim == DL_ERROR_ACK ? "DL_ERROR_ACK" : "other",
	    time((long *)0) - t0);
	bogus.prim = 0x55;
	bogus.pad[0] = bogus.pad[1] = bogus.pad[2] = 0;
	t0 = time((long *)0);
	if (sendctl(fd, (char *)&bogus, sizeof(bogus)) < 0)
		printf("SIDE unknown_primitive putmsg errno %d\n", errno);
	else {
		union buf u;

		prim = getack(fd, &u, 4);
		printf("SIDE unknown_primitive answer=%s after=%lds\n",
		    prim == -1 ? "none" : prim == DL_ERROR_ACK ?
		    "DL_ERROR_ACK" : "other", time((long *)0) - t0);
	}
	if (info(fd, "side-after", (long *)0) == 0)
		printf("SIDE stream usable after both\n");
	close(fd);
}

int
main(argc, argv)
int argc;
char **argv;
{
	char *dev;
	int fd, s, c, one = 1, sides = 0, linkonly = 0, r, delay = 0;
	long style = 0, t0;
	struct sockaddr_in me;

	while ((c = getopt(argc, argv, "axd:w:i:")) != -1) {
		switch (c) {
		case 'd': delay = atoi(optarg); break;
		case 'a': sides = 1; break;
		case 'x': linkonly = 1; break;
		case 'w': waitsecs = atoi(optarg); break;
		case 'i': {
			unsigned int a, b, cc, d;

			if (sscanf(optarg, "%u.%u.%u.%u", &a, &b, &cc, &d) != 4)
				goto usage;
			ifaddr = ((unsigned long)a << 24) |
			    ((unsigned long)b << 16) | (cc << 8) | d;
			break;
		}
		default:
			goto usage;
		}
	}
	if (optind != argc - 1) {
usage:
		fprintf(stderr,
		    "usage: dhcprobe [-a] [-x] [-w secs] [-i addr] device\n");
		exit(1);
	}
	dev = argv[optind];
	setbuf(stdout, (char *)0);
	xid = ((unsigned long)time((long *)0) << 8) ^ getpid();

	STEP("open");
	t0 = time((long *)0);
	if ((fd = open(dev, O_RDWR)) < 0) {
		printf("OPEN %s errno %d after %lds\n", dev, errno,
		    time((long *)0) - t0);
		exit(1);
	}
	printf("OPEN %s ok after %lds\n", dev, time((long *)0) - t0);
	if (delay) {
		sleep(delay);
		printf("QUEUED before any request: %d DL_UNITDATA_IND\n",
		    drain(fd));
	}

	STEP("rule1-info");
	if (info(fd, "unbound", &style) < 0) {
		fail("rule1 DL_INFO_ACK");
		exit(2);
	}
	printf("RULE1 ok strays=%d\n", strays);

	STEP("rule2-attach");
	if (style == DL_STYLE2) {
		r = attach(fd, ACK_SECS);
		printf("RULE2 style2 attach answer=%ld\n", (long)r);
		if (r != DL_OK_ACK)
			fail("rule2 attach");
	} else
		printf("RULE2 style1 attach skipped\n");

	STEP("rule3-bind");
	if (dlbind(fd) < 0) {
		fail("rule3 bind");
		exit(2);
	}
	info(fd, "bound", (long *)0);
	printf("RULE3 ok strays=%d\n", strays);
	if (delay) {
		sleep(delay);
		printf("QUEUED after bind: %d DL_UNITDATA_IND\n", drain(fd));
	}

	if (sides)
		sidetests(dev);
	if (linkonly) {
		close(fd);
		printf("DONE link-only strays=%d failed=%d\n", strays, failed);
		exit(failed ? 2 : 0);
	}

	STEP("rule4-discover");
	if (dlsend(fd, DHCPDISCOVER, 1, ifaddr, 0L) < 0 ||
	    dlrecv(fd, DHCPOFFER) != DHCPOFFER) {
		fail("rule4 offer");
		close(fd);
		exit(2);
	}
	printf("RULE4 offer ok leased=%s server=%s\n", ipstr(leased),
	    ipstr(server));
	STEP("rule4-request");
	if (dlsend(fd, DHCPREQUEST, 0, leased, server) < 0 ||
	    dlrecv(fd, DHCPACK) != DHCPACK) {
		fail("rule4 ack");
		close(fd);
		exit(2);
	}
	printf("RULE4 ack ok leased=%s (unicast reply on the dlpi stream)\n",
	    ipstr(leased));
	close(fd);
	printf("CLOSE dlpi stream closed strays_total=%d\n", strays);

	STEP("rule6-udp");
	if ((s = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
		printf("UDP socket errno %d\n", errno);
		fail("rule6 socket");
		exit(2);
	}
	memset((char *)&me, 0, sizeof(me));
	me.sin_family = AF_INET;
	me.sin_port = htons(BOOTPC);
	me.sin_addr.s_addr = htonl(INADDR_ANY);
	if (bind(s, (struct sockaddr *)&me, sizeof(me)) < 0) {
		printf("UDP bind errno %d\n", errno);
		fail("rule6 bind 68");
		exit(2);
	}
	printf("UDP bound *:68\n");
	xid++;
	r = udpround(s, DHCPREQUEST, server, leased, "renew");
	if (r == DHCPACK)
		printf("RULE6 renew ok (unicast ACK accepted on *:68)\n");
	else
		fail("rule6 renew");
	if (setsockopt(s, SOL_SOCKET, SO_BROADCAST, (char *)&one,
	    sizeof(one)) < 0)
		printf("UDP SO_BROADCAST errno %d\n", errno);
	xid++;
	r = udpround(s, DHCPREQUEST, 0xffffffffUL, leased, "rebind");
	if (r == DHCPACK)
		printf("RULE8 rebind ok (broadcast send from the socket)\n");
	else
		fail("rule8 rebind");
	close(s);
	printf("DONE strays=%d failed=%d\n", strays, failed);
	exit(failed ? 2 : 0);
}
