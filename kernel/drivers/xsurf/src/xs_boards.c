/*
 * xs_boards.c -- finding, mapping and setting up the boards, and each
 * card's access to its chip (the back ends).
 *
 * MAPPING.  A board window is reached as each kernel line maps it:
 *   k46  dev_kvmap(phys, bytes, 0x40, 1): non-cacheable serialised, the
 *        kit's class for registers, below VSECT1 as above it;
 *   k30  the identity below VSECT1 (Zorro II space), else sptalloc().  The
 *        k30 kernel runs with the 68030 data cache disabled in supervisor
 *        mode, so neither mapping is data-cached; sptalloc() itself makes
 *        no cache-inhibited page.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "xsk.h"
#include "xsurf.h"

/*
 * A card the driver knows: its AutoConfig id, its operations, how many
 * bytes of its window the driver uses, and its probe (reset, register
 * check, station address, chip set up and stopped; XSURF_REFUSED_NONE, or
 * why the board is not usable).
 */
struct xs_card
{
    unsigned long	id;		/* manufacturer << 16 | product */
    struct xs_ops	*ops;
    unsigned long	bytes;
    int			(*probe)();	/* (b) */
};

static int
xs_map(b, phys, bytes)
xs_board_t *b;
unsigned long phys, bytes;
{
#ifdef XS_K46
    b->va = (volatile unsigned char *)dev_kvmap(phys, bytes, 0x40, 1);
    if (b->va == 0)
	return ENOMEM;
    b->map_how = XS_MAP_KV;
#else
    if (phys + bytes <= VSECT1) {
	b->va = (volatile unsigned char *)phystokv(phys);
	b->map_how = XS_MAP_IDENT;
    } else {
	b->va = (volatile unsigned char *)sptalloc((int)((bytes + NBPP - 1) / NBPP),
						   PG_V, phystopfn(phys), 0);
	if (b->va == 0)
	    return ENOMEM;
	b->map_how = XS_MAP_SPT;
    }
#endif
    b->phys = phys;
    b->map_bytes = bytes;
    return 0;
}

void
xs_unmap(b)
xs_board_t *b;
{
#ifdef XS_K46
    if (b->map_how == XS_MAP_KV)
	dev_kvunmap((char *)b->va, b->map_bytes);
#else
    if (b->map_how == XS_MAP_SPT)
	sptfree((caddr_t)b->va, (int)((b->map_bytes + NBPP - 1) / NBPP), 1);
#endif
    b->map_how = XS_MAP_NONE;
    b->va = 0;
}

xs_found_t	xs_found[XSURF_MAXFOUND];
int		xs_nfound;

/*
 * What both cards' probes end with: reset, the register check, station
 * address, the chip set up and left stopped.  A refusal has a console
 * line naming what failed; the reason and its detail go to the caller.
 */
static int
xs_probe_chip(b, detail)
xs_board_t *b;
int *detail;
{
    int got;

    if (!xs_chip_reset(b)) {
	cmn_err(CE_NOTE, "xsurf: %s at 0x%x: the chip does not reset",
	    b->ops->name, (int)b->phys);
	return XSURF_REFUSED_NORESET;
    }
    if ((got = xs_regs_check(b)) >= 0) {
	*detail = got;
	cmn_err(CE_NOTE,
	    "xsurf: %s at 0x%x: its registers do not take writes (wrote 0x55 or 0xaa, read 0x%x)",
	    b->ops->name, (int)b->phys, got);
	return XSURF_REFUSED_NOWRITES;
    }
    if (!xs_read_prom(b, b->mac)) {
	cmn_err(CE_NOTE, "xsurf: %s at 0x%x: no usable station address",
	    b->ops->name, (int)b->phys);
	return XSURF_REFUSED_NOMAC;
    }
    xs_chip_init(b, 0);
    return XSURF_REFUSED_NONE;
}

static int	xs100_probe(), xsurf_probe();
static struct xs_ops xs100_ops, xsurf_ops;

static struct xs_card xs_cards[] = {
    { 0x12120064, &xs100_ops, 0x9000, xs100_probe },	/* X-Surf-100 */
    { 0x12120017, &xsurf_ops, 0x9000, xsurf_probe },	/* X-Surf */
    { 0 },
};

