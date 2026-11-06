/*
 * sparsehole.c -- a whole-page write into a hole in the middle of a file, and what the rest of the new block reads.
 *
 * ufs allocates a whole block for a write into a hole.  For a block among a file's first 12 (the direct blocks: the
 * first 96 KiB with 8 KiB blocks), a page-aligned write of whole pages (the pagecreate case) makes the stock ufs_bmap
 * allocate the block without reading or zeroing it, and only the pages written are created in the cache; the block's
 * other pages are later read from the disk block, which still holds whatever was there before.  For a block mapped
 * through an indirect block, ufs_bmap reads the new block in (zeroed) unless the write reaches its last page, so the
 * same write there is the control and should come out clean.  The test:
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
 * page, so ufs_bmap skips the read for indirect blocks too and both kinds are expected wrong.
 *
 * Regression cases, where a kernel with the fix and one without should both read right:
 *   "eof"      each file gets its 2 KiB written 2 KiB past its end into a new block, once a direct one (block 0 of an
 *              empty file) and once an indirect one (block 15, after 8 KiB at block 14), then 8 KiB at block 40, so
 *              the rest of both blocks lies inside the file and must read zero (rwip's own zeroing of the gap past the
 *              end covers it).
 *   "keep"     the 2 KiB goes at the start of a new block and reaches the end of the file (block 1 after 8 KiB at
 *              block 0, block 15 after 8 KiB at block 14), then the file is extended past it, so the block's rest
 *              must read zero.  The stock ufs allocates only the fragments such a write covers and reads the block
 *              when it grows; with the hole fix the new block is read (zero-filled) at once.
 *   "rewrite"  no holes: the files are written whole with 0x11 and pushed out of the cache, then 2 KiB of 0x22 is
 *              written at 2 KiB into blocks 1-25 above, each already allocated, while the block's other pages are not
 *              in the cache.  The block is not new, so the hole fix leaves the write alloc-only (pagecreate) as the
 *              stock kernel does: the written page is created unread and the others are read from the file's own
 *              block.  The blocks are read back twice, at once (the page cache's view) and again after the cache is
 *              pushed out (the disk's): 0x11, then the 2 KiB of 0x22, then 0x11.  A kernel whose rwip gives
 *              segmap_pagecreate the window's base instead of the write's address creates the block's first page
 *              instead of the written one, so its first read finds page 0 wrong.
 *
 * Exit 1 when a direct or an indirect page is wrong.  It assumes 8 KiB blocks (the 1.1 filesystems).
 *
 * sparsehole DIR [NF [MB [WHERE]]]     WHERE: mid (the default), last, eof, keep, rewrite
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
#define NFB 41L		/* blocks in each file */

static char buf[8192];
static int blocks[] = { 1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25 };	/* the first six direct, the rest indirect */
static int eofblocks[] = { 0, 15 }, keepblocks[] = { 1, 15 };
static long bad[2], stale[2], n[2];
static int shown;

