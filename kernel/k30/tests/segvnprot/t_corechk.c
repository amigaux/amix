/*
 * t_corechk.c -- corechk.h on the host, against cores laid out as elfcore writes vm30's: one PT_LOAD of 16 pages, page i
 * holding i + 1, pages 3 and 15 holes.  A whole core passes; one that ends before its last page (the trailing byte for a
 * run that ends denied never written) and one whose hole holds data fail.  With -DHEAD_RULE the check is the earlier
 * one (a hole may read anything not above 0, no length check), which passes the short core: red.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include "corechk.h"

#define BASE	0x10000000UL
#define DATA	4096UL

static void be32(unsigned char *b, unsigned long v) { b[0] = v >> 24; b[1] = v >> 16; b[2] = v >> 8; b[3] = v; }

/* a core of len bytes, the hole at page 3 holding hole3 */
static int mkcore(const char *path, unsigned long len, int hole3)
{
	unsigned char *b = calloc(1, DATA + 16 * CK_PG);
	int i, fd;

	b[0] = 0x7f; b[1] = 'E'; b[2] = 'L'; b[3] = 'F'; b[4] = 1; b[5] = 2;
	be32(b + 28, 52);
	b[44] = 0; b[45] = 1;
	be32(b + 52, 1);
	be32(b + 56, DATA);
	be32(b + 60, BASE);
	be32(b + 68, 16 * CK_PG);
	for (i = 0; i < 16; i++)
		b[DATA + i * CK_PG] = (i == 3 || i == 15) ? 0 : i + 1;
	b[DATA + 3 * CK_PG] = hole3;
	fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
	if (fd < 0 || write(fd, b, len) != (long)len)
		exit(2);
	free(b);
	return fd;
}

static int check(int fd, long size)
{
#ifdef HEAD_RULE
	int i, v, bad = 0;

	(void)size;
	for (i = 0; i < 16; i++) {
		int none = i == 3 || i == 15;

		v = coreat(fd, (char *)BASE + i * CK_PG);
		if (none ? v > 0 : v != i + 1)
			bad++;
	}
	return bad ? 4 : 0;
#else
	return corecheck(fd, size, (char *)BASE, 1);
#endif
}

int main(void)
{
	char path[] = "/tmp/t_corechk.XXXXXX";
	int fails = 0, r, fd = mkstemp(path);

	close(fd);
	fd = mkcore(path, DATA + 16 * CK_PG, 0);
	r = check(fd, DATA + 16 * CK_PG);
	printf("%s a whole core passes (%d)\n", r == 0 ? "PASS" : "FAIL", r);
	fails += r != 0;
	close(fd);
	fd = mkcore(path, DATA + 15 * CK_PG, 0);
	r = check(fd, DATA + 15 * CK_PG);
	printf("%s a core that ends before its last, denied page fails (%d)\n", r != 0 ? "PASS" : "FAIL", r);
	fails += r == 0;
	close(fd);
	fd = mkcore(path, DATA + 16 * CK_PG, 9);
	r = check(fd, DATA + 16 * CK_PG);
	printf("%s a hole that holds data fails (%d)\n", r != 0 ? "PASS" : "FAIL", r);
	fails += r == 0;
	close(fd);
	unlink(path);
	return fails != 0;
}
