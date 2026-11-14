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

static int	xs100_probe();
static struct xs_ops xs100_ops;

static struct xs_card xs_cards[] = {
    { 0x12120064, &xs100_ops, 0x9000, xs100_probe },	/* X-Surf-100 */
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
    volatile unsigned long *fifo;
    int n;

    while (len >= 4) {
	n = len & ~3;
	if (n > XS100_BLOCK)
	    n = XS100_BLOCK;
	len -= n;
	fifo = (volatile unsigned long *)(b->va + XS100_FIFO_RD);
	for (; n > 0; n -= 4, buf += 4)
	    *(unsigned long *)buf = *fifo++;
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
    volatile unsigned long *fifo;
    int n;

    while (len >= 4) {
	n = len & ~3;
	if (n > XS100_BLOCK)
	    n = XS100_BLOCK;
	len -= n;
	fifo = (volatile unsigned long *)(b->va + XS100_FIFO_WR);
	for (; n > 0; n -= 4, buf += 4)
	    *fifo++ = *(unsigned long *)buf;
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
