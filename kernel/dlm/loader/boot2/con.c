/*
 * con.c -- the loader console (docs/spec/10-boot-loader.md §3.2, §8):
 * every line goes to the serial port, and to an Intuition screen once
 * con_screen() has opened one.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdarg.h>
#include "b2.h"

#define SERDATR	(*(volatile ax_u16 *)0xDFF018)
#define SERDAT	(*(volatile ax_u16 *)0xDFF030)
#define SERPER	(*(volatile ax_u16 *)0xDFF032)

#define COLS	78
#define ROWH	9		/* topaz 8 plus one line of spacing */
#define TOP	12
#define ROWS	20

static void *gfx, *screen, *rp;
static char line[COLS + 1];
static int col, row;

static void
ser_putc(int c)
{
	while (!(SERDATR & 0x2000))
		;
	SERDAT = (ax_u16)(0x100 | (c & 0xFF));
}

static void
gcall(long lvo, ax_u32 d0, ax_u32 d1, ax_u32 a0)
{
	struct ax_regs r;

	REGS0(r);
	r.a1 = (ax_u32)rp, r.d0 = d0, r.d1 = d1, r.a0 = a0;
	ax_call(gfx, lvo, &r);
}

static void
scr_line(void)
{
	struct ax_regs r;

	if (!rp)
		return;
	if (row == ROWS) {
		REGS0(r);	/* ScrollRaster(rp, 0, ROWH, 0, TOP, 639, TOP + ROWS*ROWH - 1) */
		r.a1 = (ax_u32)rp, r.d1 = ROWH, r.d3 = TOP, r.d4 = 639, r.d5 = TOP + ROWS * ROWH - 1;
		ax_call(gfx, -396, &r);
		row = ROWS - 1;
	}
	gcall(-240, 8, TOP + row * ROWH + 6, 0);		/* Move */
	gcall(-60, (ax_u32)col, 0, (ax_u32)line);		/* Text */
	row++;
}

static void
putc_(int c)
{
	if (c == '\n') {
		ser_putc('\r');
		ser_putc('\n');
		line[col] = 0;
		scr_line();
		col = 0;
		return;
	}
	ser_putc(c);
	if (col < COLS)
		line[col++] = (char)c;
}

void
con_init(ax_u32 baud)
{
	/* the colour clock is 3.546895 MHz (PAL) or 3.579545 MHz (NTSC); the
	 * midpoint is within 0.5 % of both */
	if (baud < 1200)
		baud = 9600;
	SERPER = (ax_u16)(3563220UL / baud - 1);
}

/* a 640x200 hires screen, one bitplane; silently stays serial-only when
 * Intuition or graphics.library cannot be opened */
void
con_screen(void)
{
	static ax_u8 ns[32];
	void *intui;
	struct ax_regs r;

	intui = x_openlib("intuition.library", 33);
	gfx = x_openlib("graphics.library", 33);
	if (!intui || !gfx)
		return;
	x_memset(ns, 0, sizeof(ns));
	*(ax_u16 *)(ns + 4) = 640;		/* Width */
	*(ax_u16 *)(ns + 6) = 200;		/* Height */
	*(ax_u16 *)(ns + 8) = 1;		/* Depth */
	ns[11] = 1;				/* BlockPen */
	*(ax_u16 *)(ns + 12) = 0x8000;		/* ViewModes HIRES */
	*(ax_u16 *)(ns + 14) = 0x000F;		/* CUSTOMSCREEN */
	*(ax_u32 *)(ns + 20) = (ax_u32)"amix-boot";
	REGS0(r);
	r.a0 = (ax_u32)ns;
	screen = (void *)ax_call(intui, -198, &r);	/* OpenScreen */
	if (!screen)
		return;
	rp = (ax_u8 *)screen + 84;			/* sc_RastPort */
	gcall(-342, 1, 0, 0);				/* SetAPen(rp, 1) */
}

void
con_puts(const char *s)
{
	while (*s)
		putc_(*s++);
}

static void
putnum(ax_u32 v, int base, int width, int zero)
{
	char buf[12];
	int n = 0;

	do {
		buf[n++] = "0123456789abcdef"[v % base];
		v /= base;
	} while (v && n < 11);
	while (n < width && n < 11)
		buf[n++] = zero ? '0' : ' ';
	while (n)
		putc_(buf[--n]);
}

/* %s %c %u %d %x, with an optional zero flag and width: "%08x" */
static void
vout(const char *fmt, va_list ap)
{
	int width, zero;
	long d;

	for (; *fmt; fmt++) {
		if (*fmt != '%') {
			putc_(*fmt);
			continue;
		}
		fmt++;
		zero = *fmt == '0';
		for (width = 0; *fmt >= '0' && *fmt <= '9'; fmt++)
			width = width * 10 + (*fmt - '0');
		switch (*fmt) {
		case 's':
			con_puts(va_arg(ap, const char *));
			break;
		case 'c':
			putc_(va_arg(ap, int));
			break;
		case 'u':
			putnum(va_arg(ap, ax_u32), 10, width, zero);
			break;
		case 'd':
			d = va_arg(ap, long);
			if (d < 0) {
				putc_('-');
				d = -d;
			}
			putnum((ax_u32)d, 10, width, zero);
			break;
		case 'x':
			putnum(va_arg(ap, ax_u32), 16, width, zero);
			break;
		default:
			putc_(*fmt);
		}
	}
}

void
con_printf(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	vout(fmt, ap);
	va_end(ap);
}

/* a loader message (10 §9): the "amix-boot: " prefix, then as con_printf */
void
con_say(const char *fmt, ...)
{
	va_list ap;

	con_puts("amix-boot: ");
	va_start(ap, fmt);
	vout(fmt, ap);
	va_end(ap);
}
