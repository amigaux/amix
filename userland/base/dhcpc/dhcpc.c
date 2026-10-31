/*
 * dhcpc -- the DHCP client of Amix's base system (P-36 section 4).
 *
 *   dhcpc [-b secs] <if>     get a lease, apply it through the hook, keep it
 *   dhcpc -x <if>            release the lease and end the daemon
 *   dhcpc -q <if>            print the lease; exit 0 when one is held
 *
 * One daemon per interface. The first lease is waited for in the
 * foreground, for at most secs seconds with -b: exit 0 when it is bound and
 * applied, 2 when none came yet (the daemon goes on trying in the
 * background), 1 when the interface cannot do DHCP or a daemon already
 * holds it.
 *
 * The rules (P-36 section 4.4), with no per-driver code:
 *   - INIT, INIT-REBOOT, SELECTING and REQUESTING, and REBINDING after the
 *     lease ended, go over the interface's DLPI node: DL_INFO_REQ, then
 *     DL_ATTACH_REQ only for a Style 2 provider, then DL_BIND_REQ on 0x0800
 *     (the MAC from the ack), every wait under an alarm and every
 *     DL_UNITDATA_IND that arrives meanwhile thrown away; our own IP and
 *     UDP headers, to the Ethernet broadcast address; only the IP and UDP
 *     lengths of a reply are trusted, never the frame's;
 *   - from BOUND on the DLPI stream is closed (an IP-type stream gets a copy
 *     of every IP frame) and a UDP socket bound to port 68 is kept: it
 *     renews at T1 by unicast and rebinds at T2 by broadcast, and while it
 *     exists IP does not answer the server's unicast replies with ICMP;
 *   - dhcpc edits no system file. Every change goes through
 *     /usr/lib/inet/dhcpc-hook <if> BOUND|RENEW|REBIND|EXPIRE|RELEASE, with
 *     the lease in DHCP_* variables (userland/base/docs/package-split.md);
 *   - no client identifier (option 61): replies are matched by xid and
 *     chaddr.
 *
 * Files: /var/inet/dhcpc/<if>.lease (the hook's DHCP_* lines; its time of
 * writing is when the lease was obtained), /var/inet/dhcpc/<if>.pid, the log
 * /var/adm/dhcpc.log. The DLPI node is found in /etc/inet/link.d.
 *
 * Built with gcc-cross-amix (m68k-cbm-sysv4, the period compiler) against
 * the stock headers and libraries: build.sh.
 *
 * MIT licence, see LICENSE at the top of the repository.
 */
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/stropts.h>
#include <sys/dlpi.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <stdio.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <dirent.h>

/* the stock headers declare none of these */
extern int errno;
extern long time(), lseek();
extern int getpid(), getppid(), fork(), execve(), wait(), pipe(), read();
extern int write(), close(), unlink(), rename(), kill(), alarm(), dup2();
extern int setpgrp(), getopt(), getmsg(), putmsg(), mkdir();
extern void _exit();
extern int socket(), bind(), sendto(), recvfrom(), setsockopt(), select();
extern char *optarg;
extern int optind;

#define LINKD		"/etc/inet/link.d"
#define STATEDIR	"/var/inet/dhcpc"
#define LOGFILE		"/var/adm/dhcpc.log"
#define HOOK		"/usr/lib/inet/dhcpc-hook"	/* DHCPC_HOOK, for tests */
#define HOOKPATH	"PATH=/sbin:/usr/sbin:/usr/bin:/etc"

#define SAP_IP		0x0800
#define ACK_SECS	5
#define BOOTPS		67
#define BOOTPC		68
#define COOKIE		0x63825363UL
#define INFINITE	0xffffffffUL

#define DHCPDISCOVER	1
#define DHCPOFFER	2
#define DHCPREQUEST	3
#define DHCPACK		5
#define DHCPNAK		6
#define DHCPRELEASE	7

#define MAXDNS		3

union buf {
	long	align;
	char	c[2048];
};

/* a lease as the server gave it; addresses in host order */
struct lease {
	unsigned long	addr, mask, router, server;
	unsigned long	dns[MAXDNS];
	int		ndns;
	char		host[64];
	unsigned long	secs, t1, t2;
	long		got;		/* when it was obtained (time()) */
};

