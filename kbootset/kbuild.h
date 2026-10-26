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

/* the kernel's sidecar (C2-3 §2; a module kernel's, version 5: C3-3 §3) */
struct kb_kernel {
	char kabi[24], family[32], line[8], pin[48], build[48], sha256[65];
	char root[256], rootfs[64];
	ax_u32 size, loader_min, arena_off, arena_cap, ident_off;
	ax_u32 bss;		/* bytes past the image to the kernel's end: a brel
				 * kernel does not record them (C2-3 §2) */
	int has_arena, has_ident;
	int brel;		/* the kernel file is a brel (ELF type 0xff00) */
};

/* compose the next generation under root (the box: "/") into
 * root/stand/gen/<id>/: `build` (the generation's records and members) and
 * `facts` (what the gates were run against); every gate is run; nothing is
 * written to the store */
int kb_build(struct ks *k, const char *root, const struct kb_facts *f, ax_u32 created,
	     ax_u32 *id);

/* commit the generation built for the store's next id: the gates run again
 * against its files as they are now, then ks_commit.  When it equals the
 * default generation (members by size and SHA-256, the facts, the
 * parameters) nothing is written and KS_OK returned, unless again is set
 * (C2-4 §3: a repair, or a row that needs the generation) */
int kb_commit(struct ks *k, const char *root, ax_u32 *id, int again);

/* a new medium's pristine generation (host media builds, S2-04): every
 * gate, against the loader version the medium carries, then the
 * generation as a mkstore spec in out (paths under root; members deflated
 * when deflate is set; ramdisk, if given, as its RAM disk); msg the refusal;
 * returns kbootset's exit status (0, 3 or 4) */
int kb_spec(const char *root, const struct kb_facts *f, ax_u32 loader_version, ax_u32 created,
	    int deflate, const char *ramdisk, char *out, char *msg);

/* the root-side half of `kbootset check` (C2-5), never writing: the
 * boot- and demand-class files the manifests name under root, and the
 * default generation's kernel against the installed kernel package;
 * skipped when root holds no apkg records; returns the number of problems */
int kb_check(struct ks *k, const char *root, void (*say)(const char *line));

#endif
