#!/bin/sh
# hosttest.sh -- host test of the ramdisk module (ramdisk/README.md), without a box.  The
# shipped ramdisk/src/ramdisk.c is compiled by the host cc after one mechanical substitution:
# the K&R printf declaration goes (the test's printf is a prototyped recorder).  Stub headers
# stand in for the kernel's sys/buf.h, sys/open.h, sys/kmem.h, sys/conf.h, sys/ddi.h,
# sys/moddefs.h, sys/amixddi.h, sys/cred.h and sys/param.h; the test provides the DDI names
# the module calls: kmem_zalloc/kmem_free (recording every request), vtop (the identity),
# bcopy (checking that no copy crosses a buffer page or leaves a kmem piece), iodone,
# getminor and ramdisk_image (an image in host memory, or none).  It runs once with the k30
# page size (2 KiB) and once with the k46 one (4 KiB).
#
#   usage: sh ramdisk/test/hosttest.sh        (HOSTCC overrides cc)
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/inc/sys"

sed -e 's|^extern int printf();$|/* extern int printf(); -- hosttest */|' \
    "$top/ramdisk/src/ramdisk.c" > "$tmp/ramdisk.c"
[ "$(grep -cF '/* extern int printf(); -- hosttest */' "$tmp/ramdisk.c")" = 1 ] ||
	{ echo "hosttest: substitution failed: printf" >&2; exit 1; }

cat > "$tmp/inc/sys/param.h" <<'H'
#define PAGESIZE        TD_PAGESIZE
#define PAGEOFFSET      (PAGESIZE - 1)
H
cat > "$tmp/inc/sys/cred.h" <<'H'
struct cred { int cr_uid; };
H
cat > "$tmp/inc/sys/open.h" <<'H'
#define OTYP_BLK 0
#define OTYP_MNT 1
#define OTYP_CHR 2
#define OTYP_SWP 3
#define OTYP_LYR 4
H
cat > "$tmp/inc/sys/kmem.h" <<'H'
#define KM_SLEEP   0
#define KM_NOSLEEP 1
void *kmem_zalloc(long, int);
void kmem_free(void *, long);
H
cat > "$tmp/inc/sys/buf.h" <<'H'
typedef unsigned long paddr_t;
struct proc;
struct buf {
	int b_flags;
	unsigned b_bcount;
	union { caddr_t b_addr; } b_un;
	daddr_t b_blkno;
	unsigned int b_resid;
	struct proc *b_proc;
	int b_error;
	dev_t b_edev;
};
#define paddr(X) (paddr_t)(X->b_un.b_addr)
#define B_WRITE 0x0000
#define B_READ  0x0001
#define B_ERROR 0x0004
void iodone(struct buf *);
H
cat > "$tmp/inc/sys/ddi.h" <<'H'
unsigned getminor(dev_t);
paddr_t vtop(caddr_t, struct proc *);
H
cat > "$tmp/inc/sys/conf.h" <<'H'
#ifndef _SYS_CONF_H
#define _SYS_CONF_H
struct bdevsw { int (*d_open)(); int (*d_close)(); int (*d_strategy)(); int (*d_print)();
	int (*d_size)(); int (*d_xpoll)(); int (*d_xhalt)(); int *d_flag; };
struct cdevsw { int (*d_open)(); int (*d_close)(); int (*d_read)(); int (*d_write)();
	int (*d_ioctl)(); int (*d_mmap)(); };
#endif
H
cat > "$tmp/inc/sys/moddefs.h" <<'H'
struct mod_drv_data {
	struct bdevsw drv_bdevsw; int drv_bmajor, drv_bcount;
	struct cdevsw drv_cdevsw; int drv_cmajor, drv_ccount;
};
struct td_wrapper { int (*load)(); int (*unload)(); void (*halt)(); char *desc; };
#define MOD_DRV_WRAPPER(p, l, u, h, d) struct td_wrapper p##_wrapper = { l, u, h, d }
H
cat > "$tmp/inc/sys/amixddi.h" <<'H'
/* as the kit's: VSECT1 and an identity phystokv, unless already defined */
#ifndef VSECT1
#define VSECT1 0x40000000
#endif
#ifndef phystokv
#define phystokv(paddr) (paddr)
#endif
int ramdisk_image(unsigned long *, unsigned long *);
H

