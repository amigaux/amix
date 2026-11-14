/*
 * xsf -- the xsurf driver's status record, one counter per line
 * (build on the box: cc -o xsf xsf.c, with xsurfuser.h beside it).
 *
 *   xsf [unit]     print /dev/xsf<unit>'s status record (unit 0 by default)
 *   xsf -S [unit]  silent presence check: exit 0 when the board is there,
 *                  1 when its open fails (no such board)
 *
 * The record starts with its version and size; a record newer than this
 * program prints the fields it knows.
 */
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <stropts.h>
#include <sys/types.h>
#include "xsurfuser.h"

extern int errno;

static char *names[] = {
    "version", "size", "board_kind", "zorro", "board_phys", "intr_mode",
    "link", "running", "pnp",
    "rx_frames", "rx_delivered", "rx_no_sap", "rx_not_for_us",
    "rx_couldnt_put", "rx_nomem", "rx_errors", "rx_bad_size", "rx_resyncs",
    "rx_overruns", "rx_frame_errors", "rx_crc_errors", "rx_missed",
    "tx_frames", "tx_errors", "tx_aborts", "tx_collisions", "tx_timeouts",
    "tx_dma_timeouts", "tx_bad_req", "tx_unbound", "tx_resends",
    "irq_claims", "irq_fallbacks", "resets", "ack_retries",
    "if_ipackets", "if_opackets", "if_ierrors", "if_oerrors",
    0
};

main(argc, argv)
int argc;
char **argv;
{
    char dev[32];
    int fd, silent = 0, unit = 0, i, n;
    xsurf_status_t st;
    unsigned int *v = (unsigned int *)&st;
    struct strioctl si;

    if (argc > 1 && strcmp(argv[1], "-S") == 0) {
	silent = 1;
	argc--;
	argv++;
    }
    if (argc > 1)
	unit = atoi(argv[1]);
    sprintf(dev, "/dev/xsf%d", unit);
    if ((fd = open(dev, O_RDWR)) < 0) {
	if (!silent)
	    fprintf(stderr, "xsf: %s: %s\n", dev,
		    errno == ENXIO ? "no such board" : strerror(errno));
	exit(1);
    }
    if (silent)
	exit(0);
    memset((char *)&st, 0, sizeof st);
    si.ic_cmd = XSURF_GET_STATUS;
    si.ic_timout = 10;
    si.ic_len = sizeof st;
    si.ic_dp = (char *)&st;
    if (ioctl(fd, I_STR, &si) < 0) {
	fprintf(stderr, "xsf: %s: status: %s\n", dev, strerror(errno));
	exit(1);
    }
    n = st.size / sizeof(unsigned int);
    if (n > sizeof st / sizeof(unsigned int))
	n = sizeof st / sizeof(unsigned int);
    for (i = 0; i < n && names[i]; i++)
	printf("%s %u\n", names[i], v[i]);
    close(fd);
    exit(0);
}
