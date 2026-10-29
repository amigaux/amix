/*
 * t_rel.c -- the kernel relocator on synthetic ELF images: binding order,
 * COMMON placement, etext/edata/end, R_68K_32, the PC-relative types and
 * their range checks, and every refusal.  Real kernels: rel-kernels.sh.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <string.h>
#include "t.h"
#include "rel.h"

#define V 0x07800000UL

static ax_u8 img[4096];
static ax_u32 imglen;
static struct ax_bootdata bd;
static struct ax_relerr er;

static void
p32(ax_u32 o, ax_u32 v) { AX_PUT32(img + o, v); }
static void
p16(ax_u32 o, ax_u32 v) { AX_PUT16(img + o, v); }

/* symbol table entries: name offset, value, size, shndx */
struct sy { ax_u32 name, value, size, shndx; };
/* relocations: offset, symbol, type, addend */
struct rl { ax_u32 off, sym, type, add; };

/*
 * Layout: header | .text 64 | .rodata 16 | .data 16 | symtab | strtab |
 * shstrtab | rela.text | section headers (NULL, text, rodata, data, bss,
 * symtab, strtab, shstrtab, rela.text).  bss is 32 bytes.
 */
static void
build(const struct sy *s, int ns, const struct rl *r, int nr, ax_u32 type)
{
	static const char strtab[] = "\0etext\0edata\0end\0foo\0com\0";
	ax_u32 o = 52, text, rod, data, sym, str, shs, rela, sh;
	int i;

	memset(img, 0, sizeof(img));
	img[0] = 0x7F; img[1] = 'E'; img[2] = 'L'; img[3] = 'F';
	img[4] = 1; img[5] = 2; img[6] = 1;
	p16(16, type); p16(18, 4); p32(20, 1);
	text = o; o += 64;
	for (i = 0; i < 64; i += 2)
		p16(text + i, 0x4E71);		/* nop */
	rod = o; o += 16;
	data = o; o += 16;
	sym = o; o += 16 * (ns + 1);
	for (i = 0; i < ns; i++) {
		p32(sym + 16 * (i + 1), s[i].name);
		p32(sym + 16 * (i + 1) + 4, s[i].value);
		p32(sym + 16 * (i + 1) + 8, s[i].size);
		img[sym + 16 * (i + 1) + 12] = 0x11;
		p16(sym + 16 * (i + 1) + 14, s[i].shndx);
	}
	str = o; memcpy(img + o, strtab, sizeof(strtab)); o += sizeof(strtab);
	shs = o; img[o++] = 0;
	rela = o;
	for (i = 0; i < nr; i++) {
		p32(o, r[i].off);
		p32(o + 4, (r[i].sym << 8) | r[i].type);
		p32(o + 8, r[i].add);
		o += 12;
	}
	o = (o + 3) & ~3UL;
	sh = o;
	p32(32, sh); p16(46, 40); p16(48, 9); p16(50, 7);
	/* name, type, flags, addr, offset, size, link, info, align, entsize */
#define SEC(n, t, f, off, sz, lk, inf, es) \
	p32(sh + 40 * (n) + 4, t); p32(sh + 40 * (n) + 8, f); p32(sh + 40 * (n) + 16, off); \
	p32(sh + 40 * (n) + 20, sz); p32(sh + 40 * (n) + 24, lk); p32(sh + 40 * (n) + 28, inf); \
	p32(sh + 40 * (n) + 36, es)
	SEC(1, 1, 6, text, 64, 0, 0, 0);		/* .text  ALLOC|EXEC */
	SEC(2, 1, 2, rod, 16, 0, 0, 0);			/* .rodata ALLOC */
	SEC(3, 1, 3, data, 16, 0, 0, 0);		/* .data ALLOC|WRITE */
	SEC(4, 8, 3, data + 16, 32, 0, 0, 0);		/* .bss NOBITS */
	SEC(5, 2, 0, sym, 16 * (ns + 1), 6, 1, 16);	/* .symtab */
	SEC(6, 3, 0, str, sizeof(strtab), 0, 0, 0);
	SEC(7, 3, 0, shs, 1, 0, 0, 0);
	SEC(8, 4, 0, rela, 12 * nr, 5, 1, 12);		/* .rela.text -> .text */
	imglen = sh + 40 * 9;
}

static ax_u32
textword(ax_u32 off) { return AX_GET32(img + 52 + off); }

