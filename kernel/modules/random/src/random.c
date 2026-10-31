/*
 * random.c -- /dev/random and /dev/urandom: a ChaCha20 generator with fast key erasure, a
 * demand-class loadable module for both kernel lines.  random/README.md has the whole story;
 * this is the short form.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see kernel/modules/LICENSE in the amix repository.
 *
 *   minor 0  /dev/random     the same generator; neither minor blocks and there is no
 *   minor 1  /dev/urandom    entropy count, as /dev/urandom on Linux after its first seeding
 *
 * The state is a 256-bit ChaCha20 key and a block counter.  Output is ChaCha20 blocks
 * (RFC 8439 section 2.3) of that key and counter, and every read ends by replacing the key
 * with a block no one sees (fast key erasure), so a later state gives nothing about earlier
 * output.  The key also changes every 64 KiB within one long read.
 *
 * Input goes into the key 32 bytes at a time: XORed in, then the key becomes the first half
 * of a block of the result under a nonce no output block uses.  Input is what a process
 * writes to either device (the boot step randseed writes the saved seed, the date and the
 * process table) and a sample taken at load, at every open and at every read: lbolt, the
 * beam position (VHPOSR) three times between the slow CIA accesses, the four timer bytes
 * of each CIA, a call count and the request.  The chipset and the CIAs lie below VSECT1, where both lines map
 * physical addresses one to one (at phystokv(), cache-inhibited on k46).  They are only
 * read, and only registers whose reading changes nothing: not a TOD high byte (it latches
 * the counter) and not an ICR (reading clears it).
 *
 * The kernel is not preemptive, but uiomove() may sleep on a page fault, and another reader
 * may run meanwhile.  So the counter is advanced before every uiomove(), and nothing of the
 * state is kept in locals across one: no two outputs share a key and a counter.
 *
 * unload=never: the key holds what randseed wrote at boot, which a reload would lose.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>
#include <sys/uio.h>
#include <sys/cred.h>
#include <sys/conf.h>
#include <sys/ddi.h>
#include <sys/moddefs.h>
#include <sys/amixddi.h>

#define RAND_MAJOR	48		/* c 48, the registry's (kit registry/majors) */
#define RAND_NMINOR	2
#define RAND_BUF	256		/* bytes per uiomove(): four blocks */
#define RAND_REKEY	1024		/* blocks: the key changes every 64 KiB */

#define RAND_VHPOSR	0xdff006	/* the beam position, a word */
#define RAND_CIAA	0xbfe001	/* CIA-A; its registers are 0x100 apart */
#define RAND_CIAB	0xbfd000	/* CIA-B */

/* nonce words: output blocks use 0, the two private uses their own */
#define RAND_NMIX	0x6d697820	/* "mix " */
#define RAND_NKEY	0x6b657920	/* "key " */

typedef unsigned int r32;		/* 32 bits on the target and on the host */

extern clock_t lbolt;

static r32 rand_key[8];
static r32 rand_ctr;
static r32 rand_calls;

#define ROTL(x, n)	(((x) << (n)) | ((x) >> (32 - (n))))
#define QR(a, b, c, d) { \
	a += b; d ^= a; d = ROTL(d, 16); \
	c += d; b ^= c; b = ROTL(b, 12); \
	a += b; d ^= a; d = ROTL(d, 8); \
	c += d; b ^= c; b = ROTL(b, 7); }

/*
 * One ChaCha20 block (RFC 8439 section 2.3): out[16] = the 20 rounds of (the constants, key,
 * ctr, n0 n1 n2) plus that input, as words.  out must not be key.
 */
static void
rand_block(key, ctr, n0, n1, n2, out)
r32 *key;
r32 ctr, n0, n1, n2;
r32 *out;
{
	register r32 x0, x1, x2, x3, x4, x5, x6, x7;
	r32 x8, x9, x10, x11, x12, x13, x14, x15;
	int i;

	x0 = 0x61707865; x1 = 0x3320646e; x2 = 0x79622d32; x3 = 0x6b206574;
	x4 = key[0]; x5 = key[1]; x6 = key[2]; x7 = key[3];
	x8 = key[4]; x9 = key[5]; x10 = key[6]; x11 = key[7];
	x12 = ctr; x13 = n0; x14 = n1; x15 = n2;
	for (i = 0; i < 10; i++) {
		QR(x0, x4, x8, x12)
		QR(x1, x5, x9, x13)
		QR(x2, x6, x10, x14)
		QR(x3, x7, x11, x15)
		QR(x0, x5, x10, x15)
		QR(x1, x6, x11, x12)
		QR(x2, x7, x8, x13)
		QR(x3, x4, x9, x14)
	}
	out[0] = x0 + 0x61707865; out[1] = x1 + 0x3320646e;
	out[2] = x2 + 0x79622d32; out[3] = x3 + 0x6b206574;
	out[4] = x4 + key[0]; out[5] = x5 + key[1]; out[6] = x6 + key[2]; out[7] = x7 + key[3];
	out[8] = x8 + key[4]; out[9] = x9 + key[5]; out[10] = x10 + key[6]; out[11] = x11 + key[7];
	out[12] = x12 + ctr; out[13] = x13 + n0; out[14] = x14 + n1; out[15] = x15 + n2;
}

