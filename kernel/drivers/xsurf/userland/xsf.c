/*
 * xsf -- what the xsurf driver knows about its boards (xsf(1M)).
 *
 *   xsf [unit]     board <unit>'s state (unit 0 by default): first what the
 *                  console said at load, the link and what has gone wrong
 *                  in words, then every counter of its status record, one
 *                  "name value" per line; then any board refused at load
 *   xsf -a         every board the driver found, in use or refused
 *   xsf -S [unit]  silent: exit 0 when xsf<unit> is in use, 1 when not
 *
 * /dev/xsf<unit> answers for a board in use; /dev/xsfctl for every board
 * found, also one the driver refused at load, whose console line is gone
 * once the system is up.  A record newer than this program prints the
 * fields it knows; an older one (driver 1.0.0-3 and before) only those it has.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <stropts.h>
#include <sys/types.h>
#include "xsurfuser.h"
#define XS_WORDS_REFUSED
#include "xsurfwords.h"

#define CTL	"/dev/xsfctl"

static const char *names[] = {
    "version", "size", "board_kind", "zorro", "board_phys", "intr_mode",
    "link", "running", "pnp",
    "rx_frames", "rx_delivered", "rx_no_sap", "rx_not_for_us",
    "rx_couldnt_put", "rx_nomem", "rx_errors", "rx_bad_size", "rx_resyncs",
    "rx_overruns", "rx_frame_errors", "rx_crc_errors", "rx_missed",
    "tx_frames", "tx_errors", "tx_aborts", "tx_collisions", "tx_timeouts",
    "tx_dma_timeouts", "tx_bad_req", "tx_unbound", "tx_resends",
    "irq_claims", "irq_fallbacks", "resets", "ack_retries",
    "if_ipackets", "if_opackets", "if_ierrors", "if_oerrors",
    /* version 2 (mac is printed apart: it is bytes) */
    "unit", "refused", "refused_detail", "intr_param", "selftest_failed",
    0, 0,
    "link_speed", "link_duplex", "link_medium", "link_raw", "link_changes",
    "notes", "if_collisions",
    0
};

static int
status(int fd, int cmd, xsurf_status_t *st)
{
    struct strioctl si;

    memset((char *)st, 0, sizeof *st);
    si.ic_cmd = cmd;
    si.ic_timout = 10;
    si.ic_len = sizeof *st;
    si.ic_dp = (char *)st;
    return ioctl(fd, I_STR, &si);
}

static const char *
card(unsigned int kind)
{
    return kind == XSURF_KIND_XSURF100 ? "X-Surf-100" :
	   kind == XSURF_KIND_XSURF ? "X-Surf" : "an unknown card";
}

/* the record's own field count, at most what this program knows */
static int
fields(xsurf_status_t *st)
{
    int n = st->size / sizeof(unsigned int);

    if (n > (int)(sizeof *st / sizeof(unsigned int)))
	n = sizeof *st / sizeof(unsigned int);
    return n;
}

/* a refused board: what it is and why, as its console line said */
static void
refused(int i, xsurf_status_t *st)
{
    printf("board %d: %s, Zorro %u at 0x%x: refused at load: %s", i,
	   card(st->board_kind), st->zorro, st->board_phys,
	   xs_words_refused(st->refused));
    if (st->refused == XSURF_REFUSED_NOWRITES)
	printf(" (wrote 0x55 or 0xaa, read 0x%x)", st->refused_detail);
    printf("\n");
}

