/*
 * t43rel.c -- S3-43: the relocation oracle's module.  Its image holds
 * absolute references to its own text, data and strings and to kernel
 * names (printf, lbolt, bootinfo, kmem_zalloc), and nothing in it is
 * written after the load, so the bytes the core left in memory can be
 * compared with the host loader's image at the same base.  t43rel_first
 * is the first thing in its text, so `modadmin -p t43rel_first:64` reads
 * the image from its base.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();
extern char	*kmem_zalloc();
extern long	lbolt;
extern char	bootinfo[];

int
t43rel_first()
{
	return 0x7465;
}

static int t43rel_load(), t43rel_unload();

static char	t43rel_msg[] = "t43rel: loaded";
static long	t43rel_word = 0x12345678;
int (*t43rel_fns[])() = { t43rel_first, t43rel_load, t43rel_unload };
char *t43rel_refs[] = { t43rel_msg, (char *)&t43rel_word, (char *)&lbolt, bootinfo + 0x650,
	(char *)printf, (char *)kmem_zalloc };

static int
t43rel_load(params)
	char *params;
{
	printf("%s at 0x%x\n", t43rel_msg, (int)t43rel_first);
	return 0;
}

static int
t43rel_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(t43rel, t43rel_load, t43rel_unload, "S3-43 relocation oracle");
