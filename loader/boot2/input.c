/*
 * input.c -- what the menu reads (docs/spec/10-boot-loader.md §7.4): the
 * keyboard matrix through keyboard.device, the mouse buttons from CIA-A
 * and POTGO, bytes from the serial port, and frame timing from the beam.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "input.h"

#define CIAAPRA	(*(volatile ax_u8 *)0xBFE001)
#define POTGOR	(*(volatile ax_u16 *)0xDFF016)
#define SERDATR	(*(volatile ax_u16 *)0xDFF018)
#define INTREQ	(*(volatile ax_u16 *)0xDFF09C)
#define VPOSR	(*(volatile ax_u16 *)0xDFF004)
#define VHPOSR	(*(volatile ax_u16 *)0xDFF006)
#define KBD_READMATRIX	10

static ax_u8 kreq[IOSTD_SIZE];
static int kopen;
static ax_u8 prev[16];

void
in_init(void *strap_iob)
{
	x_memset(kreq, 0, sizeof(kreq));
	/* the strap's reply port belongs to this task: reuse it */
	*(ax_u32 *)(kreq + 14) = *(ax_u32 *)((ax_u8 *)strap_iob + 14);
	*(ax_u16 *)(kreq + 18) = IOSTD_SIZE;
	kopen = x_opendevice("keyboard.device", 0, kreq, 0) == 0;
	in_matrix(prev);
}

void
in_matrix(ax_u8 m[16])
{
	x_memset(m, 0, 16);
	if (!kopen)
		return;
	*(ax_u16 *)(kreq + IO_COMMAND) = KBD_READMATRIX;
	*(ax_u32 *)(kreq + IO_LENGTH) = 13;	/* 13 bytes before V36, 16 after */
	*(ax_u32 *)(kreq + IO_DATA) = (ax_u32)m;
	x_doio(kreq);
}

/* a key newly pressed since the last call (qualifiers 0x60-0x67 ignored),
 * or -1 */
int
in_key(void)
{
	ax_u8 m[16];
	int i, b, k = -1;

	in_matrix(m);
	for (i = 0; i < 16 && k < 0; i++)
		for (b = 0; b < 8; b++)
			if ((m[i] & ~prev[i]) & (1 << b) && (i * 8 + b < 0x60 || i * 8 + b > 0x67)) {
				k = i * 8 + b;
				break;
			}
	x_memcpy(prev, m, 16);
	return k;
}

int
in_lmb(void)
{
	return !(CIAAPRA & 0x40);
}

int
in_serial(void)
{
	ax_u16 d = SERDATR;

	if (!(d & 0x4000))
		return -1;
	INTREQ = 0x0800;		/* clear RBF */
	return d & 0xFF;
}

/* raw key code to a menu character, or 0 */
int
in_char(int k)
{
	static const char digits[] = "1234567890";

	if (k >= 0x01 && k <= 0x0A)
		return digits[k - 1];
	switch (k) {
	case 0x1D: return '1';
	case 0x1E: return '2';
	case 0x1F: return '3';
	case 0x2D: return '4';
	case 0x2E: return '5';
	case 0x2F: return '6';
	case 0x3D: return '7';
	case 0x3E: return '8';
	case 0x3F: return '9';
	case 0x0F: return '0';
	case 0x19: return 'p';
	case 0x21: return 's';
	case 0x22: return 'd';
	case 0x13: return 'r';
	case 0x44: case 0x43: return '\r';
	case 0x40: return ' ';
	}
	return 0;
}

/* wait for the beam to start a new frame (about 1/50 or 1/60 s) */
void
in_frame(void)
{
	ax_u32 v;

	do
		v = ((VPOSR & 1) << 8) | (VHPOSR >> 8);
	while (v < 16);
	do
		v = ((VPOSR & 1) << 8) | (VHPOSR >> 8);
	while (v >= 16);
}
