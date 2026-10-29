/*
 * axrel.c -- test helper: relocate a kernel file at VADDR with the loader's
 * relocator and write the bound text..data image (what lands in memory
 * from VADDR on, bss excluded).
 * usage: axrel KERNEL VADDR OUT [pcrel]
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rel.h"

int
main(int argc, char **argv)
{
	FILE *f;
	long n;
	unsigned char *img, *mem;
	unsigned long v;
	ax_u32 span;
	struct ax_bootdata bd;
	struct ax_relerr er;
	int rc;

	if (argc < 4)
		return 2;
	v = strtoul(argv[2], 0, 0);
	if (!(f = fopen(argv[1], "rb")))
		return 1;
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	img = malloc(n);
	if (!img || fread(img, 1, n, f) != (size_t)n)
		return 1;
	fclose(f);
	rc = ax_rel(img, (ax_u32)n, v, argc > 4, &bd, &er);
	if (rc != AXR_OK) {
		fprintf(stderr, "axrel: %s: error %d (rela section %lu record %lu type %lu sym %lu)\n",
			argv[1], rc, (unsigned long)er.rsect, (unsigned long)er.index,
			(unsigned long)er.type, (unsigned long)er.sym);
		return 1;
	}
	span = (bd.dsize ? bd.dvaddr + bd.dsize : bd.rsize ? bd.rvaddr + bd.rsize : bd.tvaddr + bd.tsize) - v;
	mem = calloc(1, span);
	memcpy(mem + (bd.tvaddr - v), img + bd.toffset, bd.tsize);
	if (bd.rsize)
		memcpy(mem + (bd.rvaddr - v), img + bd.roffset, bd.rsize);
	if (bd.dsize)
		memcpy(mem + (bd.dvaddr - v), img + bd.doffset, bd.dsize);
	if (!(f = fopen(argv[3], "wb")) || fwrite(mem, 1, span, f) != span)
		return 1;
	fclose(f);
	printf("axrel: %s: text %lu rodata %lu data %lu, end 0x%lx\n", argv[1],
	       (unsigned long)bd.tsize, (unsigned long)bd.rsize, (unsigned long)bd.dsize,
	       (unsigned long)bd.end);
	return 0;
}