/* ------------------------------------------------------------------------
 * X-Surf-100 (AX88796B), Zorro II or Zorro III.  docs/facts.md:
 *   +0x0040  network interrupt status, bit 7 of a byte read
 *   +0x0800  chip register r at 0x800 + 4r, byte access (as Linux; the
 *            maker's page says word access: one place to change, here)
 *   +0x0840  the data port (register 0x10), word or byte
 *   +0x8880  long-word FIFO read window, +0x8C80 the write window: each
 *            long is two 16-bit chip transfers in byte order.  Used in
 *            blocks of 0x80 bytes from those addresses, inside the maker's
 *            windows and where the emulator decodes them.
 * The PHY is on from reset and left to the chip (no MII access); its link,
 * speed and duplex come from the Device Status Register (0x17, read).
 * The driver never writes 0x17: on the AX88796B a write sets the
 * back-pressure jam limit (datasheet V1.6 sec. 5.1.67), not a GPOC.
 * --------------------------------------------------------------------- */
#define XS100_IRQ	0x0040
#define XS100_REGS	0x0800
#define XS100_FIFO_RD	0x8880
#define XS100_FIFO_WR	0x8C80
#define XS100_BLOCK	0x80
#define XS100_REG(b, r)	((b)->va + XS100_REGS + 4 * (r))

static int
xs100_rd(b, r)
xs_board_t *b;
int r;
{
    return *XS100_REG(b, r);
}

static void
xs100_wr(b, r, v)
xs_board_t *b;
int r, v;
{
    *XS100_REG(b, r) = v;
}

/* `len' bytes from the data port: whole longs through the FIFO window, a
 * block at a time, then a word and a byte from the data port itself */
static void
xs100_bin(b, buf, len)
xs_board_t *b;
unsigned char *buf;
int len;
{
    volatile unsigned int *fifo;	/* 32 bits */
    int n;

    while (len >= 4) {
	n = len & ~3;
	if (n > XS100_BLOCK)
	    n = XS100_BLOCK;
	len -= n;
	fifo = (volatile unsigned int *)(b->va + XS100_FIFO_RD);
	for (; n > 0; n -= 4, buf += 4)
	    *(unsigned int *)buf = *fifo++;
    }
    if (len & 2) {
	*(unsigned short *)buf = *(volatile unsigned short *)XS100_REG(b, XS_DATA);
	buf += 2;
    }
    if (len & 1)
	*buf = *XS100_REG(b, XS_DATA);
}

/* an even `len' to the data port, the same way */
static void
xs100_bout(b, buf, len)
xs_board_t *b;
unsigned char *buf;
int len;
{
    volatile unsigned int *fifo;	/* 32 bits */
    int n;

    while (len >= 4) {
	n = len & ~3;
	if (n > XS100_BLOCK)
	    n = XS100_BLOCK;
	len -= n;
	fifo = (volatile unsigned int *)(b->va + XS100_FIFO_WR);
	for (; n > 0; n -= 4, buf += 4)
	    *fifo++ = *(unsigned int *)buf;
    }
    if (len & 2)
	*(volatile unsigned short *)XS100_REG(b, XS_DATA) = *(unsigned short *)buf;
}

static int
xs100_irq(b)
xs_board_t *b;
{
    return (b->va[XS100_IRQ] & 0x80) != 0;
}

/*
 * The link from the DSR.  D_RDY clear (the chip in reset, asleep or
 * loading its EEPROM) makes the other bits meaningless: link unknown.
 */
static void
xs100_link(b)
xs_board_t *b;
{
    int dsr = xs100_rd(b, XS_DSR);
    xsurf_status_t *st = &b->st;

    st->link_raw = dsr;
    if (!(dsr & XS_DSR_RDY)) {
	st->link = XSURF_LINK_UNKNOWN;
	st->link_speed = 0;
	st->link_duplex = XSURF_DUPLEX_UNKNOWN;
	st->link_medium = XSURF_MEDIUM_NOTREADY;
	return;
    }
    st->link_medium = XSURF_MEDIUM_TP;
    if (dsr & XS_DSR_LINK) {
	st->link = XSURF_LINK_UP;
	st->link_speed = (dsr & XS_DSR_SPEED) ? 100 : 10;
	st->link_duplex = (dsr & XS_DSR_DUPLEX) ? XSURF_DUPLEX_FULL : XSURF_DUPLEX_HALF;
    } else {
	st->link = XSURF_LINK_DOWN;
	st->link_speed = 0;
	st->link_duplex = XSURF_DUPLEX_UNKNOWN;
    }
}

static struct xs_ops xs100_ops = {
    "X-Surf-100", XSURF_KIND_XSURF100, 0x40,
    xs100_rd, xs100_wr, xs100_bin, xs100_bout, xs100_irq, xs100_link,
};

