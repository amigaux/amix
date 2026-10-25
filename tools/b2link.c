/*
 * b2link.c -- turn boot2's relocatable link (ld -r output) into the loaded
 * image: bound at address 0 with the loader's own relocator, followed by the
 * self-relocation table its start-up stub applies (loader/boot2/start.s).
 * (docs/plan/stage-1.md S1-11.)
 *
 * usage: b2link IN.o OUT.bin       boot2 behind boot1 (self-relocating)
 *        b2link -h [-c] IN.o OUT   amix-cdboot: an AmigaDOS load file (one
 *                                  code hunk with bss, HUNK_RELOC32 for the
 *                                  same fields, an empty self-relocation
 *                                  table) -- docs/spec/10-boot-loader.md §4.4;
 *                                  -c asks AmigaDOS for chip memory (to time
 *                                  code that runs from chip RAM, as boot2
 *                                  does behind boot1)
 *
 * Refuses: an image whose first bytes are not the start.s header; undefined
 * or unbound symbols; a file longer than 28672 bytes or an image plus bss
 * that does not fit the 28672-byte area boot1 loads boot2 into.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "rel.h"
#include "store.h"

static ax_u32 *offs;
static ax_u32 noffs, capoffs;
static int chip;		/* -c: the hunk in chip memory */

static void
note(void *ctx, ax_u32 off)
{
	(void)ctx;
	if (noffs == capoffs) {
		capoffs = capoffs ? 2 * capoffs : 256;
		offs = realloc(offs, capoffs * sizeof(*offs));
		if (!offs)
			exit(1);
	}
	offs[noffs++] = off;
}

static void
put(FILE *f, ax_u32 v)
{
	unsigned char b[4];

	AX_PUT32(b, v);
	fwrite(b, 1, 4, f);
}

/* AmigaDOS load file: HUNK_HEADER, one HUNK_CODE (image + an empty
 * self-relocation table; the hunk's allocation includes bss), HUNK_RELOC32
 * for every 0-based address field, HUNK_END */
static int
write_hunk(const char *path, unsigned char *img, ax_u32 span, ax_u32 bss)
{
	FILE *f = fopen(path, "wb");
	ax_u32 code = (span + 4) / 4, alloc = (span + 4 + bss + 3) / 4, i;

	if (!f) {
		perror(path);
		return 1;
	}
	put(f, 0x3F3);				/* HUNK_HEADER */
	put(f, 0);				/* no resident library names */
	put(f, 1);				/* one hunk */
	put(f, 0);
	put(f, 0);
	put(f, alloc | (chip ? 0x40000000UL : 0));	/* bit 30: MEMF_CHIP */
	put(f, 0x3E9);				/* HUNK_CODE */
	put(f, code);
	fwrite(img, 1, span, f);
	put(f, 0);				/* the empty self-relocation table */
	if (noffs) {
		put(f, 0x3EC);			/* HUNK_RELOC32 */
		put(f, noffs);
		put(f, 0);			/* against hunk 0 */
		for (i = 0; i < noffs; i++)
			put(f, offs[i]);
		put(f, 0);
	}
	put(f, 0x3F2);				/* HUNK_END */
	if (fclose(f) != 0) {
		perror(path);
		return 1;
	}
	printf("b2link: AmigaDOS load file, code %lu bytes, %lu relocations, bss %lu\n",
	       (unsigned long)(code * 4), (unsigned long)noffs, (unsigned long)bss);
	return 0;
}

static int
cmp(const void *a, const void *b)
{
	ax_u32 x = *(const ax_u32 *)a, y = *(const ax_u32 *)b;
	return x < y ? -1 : x > y;
}

int
main(int argc, char **argv)
{
	FILE *f;
	long n;
	unsigned char *img, *out;
	ax_u32 span, bss, total, i;
	struct ax_bootdata bd;
	struct ax_relerr er;
	int rc, hunk = 0;

	if (argc >= 4 && !strcmp(argv[1], "-h")) {
		hunk = 1;
		argv++, argc--;
		if (argc == 4 && !strcmp(argv[1], "-c")) {
			chip = 1;
			argv++, argc--;
		}
	}
	if (argc != 3) {
		fprintf(stderr, "usage: b2link [-h [-c]] IN.o OUT\n");
		return 2;
	}
	if (!(f = fopen(argv[1], "rb"))) {
		perror(argv[1]);
		return 1;
	}
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	img = malloc(n);
	if (!img || fread(img, 1, n, f) != (size_t)n)
		return 1;
	fclose(f);
	rc = ax_rel_ex(img, (ax_u32)n, 0, 1, &bd, &er, note, 0);
	if (rc != AXR_OK) {
		fprintf(stderr, "b2link: %s: relocation error %d (rela section %lu record %lu type %lu sym %lu)\n",
			argv[1], rc, (unsigned long)er.rsect, (unsigned long)er.index,
			(unsigned long)er.type, (unsigned long)er.sym);
		return 1;
	}
	span = bd.dsize ? bd.dvaddr + bd.dsize : bd.rsize ? bd.rvaddr + bd.rsize : bd.tsize;
	span = (span + 3) & ~3UL;
	bss = bd.end > span ? bd.end - span : 0;
	total = span + 4 + 4 * noffs;
	out = calloc(1, total);
	memcpy(out + bd.tvaddr, img + bd.toffset, bd.tsize);
	if (bd.rsize)
		memcpy(out + bd.rvaddr, img + bd.roffset, bd.rsize);
	if (bd.dsize)
		memcpy(out + bd.dvaddr, img + bd.doffset, bd.dsize);
	if (AX_GET32(out + 4) != 0x41584232UL) {
		fprintf(stderr, "b2link: %s: the image does not start with start.s\n", argv[1]);
		return 1;
	}
	qsort(offs, noffs, sizeof(*offs), cmp);
	AX_PUT32(out + 8, span);
	AX_PUT32(out + 12, bss);
	AX_PUT32(out + 16, span);
	for (i = 0; i < noffs; i++)
		if (offs[i] + 4 > span || offs[i] < 20) {
			fprintf(stderr, "b2link: relocated field at 0x%lx is outside the image\n",
				(unsigned long)offs[i]);
			return 1;
		}
	if (hunk)
		return write_hunk(argv[2], out, span, bss);
	AX_PUT32(out + span, noffs);
	for (i = 0; i < noffs; i++)
		AX_PUT32(out + span + 4 + 4 * i, offs[i]);
	if (total > AX_BOOT2_MAX || span + bss > AX_BOOT2_MAX) {
		fprintf(stderr, "b2link: SIZE GATE: file %lu, image + bss %lu; the limit is %lu\n",
			(unsigned long)total, (unsigned long)(span + bss), (unsigned long)AX_BOOT2_MAX);
		return 1;
	}
	if (!(f = fopen(argv[2], "wb")) || fwrite(out, 1, total, f) != total || fclose(f) != 0) {
		perror(argv[2]);
		return 1;
	}
	printf("b2link: boot2 image %lu + table %lu = %lu bytes, bss %lu (limit %lu)\n",
	       (unsigned long)span, (unsigned long)(4 + 4 * noffs), (unsigned long)total,
	       (unsigned long)bss, (unsigned long)AX_BOOT2_MAX);
	return 0;
}