void
test_rel(void)
{
	/* symbols: 1 etext, 2 edata, 3 end, 4 foo (data+4), 5 com (COMMON, align 8, size 12),
	 * 6 abs 0x1234, 7 undefined, 8 foo-in-text (+0x10) */
	struct sy s[] = {
		{ 1, 0, 0, 1 }, { 7, 0, 0, 3 }, { 13, 0, 0, 4 }, { 17, 4, 4, 3 },
		{ 21, 8, 12, 0xfff2 }, { 0, 0x1234, 0, 0xfff1 }, { 17, 0, 0, 0 },
		{ 17, 0x10, 0, 1 } };
	struct rl ok[] = {
		{ 0x00, 4, 1, 0 },	/* foo: data + 4 */
		{ 0x04, 1, 1, 0 },	/* etext */
		{ 0x08, 2, 1, 0 },	/* edata */
		{ 0x0c, 3, 1, 0 },	/* end */
		{ 0x10, 5, 1, 2 },	/* com + 2 */
		{ 0x14, 6, 1, 1 },	/* abs + 1 */
		{ 0x18, 8, 4, 0 },	/* PC32 to text+0x10 from 0x18 */
		{ 0x1c, 8, 5, 0 },	/* PC16 to text+0x10 from 0x1c */
		{ 0x1e, 8, 6, (ax_u32)-1 } };	/* PC8 (bra.b style addend -1) */
	struct rl r;
	ax_u32 end;

	build(s, 8, ok, 9, 1);
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_OK);
	T_EQ(bd.entry, V);
	T_EQ(bd.tvaddr, V);
	T_EQ(bd.tsize, 64);
	T_EQ(bd.rvaddr, V + 64);		/* rodata right after text */
	T_EQ(bd.dvaddr, V + 80);		/* data right after rodata */
	T_EQ(bd.dsize, 16);
	/* bss at V+96..V+128; COMMON aligned to 8 at V+128, 12 bytes: end V+140 */
	end = V + 140;
	T_EQ(bd.end, end);
	T_EQ(textword(0x00), V + 80 + 4);
	T_EQ(textword(0x04), V + 64);		/* etext */
	T_EQ(textword(0x08), V + 96);		/* edata */
	T_EQ(textword(0x0c), end);		/* end */
	T_EQ(textword(0x10), V + 128 + 2);	/* com + 2 */
	T_EQ(textword(0x14), 0x1235);
	T_EQ(textword(0x18), (ax_u32)(0x10 - 0x18));
	T_EQ(AX_GET16(img + 52 + 0x1c), 0xFFF4);	/* 0x10 - 0x1c */
	T_EQ(img[52 + 0x1e], 0xF1);			/* 0x10 - 1 - 0x1e = -15 */

	/* the stock loader handles only R_68K_32: PC types refused without pcrel_ok */
	build(s, 8, ok, 9, 1);
	T_EQ(ax_rel(img, imglen, V, 0, &bd, &er), AXR_ETYPE);
	T_EQ(er.index, 6);

	/* PC16 out of range */
	r.off = 0x1c; r.sym = 6; r.type = 5; r.add = 0x40000;	/* absolute target far away */
	build(s, 8, &r, 1, 1);
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_ERANGE);
	/* PC8 out of range */
	r.off = 0x1e; r.sym = 8; r.type = 6; r.add = 400;
	build(s, 8, &r, 1, 1);
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_ERANGE);

	/* undefined symbol */
	r.off = 0; r.sym = 7; r.type = 1; r.add = 0;
	build(s, 8, &r, 1, 1);
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_ESYMBOL);
	T_EQ(er.sym, 7);
	/* symbol index past the table */
	r.sym = 99;
	build(s, 8, &r, 1, 1);
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_ESYMBOL);
	/* unknown relocation type */
	r.sym = 4; r.type = 9;
	build(s, 8, &r, 1, 1);
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_ETYPE);
	/* field beyond the section */
	r.off = 62; r.type = 1;
	build(s, 8, &r, 1, 1);
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_EBOUNDS);
	/* truncated image: section header table cut off */
	build(s, 8, ok, 9, 1);
	T_EQ(ax_rel(img, imglen - 10, V, 1, &bd, &er), AXR_EBOUNDS);
	/* not an m68k ELF */
	build(s, 8, ok, 9, 1);
	img[19] = 3;
	T_EQ(ax_rel(img, imglen, V, 1, &bd, &er), AXR_EFORMAT);

	/* brel: section 1 combined text, section 3 the pair table */
	memset(img, 0, sizeof(img));
	img[0] = 0x7F; img[1] = 'E'; img[2] = 'L'; img[3] = 'F'; img[4] = 1; img[5] = 2;
	p16(16, 0xff00); p16(18, 4);
	p32(32, 300); p16(46, 40); p16(48, 4);
	p32(300 + 40 + 16, 100); p32(300 + 40 + 20, 32);	/* text at 100, 32 bytes */
	p32(300 + 120 + 16, 200); p32(300 + 120 + 20, 16);	/* two pairs at 200 */
	p32(200, 4); p32(204, 0x20);				/* text[4] = V + 0x20 */
	p32(208, 0x80000008UL); p32(212, 0xDEADBEEFUL);	/* text[8] = absolute */
	T_EQ(ax_rel(img, 700, V, 0, &bd, &er), AXR_OK);
	T_EQ(AX_GET32(img + 104), V + 0x20);
	T_EQ(AX_GET32(img + 108), 0xDEADBEEFUL);
	T_EQ(bd.tsize, 32);
	T_EQ(bd.toffset, 100);
	/* a brel records no bss: its end is the image's, and ax_kernel_end adds
	 * the manifest's bss=, or assumes AX_BREL_BSS without one */
	{
		int assumed;

		T_EQ(bd.brel, 1);
		T_EQ(bd.end, V + 32);
		T_EQ(ax_kernel_end(&bd, 283445, &assumed), V + 32 + 283445);
		T_EQ(assumed, 0);
		T_EQ(ax_kernel_end(&bd, 0, &assumed), V + 32 + AX_BREL_BSS);
		T_EQ(assumed, 1);
		/* an ET_REL's end already holds its bss: bss= is not added */
		bd.brel = 0;
		T_EQ(ax_kernel_end(&bd, 283445, &assumed), V + 32);
		T_EQ(assumed, 0);
	}
	/* a pair pointing past the text */
	p32(200, 30);
	T_EQ(ax_rel(img, 700, V, 0, &bd, &er), AXR_EBOUNDS);
}
