/*
 * store.h -- the boot store: on-medium layout of the Amix boot slice
 * (docs/spec/10-boot-loader.md §4.2).  Shared by boot2, the host tools and
 * kbootset.  All multi-byte fields are big-endian; every structure is
 * parsed from and written to a byte buffer, never overlaid on it.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef STORE_H
#define STORE_H

#include "axtypes.h"

/* fixed layout of a store (offsets from the start of the partition) */
#define AX_BOOT1_OFF	0x0000UL
#define AX_BOOT1_MAX	1024UL
#define AX_HDR_A_OFF	0x0400UL
#define AX_HDR_B_OFF	0x0600UL
#define AX_HDR_SIZE	512UL
#define AX_BOOT2_A_OFF	0x0800UL
#define AX_BOOT2_MAX	(28UL * 1024UL)
#define AX_LOADER_VERSION	3	/* boot2's version, as the header records it and
				 * a manifest's loader-min asks for (10 §5.1):
				 * 2 the arena (stage 3), 3 root-class modules
				 * placed in it (S4-10) */
#define AX_LOADER_ROOT		3	/* the loader-min of a generation with a
				 * root-class record */
#define AX_TALLY_OFF	0x7800UL
#define AX_BOOT2_B_OFF	0x8000UL
#define AX_CTL_A_OFF	0xF000UL
#define AX_CTL_B_OFF	0xF800UL
#define AX_BLK		2048UL	/* every read and every extent: aligned to this */
#define AX_DATA_OFF	0x10000UL
/* multi-volume stores (§4.3): data on volumes after the first starts here,
 * and an extent that runs past the end of its volume continues here on the
 * next volume */
#define AX_VOLN_DATA	0x0800UL

#define AX_MAGIC_HDR	0x41585331UL	/* "AXS1" */
#define AX_MAGIC_TALLY	0x41585431UL	/* "AXT1" */
#define AX_MAGIC_CTL	0x41584331UL	/* "AXC1" */
#define AX_STORE_VERSION 1

/* header flags */
#define AXF_WRITABLE	0x0001UL
#define AXF_READONLY	0x0002UL
#define AXF_MULTIVOL	0x0004UL
#define AXF_LDRTRIAL	0x0008UL	/* the primary boot2 is on trial */

/* medium types */
#define AXM_DISK	0
#define AXM_FLOPPY	1
#define AXM_CDRDB	2

struct ax_extent {
	ax_u32 off;		/* bytes from the partition start, AX_BLK-aligned */
	ax_u32 len;		/* bytes; reads round up to AX_BLK */
	ax_u32 crc;		/* CRC-32 of the len bytes */
	ax_u32 ver;		/* loader version (boot2 extents only) */
};

struct ax_header {
	ax_u32 magic;
	ax_u16 version;
	ax_u16 hdrlen;
	ax_u32 seq;
	ax_u32 store_size;
	ax_u32 flags;
	ax_u16 volume;		/* 1-based */
	ax_u16 nvolumes;
	ax_u32 set_id;
	struct ax_extent boot2[2];	/* [0] primary, [1] secondary */
	ax_u32 ctl_off[2];
	ax_u32 tally_off;
	ax_u32 medium;
};

struct ax_tally {
	ax_u32 magic;
	ax_u32 hdr_seq;		/* the header sequence number it refers to */
	ax_u32 attempts;
};

/* generation states */
#define AXG_FREE	0
#define AXG_PRISTINE	1
#define AXG_GOOD	2
#define AXG_TRIAL	3
#define AXG_BAD		4

/* one-shot requests */
#define AXO_NONE	0
#define AXO_PREVIOUS	1
#define AXO_GEN		2
#define AXO_SAFE	3
#define AXO_DEVLOAD	4

#define AX_MAXGEN	16

struct ax_gen {
	ax_u32 id;
	ax_u8 state;
	ax_u8 flags;
	ax_u8 attempts;
	ax_u16 volume;		/* volume holding the manifest (1-based) */
	ax_u32 man_off;
	ax_u32 man_len;
	ax_u32 man_crc;
	ax_u32 created;		/* seconds since 1970-01-01 UTC */
};

#define AXC_SERIAL	0x0001	/* console flags */
#define AXC_SCREEN	0x0002

struct ax_ctl {
	ax_u32 magic;
	ax_u16 version;
	ax_u16 ngen;
	ax_u32 seq;
	ax_u32 default_gen;
	ax_u32 trial_gen;
	ax_u8 oneshot;
	ax_u32 oneshot_gen;
	ax_u16 menu_ds;		/* menu window in tenths of a second */
	ax_u16 console;
	ax_u32 serial_baud;
	/* the highest generation id ever issued on this store, so an id is
	 * never reused after its generation is collected (0 in a block written
	 * before the field: then the highest id present) */
	ax_u32 last_id;
	struct ax_gen gen[AX_MAXGEN];
};

/* parse results */
#define AX_OK		0
#define AX_EMAGIC	(-1)
#define AX_ECRC		(-2)
#define AX_EVERSION	(-3)
#define AX_ERANGE	(-4)
#define AX_ENONE	(-5)	/* no valid copy */

/* serial-number comparison: nonzero when a is newer than b */
#define AX_SEQ_NEWER(a, b) ((ax_s32)((ax_u32)(a) - (ax_u32)(b)) > 0)

int ax_hdr_parse(const ax_u32 *crctab, const ax_u8 buf[512], struct ax_header *h);
void ax_hdr_write(const ax_u32 *crctab, const struct ax_header *h, ax_u8 buf[512]);
/* pick the valid header copy with the newer sequence number; returns 0 or 1
 * for the copy taken, or AX_ENONE */
int ax_hdr_pick(const ax_u32 *crctab, const ax_u8 a[512], const ax_u8 b[512],
		struct ax_header *h);

int ax_tally_parse(const ax_u32 *crctab, const ax_u8 buf[2048], struct ax_tally *t);
void ax_tally_write(const ax_u32 *crctab, const struct ax_tally *t, ax_u8 buf[2048]);

int ax_ctl_parse(const ax_u32 *crctab, const ax_u8 buf[2048], struct ax_ctl *c);
void ax_ctl_write(const ax_u32 *crctab, const struct ax_ctl *c, ax_u8 buf[2048]);
int ax_ctl_pick(const ax_u32 *crctab, const ax_u8 a[2048], const ax_u8 b[2048],
		struct ax_ctl *c);	/* *c is undefined when it returns AX_ENONE */

/* the boot1 decision for a loader trial (docs/spec/10-boot-loader.md §3.1):
 * returns 0 to take the primary boot2, 1 for the secondary; *write_tally is
 * set when the tally must be written (attempt recorded) before the jump */
int ax_ldrtrial_choice(const struct ax_header *h, int tally_valid,
		       const struct ax_tally *t, int *write_tally);

#endif
