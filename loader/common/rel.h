/*
 * rel.h -- relocate an Amix kernel image in place for its bind address and
 * describe where its segments go (docs/spec/10-boot-loader.md §2.2).
 *
 * Three kernel forms, with the stock loader's semantics:
 *   ET_REL     sections picked by flags (executable PROGBITS = text, other
 *              writable PROGBITS = data, other PROGBITS = rodata, writable
 *              NOBITS = bss; the last of each kind wins), bound contiguously
 *              text, rodata, data, bss from the bind address with no padding;
 *              COMMON symbols placed after bss at their alignment; etext,
 *              edata and end made absolute; R_68K_32 = S + A, and with
 *              pcrel_ok also R_68K_PC32/PC16/PC8 = S + A - P, range-checked.
 *   brel       e_type 0xff00: section 1 is the combined text, section 3 a
 *              table of (offset, value) pairs; bit 31 of offset set = value is
 *              absolute, else value + bind address.
 *   ET_EXEC    the first program header gives the segment; nothing is
 *              relocated.
 * Unlike the stock loader, every offset is bounds-checked and every error is
 * reported instead of written through.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef REL_H
#define REL_H

#include "axtypes.h"

/* the kernel's struct BootData plus the end of the bound image */
struct ax_bootdata {
	ax_u32 entry;
	ax_u32 tvaddr, toffset, tsize;
	ax_u32 rvaddr, roffset, rsize;
	ax_u32 dvaddr, doffset, dsize;
	ax_u32 end;		/* first address past text..bss and COMMON */
};

#define AXR_OK		0
#define AXR_EFORMAT	(-1)	/* not a big-endian m68k ELF of a known type */
#define AXR_EBOUNDS	(-2)	/* a header, table or field lies outside the image */
#define AXR_ENOSECT	(-3)	/* no text section or no symbol table */
#define AXR_ESYMBOL	(-4)	/* symbol in an unbound section, or undefined */
#define AXR_ETYPE	(-5)	/* relocation type not handled */
#define AXR_ERANGE	(-6)	/* PC-relative displacement does not fit */

struct ax_relerr {
	ax_u32 rsect;		/* relocation section index */
	ax_u32 index;		/* record number within it */
	ax_u32 type;		/* relocation type */
	ax_u32 sym;		/* symbol index */
};

int ax_rel(ax_u8 *img, ax_u32 len, ax_u32 vaddr, int pcrel_ok,
	   struct ax_bootdata *bd, struct ax_relerr *err);

/* as ax_rel, and call note(ctx, off) for every 32-bit field that holds a
 * bind-address-relative value (off counted from vaddr), so a host tool can
 * emit a self-relocation table; absolute values are not reported */
typedef void (*ax_relnote)(void *ctx, ax_u32 off);
int ax_rel_ex(ax_u8 *img, ax_u32 len, ax_u32 vaddr, int pcrel_ok,
	      struct ax_bootdata *bd, struct ax_relerr *err, ax_relnote note, void *ctx);

#endif