static char *ifname;
static char node[80];		/* a 63-byte node prefix and a unit */
static long ppa;
static unsigned char mac[6];
static unsigned char bcast[6] = { 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
static unsigned long xid;
static volatile int timedout, stop;
static int logfd = -1;
static int tellfd = -1;		/* the foreground parent's pipe, until bound */
static char leasefile[80], pidfile[80];

static void sleepuntil();

/* --- small helpers ------------------------------------------------------- */

static unsigned long
get32(p)
unsigned char *p;
{
	return ((unsigned long)p[0] << 24) | ((unsigned long)p[1] << 16) |
	    ((unsigned long)p[2] << 8) | p[3];
}

static unsigned int
get16(p)
unsigned char *p;
{
	return (p[0] << 8) | p[1];
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

static unsigned long
ipnum(s)
char *s;
{
	unsigned long v = 0, o;
	int i;

	for (i = 0; i < 4; i++) {
		o = 0;
		if (*s < '0' || *s > '9')
			return 0;
		while (*s >= '0' && *s <= '9')
			o = o * 10 + (*s++ - '0');
		if (o > 255 || (i < 3 && *s++ != '.'))
			return 0;
		v = (v << 8) | o;
	}
	return *s && *s != '\n' && *s != ' ' ? 0 : v;
}

/*
 * One line in the log, with the time. The arguments are passed as char *
 * and printed by the format (%s, or %d/%lu for a number cast to char *: one
 * 32-bit word either way on this machine).
 */
static void
say(fmt, a, b, c, d)
char *fmt, *a, *b, *c, *d;
{
	char line[300], when[40];
	long now = time((long *)0);
	int n;

	strftime(when, sizeof(when), "%Y-%m-%d %H:%M:%S", localtime(&now));
	n = sprintf(line, "%s dhcpc[%d] %s: ", when, getpid(), ifname);
	sprintf(line + n, fmt, a, b, c, d);
	strcat(line, "\n");
	if (logfd >= 0)
		write(logfd, line, strlen(line));
}

static void
onalarm(sig)
int sig;
{
	signal(SIGALRM, onalarm);
	timedout = 1;
}

static void
onterm(sig)
int sig;
{
	stop = 1;
}

static void
arm(secs)
int secs;
{
	timedout = 0;
	signal(SIGALRM, onalarm);
	alarm(secs > 0 ? secs : 1);
}

/* ones' complement sum over n bytes */
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

/* --- the node, from /etc/inet/link.d ------------------------------------- */

/* "<prefix> <node prefix> <first> <major> ..." for the driver of ifname */
static int
findnode()
{
	DIR *d;
	struct dirent *e;
	FILE *f;
	char path[300], line[300], pre[32], npre[64];
	int plen, unit;
	char *u;

	for (u = ifname; *u && (*u < '0' || *u > '9'); u++)
		;
	if (!*u)
		return -1;
	plen = u - ifname;
	unit = atoi(u);
	if ((d = opendir(LINKD)) == 0)
		return -1;
	while ((e = readdir(d)) != 0) {
		if (e->d_name[0] == '.')
			continue;
		sprintf(path, "%s/%s", LINKD, e->d_name);
		if ((f = fopen(path, "r")) == 0)
			continue;
		while (fgets(line, sizeof(line), f)) {
			if (strchr(line, '#'))
				*strchr(line, '#') = 0;
			if (sscanf(line, "%31s %63s", pre, npre) != 2)
				continue;
			if ((int)strlen(pre) == plen && strncmp(pre, ifname, plen) == 0) {
				sprintf(node, "%s%d", npre, unit);
				ppa = unit;
				fclose(f);
				closedir(d);
				return 0;
			}
			break;
		}
		fclose(f);
	}
	closedir(d);
	return -1;
}

/* --- DLPI ------------------------------------------------------------------ */

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

/* the next control message other than DL_UNITDATA_IND, or -1 */
static long
getack(fd, u, n)
int fd;
union buf *u;
int *n;
{
	struct strbuf ctl, dat;
	union buf d;
	int flags;

	arm(ACK_SECS);
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
			return -1;
		}
		if (ctl.len < (int)sizeof(long) || *(long *)u->c == DL_UNITDATA_IND)
			continue;
		alarm(0);
		*n = ctl.len;
		return *(long *)u->c;
	}
}

