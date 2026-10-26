/*
 * kmod.c -- see kmod.h.  The object is read by explicit byte offsets, as
 * the module core reads it (core patch 0003).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "kmod.h"

#define G16(p)	((ax_u32)(p)[0] << 8 | (ax_u32)(p)[1])
#define G32(p)	(G16(p) << 16 | G16((p) + 2))

/* copy a key's value into dst (cap bytes), refusing an overlong one */
static int
put(char *dst, size_t cap, const char *v)
{
	if (strlen(v) >= cap)
		return -1;
	strcpy(dst, v);
	return 0;
}

/* "<name>:<type>:<default>[:<min>:<max>]" */
static int
param(struct km_param *p, const char *v)
{
	char buf[256], *f[6], *s;
	int n = 0;

	if (strlen(v) >= sizeof(buf))
		return -1;
	strcpy(buf, v);
	for (s = buf, f[n++] = s; *s && n < 6; s++)
		if (*s == ':') {
			*s = 0;
			f[n++] = s + 1;
		}
	if ((n != 3 && n != 5) || put(p->name, sizeof(p->name), f[0]) || !f[0][0] ||
	    put(p->type, sizeof(p->type), f[1]) || put(p->def, sizeof(p->def), f[2]))
		return -1;
	if (strcmp(p->type, "int") && strcmp(p->type, "hex") && strcmp(p->type, "bool") &&
	    strcmp(p->type, "str"))
		return -1;
	p->has_range = n == 5;
	if (p->has_range) {
		char *e1, *e2;

		p->min = strtol(f[3], &e1, 0);
		p->max = strtol(f[4], &e2, 0);
		if (*e1 || *e2 || p->min > p->max)
			return -1;
	}
	return 0;
}

int
km_read(const ax_u8 *b, ax_u32 len, struct km_info *mi, char *why)
{
	ax_u32 shoff, shnum, shstr, i, so, md = 0, mdlen = 0, o;
	int found = 0;

	memset(mi, 0, sizeof(*mi));
	if (len < 52 || memcmp(b, "\177ELF", 4) || b[4] != 1 || b[5] != 2 ||
	    G16(b + 16) != 1 || G16(b + 18) != 4) {
		strcpy(why, "not an ELF32 big-endian 68k relocatable object");
		return -1;
	}
	shoff = G32(b + 32);
	shnum = G16(b + 48);
	shstr = G16(b + 50);
	if (G16(b + 46) != 40 || shstr >= shnum || shoff > len || shnum * 40 > len - shoff) {
		strcpy(why, "malformed section headers");
		return -1;
	}
	so = G32(b + shoff + 40 * shstr + 16);
	for (i = 0; i < shnum; i++) {
		const ax_u8 *s = b + shoff + 40 * i;
		ax_u32 nm = so + G32(s);

		if (G32(s + 4) == 13 || (nm + 9 <= len && !memcmp(b + nm, ".moddata", 9))) {
			found++;
			md = G32(s + 16);
			mdlen = G32(s + 20);
		}
	}
	if (found != 1 || md > len || mdlen > len - md || mdlen < 12 || mdlen > 2048) {
		strcpy(why, found == 1 ? "a .moddata of the wrong size" : "not exactly one .moddata");
		return -1;
	}
	if (memcmp(b + md + 4, "MD2", 4)) {
		strcpy(why, "not .moddata version 2 (no MD2 marker)");
		return -1;
	}
	for (o = 8; ; ) {
		const char *k = (const char *)b + md + o, *v;
		size_t n;
		int bad = 0;

		if (o >= mdlen || !memchr(k, 0, mdlen - o)) {
			strcpy(why, ".moddata's key list does not end");
			return -1;
		}
		n = strlen(k);
		if (!n)
			break;
		o += (ax_u32)n + 1;
		if (!(v = strchr(k, '='))) {
			sprintf(why, ".moddata string without '=': %.40s", k);
			return -1;
		}
		v++;
#define KEY(s)	(!strncmp(k, s "=", sizeof(s)))
		if (KEY("name")) bad = put(mi->name, sizeof(mi->name), v);
		else if (KEY("kabi")) bad = put(mi->kabi, sizeof(mi->kabi), v);
		else if (KEY("cc")) bad = put(mi->cc, sizeof(mi->cc), v);
		else if (KEY("cpu")) bad = put(mi->cpu, sizeof(mi->cpu), v);
		else if (KEY("class")) bad = put(mi->cls, sizeof(mi->cls), v);
		else if (KEY("match")) bad = put(mi->match, sizeof(mi->match), v);
		else if (KEY("majors")) bad = put(mi->majors, sizeof(mi->majors), v);
		else if (KEY("depend")) bad = put(mi->depend, sizeof(mi->depend), v);
		else if (KEY("unload")) bad = put(mi->unload, sizeof(mi->unload), v);
		else if (KEY("tier")) bad = put(mi->tier, sizeof(mi->tier), v);
		else if (KEY("build")) bad = put(mi->build, sizeof(mi->build), v);
		else if (KEY("param")) {
			if (mi->nparam == KM_MAXPARAM) {
				strcpy(why, "more parameters than kbootset takes (16)");
				return -1;
			}
			bad = param(&mi->param[mi->nparam++], v);
		} else if (k[0] == '!') {
			sprintf(why, "a critical key kbootset does not know: %.40s", k);
			return -1;
		}
#undef KEY
		if (bad) {
			sprintf(why, "malformed .moddata key: %.60s", k);
			return -1;
		}
	}
	if (!mi->name[0] || !mi->kabi[0] || !mi->cc[0] || !mi->cpu[0] || !mi->cls[0]) {
		strcpy(why, ".moddata lacks one of name, kabi, cc, cpu, class");
		return -1;
	}
	return 0;
}

