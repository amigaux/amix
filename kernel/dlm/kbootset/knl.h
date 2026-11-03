/*
 * knl.h -- the booted kernel's namelist (docs/spec/40-generations-and-
 * composer.md §4.2, docs/contracts/C2-4-kbootset-cli.md §12): an ELF32
 * ET_EXEC holding the kernel's symbol table at the addresses of this boot,
 * for the stock nlist consumers that read /stand/unix.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KNL_H
#define KNL_H

#include "axtypes.h"

/* where the namelist's sections lie: text, rodata, data, bss (0 = none) */
struct kb_layout {
	ax_u32 entry;
	ax_u32 vaddr[4], size[4];
};

/* what a namelist carries beyond the kernel's own symbols (0: nothing) */
struct kb_nlsym {
	const char *name;
	ax_u32 value, size;
	ax_u8 info;			/* st_info: binding and type */
};
struct kb_nlx {
	int nsym;
	const struct kb_nlsym *sym;	/* the loaded modules' globals, at their addresses */
	/* reads n bytes of the running kernel at addr into buf: 0, or -1 */
	int (*mem)(void *ctx, ax_u32 addr, ax_u8 *buf, ax_u32 n);
	void *ctx;
};

/*
 * Build the namelist of a kernel bound at bind.  The symbols come from
 * sym (slen bytes) when it is given: an ELF whose symbol values are
 * addresses with the kernel bound at 0 (C2-3 §2.1, unix.sym); otherwise
 * from kern, an ET_REL kernel, laid out by the loader's own relocator.
 * x (or 0) adds symbols, and gives crash_sync's contents (see knl.c).
 * On success 0, *out (malloc'd, *olen bytes) and *lay; else -1 and why.
 */
int kb_namelist(const ax_u8 *kern, ax_u32 klen, const ax_u8 *sym, ax_u32 slen, ax_u32 bind,
		const struct kb_nlx *x, struct kb_layout *lay, ax_u8 **out, ax_u32 *olen, char why[120]);

#endif