/* the key becomes the first half of block (key, ctr, nonce); the counter starts again */
static void
rand_newkey(ctr, n0, n1)
r32 ctr, n0, n1;
{
	r32 t[16];
	int i;

	rand_block(rand_key, ctr, n0, n1, 0, t);
	for (i = 0; i < 8; i++)
		rand_key[i] = t[i];
	for (i = 0; i < 16; i++)
		t[i] = 0;
	rand_ctr = 0;
}

/* in[8] into the key; len (0-32, the bytes of in that are input) goes into the nonce */
static void
rand_absorb(in, len)
r32 *in;
r32 len;
{
	int i;

	for (i = 0; i < 8; i++)
		rand_key[i] ^= in[i];
	rand_newkey(0, RAND_NMIX, len);
}

/* the sample taken at load, open and read; what says where it was taken from */
static void
rand_stir(what)
r32 what;
{
	volatile unsigned char *a = (volatile unsigned char *)phystokv(RAND_CIAA);
	volatile unsigned char *b = (volatile unsigned char *)phystokv(RAND_CIAB);
	volatile unsigned short *beam = (volatile unsigned short *)phystokv(RAND_VHPOSR);
	r32 s[8];

	s[0] = (r32)lbolt;
	s[1] = *beam;
	s[2] = a[0x400] | a[0x500] << 8 | a[0x600] << 16 | (r32)a[0x700] << 24;
	s[3] = *beam;		/* again after each CIA's slow accesses: E-clock jitter */
	s[4] = b[0x400] | b[0x500] << 8 | b[0x600] << 16 | (r32)b[0x700] << 24;
	s[5] = *beam;
	s[6] = ++rand_calls;
	s[7] = what;
	rand_absorb(s, 32);
}

/*ARGSUSED*/
static int
randopen(devp, flag, otyp, cr)
dev_t *devp;
int flag, otyp;
struct cred *cr;
{
	if (getminor(*devp) >= RAND_NMINOR)
		return ENXIO;
	rand_stir((r32)getminor(*devp));
	return 0;
}

/*ARGSUSED*/
static int
randclose(dev, flag, otyp, cr)
dev_t dev;
int flag, otyp;
struct cred *cr;
{
	return 0;
}

/*ARGSUSED*/
static int
randread(dev, uiop, cr)
dev_t dev;
struct uio *uiop;
struct cred *cr;
{
	r32 buf[RAND_BUF / 4];
	int n, i, error = 0;

	if (getminor(dev) >= RAND_NMINOR)
		return ENXIO;
	rand_stir((r32)uiop->uio_resid);
	while (uiop->uio_resid > 0) {
		n = uiop->uio_resid < RAND_BUF ? uiop->uio_resid : RAND_BUF;
		if (rand_ctr >= RAND_REKEY)
			rand_newkey(rand_ctr, RAND_NKEY, 0);
		for (i = 0; i < n; i += 64)
			rand_block(rand_key, rand_ctr++, 0, 0, 0, buf + i / 4);
		if ((error = uiomove((caddr_t)buf, n, UIO_READ, uiop)) != 0)
			break;
	}
	rand_newkey(rand_ctr, RAND_NKEY, 0);
	for (i = 0; i < RAND_BUF / 4; i++)
		buf[i] = 0;
	return error;
}

/*ARGSUSED*/
static int
randwrite(dev, uiop, cr)
dev_t dev;
struct uio *uiop;
struct cred *cr;
{
	r32 buf[8];
	int n, i, error = 0;

	if (getminor(dev) >= RAND_NMINOR)
		return ENXIO;
	while (uiop->uio_resid > 0) {
		n = uiop->uio_resid < 32 ? uiop->uio_resid : 32;
		for (i = 0; i < 8; i++)
			buf[i] = 0;
		if ((error = uiomove((caddr_t)buf, n, UIO_WRITE, uiop)) != 0)
			break;
		rand_absorb(buf, (r32)n);
	}
	for (i = 0; i < 8; i++)
		buf[i] = 0;
	return error;
}

static int
random_load(params)
char *params;
{
	rand_stir((r32)(unsigned long)rand_key);
	return 0;
}

/*
 * unload=never: moduload never calls this, but the core does when the load fails after
 * _load returned 0 (C3-6 section 1.1).  Nothing is registered anywhere; the key goes.
 */
static int
random_unload()
{
	int i;

	for (i = 0; i < 8; i++)
		rand_key[i] = 0;
	rand_ctr = 0;
	return 0;
}

struct mod_drv_data random_drvdata[] = {
	{ { 0 }, 0, 0,
	  { randopen, randclose, randread, randwrite },
	  RAND_MAJOR, 1 }
};

/* _halt: none: nothing here interrupts or writes memory on its own. */
MOD_DRV_WRAPPER(random, random_load, random_unload, 0, "random numbers /dev/random, /dev/urandom");