int
km_value(const struct km_param *p, const char *in, char *out)
{
	if (!strcmp(p->type, "bool")) {
		static const char *const t[] = { "1", "yes", "true", "on", 0 };
		static const char *const f[] = { "0", "no", "false", "off", 0 };
		int i;

		for (i = 0; t[i]; i++)
			if (!strcmp(in, t[i]) || !strcmp(in, f[i])) {
				strcpy(out, strcmp(in, t[i]) ? "0" : "1");
				return 0;
			}
		return -1;
	}
	if (!strcmp(p->type, "int") || !strcmp(p->type, "hex")) {
		char *e;
		long v;
		const char *s = in;

		/* decimal, or 0x-hex; never octal */
		if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
			v = strtol(s, &e, 16);
		else {
			if (*s == '-')
				s++;
			if (*s < '0' || *s > '9')
				return -1;
			v = strtol(in, &e, 10);
		}
		if (!*in || *e || (p->has_range && (v < p->min || v > p->max)))
			return -1;
		if (!strcmp(p->type, "int"))
			sprintf(out, "%ld", v);
		else
			sprintf(out, "0x%lx", (unsigned long)v);
		return 0;
	}
	if (strlen(in) > 63 || strchr(in, ' ') || strchr(in, '\t'))
		return -1;
	strcpy(out, in);
	return 0;
}

int
km_tail(const ax_u8 *b, ax_u32 len, ax_u32 *tail, char *why)
{
	ax_u32 shoff, shnum, i, k, t, al, off = 0, so, sz, n;

	if (len < 52 || memcmp(b, "\177ELF", 4) || G16(b + 46) != 40) {
		strcpy(why, "not an ELF32 relocatable object");
		return -1;
	}
	shoff = G32(b + 32);
	shnum = G16(b + 48);
	if (shoff > len || shnum * 40 > len - shoff) {
		strcpy(why, "malformed section headers");
		return -1;
	}
	for (i = 1; i < shnum; i++) {		/* the NOBITS sections */
		const ax_u8 *s = b + shoff + 40 * i;

		if (!(G32(s + 8) & 2))		/* SHF_ALLOC */
			continue;
		t = G32(s + 4);
		al = G32(s + 32) < 4 ? 4 : G32(s + 32);
		if ((al & (al - 1)) || al > 16) {
			sprintf(why, "section %lu is aligned to %lu: the arena aligns to 16",
				(unsigned long)i, (unsigned long)al);
			return -1;
		}
		if (t == 8) {			/* SHT_NOBITS */
			off = (off + al - 1) & ~(al - 1);
			off += G32(s + 20);
		} else if (G32(s + 16) % al) {
			sprintf(why, "section %lu lies at file offset %lu, not a multiple of %lu",
				(unsigned long)i, (unsigned long)G32(s + 16), (unsigned long)al);
			return -1;
		}
	}
	for (i = 1; i < shnum; i++) {		/* then the commons */
		const ax_u8 *s = b + shoff + 40 * i;

		if (G32(s + 4) != 2)		/* SHT_SYMTAB */
			continue;
		so = G32(s + 16);
		sz = G32(s + 20);
		if (G32(s + 36) != 16 || so > len || sz > len - so) {
			strcpy(why, "malformed symbol table");
			return -1;
		}
		for (n = sz / 16, k = 1; k < n; k++) {
			const ax_u8 *y = b + so + 16 * k;

			if (G16(y + 14) != 0xfff2)	/* SHN_COMMON */
				continue;
			al = G32(y + 4) ? G32(y + 4) : 1;
			if ((al & (al - 1)) || al > 16) {
				sprintf(why, "a common symbol is aligned to %lu: the arena aligns to 16",
					(unsigned long)al);
				return -1;
			}
			off = (off + al - 1) & ~(al - 1);
			off += G32(y + 8);
		}
	}
	*tail = (off + 3) & ~(ax_u32)3;
	return 0;
}
