/*
 * line.c -- what the 68040/68060 line's kernels give the platform hook
 * (core/plat/amiga.c): their build id is the buildid string, which uname -m
 * shows.  cputype they define themselves, and dev_kvmap/dev_kvunmap are the
 * port's own (devkvmap040.o, linked by the kernel build).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
extern char buildid[];

char *
plat_buildid(void)
{
	return buildid;
}
