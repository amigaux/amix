/*
 * axtime.c -- M-LD7 and M-LD8 on the Amiga itself: how long the loader's
 * CRC-32, a SHA-256 and the raw-deflate decoder take over a kernel-sized
 * file on this CPU (docs/spec/90-measurements.md; docs/plan/stage-1.md
 * S1-23).  An AmigaDOS program (cross-built with gcc-cross-amix, written as
 * a load file by b2link -h), run from a shell under AmigaOS: the same C the
 * loader runs, timed with the E-clock under Forbid, interrupts on as during
 * a boot.
 *
 * usage: axtime FILE           CRC-32, SHA-256 and a copy over FILE
 *        axtime FILE SIZE      FILE is raw deflate of SIZE bytes: inflate
 *                              it, then the same over the inflated bytes
 *
 * Prints one line per step (E-clock ticks, milliseconds, KiB/s) and the
 * CRC-32 and SHA-256 found, to compare with the host.  Return code 0, or
 * 20 when the file cannot be read, memory is short or the inflate fails.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "crc32.h"
#include "sha256.h"
#include "inflate.h"

#define MODE_OLDFILE	1005
#define OFFSET_BEGINNING (-1)
#define OFFSET_END	1
#define RETURN_FAIL	20

static void *dosbase, *timerbase;
static ax_u32 efreq;		/* E-clock ticks per second */
static long out;		/* the CLI's output file handle */

static long
dos(long lvo, ax_u32 d1, ax_u32 d2, ax_u32 d3)
{
	struct ax_regs r;

	REGS0(r);
	r.d1 = d1, r.d2 = d2, r.d3 = d3;
	return ax_call(dosbase, lvo, &r);
}

static void
put(const char *s)
{
	ax_u32 n = 0;

	while (s[n])
		n++;
	dos(-48, (ax_u32)out, (ax_u32)s, n);	/* Write */
}

static void
putu(ax_u32 v)
{
	char b[12];
	int n = 11;

	b[11] = 0;
	do {
		b[--n] = (char)('0' + v % 10);
		v /= 10;
	} while (v);
	put(b + n);
}

static void
puthex(const ax_u8 *p, int n)
{
	static const char x[] = "0123456789abcdef";
	char b[3];

	b[2] = 0;
	while (n--) {
		b[0] = x[*p >> 4], b[1] = x[*p++ & 15];
		put(b);
	}
}

/* the low 32 bits of the E-clock (wraps after about 100 minutes) */
static ax_u32
eclock(void)
{
	ax_u32 ev[2];
	struct ax_regs r;

	REGS0(r);
	r.a0 = (ax_u32)ev;
	efreq = (ax_u32)ax_call(timerbase, -60, &r);	/* ReadEClock */
	return ev[1];
}

/* one result line: ticks, milliseconds and KiB/s over len bytes */
static void
report(const char *what, ax_u32 t0, ax_u32 t1, ax_u32 len)
{
	ax_u32 ticks = t1 - t0, ms = ticks / (efreq / 1000);

	put("axtime: ");
	put(what);
	put(" ");
	putu(ticks);
	put(" ticks, ");
	putu(ms);
	put(" ms");
	if (ms) {
		put(", ");
		putu(len / 1024 * 1000 / ms);
		put(" KiB/s");
	}
	put("\n");
}

static ax_u32
number(const char *s, int n)
{
	ax_u32 v = 0;

	while (n-- > 0 && *s >= '0' && *s <= '9')
		v = v * 10 + (ax_u32)(*s++ - '0');
	return v;
}

