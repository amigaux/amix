/*
 * hunkcheck.c -- test helper: read an AmigaDOS load file written by
 * b2link -h, check its structure, apply HUNK_RELOC32 at BASE (as LoadSeg
 * does) and compare with the loader's relocator binding the same
 * relocatable link at BASE.  usage: hunkcheck IN.o FILE BASE
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rel.h"

static unsigned char *
slurp(const char *p, long *n)
{
	FILE *f = fopen(p, "rb");
	unsigned char *b;

	if (!f)
		exit(1);
	fseek(f, 0, SEEK_END);
	*n = ftell(f);
	fseek(f, 0, SEEK_SET);
	b = malloc(*n);
	if (!b || fread(b, 1, *n, f) != (size_t)*n)
		exit(1);
	fclose(f);
	return b;
}

#define BAD(msg) do { fprintf(stderr, "hunkcheck: %s\n", msg); return 1; } while (0)

int
main(int argc, char **argv)
{
	long on, hn;
	unsigned char *obj, *h, *code, *mem;
	unsigned long base;
	ax_u32 pos, alloc, ncode, nrel = 0, i, off, span;
	struct ax_bootdata bd;
	struct ax_relerr er;

	if (argc != 4)
		return 2;
	base = strtoul(argv[3], 0, 0);
	obj = slurp(argv[1], &on);
	h = slurp(argv[2], &hn);
	if (AX_GET32(h) != 0x3F3 || AX_GET32(h + 4) != 0 || AX_GET32(h + 8) != 1 ||
	    AX_GET32(h + 12) != 0 || AX_GET32(h + 16) != 0)
		BAD("not a one-hunk AmigaDOS load file");
	alloc = (AX_GET32(h + 20) & 0x3FFFFFFFUL) * 4;	/* bits 30/31: memory type */
	if (AX_GET32(h + 24) != 0x3E9)
		BAD("no HUNK_CODE");
	ncode = AX_GET32(h + 28) * 4;
	if (ncode > alloc || 32 + ncode > (ax_u32)hn)
		BAD("code larger than its hunk or the file");
	code = calloc(1, alloc);
	memcpy(code, h + 32, ncode);
	pos = 32 + ncode;
	if (AX_GET32(h + pos) == 0x3EC) {
		nrel = AX_GET32(h + pos + 4);
		if (AX_GET32(h + pos + 8) != 0)
			BAD("RELOC32 against another hunk");
		for (i = 0; i < nrel; i++) {
			off = AX_GET32(h + pos + 12 + 4 * i);
			if (off + 4 > ncode)
				BAD("RELOC32 offset outside the code");
			AX_PUT32(code + off, AX_GET32(code + off) + (ax_u32)base);
		}
		pos += 12 + 4 * nrel;
		if (AX_GET32(h + pos) != 0)
			BAD("RELOC32 block not terminated");
		pos += 4;
	}
	if (AX_GET32(h + pos) != 0x3F2 || pos + 4 != (ax_u32)hn)
		BAD("no HUNK_END at the end");
	span = AX_GET32(code + 8);
	if (AX_GET32(code + 4) != 0x41584232UL || AX_GET32(code + span) != 0)
		BAD("header or empty self-relocation table missing");
	if (span + 4 + AX_GET32(code + 12) > alloc)
		BAD("the hunk allocation does not cover bss");
	if (ax_rel(obj, (ax_u32)on, (ax_u32)base, 1, &bd, &er) != AXR_OK)
		BAD("relocator refused the object");
	mem = calloc(1, span);
	memcpy(mem + (bd.tvaddr - base), obj + bd.toffset, bd.tsize);
	if (bd.rsize)
		memcpy(mem + (bd.rvaddr - base), obj + bd.roffset, bd.rsize);
	if (bd.dsize)
		memcpy(mem + (bd.dvaddr - base), obj + bd.doffset, bd.dsize);
	if (memcmp(mem + 20, code + 20, span - 20) != 0)
		BAD("relocated code differs from the relocator's binding");
	printf("hunkcheck: %lu RELOC32 entries applied at 0x%lx match the relocator\n",
	       (unsigned long)nrel, base);
	return 0;
}
