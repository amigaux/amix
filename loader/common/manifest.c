/*
 * manifest.c -- GMF1 parser (see manifest.h).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "manifest.h"
#include "crc32.h"

#define MAXTOK 16

static int
streq(const char *a, const char *b)
{
	while (*a && *a == *b)
		a++, b++;
	return *a == *b;
}

static int
prefix(const char *s, const char *p)
{
	while (*p)
		if (*s++ != *p++)
			return 0;
	return 1;
}

/* decimal, or hexadecimal with 0x; the whole string must be consumed */
static int
number(const char *s, ax_u32 *v)
{
	ax_u32 n = 0, d;
	int base = 10, any = 0;

	if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
		base = 16, s += 2;
	for (; *s; s++, any = 1) {
		if (*s >= '0' && *s <= '9')
			d = *s - '0';
		else if (base == 16 && *s >= 'a' && *s <= 'f')
			d = *s - 'a' + 10;
		else if (base == 16 && *s >= 'A' && *s <= 'F')
			d = *s - 'A' + 10;
		else
			return 0;
		if (n > (0xFFFFFFFFUL - d) / base)
			return 0;
		n = n * base + d;
	}
	*v = n;
	return any;
}

static int
hex8(const char *s, ax_u32 *v)
{
	int i;

	for (i = 0; i < 8; i++) {
		char c = s[i];
		if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
		      (c >= 'A' && c <= 'F')))
			return 0;
	}
	if (s[8] != 0)
		return 0;
	{
		char tmp[11];
		tmp[0] = '0', tmp[1] = 'x';
		for (i = 0; i < 9; i++)
			tmp[i + 2] = s[i];
		return number(tmp, v);
	}
}

/* split a line in place into space-separated tokens */
static int
split(char *s, char **tok)
{
	int n = 0;

	for (;;) {
		while (*s == ' ')
			*s++ = 0;
		if (!*s)
			return n;
		if (n == MAXTOK)
			return -1;
		tok[n++] = s;
		while (*s && *s != ' ')
			s++;
	}
}

/* the rest of the line after the key, with the separating space removed */
static char *
rest(char *line)
{
	while (*line && *line != ' ')
		line++;
	while (*line == ' ')
		line++;
	return line;
}

static int
attrs(struct ax_member *mb, char **tok, int ntok)
{
	int i;
	ax_u32 v;
	char *a, *colon;

	mb->stored = mb->size;
	mb->vol = 1;
	for (i = 0; i < ntok; i++) {
		a = tok[i];
		if (prefix(a, "at=")) {
			a += 3;
			for (colon = a; *colon && *colon != ':'; colon++)
				;
			if (*colon == ':') {
				*colon = 0;
				if (!number(a, &v) || v == 0 || v > 0xFFFF)
					return AXM_ESYNTAX;
				mb->vol = (ax_u16)v;
				a = colon + 1;
			}
			if (!number(a, &mb->at))
				return AXM_ESYNTAX;
			mb->has_at = 1;
		} else if (prefix(a, "stored=")) {
			if (!number(a + 7, &mb->stored))
				return AXM_ESYNTAX;
		} else if (prefix(a, "z=")) {
			if (streq(a + 2, "deflate"))
				mb->z = AXZ_DEFLATE;
			else if (streq(a + 2, "none"))
				mb->z = AXZ_NONE;
			else
				return AXM_ESYNTAX;
		} else if (prefix(a, "crc32=")) {
			if (!hex8(a + 6, &mb->crc))
				return AXM_ESYNTAX;
			mb->has_crc = 1;
		} else if (prefix(a, "sha256=")) {
			mb->sha256 = a + 7;
		} else if (prefix(a, "match=")) {
			mb->match = a + 6;
		} else if (prefix(a, "path=")) {
			mb->path = a + 5;
		} else if (prefix(a, "file=")) {
			mb->file = a + 5;
		}
		/* other attributes are for kbootset and the kernel */
	}
	if (mb->z == AXZ_NONE && mb->stored != mb->size)
		return AXM_ESYNTAX;
	return AXM_OK;
}

static int
member(struct ax_member *mb, int kind, char **tok, int ntok)
{
	int i = 1;

	mb->kind = kind;
	if (ntok < 3)
		return AXM_ESYNTAX;
	mb->name = tok[i++];
	if (kind == AXK_MODULE) {
		if (ntok < 4)
			return AXM_ESYNTAX;
		if (streq(tok[i], "root"))
			mb->cls = AXC_ROOT;
		else if (streq(tok[i], "boot"))
			mb->cls = AXC_BOOT;
		else if (streq(tok[i], "demand"))
			mb->cls = AXC_DEMAND;
		else
			return AXM_ESYNTAX;
		i++;
	}
	if (!number(tok[i++], &mb->size))
		return AXM_ESYNTAX;
	return attrs(mb, tok + i, ntok - i);
}

/* what the loader itself must find in a member it loads: a CRC, and either
 * a store extent (2048-aligned) or, on a CD, a file in the line directory */
static int
loadable(const struct ax_member *mb)
{
	if (!mb->has_crc)
		return 0;
	if (mb->file && *mb->file)
		return !mb->has_at;
	return mb->has_at && mb->at % 2048 == 0;
}

/* one record (the line is NUL-terminated, without its newline) */
static int
record(struct ax_manifest *m, char *line)
{
	char *tok[MAXTOK];
	char **sdst;
	ax_u32 *ndst;
	char *key;
	int n, rc, crit;

	crit = line[0] == '!';
	key = line + crit;