/* from adstart.s */
long
ados_main(void *execbase, const char *args, long arglen)
{
	/* the tables in allocated memory, as boot2 keeps them (its work area),
	 * so a chip-memory build (b2link -c) moves only the code */
	ax_u32 *tab;
	struct ax_inflate *inf;
	static ax_u8 tr[40];		/* a timerequest */
	struct ax_sha256 sh;
	ax_u8 digest[32], *buf, *data, *copy;
	char name[128];
	ax_u32 len, size = 0, t0, crc, got;
	ax_u16 attn;
	long fh;
	int i = 0, n;

	ax_execbase = execbase;
	dosbase = x_openlib("dos.library", 36);
	if (!dosbase)
		return RETURN_FAIL;
	out = dos(-60, 0, 0, 0);			/* Output */
	while (i < arglen && args[i] == ' ')
		i++;
	for (n = 0; i < arglen && args[i] > ' ' && n < 127; )
		name[n++] = args[i++];
	name[n] = 0;
	while (i < arglen && args[i] == ' ')
		i++;
	if (i < arglen)
		size = number(args + i, (int)(arglen - i));
	if (!n) {
		put("usage: axtime FILE [SIZE]\n");
		return RETURN_FAIL;
	}
	if (x_opendevice("timer.device", 0, tr, 0) != 0) {
		put("axtime: no timer.device\n");
		return RETURN_FAIL;
	}
	timerbase = *(void **)(tr + IO_DEVICE);

	fh = dos(-30, (ax_u32)name, MODE_OLDFILE, 0);	/* Open */
	if (!fh) {
		put("axtime: cannot open the file\n");
		return RETURN_FAIL;
	}
	dos(-66, (ax_u32)fh, 0, OFFSET_END);		/* Seek */
	len = (ax_u32)dos(-66, (ax_u32)fh, 0, OFFSET_BEGINNING);
	buf = x_allocmem(len ? len : 1, MEMF_PUBLIC);
	if (!buf || dos(-42, (ax_u32)fh, (ax_u32)buf, len) != (long)len) {	/* Read */
		put("axtime: cannot read the file\n");
		return RETURN_FAIL;
	}
	dos(-36, (ax_u32)fh, 0, 0);			/* Close */

	tab = x_allocmem(256 * 4, MEMF_PUBLIC);
	inf = x_allocmem(sizeof(*inf), MEMF_PUBLIC);
	if (!tab || !inf) {
		put("axtime: no memory for the tables\n");
		return RETURN_FAIL;
	}
	attn = *(ax_u16 *)((ax_u8 *)execbase + EXEC_ATTNFLAGS);
	eclock();
	put("axtime: ");
	put(name);
	put(", ");
	putu(len);
	put(" bytes, 680");
	put(attn & 0x80 ? "60" : attn & 0x08 ? "40" : attn & 0x04 ? "30" : "20");
	put(", code at 0x");
	{
		static const char x[] = "0123456789abcdef";
		char a[9];
		ax_u32 v = (ax_u32)ados_main;
		int i;

		for (i = 7; i >= 0; i--, v >>= 4)
			a[i] = x[v & 15];
		a[8] = 0;
		put(a);
	}
	put(", E-clock ");
	putu(efreq);
	put(" Hz\n");

	data = buf;
	if (size) {
		data = x_allocmem(size, MEMF_PUBLIC);
		if (!data) {
			put("axtime: no memory for the inflated bytes\n");
			return RETURN_FAIL;
		}
		x_forbid();
		t0 = eclock();
		n = ax_inflate(inf, data, size, &got, buf, len);
		report("inflate", t0, eclock(), size);
		x_permit();
		if (n != AXI_OK || got != size) {
			put("axtime: inflate failed\n");
			return RETURN_FAIL;
		}
		len = size;
	}

	x_forbid();
	t0 = eclock();
	ax_crc32_init(tab);
	report("crc32-table", t0, eclock(), 1024);
	t0 = eclock();
	crc = ax_crc32(tab, data, len);
	report("crc32", t0, eclock(), len);
	t0 = eclock();
	ax_sha256_init(&sh);
	ax_sha256_update(&sh, data, len);
	ax_sha256_final(&sh, digest);
	report("sha256", t0, eclock(), len);
	x_permit();

	copy = x_allocmem(len ? len : 1, MEMF_PUBLIC);
	if (copy) {
		x_forbid();
		t0 = eclock();
		x_memcpy(copy, data, len);
		report("copy", t0, eclock(), len);
		x_permit();
		x_freemem(copy, len ? len : 1);
	}

	put("axtime: crc32 ");
	puthex((const ax_u8 *)&crc, 4);		/* big-endian: the bytes are the number */
	put(", sha256 ");
	puthex(digest, 32);
	put("\n");
	x_closedevice(tr);
	return 0;
}
