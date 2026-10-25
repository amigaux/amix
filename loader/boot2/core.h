/*
 * core.h -- what boot2 does once it knows how to read its medium
 * (docs/spec/10-boot-loader.md §3.2, §5-§7): choose the generation, load
 * and check the kernel, build bootinfo, hand over.  Two media use it: the
 * boot store behind boot1 (main.c) and files through dos.library on a CD
 * (cdmain.c, §4.4).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef CORE_H
#define CORE_H

#include "store.h"
#include "manifest.h"
#include "bootinfo.h"

struct medium {
	int readonly;			/* no trial, no one-shot, no writes */
	/* read mb->stored bytes of a member into dst; 0, or a fail() code */
	int (*read_stored)(const struct ax_member *mb, ax_u8 *dst);
	/* the manifest of generation g into a new buffer of g->man_len bytes */
	ax_u8 *(*read_manifest)(const struct ax_gen *g);
	/* write the control block (0 ok), or 0 for none */
	int (*write_ctl)(const struct ax_ctl *c);
	/* stop the device before the hand-off (floppy motor), or 0 */
	void (*quiesce)(void);
	/* RTH1 boot fields and the loader record's boot-device fields */
	void (*identify)(ax_u32 *flags, ax_u32 *unit, ax_u32 *base, ax_u32 *id,
			 struct ax_loaderrec *lr);
	/* a word that boot1 handed over, for the loader record (0 on a CD) */
	ax_u32 choice;
};

extern ax_u32 *ax_crctab;
extern ax_u32 core_cpu;

void fail(int code, ax_u32 gen);
/* allocate the working state, init CRC, probe the CPU; 0 or -1 */
int core_init(void);
/* boot from the control block c; returns only on failure */
long core_boot(const struct medium *m, const struct ax_ctl *c, void *replyport);

#endif