/* open, info, attach (Style 2 only), bind 0x0800; the MAC into mac[] */
static int
dlopen_if()
{
	int fd, n;
	union buf u;
	dl_info_req_t ireq;
	dl_info_ack_t *ia;
	dl_attach_req_t areq;
	dl_bind_req_t breq;
	dl_bind_ack_t *ba;

	if ((fd = open(node, O_RDWR)) < 0) {
		say("cannot open %s (errno %d)", node, (char *)errno, 0, 0);
		return -1;
	}
	ireq.dl_primitive = DL_INFO_REQ;
	if (sendctl(fd, (char *)&ireq, sizeof(ireq)) < 0 ||
	    getack(fd, &u, &n) != DL_INFO_ACK) {
		say("%s: no DL_INFO_ACK", node, 0, 0, 0);
		close(fd);
		return -1;
	}
	ia = (dl_info_ack_t *)u.c;
	if (ia->dl_provider_style == DL_STYLE2) {
		areq.dl_primitive = DL_ATTACH_REQ;
		areq.dl_ppa = ppa;
		if (sendctl(fd, (char *)&areq, sizeof(areq)) < 0 ||
		    getack(fd, &u, &n) != DL_OK_ACK) {
			say("%s: DL_ATTACH_REQ not acknowledged", node, 0, 0, 0);
			close(fd);
			return -1;
		}
	}
	memset((char *)&breq, 0, sizeof(breq));
	breq.dl_primitive = DL_BIND_REQ;
	breq.dl_sap = SAP_IP;
	breq.dl_service_mode = DL_CLDLS;
	if (sendctl(fd, (char *)&breq, sizeof(breq)) < 0 ||
	    getack(fd, &u, &n) != DL_BIND_ACK) {
		say("%s: no DL_BIND_ACK", node, 0, 0, 0);
		close(fd);
		return -1;
	}
	ba = (dl_bind_ack_t *)u.c;
	if (ba->dl_addr_length < 6 || ba->dl_addr_offset == 0 ||
	    ba->dl_addr_offset + 6 > (unsigned long)n) {
		say("%s: DL_BIND_ACK carries no address", node, 0, 0, 0);
		close(fd);
		return -1;
	}
	memcpy((char *)mac, u.c + ba->dl_addr_offset, 6);
	return fd;
}

/* --- DHCP messages ----------------------------------------------------- */

/*
 * A BOOTREQUEST at p; returns its length. ciaddr, requested and sid are 0
 * when absent. Every request asks for the broadcast flag except a renew
 * from a bound address (ciaddr set).
 */
static int
dhcpmsg(p, type, ciaddr, requested, sid)
unsigned char *p;
int type;
unsigned long ciaddr, requested, sid;
{
	unsigned char *o;
	static unsigned char prl[] = { 1, 3, 6, 12, 51, 54, 58, 59 };

	memset((char *)p, 0, 300);
	p[0] = 1;
	p[1] = 1;
	p[2] = 6;
	put32(p + 4, xid);
	put16(p + 10, ciaddr ? 0 : 0x8000);
	put32(p + 12, ciaddr);
	memcpy((char *)p + 28, (char *)mac, 6);
	put32(p + 236, COOKIE);
	o = p + 240;
	*o++ = 53; *o++ = 1; *o++ = type;
	if (type != DHCPRELEASE) {
		*o++ = 57; *o++ = 2; put16(o, 576); o += 2;
	}
	if (requested) {
		*o++ = 50; *o++ = 4; put32(o, requested); o += 4;
	}
	if (sid) {
		*o++ = 54; *o++ = 4; put32(o, sid); o += 4;
	}
	if (type != DHCPRELEASE) {
		*o++ = 55; *o++ = sizeof(prl);
		memcpy((char *)o, (char *)prl, sizeof(prl)); o += sizeof(prl);
	}
	*o++ = 255;
	return (o - p) < 300 ? 300 : (o - p);
}

/*
 * A BOOTREPLY for us (our xid and chaddr): its DHCP type, with the lease
 * fields in *l; 0 when it is not ours.
 */
static int
dhcpparse(m, n, l)
unsigned char *m;
int n;
struct lease *l;
{
	unsigned char *o, *end;
	int type = 0, i, k;

