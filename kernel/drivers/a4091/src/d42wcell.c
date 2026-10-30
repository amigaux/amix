/* SPDX-License-Identifier: MIT */
/*
 * d42wcell.c -- metal cell for the D42 push half (dma_prepare's cpushl).
 *
 * Raw writes go through one kernel staging buffer (physdsk.c amiga_dma_pageio,
 * ngeteblk): copyin fills it, then the controller DMAs it to disk.  A dd write
 * never makes that buffer's lines cache-resident before copyin writes them, so
 * on a CPU that does not allocate on a write miss there is nothing dirty to
 * push.  This tool makes the lines resident first: a raw read() (whose copyout
 * reads the staging buffer) immediately followed by a raw write() of DIFFERENT
 * data, chunk by chunk, so the write's copyin hits resident lines and leaves
 * them dirty when the DMA reads RAM.  Without the push, the disk receives the
 * read's data (pattern A) where the write's (pattern B) belongs.
 *
 *   d42wcell a <rawdev> <blkA> <n>          write pattern A to blocks blkA..
 *   d42wcell w <rawdev> <blkA> <blkB> <n>   n x { read A[i]; write B[i] }
 *   d42wcell v <rawdev> <blkA> <blkB> <n>   verify: region B == pattern B
 *
 * Blocks are CHUNK (2048) bytes, the raw path's chunk on this kernel.  Each
 * 16-byte line is "<tag><blk6>:<ln3>:D42w", unique and self-locating.  Verify
 * prints one line per bad 16-byte line (first 40) and a summary.
 *
 * Build on the box:  cc -o d42wcell d42wcell.c
 */
#include <stdio.h>
#include <fcntl.h>

#define	CHUNK	2048
#define	LINE	16
#define	NLINE	(CHUNK / LINE)

static char	pa[CHUNK], pb[CHUNK], rb[CHUNK];

static void
fill( buf, tag, blk)
char	*buf;
int	tag;
long	blk;
{
	int	ln;
	char	t[LINE + 8];

	for (ln = 0; ln < NLINE; ln++) {
		sprintf( t, "%c%06ld:%03d:D42w", tag, blk, ln);	/* blk < 10^6 */
		memcpy( buf + ln * LINE, t, LINE);
	}
}

static int
seekblk( fd, blk)
int	fd;
long	blk;
{
	long	off;

	off = blk * (long)CHUNK;	/* CHUNK is a power of two: a shift, no 64-bit multiply */
	return lseek( fd, off, 0) == off ? 0 : -1;
}

static int
xfer( fd, blk, buf, wr)
int	fd;
long	blk;
char	*buf;
int	wr;
{
	if (seekblk( fd, blk) < 0)
		return -1;
	if (wr)
		return write( fd, buf, CHUNK) == CHUNK ? 0 : -1;
	return read( fd, buf, CHUNK) == CHUNK ? 0 : -1;
}

int
main( argc, argv)
int	argc;
char	**argv;
{
	int	fd, mode, ln, shown;
	long	a, b, n, i, bad, bada, badz, bado;

	if (argc < 5) {
		fprintf( stderr, "usage: d42wcell a|w|v rawdev blkA [blkB] n\n");
		return 2;
	}
	mode = argv[1][0];
	if ((fd = open( argv[2], O_RDWR)) < 0) {
		perror( argv[2]);
		return 2;
	}
	a = atol( argv[3]);
	if (mode == 'a') {
		n = atol( argv[4]);
		for (i = 0; i < n; i++) {
			fill( pa, 'A', a + i);
			if (xfer( fd, a + i, pa, 1) < 0) {
				perror( "write A");
				return 1;
			}
		}
		printf( "d42wcell a: %ld blocks of pattern A at %ld\n", n, a);
		return 0;
	}
	if (argc < 6) {
		fprintf( stderr, "usage: d42wcell w|v rawdev blkA blkB n\n");
		return 2;
	}
	b = atol( argv[4]);
	n = atol( argv[5]);
	if (mode == 'w') {
		for (i = 0; i < n; i++) {
			fill( pb, 'B', b + i);	/* before the read: nothing between read and write */
			if (xfer( fd, a + i, rb, 0) < 0 || xfer( fd, b + i, pb, 1) < 0) {
				perror( "read A / write B");
				return 1;
			}
		}
		printf( "d42wcell w: %ld x {read A %ld+i, write B %ld+i}\n", n, a, b);
		return 0;
	}
	if (mode != 'v') {
		fprintf( stderr, "d42wcell: mode must be a, w or v\n");
		return 2;
	}
	bad = bada = badz = bado = 0;
	shown = 0;
	for (i = 0; i < n; i++) {
		fill( pb, 'B', b + i);
		fill( pa, 'A', a + i);
		if (xfer( fd, b + i, rb, 0) < 0) {
			perror( "read B");
			return 1;
		}
		for (ln = 0; ln < NLINE; ln++) {
			char	*g = rb + ln * LINE;
			int	k, z;

			if (memcmp( g, pb + ln * LINE, LINE) == 0)
				continue;
			bad++;
			for (z = 1, k = 0; k < LINE; k++)
				if (g[k] != 0)
					z = 0;
			if (z)
				badz++;
			else if (g[0] == 'A')
				bada++;
			else
				bado++;
			if (shown < 40) {
				printf( "bad blk %ld line %d: %.16s\n", b + i, ln, g);
				shown++;
			}
		}
	}
	printf( "d42wcell v: %ld blocks, %ld bad 16-byte lines (A-data %ld, zero %ld, other %ld)\n",
	    n, bad, bada, badz, bado);
	return bad ? 1 : 0;
}
