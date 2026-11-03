/*
 * knl.c -- the booted kernel's namelist (see knl.h).
 *
 * An ET_REL kernel is laid out by the loader's relocator (rel.c) at the
 * bind address, exactly as boot2 laid it out, COMMON symbols included;
 * each defined symbol in text, rodata, data or bss then has the address
 * of its section plus its value, and etext, edata and end are absolute.
 * A brel carries no symbols, so its line ships unix.sym, whose values are
 * addresses at bind 0: each symbol defined in a section is moved by the
 * bind address (as are etext, edata and end); SHN_ABS is a constant.
 *
 * The namelist: the ELF header, the four sections as NOBITS (addresses
 * and sizes, no contents), .symtab with the local symbols first, .strtab
 * and .shstrtab.  With x, the loaded modules' globals are added, and
 * crash_sync gets an eighth section of its own, PROGBITS, holding the
 * running kernel's word: stock crash reads 4 bytes at the symbol's own
 * section's sh_offset + (st_value - sh_addr) to compare with memory, and
 * on a NOBITS section reads past the file's end and stops.  When the word
 * cannot be read, crash_sync is left out (crash then warns that it checks
 * no timestamps, and goes on).  An address names the section it lies in, a constant
 * stays SHN_ABS, so a namelist made at bind 0 is itself a unix.sym.  The same inputs give the same bytes, so a caller can
 * tell a current namelist from a stale one by comparing them.
 *
 * Portable C89.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rel.h"
#include "knl.h"

#define ET_REL		1
#define ET_EXEC		2
#define SHT_PROGBITS	1
#define SHT_SYMTAB	2
#define SHT_STRTAB	3
#define SHT_NOBITS	8
#define SHF_WRITE	1
#define SHF_ALLOC	2
#define SHF_EXECINSTR	4
#define SHN_UNDEF	0
#define SHN_LORESERVE	0xff00
#define SHN_ABS		0xfff1
#define SHN_COMMON	0xfff2
#define STB_LOCAL	0
#define STT_SECTION	3
#define STT_FILE	4

struct nsym {
	ax_u32 name, value, size;	/* name: offset in the input's strings */
	const char *xname;		/* or the name itself (an added symbol) */
	ax_u8 info;
	ax_u8 cnst;			/* a constant (SHN_ABS), not an address */
};

static const char *cmpstr;		/* the input's strings, for by_local */

static const char *
nsname(const struct nsym *s)
{
	return s->xname ? s->xname : cmpstr + s->name;
}

/* etext, edata and end are addresses, whatever section names them */
static int
isaddr(const char *nm)
{
	return !strcmp(nm, "etext") || !strcmp(nm, "edata") || !strcmp(nm, "end");
}

static int
elfok(const ax_u8 *p, ax_u32 n)
{
	return n >= 52 && p[0] == 0x7F && p[1] == 'E' && p[2] == 'L' && p[3] == 'F' &&
	       p[4] == 1 && p[5] == 2 && AX_GET16(p + 18) == 4;
}

static int
inside(ax_u32 off, ax_u32 n, ax_u32 len)
{
	return off <= len && n <= len - off;
}

static int
by_local(const void *a, const void *b)
{
	const struct nsym *x = (const struct nsym *)a, *y = (const struct nsym *)b;
	int lx = (x->info >> 4) == STB_LOCAL, ly = (y->info >> 4) == STB_LOCAL;

	if (lx != ly)
		return ly - lx;
	return x->value < y->value ? -1 : x->value > y->value ? 1 : strcmp(nsname(x), nsname(y));
}

