/*
 * sparsehole.c -- a whole-page write into a hole in the middle of a file, and what the rest of the new block reads.
 *
 * ufs allocates a whole block for a write into a hole.  For a block among a file's first 12 (the direct blocks: the
 * first 96 KiB with 8 KiB blocks), a page-aligned write of whole pages (the pagecreate case) makes ufs_bmap allocate
 * the block without reading or zeroing it, and only the pages written are created in the cache; the block's other
 * pages are later read from the disk block, which still holds whatever was there before.  For a block mapped through
 * an indirect block, ufs_bmap reads the new block in (zeroed) unless the write reaches its last page, so the same
 * write there is the control and should come out clean.  The test:
 *
 *   1. writes a filler file of MB megabytes of 0x5a and removes it, so free blocks hold 0x5a;
 *   2. makes NF files of 41 blocks of 8 KiB: 0x11 in blocks 0, 12 and 40, the rest holes, so every hole is in the
 *      middle of its file; blocks 1-11 are direct, 13-39 indirect;
 *   3. writes 2 KiB of 0x22 into blocks 1, 3, 5, 7, 9 and 11 (direct) and 15, 17, 19, 21, 23 and 25 (indirect) of
 *      each file, at 2 KiB into the block (the default) or, with WHERE "last", at 6 KiB: the block's last page;
 *   4. writes and reads back MB megabytes of another file and removes it, to push the files' pages out of the cache;
 *   5. reads each written block back: zeros, then the 2 KiB of 0x22, then zeros.
 *
 * A page that should be zero and is not is counted, as direct or indirect, with how many hold the filler's 0x5a.  The
 * direct case reports the exposure; a direct count of 0 with no 0x5a anywhere can also mean the new blocks never
 * landed on the filler's, so the 0x5a count is printed beside it.  With "last" the write reaches the block's last
 * page, so ufs_bmap skips the read for indirect blocks too and both kinds are expected wrong.  With "eof" each file
 * instead gets its 2 KiB written 2 KiB past its end into a new block, once a direct one (block 0 of an empty file)
 * and once an indirect one (block 15, after 8 KiB at block 14), then 8 KiB at block 40, so the rest of both blocks
 * lies inside the file and must read zero (a regression case: rwip's own zeroing of a gap past the end covers it).
 * With "keep" the 2 KiB goes at the start of a new block and reaches the end of the file (block 1 after 8 KiB at
 * block 0, block 15 after 8 KiB at block 14): the one write shorter than a window that still allocates alloc-only,
 * whose block's rest must read zero once the file is extended past it.  Exit 1 when a direct or an indirect page is
 * wrong.  It assumes 8 KiB blocks (the 1.1 filesystems).
 *
 * sparsehole DIR [NF [MB [WHERE]]]
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

#define BLK 8192L
#define PG 2048

static char buf[8192];
static int blocks[] = { 1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25 };	/* the first six direct, the rest indirect */

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
	long nf = ac > 2 ? atol(av[2]) : 16, mb = ac > 3 ? atol(av[3]) : 24, bad[2], stale[2], n[2], page, off;
	int keep = ac > 4 && strcmp(av[4], "keep") == 0;
	int eof = keep || (ac > 4 && strcmp(av[4], "eof") == 0);
	int wp = ac > 4 && strcmp(av[4], "last") == 0 ? 3 : keep ? 0 : 1;	/* the page written in each block */
	static int eofblocks[] = { 0, 15 }, keepblocks[] = { 1, 15 };
	int fd, i, j, k, want, ind, shown = 0;

	sprintf(g, "%s/sh.fill", dir);
	sprintf(h, "%s/sh.evict", dir);
	bad[0] = bad[1] = stale[0] = stale[1] = n[0] = n[1] = 0;
	if (churn(g, 0x5a, mb, 0) < 0) {
		perror("filler");
		return 2;
	}
	for (i = 0; i < nf; i++) {
		sprintf(f, "%s/sh.%d", dir, i);
		if (keep) {
			if ((fd = open(f, O_RDWR | O_CREAT | O_TRUNC, 0600)) < 0 || wr(fd, 0L, 0x11, BLK) < 0
			    || wr(fd, BLK, 0x22, 2048L) < 0 || wr(fd, 14 * BLK, 0x11, BLK) < 0 || wr(fd, 15 * BLK, 0x22, 2048L) < 0
			    || wr(fd, 40 * BLK, 0x11, BLK) < 0) {
				perror(f);
				return 2;
			}
			fsync(fd);
			close(fd);
			continue;
		}
		if (eof) {
			if ((fd = open(f, O_RDWR | O_CREAT | O_TRUNC, 0600)) < 0 || wr(fd, 2048L, 0x22, 2048L) < 0
			    || wr(fd, 14 * BLK, 0x11, BLK) < 0 || wr(fd, 15 * BLK + 2048, 0x22, 2048L) < 0
			    || wr(fd, 40 * BLK, 0x11, BLK) < 0) {
				perror(f);
				return 2;
			}
			fsync(fd);
			close(fd);
			continue;
		}
		if ((fd = open(f, O_RDWR | O_CREAT | O_TRUNC, 0600)) < 0 || wr(fd, 0L, 0x11, BLK) < 0
		    || wr(fd, 12 * BLK, 0x11, BLK) < 0 || wr(fd, 40 * BLK, 0x11, BLK) < 0) {
			perror(f);
			return 2;
		}
		for (k = 0; k < (int)(sizeof blocks / sizeof blocks[0]); k++)
			if (wr(fd, blocks[k] * BLK + wp * PG, 0x22, 2048L) < 0) {
				perror("hole write");
				return 2;
			}
		fsync(fd);
		close(fd);
	}
	sync();
	if (churn(h, 0x33, mb, 1) < 0) {
		perror("evict");
		return 2;
	}
	sync();
	for (i = 0; i < nf; i++) {
		sprintf(f, "%s/sh.%d", dir, i);
		if ((fd = open(f, O_RDONLY)) < 0) {
			perror(f);
			return 2;
		}
		for (k = 0; k < (eof ? 2 : (int)(sizeof blocks / sizeof blocks[0])); k++) {
			ind = (keep ? keepblocks[k] : eof ? eofblocks[k] : blocks[k]) > 11;
			off = (keep ? keepblocks[k] : eof ? eofblocks[k] : blocks[k]) * BLK;
			lseek(fd, off, SEEK_SET);
			if (read(fd, buf, (int)BLK) != (int)BLK) {
				perror("read");
				return 2;
			}
			for (page = 0; page < 4; page++) {
				want = page == wp ? 0x22 : 0;
				if (page != wp)
					n[ind]++;
				for (j = 0; j < PG; j++)
					if ((buf[page * PG + j] & 0xff) != want)
						break;
				if (j == PG)
					continue;
				bad[ind]++;
				if ((buf[page * PG + j] & 0xff) == 0x5a)
					stale[ind]++;
				if (shown++ < 20)
					printf("RES sparsehole BAD %s file %d block %ld page %ld (offset %ld): byte %d is 0x%02x, want 0x%02x\n",
					    ind ? "indirect" : "direct", i, off / BLK, page, off + page * PG, j,
					    buf[page * PG + j] & 0xff, want);
			}
		}
		close(fd);
		unlink(f);
	}
	printf("RES sparsehole: %s write at page %d: direct %ld of %ld pages wrong (%ld the filler's 0x5a); indirect %ld of %ld "
	    "wrong (%ld 0x5a); %ld files\n", keep ? "window-start-to-EOF" : eof ? "past-EOF" : "hole", wp, bad[0], n[0], stale[0], bad[1], n[1], stale[1], nf);
	return bad[0] || bad[1] ? 1 : 0;
}
