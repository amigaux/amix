/*
 * bootinfo.c -- see bootinfo.h.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "bootinfo.h"

static void
copy(ax_u8 *d, const ax_u8 *s, ax_u32 n)
{
	while (n--)
		*d++ = *s++;
}

static void
zero(ax_u8 *d, ax_u32 n)
{
	while (n--)
		*d++ = 0;
}

/* make the sum of the n longs at p zero by setting the long at p + at */
static void
seal(ax_u8 *p, int n, int at)
{
	ax_u32 sum = 0;
	int i;

	AX_PUT32(p + at, 0);
	for (i = 0; i < n; i++)
		sum += AX_GET32(p + 4 * i);
	AX_PUT32(p + at, (ax_u32)(0 - sum));
}

static int
prefix(const char *s, const char *p)
{
	while (*p)
		if (*s++ != *p++)
			return 0;
	return 1;
}

static int
hexnum(const char *s, ax_u32 *v)
{
	ax_u32 n = 0;
	int any = 0, d;

	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		s += 2;
	for (; *s && *s != ' '; s++, any++) {
		if (*s >= '0' && *s <= '9') d = *s - '0';
		else if (*s >= 'a' && *s <= 'f') d = *s - 'a' + 10;
		else if (*s >= 'A' && *s <= 'F') d = *s - 'A' + 10;
		else return 0;
		if (any >= 8)
			return 0;
		n = (n << 4) | (ax_u32)d;
	}
	*v = n;
	return any > 0;
}

static int
decnum(const char *s, ax_u32 *v)
{
	ax_u32 n = 0;
	int any = 0;

	for (; *s && *s != ' '; s++, any++) {
		if (*s < '0' || *s > '9' || any >= 9)
			return 0;
		n = n * 10 + (ax_u32)(*s - '0');
	}
	*v = n;
	return any > 0;
}

int
ax_disksel_parse(const char *s, struct ax_disksel *d)
{
	d->kind = AXS_NONE;
	d->id = d->base = d->unit = d->slice = 0;
	d->mobo = 0;
	if (prefix(s, "none") && (s[4] == 0 || s[4] == ' '))
		return 0;
	if (prefix(s, "ramdisk") && (s[7] == 0 || s[7] == ' ')) {
		d->kind = AXS_RAMDISK;
		return 0;
	}
	if (!prefix(s, "sd ") && !(prefix(s, "sd") && s[2] == 0))
		return -1;
	d->kind = AXS_SD;
	for (s += 2; *s;) {
		while (*s == ' ')
			s++;
		if (!*s)
			break;
		if (prefix(s, "id=")) {
			if (!hexnum(s + 3, &d->id)) return -1;
		} else if (prefix(s, "base=")) {
			if (!hexnum(s + 5, &d->base)) return -1;
		} else if (prefix(s, "unit=")) {
			if (!decnum(s + 5, &d->unit) || d->unit > 7) return -1;
		} else if (prefix(s, "slice=")) {
			if (!decnum(s + 6, &d->slice) || d->slice > 7) return -1;
		} else if (prefix(s, "mobo") && (s[4] == 0 || s[4] == ' ')) {
			d->mobo = 1;
		} else {
			return -1;
		}
		while (*s && *s != ' ')
			s++;
	}
	if (d->mobo ? (d->id || d->base) : (!d->id && !d->base))
		return -1;	/* name exactly one kind of controller */
	return 0;
}

int
ax_rto1_build(const struct ax_disksel *d, ax_u8 out[AX_RTO1_LEN])
{
	if (d->kind != AXS_SD || d->unit > 7)
		return -1;
	AX_PUT32(out, AX_RTO1_MAGIC);
	AX_PUT32(out + 4, 0x00010000UL | AX_RTO1_LEN);
	AX_PUT32(out + 8, d->unit);
	AX_PUT32(out + 12, d->base);
	AX_PUT32(out + 16, d->id);
	AX_PUT32(out + 20, d->mobo ? RTO_MOBO : 0);
	seal(out, 7, 24);
	return 0;
}

void
ax_rth1_build(ax_u32 flags, ax_u32 boot_unit, ax_u32 boot_base, ax_u32 boot_id,
	      const ax_u8 *root, ax_u8 out[AX_RTH1_LEN])
{
	zero(out, AX_RTH1_LEN);
	AX_PUT32(out, AX_RTH1_MAGIC);
	AX_PUT32(out + 4, 0x00010000UL | AX_RTH1_LEN);
	AX_PUT32(out + 8, flags | (root ? RTH_ROOT : 0));
	AX_PUT32(out + 12, boot_unit);
	AX_PUT32(out + 16, boot_base);
	AX_PUT32(out + 20, boot_id);
	seal(out, 7, 24);
	if (root)
		copy(out + 28, root, AX_RTO1_LEN);
}

static void
put_sel(ax_u8 *p, const struct ax_disksel *d)
{
	AX_PUT32(p, (ax_u32)d->kind | (d->mobo ? 0x100UL : 0));
	AX_PUT32(p + 4, d->id);
	AX_PUT32(p + 8, d->base);
	AX_PUT32(p + 12, d->unit);
	AX_PUT32(p + 16, d->slice);
}

