/*
 * con.c -- the loader console: every line goes to the serial port; the
 * screen is added by the menu work (docs/plan/stage-1.md S1-14).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdarg.h>
#include "b2.h"

#define SERDATR	(*(volatile ax_u16 *)0xDFF018)
#define SERDAT	(*(volatile ax_u16 *)0xDFF030)
#define SERPER	(*(volatile ax_u16 *)0xDFF032)

static void
ser_putc(int c)
{
	while (!(SERDATR & 0x2000))
		;
	SERDAT = (ax_u16)(0x100 | (c & 0xFF));
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

void
con_puts(const char *s)
{
	for (; *s; s++) {
		if (*s == '\n')
			ser_putc('\r');
		ser_putc(*s);
	}
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
		ser_putc(buf[--n]);
}

/* %s %c %u %d %x, with an optional zero flag and width: "%08x" */
void
con_printf(const char *fmt, ...)
{
	va_list ap;
	int width, zero;
	long d;

	va_start(ap, fmt);
	for (; *fmt; fmt++) {
		if (*fmt != '%') {
			if (*fmt == '\n')
				ser_putc('\r');
			ser_putc(*fmt);
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
			ser_putc(va_arg(ap, int));
			break;
		case 'u':
			putnum(va_arg(ap, ax_u32), 10, width, zero);
			break;
		case 'd':
			d = va_arg(ap, long);
			if (d < 0) {
				ser_putc('-');
				d = -d;
			}
			putnum((ax_u32)d, 10, width, zero);
			break;
		case 'x':
			putnum(va_arg(ap, ax_u32), 16, width, zero);
			break;
		default:
			ser_putc(*fmt);
		}
	}
	va_end(ap);
}