	if (n < 240 || m[0] != 2 || get32(m + 4) != xid ||
	    memcmp((char *)m + 28, (char *)mac, 6) != 0 || get32(m + 236) != COOKIE)
		return 0;
	memset((char *)l, 0, sizeof(*l));
	l->addr = get32(m + 16);
	end = m + n;
	for (o = m + 240; o < end && *o != 255; ) {
		if (*o == 0) {
			o++;
			continue;
		}
		if (o + 2 > end || o + 2 + o[1] > end)
			break;
		switch (o[0]) {
		case 53: type = o[2]; break;
		case 54: if (o[1] >= 4) l->server = get32(o + 2); break;
		case 1: if (o[1] >= 4) l->mask = get32(o + 2); break;
		case 3: if (o[1] >= 4) l->router = get32(o + 2); break;
		case 51: if (o[1] >= 4) l->secs = get32(o + 2); break;
		case 58: if (o[1] >= 4) l->t1 = get32(o + 2); break;
		case 59: if (o[1] >= 4) l->t2 = get32(o + 2); break;
		case 6:
			for (i = 0; i + 4 <= o[1] && l->ndns < MAXDNS; i += 4)
				l->dns[l->ndns++] = get32(o + 2 + i);
			break;
		case 12:
			/* a host name: letters, digits and '-' only */
			for (i = k = 0; i < o[1] && k < (int)sizeof(l->host) - 1; i++) {
				int c = o[2 + i];

				if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
				    (c >= '0' && c <= '9') || (c == '-' && k > 0))
					l->host[k++] = c;
				else
					break;
			}
			l->host[k] = 0;
			break;
		}
		o += 2 + o[1];
	}
	if (l->secs == 0)
		l->secs = 3600;
	if (l->secs != INFINITE) {
		if (l->t1 == 0 || l->t1 >= l->secs)
			l->t1 = l->secs / 2;
		if (l->t2 == 0 || l->t2 >= l->secs || l->t2 <= l->t1)
			l->t2 = l->secs / 8 * 7;
	}
	if (l->mask == 0)
		l->mask = l->addr < 0x80000000UL ? 0xff000000UL :
		    l->addr < 0xc0000000UL ? 0xffff0000UL : 0xffffff00UL;
	return type;
}

/* IP + UDP around a DHCP message of n bytes at ip + 28; returns the total */
static int
ipudp(ip, n)
unsigned char *ip;
int n;
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
	put32(ip + 12, 0L);
	put32(ip + 16, 0xffffffffUL);
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
dlsend(fd, type, requested, sid)
int fd, type;
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
	n = dhcpmsg((unsigned char *)d.c + 28, type, 0L, requested, sid);
	n = ipudp((unsigned char *)d.c, n);
	ctl.maxlen = 0;
	ctl.len = sizeof(dl_unitdata_req_t) + 6;
	ctl.buf = c.c;
	dat.maxlen = 0;
	dat.len = n;
	dat.buf = d.c;
	return putmsg(fd, &ctl, &dat, 0);
}

/*
 * Wait up to secs on the DLPI stream for a reply of type want (or a NAK);
 * the reply's type, or 0. Only the IP total length and the UDP length are
 * trusted.
 */
static int
dlrecv(fd, want, secs, l)
int fd, want, secs;
struct lease *l;
{
	struct strbuf ctl, dat;
	union buf c, d;
	unsigned char *ip, *udp;
	int flags, iplen, ihl, udplen, type;

	arm(secs);
	while (!stop) {
		ctl.maxlen = sizeof(c.c);
		ctl.len = 0;
		ctl.buf = c.c;
		dat.maxlen = sizeof(d.c);
		dat.len = 0;
		dat.buf = d.c;
		flags = 0;
		if (getmsg(fd, &ctl, &dat, &flags) < 0)
			break;
		if (ctl.len < (int)sizeof(long) || *(long *)c.c != DL_UNITDATA_IND)
			continue;
		ip = (unsigned char *)d.c;
		if (dat.len < 28 || (ip[0] >> 4) != 4 || ip[9] != 17)
			continue;
		ihl = (ip[0] & 15) * 4;
		iplen = get16(ip + 2);
		udp = ip + ihl;
		if (iplen > dat.len || ihl + 8 > iplen || get16(udp + 2) != BOOTPC)
			continue;
		udplen = get16(udp + 4);
		if (udplen < 8 || ihl + udplen > iplen)
			continue;
		type = dhcpparse(udp + 8, udplen - 8, l);
		if (type == want || type == DHCPNAK) {
			alarm(0);
			return type;
		}
	}
	alarm(0);
	return 0;
}

/* --- the UDP socket of a bound lease ----------------------------------- */

