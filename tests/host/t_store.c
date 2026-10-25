/*
 * t_store.c -- header, tally and control block round trips, copy picking,
 * and the boot1 loader-trial rule.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <string.h>
#include "t.h"
#include "crc32.h"
#include "store.h"

static ax_u32 tab[256];

static void
mkhdr(struct ax_header *h, ax_u32 seq)
{
	memset(h, 0, sizeof(*h));
	h->seq = seq;
	h->store_size = 64UL << 20;
	h->flags = AXF_WRITABLE;
	h->volume = h->nvolumes = 1;
	h->set_id = 0x12345678UL;
	h->boot2[0].off = AX_BOOT2_A_OFF;
	h->boot2[0].len = 20000;
	h->boot2[0].crc = 0xdeadbeefUL;
	h->boot2[0].ver = 1;
	h->boot2[1].off = AX_BOOT2_B_OFF;
	h->boot2[1].len = 19000;
	h->ctl_off[0] = AX_CTL_A_OFF;
	h->ctl_off[1] = AX_CTL_B_OFF;
	h->tally_off = AX_TALLY_OFF;
}

static void
test_header(void)
{
	struct ax_header h, g;
	ax_u8 a[512], b[512];

	mkhdr(&h, 7);
	ax_hdr_write(tab, &h, a);
	T_EQ(ax_hdr_parse(tab, a, &g), AX_OK);
	T_EQ(g.seq, 7);
	T_EQ(g.boot2[0].len, 20000);
	T_EQ(g.boot2[1].off, AX_BOOT2_B_OFF);
	T_EQ(g.tally_off, AX_TALLY_OFF);

	/* corruption is caught */
	a[100] ^= 1;
	T_EQ(ax_hdr_parse(tab, a, &g), AX_ECRC);
	a[100] ^= 1;
	a[0] = 'x';
	T_EQ(ax_hdr_parse(tab, a, &g), AX_EMAGIC);

	/* misaligned extent refused */
	mkhdr(&h, 1);
	h.boot2[0].off = 0x900;
	ax_hdr_write(tab, &h, a);
	T_EQ(ax_hdr_parse(tab, a, &g), AX_ERANGE);
	/* oversize boot2 refused */
	mkhdr(&h, 1);
	h.boot2[0].len = AX_BOOT2_MAX + 1;
	ax_hdr_write(tab, &h, a);
	T_EQ(ax_hdr_parse(tab, a, &g), AX_ERANGE);

	/* picking: newer valid copy wins, an invalid copy is skipped */
	mkhdr(&h, 5);
	ax_hdr_write(tab, &h, a);
	mkhdr(&h, 6);
	ax_hdr_write(tab, &h, b);
	T_EQ(ax_hdr_pick(tab, a, b, &g), 1);
	T_EQ(g.seq, 6);
	b[200] ^= 0x40;
	T_EQ(ax_hdr_pick(tab, a, b, &g), 0);
	T_EQ(g.seq, 5);
	a[200] ^= 0x40;
	T_EQ(ax_hdr_pick(tab, a, b, &g), AX_ENONE);
	/* sequence wrap: 0 is newer than 0xFFFFFFFF */
	mkhdr(&h, 0xFFFFFFFFUL);
	ax_hdr_write(tab, &h, a);
	mkhdr(&h, 0);
	ax_hdr_write(tab, &h, b);
	T_EQ(ax_hdr_pick(tab, a, b, &g), 1);
}

static void
test_ctl(void)
{
	static struct ax_ctl c, d;
	ax_u8 a[2048], b[2048];

	memset(&c, 0, sizeof(c));
	c.ngen = 3;
	c.seq = 10;
	c.default_gen = 41;
	c.trial_gen = 42;
	c.oneshot = AXO_PREVIOUS;
	c.menu_ds = 20;
	c.console = AXC_SERIAL | AXC_SCREEN;
	c.serial_baud = 9600;
	c.gen[0].id = 12; c.gen[0].state = AXG_PRISTINE; c.gen[0].volume = 1;
	c.gen[0].man_off = 0x10000; c.gen[0].man_len = 900; c.gen[0].man_crc = 0x1111;
	c.gen[1].id = 41; c.gen[1].state = AXG_GOOD; c.gen[1].volume = 1;
	c.gen[1].man_off = 0x210000;
	c.gen[2].id = 42; c.gen[2].state = AXG_TRIAL; c.gen[2].attempts = 1; c.gen[2].volume = 1;
	c.gen[2].man_off = 0x410000; c.gen[2].created = 1793000000UL;
	ax_ctl_write(tab, &c, a);
	T_EQ(ax_ctl_parse(tab, a, &d), AX_OK);
	T_EQ(d.ngen, 3);
	T_EQ(d.default_gen, 41);
	T_EQ(d.oneshot, AXO_PREVIOUS);
	T_EQ(d.gen[2].state, AXG_TRIAL);
	T_EQ(d.gen[2].attempts, 1);
	T_EQ(d.gen[2].created, 1793000000UL);
	T_EQ(d.gen[0].man_crc, 0x1111);

	c.seq = 11;
	c.oneshot = AXO_NONE;
	ax_ctl_write(tab, &c, b);
	T_EQ(ax_ctl_pick(tab, a, b, &d), 1);
	T_EQ(d.oneshot, AXO_NONE);
	b[2044] ^= 1;		/* torn write of the newer copy */
	T_EQ(ax_ctl_pick(tab, a, b, &d), 0);
	T_EQ(d.seq, 10);

	/* a state value out of range is refused */
	c.gen[1].state = 9;
	ax_ctl_write(tab, &c, a);
	T_EQ(ax_ctl_parse(tab, a, &d), AX_ERANGE);
}

static void
test_ldrtrial(void)
{
	struct ax_header h;
	struct ax_tally t, u;
	ax_u8 buf[2048];
	int w;

	memset(&t, 0, sizeof(t));
	mkhdr(&h, 30);
	/* no trial: primary, no write */
	T_EQ(ax_ldrtrial_choice(&h, 0, &t, &w), 0);
	T_EQ(w, 0);

	h.flags |= AXF_LDRTRIAL;
	/* first start of the new loader: primary, record the attempt */
	T_EQ(ax_ldrtrial_choice(&h, 0, &t, &w), 0);
	T_EQ(w, 1);
	/* tally refers to an older header: same as no attempt */
	t.hdr_seq = 29; t.attempts = 5;
	T_EQ(ax_ldrtrial_choice(&h, 1, &t, &w), 0);
	T_EQ(w, 1);
	/* attempt already recorded for this header: secondary */
	t.hdr_seq = 30; t.attempts = 1;
	T_EQ(ax_ldrtrial_choice(&h, 1, &t, &w), 1);
	T_EQ(w, 0);
	/* a read-only medium never runs a loader trial */
	h.flags |= AXF_READONLY;
	T_EQ(ax_ldrtrial_choice(&h, 1, &t, &w), 0);
	T_EQ(w, 0);

	/* tally round trip and damage */
	t.hdr_seq = 30; t.attempts = 1;
	ax_tally_write(tab, &t, buf);
	T_EQ(ax_tally_parse(tab, buf, &u), AX_OK);
	T_EQ(u.hdr_seq, 30);
	buf[8] ^= 2;
	T_EQ(ax_tally_parse(tab, buf, &u), AX_ECRC);
}

void
test_store(void)
{
	ax_crc32_init(tab);
	test_header();
	test_ctl();
	test_ldrtrial();
}
