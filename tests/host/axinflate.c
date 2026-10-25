/*
 * axinflate.c -- test helper: inflate a raw deflate file with the loader's
 * decoder.  usage: axinflate IN OUT SIZE
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include "inflate.h"

static struct ax_inflate st;

int
main(int argc, char **argv)
{
	FILE *f;
	long n;
	unsigned long size;
	unsigned char *in, *out;
	ax_u32 got;
	int rc;

	if (argc != 4)
		return 2;
	size = strtoul(argv[3], 0, 0);
	if (!(f = fopen(argv[1], "rb")))
		return 1;
	fseek(f, 0, SEEK_END);
	n = ftell(f);
	fseek(f, 0, SEEK_SET);
	in = malloc(n);
	out = malloc(size);
	if (!in || !out || fread(in, 1, n, f) != (size_t)n)
		return 1;
	fclose(f);
	rc = ax_inflate(&st, out, size, &got, in, (ax_u32)n);
	if (rc != AXI_OK || got != size) {
		fprintf(stderr, "axinflate: rc %d, %lu of %lu bytes\n", rc, (unsigned long)got, size);
		return 1;
	}
	if (!(f = fopen(argv[2], "wb")) || fwrite(out, 1, size, f) != size)
		return 1;
	fclose(f);
	return 0;
}
