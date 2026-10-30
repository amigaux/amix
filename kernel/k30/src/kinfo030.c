/*
 * kinfo030.c -- /dev/kinfo on the 030 line: the kernel's read-only identity record
 * (kernel/dlm docs/contracts/C2-1-kinfo.md, version 3: the loader's bootdata block at 536, where the kernel was
 * bound, for the booted kernel's namelist; the module list moves to 576/580).
 *
 * The 040/060 line's src/kinfo.c (amix-040-060-port e65247a), ported to the classic 030 kit:
 *   - the CPU is the line's own constant (the 030 kernel keeps no cputype);
 *   - the build id is kinfo_buildid[], stamped by the build (build-cross-kernel.sh --kinfo-build,
 *     compiled in as KINFO_BUILD) -- the 030 kernel has no buildid string and its uname -m is empty;
 *   - sd's cards come through sd.c's own accessors (sdopen, sdcardbase, sdhardwarename): the 030
 *     sd.c keeps its queue[] static.
 * One record, built on the first open from the kernel's own copy of bootinfo: the CPU and line,
 * the kabi tag, the build id, the loader's AXL1 and RTH1 records as they arrived, the AutoConfig
 * boards, sd's card table, the memory the kernel runs on, and the loaded modules (none: a static
 * kernel).  read(2) returns its bytes from the file offset on, write(2) is EPERM.
 *
 * With -DKINFO_DLM (the module kernel, build-cross-kernel.sh --dlm) the record also lists the loaded modules.
 *
 * Linked by build-cross-kernel.sh --kinfo, which registers kinfoopen/close/read/write in
 * cdevsw[53] (tools/kinfo-cdevsw.py).  The node is `mknod /dev/kinfo c 53 0`, mode 0444.
 *
 * Kept free of division and of multiplication by a non-power of two, as rth1.c is.
 */
#include <sys/types.h>
#include <sys/errno.h>
#include <sys/uio.h>

#ifndef KINFO_BUILD
#error KINFO_BUILD (the build id, "68030-yymmdd-nn") must be given by the build
#endif

#define KIF1_MAGIC	0x4B494631	/* "KIF1" */
#define KIF1_VERSION	3
#define KIF1_LENGTH	580		/* no modules */
#define KIF1_CPU	30
#define KIF1_LINE	30

#define AXL1_MAGIC	0x41584C31	/* "AXL1" */
#define AXL1_LONGS	31		/* 124 bytes, all summed */
#define AXLF_SAFE	0x01
#define RTH1_MAGIC	0x52544831	/* "RTH1" */
#define RTH1_LONGS	14		/* 0x38 bytes */
#define RTH1_CHECKED	7		/* longs 0x00..0x18 sum to 0 */

#define BI_RTH1		0x678		/* loader reserved[0], kernel bootinfo+0x678 */
#define BI_AXL1		(BI_RTH1 + 0x38)
#define BI_BOOTDATA	0x650		/* entry, then text/rodata/data vaddr, offset, size: 40 bytes */
#define BD_LEN		40
#define BD_TEXTVA	4		/* the text vaddr within the block */
#define NAUTO		16
#define CD_SIZE		0x44		/* struct ConfigDev */
#define CD_PRODUCT	0x11		/* er_Product, a byte */
#define CD_MANUF	0x14		/* er_Manufacturer, a word */
#define CD_BOARDADDR	0x20
#define CD_BOARDSIZE	0x24
#define KCARDS		4		/* the record's card table; sdopen refuses past sd's own count */

/* record offsets */
#define K_CHECK		8
#define K_CPU		12
#define K_LINE		16
#define K_ATTN		20
#define K_KABI		24
#define K_BUILD		48
#define K_FLAGS		80
#define K_AXL1		84
#define K_RTH1		208
#define K_NBOARD	264
#define K_BOARD		268
#define K_NCARD		460
#define K_CARD		464
#define K_FAST		528
#define K_CHIP		532
#define K_BOOTDATA	536
#define K_NMOD		576

#define KF_AXL1		0x1
#define KF_RTH1		0x2
#define KF_SAFE		0x4
#define KF_BINDDIFF	0x8		/* the bootdata text vaddr is not the kernel's own stext */
#define KC_MOBO		0x1

/* motherboard controllers: a zero manufacturer, so never a Zorro id */
#define MOBO_A3000WD	1
#define MOBO_GAYLE	2
#define MOBO_A4000T710	3		/* the A4000T's onboard 53C710 (a4kt710, S5-06) */
#define MOBO_Z3660WIN	4		/* the Z3660 in its 68030 mode: no AutoConfig board, sd took it at the window */
#define Z3660_WINDOW	0x10000000UL	/* the Z3660's fixed register window (kernel/dlm C4-1 v4 section 5.1) */