static int
xs100_probe(b, detail)
xs_board_t *b;
int *detail;
{
    if (bprobe((caddr_t)XS100_REG(b, XS_CR), -1)) {
	cmn_err(CE_NOTE, "xsurf: X-Surf-100 at 0x%x: no answer at its registers",
	    (int)b->phys);
	return XSURF_REFUSED_NOANSWER;
    }
    return xs_probe_chip(b, detail);
}

/* ------------------------------------------------------------------------
 * X-Surf (Realtek, an RTL8019AS in the emulator), Zorro II.  docs/facts.md:
 *   +0x0040  ethernet interrupt status, bits 7 and 5 (always equal)
 *   +0x007E  write 0x80: ISA A11 high (adds 0x800 to ISA ports), 0x00: low.
 *            Never read here: a read can change A11, and bit 7 of it is
 *            the IDE interrupt.
 *   +0x8000  ISA I/O space, addresses doubled: port p at 0x8000 + 2p.  The
 *            chip at ISA 0x300: register r at 0x8600 + 2r, the data port
 *            (0x310) at 0x8620.
 * The IDE ports (+0xB000, +0xD000), the clock ports and the expansion port
 * are never touched.  Register writes are byte writes, as Linux does (the
 * maker's page says word-wide: one place to change, here).
 *
 * Whether the chip comes up at ISA 0x300 by itself (Linux assumes it) or
 * waits for ISA plug-and-play (the emulator does) is not known, so the
 * probe looks at 0x300 first and configures the chip through
 * plug-and-play only when nothing answers there.
 * --------------------------------------------------------------------- */
#define XSURF_IRQ	0x0040
#define XSURF_A11	0x007E
#define XSURF_ISA	0x8000
#define XSURF_IO	0x300			/* the chip's ISA I/O base */
#define XSURF_PORT(b, p) ((b)->va + XSURF_ISA + 2 * (p))
#define XSURF_REG(b, r)	XSURF_PORT((b), XSURF_IO + (r))

/* ISA plug-and-play ports (the ISA Plug and Play specification 1.0a) */
#define PNP_ADDRESS	0x279			/* write, A11 low */
#define PNP_WRITE_DATA	0x279			/* 0xA79: written with A11 high */
#define PNP_READ_PORT	0x20B			/* the read port we assign */

static int
xsurf_rd(b, r)
xs_board_t *b;
int r;
{
    return *XSURF_REG(b, r);
}

static void
xsurf_wr(b, r, v)
xs_board_t *b;
int r, v;
{
    *XSURF_REG(b, r) = v;
}

/* the data port is 16 bits wide and gives the bytes in memory order */
static void
xsurf_bin(b, buf, len)
xs_board_t *b;
unsigned char *buf;
int len;
{
    volatile unsigned short *dp =
	(volatile unsigned short *)XSURF_REG(b, XS_DATA);

    for (; len >= 2; len -= 2, buf += 2)
	*(unsigned short *)buf = *dp;
    if (len)
	*buf = *XSURF_REG(b, XS_DATA);
}

static void
xsurf_bout(b, buf, len)
xs_board_t *b;
unsigned char *buf;
int len;
{
    volatile unsigned short *dp =
	(volatile unsigned short *)XSURF_REG(b, XS_DATA);

    for (; len >= 2; len -= 2, buf += 2)
	*dp = *(unsigned short *)buf;
}

static int
xsurf_irq(b)
xs_board_t *b;
{
    return (b->va[XSURF_IRQ] & 0x80) != 0;
}

/*
 * The link as the RTL8019AS shows it (datasheet LS003.8, CONFIG0 and
 * CONFIG2): it has no link bit, but in auto-detect (CONFIG2 PL 00) it
 * sends on coax, or on AUI, when the 10BASE-T link test fails, and says
 * so in CONFIG0.  With the medium set any other way the link is not known.
 * A chip whose ID bytes are not the RTL8019's is not decoded.
 */
