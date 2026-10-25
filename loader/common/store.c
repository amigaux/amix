/*
 * store.c -- parse and write the boot store structures (see store.h).
 *
 * Byte layouts (big-endian):
 *
 *   header AXS1, 512 bytes          control block AXC1, 2048 bytes
 *     0 magic       4 version          0 magic     4 version  6 ngen
 *     6 hdrlen      8 seq              8 seq      12 default 16 trial
 *    12 store_size 16 flags           20 oneshot  24 oneshot_gen
 *    20 volume     22 nvolumes        28 menu_ds  30 console 32 serial_baud
 *    24 set_id                        64 + 64*i  generation entry i:
 *    28 boot2[0] {off,len,crc,ver}       +0 id +4 state +5 flags
 *    44 boot2[1] {off,len,crc,ver}       +6 attempts +8 volume
 *    60 ctl_off[0] 64 ctl_off[1]         +12 man_off +16 man_len
 *    68 tally_off  72 medium             +20 man_crc +24 created
 *   508 crc32 of bytes 0..507         2044 crc32 of bytes 0..2043
 *
 *   tally AXT1, 2048 bytes: 0 magic, 4 hdr_seq, 8 attempts,
 *                           2044 crc32 of bytes 0..2043
 *
 * Unused bytes are written as zero and ignored when read.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "store.h"
#include "crc32.h"

static void
zero(ax_u8 *p, ax_u32 n)
{
	while (n--)
		*p++ = 0;
}

static int
aligned_extent(const struct ax_extent *e, ax_u32 max)
{
	if (e->len == 0)
		return e->off == 0;
	return (e->off % AX_BLK) == 0 && e->len <= max;
}

int
ax_hdr_parse(const ax_u32 *crctab, const ax_u8 buf[512], struct ax_header *h)
{
	int i;
	const ax_u8 *p;

	if (AX_GET32(buf) != AX_MAGIC_HDR)
		return AX_EMAGIC;
	if (AX_GET32(buf + 508) != ax_crc32(crctab, buf, 508))
		return AX_ECRC;
	h->magic = AX_MAGIC_HDR;
	h->version = AX_GET16(buf + 4);
	h->hdrlen = AX_GET16(buf + 6);
	if (h->version != AX_STORE_VERSION || h->hdrlen != AX_HDR_SIZE)
		return AX_EVERSION;
	h->seq = AX_GET32(buf + 8);
	h->store_size = AX_GET32(buf + 12);
	h->flags = AX_GET32(buf + 16);
	h->volume = AX_GET16(buf + 20);
	h->nvolumes = AX_GET16(buf + 22);
	h->set_id = AX_GET32(buf + 24);
	for (i = 0; i < 2; i++) {
		p = buf + 28 + 16 * i;
		h->boot2[i].off = AX_GET32(p);
		h->boot2[i].len = AX_GET32(p + 4);
		h->boot2[i].crc = AX_GET32(p + 8);
		h->boot2[i].ver = AX_GET32(p + 12);
		if (!aligned_extent(&h->boot2[i], AX_BOOT2_MAX))
			return AX_ERANGE;
	}
	if (h->boot2[0].len == 0)
		return AX_ERANGE;
	h->ctl_off[0] = AX_GET32(buf + 60);
	h->ctl_off[1] = AX_GET32(buf + 64);
	h->tally_off = AX_GET32(buf + 68);
	h->medium = AX_GET32(buf + 72);
	if (h->ctl_off[0] % AX_BLK || h->ctl_off[1] % AX_BLK || h->tally_off % AX_BLK)
		return AX_ERANGE;
	if (h->volume == 0 || h->volume > h->nvolumes)
		return AX_ERANGE;
	return AX_OK;
}

void
ax_hdr_write(const ax_u32 *crctab, const struct ax_header *h, ax_u8 buf[512])
{
	int i;
	ax_u8 *p;

	zero(buf, 512);
	AX_PUT32(buf, AX_MAGIC_HDR);
	AX_PUT16(buf + 4, AX_STORE_VERSION);
	AX_PUT16(buf + 6, AX_HDR_SIZE);
	AX_PUT32(buf + 8, h->seq);
	AX_PUT32(buf + 12, h->store_size);
	AX_PUT32(buf + 16, h->flags);
	AX_PUT16(buf + 20, h->volume);
	AX_PUT16(buf + 22, h->nvolumes);
	AX_PUT32(buf + 24, h->set_id);
	for (i = 0; i < 2; i++) {
		p = buf + 28 + 16 * i;
		AX_PUT32(p, h->boot2[i].off);
		AX_PUT32(p + 4, h->boot2[i].len);
		AX_PUT32(p + 8, h->boot2[i].crc);
		AX_PUT32(p + 12, h->boot2[i].ver);
	}
	AX_PUT32(buf + 60, h->ctl_off[0]);
	AX_PUT32(buf + 64, h->ctl_off[1]);
	AX_PUT32(buf + 68, h->tally_off);
	AX_PUT32(buf + 72, h->medium);
	AX_PUT32(buf + 508, ax_crc32(crctab, buf, 508));
}

int
ax_hdr_pick(const ax_u32 *crctab, const ax_u8 a[512], const ax_u8 b[512],
	    struct ax_header *h)
{
	struct ax_header ha, hb;
	int va = ax_hdr_parse(crctab, a, &ha) == AX_OK;
	int vb = ax_hdr_parse(crctab, b, &hb) == AX_OK;

	if (va && (!vb || !AX_SEQ_NEWER(hb.seq, ha.seq))) {
		*h = ha;
		return 0;
	}
	if (vb) {
		*h = hb;
		return 1;
	}
	return AX_ENONE;
}

int
ax_tally_parse(const ax_u32 *crctab, const ax_u8 buf[2048], struct ax_tally *t)
{
	if (AX_GET32(buf) != AX_MAGIC_TALLY)
		return AX_EMAGIC;
	if (AX_GET32(buf + 2044) != ax_crc32(crctab, buf, 2044))
		return AX_ECRC;
	t->magic = AX_MAGIC_TALLY;
	t->hdr_seq = AX_GET32(buf + 4);
	t->attempts = AX_GET32(buf + 8);
	return AX_OK;
}

void
ax_tally_write(const ax_u32 *crctab, const struct ax_tally *t, ax_u8 buf[2048])
{
	zero(buf, 2048);
	AX_PUT32(buf, AX_MAGIC_TALLY);
	AX_PUT32(buf + 4, t->hdr_seq);
	AX_PUT32(buf + 8, t->attempts);
	AX_PUT32(buf + 2044, ax_crc32(crctab, buf, 2044));
}

int
ax_ctl_parse(const ax_u32 *crctab, const ax_u8 buf[2048], struct ax_ctl *c)
{
	int i;
	const ax_u8 *p;

	if (AX_GET32(buf) != AX_MAGIC_CTL)
		return AX_EMAGIC;
	if (AX_GET32(buf + 2044) != ax_crc32(crctab, buf, 2044))
		return AX_ECRC;
	c->magic = AX_MAGIC_CTL;
	c->version = AX_GET16(buf + 4);
	if (c->version != AX_STORE_VERSION)
		return AX_EVERSION;
	c->ngen = AX_GET16(buf + 6);
	if (c->ngen > AX_MAXGEN)
		return AX_ERANGE;
	c->seq = AX_GET32(buf + 8);
	c->default_gen = AX_GET32(buf + 12);
	c->trial_gen = AX_GET32(buf + 16);
	c->oneshot = buf[20];
	c->oneshot_gen = AX_GET32(buf + 24);
	c->menu_ds = AX_GET16(buf + 28);
	c->console = AX_GET16(buf + 30);
	c->serial_baud = AX_GET32(buf + 32);
	for (i = 0; i < AX_MAXGEN; i++) {
		p = buf + 64 + 64 * i;
		c->gen[i].id = AX_GET32(p);
		c->gen[i].state = p[4];
		c->gen[i].flags = p[5];
		c->gen[i].attempts = p[6];
		c->gen[i].volume = AX_GET16(p + 8);
		c->gen[i].man_off = AX_GET32(p + 12);
		c->gen[i].man_len = AX_GET32(p + 16);
		c->gen[i].man_crc = AX_GET32(p + 20);
		c->gen[i].created = AX_GET32(p + 24);
		if (i >= c->ngen && c->gen[i].state != AXG_FREE)
			return AX_ERANGE;
		if (c->gen[i].state > AXG_BAD || c->gen[i].man_off % AX_BLK)
			return AX_ERANGE;
	}
	return AX_OK;
}

void
ax_ctl_write(const ax_u32 *crctab, const struct ax_ctl *c, ax_u8 buf[2048])
{
	int i;
	ax_u8 *p;

	zero(buf, 2048);
	AX_PUT32(buf, AX_MAGIC_CTL);
	AX_PUT16(buf + 4, AX_STORE_VERSION);
	AX_PUT16(buf + 6, c->ngen);
	AX_PUT32(buf + 8, c->seq);
	AX_PUT32(buf + 12, c->default_gen);
	AX_PUT32(buf + 16, c->trial_gen);
	buf[20] = c->oneshot;
	AX_PUT32(buf + 24, c->oneshot_gen);
	AX_PUT16(buf + 28, c->menu_ds);
	AX_PUT16(buf + 30, c->console);
	AX_PUT32(buf + 32, c->serial_baud);
	for (i = 0; i < c->ngen && i < AX_MAXGEN; i++) {
		p = buf + 64 + 64 * i;
		AX_PUT32(p, c->gen[i].id);
		p[4] = c->gen[i].state;
		p[5] = c->gen[i].flags;
		p[6] = c->gen[i].attempts;
		AX_PUT16(p + 8, c->gen[i].volume);
		AX_PUT32(p + 12, c->gen[i].man_off);
		AX_PUT32(p + 16, c->gen[i].man_len);
		AX_PUT32(p + 20, c->gen[i].man_crc);
		AX_PUT32(p + 24, c->gen[i].created);
	}
	AX_PUT32(buf + 2044, ax_crc32(crctab, buf, 2044));
}

int
ax_ctl_pick(const ax_u32 *crctab, const ax_u8 a[2048], const ax_u8 b[2048],
	    struct ax_ctl *c)
{
	/* both copies parsed into one scratch each; struct ax_ctl is ~600 bytes */
	static struct ax_ctl ca, cb;
	int va = ax_ctl_parse(crctab, a, &ca) == AX_OK;
	int vb = ax_ctl_parse(crctab, b, &cb) == AX_OK;

	if (va && (!vb || !AX_SEQ_NEWER(cb.seq, ca.seq))) {
		*c = ca;
		return 0;
	}
	if (vb) {
		*c = cb;
		return 1;
	}
	return AX_ENONE;
}

int
ax_ldrtrial_choice(const struct ax_header *h, int tally_valid,
		   const struct ax_tally *t, int *write_tally)
{
	*write_tally = 0;
	if (!(h->flags & AXF_LDRTRIAL) || (h->flags & AXF_READONLY))
		return 0;
	if (tally_valid && t->hdr_seq == h->seq && t->attempts >= 1)
		return 1;
	*write_tally = 1;
	return 0;
}
