/*
 * libmod.c -- the module core's six system calls (sysent 64-69,
 * docs/spec/20-module-format-and-abi.md section 6) for the box's GCC 14
 * build of modadmin, through the stock libc's syscall(): the same calls
 * the core's libmod/ assembler stubs make for its gcc-cross-amix build.
 * Each retries while the kernel says ERESTART, as those do.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <errno.h>

extern int syscall();

#define	ERESTART	91	/* the Amix errno a system call restarts on */

int
modload(path)
	char *path;
{
	int r;

	while ((r = syscall(64, path)) < 0 && errno == ERESTART)
		;
	return r;
}

int
moduload(id)
	int id;
{
	int r;

	while ((r = syscall(65, id)) < 0 && errno == ERESTART)
		;
	return r;
}

int
modpath(path)
	char *path;
{
	int r;

	while ((r = syscall(66, path)) < 0 && errno == ERESTART)
		;
	return r;
}

int
modstat(id, st, mode)
	int id, mode;
	char *st;
{
	int r;

	while ((r = syscall(67, id, st, mode)) < 0 && errno == ERESTART)
		;
	return r;
}

int
modadm(type, cmd, data)
	int type, cmd;
	char *data;
{
	int r;

	while ((r = syscall(68, type, cmd, data)) < 0 && errno == ERESTART)
		;
	return r;
}

int
getksym(name, value, info)
	char *name;
	unsigned long *value, *info;
{
	int r;

	while ((r = syscall(69, name, value, info)) < 0 && errno == ERESTART)
		;
	return r;
}
