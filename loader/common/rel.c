/*
 * rel.c -- kernel relocation (see rel.h).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "rel.h"

#define ET_REL		1
#define ET_EXEC		2
#define ET_BREL		0xff00
#define EM_68K		4
#define SHT_PROGBITS	1
#define SHT_SYMTAB	2
#define SHT_RELA	4
#define SHT_NOBITS	8
#define SHF_WRITE	1
#define SHF_ALLOC	2
#define SHF_EXECINSTR	4
#define SHN_ABS		0xfff1
#define SHN_COMMON	0xfff2
#define R_68K_32	1
#define R_68K_PC32	4
#define R_68K_PC16	5
#define R_68K_PC8	6

#define SH(i)		(img + shoff + (ax_u32)(i) * shentsize)

/* is [off, off+n) inside len? overflow-safe */
static int
inside(ax_u32 off, ax_u32 n, ax_u32 len)
{
	return off <= len && n <= len - off;
}

static int
streq(const ax_u8 *a, const char *b)
{
	while (*a && *a == (ax_u8)*b)
		a++, b++;
	return *a == 0 && *b == 0;
}

static int
brel(ax_u8 *img, ax_u32 len, ax_u32 vaddr, ax_u32 shoff, ax_u32 shentsize,
     ax_u32 shnum, struct ax_bootdata *bd)
{
	ax_u32 toff, tsize, roff, rsize, i, off, val;
	ax_u8 *p;

	if (shnum < 4)
		return AXR_ENOSECT;
	toff = AX_GET32(SH(1) + 16);
	tsize = AX_GET32(SH(1) + 20);
	roff = AX_GET32(SH(3) + 16);
	rsize = AX_GET32(SH(3) + 20);
	if (!inside(toff, tsize, len) || !inside(roff, rsize, len) || rsize % 8)
		return AXR_EBOUNDS;
	for (i = 0; i < rsize; i += 8) {
		off = AX_GET32(img + roff + i);
		val = AX_GET32(img + roff + i + 4);
		if (!(off & 0x80000000UL))
			val += vaddr;
		off &= 0x7FFFFFFFUL;
		if (!inside(off, 4, tsize))
			return AXR_EBOUNDS;
		p = img + toff + off;
		AX_PUT32(p, val);
	}
	bd->entry = bd->tvaddr = vaddr;
	bd->toffset = toff;
	bd->tsize = tsize;
	bd->end = vaddr + tsize;
	return AXR_OK;
}

int
ax_rel(ax_u8 *img, ax_u32 len, ax_u32 vaddr, int pcrel_ok,
       struct ax_bootdata *bd, struct ax_relerr *err)
{
	ax_u32 type, shoff, shentsize, shnum, i, k;
	ax_u32 t = 0, r = 0, d = 0, b = 0, sy = 0;	/* section indices; 0 = none */
	ax_u32 end, syoff, syent, nsym, stroff, strsize;
	ax_u32 bound[4];
	ax_u8 *s, *sym;

	bd->entry = bd->tvaddr = bd->toffset = bd->tsize = 0;
	bd->rvaddr = bd->roffset = bd->rsize = 0;
	bd->dvaddr = bd->doffset = bd->dsize = bd->end = 0;
	err->rsect = err->index = err->type = err->sym = 0;

	if (len < 52 || img[0] != 0x7F || img[1] != 'E' || img[2] != 'L' || img[3] != 'F' ||
	    img[4] != 1 || img[5] != 2 || AX_GET16(img + 18) != EM_68K)
		return AXR_EFORMAT;
	type = AX_GET16(img + 16);

	if (type == ET_EXEC) {
		ax_u32 phoff = AX_GET32(img + 28);

		if (AX_GET16(img + 44) < 1 || !inside(phoff, 32, len))
			return AXR_EBOUNDS;
		bd->entry = AX_GET32(img + 24);
		bd->toffset = AX_GET32(img + phoff + 4);
		bd->tvaddr = AX_GET32(img + phoff + 8);
		bd->tsize = AX_GET32(img + phoff + 16);
		if (!inside(bd->toffset, bd->tsize, len))
			return AXR_EBOUNDS;
		bd->end = bd->tvaddr + AX_GET32(img + phoff + 20);
		return AXR_OK;
	}