static int
udpopen()
{
	int s, on = 1;
	struct sockaddr_in me;

	if ((s = socket(AF_INET, SOCK_DGRAM, 0)) < 0)
		return -1;
	setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (char *)&on, sizeof(on));
	setsockopt(s, SOL_SOCKET, SO_BROADCAST, (char *)&on, sizeof(on));
	memset((char *)&me, 0, sizeof(me));
	me.sin_family = AF_INET;
	me.sin_port = htons(BOOTPC);
	me.sin_addr.s_addr = htonl(INADDR_ANY);
	if (bind(s, (struct sockaddr *)&me, sizeof(me)) < 0) {
		close(s);
		return -1;
	}
	return s;
}

static int
udpsend(s, type, ciaddr, dst, sid)
int s, type;
unsigned long ciaddr, dst, sid;
{
	union buf b;
	struct sockaddr_in to;
	int n;

	n = dhcpmsg((unsigned char *)b.c, type, ciaddr, 0L, sid);
	memset((char *)&to, 0, sizeof(to));
	to.sin_family = AF_INET;
	to.sin_port = htons(BOOTPS);
	to.sin_addr.s_addr = htonl(dst);
	return sendto(s, b.c, n, 0, (struct sockaddr *)&to, sizeof(to));
}

/* wait up to secs on the socket for an ACK or NAK; its type, or 0 */
static int
udprecv(s, secs, l)
int s, secs;
struct lease *l;
{
	union buf b;
	struct sockaddr_in from;
	struct timeval tv;
	fd_set fds;
	long until = time((long *)0) + secs;
	int n, fromlen, type;

	while (!stop) {
		n = until - time((long *)0);
		if (n <= 0)
			break;
		FD_ZERO(&fds);
		FD_SET(s, &fds);
		tv.tv_sec = n;
		tv.tv_usec = 0;
		if (select(s + 1, &fds, (fd_set *)0, (fd_set *)0, &tv) <= 0)
			continue;
		fromlen = sizeof(from);
		n = recvfrom(s, b.c, sizeof(b.c), 0, (struct sockaddr *)&from, &fromlen);
		if (n <= 0)
			continue;
		type = dhcpparse((unsigned char *)b.c, n, l);
		if (type == DHCPACK || type == DHCPNAK)
			return type;
	}
	return 0;
}

/* sleep until a time, or until stopped */
static void
sleepuntil(t)
long t;
{
	struct timeval tv;
	long n;

	while (!stop && (n = t - time((long *)0)) > 0) {
		tv.tv_sec = n < 86400 ? n : 86400;
		tv.tv_usec = 0;
		select(0, (fd_set *)0, (fd_set *)0, (fd_set *)0, &tv);
	}
}

/* --- the lease file and the hook ------------------------------------------ */

static int
leaselines(l, buf, old)
struct lease *l;
char *buf;
unsigned long old;
{
	char *p = buf;
	int i;

	p += sprintf(p, "DHCP_IF=%s\nDHCP_ADDR=%s\nDHCP_MASK=%s\n", ifname,
	    ipstr(l->addr), ipstr(l->mask));
	p += sprintf(p, "DHCP_ROUTER=%s\nDHCP_DNS=", l->router ? ipstr(l->router) : "");
	for (i = 0; i < l->ndns; i++)
		p += sprintf(p, "%s%s", i ? " " : "", ipstr(l->dns[i]));
	p += sprintf(p, "\nDHCP_HOSTNAME=%s\nDHCP_SERVER=%s\n", l->host, ipstr(l->server));
	p += sprintf(p, "DHCP_LEASE=%lu\nDHCP_T1=%lu\nDHCP_T2=%lu\n", l->secs, l->t1, l->t2);
	if (old && old != l->addr)
		p += sprintf(p, "DHCP_OLD_ADDR=%s\n", ipstr(old));
	return p - buf;
}

static void
writelease(l)
struct lease *l;
{
	char buf[1024], tmp[96];
	int fd, n;

	n = leaselines(l, buf, 0L);
	sprintf(tmp, "%s.new", leasefile);
	if ((fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0644)) < 0)
		return;
	write(fd, buf, n);
	close(fd);
	rename(tmp, leasefile);
}

/* the last lease, when its file is there; got is the file's time */
static int
readlease(l)
struct lease *l;
{
	FILE *f;
	char line[300], *v;
	struct stat st;

