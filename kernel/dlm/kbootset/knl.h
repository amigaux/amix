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

/*
 * Build the namelist of a kernel bound at bind.  The symbols come from
 * sym (slen bytes) when it is given: an ELF whose symbol values are
 * addresses with the kernel bound at 0 (C2-3 §2.1, unix.sym); otherwise
 * from kern, an ET_REL kernel, laid out by the loader's own relocator.
 * On success 0, *out (malloc'd, *olen bytes) and *lay; else -1 and why.
 */
int kb_namelist(const ax_u8 *kern, ax_u32 klen, const ax_u8 *sym, ax_u32 slen, ax_u32 bind,
		struct kb_layout *lay, ax_u8 **out, ax_u32 *olen, char why[120]);

#endif