cat > "$tmp/t.c" <<'C'
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>

#define KIB 1024L
#define PIECE (256 * KIB)

static int td_nlines;
static char td_lines[4096];

int td_printf(const char *, ...);
int
td_printf(const char *fmt, ...)
{
	va_list ap;
	size_t n = strlen(td_lines);

	va_start(ap, fmt);
	vsnprintf(td_lines + n, sizeof td_lines - n, fmt, ap);
	va_end(ap);
	td_nlines++;
	return 0;
}

/* kmem: every live request, its size and flag; td_failat > 0 fails that request (1 = next) */
#define NA 256
static struct { char *p; long n; } td_al[NA];
static int td_nreq, td_maxreqflag, td_failat;
static long td_maxreq, td_live;
static int td_badfree;

void *
kmem_zalloc(long n, int f)
{
	int i;

	td_nreq++;
	if (n > td_maxreq)
		td_maxreq = n;
	if (f != 1)
		td_maxreqflag = 1;		/* not KM_NOSLEEP */
	if (td_failat > 0 && --td_failat == 0)
		return 0;
	for (i = 0; i < NA; i++)
		if (td_al[i].p == 0) {
			td_al[i].p = calloc(1, n);
			td_al[i].n = n;
			td_live += n;
			return td_al[i].p;
		}
	abort();
}

void
kmem_free(void *p, long n)
{
	int i;

	for (i = 0; i < NA; i++)
		if (td_al[i].p == p) {
			if (td_al[i].n != n)
				td_badfree++;
			td_live -= td_al[i].n;
			free(p);
			td_al[i].p = 0;
			return;
		}
	td_badfree++;
}

/* the piece holding [p, p+n), or -1 */
static int
td_inpiece(const char *p, long n)
{
	int i;

	for (i = 0; i < NA; i++)
		if (td_al[i].p && p >= td_al[i].p && p + n <= td_al[i].p + td_al[i].n)
			return i;
	return -1;
}

/* the image: host memory standing at a physical address below VSECT1 */
static char *td_img;
static unsigned long td_imgpa, td_imgsz;
static int td_haveimg;

int
ramdisk_image(unsigned long *pa, unsigned long *sz)
{
	if (!td_haveimg)
		return ENOENT;
	*pa = td_imgpa;
	*sz = td_imgsz;
	return 0;
}

unsigned getminor(dev_t d) { return (unsigned)d & 0xff; }

/* the buffer side: a page-aligned host area the strategy reaches through vtop */
static char *td_ubuf;
static long td_ubufsz;
static int td_crossed, td_outside, td_nvtop, td_niodone;

typedef unsigned long paddr_t;
struct proc;
paddr_t vtop(caddr_t a, struct proc *p) { (void)p; td_nvtop++; return (paddr_t)a; }

static void
td_bcopy(const void *from, void *to, size_t n)
{
	const char *u = 0, *k = 0;

	if ((const char *)from >= td_ubuf && (const char *)from < td_ubuf + td_ubufsz)
		u = from, k = to;
	else
		u = to, k = from;
	if (((unsigned long)u & ~(unsigned long)(TD_PAGESIZE - 1)) !=
	    (((unsigned long)u + n - 1) & ~(unsigned long)(TD_PAGESIZE - 1)))
		td_crossed++;
	if (!(k >= td_img && td_img && k + n <= td_img + td_imgsz) && td_inpiece(k, (long)n) < 0)
		td_outside++;
	memmove(to, from, n);
}

#define printf td_printf
#define bcopy td_bcopy
/* the image's "physical" address is a host address: put VSECT1 above all of them */
#define VSECT1 (~0UL >> 1)
#include "ramdisk.c"
#undef printf
#undef bcopy

struct buf;
void iodone(struct buf *bp) { (void)bp; td_niodone++; }

static int fails, checks;

#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; \
	fprintf(stdout, "FAIL line %d (page %d): ", __LINE__, TD_PAGESIZE); \
	fprintf(stdout, __VA_ARGS__); fputc('\n', stdout); } } while (0)

