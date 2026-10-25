/*
 * manifest.h -- the generation manifest, GMF1
 * (docs/spec/10-boot-loader.md §5.1).
 *
 * Plain ASCII, one record per line, each line at most 255 characters plus
 * the newline.  First line "GMF1"; last line "end crc32=XXXXXXXX", the
 * CRC-32 of every byte before that line.  A record whose key starts with
 * '!' must be understood: an unknown critical key refuses the manifest;
 * any other unknown key is ignored.
 *
 * The parser works in place on a writable buffer (it NUL-terminates tokens)
 * and allocates nothing; string fields point into the buffer.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef MANIFEST_H
#define MANIFEST_H

#include "axtypes.h"

#define AXM_MAXLINE	255
#define AXM_MAXMOD	32
#define AXM_MAXPARAM	32

/* member kinds and classes */
#define AXK_KERNEL	1
#define AXK_MODULE	2
#define AXK_RAMDISK	3
#define AXC_NONE	0
#define AXC_ROOT	1
#define AXC_BOOT	2
#define AXC_DEMAND	3
/* compression */
#define AXZ_NONE	0
#define AXZ_DEFLATE	1

struct ax_member {
	int kind;
	int cls;
	char *name;
	ax_u32 size;		/* bytes after decompression */
	int has_at;
	ax_u16 vol;		/* volume of the extent, 1-based */
	ax_u32 at;		/* store-relative offset (or 0 with path) */
	ax_u32 stored;		/* bytes as stored; = size when uncompressed */
	int z;
	int has_crc;
	ax_u32 crc;		/* CRC-32 of the decompressed bytes */
	char *sha256;		/* 64 hex digits, or 0 */
	char *match;		/* comma-separated match keys, or 0 */
	char *path;		/* root-filesystem path (boot/demand class), or 0 */
	char *file;		/* a file in the line directory (CD media), or 0 */
};

struct ax_manifest {
	ax_u32 generation;
	char *line;		/* "k30" or "k46" */
	char *kabi;
	char *cpu;		/* space-separated CPU list as written */
	ax_u32 loader_min;
	char *created;
	char *rootfs;
	char *root;		/* the rest of the root line, unparsed */
	char *swap;
	char *boards;
	int has_arena;
	ax_u32 arena_off, arena_cap;
	int has_kernel;
	struct ax_member kernel;
	int nmod;
	struct ax_member mod[AXM_MAXMOD];
	int has_ramdisk;
	struct ax_member ramdisk;
	int nparam;
	char *param[AXM_MAXPARAM];
	ax_u32 end_crc;
};

#define AXM_OK		0
#define AXM_EHEAD	(-1)	/* first line is not GMF1 */
#define AXM_ELONG	(-2)	/* a line is too long or has a bad character */
#define AXM_EEND	(-3)	/* no end line, or bytes after it */
#define AXM_ECRC	(-4)	/* end crc32 does not match */
#define AXM_ESYNTAX	(-5)	/* a record is malformed */
#define AXM_ECRIT	(-6)	/* an unknown critical ('!') key */
#define AXM_EMANY	(-7)	/* too many modules or parameters */
#define AXM_EMISSING	(-8)	/* a required record or attribute is missing */
#define AXM_EDUP	(-9)	/* a single-valued record appears twice */

/* parse buf[0..len); on error *errline is the 1-based line number */
int ax_manifest_parse(const ax_u32 *crctab, char *buf, ax_u32 len,
		      struct ax_manifest *m, int *errline);

#endif