extern unsigned char bootinfo[];
extern char stext[];
extern unsigned long chipmem, VSIZOFMEM;
extern int sdopen();
extern char *sdcardbase(), *sdhardwarename();
extern int uiomove();

/* The kabi tag and the build id; tools/kabi-sidecar030.py reads both from the image. */
#ifndef KINFO_KABI
#define KINFO_KABI	"static"	/* a static kernel; a module kernel's build passes its kabi (k30.1.0) */
#endif
char kinfo_kabi[24] = KINFO_KABI;
char kinfo_buildid[32] = KINFO_BUILD;

#ifdef KINFO_DLM
/*
 * The module kernel (stage 3, S3-21; build-cross-kernel.sh --dlm): the record ends in the loaded modules,
 * 32 bytes each from the core's dlm_kinfo_list() (C2-1 v3: count at 576, list at 580), refreshed on every open and on every
 * read from offset 0, so its length and check follow what is loaded.
 */
#define KMODS		32
extern int dlm_kinfo_list();
static unsigned long kinfo_rec[(KIF1_LENGTH + (KMODS << 5)) / 4] = { 0 };
static long kinfo_len = KIF1_LENGTH;
#define KLEN		kinfo_len
#else
static unsigned long kinfo_rec[KIF1_LENGTH / 4] = { 0 };
#define KLEN		KIF1_LENGTH
#endif
static int kinfo_built = 0;

#define L(p, o)	(*(unsigned long *) ((unsigned char *) (p) + (o)))
#define W(p, o)	(*(unsigned short *) ((unsigned char *) (p) + (o)))

static int
kinfo_sum0(p, n)
unsigned long *p;
int n;
{
	unsigned long s = 0;

	while (n-- > 0)
		s += *p++;
	return s == 0;
}

static void
kinfo_copy(to, from, n)
unsigned char *to, *from;
int n;
{
	while (n-- > 0)
		*to++ = *from++;
}

static int
kinfo_streq(a, b)
char *a, *b;
{
	while (*a && *a == *b)
		a++, b++;
	return *a == *b;
}

