/*
 * zenmac -- print the Z3660 ethernet (zen0) station MAC, as the driver sees it.
 *
 *   zenmac [device]      default device /dev/zen0
 *
 * Prints one line, six two-digit lower-case hex octets joined by ':'
 * (e.g. 00:80:51:01:02:04), and exits 0.  Exit 1: the device cannot be opened
 * (ENXIO = no Z3660 ethernet on this machine).  Exit 2: the DLPI exchange
 * failed or timed out.  Nothing else is printed on stdout in any case, so a
 * shell can take `zenmac` output verbatim.
 *
 * WHY A PROGRAM.  The z3660eth driver (../amix-z3660net/src/z3660eth.c) holds
 * the MAC it read from the firmware's ZZ_ETH_MAC_HI/LO registers in
 * info->paddress and hands it out in exactly one user-reachable place: the
 * address part of a DLPI DL_BIND_ACK (and of DL_INFO_ACK once bound).  The
 * SVR4.0 `ifconfig` prints no link address, `arp -a` reads the kernel through
 * nlist (broken on this relocated kernel), and the driver's kmem globals
 * z3660eth_machi/z3660eth_maclo are bare tentative definitions (SHN_COMMON in
 * /stand/unix, so nlist cannot place them).  The Z3660ETH_GET_CONFIG ioctl is
 * declared but not implemented.  So: open, DL_BIND_REQ, read the ack, close.
 *
 * Safe to run before or after `slink`: every open of the node gets its own
 * stream slot (the driver's clone-style minor rewrite), the bind uses an
 * otherwise-unused experimental SAP (0x88B5), no frame is ever sent, and the
 * close releases the slot.  An alarm bounds the wait, so a boot script can never
 * hang on it.  Built with the m68k-cbm-sysv4 cross toolchain
 * (tools/build-zenmac.sh); installed as /usr/amiga/bin/zenmac.
 */
#include <sys/types.h>
#include <sys/stropts.h>
#include <sys/dlpi.h>
#include <stdio.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>

#define DEFDEV		"/dev/zen0"
#define PROBE_SAP	0x88B5
#define TIMEOUT		5

extern int errno;

static void
ontimeout(sig)
int sig;
{
	exit(2);
}

main(argc, argv)
int argc;
char **argv;
{
	char *dev = (argc > 1) ? argv[1] : DEFDEV;
	int fd, flags, i;
	struct strbuf ctl;
	dl_bind_req_t req;
	union {
		long		align;
		dl_bind_ack_t	ack;
		char		buf[256];
	} u;
	unsigned char *a;

	if ((fd = open(dev, O_RDWR)) < 0) {
		fprintf(stderr, "zenmac: %s: %s\n", dev,
			errno == ENXIO ? "no Z3660 ethernet present"
				       : "cannot open");
		exit(1);
	}

	signal(SIGALRM, ontimeout);
	alarm(TIMEOUT);

	memset((char *)&req, 0, sizeof(req));
	req.dl_primitive = DL_BIND_REQ;
	req.dl_sap = PROBE_SAP;
	req.dl_max_conind = 0;
	req.dl_service_mode = DL_CLDLS;
	req.dl_conn_mgmt = 0;
	ctl.maxlen = 0;
	ctl.len = sizeof(req);
	ctl.buf = (char *)&req;
	if (putmsg(fd, &ctl, (struct strbuf *)0, 0) < 0) {
		fprintf(stderr, "zenmac: %s: putmsg DL_BIND_REQ failed\n", dev);
		exit(2);
	}

	ctl.maxlen = sizeof(u.buf);
	ctl.len = 0;
	ctl.buf = u.buf;
	flags = 0;
	if (getmsg(fd, &ctl, (struct strbuf *)0, &flags) < 0) {
		fprintf(stderr, "zenmac: %s: getmsg failed\n", dev);
		exit(2);
	}
	alarm(0);

	if (ctl.len < (int)sizeof(dl_bind_ack_t) ||
	    u.ack.dl_primitive != DL_BIND_ACK ||
	    u.ack.dl_addr_length < 6 ||
	    u.ack.dl_addr_offset + 6 > (unsigned long)ctl.len) {
		fprintf(stderr, "zenmac: %s: no DL_BIND_ACK with an address\n", dev);
		exit(2);
	}

	a = (unsigned char *)u.buf + u.ack.dl_addr_offset;
	for (i = 0; i < 6; i++)
		printf("%s%02x", i ? ":" : "", a[i]);
	printf("\n");
	close(fd);
	exit(0);
}