static int wr(int fd, long off, int c, long len)
{
	memset(buf, c, sizeof buf);
	if (lseek(fd, off, SEEK_SET) < 0)
		return -1;
	while (len > 0) {
		long k = len > (long)sizeof buf ? (long)sizeof buf : len;
		if (write(fd, buf, k) != k)
			return -1;
		len -= k;
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

/* read back the NB blocks BL of each file: page WP holds 0x22, the others OTHER; count what is not */
static int readback(char *dir, long nf, int *bl, int nb, int wp, int other, char *pass)
{
	char f[256];
	long page, off;
	int fd, i, j, k, want, ind;

	for (i = 0; i < nf; i++) {
		sprintf(f, "%s/sh.%d", dir, i);
		if ((fd = open(f, O_RDONLY)) < 0) {
			perror(f);
			return -1;
		}
		for (k = 0; k < nb; k++) {
			ind = bl[k] > 11;
			off = bl[k] * BLK;
			lseek(fd, off, SEEK_SET);
			if (read(fd, buf, (int)BLK) != (int)BLK) {
				perror("read");
				return -1;
			}
			for (page = 0; page < 4; page++) {
				want = page == wp ? 0x22 : other;
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
					printf("RES sparsehole BAD%s %s file %d block %ld page %ld (offset %ld): byte %d is 0x%02x, want 0x%02x\n",
					    pass, ind ? "indirect" : "direct", i, off / BLK, page, off + page * PG, j,
					    buf[page * PG + j] & 0xff, want);
			}
		}
		close(fd);
	}
	return 0;
}

int main(int ac, char **av)
{
	char *dir = ac > 1 ? av[1] : "/tmp", f[256], g[256], h[256];
	long nf = ac > 2 ? atol(av[2]) : 16, mb = ac > 3 ? atol(av[3]) : 24, cached[2];
	char *where = ac > 4 ? av[4] : "mid";
	int keep = strcmp(where, "keep") == 0, rewrite = strcmp(where, "rewrite") == 0;
	int eof = keep || strcmp(where, "eof") == 0;
	int wp = strcmp(where, "last") == 0 ? 3 : keep ? 0 : 1;	/* the page written in each block */
	int *bl = keep ? keepblocks : eof ? eofblocks : blocks, nb = eof ? 2 : (int)(sizeof blocks / sizeof blocks[0]);
	int other = rewrite ? 0x11 : 0;
	int fd, i, k;

	if (!rewrite && !eof && strcmp(where, "mid") != 0 && strcmp(where, "last") != 0) {
		fprintf(stderr, "sparsehole: WHERE is mid, last, eof, keep or rewrite\n");
		return 2;
	}
	sprintf(g, "%s/sh.fill", dir);
	sprintf(h, "%s/sh.evict", dir);
	bad[0] = bad[1] = stale[0] = stale[1] = n[0] = n[1] = 0;
	if (churn(g, 0x5a, mb, 0) < 0) {
		perror("filler");
		return 2;
	}
	for (i = 0; i < nf; i++) {
		sprintf(f, "%s/sh.%d", dir, i);
		if ((fd = open(f, O_RDWR | O_CREAT | O_TRUNC, 0600)) < 0) {
			perror(f);
			return 2;
		}
		if (rewrite ? wr(fd, 0L, 0x11, NFB * BLK) < 0
		    : keep ? wr(fd, 0L, 0x11, BLK) < 0 || wr(fd, BLK, 0x22, 2048L) < 0 || wr(fd, 14 * BLK, 0x11, BLK) < 0
			|| wr(fd, 15 * BLK, 0x22, 2048L) < 0 || wr(fd, 40 * BLK, 0x11, BLK) < 0
		    : eof ? wr(fd, 2048L, 0x22, 2048L) < 0 || wr(fd, 14 * BLK, 0x11, BLK) < 0
			|| wr(fd, 15 * BLK + 2048, 0x22, 2048L) < 0 || wr(fd, 40 * BLK, 0x11, BLK) < 0
		    : wr(fd, 0L, 0x11, BLK) < 0 || wr(fd, 12 * BLK, 0x11, BLK) < 0 || wr(fd, 40 * BLK, 0x11, BLK) < 0) {
			perror(f);
			return 2;
		}
		fsync(fd);
		close(fd);
	}
	if (rewrite) {	/* the files' pages out of the cache, then the rewrites into allocated blocks */
		sync();
		if (churn(h, 0x33, mb, 1) < 0) {
			perror("evict");
			return 2;
		}
	}
	if (!eof)
		for (i = 0; i < nf; i++) {
			sprintf(f, "%s/sh.%d", dir, i);
			if ((fd = open(f, O_RDWR)) < 0) {
				perror(f);
				return 2;
			}
			for (k = 0; k < nb; k++)
				if (wr(fd, bl[k] * BLK + wp * PG, 0x22, 2048L) < 0) {
					perror("hole write");
					return 2;
				}
			fsync(fd);
			close(fd);
		}
	cached[0] = cached[1] = -1;
	if (rewrite) {	/* the page cache's view first */
		if (readback(dir, nf, bl, nb, wp, other, " (cached)") < 0)
			return 2;
		cached[0] = bad[0];
		cached[1] = bad[1];
	}
	sync();
	if (churn(h, 0x33, mb, 1) < 0) {
		perror("evict");
		return 2;
	}
	sync();
	if (readback(dir, nf, bl, nb, wp, other, "") < 0)
		return 2;
	for (i = 0; i < nf; i++) {
		sprintf(f, "%s/sh.%d", dir, i);
		unlink(f);
	}
	if (rewrite)
		printf("RES sparsehole: rewrite of allocated blocks at page %d: cached direct %ld, indirect %ld wrong; "
		    "after eviction direct %ld, indirect %ld wrong; of %ld and %ld pages each time; %ld files\n", wp,
		    cached[0], cached[1], bad[0] - cached[0], bad[1] - cached[1], n[0] / 2, n[1] / 2, nf);
	else
		printf("RES sparsehole: %s write at page %d: direct %ld of %ld pages wrong (%ld the filler's 0x5a); indirect "
		    "%ld of %ld wrong (%ld 0x5a); %ld files\n", keep ? "window-start-to-EOF" : eof ? "past-EOF" : "hole", wp,
		    bad[0], n[0], stale[0], bad[1], n[1], stale[1], nf);
	return bad[0] || bad[1] ? 1 : 0;
}
