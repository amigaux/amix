/*
 * td.h -- the host harness for zz9ksvc.c: the DDI stand-ins it calls (timeout and sleep
 * drive a simulated clock that steps test/fw.c, the stand-in runtime), a stub zz9kbus board
 * whose host-visible heap window lies at PHYS_BASE, and the client's calls (open, ioctl,
 * mmap, close through the cdevsw row).  Included once, by the test's own source; compiled
 * with -Itest/stub, -Isrc and -DTD_NBPP/-DTD_PSHIFT for the line's page.
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see zz9ksvc/LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>

typedef long clock_t_td;
#define _KERNEL
/* the DDI stand-ins zz9ksvc.c declares K&R-style */
clock_t lbolt;
int td_root = 1, td_signal, td_kmem_fail, td_copy_fail, td_doorbells, td_kmem_live;
struct td_co { void (*f)(); caddr_t a; long when; int id; } td_co[64];
int td_coid;

#include "zz9ksvc.c"
#include "fw.h"

static int checks, td_woken_any;
static caddr_t td_woken[64];
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); \
	printf(__VA_ARGS__); printf("\n"); exit(1); } checks++; } while (0)

unsigned getminor(dev_t d) { return (unsigned)d & 0x3ffff; }
unsigned getmajor(dev_t d) { return ((unsigned)d >> 18) & 0xff; }
dev_t makedevice(unsigned ma, unsigned mi) { return (dev_t)((ma << 18) | mi); }
int spl4(void) { return 0; }
int splx(int s) { return 0; }
int drv_priv(struct cred *c) { return td_root ? 0 : EPERM; }
int copyin(caddr_t u, caddr_t k, size_t n) { if (td_copy_fail) return -1; memcpy(k, u, n); return 0; }
int copyout(caddr_t k, caddr_t u, size_t n) { if (td_copy_fail) return -1; memcpy(u, k, n); return 0; }
void bcopy(const void *s, void *d, size_t n) { memmove(d, s, n); }
void bzero(void *p, size_t n) { memset(p, 0, n); }
caddr_t kmem_zalloc(size_t n, int f) { if (td_kmem_fail) return 0; td_kmem_live++; return calloc(1, n); }
void kmem_free(caddr_t p, size_t n) { td_kmem_live--; free(p); }

int
timeout(void (*f)(), caddr_t a, long t)
{
	int i;

	for (i = 0; i < 64; i++)
		if (td_co[i].f == 0) {
			td_co[i].f = f; td_co[i].a = a; td_co[i].when = lbolt + t; td_co[i].id = ++td_coid;
			return td_co[i].id;
		}
	printf("FAIL: callout table full\n");
	exit(1);
}

int
untimeout(int id)
{
	int i;

	for (i = 0; i < 64; i++)
		if (td_co[i].f && td_co[i].id == id)
			td_co[i].f = 0;
	return 0;
}

void
wakeup(caddr_t chan)
{
	int i;

	for (i = 0; i < 64; i++)
		if (td_woken[i] == 0) {
			td_woken[i] = chan;
			break;
		}
	td_woken_any = 1;
}

static int
was_woken(caddr_t chan)
{
	int i, w = 0;

	for (i = 0; i < 64; i++)
		if (td_woken[i] == chan) {
			td_woken[i] = 0;
			w = 1;
		}
	return w;
}

/* one clock tick of the simulated box: the runtime steps, due callouts run */
static void
td_tick(void)
{
	int i;

	lbolt++;
	fw_step();
	for (i = 0; i < 64; i++)
		if (td_co[i].f && td_co[i].when <= lbolt) {
			void (*f)() = td_co[i].f;
			caddr_t a = td_co[i].a;

			td_co[i].f = 0;
			f(a);
		}
}

static void
td_run(int ticks)
{
	while (ticks-- > 0)
		td_tick();
}

int
sleep(caddr_t chan, int pri)
{
	int n;

	for (n = 0; n < 100000; n++) {
		if (td_signal) {
			td_signal = 0;
			return 1;
		}
		td_tick();
		if (was_woken(chan))
			return 0;
	}
	printf("FAIL: sleep never woken\n");
	exit(1);
}

static int
callouts(void)
{
	int i, n = 0;

	for (i = 0; i < 64; i++)
		if (td_co[i].f)
			n++;
	return n;
}

/* ---- the stub board ---- */

#define PHYS_BASE	0x20000000UL	/* where runtime 0's window lies in physical memory */
#define PHYS_STEP	0x02000000UL	/* and runtime n's, n steps above it */
static struct zz9kbus_board board;
static int bread_magic = 1;

static unsigned bread(char *c, int off) { return off == 0 && bread_magic ? zzw_boot_magic : 0xffff; }
static void bell(char *c) { td_doorbells++; }
static int
heapphys(char *c, unsigned long arm, unsigned long len, unsigned long *phys)
{
	unsigned long base = PHYS_BASE + (unsigned long)c * PHYS_STEP;	/* zb_ctx: the runtime */

	*phys = base;	/* a plausible answer even when refusing: only the return counts */
	if (arm < FW_HEAP_ARM || len > FW_HEAP_LEN || arm - FW_HEAP_ARM > FW_HEAP_LEN - len)
		return -1;
	*phys = base + (arm - FW_HEAP_ARM);
	return 0;
}

