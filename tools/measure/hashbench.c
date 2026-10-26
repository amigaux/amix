/*
 * hashbench.c -- the hashing rate on the box, apart from any I/O: the
 * loader's own SHA-256 and CRC-32 (loader/common) and a memcpy over a
 * fixed buffer in memory, timed with times(2).  Built twice from this one
 * source, with GCC 14 as the box kbootset is (make box-hashbench) and
 * with gcc-cross-amix (GCC 2.7.2.3) as the loader is, so that the two
 * compilers' code can be compared on the same machine.  M-GEN2 found
 * kbootset hashing at about a third of axtime's rate
 * (docs/measurements/2026-10-26-m-gen2.md); this separates the compiler
 * from the I/O.
 *
 * usage: hashbench [KIB [ROUNDS]]   default 1024 KiB, 2 rounds
 *
 * Prints, per step, the bytes, the user and real clock ticks, and KiB/s
 * from user time; then the buffer's SHA-256 and CRC-32, which the host
 * build must print identically.  Return code 0, or 1 when memory is
 * short.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/times.h>
#include <unistd.h>
#include "crc32.h"
#include "sha256.h"

static long hz;

static void
report(const char *what, unsigned long bytes, struct tms *a, clock_t ra,
       struct tms *b, clock_t rb)
{
	long user = (long)(b->tms_utime - a->tms_utime);
	long real = (long)(rb - ra);

	printf("hashbench: %-7s %lu bytes, user %ld, real %ld ticks of 1/%ld s",
	       what, bytes, user, real, hz);
	if (user > 0)
		printf(", %lu KiB/s", (unsigned long)(bytes / 1024 * hz / user));
	printf("\n");
}

int
main(int argc, char **argv)
{
	unsigned long kib = argc > 1 ? strtoul(argv[1], 0, 10) : 1024;
	int rounds = argc > 2 ? atoi(argv[2]) : 2;
	unsigned long n = kib * 1024, i, total = n * (unsigned long)rounds;
	ax_u8 *buf, *dst, out[32];
	ax_u32 *table, crc = 0;
	struct ax_sha256 s;
	struct tms t0, t1;
	clock_t r0, r1;
	int k;

	hz = sysconf(_SC_CLK_TCK);
	if (hz <= 0)
		hz = 100;
	buf = malloc(n);
	dst = malloc(n);
	table = malloc(256 * sizeof(ax_u32));
	if (!buf || !dst || !table || rounds < 1) {
		fprintf(stderr, "hashbench: not enough memory for %lu KiB\n", kib);
		return 1;
	}
	for (i = 0; i < n; i++)		/* a fixed pattern the host repeats */
		buf[i] = (ax_u8)((i * 2654435761UL) >> 24);
	ax_crc32_init(table);

	r0 = times(&t0);
	ax_sha256_init(&s);
	for (k = 0; k < rounds; k++)
		ax_sha256_update(&s, buf, n);
	ax_sha256_final(&s, out);
	r1 = times(&t1);
	report("sha256", total, &t0, r0, &t1, r1);

	r0 = times(&t0);
	for (k = 0; k < rounds; k++)
		crc = ax_crc32_update(table, crc, buf, n);
	r1 = times(&t1);
	report("crc32", total, &t0, r0, &t1, r1);

	r0 = times(&t0);
	for (k = 0; k < rounds; k++)
		memcpy(dst, buf, n);
	r1 = times(&t1);
	report("memcpy", total, &t0, r0, &t1, r1);

	printf("hashbench: sha256 ");
	for (i = 0; i < 32; i++)
		printf("%02x", out[i]);
	printf(" crc32 %08lx over %d x %lu KiB\n", (unsigned long)crc, rounds, kib);
	if (memcmp(dst, buf, n) != 0) {	/* also keeps the copy from being optimised away */
		printf("hashbench: memcpy copied wrongly\n");
		return 1;
	}
	return 0;
}
