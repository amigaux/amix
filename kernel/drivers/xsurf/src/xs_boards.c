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
 * bytes of its window the driver uses, and its probe (reset, station
 * address, chip set up and stopped; 0 = not usable).
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

/*
 * What both cards' probes end with: reset, station address, the chip set
 * up and left stopped.  0 with a console line naming what failed.
 */
static int
xs_probe_chip(b)
xs_board_t *b;
{
    if (!xs_chip_reset(b)) {
	cmn_err(CE_NOTE, "xsurf: %s at 0x%x: the chip does not reset",
	    b->ops->name, (int)b->phys);
	return 0;
    }
    if (!xs_read_prom(b, b->mac)) {
	cmn_err(CE_NOTE, "xsurf: %s at 0x%x: no usable station address",
	    b->ops->name, (int)b->phys);
	return 0;
    }
    xs_chip_init(b, 0);
    return 1;
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
 * The PHY is powered through GPOC and left to the chip: no MII access.
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

/* GPOC: only ever written with no remote DMA set up (a stopped chip, a
 * zero remote count), so a model that decodes it as the data port moves
 * nothing */
static void
xs100_phy(b, on)
xs_board_t *b;
int on;
{
    xs100_wr(b, XS_GPOC, on ? 0 : XS_GPOC_PPDSET);
}

static struct xs_ops xs100_ops = {
    "X-Surf-100", XSURF_KIND_XSURF100, 0x40,
    xs100_rd, xs100_wr, xs100_bin, xs100_bout, xs100_irq, xs100_phy,
};

static int
xs100_probe(b)
xs_board_t *b;
{
    if (bprobe((caddr_t)XS100_REG(b, XS_CR), -1)) {
	cmn_err(CE_NOTE, "xsurf: X-Surf-100 at 0x%x: no answer at its registers",
	    (int)b->phys);
	return 0;
    }
    return xs_probe_chip(b);
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

static struct xs_ops xsurf_ops = {
    "X-Surf", XSURF_KIND_XSURF, 0x00,
    xsurf_rd, xsurf_wr, xsurf_bin, xsurf_bout, xsurf_irq, 0,
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
xsurf_probe(b)
xs_board_t *b;
{
    if (bprobe((caddr_t)XSURF_REG(b, XS_CR), -1)) {
	cmn_err(CE_NOTE, "xsurf: X-Surf at 0x%x: no answer in its ISA window",
	    (int)b->phys);
	return 0;
    }
    if (!xs_chip_reset(b)) {
	xsurf_pnp(b);
	b->st.pnp = 1;
	cmn_err(CE_NOTE, "xsurf: X-Surf at 0x%x: chip set up through ISA plug-and-play",
	    (int)b->phys);
    }
    return xs_probe_chip(b);
}

/*
 * Every board of every known card, in the order of xs_cards, up to
 * XS_MAXBOARDS: found through AutoConfig, mapped, probed.  The units are
 * numbered in that order.  Returns how many are set up.
 */
int
xs_find_boards()
{
    struct xs_card *c;
    xs_board_t *b;
    long addr, size;
    int i;

    xs_nboards = 0;
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
		continue;
	    }
	    if ((unsigned long)size < c->bytes) {
		cmn_err(CE_NOTE, "xsurf: %s at 0x%x: AutoConfig size 0x%x too small",
		    c->ops->name, (int)addr, (int)size);
		continue;
	    }
	    if (xs_map(b, (unsigned long)addr, c->bytes) != 0) {
		cmn_err(CE_NOTE, "xsurf: %s at 0x%x: no kernel address space to map it",
		    c->ops->name, (int)addr);
		continue;
	    }
	    if (!(*c->probe)(b)) {
		xs_unmap(b);
		continue;
	    }
	    b->present = 1;
	    b->st.board_kind = c->ops->kind;
	    b->st.board_phys = (unsigned int)addr;
	    b->st.zorro = (unsigned long)addr >= (unsigned long)0x01000000 ? 3 : 2;
	    xs_nboards++;
	}
    }
    return xs_nboards;
}