	shoff = AX_GET32(img + 32);
	shentsize = AX_GET16(img + 46);
	shnum = AX_GET16(img + 48);
	if (shentsize < 40 || shnum == 0 || !inside(shoff, shnum * shentsize, len))
		return AXR_EBOUNDS;

	if (type == ET_BREL)
		return brel(img, len, vaddr, shoff, shentsize, shnum, bd);
	if (type != ET_REL)
		return AXR_EFORMAT;

	/* pick the sections by flags; the last of each kind wins */
	for (i = 0; i < shnum; i++) {
		ax_u32 st = AX_GET32(SH(i) + 4), fl = AX_GET32(SH(i) + 8), sz = AX_GET32(SH(i) + 20);

		if (st == SHT_PROGBITS && sz > 0 && (fl & SHF_ALLOC)) {
			if (fl & SHF_EXECINSTR)
				t = i;
			else if (fl & SHF_WRITE)
				d = i;
			else
				r = i;
		} else if (st == SHT_NOBITS && (fl & SHF_WRITE) && sz > 0) {
			b = i;
		} else if (st == SHT_SYMTAB) {
			sy = i;
		}
	}
	if (!t || !sy)
		return AXR_ENOSECT;

	/* bind text, rodata, data, bss in that order, no padding */
	end = vaddr;
	bound[0] = t, bound[1] = r, bound[2] = d, bound[3] = b;
	for (k = 0; k < 4; k++) {
		if (!bound[k])
			continue;
		s = SH(bound[k]);
		if (AX_GET32(s + 4) == SHT_PROGBITS && !inside(AX_GET32(s + 16), AX_GET32(s + 20), len))
			return AXR_EBOUNDS;
		AX_PUT32(s + 12, end);
		end += AX_GET32(s + 20);
	}
	bd->entry = vaddr;
	bd->tvaddr = AX_GET32(SH(t) + 12);
	bd->toffset = AX_GET32(SH(t) + 16);
	bd->tsize = AX_GET32(SH(t) + 20);
	if (r) {
		bd->rvaddr = AX_GET32(SH(r) + 12);
		bd->roffset = AX_GET32(SH(r) + 16);
		bd->rsize = AX_GET32(SH(r) + 20);
	}
	if (d) {
		bd->dvaddr = AX_GET32(SH(d) + 12);
		bd->doffset = AX_GET32(SH(d) + 16);
		bd->dsize = AX_GET32(SH(d) + 20);
	}

	/* the symbol table and its strings */
	syoff = AX_GET32(SH(sy) + 16);
	syent = AX_GET32(SH(sy) + 36);
	if (syent < 16 || !inside(syoff, AX_GET32(SH(sy) + 20), len))
		return AXR_EBOUNDS;
	nsym = AX_GET32(SH(sy) + 20) / syent;
	k = AX_GET32(SH(sy) + 24);
	if (k >= shnum)
		return AXR_EBOUNDS;
	stroff = AX_GET32(SH(k) + 16);
	strsize = AX_GET32(SH(k) + 20);
	if (!inside(stroff, strsize, len) || strsize == 0 || img[stroff + strsize - 1] != 0)
		return AXR_EBOUNDS;

	/* COMMON symbols: placed after bss, each at its alignment */
	for (i = 0; i < nsym; i++) {
		sym = img + syoff + i * syent;
		if (AX_GET16(sym + 14) == SHN_COMMON) {
			ax_u32 align = AX_GET32(sym + 4), at;

			if (!b) {
				err->sym = i;
				return AXR_ESYMBOL;
			}
			if (align == 0)
				align = 1;
			s = SH(b);
			at = AX_GET32(s + 12) + AX_GET32(s + 20);
			at = (at + align - 1) & ~(align - 1);
			AX_PUT16(sym + 14, b);
			AX_PUT32(sym + 4, at - AX_GET32(s + 12));
			end = at + AX_GET32(sym + 8);
			AX_PUT32(s + 20, end - AX_GET32(s + 12));
		}
	}
	bd->end = end;