static void
xsurf_link(b)
xs_board_t *b;
{
    xsurf_status_t *st = &b->st;
    int c0, c2, c3, run = b->running ? XS_CR_STA : XS_CR_STP;

    st->link = XSURF_LINK_UNKNOWN;
    st->link_speed = 0;
    st->link_duplex = XSURF_DUPLEX_UNKNOWN;
    if (xsurf_rd(b, XS_RTL_ID0) != 0x50 || xsurf_rd(b, XS_RTL_ID1) != 0x70) {
	st->link_raw = 0;
	st->link_medium = XSURF_MEDIUM_NOTKNOWN;
	return;
    }
    xsurf_wr(b, XS_CR, XS_CR_NODMA | XS_CR_PAGE3 | run);
    c0 = xsurf_rd(b, XS_RTL_CONFIG0);
    c2 = xsurf_rd(b, XS_RTL_CONFIG2);
    c3 = xsurf_rd(b, XS_RTL_CONFIG3);
    xsurf_wr(b, XS_CR, XS_CR_NODMA | run);
    st->link_raw = (c0 << 8) | c2;
    switch (XS_CONFIG2_PL(c2)) {
    case 0:
	if (c0 & XS_CONFIG0_AUI) {
	    st->link = XSURF_LINK_DOWN;
	    st->link_medium = XSURF_MEDIUM_AUI;
	} else if (c0 & XS_CONFIG0_BNC) {
	    st->link = XSURF_LINK_DOWN;
	    st->link_medium = XSURF_MEDIUM_COAX;
	} else {
	    st->link = XSURF_LINK_UP;
	    st->link_medium = XSURF_MEDIUM_TP;
	    st->link_speed = 10;
	    st->link_duplex = (c3 & XS_CONFIG3_FUDUP) ? XSURF_DUPLEX_FULL : XSURF_DUPLEX_HALF;
	}
	break;
    case 1:
	st->link_medium = XSURF_MEDIUM_TP_NOTEST;
	break;
    case 2:
	st->link_medium = XSURF_MEDIUM_AUI;
	break;
    default:
	st->link_medium = XSURF_MEDIUM_COAX;
	break;
    }
}

static struct xs_ops xsurf_ops = {
    "X-Surf", XSURF_KIND_XSURF, 0x00,
    xsurf_rd, xsurf_wr, xsurf_bin, xsurf_bout, xsurf_irq, xsurf_link,
};

static void
pnp_address(b, v)
xs_board_t *b;
int v;
{
    *XSURF_PORT(b, PNP_ADDRESS) = v;
}

static void
pnp_write(b, reg, v)
xs_board_t *b;
int reg, v;
{
    pnp_address(b, reg);
    b->va[XSURF_A11] = 0x80;
    *XSURF_PORT(b, PNP_WRITE_DATA) = v;
    b->va[XSURF_A11] = 0x00;
}

static int
pnp_read(b)
xs_board_t *b;
{
    return *XSURF_PORT(b, PNP_READ_PORT);
}

/*
 * The initiation key: 32 bytes from a linear-feedback shift register that
 * starts at 0x6A, as the specification defines it.  Exported for the host
 * tests, which check it against the published sequence.
 */
int
xs_pnp_key(i)
int i;
{
    int k = 0x6a;

    while (i-- > 0)
	k = (k >> 1) | (((k ^ (k >> 1)) & 1) << 7);
    return k & 0xff;
}

/*
 * Configure the one card behind the bridge: key, card numbers cleared,
 * isolation (one card wins it alone), card number 1, logical device 0 at
 * ISA 0x300, activated, back to waiting for the key.  Interrupts from this
 * board cannot come yet; the level is raised anyway, as the maker asks
 * while A11 is moved.  About 20 ms, once, at load.
 */
static void
xsurf_pnp(b)
xs_board_t *b;
{
    int i, s;

    s = splxs();
    b->va[XSURF_A11] = 0x00;
    pnp_address(b, 0);
    pnp_address(b, 0);
    for (i = 0; i < 32; i++)
	pnp_address(b, xs_pnp_key(i));
    pnp_write(b, 0x02, 0x04);			/* reset card numbers */
    pnp_write(b, 0x03, 0x00);			/* wake card 0: isolation */
    pnp_write(b, 0x00, PNP_READ_PORT >> 2);	/* the read port */
    pnp_address(b, 0x01);			/* serial isolation */
    xs_udelay(1000L);
    for (i = 0; i < 72; i++) {
	(void)pnp_read(b);
	(void)pnp_read(b);
	xs_udelay(250L);
    }
    pnp_write(b, 0x06, 0x01);			/* card number 1 */
    pnp_write(b, 0x07, 0x00);			/* logical device 0 */
    pnp_write(b, 0x60, (XSURF_IO >> 8) & 0xff);	/* I/O base */
    pnp_write(b, 0x61, XSURF_IO & 0xff);
    pnp_write(b, 0x30, 0x01);			/* activate */
    pnp_write(b, 0x02, 0x02);			/* wait for the key again */
    splx(s);
}

