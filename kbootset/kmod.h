/*
 * kmod.h -- what kbootset reads from a module object (docs/contracts/
 * C3-1-module-object.md section 3): the .moddata version 2 keys, and the
 * text forms of parameter values (C3-1 section 3, C3-5 section 2).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KMOD_H
#define KMOD_H

#include "axtypes.h"

#define KM_MAXPARAM	16

struct km_param {
	char name[32];
	char type[5];		/* int, hex, bool, str */
	char def[64];		/* the default, as .moddata gives it */
	int has_range;
	long min, max;		/* int and hex */
};

struct km_info {
	char name[16], kabi[24], cc[48], cpu[8], cls[8];
	char match[256], majors[128], depend[128], unload[8], tier[8], build[48];
	char fs[16];		/* the type vfs_register takes (C4-6 section 3), or "" */
	int nparam;
	struct km_param param[KM_MAXPARAM];
};

/* the .moddata of the module object in b; 0, or -1 with why set (at most
 * 120 bytes): not ELF32 big-endian, no or two .moddata, not version 2, a
 * malformed key list, a required key missing, too many parameters */
int km_read(const ax_u8 *b, ax_u32 len, struct km_info *mi, char *why);

/* the tail a root-class module needs behind its file, its manifest
 * record's bss= (C3-5 section 3, C4-4 section 4): the NOBITS sections in
 * section order, each aligned to max(its alignment, 4), then every COMMON
 * symbol aligned to its own, from 0, as the module core lays them (core
 * patch 0033), rounded up to 4.  Every COMMON counts, so it is an upper
 * bound when the core resolves one against the kernel or a dependency.
 * 0 with *tail set, or -1 with why (at most 120 bytes): malformed headers
 * or symbols, an alignment above 16, or a PROGBITS section whose file
 * offset is not a multiple of its alignment (the core runs it in place) */
int km_tail(const ax_u8 *b, ax_u32 len, ax_u32 *tail, char *why);

/* each global symbol of the module object in b: fn(ctx, name, undef),
 * undef 1 for an import (SHN_UNDEF), 0 for a definition; fn returns
 * nonzero to stop.  0, or -1 with why set: not ELF32, a malformed symbol
 * table */
int km_syms(const ax_u8 *b, ax_u32 len, int (*fn)(void *, const char *, int), void *ctx,
	    char *why);

/* in, a parameter value as modreg.d gives it, in C3-1's form for p's type
 * into out (64 bytes): bool from 0/1, yes/no, true/false, on/off; int and
 * hex from either number form, written in the declared one and within
 * min..max; str one word of at most 63 bytes.  0, or -1 */
int km_value(const struct km_param *p, const char *in, char *out);

/* the character major registry (abi/registry/majors, kreg.c): the module
 * that owns major n of type 'c' or 'b', or 0 */
const char *km_owner(int type, int n);

#endif