#define BOPEN(m, t) ramdisk_drvdata[0].drv_bdevsw.d_open(&(dev_t){ (dev_t)(m) }, 0, (t), (struct cred *)0)
#define BCLOSE(m, t) ramdisk_drvdata[0].drv_bdevsw.d_close((dev_t)(m), 0, (t), (struct cred *)0)
#define BSIZE(m) ramdisk_drvdata[0].drv_bdevsw.d_size((dev_t)(m))

/* one transfer through the row's strategy: buffer at td_ubuf + uoff */
static struct buf
xfer(int m, int rd, long blk, long uoff, unsigned n)
{
	struct buf b;
	int before = td_niodone;

	memset(&b, 0, sizeof b);
	b.b_flags = rd ? B_READ : B_WRITE;
	b.b_edev = (dev_t)m;
	b.b_blkno = blk;
	b.b_bcount = n;
	b.b_un.b_addr = td_ubuf + uoff;
	ramdisk_drvdata[0].drv_bdevsw.d_strategy(&b);
	CHECK(td_niodone == before + 1, "strategy(minor %d blk %ld) called iodone %d times", m, blk,
	    td_niodone - before);
	return b;
}

static void
fill(long uoff, long n, int seed)
{
	long i;

	for (i = 0; i < n; i++)
		td_ubuf[uoff + i] = (char)(seed + i * 7 + (i >> 9));
}

static int
same(long uoff, long n, int seed)
{
	long i;

	for (i = 0; i < n; i++)
		if (td_ubuf[uoff + i] != (char)(seed + i * 7 + (i >> 9)))
			return 0;
	return 1;
}

/* the image holds fill()'s pattern at off */
static int
imgsame(long off, long n, int seed)
{
	long i;

	for (i = 0; i < n; i++)
		if (td_img[off + i] != (char)(seed + i * 7 + (i >> 9)))
			return 0;
	return 1;
}

/* a fresh module: what a load finds */
static void
fresh(void)
{
	memset(rd_unit, 0, sizeof rd_unit);
	td_lines[0] = 0; td_nlines = 0;
	td_nreq = 0; td_maxreq = 0; td_maxreqflag = 0; td_failat = 0; td_badfree = 0;
	td_crossed = 0; td_outside = 0;
	td_haveimg = 0; td_img = 0; td_imgpa = 0; td_imgsz = 0;
}

