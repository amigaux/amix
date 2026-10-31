/*
 * dlpi-mac -- print the station address of a DLPI Ethernet interface.
 *
 *   dlpi-mac [-p ppa] [-s sap] [-t secs] <device>     e.g. /dev/aen0
 *
 * Prints one line, six two-digit lower-case hex octets joined by ':'
 * (00:80:10:ff:ff:ff), and exits 0. Exit 1: usage, or the device cannot be
 * opened (ENXIO or ENODEV: no such card in this machine). Exit 2: the DLPI
 * exchange failed or timed out. Nothing but the address is ever printed on
 * stdout, so a shell can take the output as it is.
 *
 * An SVR4.0 Ethernet driver gives its address out in one place a program can
 * reach: the DL_BIND_ACK, or the DL_INFO_ACK of a stream already bound. So,
 * by the rules every driver is held to (P-36 section 4.4):
 *
 *   1. open; DL_INFO_REQ under an alarm;
 *   2. DL_ATTACH_REQ (PPA -p, default 0) only if the provider is Style 2;
 *   3. if the stream is already bound with an address (a driver may hand out
 *      a slot an earlier user left bound, as the stock A2065 does), the
 *      address is taken from the DL_INFO_ACK; otherwise DL_BIND_REQ on an
 *      unused SAP (-s, default 0x88B5, an experimental ethertype) and the
 *      address from the DL_BIND_ACK;
 *   4. DL_UNBIND_REQ, so the slot is left unbound for whoever opens it next;
 *      close.
 *
 * Every wait is bounded (-t, default 5 s), so a boot script never hangs on
 * it; DL_UNITDATA_IND arriving meanwhile is thrown away. No frame is sent.
 *
 * Built with gcc-cross-amix (m68k-cbm-sysv4, the period compiler) against
 * the stock headers and libc: build.sh.
 *
 * MIT licence, see LICENSE at the top of the repository.
 */
#include <sys/types.h>
#include <sys/stropts.h>
#include <sys/dlpi.h>
#include <stdio.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

/* the stock headers declare none of these */
extern int errno;
extern int alarm(), close(), getopt(), getmsg(), putmsg();
extern long strtol();
extern char *optarg;
extern int optind;

#define DEFSAP		0x88B5
#define DEFSECS		5

static char *dev;
static int secs = DEFSECS;
static volatile int timedout;
static int acklen;		/* bytes in the last ack getack returned */

union buf {
	long	align;
	char	c[1024];
};

static void
onalarm(sig)
int sig;
{
	timedout = 1;
}

static void
die(why)
char *why;
{
	fprintf(stderr, "dlpi-mac: %s: %s\n", dev, why);
	exit(2);
}

static void
usage()
{
	fprintf(stderr, "usage: dlpi-mac [-p ppa] [-s sap] [-t secs] device\n");
	exit(1);
}

static void
sendctl(fd, p, n, what)
int fd;
char *p;
int n;
char *what;
{
	struct strbuf ctl;

	ctl.maxlen = 0;
	ctl.len = n;
	ctl.buf = p;
	if (putmsg(fd, &ctl, (struct strbuf *)0, 0) < 0)
		die(what);
}

/*
 * The next control message other than DL_UNITDATA_IND; its primitive, or -1
 * when none came within the bound. Its length is left in acklen.
 */
static long
getack(fd, u)
int fd;
union buf *u;
{
	struct strbuf ctl, dat;
	union buf d;
	int flags;

	timedout = 0;
	signal(SIGALRM, onalarm);
	alarm(secs);
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
		if (ctl.len < (int)sizeof(long))
			continue;
		if (*(long *)u->c == DL_UNITDATA_IND)
			continue;
		alarm(0);
		acklen = ctl.len;
		return *(long *)u->c;
	}
}