	memset((char *)l, 0, sizeof(*l));
	if (stat(leasefile, &st) < 0 || (f = fopen(leasefile, "r")) == 0)
		return -1;
	l->got = st.st_mtime;
	while (fgets(line, sizeof(line), f)) {
		if ((v = strchr(line, '=')) == 0)
			continue;
		*v++ = 0;
		if (v[0] && v[strlen(v) - 1] == '\n')
			v[strlen(v) - 1] = 0;
		if (strcmp(line, "DHCP_ADDR") == 0)
			l->addr = ipnum(v);
		else if (strcmp(line, "DHCP_SERVER") == 0)
			l->server = ipnum(v);
		else if (strcmp(line, "DHCP_LEASE") == 0)
			l->secs = strtoul(v, (char **)0, 10);
		else if (strcmp(line, "DHCP_ROUTER") == 0)
			l->router = ipnum(v);
	}
	fclose(f);
	return l->addr ? 0 : -1;
}

static int
hook(why, l, old)
char *why;
struct lease *l;
unsigned long old;
{
	char buf[1024], *env[16], *argv[4], *p;
	int pid, st, n = 0;

	if (l)
		leaselines(l, buf, old);
	else
		sprintf(buf, "DHCP_IF=%s\n", ifname);
	env[n++] = HOOKPATH;
	if (getenv("TZ")) {
		static char tz[80];

		sprintf(tz, "TZ=%.70s", getenv("TZ"));
		env[n++] = tz;
	}
	for (p = buf; *p && n < 14; ) {
		env[n++] = p;
		p = strchr(p, '\n');
		*p++ = 0;
	}
	env[n] = 0;
	argv[0] = getenv("DHCPC_HOOK") ? getenv("DHCPC_HOOK") : HOOK;
	argv[1] = ifname;
	argv[2] = why;
	argv[3] = 0;
	if ((pid = fork()) == 0) {
		if (logfd >= 0) {
			dup2(logfd, 1);
			dup2(logfd, 2);
		}
		execve(argv[0], argv, env);
		_exit(127);
	}
	if (pid < 0)
		return -1;
	while (wait(&st) != pid)
		;
	say("hook %s %s: status %d", why, l ? ipstr(l->addr) : "", (char *)((st >> 8) & 255), 0);
	return (st >> 8) & 255;
}

/* the foreground parent, told once: 'B' bound, 'F' cannot run; a parent
 * that stopped waiting (-b passed) is not there to read it, which is fine */
static void
tell(c)
int c;
{
	char b = c;

	if (tellfd >= 0) {
		write(tellfd, &b, 1);
		close(tellfd);
		tellfd = -1;
	}
}

/* --- the states ---------------------------------------------------------- */

/* backoff 4, 8, 16, 32, 64, 64 ... seconds, with up to a second of jitter */
static int
backoff(try)
int try;
{
	int s = 4 << (try < 4 ? try : 4);

	return s + (rand() & 1);
}

/*
 * INIT-REBOOT (when a last address is known) then INIT, SELECTING and
 * REQUESTING over DLPI until a lease is bound; 0 on success, -1 when the
 * interface cannot do DHCP.
 */
static int
acquire(l, last)
struct lease *l;
unsigned long last;
{
	int fd, try, type;
	struct lease offer;

	if ((fd = dlopen_if()) < 0)
		return -1;
	if (last) {
		for (try = 0; try < 2 && !stop; try++) {
			xid = rand() ^ ((unsigned long)rand() << 16);
			dlsend(fd, DHCPREQUEST, last, 0L);
			type = dlrecv(fd, DHCPACK, backoff(try), l);
			if (type == DHCPACK) {
				say("INIT-REBOOT: %s acknowledged by %s", ipstr(l->addr), ipstr(l->server), 0, 0);
				close(fd);
				return 0;
			}
			if (type == DHCPNAK) {
				say("INIT-REBOOT: %s refused", ipstr(last), 0, 0, 0);
				break;
			}
		}
	}
	for (try = 0; !stop; try = try < 30 ? try + 1 : try) {
		xid = rand() ^ ((unsigned long)rand() << 16);
		dlsend(fd, DHCPDISCOVER, 0L, 0L);
		if (dlrecv(fd, DHCPOFFER, backoff(try), &offer) != DHCPOFFER) {
			if (try == 2)
				say("no DHCP server answers yet; still trying", 0, 0, 0, 0);
			continue;
		}
		dlsend(fd, DHCPREQUEST, offer.addr, offer.server);
		type = dlrecv(fd, DHCPACK, ACK_SECS + 3, l);
		if (type == DHCPACK) {
			if (!l->server)
				l->server = offer.server;
			say("bound %s from %s", ipstr(l->addr), ipstr(l->server), 0, 0);
			close(fd);
			return 0;
		}
		say("REQUEST for %s: %s", ipstr(offer.addr), type == DHCPNAK ? "NAK" : "no answer", 0, 0);
		sleepuntil(time((long *)0) + backoff(try));
	}
	close(fd);
	return -1;
}