int
main(void)
{
	struct buf b;
	long big = 2 * PIECE + 3 * TD_PAGESIZE;
	int i;

	td_ubufsz = 4 * PIECE;
	if (posix_memalign((void **)&td_ubuf, 65536, td_ubufsz))
		return 2;

	/* 1. the driver row: block major 20, one; no character row; no _halt */
	CHECK(ramdisk_drvdata[0].drv_bmajor == 20 && ramdisk_drvdata[0].drv_bcount == 1 &&
	    ramdisk_drvdata[0].drv_ccount == 0 && ramdisk_drvdata[0].drv_cmajor == 0, "drvdata majors");
	CHECK(ramdisk_drvdata[0].drv_bdevsw.d_open == ramdiskopen &&
	    ramdisk_drvdata[0].drv_bdevsw.d_close == ramdiskclose &&
	    ramdisk_drvdata[0].drv_bdevsw.d_strategy == ramdiskstrategy &&
	    ramdisk_drvdata[0].drv_bdevsw.d_print == ramdiskprint &&
	    ramdisk_drvdata[0].drv_bdevsw.d_size == ramdisksize &&
	    ramdisk_drvdata[0].drv_bdevsw.d_xpoll == 0 && ramdisk_drvdata[0].drv_bdevsw.d_flag == 0,
	    "drvdata bdevsw row");
	CHECK(ramdisk_drvdata[0].drv_cdevsw.d_open == 0, "a character row");
	CHECK(ramdisk_wrapper.halt == 0, "_halt is not the wrapper's 0");

	/* 2. no image: _load is 0 and silent, allocates nothing; unit 0 is ENXIO, units 1-2 sized */
	fresh();
	CHECK(ramdisk_wrapper.load((char *)0) == 0, "load(0) with no image failed");
	CHECK(td_nlines == 0 && td_nreq == 0, "load(0): said '%s', %d requests", td_lines, td_nreq);
	CHECK(BOPEN(0, OTYP_MNT) == ENXIO && BOPEN(0, OTYP_BLK) == ENXIO, "no image: unit 0 opens");
	CHECK(BSIZE(0) == -1, "no image: unit 0 size %d", BSIZE(0));
	CHECK(BSIZE(1) == 1024 && BSIZE(2) == 4096, "default sizes %d %d", BSIZE(1), BSIZE(2));
	CHECK(BSIZE(3) == -1 && BOPEN(3, OTYP_BLK) == ENXIO, "minor 3");
	b = xfer(0, 1, 0, 0, 512);
	CHECK((b.b_flags & B_ERROR) && b.b_error == ENXIO && b.b_resid == 512, "no image: unit 0 read");
	b = xfer(1, 1, 0, 0, 512);
	CHECK((b.b_flags & B_ERROR) && b.b_error == ENXIO, "a scratch unit read before its open");

	/* 3. the scratch units: allocated at first open in requests of at most 256 KiB, all
	 * KM_NOSLEEP, zero-filled; freed at the last close */
	CHECK(BOPEN(2, OTYP_BLK) == 0, "open unit 2");
	CHECK(td_nreq == 8 && td_maxreq == PIECE && !td_maxreqflag && td_live == 2048 * KIB,
	    "unit 2: %d requests, largest %ld, live %ld, flag %d", td_nreq, td_maxreq, td_live,
	    td_maxreqflag);
	CHECK(BOPEN(2, OTYP_MNT) == 0 && td_nreq == 8, "a second open allocated again");
	memset(td_ubuf, 0x55, 8192);
	b = xfer(2, 1, 4095, 0, 512);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 0, "read the last block of unit 2");
	for (i = 0; i < 512 && td_ubuf[i] == 0; i++)
		;
	CHECK(i == 512, "a fresh scratch unit does not read zeros");
	/* a run across a piece boundary and several buffer pages, from an unaligned buffer */
	fill(1000, big, 3);
	b = xfer(2, 0, (PIECE - 4096) / 512, 1000, (unsigned)big);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 0, "write across pieces: err %d resid %u",
	    b.b_error, b.b_resid);
	memset(td_ubuf, 0, td_ubufsz);
	b = xfer(2, 1, (PIECE - 4096) / 512, 3 * PIECE / 2 + 24, (unsigned)big);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 0 && same(3 * PIECE / 2 + 24, big, 3),
	    "read back across pieces");
	CHECK(td_crossed == 0, "%d copies crossed a buffer page", td_crossed);
	CHECK(td_outside == 0, "%d copies left a piece", td_outside);
	CHECK(td_nvtop >= big / TD_PAGESIZE, "vtop called %d times for %ld bytes", td_nvtop, big);
	/* the end: a read at the end is empty, a write there ENXIO, a run over it is cut */
	b = xfer(2, 1, 4096, 0, 1024);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 1024, "read at the end: err %d resid %u",
	    b.b_error, b.b_resid);
	b = xfer(2, 0, 4096, 0, 1024);
	CHECK((b.b_flags & B_ERROR) && b.b_error == ENXIO, "write at the end");
	b = xfer(2, 1, 4097, 0, 512);
	CHECK((b.b_flags & B_ERROR) && b.b_error == ENXIO, "read past the end");
	b = xfer(2, 1, -1, 0, 512);
	CHECK((b.b_flags & B_ERROR) && b.b_error == ENXIO, "a negative block");
	b = xfer(2, 0, 4094, 0, 4096);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 3072, "a run over the end: resid %u",
	    b.b_resid);
	/* the open types: the memory stays until the last one closes */
	CHECK(BCLOSE(2, OTYP_BLK) == 0 && td_live == 2048 * KIB, "close of one type freed");
	CHECK(BCLOSE(2, OTYP_MNT) == 0 && td_live == 0 && !td_badfree, "last close: live %ld bad %d",
	    td_live, td_badfree);
	CHECK(BOPEN(1, OTYP_CHR) == ENODEV && BOPEN(1, OTYP_LYR) == ENODEV && td_live == 0,
	    "character and layered opens");
	CHECK(BOPEN(1, OTYP_SWP) == 0 && td_live == 512 * KIB && BCLOSE(1, OTYP_SWP) == 0 &&
	    td_live == 0, "unit 1: swap open, 512 KiB");

	/* 4. a request that fails part way: ENOMEM, nothing left */
	td_nreq = 0; td_failat = 3;
	CHECK(BOPEN(2, OTYP_BLK) == ENOMEM && td_nreq == 3 && td_live == 0 && !td_badfree,
	    "the third request failing: %d requests, live %ld", td_nreq, td_live);
	CHECK(BOPEN(2, OTYP_BLK) == 0 && td_live == 2048 * KIB && BCLOSE(2, OTYP_BLK) == 0 &&
	    td_live == 0, "the open after an ENOMEM");

	/* 5. the parameters */
	fresh();
	ramdisk_wrapper.load("size1=300 size2=16384");
	CHECK(BSIZE(1) == 600 && BSIZE(2) == 32768 && td_nlines == 0, "size1=300 size2=16384");
	td_nreq = 0;
	CHECK(BOPEN(1, OTYP_BLK) == 0 && td_nreq == 2 && td_live == 300 * KIB, "300 KiB: %d requests",
	    td_nreq);
	CHECK(td_al[0].n + td_al[1].n == 300 * KIB && (td_al[0].n == 44 * KIB || td_al[1].n == 44 * KIB),
	    "300 KiB pieces %ld %ld", td_al[0].n, td_al[1].n);
	fill(0, 8192, 9);
	b = xfer(1, 0, 590, 0, 8192);		/* the last 5 KiB: cut at the end */
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 8192 - 5 * 1024, "300 KiB end: resid %u",
	    b.b_resid);
	BCLOSE(1, OTYP_BLK);
	td_nreq = 0;
	CHECK(BOPEN(2, OTYP_BLK) == 0 && td_nreq == 64 && td_maxreq <= PIECE &&
	    td_live == 16384 * KIB, "16 MiB: %d requests", td_nreq);
	fill(0, 4096, 1);
	xfer(2, 0, 32760, 0, 4096);
	memset(td_ubuf, 0, 4096);
	b = xfer(2, 1, 32760, 0, 4096);
	CHECK(!(b.b_flags & B_ERROR) && same(0, 4096, 1), "16 MiB: the last 4 KiB");
	BCLOSE(2, OTYP_BLK);
	CHECK(td_live == 0 && !td_badfree, "16 MiB freed");
	fresh();
	ramdisk_wrapper.load("x=1 size2=0 size1=64");
	CHECK(BSIZE(1) == 128 && BSIZE(2) == -1 && BOPEN(2, OTYP_BLK) == ENXIO && td_nlines == 0,
	    "size2=0: no unit 2");
	fresh();
	ramdisk_wrapper.load("size1=16385 size2=2k");
	CHECK(BSIZE(1) == 1024 && BSIZE(2) == 4096, "bad sizes give the defaults: %d %d", BSIZE(1),
	    BSIZE(2));
	CHECK(strcmp(td_lines, "ramdisk: size1 is not a size of 0 to 16384 KiB; 512 taken\n"
	    "ramdisk: size2 is not a size of 0 to 16384 KiB; 2048 taken\n") == 0, "said: %s", td_lines);
	fresh();
	ramdisk_wrapper.load("size1x=1 xsize1=2 size1=");
	CHECK(BSIZE(1) == 1024 && td_nlines == 1, "other names; an empty value: %d, said %s",
	    BSIZE(1), td_lines);
	fresh();
	ramdisk_wrapper.load("size1=99999999999999999999");
	CHECK(BSIZE(1) == 1024 && td_nlines == 1, "a long number: %d", BSIZE(1));

	/* 6. the image: unit 0 is its memory, read and written in place, never allocated or
	 * freed; its size reported; units 1-2 as before */
	fresh();
	td_imgsz = 3 * PIECE + 1000;		/* not a multiple of 512: the tail is left out */
	td_img = calloc(1, td_imgsz);
	td_imgpa = (unsigned long)td_img;
	td_haveimg = 1;
	for (i = 0; i < 4096; i++)
		td_img[i] = (char)(i * 3);
	CHECK(ramdisk_wrapper.load((char *)0) == 0 && td_nreq == 0, "load with an image");
	CHECK(td_nlines == 1 && strstr(td_lines, "ramdisk: unit 0 is the image at 0x") &&
	    strstr(td_lines, ", 768 KiB\n"), "load said: %s", td_lines);
	CHECK(BSIZE(0) == (int)((3 * PIECE) / 512 + 1), "unit 0 size %d", BSIZE(0));
	CHECK(BOPEN(0, OTYP_MNT) == 0 && td_nreq == 0, "open unit 0: %d requests", td_nreq);
	memset(td_ubuf, 0, 4096);
	b = xfer(0, 1, 0, 0, 4096);
	for (i = 0; i < 4096 && td_ubuf[i] == (char)(i * 3); i++)
		;
	CHECK(!(b.b_flags & B_ERROR) && i == 4096, "read the image's first 4 KiB");
	fill(500, big, 5);
	b = xfer(0, 0, 100, 500, (unsigned)big);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 0, "write into the image");
	CHECK(memcmp(td_img + 100 * 512, td_ubuf + 500, big) == 0, "the image holds the write");
	b = xfer(0, 1, BSIZE(0), 0, 512);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 512, "read at the image's end");
	b = xfer(0, 1, BSIZE(0) - 1, 0, 1024);
	CHECK(!(b.b_flags & B_ERROR) && b.b_resid == 512, "a run over the image's end");
	CHECK(td_crossed == 0 && td_outside == 0, "image copies: %d crossed, %d outside",
	    td_crossed, td_outside);
	CHECK(BCLOSE(0, OTYP_MNT) == 0 && td_nreq == 0 && td_badfree == 0 && td_live == 0,
	    "close unit 0 freed something");
	CHECK(BOPEN(0, OTYP_BLK) == 0 && imgsame(100 * 512, big, 5), "unit 0 kept its data");
	BCLOSE(0, OTYP_BLK);
	CHECK(BOPEN(1, OTYP_BLK) == 0 && td_live == 512 * KIB, "unit 1 beside an image");
	CHECK(ramdisk_wrapper.unload() == EBUSY, "unload with unit 1 open is not EBUSY");
	BCLOSE(1, OTYP_BLK);
	BOPEN(2, OTYP_BLK);
	rd_unit[2].ru_open = 0;		/* as after a failed load: memory, no opener */
	CHECK(ramdisk_wrapper.unload() == 0 && td_live == 0 && !td_badfree && BSIZE(0) == -1 &&
	    BSIZE(1) == -1, "unload: live %ld", td_live);
	CHECK(imgsame(100 * 512, big, 5), "unload touched the image");

	/* 7. an image the kernel does not map one to one: no unit 0, said; units 1-2 stay */
	fresh();
	td_haveimg = 1; td_img = 0; td_imgpa = VSECT1 - 4096; td_imgsz = 8192;
	CHECK(ramdisk_wrapper.load((char *)0) == 0 && BSIZE(0) == -1 && BSIZE(1) == 1024,
	    "an image across VSECT1");
	CHECK(td_nlines == 1 && strstr(td_lines, "is not below") != 0, "said: %s", td_lines);
	fresh();
	td_haveimg = 1; td_imgpa = 0x100000; td_imgsz = 300;	/* under one block */
	CHECK(ramdisk_wrapper.load((char *)0) == 0 && BSIZE(0) == -1, "an image under one block");

	if (fails) {
		fprintf(stdout, "hosttest: page %d: %d of %d checks failed\n", TD_PAGESIZE, fails, checks);
		return 1;
	}
	fprintf(stdout, "hosttest: page %d: ok (%d checks)\n", TD_PAGESIZE, checks);
	return 0;
}
C
for pg in 2048 4096; do
	${HOSTCC:-cc} -std=gnu99 -w -DTD_PAGESIZE=$pg -I"$tmp/inc" -I"$tmp" -o "$tmp/t$pg" "$tmp/t.c"
	"$tmp/t$pg"
done
