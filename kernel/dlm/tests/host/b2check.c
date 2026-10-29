/*
 * b2check.c -- test helper: apply a b2link image's self-relocation table at
 * BASE (as start.s does) and compare with the loader's relocator binding the
 * same relocatable link at BASE.  usage: b2check IN.o OUT.bin BASE
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

int
main(int argc, char **argv)
{
	long on, bn;
	unsigned char *obj, *bin, *mem;
	unsigned long base;
	ax_u32 span, cnt, i, off, v, end;
	struct ax_bootdata bd;
	struct ax_relerr er;

	if (argc != 4)
		return 2;
	base = strtoul(argv[3], 0, 0);
	obj = slurp(argv[1], &on);
	bin = slurp(argv[2], &bn);
	span = AX_GET32(bin + 8);
	end = span + 4 + AX_GET32(bin + span);
	if (end != (ax_u32)bn) {
		fprintf(stderr, "b2check: the table's length is not the file's rest\n");
		return 1;
	}
	/* a byte each: half the distance, or 0 and a 16-bit offset */
	for (i = span + 4, off = 0, cnt = 0; i < end; cnt++) {
		if (bin[i]) {
			off += 2 * bin[i++];
		} else {
			off = AX_GET16(bin + i + 1);
			i += 3;
		}
		v = AX_GET32(bin + off) + (ax_u32)base;
		AX_PUT32(bin + off, v);
	}
	if (ax_rel(obj, (ax_u32)on, (ax_u32)base, 1, &bd, &er) != AXR_OK)
		return 1;
	mem = calloc(1, span);
	memcpy(mem + (bd.tvaddr - base), obj + bd.toffset, bd.tsize);
	if (bd.rsize)
		memcpy(mem + (bd.rvaddr - base), obj + bd.roffset, bd.rsize);
	if (bd.dsize)
		memcpy(mem + (bd.dvaddr - base), obj + bd.doffset, bd.dsize);
	/* the header fields are b2link's own; compare everything after them */
	if (memcmp(mem + 20, bin + 20, span - 20) != 0) {
		for (i = 20; i < span && mem[i] == bin[i]; i++)
			;
		fprintf(stderr, "b2check: differs at 0x%lx\n", (unsigned long)i);
		return 1;
	}
	printf("b2check: %lu relocations applied at 0x%lx match the relocator\n",
	       (unsigned long)cnt, base);
	return 0;
}
