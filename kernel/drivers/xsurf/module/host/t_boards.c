/*
 * t_boards.c -- host tests of xs_boards.c: where each card's operations
 * reach in its window, the plug-and-play key, and how boards are found,
 * refused and mapped (the k30 form: the identity in Zorro II space,
 * sptalloc above VSECT1).  The core's chip routines are stubbed here; the
 * window is plain memory.
 */
#include <stdarg.h>
#include "hostk.h"
#include "xsurf.h"

static int	n_checks, n_fail;
static char	*cur;
#define CHECK(c) do { n_checks++; if (!(c)) { n_fail++; \
	printf("FAIL %s: %s (line %d)\n", cur, #c, __LINE__); } } while (0)

xs_board_t	xs_board[XS_MAXBOARDS];
int		xs_nboards;
long		lbolt;
char		*panicstr;
unsigned char	*host_window;
unsigned long	host_window_phys;
static char	console[4096];
static int	ipl, reset_fail_n, reset_calls;
static int	regs_fail = -1, prom_fail, bprobe_fail, stop_calls;
static unsigned char *z3_window;
static int	spt_pages, spt_flag;
static unsigned long spt_pfn;
static caddr_t	spt_freed;

/* the stubs */
void
cmn_err(int level, char *fmt, ...)
{
    va_list ap;
    char line[256];

    va_start(ap, fmt);
    vsnprintf(line, sizeof line, fmt, ap);
    va_end(ap);
    strncat(console, line, sizeof console - strlen(console) - 2);
    strcat(console, "\n");
}
int spl6() { int s = ipl; ipl = 4; return s; }
int splx(int s) { int o = ipl; ipl = s; return o; }
void xs_udelay(long us) { }
int bprobe(caddr_t a, int v) { return bprobe_fail; }
int xs_regs_check(xs_board_t *b) { return regs_fail; }
void xs_chip_stop(xs_board_t *b) { stop_calls++; }
int
xs_chip_reset(xs_board_t *b)
{
    return ++reset_calls > reset_fail_n;	/* the first reset_fail_n fail */
}
int
xs_read_prom(xs_board_t *b, unsigned char *mac)
{
    memset(mac, 0x22, 6);
    mac[0] = 0;
    return !prom_fail;
}
void xs_chip_init(xs_board_t *b, int start) { }
caddr_t
sptalloc(int npages, int mode, unsigned long pfn, int flag)
{
    spt_pages = npages;
    spt_pfn = pfn;
    return (caddr_t)z3_window;
}
void
sptfree(caddr_t va, int npages, int flag)
{
    spt_freed = va;
    spt_pages = npages;
    spt_flag = flag;
}

/* the AutoConfig table the finder reads */
struct ac { unsigned long id; long addr, size; };
static struct ac *actab;

int
autocon(unsigned long id, int index, long *addr, long *size)
{
    struct ac *a;
    int n = 0;

    for (a = actab; a && a->id; a++)
	if (a->id == id && n++ == index) {
	    *addr = a->addr;
	    *size = a->size;
	    return 1;
	}
    return 0;
}

static unsigned char *
win(unsigned long off)
{
    return host_window + off;
}

static void
t_xs100_access()
{
    xs_board_t b;
    unsigned char buf[0x200], pat[0x80];
    int i, ok;

    cur = "xs100-registers-and-fifo";
    static struct ac t[] = { { 0x12120064, 0xE90000, 0x10000 }, { 0 } };
    actab = t;
    reset_calls = reset_fail_n = 0;
    memset(host_window, 0, 0x10000);
    CHECK(xs_find_boards() == 1);
    b = xs_board[0];
    CHECK(b.st.board_kind == XSURF_KIND_XSURF100 && b.st.zorro == 2);
    CHECK(b.va == win(0) && b.map_how == XS_MAP_IDENT);

    (*b.ops->wr)(&b, XS_ISR, 0x5a);
    CHECK(*win(0x800 + 4 * 7) == 0x5a);
    *win(0x800 + 4 * XS_CURR) = 0x66;
    CHECK((*b.ops->rd)(&b, XS_CURR) == 0x66);

    for (i = 0; i < 0x80; i++)
	pat[i] = *win(0x8880 + i) = i ^ 0xa5;
    *win(0x840) = 0xaa;
    *win(0x841) = 0xbb;
    (*b.ops->bin)(&b, buf, 0x100 + 3);
    for (ok = 1, i = 0; i < 0x100; i++)
	ok &= buf[i] == pat[i & 0x7f];		/* each block from 0x8880 again */
    CHECK(ok);
    CHECK(buf[0x100] == 0xaa && buf[0x101] == 0xbb);	/* a word from the data port */
    CHECK(buf[0x102] == 0xaa);			/* then a byte */

    for (i = 0; i < 0x86; i++)
	buf[i] = i;
    memset(win(0x8c00), 0, 0x400);
    (*b.ops->bout)(&b, buf, 0x86);
    CHECK(win(0x8c80)[0] == 0x80 && win(0x8c80)[3] == 0x83);	/* the second block */
    CHECK(win(0x8c80)[4] == 4 && win(0x8c80)[0x7f] == 0x7f);	/* the first's rest */
    CHECK(*win(0x8c7f) == 0 && *win(0x8d00) == 0);		/* nothing outside */
    CHECK(win(0x840)[0] == 0x84 && win(0x840)[1] == 0x85);	/* the tail word */

    *win(0x40) = 0x80;
    CHECK((*b.ops->irq)(&b) == 1);
    *win(0x40) = 0x7f;
    CHECK((*b.ops->irq)(&b) == 0);

    cur = "xs100-link-from-dsr";
    *win(0x800 + 4 * 0x17) = 0x17;		/* ready, link, 100, full */
    (*b.ops->link)(&b);
    CHECK(b.st.link == XSURF_LINK_UP && b.st.link_speed == 100);
    CHECK(b.st.link_duplex == XSURF_DUPLEX_FULL && b.st.link_medium == XSURF_MEDIUM_TP);
    CHECK(b.st.link_raw == 0x17);
    CHECK(*win(0x800 + 4 * 0x17) == 0x17);	/* read only: 0x17 is never written */
    *win(0x800 + 4 * 0x17) = 0x11;		/* ready, link, 10, half */
    (*b.ops->link)(&b);
    CHECK(b.st.link == XSURF_LINK_UP && b.st.link_speed == 10);
    CHECK(b.st.link_duplex == XSURF_DUPLEX_HALF);
    *win(0x800 + 4 * 0x17) = 0x13;		/* ready, link, 10, full */
    (*b.ops->link)(&b);
    CHECK(b.st.link_speed == 10 && b.st.link_duplex == XSURF_DUPLEX_FULL);
    *win(0x800 + 4 * 0x17) = 0x15;		/* ready, link, 100, half */
    (*b.ops->link)(&b);
    CHECK(b.st.link_speed == 100 && b.st.link_duplex == XSURF_DUPLEX_HALF);
    *win(0x800 + 4 * 0x17) = 0x16;		/* ready, no link (speed, duplex stale) */
    (*b.ops->link)(&b);
    CHECK(b.st.link == XSURF_LINK_DOWN && b.st.link_speed == 0);
    CHECK(b.st.link_duplex == XSURF_DUPLEX_UNKNOWN && b.st.link_medium == XSURF_MEDIUM_TP);
    *win(0x800 + 4 * 0x17) = 0x07;		/* not ready: the rest means nothing */
    (*b.ops->link)(&b);
    CHECK(b.st.link == XSURF_LINK_UNKNOWN && b.st.link_medium == XSURF_MEDIUM_NOTREADY);
    CHECK(b.st.link_speed == 0 && b.st.link_duplex == XSURF_DUPLEX_UNKNOWN);
}

/* the X-Surf's link from its RTL8019AS registers, in the window's memory */
static void
rtl(xs_board_t *b, int id0, int c0, int c2, int c3, int running)
{
    *win(0x8600 + 2 * 0x0a) = id0;
    *win(0x8600 + 2 * 0x0b) = 0x70;
    *win(0x8600 + 2 * 3) = c0;
    *win(0x8600 + 2 * 5) = c2;
    *win(0x8600 + 2 * 6) = c3;
    *win(0x8600) = 0;
    b->running = running;
    (*b->ops->link)(b);
}

static void
t_xsurf_access()
{
    xs_board_t b;
    unsigned char buf[8];
    int i, ok;

    cur = "xsurf-isa-window";
    static struct ac t[] = { { 0x12120017, 0xE90000, 0x10000 }, { 0 } };
    actab = t;
    reset_calls = reset_fail_n = 0;
    memset(host_window, 0, 0x10000);
    console[0] = 0;
    CHECK(xs_find_boards() == 1);
    b = xs_board[0];
    CHECK(b.st.board_kind == XSURF_KIND_XSURF && b.st.pnp == 0);
    CHECK(strstr(console, "plug-and-play") == NULL);
    (*b.ops->wr)(&b, XS_ISR, 0x5a);
    CHECK(*win(0x8600 + 2 * 7) == 0x5a);		/* ISA 0x307 */
    win(0x8620)[0] = 1;
    win(0x8620)[1] = 2;
    (*b.ops->bin)(&b, buf, 5);
    CHECK(buf[0] == 1 && buf[1] == 2 && buf[2] == 1 && buf[3] == 2 && buf[4] == 1);
    buf[0] = 9;
    buf[1] = 8;
    (*b.ops->bout)(&b, buf, 2);
    CHECK(win(0x8620)[0] == 9 && win(0x8620)[1] == 8);
    *win(0x40) = 0xa0;
    CHECK((*b.ops->irq)(&b) == 1);

    cur = "xsurf-link-from-config";
    rtl(&b, 0x50, 0x00, 0x00, 0x00, 1);		/* auto-detect, on 10BASE-T */
    CHECK(b.st.link == XSURF_LINK_UP && b.st.link_speed == 10);
    CHECK(b.st.link_duplex == XSURF_DUPLEX_HALF && b.st.link_medium == XSURF_MEDIUM_TP);
    CHECK(*win(0x8600) == (XS_CR_NODMA | XS_CR_STA));	/* page 0 again, still running */
    CHECK(b.st.link_raw == 0x0000);
    rtl(&b, 0x50, 0x00, 0x00, XS_CONFIG3_FUDUP, 0);
    CHECK(b.st.link == XSURF_LINK_UP && b.st.link_duplex == XSURF_DUPLEX_FULL);
    CHECK(*win(0x8600) == (XS_CR_NODMA | XS_CR_STP));	/* stopped stays stopped */
    rtl(&b, 0x50, XS_CONFIG0_BNC, 0x00, 0, 1);	/* link test failed: coax */
    CHECK(b.st.link == XSURF_LINK_DOWN && b.st.link_medium == XSURF_MEDIUM_COAX);
    CHECK(b.st.link_raw == (XS_CONFIG0_BNC << 8));
    rtl(&b, 0x50, XS_CONFIG0_AUI, 0x00, 0, 1);	/* link test failed: AUI */
    CHECK(b.st.link == XSURF_LINK_DOWN && b.st.link_medium == XSURF_MEDIUM_AUI);
    rtl(&b, 0x50, 0x00, 0x40, 0, 1);		/* 10BASE-T, link test off */
    CHECK(b.st.link == XSURF_LINK_UNKNOWN && b.st.link_medium == XSURF_MEDIUM_TP_NOTEST);
    CHECK(b.st.link_raw == 0x40);
    rtl(&b, 0x50, XS_CONFIG0_AUI, 0x80, 0, 1);	/* set to 10BASE5 */
    CHECK(b.st.link == XSURF_LINK_UNKNOWN && b.st.link_medium == XSURF_MEDIUM_AUI);
    rtl(&b, 0x50, XS_CONFIG0_BNC, 0xc0, 0, 1);	/* set to 10BASE2 */
    CHECK(b.st.link == XSURF_LINK_UNKNOWN && b.st.link_medium == XSURF_MEDIUM_COAX);
    rtl(&b, 0x51, 0x00, 0x00, 0, 1);		/* not an RTL8019 */
    CHECK(b.st.link == XSURF_LINK_UNKNOWN && b.st.link_medium == XSURF_MEDIUM_NOTKNOWN);
    CHECK(b.st.link_raw == 0);
    *win(0x8600 + 2 * 0x0b) = 0x71;
    *win(0x8600 + 2 * 0x0a) = 0x50;
    (*b.ops->link)(&b);
    CHECK(b.st.link_medium == XSURF_MEDIUM_NOTKNOWN);

    cur = "xsurf-plug-and-play";
    memset(host_window, 0, 0x10000);
    console[0] = 0;
    reset_calls = 0;
    reset_fail_n = 1;				/* nothing at 0x300 until set up */
    CHECK(xs_find_boards() == 1);
    CHECK(reset_calls == 2 && xs_board[0].st.pnp == 1);
    CHECK(strstr(console, "set up through ISA plug-and-play") != NULL);
    cur = "xsurf-plug-and-play-fails";
    console[0] = 0;
    reset_calls = 0;
    reset_fail_n = 2;				/* nothing answers either time */
    CHECK(xs_find_boards() == 0);
    CHECK(strstr(console, "does not reset") != NULL);
    for (ok = 1, i = 0xB000; i < 0xC000; i++)
	ok &= *win(i) == 0;
    for (i = 0xD000; i < 0xE000; i++)
	ok &= *win(i) == 0;
    CHECK(ok);					/* the IDE ports untouched */
    CHECK(*win(0x7e) == 0);			/* A11 left low */
    CHECK(*win(0x8000 + 2 * 0x279) == 0x02);	/* last: wait for the key */
}

static void
t_pnp_key()
{
    static unsigned char key[32] = {
	0x6A, 0xB5, 0xDA, 0xED, 0xF6, 0xFB, 0x7D, 0xBE,
	0xDF, 0x6F, 0x37, 0x1B, 0x0D, 0x86, 0xC3, 0x61,
	0xB0, 0x58, 0x2C, 0x16, 0x8B, 0x45, 0xA2, 0xD1,
	0xE8, 0x74, 0x3A, 0x9D, 0xCE, 0xE7, 0x73, 0x39,
    };
    extern int xs_pnp_key();
    int i, ok;

    cur = "pnp-initiation-key";
    for (ok = 1, i = 0; i < 32; i++)
	ok &= xs_pnp_key(i) == key[i];
    CHECK(ok);
}

static void
t_find()
{
    static struct ac t[] = {
	{ 0x12120017, 0xE90000, 0x10000 },		/* X-Surf */
	{ 0x12120064, 0x40000000, 0x4000000 },		/* X-Surf-100, Zorro III */
	{ 0x12120064, (long)0x80000000UL, 0x4000000 },	/* shut up */
	{ 0x12120064, 0x00200000, 0x1000 },		/* too small */
	{ 0 },
    };

    cur = "find-order-refusals-mapping";
    actab = t;
    reset_calls = reset_fail_n = 0;
    console[0] = 0;
    CHECK(xs_find_boards() == 2);
    CHECK(xs_board[0].st.board_kind == XSURF_KIND_XSURF100);	/* -100 first */
    CHECK(xs_board[0].st.zorro == 3 && xs_board[0].map_how == XS_MAP_SPT);
    CHECK(xs_board[0].va == z3_window);
    CHECK(spt_pages == 0x9000 / NBPP && spt_pfn == (0x40000000UL >> 11));
    CHECK(xs_board[1].st.board_kind == XSURF_KIND_XSURF && xs_board[1].unit == 1);
    CHECK(xs_board[1].st.zorro == 2 && xs_board[1].map_how == XS_MAP_IDENT);
    CHECK(strstr(console, "has shut itself up") != NULL);
    CHECK(strstr(console, "too small") != NULL);
    CHECK(xs_nfound == 4);			/* every board AutoConfig gave, in order */
    CHECK(xs_found[0].board == 0 && xs_found[3].board == 1);
    CHECK(xs_found[1].board == -1 && xs_found[1].rec.refused == XSURF_REFUSED_HIGH);
    CHECK(xs_found[1].rec.board_phys == 0x80000000UL && xs_found[1].rec.zorro == 3);
    CHECK(xs_found[2].board == -1 && xs_found[2].rec.refused == XSURF_REFUSED_SMALL);
    CHECK(xs_found[2].rec.refused_detail == 0x1000 && xs_found[2].rec.unit == 0xffffffff);
    CHECK(xs_found[2].rec.board_kind == XSURF_KIND_XSURF100);
    CHECK(xs_found[2].rec.version == XSURF_STATUS_VERSION);
    CHECK(xs_board[0].st.unit == 0 && xs_board[1].st.unit == 1);
    xs_unmap(&xs_board[0]);
    CHECK(spt_freed == (caddr_t)z3_window && spt_pages == 18 && spt_flag == 1);
    CHECK(xs_board[0].va == 0 && xs_board[0].map_how == XS_MAP_NONE);
    spt_freed = 0;
    xs_unmap(&xs_board[1]);
    CHECK(spt_freed == 0);			/* the identity is not freed */

    cur = "find-none";
    actab = NULL;
    CHECK(xs_find_boards() == 0);
    CHECK(xs_nfound == 0);
}

/* a board whose probe refuses it: recorded, unmapped, its chip stopped */
static void
t_refuse()
{
    static struct ac t[] = {
	{ 0x12120064, 0x40000000, 0x4000000 },		/* X-Surf-100, Zorro III */
	{ 0x12120017, 0xE90000, 0x10000 },		/* X-Surf */
	{ 0 },
    };

    actab = t;
    cur = "refuse-registers-dead";
    reset_calls = reset_fail_n = 0;
    console[0] = 0;
    regs_fail = 0x99;
    stop_calls = 0;
    spt_freed = 0;
    CHECK(xs_find_boards() == 0);
    CHECK(xs_nfound == 2);
    CHECK(xs_found[0].board == -1 && xs_found[0].rec.refused == XSURF_REFUSED_NOWRITES);
    CHECK(xs_found[0].rec.refused_detail == 0x99);
    CHECK(xs_found[0].rec.board_phys == 0x40000000 && xs_found[0].rec.zorro == 3);
    CHECK(xs_found[1].rec.refused == XSURF_REFUSED_NOWRITES);
    CHECK(xs_found[1].rec.board_kind == XSURF_KIND_XSURF);
    CHECK(strstr(console, "X-Surf-100 at 0x40000000: its registers do not take writes") != NULL);
    CHECK(strstr(console, "read 0x99") != NULL);
    CHECK(stop_calls == 2);			/* both masked before they were unmapped */
    CHECK(spt_freed == (caddr_t)z3_window);	/* the Zorro III window unmapped */
    CHECK(xs_board[0].present == 0 && xs_board[0].map_how == XS_MAP_NONE);
    regs_fail = -1;

    cur = "refuse-no-address";
    console[0] = 0;
    prom_fail = 1;
    stop_calls = 0;
    CHECK(xs_find_boards() == 0);
    CHECK(xs_nfound == 2 && xs_found[0].rec.refused == XSURF_REFUSED_NOMAC);
    CHECK(strstr(console, "no usable station address") != NULL && stop_calls == 2);
    prom_fail = 0;

    cur = "refuse-no-answer";
    console[0] = 0;
    bprobe_fail = 1;
    stop_calls = 0;
    CHECK(xs_find_boards() == 0);
    CHECK(xs_nfound == 2 && xs_found[0].rec.refused == XSURF_REFUSED_NOANSWER);
    CHECK(stop_calls == 0);			/* a bus error: its registers untouched */
    bprobe_fail = 0;

    cur = "refuse-no-reset";
    console[0] = 0;
    reset_calls = 0;
    reset_fail_n = 100;
    stop_calls = 0;
    CHECK(xs_find_boards() == 0);
    CHECK(xs_found[0].rec.refused == XSURF_REFUSED_NORESET);
    CHECK(xs_found[1].rec.refused == XSURF_REFUSED_NORESET && stop_calls == 2);
    reset_fail_n = 0;

    cur = "refuse-one-of-two";
    reset_calls = 0;
    regs_fail = -1;
    CHECK(xs_find_boards() == 2 && xs_nfound == 2);
    CHECK(xs_found[0].board == 0 && xs_found[1].board == 1);
}

int
main()
{
    host_window_phys = 0xE90000;
    host_window = calloc(1, 0x10000);
    z3_window = calloc(1, 0x10000);
    t_xs100_access();
    t_xsurf_access();
    t_pnp_key();
    t_find();
    t_refuse();
    printf("t_boards: %d checks, %d failed\n", n_checks, n_fail);
    return n_fail != 0;
}