/* the address at off/len in an ack of n bytes, or 0 */
static unsigned char *
addr(u, n, off, len)
union buf *u;
int n;
unsigned long off, len;
{
	if (off == 0 || len < 6 || off + 6 > (unsigned long)n)
		return 0;
	return (unsigned char *)u->c + off;
}

int
main(argc, argv)
int argc;
char **argv;
{
	int fd, c, i, n;
	long ppa = 0, sap = DEFSAP, prim;
	union buf u;
	dl_info_req_t ireq;
	dl_info_ack_t *ia;
	dl_attach_req_t areq;
	dl_bind_req_t breq;
	dl_bind_ack_t *ba;
	dl_unbind_req_t ureq;
	unsigned char *a, mac[6];

	while ((c = getopt(argc, argv, "p:s:t:")) != -1) {
		switch (c) {
		case 'p':
			ppa = strtol(optarg, (char **)0, 0);
			break;
		case 's':
			sap = strtol(optarg, (char **)0, 0);
			break;
		case 't':
			secs = (int)strtol(optarg, (char **)0, 0);
			if (secs < 1)
				usage();
			break;
		default:
			usage();
		}
	}
	if (optind != argc - 1)
		usage();
	dev = argv[optind];

	if ((fd = open(dev, O_RDWR)) < 0) {
		fprintf(stderr, "dlpi-mac: %s: %s\n", dev,
		    errno == ENXIO || errno == ENODEV ? "no such interface here"
		    : "cannot open");
		exit(1);
	}

	ireq.dl_primitive = DL_INFO_REQ;
	sendctl(fd, (char *)&ireq, sizeof(ireq), "putmsg DL_INFO_REQ failed");
	if (getack(fd, &u) != DL_INFO_ACK)
		die("no DL_INFO_ACK");
	ia = (dl_info_ack_t *)u.c;
	if (ia->dl_provider_style == DL_STYLE2) {
		areq.dl_primitive = DL_ATTACH_REQ;
		areq.dl_ppa = ppa;
		sendctl(fd, (char *)&areq, sizeof(areq),
		    "putmsg DL_ATTACH_REQ failed");
		if (getack(fd, &u) != DL_OK_ACK)
			die("DL_ATTACH_REQ not acknowledged");
		sendctl(fd, (char *)&ireq, sizeof(ireq),
		    "putmsg DL_INFO_REQ failed");
		if (getack(fd, &u) != DL_INFO_ACK)
			die("no DL_INFO_ACK after the attach");
		ia = (dl_info_ack_t *)u.c;
	}

	a = 0;
	if (ia->dl_current_state == DL_IDLE)
		a = addr(&u, acklen, ia->dl_addr_offset,
		    ia->dl_addr_length);
	if (a == 0) {
		memset((char *)&breq, 0, sizeof(breq));
		breq.dl_primitive = DL_BIND_REQ;
		breq.dl_sap = sap;
		breq.dl_service_mode = DL_CLDLS;
		sendctl(fd, (char *)&breq, sizeof(breq),
		    "putmsg DL_BIND_REQ failed");
		prim = getack(fd, &u);
		if (prim != DL_BIND_ACK)
			die(prim == DL_ERROR_ACK ? "DL_BIND_REQ refused"
			    : "no DL_BIND_ACK");
		ba = (dl_bind_ack_t *)u.c;
		a = addr(&u, acklen, ba->dl_addr_offset,
		    ba->dl_addr_length);
		if (a == 0)
			die("DL_BIND_ACK carries no address");
	}
	for (i = 0; i < 6; i++)
		mac[i] = a[i];

	/* best effort: an unbind that is not answered changes nothing above */
	ureq.dl_primitive = DL_UNBIND_REQ;
	sendctl(fd, (char *)&ureq, sizeof(ureq), "putmsg DL_UNBIND_REQ failed");
	(void)getack(fd, &u);
	close(fd);

	n = printf("%02x:%02x:%02x:%02x:%02x:%02x\n",
	    mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
	exit(n == 18 ? 0 : 2);
}