/* bp as a board whose runtime is fw_mboxes[inst] */
static void
board_setup(struct zz9kbus_board *bp, int inst)
{
	memset(bp, 0, sizeof *bp);
	bp->zb_version = ZZ9KBUS_VERSION;
	bp->zb_id = ZZ9KBUS_ID_Z3660;
	bp->zb_boff = 0x400;
	bp->zb_bsize = 0x20;
	bp->zb_ctx = (char *)(long)inst;
	bp->zb_bread = (unsigned (*)())bread;
	bp->zb_doorbell = (void (*)())bell;
	bp->zb_mbox = (char *)fw_mboxes[inst];
	bp->zb_mboxlen = FW_MBOXLEN;
	bp->zb_heapphys = (int (*)())heapphys;
}

static void
board_init(void)
{
	board_setup(&board, 0);
}

/* ---- the client's side ---- */

static dev_t
op_open(int unit, int *err)
{
	dev_t d = makedevice(ZZS_MAJOR, unit);

	*err = zz9ksvc_drvdata[0].drv_cdevsw.d_open(&d, FREAD | FWRITE, 2, (struct cred *)0);
	return d;
}

static int
op_close(dev_t d)
{
	return zz9ksvc_drvdata[0].drv_cdevsw.d_close(d, FREAD | FWRITE, 2, (struct cred *)0);
}

static int
ioc(dev_t d, int cmd, void *arg)
{
	int rv;

	return zz9ksvc_drvdata[0].drv_cdevsw.d_ioctl(d, cmd, (caddr_t)arg, FREAD | FWRITE,
	    (struct cred *)0, &rv);
}

static int
op_alloc(dev_t d, long len, long flags, struct zzs_alloc *za)
{
	memset(za, 0, sizeof *za);
	za->za_length = len;
	za->za_flags = flags;
	return ioc(d, ZZSIOC_ALLOC, za);
}

static void
be32(unsigned char *p, unsigned long v)
{
	p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

/* a DECOMPRESS of src (off, len) into dst (off, cap) */
static int
op_decompress(dev_t d, long src, unsigned long soff, unsigned long slen,
    long dst, unsigned long doff, unsigned long dcap, long *id)
{
	struct zzs_submit zs;
	int e;

	memset(&zs, 0, sizeof zs);
	zs.zs_opcode = fw_op_decompress();
	zs.zs_len = 48;
	be32(zs.zs_payload + 0, src);
	be32(zs.zs_payload + 4, soff);
	be32(zs.zs_payload + 8, slen);
	be32(zs.zs_payload + 12, dst);
	be32(zs.zs_payload + 16, doff);
	be32(zs.zs_payload + 20, dcap);
	e = ioc(d, ZZSIOC_SUBMIT, &zs);
	if (id)
		*id = zs.zs_id;
	return e;
}

static int
op_plain(dev_t d, unsigned long opcode, long *id)
{
	struct zzs_submit zs;
	int e;

	memset(&zs, 0, sizeof zs);
	zs.zs_opcode = opcode;
	zs.zs_len = 4;
	e = ioc(d, ZZSIOC_SUBMIT, &zs);
	if (id)
		*id = zs.zs_id;
	return e;
}

static int
op_wait(dev_t d, long id, long ms, struct zzs_wait *zw)
{
	memset(zw, 0, sizeof *zw);
	zw->zw_id = id;
	zw->zw_ms = ms;
	return ioc(d, ZZSIOC_WAIT, zw);
}

static int
op_mmap(dev_t d, long off)
{
	return zz9ksvc_drvdata[0].drv_cdevsw.d_mmap(d, (off_t)off, 3);
}

/* a DECOMPRESS of slen bytes of src into dcap bytes of dst with a real algorithm */
static int
op_inflate(dev_t d, long src, unsigned long slen, long dst, unsigned long dcap, unsigned long alg,
    long *id)
{
	struct zzs_submit zs;
	int e;

	memset(&zs, 0, sizeof zs);
	zs.zs_opcode = fw_op_decompress();
	zs.zs_len = 32;
	be32(zs.zs_payload + 0, src);
	be32(zs.zs_payload + 8, slen);
	be32(zs.zs_payload + 12, dst);
	be32(zs.zs_payload + 20, dcap);
	be32(zs.zs_payload + 24, alg);
	e = ioc(d, ZZSIOC_SUBMIT, &zs);
	if (id)
		*id = zs.zs_id;
	return e;
}

/*
 * What a mapping of len bytes at cookie reaches: d_mmap asked for every 2 KiB step, as
 * spec_segmap does, the frames turned back into the stand-in's heap memory.  0 when a step
 * is refused or the frames are not one run.
 */
static unsigned char *
td_map(dev_t d, long cookie, unsigned long len)
{
	unsigned long off;
	int pfn, first = -1;

	for (off = 0; off < len; off += 2048) {
		if ((pfn = op_mmap(d, cookie + (long)off)) == -1)
			return 0;
		if (first == -1)
			first = pfn;
		else if ((unsigned long)pfn != (unsigned long)first + (off >> TD_PSHIFT))
			return 0;
	}
	if (first == -1)
		return 0;
	{
		unsigned long phys = (unsigned long)first << TD_PSHIFT;
		int inst = (int)((phys - PHYS_BASE) / PHYS_STEP);

		return fw_heap_of(inst, FW_HEAP_ARM + phys - PHYS_BASE - (unsigned long)inst * PHYS_STEP);
	}
}

static struct zzs_stats
stats(dev_t d)
{
	struct zzs_stats zt;

	memset(&zt, 0, sizeof zt);
	if (ioc(d, ZZSIOC_STATS, &zt) != 0) {
		printf("FAIL: STATS\n");
		exit(1);
	}
	return zt;
}

static void
drain(void)
{
	int n;

	for (n = 0; n < 200 && (zzs_pending() || callouts()); n++)
		td_tick();
}