	/* records whose value is the whole rest of the line */
	sdst = 0;
	if (prefix(key, "root "))
		sdst = &m->root;
	else if (prefix(key, "swap "))
		sdst = &m->swap;
	else if (prefix(key, "boards "))
		sdst = &m->boards;
	else if (prefix(key, "cpu "))
		sdst = &m->cpu;
	else if (prefix(key, "created "))
		sdst = &m->created;
	if (sdst) {
		if (*sdst)
			return AXM_EDUP;
		*sdst = rest(key);
		return AXM_OK;
	}
	if (prefix(key, "param ")) {
		if (m->nparam == AXM_MAXPARAM)
			return AXM_EMANY;
		m->param[m->nparam++] = rest(key);
		return AXM_OK;
	}

	n = split(line, tok);
	if (n <= 0)
		return AXM_ESYNTAX;
	key = tok[0] + crit;
	if (streq(key, "generation") || streq(key, "loader-min")) {
		ndst = streq(key, "generation") ? &m->generation : &m->loader_min;
		if (n != 2 || !number(tok[1], ndst))
			return AXM_ESYNTAX;
		return AXM_OK;
	}
	if (streq(key, "line") || streq(key, "kabi") || streq(key, "rootfs")) {
		sdst = streq(key, "line") ? &m->line :
		       streq(key, "kabi") ? &m->kabi : &m->rootfs;
		if (n != 2)
			return AXM_ESYNTAX;
		if (*sdst)
			return AXM_EDUP;
		*sdst = tok[1];
		return AXM_OK;
	}
	if (streq(key, "arena")) {
		if (n != 3 || !number(tok[1], &m->arena_off) || !number(tok[2], &m->arena_cap))
			return AXM_ESYNTAX;
		if (m->has_arena)
			return AXM_EDUP;
		m->has_arena = 1;
		return AXM_OK;
	}
	if (streq(key, "kernel")) {
		if (m->has_kernel)
			return AXM_EDUP;
		if ((rc = member(&m->kernel, AXK_KERNEL, tok, n)) != AXM_OK)
			return rc;
		if (!loadable(&m->kernel))
			return AXM_EMISSING;
		m->has_kernel = 1;
		return AXM_OK;
	}
	if (streq(key, "module")) {
		struct ax_member *mb;

		if (m->nmod == AXM_MAXMOD)
			return AXM_EMANY;
		mb = &m->mod[m->nmod];
		if ((rc = member(mb, AXK_MODULE, tok, n)) != AXM_OK)
			return rc;
		if (mb->cls == AXC_ROOT && !loadable(mb))
			return AXM_EMISSING;
		if (mb->cls != AXC_ROOT && !mb->path)
			return AXM_EMISSING;
		m->nmod++;
		return AXM_OK;
	}
	if (streq(key, "ramdisk")) {
		if (m->has_ramdisk)
			return AXM_EDUP;
		if ((rc = member(&m->ramdisk, AXK_RAMDISK, tok, n)) != AXM_OK)
			return rc;
		if (!loadable(&m->ramdisk))
			return AXM_EMISSING;
		m->has_ramdisk = 1;
		return AXM_OK;
	}
	/* unknown: refuse a critical key, ignore any other */
	return crit ? AXM_ECRIT : AXM_OK;
}

int
ax_manifest_parse(const ax_u32 *crctab, char *buf, ax_u32 len,
		  struct ax_manifest *m, int *errline)
{
	ax_u32 i, start, endstart = 0, crc;
	int lineno = 0, found_end = 0, rc;
	char *zp;
	char *tok[MAXTOK];

	*errline = 0;
	for (zp = (char *)m, i = 0; i < sizeof(*m); i++)
		zp[i] = 0;

	/* pass 1: line shape and the end line; the CRC is taken here, before
	 * pass 2 changes any byte */
	for (start = 0, i = 0; i < len; i++) {
		unsigned char c = (unsigned char)buf[i];

		if (c == '\n') {
			lineno++;
			if (i - start > AXM_MAXLINE) {
				*errline = lineno;
				return AXM_ELONG;
			}
			if (found_end) {
				*errline = lineno;
				return AXM_EEND;
			}
			if (i - start >= 4 && buf[start] == 'e' && buf[start + 1] == 'n' &&
			    buf[start + 2] == 'd' && buf[start + 3] == ' ') {
				found_end = 1;
				endstart = start;
			}
			start = i + 1;
		} else if (c < 0x20 || c > 0x7E) {
			*errline = lineno + 1;
			return AXM_ELONG;
		}
	}
	if (start != len || !found_end) {
		*errline = lineno + 1;
		return AXM_EEND;
	}
	if (len < 5 || buf[0] != 'G' || buf[1] != 'M' || buf[2] != 'F' ||
	    buf[3] != '1' || buf[4] != '\n') {
		*errline = 1;
		return AXM_EHEAD;
	}
	crc = ax_crc32(crctab, (const ax_u8 *)buf, endstart);

	/* pass 2: the records between the head line and the end line */
	lineno = 1;
	for (start = 5; start < endstart; start = i + 1) {
		for (i = start; buf[i] != '\n'; i++)
			;
		buf[i] = 0;
		lineno++;
		if ((rc = record(m, buf + start)) != AXM_OK) {
			*errline = lineno;
			return rc;
		}
	}

	/* the end line */
	lineno++;
	for (i = endstart; buf[i] != '\n'; i++)
		;
	buf[i] = 0;
	if (split(buf + endstart, tok) != 2 || !prefix(tok[1], "crc32=") ||
	    !hex8(tok[1] + 6, &m->end_crc)) {
		*errline = lineno;
		return AXM_ESYNTAX;
	}
	if (m->end_crc != crc) {
		*errline = lineno;
		return AXM_ECRC;
	}
	if (!m->has_kernel || !m->line || m->generation == 0)
		return AXM_EMISSING;
	return AXM_OK;
}