/*
 * BOUND, RENEWING, REBINDING on the UDP socket until the lease ends, is
 * refused, or dhcpc is stopped. Returns 0 when the lease ended (or a NAK).
 */
static int
keep(l)
struct lease *l;
{
	int s, type;
	long t1, t2, end, wait;
	struct lease n;

	/* port 68 may be held for a moment (a dhcpc that is ending): retry */
	while ((s = udpopen()) < 0) {
		say("cannot bind UDP port 68 (errno %d); retrying", (char *)errno, 0, 0, 0);
		sleepuntil(time((long *)0) + 10);
		if (stop)
			return -1;
		if (l->secs != INFINITE && time((long *)0) >= l->got + (long)l->secs) {
			hook("EXPIRE", l, 0L);
			unlink(leasefile);
			return 0;
		}
	}
	for (;;) {
		if (l->secs == INFINITE) {
			sleepuntil(0x7fffffffL);
			close(s);
			return -1;
		}
		t1 = l->got + l->t1;
		t2 = l->got + l->t2;
		end = l->got + l->secs;
		sleepuntil(t1);
		type = 0;
		/* RENEWING: unicast to the server, retried at half the time left */
		while (!stop && type == 0 && time((long *)0) < t2) {
			xid = rand() ^ ((unsigned long)rand() << 16);
			udpsend(s, DHCPREQUEST, l->addr, l->server, 0L);
			wait = (t2 - time((long *)0)) / 2;
			type = udprecv(s, wait < 60 ? (int)(t2 - time((long *)0)) : (int)wait, &n);
		}
		if (type == 0 && !stop)
			say("RENEW: no answer from %s; rebinding", ipstr(l->server), 0, 0, 0);
		/* REBINDING: broadcast from the socket (it leaves as the subnet's) */
		while (!stop && type == 0 && time((long *)0) < end) {
			xid = rand() ^ ((unsigned long)rand() << 16);
			udpsend(s, DHCPREQUEST, l->addr, 0xffffffffUL, 0L);
			wait = (end - time((long *)0)) / 2;
			type = udprecv(s, wait < 60 ? (int)(end - time((long *)0)) : (int)wait, &n);
		}
		if (stop) {
			close(s);
			return -1;
		}
		if (type == DHCPACK && n.addr == l->addr) {
			n.got = time((long *)0);
			if (!n.server)
				n.server = l->server;
			say("%s: %s extended for %lu s", time((long *)0) < t2 ? "RENEW" : "REBIND",
			    ipstr(n.addr), (char *)n.secs, 0);
			*l = n;
			writelease(l);
			hook(time((long *)0) < t2 ? "RENEW" : "REBIND", l, 0L);
			continue;
		}
		say("lease %s %s", ipstr(l->addr), type == DHCPNAK ? "refused (NAK)" : "ended", 0, 0);
		close(s);
		hook("EXPIRE", l, 0L);
		unlink(leasefile);
		return 0;
	}
}

static void
daemon_main()
{
	struct lease l, last;
	unsigned long prev = 0;

	signal(SIGTERM, onterm);
	signal(SIGHUP, SIG_IGN);
	signal(SIGINT, SIG_IGN);
	srand((unsigned)(time((long *)0) ^ getpid()));
	if (readlease(&last) == 0 && (last.secs == INFINITE ||
	    last.got + (long)last.secs > time((long *)0)))
		prev = last.addr;
	while (!stop) {
		if (acquire(&l, prev) < 0) {
			tell('F');
			break;
		}
		l.got = time((long *)0);
		srand((unsigned)(l.got ^ getpid() ^ get32(mac + 2)));
		writelease(&l);
		hook("BOUND", &l, prev);
		tell('B');
		prev = l.addr;
		if (keep(&l) < 0)
			break;
		prev = 0;
	}
	unlink(pidfile);
	say("stopped", 0, 0, 0, 0);
	exit(0);
}

/* --- the commands ----------------------------------------------------------- */