/* a board in use: the load line, the state in words, then the counters */
static void
inuse(xsurf_status_t *st)
{
    unsigned int *v = (unsigned int *)st;
    char words[64];
    int i, n = fields(st);
    unsigned int notes;

    if (st->version < 2) {
	printf("xsf: the driver's record is version %u: no words, only counters\n",
	       st->version);
    } else {
	printf("xsf%u: %s, Zorro %u at 0x%x, %02x:%02x:%02x:%02x:%02x:%02x, %s, %s\n",
	       st->unit, card(st->board_kind), st->zorro, st->board_phys,
	       st->mac[0], st->mac[1], st->mac[2], st->mac[3], st->mac[4], st->mac[5],
	       st->intr_mode == XSURF_MODE_INTR ? "interrupt I/O" :
	       st->selftest_failed ? "polled (interrupt self-test failed)" : "polled",
	       xs_words_link(st->link, st->link_speed, st->link_duplex,
			     st->link_medium, words));
	if (st->intr_mode != XSURF_MODE_INTR && st->irq_fallbacks)
	    printf("  interrupts stopped after load; polled since\n");
	printf("  received %u frames, %u errors; sent %u frames, %u errors, %u collisions\n",
	       st->if_ipackets, st->if_ierrors, st->if_opackets, st->if_oerrors,
	       st->if_collisions);
	printf("  transmits: %u not completed (chip restarted), %u remote-DMA writes not completed,\n",
	       st->tx_timeouts, st->tx_dma_timeouts);
	printf("    %u aborted (16 collisions or FIFO underrun), %u other errors\n",
	       st->tx_aborts, st->tx_errors - st->tx_aborts);
	if (st->link == XSURF_LINK_DOWN)
	    printf("  no link: see the cable, the hub or switch port and their link lights\n");
	if (st->tx_frames == 0 && st->tx_dma_timeouts > 0)
	    printf("  no frame reached the chip: its remote-DMA writes do not complete\n");
	else if (st->tx_frames == 0 && st->tx_timeouts > 0)
	    printf("  no transmit has completed: the chip takes frames but never reports them sent\n");
	else if (st->tx_frames == 0 && st->tx_aborts > 0)
	    printf("  every transmit aborted on collisions: the medium (coax, or no link)\n");
	notes = st->notes;
	if (notes)
	    printf("  said on the console:%s%s%s%s\n",
		   notes & XSURF_NOTE_TXTIMEOUT ? " transmit not completed;" : "",
		   notes & XSURF_NOTE_DMA ? " remote-DMA write not completed;" : "",
		   notes & XSURF_NOTE_ABORT ? " transmit aborted;" : "",
		   notes & XSURF_NOTE_TXERR ? " transmit error;" : "");
    }
    for (i = 0; i < n && i < (int)(sizeof names / sizeof names[0]); i++)
	if (names[i])			/* the mac's two words are printed below */
	    printf("%s %u\n", names[i], v[i]);
    if (st->version >= 2)
	printf("mac %02x:%02x:%02x:%02x:%02x:%02x\n",
	       st->mac[0], st->mac[1], st->mac[2], st->mac[3], st->mac[4], st->mac[5]);
}

/* every board found through /dev/xsfctl; refused_only skips those in use */
static int
found(int refused_only, int *ctl_errno)
{
    xsurf_status_t st;
    int fd, i, shown = 0;

    if ((fd = open(CTL, O_RDONLY)) < 0) {
	*ctl_errno = errno;
	return -1;
    }
    for (i = 0; i < XSURF_MAXFOUND; i++) {
	if (status(fd, XSURF_FOUND_STATUS(i), &st) < 0)
	    break;
	if (st.refused != XSURF_REFUSED_NONE) {
	    refused(i, &st);
	    shown++;
	} else if (!refused_only) {
	    inuse(&st);
	    shown++;
	}
    }
    close(fd);
    return shown;
}

static void
not_loaded(int e)
{
    if (e == ENOENT)
	fprintf(stderr, "xsf: no %s: the xsurf package is older than 1.0.0-4 or not installed\n", CTL);
    else
	fprintf(stderr, "xsf: the xsurf driver is not loaded: AutoConfig found no "
		"X-Surf or X-Surf-100 (%s: %s)\n", CTL, strerror(e));
}

int
main(int argc, char **argv)
{
    char dev[32];
    int fd, silent = 0, all = 0, unit = 0, e = 0, n;
    xsurf_status_t st;

    if (argc > 1 && strcmp(argv[1], "-S") == 0) {
	silent = 1;
	argc--;
	argv++;
    } else if (argc > 1 && strcmp(argv[1], "-a") == 0) {
	all = 1;
	argc--;
	argv++;
    }
    if (argc > 2 || (argc > 1 && (argv[1][0] < '0' || argv[1][0] > '9'))) {
	fprintf(stderr, "usage: xsf [unit] | xsf -a | xsf -S [unit]\n");
	return 2;
    }
    if (argc > 1)
	unit = atoi(argv[1]);
    if (all) {
	if ((n = found(0, &e)) < 0) {
	    not_loaded(e);
	    return 1;
	}
	if (n == 0)
	    printf("xsf: the driver found no board\n");
	return 0;
    }
    sprintf(dev, "/dev/xsf%d", unit);
    if ((fd = open(dev, O_RDWR)) < 0) {
	if (silent)
	    return 1;
	e = errno;
	if (e != ENXIO) {
	    fprintf(stderr, "xsf: %s: %s\n", dev, strerror(e));
	    return 1;
	}
	printf("xsf%d: no such board in use\n", unit);
	if (found(1, &e) < 0)
	    not_loaded(e);
	return 1;
    }
    if (silent)
	return 0;
    if (status(fd, XSURF_GET_STATUS, &st) < 0) {
	fprintf(stderr, "xsf: %s: status: %s\n", dev, strerror(errno));
	return 1;
    }
    close(fd);
    inuse(&st);
    (void)found(1, &e);
    return 0;
}
