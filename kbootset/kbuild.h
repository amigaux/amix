/*
 * kbuild.h -- `kbootset build` and the gates (docs/spec/40-generations-and-
 * composer.md §3, §3.1): compose the next generation from what the package
 * system installed under a root, refuse it at the first gate it fails, and
 * hand it to commit.  The inputs are the agreed contracts:
 * docs/contracts/C2-2-kpkg.md (apkg's install records) and
 * C2-3-packages.md (the kernel and its kabi sidecar).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef KBUILD_H
#define KBUILD_H

#include "ks.h"

/* the box the generation is for: from kinfo (C2-1) on the box, from the
 * command line on a host build; an unknown fact fails its gate */
struct kb_facts {
	int line;		/* 30 or 46; 0 unknown */
	char bootdev[48];	/* match key of the boot disk's controller ("zorro:0202:54") */
	char rootdev[48];	/* match key of the root disk's controller */
	char rootfs[16];	/* root filesystem type */
	ax_u32 mem;		/* fast memory in bytes; 0 unknown */
	char root[128];		/* the manifest's root record, or "": the default generation's */
	char swap[128];		/* the swap record, or "": the default generation's */
};

/* the kernel's sidecar (C2-3 §2) */
struct kb_kernel {
	char kabi[24], family[32], line[8], pin[48], build[48], sha256[65];
	char root[256], rootfs[64];
	ax_u32 size, loader_min, arena_off, arena_cap;
	int has_arena;
};

/* compose the next generation under root (the box: "/") into
 * root/stand/gen/<id>/: `build` (the generation's records and members) and
 * `facts` (what the gates were run against); every gate is run; nothing is
 * written to the store */
int kb_build(struct ks *k, const char *root, const struct kb_facts *f, ax_u32 created,
	     ax_u32 *id);

/* commit the generation built for the store's next id: the gates run again
 * against its files as they are now, then ks_commit */
int kb_commit(struct ks *k, const char *root, ax_u32 *id);

#endif
