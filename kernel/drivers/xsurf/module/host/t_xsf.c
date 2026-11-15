/*
 * t_xsf.c -- host tests of userland/xsf.c: xsf built with its open, ioctl
 * and close replaced by a model of /dev/xsfN and /dev/xsfctl that answers
 * with records the test sets, and its output checked line by line.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include "stropts.h"
#include "xsurfuser.h"

extern int	xsf_main(int, char **);

static int	n_checks, n_fail;
static char	*cur;
#define CHECK(c) do { n_checks++; if (!(c)) { n_fail++; \
	printf("FAIL %s: %s (line %d)\n", cur, #c, __LINE__); } } while (0)

/* the model: board 0's record (or ENXIO), the found list (or ctl's errno) */
static int		board_errno, ctl_errno;
static xsurf_status_t	board, fnd[XSURF_MAXFOUND];
static int		nfnd, rec_size;
static char		out[16384];

#define FD_BOARD	10
#define FD_CTL		11

int
f_open(const char *path, int flags, ...)
{
    if (strcmp(path, "/dev/xsf0") == 0) {
	if (board_errno) { errno = board_errno; return -1; }
	return FD_BOARD;
    }
    if (strcmp(path, "/dev/xsfctl") == 0) {
	if (ctl_errno) { errno = ctl_errno; return -1; }
	return FD_CTL;
    }
    errno = ENOENT;
    return -1;
}

int
f_ioctl(int fd, int req, ...)
{
    va_list ap;
    struct strioctl *si;
    int i, size = rec_size ? rec_size : (int)sizeof(xsurf_status_t);

    va_start(ap, req);
    si = va_arg(ap, struct strioctl *);
    va_end(ap);
    if (req != I_STR) { errno = EINVAL; return -1; }
    if (fd == FD_BOARD && si->ic_cmd == XSURF_GET_STATUS) {
	memcpy(si->ic_dp, &board, size);
	return 0;
    }
    i = si->ic_cmd - XSURF_FOUND_STATUS(0);
    if (fd == FD_CTL && i >= 0 && i < nfnd) {
	memcpy(si->ic_dp, &fnd[i], sizeof(xsurf_status_t));
	return 0;
    }
    errno = EINVAL;
    return -1;
}

int
f_close(int fd)
{
    return 0;
}

/* xsf with these arguments, its standard output and error into out */
static int
run(char *a1, char *a2)
{
    char *argv[4];
    int argc = 1, rc, saved1, saved2;
    FILE *f = tmpfile();
    long n;

    argv[0] = "xsf";
    if (a1) argv[argc++] = a1;
    if (a2) argv[argc++] = a2;
    argv[argc] = 0;
    fflush(stdout);
    fflush(stderr);
    saved1 = dup(1);
    saved2 = dup(2);
    dup2(fileno(f), 1);
    dup2(fileno(f), 2);
    rc = xsf_main(argc, argv);
    fflush(stdout);
    fflush(stderr);
    dup2(saved1, 1);
    dup2(saved2, 2);
    close(saved1);
    close(saved2);
    rewind(f);
    n = fread(out, 1, sizeof out - 1, f);
    out[n < 0 ? 0 : n] = 0;
    fclose(f);
    return rc;
}

static void
inuse(xsurf_status_t *st)
{
    static unsigned char mac[6] = { 0x00, 0x80, 0x10, 0x12, 0x34, 0x56 };

    memset(st, 0, sizeof *st);
    st->version = XSURF_STATUS_VERSION;
    st->size = sizeof *st;
    st->board_kind = XSURF_KIND_XSURF100;
    st->zorro = 3;
    st->board_phys = 0x40000000;
    st->intr_mode = XSURF_MODE_INTR;
    st->intr_param = 2;
    st->running = 1;
    memcpy(st->mac, mac, 6);
    st->link = XSURF_LINK_UP;
    st->link_speed = 100;
    st->link_duplex = XSURF_DUPLEX_FULL;
    st->link_medium = XSURF_MEDIUM_TP;
}

static void
reset()
{
    board_errno = ctl_errno = 0;
    rec_size = 0;
    inuse(&board);
    memset(fnd, 0, sizeof fnd);
    fnd[0] = board;
    nfnd = 1;
}