int
kb_namelist(const ax_u8 *kern, ax_u32 klen, const ax_u8 *sym, ax_u32 slen, ax_u32 bind,
	    const struct kb_nlx *x, struct kb_layout *lay, ax_u8 **out, ax_u32 *olen, char why[120])
{
	static const char shstr[] = "\0.text\0.rodata\0.data\0.bss\0.symtab\0.strtab\0.shstrtab"
				    "\0.crash_sync";
	static const ax_u32 shname[] = { 0, 1, 7, 15, 21, 26, 34, 42 };
	static const ax_u32 shflags[] = { SHF_ALLOC | SHF_EXECINSTR, SHF_ALLOC, SHF_ALLOC | SHF_WRITE,
					  SHF_ALLOC | SHF_WRITE };
	ax_u8 *img = 0, *o = 0, *sh;
	const ax_u8 *e, *st;
	struct nsym *ns = 0;
	ax_u32 shoff, shent, shnum, i, k, sy = 0, nsy, syoff, syent, stroff, strsize;
	ax_u32 secaddr[64], n = 0, nlocal, strtot, off, symoff, stroff2, shstroff, shoff2, len, shstr0;
	ax_u32 shlen = sizeof(shstr) - 12, nsh = 8, csoff = 0, cs = 0;	/* cs: crash_sync's index + 1 */
	ax_u8 csw[4];
	int rc = -1;

	memset(lay, 0, sizeof(*lay));
	*out = 0;
	*olen = 0;
	if (sym) {
		if (!elfok(sym, slen) || AX_GET16(sym + 16) != ET_EXEC) {
			strcpy(why, "unix.sym is not a big-endian m68k ELF executable (C2-3 2.1)");
			return -1;
		}
		e = sym;
		len = slen;
	} else {
		struct ax_bootdata bd;
		struct ax_relerr er;

		if (!elfok(kern, klen) || AX_GET16(kern + 16) != ET_REL) {
			strcpy(why, "the kernel has no symbols (not ET_REL, and no unix.sym)");
			return -1;
		}
		if ((img = malloc(klen)) == 0) {
			strcpy(why, "out of memory");
			return -1;
		}
		memcpy(img, kern, klen);
		if (ax_rel(img, klen, bind, 1, &bd, &er) != AXR_OK) {
			sprintf(why, "the loader's relocator refuses the kernel (section %lu, entry %lu)",
				(unsigned long)er.rsect, (unsigned long)er.index);
			goto out;
		}
		lay->entry = bd.entry;
		e = img;
		len = klen;
	}

	shoff = AX_GET32(e + 32);
	shent = AX_GET16(e + 46);
	shnum = AX_GET16(e + 48);
	if (shent < 40 || shnum == 0 || shnum > 64 || !inside(shoff, shnum * shent, len)) {
		strcpy(why, "bad section headers");
		goto out;
	}
	/* each section's address in this boot; the four the loader binds.  A
	 * unix.sym's sections may all be NOBITS: there the name decides */
	shstr0 = AX_GET16(e + 50) < shnum ? AX_GET32(e + shoff + AX_GET16(e + 50) * shent + 16) : 0;
	for (i = 0; i < shnum; i++) {
		const ax_u8 *s = e + shoff + i * shent;
		ax_u32 t = AX_GET32(s + 4), fl = AX_GET32(s + 8), sz = AX_GET32(s + 20);
		const char *nm = shstr0 && shstr0 + AX_GET32(s) < len ? (const char *)e + shstr0 + AX_GET32(s) : "";

		secaddr[i] = AX_GET32(s + 12) + (sym ? bind : 0);
		if (t == SHT_SYMTAB)
			sy = i;
		if (!(fl & SHF_ALLOC) || sz == 0 || (t != SHT_PROGBITS && t != SHT_NOBITS))
			continue;
		k = (fl & SHF_EXECINSTR) ? 0 : t == SHT_NOBITS ? 3 : (fl & SHF_WRITE) ? 2 : 1;
		if (sym && !(fl & SHF_EXECINSTR))
			k = !strncmp(nm, ".rodata", 7) ? 1 : !strncmp(nm, ".data", 5) ? 2 :
			    !strncmp(nm, ".bss", 4) ? 3 : k;
		if (!sym && t == SHT_NOBITS && !(fl & SHF_WRITE))
			continue;
		lay->vaddr[k] = secaddr[i];
		lay->size[k] = sz;
	}
	if (sym) {
		lay->entry = bind;
		if (!lay->vaddr[0]) {		/* a symbols file with no sections: text at bind */
			lay->vaddr[0] = bind;
			lay->size[0] = 0;
		}
	}
	if (!sy) {
		strcpy(why, "no symbol table");
		goto out;
	}
	st = e + shoff + sy * shent;
	syoff = AX_GET32(st + 16);
	syent = AX_GET32(st + 36);
	k = AX_GET32(st + 24);
	if (syent < 16 || !inside(syoff, AX_GET32(st + 20), len) || k >= shnum) {
		strcpy(why, "bad symbol table");
		goto out;
	}
	nsy = AX_GET32(st + 20) / syent;
	stroff = AX_GET32(e + shoff + k * shent + 16);
	strsize = AX_GET32(e + shoff + k * shent + 20);
	if (!inside(stroff, strsize, len) || strsize == 0 || e[stroff + strsize - 1] != 0) {
		strcpy(why, "bad string table");
		goto out;
	}
	if ((ns = malloc((nsy + (x ? (ax_u32)x->nsym : 0) + 1) * sizeof(*ns))) == 0) {
		strcpy(why, "out of memory");
		goto out;
	}
	/* the defined symbols with a name, at their addresses in this boot */
	for (strtot = 1, i = 1; i < nsy; i++) {
		const ax_u8 *p = e + syoff + i * syent;
		ax_u32 nm = AX_GET32(p), v = AX_GET32(p + 4);
		ax_u16 x = AX_GET16(p + 14);
		ax_u8 info = p[12];
		int a;

		if (!nm || nm >= strsize || !e[stroff + nm] || x == SHN_UNDEF || x == SHN_COMMON ||
		    (info & 15) == STT_SECTION || (info & 15) == STT_FILE)
			continue;
		a = isaddr((const char *)e + stroff + nm);
		if (x == SHN_ABS) {
			if (sym && a)		/* unix.sym: an address at bind 0 */
				v += bind;
		} else if (x < SHN_LORESERVE && x < shnum &&
			   (AX_GET32(e + shoff + x * shent + 8) & SHF_ALLOC)) {
			a = 1;
			v += sym ? bind : secaddr[x];	/* unix.sym: the address at bind 0 */
		} else
			continue;
		ns[n].cnst = (ax_u8)!a;
		ns[n].name = nm;
		ns[n].xname = 0;
		ns[n].value = v;
		ns[n].size = AX_GET32(p + 8);
		ns[n].info = info;
		strtot += (ax_u32)strlen((const char *)e + stroff + nm) + 1;
		n++;
	}
	/* the added symbols: the loaded modules' globals, addresses of this boot */
	for (i = 0; x && i < (ax_u32)x->nsym; i++) {
		if (!x->sym[i].name || !x->sym[i].name[0])
			continue;
		ns[n].cnst = 0;
		ns[n].name = 0;
		ns[n].xname = x->sym[i].name;
		ns[n].value = x->sym[i].value;
		ns[n].size = x->sym[i].size;
		ns[n].info = x->sym[i].info;
		strtot += (ax_u32)strlen(x->sym[i].name) + 1;
		n++;
	}
	cmpstr = (const char *)e + stroff;
	/* crash_sync: its own section with the running kernel's word, or out */
	for (i = 0; x && i < n; i++)
		if (!ns[i].cnst && !strcmp(nsname(&ns[i]), "crash_sync")) {
			if (x->mem && x->mem(x->ctx, ns[i].value, csw, 4) == 0) {
				nsh = 9;
				shlen = sizeof(shstr);
			} else {
				strtot -= (ax_u32)strlen("crash_sync") + 1;
				ns[i] = ns[--n];
			}
			break;
		}
	qsort(ns, n, sizeof(*ns), by_local);
	for (nlocal = 0; nlocal < n && (ns[nlocal].info >> 4) == STB_LOCAL; nlocal++)
		;
	for (i = 0; nsh == 9 && i < n; i++)
		if (!ns[i].cnst && !strcmp(nsname(&ns[i]), "crash_sync"))
			cs = i + 1;

	/* the namelist: header, .symtab, .strtab, .shstrtab, crash_sync's
	 * word, section headers */
	symoff = 52;
	stroff2 = symoff + 16 * (n + 1);
	shstroff = stroff2 + strtot;
	shoff2 = (shstroff + shlen + 3) & ~3UL;
	if (cs) {
		csoff = shoff2;
		shoff2 += 4;
	}
	*olen = shoff2 + nsh * 40;
	if ((o = calloc(1, *olen)) == 0) {
		strcpy(why, "out of memory");
		goto out;
	}
	memcpy(o, "\177ELF\1\2\1", 7);
	AX_PUT16(o + 16, ET_EXEC);
	AX_PUT16(o + 18, 4);
	AX_PUT32(o + 20, 1);
	AX_PUT32(o + 24, lay->entry);
	AX_PUT32(o + 32, shoff2);
	AX_PUT16(o + 40, 52);
	AX_PUT16(o + 46, 40);
	AX_PUT16(o + 48, nsh);
	AX_PUT16(o + 50, 7);
	for (off = 1, i = 0; i < n; i++) {
		ax_u8 *p = o + symoff + 16 * (i + 1);
		const char *nm = nsname(&ns[i]);
		ax_u16 xs = SHN_ABS;

		/* an address: the section it lies in, or the one it ends */
		for (k = 0; k < 4 && !ns[i].cnst; k++)
			if (lay->size[k] && ns[i].value >= lay->vaddr[k] &&
			    ns[i].value - lay->vaddr[k] <= lay->size[k] &&
			    (xs == SHN_ABS || ns[i].value - lay->vaddr[k] < lay->size[k]))
				xs = (ax_u16)(k + 1);
		AX_PUT32(p, off);
		AX_PUT32(p + 4, ns[i].value);
		AX_PUT32(p + 8, ns[i].size);
		p[12] = ns[i].info;
		AX_PUT16(p + 14, cs == i + 1 ? 8 : xs);
		strcpy((char *)o + stroff2 + off, nm);
		off += (ax_u32)strlen(nm) + 1;
	}
	memcpy(o + shstroff, shstr, shlen);
	for (k = 0; k < 4; k++) {
		sh = o + shoff2 + 40 * (k + 1);
		AX_PUT32(sh, shname[k + 1]);
		AX_PUT32(sh + 4, SHT_NOBITS);
		AX_PUT32(sh + 8, shflags[k]);
		AX_PUT32(sh + 12, lay->vaddr[k]);
		AX_PUT32(sh + 16, shoff2);
		AX_PUT32(sh + 20, lay->size[k]);
		AX_PUT32(sh + 32, 4);
	}
	sh = o + shoff2 + 40 * 5;		/* .symtab */
	AX_PUT32(sh, shname[5]);
	AX_PUT32(sh + 4, SHT_SYMTAB);
	AX_PUT32(sh + 16, symoff);
	AX_PUT32(sh + 20, 16 * (n + 1));
	AX_PUT32(sh + 24, 6);
	AX_PUT32(sh + 28, nlocal + 1);
	AX_PUT32(sh + 32, 4);
	AX_PUT32(sh + 36, 16);
	sh = o + shoff2 + 40 * 6;		/* .strtab */
	AX_PUT32(sh, shname[6]);
	AX_PUT32(sh + 4, SHT_STRTAB);
	AX_PUT32(sh + 16, stroff2);
	AX_PUT32(sh + 20, strtot);
	AX_PUT32(sh + 32, 1);
	sh = o + shoff2 + 40 * 7;		/* .shstrtab */
	AX_PUT32(sh, shname[7]);
	AX_PUT32(sh + 4, SHT_STRTAB);
	AX_PUT32(sh + 16, shstroff);
	AX_PUT32(sh + 20, shlen);
	AX_PUT32(sh + 32, 1);
	if (cs) {				/* crash_sync's word */
		memcpy(o + csoff, csw, 4);
		sh = o + shoff2 + 40 * 8;
		AX_PUT32(sh, (ax_u32)sizeof(shstr) - 12);
		AX_PUT32(sh + 4, SHT_PROGBITS);
		AX_PUT32(sh + 8, SHF_ALLOC | SHF_WRITE);
		AX_PUT32(sh + 12, ns[cs - 1].value);
		AX_PUT32(sh + 16, csoff);
		AX_PUT32(sh + 20, 4);
		AX_PUT32(sh + 32, 4);
	}
	*out = o;
	o = 0;
	rc = 0;
out:
	free(img);
	free(ns);
	free(o);
	if (rc)
		*olen = 0;
	return rc;
}
