/*
 * u2kva.c -- U2 (amix-dlm docs/spec/90-measurements.md): how much kernel
 * memory the module core could take for copied modules.  Its _load takes
 * kmem_zalloc chunks (the core's own allocator for module images) with
 * KM_NOSLEEP until one fails or the table is full, prints the count, the
 * bytes and the address range, and gives every chunk back before it
 * returns.  Run it on a quiet box: for that moment the kernel has no
 * memory to spare.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "sys/types.h"
#include "sys/kmem.h"
#include "sys/moddefs.h"
#include "sys/amixddi.h"

extern int	printf();

#define	NCHUNK	2048

static char	*u2kva_chunk[NCHUNK];

static long
u2kva_param(params, key, def)
	char *params, *key;
	long def;
{
	char *p;
	int n = strlen(key);
	long v = 0;

	for (p = params; p && *p; p++)
		if (strncmp(p, key, n) == 0 && p[n] == '=' && (p == params || p[-1] == ' ')) {
			for (p += n + 1; *p >= '0' && *p <= '9'; p++)
				v = v * 10 + (*p - '0');
			return v;
		}
	return def;
}

static int
u2kva_load(params)
	char *params;
{
	long size = u2kva_param(params, "kib", 64L) * 1024L;
	unsigned long lo = 0xffffffffUL, hi = 0;
	int n, i;

	for (n = 0; n < NCHUNK; n++) {
		if ((u2kva_chunk[n] = (char *)kmem_zalloc((size_t)size, KM_NOSLEEP)) == 0)
			break;
		if ((unsigned long)u2kva_chunk[n] < lo)
			lo = (unsigned long)u2kva_chunk[n];
		if ((unsigned long)u2kva_chunk[n] + size > hi)
			hi = (unsigned long)u2kva_chunk[n] + size;
	}
	printf("u2kva: %d chunks of %d bytes (%d KiB) with KM_NOSLEEP%s, from 0x%x to 0x%x\n", n,
	    (int)size, (int)(n * (size / 1024)), n == NCHUNK ? " (the table's limit)" : "",
	    (int)lo, (int)hi);
	for (i = 0; i < n; i++)
		kmem_free(u2kva_chunk[i], (size_t)size);
	printf("u2kva: all %d given back\n", n);
	return 0;
}

static int
u2kva_unload()
{
	return 0;
}

MOD_MISC_WRAPPER(u2kva, u2kva_load, u2kva_unload, "U2 kernel memory probe");