static int
heldby()
{
	FILE *f;
	int pid = 0;

	if ((f = fopen(pidfile, "r")) == 0)
		return 0;
	if (fscanf(f, "%d", &pid) != 1)
		pid = 0;
	fclose(f);
	if (pid > 0 && kill(pid, 0) == 0)
		return pid;
	return 0;
}

static int
query()
{
	FILE *f;
	char line[300];
	struct lease l;
	int held = heldby();

	if ((f = fopen(leasefile, "r")) == 0) {
		printf("DHCP_IF=%s\n", ifname);
		return 1;
	}
	while (fgets(line, sizeof(line), f))
		fputs(line, stdout);
	fclose(f);
	if (readlease(&l) < 0 || !held)
		return 1;
	return l.secs == INFINITE || l.got + (long)l.secs > time((long *)0) ? 0 : 1;
}

static int
release()
{
	struct lease l;
	int pid, s, i;

	if ((pid = heldby()) != 0) {
		kill(pid, SIGTERM);
		for (i = 0; i < 20 && kill(pid, 0) == 0; i++)
			sleepuntil(time((long *)0) + 1);
	}
	if (readlease(&l) < 0) {
		say("release: no lease held", 0, 0, 0, 0);
		unlink(pidfile);
		return pid ? 0 : 1;
	}
	if (findnode() == 0 && (s = udpopen()) >= 0) {
		int fd = dlopen_if();	/* only for the MAC */

		if (fd >= 0)
			close(fd);
		srand((unsigned)(time((long *)0) ^ getpid()));
		xid = rand() ^ ((unsigned long)rand() << 16);
		udpsend(s, DHCPRELEASE, l.addr, l.server, l.server);
		close(s);
		say("released %s to %s", ipstr(l.addr), ipstr(l.server), 0, 0);
	}
	hook("RELEASE", &l, 0L);
	unlink(leasefile);
	unlink(pidfile);
	return 0;
}

static void
usage()
{
	fprintf(stderr, "usage: dhcpc [-b secs] interface | -x interface | -q interface\n");
	exit(1);
}

int
main(argc, argv)
int argc;
char **argv;
{
	int c, bound = -1, mode = 0, p[2], pid, fd;
	char b;
	FILE *f;

	while ((c = getopt(argc, argv, "b:xq")) != -1) {
		switch (c) {
		case 'b':
			bound = atoi(optarg);
			if (bound < 1)
				usage();
			break;
		case 'x':
		case 'q':
			mode = c;
			break;
		default:
			usage();
		}
	}
	if (optind != argc - 1 || strlen(argv[optind]) > 16)
		usage();
	ifname = argv[optind];
	sprintf(leasefile, "%s/%s.lease", STATEDIR, ifname);
	sprintf(pidfile, "%s/%s.pid", STATEDIR, ifname);
	if (mode == 'q')
		exit(query());
	logfd = open(LOGFILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (mode == 'x')
		exit(release());

	if (heldby()) {
		fprintf(stderr, "dhcpc: %s: a dhcpc already holds it\n", ifname);
		exit(1);
	}
	if (findnode() < 0) {
		fprintf(stderr, "dhcpc: %s: no driver for it in %s\n", ifname, LINKD);
		exit(1);
	}
	mkdir("/var/inet", 0755);
	mkdir(STATEDIR, 0755);
	if (pipe(p) < 0)
		exit(1);
	if ((pid = fork()) < 0)
		exit(1);
	if (pid == 0) {
		close(p[0]);
		tellfd = p[1];
		setpgrp();
		if ((fd = open("/dev/null", O_RDWR)) >= 0) {
			dup2(fd, 0);
			dup2(fd, 1);
			dup2(fd, 2);
			if (fd > 2)
				close(fd);
		}
		if ((f = fopen(pidfile, "w")) != 0) {
			fprintf(f, "%d\n", getpid());
			fclose(f);
		}
		say("started on %s", node, 0, 0, 0);
		daemon_main();
	}
	close(p[1]);
	/* the parent: wait for the first lease, at most -b seconds */
	if (bound > 0)
		arm(bound);
	c = read(p[0], &b, 1);
	alarm(0);
	if (c == 1 && b == 'B')
		exit(0);
	if (c == 1 && b == 'F')
		exit(1);
	if (c == 0) {
		/* the daemon ended without a word */
		exit(1);
	}
	exit(2);			/* the bound passed; the daemon keeps trying */
}