static int
xsurf_probe(b, detail)
xs_board_t *b;
int *detail;
{
    if (bprobe((caddr_t)XSURF_REG(b, XS_CR), -1)) {
	cmn_err(CE_NOTE, "xsurf: X-Surf at 0x%x: no answer in its ISA window",
	    (int)b->phys);
	return XSURF_REFUSED_NOANSWER;
    }
    if (!xs_chip_reset(b)) {
	xsurf_pnp(b);
	b->st.pnp = 1;
	cmn_err(CE_NOTE, "xsurf: X-Surf at 0x%x: chip set up through ISA plug-and-play",
	    (int)b->phys);
    }
    return xs_probe_chip(b, detail);
}

/*
 * A board AutoConfig gave the finder: in use as xs_board[board], or refused
 * (board -1) with a record of what it is and why.
 */
static void
xs_note_found(board, c, addr, why, detail)
int board, why, detail;
struct xs_card *c;
long addr;
{
    xs_found_t *f;

    if (xs_nfound >= XSURF_MAXFOUND)
	return;
    f = &xs_found[xs_nfound++];
    bzero((caddr_t)f, sizeof(xs_found_t));
    f->board = board;
    if (board >= 0)
	return;
    f->rec.version = XSURF_STATUS_VERSION;
    f->rec.size = sizeof(xsurf_status_t);
    f->rec.board_kind = c->ops->kind;
    f->rec.board_phys = (unsigned int)addr;
    f->rec.zorro = (unsigned long)addr >= (unsigned long)0x01000000 ? 3 : 2;
    f->rec.unit = 0xffffffff;
    f->rec.refused = why;
    f->rec.refused_detail = detail;
    f->rec.link = XSURF_LINK_UNKNOWN;
    f->rec.link_duplex = XSURF_DUPLEX_UNKNOWN;
}

/*
 * Every board of every known card, in the order of xs_cards, up to
 * XS_MAXBOARDS in use: found through AutoConfig, mapped, probed.  The
 * units are numbered in that order; a refused board takes no unit and is
 * left with nothing behind (no mapping, its interrupt mask cleared when
 * its registers answered).  xs_found records every board either way.
 * Returns how many are set up.
 */
int
xs_find_boards()
{
    struct xs_card *c;
    xs_board_t *b;
    long addr, size;
    int i, why, detail;

    xs_nboards = xs_nfound = 0;
    for (c = xs_cards; c->ops; c++) {
	for (i = 0; xs_nboards < XS_MAXBOARDS; i++) {
	    addr = size = 0;
	    if (!autocon(c->id, i, &addr, &size))
		break;
	    b = &xs_board[xs_nboards];
	    bzero((caddr_t)b, sizeof(xs_board_t));
	    b->ops = c->ops;
	    b->unit = xs_nboards;
	    b->tx_cur = -1;
	    if ((unsigned long)addr >= (unsigned long)0x80000000) {
		cmn_err(CE_NOTE,
		    "xsurf: %s at 0x%x: placed at or above 0x80000000, the board has shut itself up",
		    c->ops->name, (int)addr);
		xs_note_found(-1, c, addr, XSURF_REFUSED_HIGH, 0);
		continue;
	    }
	    if ((unsigned long)size < c->bytes) {
		cmn_err(CE_NOTE, "xsurf: %s at 0x%x: AutoConfig size 0x%x too small",
		    c->ops->name, (int)addr, (int)size);
		xs_note_found(-1, c, addr, XSURF_REFUSED_SMALL, (int)size);
		continue;
	    }
	    if (xs_map(b, (unsigned long)addr, c->bytes) != 0) {
		cmn_err(CE_NOTE, "xsurf: %s at 0x%x: no kernel address space to map it",
		    c->ops->name, (int)addr);
		xs_note_found(-1, c, addr, XSURF_REFUSED_NOMAP, 0);
		continue;
	    }
	    detail = 0;
	    if ((why = (*c->probe)(b, &detail)) != XSURF_REFUSED_NONE) {
		if (why != XSURF_REFUSED_NOANSWER)
		    xs_chip_stop(b);	/* its interrupt masked, if writes land */
		xs_unmap(b);
		xs_note_found(-1, c, addr, why, detail);
		continue;
	    }
	    b->present = 1;
	    b->st.board_kind = c->ops->kind;
	    b->st.board_phys = (unsigned int)addr;
	    b->st.zorro = (unsigned long)addr >= (unsigned long)0x01000000 ? 3 : 2;
	    b->st.unit = b->unit;
	    xs_note_found(xs_nboards, c, addr, XSURF_REFUSED_NONE, 0);
	    xs_nboards++;
	}
    }
    return xs_nboards;
}
