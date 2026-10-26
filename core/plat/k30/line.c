/*
 * line.c -- what the 030 line's kernels give the platform hook
 * (core/plat/amiga.c) and the DDI: their build id is kinfo_buildid, which
 * the kernel build stamps into the kinfo driver (amix-kerntools
 * src/kinfo030.c; the 030 kernel has no buildid string); and cputype, which
 * the 68040/68060 kernels define and the 030 kernels do not (DDI v1).
 * Both strong: a kernel that already has a cputype fails to link, which is
 * the moment to drop this one.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
extern char kinfo_buildid[];

long cputype = 30;

char *
plat_buildid(void)
{
	return kinfo_buildid;
}