	/* etext, edata, end become absolute */
	for (i = 0; i < nsym; i++) {
		ax_u32 nm;

		sym = img + syoff + i * syent;
		nm = AX_GET32(sym);
		if (!nm || nm >= strsize)
			continue;
		if (streq(img + stroff + nm, "etext")) {
			AX_PUT32(sym + 4, AX_GET32(SH(t) + 12) + AX_GET32(SH(t) + 20));
			AX_PUT16(sym + 14, SHN_ABS);
		} else if (streq(img + stroff + nm, "edata")) {
			if (!d)
				return AXR_ENOSECT;
			AX_PUT32(sym + 4, AX_GET32(SH(d) + 12) + AX_GET32(SH(d) + 20));
			AX_PUT16(sym + 14, SHN_ABS);
		} else if (streq(img + stroff + nm, "end")) {
			AX_PUT32(sym + 4, end);
			AX_PUT16(sym + 14, SHN_ABS);
		}
	}

	/* relocate every RELA section */
	for (i = 0; i < shnum; i++) {
		ax_u32 roff, rsize, rent, tgt, toff, tsize, taddr, n;

		s = SH(i);
		if (AX_GET32(s + 4) != SHT_RELA)
			continue;
		roff = AX_GET32(s + 16);
		rsize = AX_GET32(s + 20);
		rent = AX_GET32(s + 36);
		tgt = AX_GET32(s + 28);
		if (rent < 12 || !inside(roff, rsize, len) || tgt >= shnum)
			return AXR_EBOUNDS;
		if (AX_GET32(s + 24) != sy)
			return AXR_ENOSECT;	/* one symbol table only */
		toff = AX_GET32(SH(tgt) + 16);
		tsize = AX_GET32(SH(tgt) + 20);
		taddr = AX_GET32(SH(tgt) + 12);
		if (!inside(toff, tsize, len))
			return AXR_EBOUNDS;
		for (n = 0; n < rsize / rent; n++) {
			ax_u8 *rec = img + roff + n * rent;
			ax_u32 off = AX_GET32(rec), info = AX_GET32(rec + 4);
			ax_u32 add = AX_GET32(rec + 8), rt = info & 0xFF, si = info >> 8;
			ax_u32 shx, S, v;
			ax_s32 disp;
			ax_u8 *p;

			err->rsect = i, err->index = n, err->type = rt, err->sym = si;
			if (si >= nsym)
				return AXR_ESYMBOL;
			sym = img + syoff + si * syent;
			shx = AX_GET16(sym + 14);
			if (shx > 0 && shx < shnum) {
				if (shx != t && shx != r && shx != d && shx != b)
					return AXR_ESYMBOL;
				S = AX_GET32(SH(shx) + 12) + AX_GET32(sym + 4);
			} else if (shx == SHN_ABS) {
				S = AX_GET32(sym + 4);
			} else {
				return AXR_ESYMBOL;
			}
			v = S + add;
			if (rt == R_68K_32) {
				if (!inside(off, 4, tsize))
					return AXR_EBOUNDS;
				p = img + toff + off;
				AX_PUT32(p, v);
				continue;
			}
			if (!pcrel_ok || (rt != R_68K_PC32 && rt != R_68K_PC16 && rt != R_68K_PC8))
				return AXR_ETYPE;
			if (tgt != t && tgt != r && tgt != d)
				return AXR_ESYMBOL;	/* the field's own section must be bound */
			disp = (ax_s32)(v - (taddr + off));
			p = img + toff + off;
			if (rt == R_68K_PC32) {
				if (!inside(off, 4, tsize))
					return AXR_EBOUNDS;
				AX_PUT32(p, (ax_u32)disp);
			} else if (rt == R_68K_PC16) {
				if (!inside(off, 2, tsize))
					return AXR_EBOUNDS;
				if (disp < -32768L || disp > 32767L)
					return AXR_ERANGE;
				AX_PUT16(p, (ax_u32)disp);
			} else {
				if (!inside(off, 1, tsize))
					return AXR_EBOUNDS;
				if (disp < -128 || disp > 127)
					return AXR_ERANGE;
				*p = (ax_u8)disp;
			}
		}
	}
	return AXR_OK;
}
