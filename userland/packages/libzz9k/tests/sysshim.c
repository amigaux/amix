/*
 * sysshim.c -- the system calls libzz9k makes, for its host test: open, close, ioctl, mmap,
 * munmap and fcntl of /dev/zz9ksvcN go to kern.c's zz9ksvc, everything else to the host's
 * kernel.  Defined in the test program, they take the place of the C library's for the
 * library's calls.  A device descriptor is closed the way specfs does it: d_close comes
 * only after the last close and the last unmap, so a library that closed before it
 * unmapped would leave an open behind, which the test sees.  An unmap must name exactly a
 * mapping that was made (spec_delmap counts in 2 KiB units per call).
 *
 * Copyright (c) 2026 Jussi Alanärä.  GPL-3.0-or-later, see LICENSE.
 */
#define _GNU_SOURCE
#include <stdarg.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <sys/types.h>

extern int kt_open(int), kt_close(int), kt_ioctl(int, int, void *);
extern void *kt_map(int, long, unsigned long);

#define SH_FD0	900
#define SH_NFD	32
#define SH_NMAP	128

static struct { int used, slot, closed; } sh_fd[SH_NFD];
static struct { void *addr; size_t len; int fd; } sh_map[SH_NMAP];
int sh_bad;		/* unmaps that matched no mapping, or not its whole length */
int sh_maps;		/* mappings made, ever */

static int
fake(int fd)
{
	return fd >= SH_FD0 && fd < SH_FD0 + SH_NFD && sh_fd[fd - SH_FD0].used;
}

int
sh_maps_live(void)
{
	int i, n = 0;

	for (i = 0; i < SH_NMAP; i++)
		if (sh_map[i].addr)
			n++;
	return n;
}

int
sh_fds_live(void)
{
	int i, n = 0;

	for (i = 0; i < SH_NFD; i++)
		if (sh_fd[i].used)
			n++;
	return n;
}

/* d_close once a closed descriptor has no mapping left */
static void
settle(int i)
{
	int m;

	if (!sh_fd[i].used || !sh_fd[i].closed)
		return;
	for (m = 0; m < SH_NMAP; m++)
		if (sh_map[m].addr && sh_map[m].fd == i)
			return;
	kt_close(sh_fd[i].slot);
	sh_fd[i].used = 0;
}

int
open(const char *path, int flags, ...)
{
	va_list ap;
	mode_t mode = 0;
	int unit, s, i;

	if (strncmp(path, "/dev/zz9ksvc", 12) == 0) {
		unit = path[12] - '0';
		if (unit < 0 || unit > 9 || path[13] != '\0') {
			errno = ENOENT;
			return -1;
		}
		if ((s = kt_open(unit)) < 0) {
			errno = -s;
			return -1;
		}
		for (i = 0; i < SH_NFD; i++)
			if (!sh_fd[i].used) {
				sh_fd[i].used = 1;
				sh_fd[i].slot = s;
				sh_fd[i].closed = 0;
				return SH_FD0 + i;
			}
		kt_close(s);
		errno = EMFILE;
		return -1;
	}
	if (flags & O_CREAT) {
		va_start(ap, flags);
		mode = va_arg(ap, mode_t);
		va_end(ap);
	}
	return (int)syscall(SYS_openat, AT_FDCWD, path, flags, mode);
}

int
close(int fd)
{
	if (fake(fd)) {
		sh_fd[fd - SH_FD0].closed = 1;
		settle(fd - SH_FD0);
		return 0;
	}
	return (int)syscall(SYS_close, fd);
}

int
ioctl(int fd, unsigned long req, ...)
{
	va_list ap;
	void *arg;
	int e;

	va_start(ap, req);
	arg = va_arg(ap, void *);
	va_end(ap);
	if (fake(fd)) {
		if (sh_fd[fd - SH_FD0].closed) {
			errno = EBADF;
			return -1;
		}
		if ((e = kt_ioctl(sh_fd[fd - SH_FD0].slot, (int)req, arg)) != 0) {
			errno = e;
			return -1;
		}
		return 0;
	}
	return (int)syscall(SYS_ioctl, fd, req, arg);
}

void *
mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
	void *p;
	int m;

	if (fake(fd)) {
		if (!(flags & MAP_SHARED) || (p = kt_map(sh_fd[fd - SH_FD0].slot, (long)off, len)) == 0) {
			errno = ENXIO;
			return MAP_FAILED;
		}
		for (m = 0; m < SH_NMAP; m++)
			if (!sh_map[m].addr) {
				sh_map[m].addr = p;
				sh_map[m].len = len;
				sh_map[m].fd = fd - SH_FD0;
				sh_maps++;
				return p;
			}
		errno = ENOMEM;
		return MAP_FAILED;
	}
	return (void *)syscall(SYS_mmap, addr, len, prot, flags, fd, off);
}

int
munmap(void *addr, size_t len)
{
	int m, f;

	for (m = 0; m < SH_NMAP; m++)
		if (sh_map[m].addr && sh_map[m].addr == addr) {
			if (sh_map[m].len != len)
				sh_bad++;
			f = sh_map[m].fd;
			sh_map[m].addr = 0;
			settle(f);
			return 0;
		}
	for (m = 0; m < SH_NMAP; m++)
		if (sh_map[m].addr && (char *)addr >= (char *)sh_map[m].addr &&
		    (char *)addr < (char *)sh_map[m].addr + sh_map[m].len) {
			sh_bad++;
			return 0;
		}
	return (int)syscall(SYS_munmap, addr, len);
}

int
fcntl(int fd, int cmd, ...)
{
	va_list ap;
	long arg;

	va_start(ap, cmd);
	arg = va_arg(ap, long);
	va_end(ap);
	if (fake(fd))
		return 0;
	return (int)syscall(SYS_fcntl, fd, cmd, arg);
}