static void
kinfo_make()
{
	unsigned char *r = (unsigned char *) kinfo_rec, *cd, *q;
	unsigned long *a = (unsigned long *) (bootinfo + BI_AXL1);
	unsigned long *h = (unsigned long *) (bootinfo + BI_RTH1);
	unsigned long flags = 0, s;
	int i, j, n;

	L(r, 0) = KIF1_MAGIC;
	L(r, 4) = (unsigned long) KIF1_VERSION << 16 | KIF1_LENGTH;
	L(r, K_CPU) = KIF1_CPU;
	L(r, K_LINE) = KIF1_LINE;
	for (i = 0; i < 23 && kinfo_kabi[i]; i++)
		r[K_KABI + i] = kinfo_kabi[i];
	for (i = 0; i < 31 && kinfo_buildid[i]; i++)
		r[K_BUILD + i] = kinfo_buildid[i];

	if (a[0] == AXL1_MAGIC && (a[1] >> 16) == 1 && (a[1] & 0xFFFF) >= AXL1_LONGS * 4
	    && kinfo_sum0(a, AXL1_LONGS)) {
		kinfo_copy(r + K_AXL1, (unsigned char *) a, AXL1_LONGS * 4);
		L(r, K_ATTN) = a[6];
		flags |= KF_AXL1;
		if (a[9] & AXLF_SAFE)
			flags |= KF_SAFE;
	}
	if (h[0] == RTH1_MAGIC && (h[1] >> 16) == 1 && (h[1] & 0xFFFF) >= RTH1_LONGS * 4
	    && kinfo_sum0(h, RTH1_CHECKED)) {
		kinfo_copy(r + K_RTH1, (unsigned char *) h, RTH1_LONGS * 4);
		flags |= KF_RTH1;
	}
	/* where the loader bound the kernel (boot2 and the stock loader's rel() both fill it), verbatim */
	kinfo_copy(r + K_BOOTDATA, bootinfo + BI_BOOTDATA, BD_LEN);
	if (L(bootinfo + BI_BOOTDATA, BD_TEXTVA) != (unsigned long) stext)
		flags |= KF_BINDDIFF;
	L(r, K_FLAGS) = flags;

	/* the boards in the loader's order; an empty slot has no manufacturer and no base */
	n = 0;
	q = r + K_BOARD;
	for (i = 0, cd = bootinfo; i < NAUTO; i++, cd += CD_SIZE) {
		if (W(cd, CD_MANUF) == 0 && L(cd, CD_BOARDADDR) == 0)
			continue;
		W(q, 0) = W(cd, CD_MANUF);
		q[2] = cd[CD_PRODUCT];
		L(q, 4) = L(cd, CD_BOARDADDR);
		L(q, 8) = L(cd, CD_BOARDSIZE);
		q += 12;
		n++;
	}
	L(r, K_NBOARD) = n;

	/*
	 * sd's cards as its init() numbered them: card k is queue[k], the c of a disk's cNdMsK being
	 * 8k + unit.  sdopen runs init() (lazy and guarded) and answers ENXIO for an empty or
	 * out-of-range card, so sdcardbase/sdhardwarename are asked only about a card that is there.
	 * The motherboard controllers go by sd's own name for them, before any board match.
	 */
	n = 0;
	q = r + K_CARD;
	for (i = 0; i < KCARDS; i++) {
		unsigned long base, id = 0, f = 0;
		char *nm;

		if (sdopen(i) != 0)
			continue;
		base = (unsigned long) sdcardbase(i);
		nm = sdhardwarename(i);
		if (nm && kinfo_streq(nm, "A3000 Internal SCSI"))
			id = MOBO_A3000WD, f = KC_MOBO;
		else if (nm && kinfo_streq(nm, "A4000 IDE"))
			id = MOBO_GAYLE, f = KC_MOBO;
		else if (nm && kinfo_streq(nm, "A4000T onboard SCSI"))
			id = MOBO_A4000T710, f = KC_MOBO;
		else
			for (j = 0, cd = bootinfo; j < NAUTO; j++, cd += CD_SIZE)
				if (L(cd, CD_BOARDADDR) == base && W(cd, CD_MANUF) != 0) {
					id = (unsigned long) W(cd, CD_MANUF) << 16
					    | (unsigned long) cd[CD_PRODUCT] << 8;
					break;
				}
		/* no board at the Z3660's window: its 68030 mode (C4-1 v4 section 5.1), never id 0 */
		if (id == 0 && base == Z3660_WINDOW)
			id = MOBO_Z3660WIN, f = KC_MOBO;
		if (f & KC_MOBO)
			base = 0;
		L(q, 0) = i;
		L(q, 4) = id;
		L(q, 8) = base;
		L(q, 12) = f;
		q += 16;
		n++;
	}
	L(r, K_NCARD) = n;

	L(r, K_FAST) = VSIZOFMEM;
	L(r, K_CHIP) = chipmem;
	L(r, K_NMOD) = 0;

	for (s = 0, i = 0; i < KIF1_LENGTH / 4; i++)
		s += kinfo_rec[i];
	L(r, K_CHECK) = -s;
	kinfo_built = 1;
}

#ifdef KINFO_DLM
static void
kinfo_mods()
{
	unsigned char *r = (unsigned char *) kinfo_rec;
	unsigned long s;
	int i, n;

	n = dlm_kinfo_list(r + KIF1_LENGTH, KMODS);
	L(r, K_NMOD) = n;
	kinfo_len = KIF1_LENGTH + (n << 5);
	L(r, 4) = (unsigned long) KIF1_VERSION << 16 | kinfo_len;
	L(r, K_CHECK) = 0;
	for (s = 0, i = 0; i < (kinfo_len >> 2); i++)
		s += kinfo_rec[i];
	L(r, K_CHECK) = -s;
}
#endif

int
kinfoopen(dp, oflags, otype, crp)
dev_t *dp;
int oflags, otype;
struct cred *crp;
{
	if ((*dp & 0x3FFFF) != 0)	/* minor 0 only */
		return ENXIO;
	if (!kinfo_built)
		kinfo_make();
#ifdef KINFO_DLM
	kinfo_mods();
#endif
	return 0;
}

int
kinfoclose(d, oflags, otype, crp)
dev_t d;
int oflags, otype;
struct cred *crp;
{
	return 0;
}

int
kinforead(d, uiop, crp)
dev_t d;
struct uio *uiop;
struct cred *crp;
{
	long off = uiop->uio_offset, n;

	if (off < 0)
		return EINVAL;
#ifdef KINFO_DLM
	if (off == 0)
		kinfo_mods();
#endif
	if (off >= KLEN)
		return 0;
	n = KLEN - off;
	if (n > uiop->uio_resid)
		n = uiop->uio_resid;
	return uiomove((caddr_t) kinfo_rec + off, n, UIO_READ, uiop);
}

int
kinfowrite(d, uiop, crp)
dev_t d;
struct uio *uiop;
struct cred *crp;
{
	return EPERM;
}
