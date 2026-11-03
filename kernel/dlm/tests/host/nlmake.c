/*
 * nlmake.c -- test helper: the namelist kbootset writes (kbootset/knl.c),
 * from a kernel or a unix.sym, at a bind address of the caller's choice.
 * usage: nlmake KERNEL BIND OUT | nlmake -s SYMFILE BIND OUT
 * Prints the layout: "text <vaddr> <size>", rodata, data, bss.
 * With NLMAKE_KMEM set, crash_sync's word is read from that file at the
 * symbol's address, as kbootset reads /dev/kmem (KBOOTSET_KMEM), and a
 * missing word leaves crash_sync out, as kbootset namelist does.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "knl.h"

static ax_u8 *
slurp(const char *p, ax_u32 *n)
{
	FILE *f = fopen(p, "rb");
	ax_u8 *b;
	long l;

	if (!f)
		return 0;
	fseek(f, 0, SEEK_END);
	l = ftell(f);
	fseek(f, 0, SEEK_SET);
	if ((b = malloc(l ? l : 1)) == 0 || fread(b, 1, l, f) != (size_t)l)
		exit(1);
	fclose(f);
	*n = (ax_u32)l;
	return b;
}

static int
kmem(void *ctx, ax_u32 addr, ax_u8 *buf, ax_u32 n)
{
	FILE *f = fopen((const char *)ctx, "rb");
	int ok;

	if (!f)
		return -1;
	ok = fseek(f, (long)addr, SEEK_SET) == 0 && fread(buf, 1, n, f) == n;
	fclose(f);
	return ok ? 0 : -1;
}

int
main(int argc, char **argv)
{
	static const char *const what[] = { "text", "rodata", "data", "bss" };
	struct kb_layout lay;
	struct kb_nlx x;
	char *km = getenv("NLMAKE_KMEM");
	ax_u8 *in, *out;
	ax_u32 n, olen;
	int s = argc == 5 && !strcmp(argv[1], "-s"), k;
	char why[120];
	FILE *f;

	if (argc != 4 + s) {
		fprintf(stderr, "usage: nlmake KERNEL BIND OUT | nlmake -s SYMFILE BIND OUT\n");
		return 2;
	}
	if (km && !*km)
		km = 0;
	memset(&x, 0, sizeof(x));
	x.mem = kmem;
	x.ctx = km;
	if ((in = slurp(argv[1 + s], &n)) == 0) {
		perror(argv[1 + s]);
		return 1;
	}
	if (kb_namelist(s ? 0 : in, s ? 0 : n, s ? in : 0, s ? n : 0,
			(ax_u32)strtoul(argv[2 + s], 0, 0), km ? &x : 0, &lay, &out, &olen, why)) {
		printf("nlmake: %s\n", why);
		return 3;
	}
	if ((f = fopen(argv[3 + s], "wb")) == 0 || fwrite(out, 1, olen, f) != olen || fclose(f))
		return 1;
	for (k = 0; k < 4; k++)
		printf("%s 0x%08lx %lu\n", what[k], (unsigned long)lay.vaddr[k], (unsigned long)lay.size[k]);
	return 0;
}
