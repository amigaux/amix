/*
 * sparsehole.c -- a whole-page write into a hole in the middle of a file, and what the rest of the new block reads.
 *
 * ufs allocates a whole block for a write into a hole.  When the write is page-aligned and covers whole pages (the
 * pagecreate case), ufs_bmap allocates the block without reading or zeroing it, and only the pages written are
 * created in the cache; the block's other pages are then read from the disk block, which still holds whatever was
 * there before.  This test makes that visible:
 *
 *   1. writes a filler file of MB megabytes of 0x5a and removes it, so free blocks hold 0x5a;
 *   2. makes a file of NSEG 64 KiB segments: 8 KiB of 0x11 at each segment's start, the rest a hole, and one more
 *      8 KiB after the last segment, so every hole is in the middle of the file;
 *   3. writes 2 KiB of 0x22 at 10 KiB into each segment (8 KiB window offset 2048, page-aligned, whole page);
 *   4. writes and reads back MB megabytes of another file and removes it, to push the file's pages out of the cache;
 *   5. reads 8 KiB at 8 KiB into each segment and checks it: zeros, then the 2 KiB of 0x22, then zeros.
 *
 * A page that should be zero and is not is reported with its first byte (0x5a: the filler's old data).
 *
 * sparsehole DIR [NSEG [MB]]
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

#define SEG 65536L
#define PG 2048

static char buf[8192];

static int wr(int fd, long off, int c, long n)
{
	memset(buf, c, sizeof buf);
	if (lseek(fd, off, SEEK_SET) < 0)
		return -1;
	while (n > 0) {
		long k = n > (long)sizeof buf ? (long)sizeof buf : n;
		if (write(fd, buf, k) != k)
			return -1;
		n -= k;
	}
	return 0;
}

static int churn(char *name, int c, long mb, int readback)
{
	int fd = open(name, O_RDWR | O_CREAT | O_TRUNC, 0600);
	long i;

	if (fd < 0 || wr(fd, 0L, c, mb * 1024L * 1024L) < 0)
		return -1;
	fsync(fd);
	if (readback) {
		lseek(fd, 0L, SEEK_SET);
		for (i = 0; i < mb * 128L; i++)
			if (read(fd, buf, sizeof buf) != (int)sizeof buf)
				break;
	}
	close(fd);
	return unlink(name);
}

int main(int ac, char **av)
{
	char *dir = ac > 1 ? av[1] : "/tmp", f[256], g[256], h[256];
	long nseg = ac > 2 ? atol(av[2]) : 64, mb = ac > 3 ? atol(av[3]) : 24, i, bad = 0, stale = 0, page;
	int fd, j, want;

	sprintf(f, "%s/sh.dat", dir);
	sprintf(g, "%s/sh.fill", dir);
	sprintf(h, "%s/sh.evict", dir);
	unlink(f);
	if (churn(g, 0x5a, mb, 0) < 0) {
		perror("filler");
		return 2;
	}
	if ((fd = open(f, O_RDWR | O_CREAT | O_TRUNC, 0600)) < 0) {
		perror(f);
		return 2;
	}
	for (i = 0; i <= nseg; i++)
		if (wr(fd, i * SEG, 0x11, 8192L) < 0) {
			perror("segment start");
			return 2;
		}
	for (i = 0; i < nseg; i++)
		if (wr(fd, i * SEG + 8192 + 2048, 0x22, 2048L) < 0) {
			perror("hole write");
			return 2;
		}
	fsync(fd);
	close(fd);
	sync();
	if (churn(h, 0x33, mb, 1) < 0) {
		perror("evict");
		return 2;
	}
	sync();
	if ((fd = open(f, O_RDONLY)) < 0) {
		perror(f);
		return 2;
	}
	for (i = 0; i < nseg; i++) {
		lseek(fd, i * SEG + 8192, SEEK_SET);
		if (read(fd, buf, 8192) != 8192) {
			perror("read");
			return 2;
		}
		for (page = 0; page < 4; page++) {
			want = page == 1 ? 0x22 : 0;
			for (j = 0; j < PG; j++)
				if ((buf[page * PG + j] & 0xff) != want)
					break;
			if (j < PG) {
				bad++;
				if ((buf[page * PG + j] & 0xff) == 0x5a)
					stale++;
				if (bad <= 20)
					printf("RES sparsehole BAD segment %ld page %ld (offset %ld): byte %d is 0x%02x, want 0x%02x\n", i,
					    page, i * SEG + 8192 + page * PG, j, buf[page * PG + j] & 0xff, want);
			}
		}
	}
	close(fd);
	unlink(f);
	printf("RES sparsehole: %ld segments, %ld pages checked, %ld wrong, %ld of them the filler's 0x5a\n", nseg, nseg * 4,
	    bad, stale);
	return bad ? 1 : 0;
}