/*
 * AXL1, 124 bytes:
 *   0 magic   4 version 1 << 16 | length   8 check (longs sum to zero)
 *  12 loader version  16 boot1 choice  20 cpu  24 AttnFlags
 *  28 generation id   32 state  36 flags
 *  40 boot device: name CRC, unit, partition start, board base, board id
 *  60 root selector: kind (| 0x100 motherboard), id, base, unit, slice
 *  80 swap selector, same shape
 * 100 root filesystem type, NUL-padded to 16
 * 116 RAM-disk physical address, 120 size
 */
void
ax_axl1_build(const struct ax_loaderrec *l, ax_u8 out[AX_AXL1_LEN])
{
	int i;

	zero(out, AX_AXL1_LEN);
	AX_PUT32(out, AX_AXL1_MAGIC);
	AX_PUT32(out + 4, 0x00010000UL | AX_AXL1_LEN);
	AX_PUT32(out + 12, l->loader_version);
	AX_PUT32(out + 16, l->boot1_choice);
	AX_PUT32(out + 20, l->cpu);
	AX_PUT32(out + 24, l->attnflags);
	AX_PUT32(out + 28, l->gen_id);
	AX_PUT32(out + 32, l->gen_state);
	AX_PUT32(out + 36, l->flags);
	AX_PUT32(out + 40, l->dev_namecrc);
	AX_PUT32(out + 44, l->dev_unit);
	AX_PUT32(out + 48, l->dev_start);
	AX_PUT32(out + 52, l->dev_base);
	AX_PUT32(out + 56, l->dev_id);
	put_sel(out + 60, &l->root);
	put_sel(out + 80, &l->swap);
	for (i = 0; i < 15 && l->rootfs[i]; i++)
		out[100 + i] = (ax_u8)l->rootfs[i];
	AX_PUT32(out + 116, l->ramdisk_addr);
	AX_PUT32(out + 120, l->ramdisk_size);
	seal(out, AX_AXL1_LEN / 4, 8);
}

int
ax_bootinfo_build(ax_u8 out[AXB_SIZE], const ax_u8 *cfgdevs, int ncfg,
		  const ax_u8 *memhdrs, int nmem, const ax_u8 keys[16],
		  const struct ax_bootdata *bd, const ax_u8 rth1[AX_RTH1_LEN],
		  const ax_u8 axl1[AX_AXL1_LEN])
{
	ax_u8 *p;

	if (ncfg < 0 || ncfg > AXB_MAXBOARDS || nmem < 0 || nmem > AXB_MAXMEM)
		return -1;
	zero(out, AXB_SIZE);
	copy(out + AXB_AUTOCON, cfgdevs, (ax_u32)ncfg * AXB_CFGSIZE);
	copy(out + AXB_MEMORY, memhdrs, (ax_u32)nmem * AXB_MEMSIZE);
	if (keys)
		copy(out + AXB_KEYS, keys, 16);
	p = out + AXB_BOOTDATA;
	AX_PUT32(p, bd->entry);
	AX_PUT32(p + 4, bd->tvaddr);
	AX_PUT32(p + 8, bd->toffset);
	AX_PUT32(p + 12, bd->tsize);
	AX_PUT32(p + 16, bd->rvaddr);
	AX_PUT32(p + 20, bd->roffset);
	AX_PUT32(p + 24, bd->rsize);
	AX_PUT32(p + 28, bd->dvaddr);
	AX_PUT32(p + 32, bd->doffset);
	AX_PUT32(p + 36, bd->dsize);
	if (rth1)
		copy(out + AXB_RESERVED, rth1, AX_RTH1_LEN);
	if (axl1)
		copy(out + AXB_RESERVED + AX_AXL1_OFF, axl1, AX_AXL1_LEN);
	return 0;
}

int
ax_memcap(ax_u8 *mems, int n, ax_u32 base, ax_u32 cap)
{
	ax_u8 *m, *e = mems + n * AXB_MEMSIZE;
	ax_u32 lo = 1, l;
	int cut = 0;

	for (m = mems; m < e; m += AXB_MEMSIZE) {	/* the region holding base */
		l = AX_GET32(m + 20) & ~0xFFUL;
		if (!(AX_GET16(m + 14) & 0x2) && base >= l && base < AX_GET32(m + 24)) {
			lo = l;
			if (AX_GET32(m + 24) - l > cap)
				AX_PUT32(m + 24, l + cap), cut = 1;
		}
	}
	/* one touching it from below ends a 2 KiB page short of it: the
	 * kernel then does not join it to its main store, and its range stays
	 * for the k30 DMA pool (C4-5 section 5.2) */
	for (m = mems; m < e; m += AXB_MEMSIZE)
		if (!(AX_GET16(m + 14) & 0x2) && AX_GET32(m + 24) == lo)
			AX_PUT32(m + 24, lo - 0x800), cut = 1;
	return cut;
}

ax_u32
ax_bind_region(const struct ax_memr *r, int n, ax_u32 *size)
{
	ax_u32 base = 0, max = 0, lower, upper;
	int i;

	for (i = 0; i < n; i++) {
		if (r[i].attr & 0x2)
			continue;	/* MEMF_CHIP */
		lower = r[i].lower & ~0xFFUL;
		/* the kernel runs where its virtual and physical addresses agree:
		 * below AX_IDMAP_TOP only (Zorro III expansion memory lies above) */
		upper = r[i].upper > AX_IDMAP_TOP ? AX_IDMAP_TOP : r[i].upper;
		if (upper > lower && upper - lower > max)
			max = upper - lower, base = lower;
	}
	*size = max;
	return base;
}
