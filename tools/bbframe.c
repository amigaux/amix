/*
 * bbframe.c -- frame boot1's code as an AmigaDOS bootblock, and the 1 KB
 * size gate (docs/plan/stage-1.md S1-05).
 *
 *   bbframe <code.bin> <bootblock.img>   frame; fails if the code exceeds
 *                                        1008 bytes
 *   bbframe -c <bootblock.img>           check an image's framing and checksum
 *
 * Layout of the 1024-byte image: "DOS\0" at 0, the bootblock checksum at 4,
 * 0x00000370 at 8, code from 12 (where the strap enters), zero padding, and
 * the A3000 SuperKickstart trailer 0x03010401 in the last longword.  The
 * checksum makes the end-around-carry sum of all 256 longwords 0xFFFFFFFF.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>

#define BB_SIZE   1024
#define BB_CODE   12
#define BB_MAX    (BB_SIZE - BB_CODE - 4)

static unsigned long
get32(const unsigned char *p)
{
	return ((unsigned long)p[0] << 24) | ((unsigned long)p[1] << 16) |
	       ((unsigned long)p[2] << 8) | p[3];
}

static void
put32(unsigned char *p, unsigned long v)
{
	p[0] = (unsigned char)(v >> 24);
	p[1] = (unsigned char)(v >> 16);
	p[2] = (unsigned char)(v >> 8);
	p[3] = (unsigned char)v;
}

/* end-around-carry sum of the 256 longwords */
static unsigned long
bbsum(const unsigned char *bb)
{
	unsigned long sum = 0, v;
	int i;

	for (i = 0; i < BB_SIZE; i += 4) {
		v = get32(bb + i);
		sum = (sum + v) & 0xFFFFFFFFUL;
		if (sum < v)
			sum = (sum + 1) & 0xFFFFFFFFUL;
	}
	return sum;
}

static int
check(const char *path)
{
	unsigned char bb[BB_SIZE + 1];
	FILE *f = fopen(path, "rb");
	size_t n;

	if (!f) {
		perror(path);
		return 1;
	}
	n = fread(bb, 1, sizeof(bb), f);
	fclose(f);
	if (n != BB_SIZE) {
		fprintf(stderr, "bbframe: %s is %lu bytes, not %d\n", path, (unsigned long)n, BB_SIZE);
		return 1;
	}
	if (memcmp(bb, "DOS\0", 4) != 0 || get32(bb + 8) != 0x370UL ||
	    get32(bb + BB_SIZE - 4) != 0x03010401UL) {
		fprintf(stderr, "bbframe: %s: framing longwords wrong\n", path);
		return 1;
	}
	if (bbsum(bb) != 0xFFFFFFFFUL) {
		fprintf(stderr, "bbframe: %s: bootblock checksum wrong\n", path);
		return 1;
	}
	printf("bbframe: %s: framing and checksum ok\n", path);
	return 0;
}

int
main(int argc, char **argv)
{
	unsigned char bb[BB_SIZE], code[BB_SIZE + 1];
	FILE *f;
	size_t n;

	if (argc == 3 && strcmp(argv[1], "-c") == 0)
		return check(argv[2]);
	if (argc != 3) {
		fprintf(stderr, "usage: bbframe <code.bin> <bootblock.img> | bbframe -c <bootblock.img>\n");
		return 2;
	}
	if (!(f = fopen(argv[1], "rb"))) {
		perror(argv[1]);
		return 1;
	}
	n = fread(code, 1, sizeof(code), f);
	fclose(f);
	if (n > BB_MAX) {
		fprintf(stderr, "bbframe: SIZE GATE: boot1 code is %lu bytes, the limit is %d\n",
			(unsigned long)n, BB_MAX);
		return 1;
	}
	memset(bb, 0, sizeof(bb));
	memcpy(bb, "DOS\0", 4);
	put32(bb + 8, 0x370UL);
	memcpy(bb + BB_CODE, code, n);
	put32(bb + BB_SIZE - 4, 0x03010401UL);
	put32(bb + 4, ~bbsum(bb) & 0xFFFFFFFFUL);
	if (!(f = fopen(argv[2], "wb")) || fwrite(bb, 1, BB_SIZE, f) != BB_SIZE) {
		perror(argv[2]);
		return 1;
	}
	fclose(f);
	printf("bbframe: boot1 code %lu of %d bytes (%lu free)\n",
	       (unsigned long)n, BB_MAX, (unsigned long)(BB_MAX - n));
	return 0;
}