int
main()
{
    int rc;

    cur = "in-use-healthy";
    reset();
    board.if_opackets = board.tx_frames = 7;
    rc = run(NULL, NULL);
    CHECK(rc == 0);
    CHECK(strstr(out, "xsf0: X-Surf-100, Zorro 3 at 0x40000000, 00:80:10:12:34:56, interrupt I/O, link up 100 full\n") == out);
    CHECK(strstr(out, "  received 0 frames, 0 errors; sent 7 frames, 0 errors, 0 collisions\n") != NULL);
    CHECK(strstr(out, "no link") == NULL && strstr(out, "refused at load") == NULL);
    CHECK(strstr(out, "\ntx_frames 7\n") != NULL && strstr(out, "\nlink 1\n") != NULL);
    CHECK(strstr(out, "\nlink_speed 100\n") != NULL && strstr(out, "\nif_collisions 0\n") != NULL);
    CHECK(strstr(out, "\nmac 00:80:10:12:34:56\n") != NULL);
    CHECK(strstr(out, "\nunit 0\n") != NULL);

    cur = "no-link-tx-timeouts";
    reset();
    board.link = XSURF_LINK_DOWN;
    board.link_speed = 0;
    board.link_duplex = XSURF_DUPLEX_UNKNOWN;
    board.intr_mode = XSURF_MODE_POLLED;
    board.selftest_failed = 1;
    board.tx_timeouts = 5;
    board.if_oerrors = 5;
    board.notes = XSURF_NOTE_TXTIMEOUT;
    run(NULL, NULL);
    CHECK(strstr(out, ", polled (interrupt self-test failed), no link\n") != NULL);
    CHECK(strstr(out, "  no link: see the cable, the hub or switch port and their link lights\n") != NULL);
    CHECK(strstr(out, "  no transmit has completed: the chip takes frames but never reports them sent\n") != NULL);
    CHECK(strstr(out, "  transmits: 5 not completed (chip restarted), 0 remote-DMA writes not completed,\n") != NULL);
    CHECK(strstr(out, "  said on the console: transmit not completed;\n") != NULL);

    cur = "dma-dead";
    reset();
    board.tx_dma_timeouts = 9;
    run(NULL, NULL);
    CHECK(strstr(out, "  no frame reached the chip: its remote-DMA writes do not complete\n") != NULL);
    CHECK(strstr(out, "no transmit has completed") == NULL);

    cur = "aborts-on-coax";
    reset();
    board.board_kind = XSURF_KIND_XSURF;
    board.zorro = 2;
    board.link = XSURF_LINK_DOWN;
    board.link_medium = XSURF_MEDIUM_COAX;
    board.tx_aborts = board.tx_errors = 4;
    board.if_collisions = 64;
    run(NULL, NULL);
    CHECK(strstr(out, "xsf0: X-Surf, Zorro 2 at 0x40000000, 00:80:10:12:34:56, interrupt I/O, no link (10BASE-T link test failed; sending on coax)\n") != NULL);
    CHECK(strstr(out, "    4 aborted (16 collisions or FIFO underrun), 0 other errors\n") != NULL);
    CHECK(strstr(out, "  every transmit aborted on collisions") != NULL);
    CHECK(strstr(out, " 64 collisions\n") != NULL);

    cur = "interrupts-stopped";
    reset();
    board.intr_mode = XSURF_MODE_POLLED;
    board.irq_fallbacks = 1;
    run(NULL, NULL);
    CHECK(strstr(out, ", polled, link up 100 full\n") != NULL);
    CHECK(strstr(out, "  interrupts stopped after load; polled since\n") != NULL);

    cur = "in-use-and-one-refused";
    reset();
    memset(&fnd[1], 0, sizeof fnd[1]);
    fnd[1].version = 2;
    fnd[1].size = sizeof fnd[1];
    fnd[1].board_kind = XSURF_KIND_XSURF;
    fnd[1].zorro = 2;
    fnd[1].board_phys = 0xe90000;
    fnd[1].unit = 0xffffffff;
    fnd[1].refused = XSURF_REFUSED_NOWRITES;
    fnd[1].refused_detail = 0x99;
    nfnd = 2;
    rc = run(NULL, NULL);
    CHECK(rc == 0);
    CHECK(strstr(out, "board 1: X-Surf, Zorro 2 at 0xe90000: refused at load: its registers do not take writes (wrote 0x55 or 0xaa, read 0x99)\n") != NULL);

    cur = "every-board-refused";
    board_errno = ENXIO;
    fnd[0] = fnd[1];
    fnd[0].board_kind = XSURF_KIND_XSURF100;
    fnd[0].refused = XSURF_REFUSED_NOMAC;
    nfnd = 1;
    rc = run(NULL, NULL);
    CHECK(rc == 1);
    CHECK(strstr(out, "xsf0: no such board in use\n") == out);
    CHECK(strstr(out, "board 0: X-Surf-100, Zorro 2 at 0xe90000: refused at load: no usable station address\n") != NULL);

    cur = "driver-not-loaded";
    ctl_errno = ENXIO;
    rc = run(NULL, NULL);
    CHECK(rc == 1);
    CHECK(strstr(out, "xsf: the xsurf driver is not loaded: AutoConfig found no X-Surf or X-Surf-100") != NULL);
    ctl_errno = ENOENT;
    run(NULL, NULL);
    CHECK(strstr(out, "xsf: no /dev/xsfctl: the xsurf package is older than 1.0.0-4 or not installed") != NULL);

    cur = "all";
    reset();
    fnd[1] = fnd[0];
    fnd[1].refused = XSURF_REFUSED_HIGH;
    nfnd = 2;
    rc = run("-a", NULL);
    CHECK(rc == 0 && strstr(out, "xsf0: X-Surf-100") == out);
    CHECK(strstr(out, "board 1: X-Surf-100, Zorro 3 at 0x40000000: refused at load: placed at or above 0x80000000") != NULL);

    cur = "silent";
    reset();
    CHECK(run("-S", NULL) == 0 && out[0] == 0);
    board_errno = ENXIO;
    CHECK(run("-S", NULL) == 1 && out[0] == 0);

    cur = "usage";
    reset();
    CHECK(run("-x", NULL) == 2 && strstr(out, "usage:") != NULL);

    cur = "version-1-record";
    reset();
    board.version = 1;
    board.size = 39 * sizeof(unsigned int);
    rec_size = board.size;
    board.tx_frames = 3;
    run(NULL, NULL);
    CHECK(strstr(out, "xsf: the driver's record is version 1: no words, only counters\n") == out);
    CHECK(strstr(out, "\ntx_frames 3\n") != NULL && strstr(out, "\nif_oerrors 0\n") != NULL);
    CHECK(strstr(out, "unit") == NULL && strstr(out, "mac ") == NULL);

    printf("t_xsf: %d checks, %d failed\n", n_checks, n_fail);
    return n_fail != 0;
}
