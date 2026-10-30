/*
 * s5sim.c - LD_PRELOAD shim that gives a Linux directory tree the naming
 * semantics of a System V s5 filesystem: every path component is truncated
 * to 14 bytes, on CREATE and on LOOKUP alike.
 *
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
 *
 * Amix's root filesystem is s5 and nothing on a Linux host behaves like it,
 * so the 14-character defect class (see ../../../docs/s5-14char-collisions.md)
 * cannot be exercised host-side without a simulation.  This is that
 * simulation, and it is deliberately small and honest about its limits:
 *
 *   * Only paths under $S5SIM_ROOT are affected -- anything else (the loader,
 *     libc, the test's own scratch files) is passed through untouched.  A
 *     relative path is checked against $PWD for that test and then truncated
 *     in its own (relative) form.
 *   * Truncation is per component, to S5_NAME_MAX (14) bytes, exactly like
 *     the s5 directory-entry format: a lookup of "typescript.stage2" finds
 *     the dirent "typescript.sta", which is what makes two long names alias
 *     each other on a real Amix box.
 *   * mkstemp() is provided HERE rather than borrowed from glibc, for two
 *     reasons.  Mechanically, glibc's mkstemp reaches the kernel through
 *     internal calls that LD_PRELOAD cannot interpose, so a glibc mkstemp
 *     would bypass the simulated namespace entirely.  Substantively, the
 *     binary under test on the box does not use glibc's: it uses the SVR4
 *     mktemp()-based mkstemp() in ../../compat/amixcompat.c, whose candidate
 *     names are <pid><letter> and which EMPTIES the template when it gives
 *     up.  This implementation mirrors that one, so the failure the harness
 *     reproduces has the same fingerprint the bench log showed --
 *     "unable to create unique temporary file <>".
 *
 * NOT simulated (and not needed by cppath()): the 65,535-inode ceiling,
 * stat()/lstat() interposition (cppath uses fstat on an open descriptor),
 * and directory-read truncation.
 *
 * Build:  cc -shared -fPIC -o s5sim.so s5sim.c -ldl
 * Use:    S5SIM_ROOT=/some/dir [S5SIM_LOG=/some/log] LD_PRELOAD=./s5sim.so cmd
 */

#define	_GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <utime.h>

#define	S5_NAME_MAX	14

static int (*real_open)(const char *, int, ...);
static int (*real_access)(const char *, int);
static int (*real_rename)(const char *, const char *);
static int (*real_unlink)(const char *);
static int (*real_remove)(const char *);
static int (*real_mkdir)(const char *, mode_t);
static int (*real_utime)(const char *, const struct utimbuf *);

static int logfd = -2;			/* -2 = not tried, -1 = no log */

static void
resolve(void)
{
	if (real_open != NULL)
		return;
	real_open   = dlsym(RTLD_NEXT, "open");
	real_access = dlsym(RTLD_NEXT, "access");
	real_rename = dlsym(RTLD_NEXT, "rename");
	real_unlink = dlsym(RTLD_NEXT, "unlink");
	real_remove = dlsym(RTLD_NEXT, "remove");
	real_mkdir  = dlsym(RTLD_NEXT, "mkdir");
	real_utime  = dlsym(RTLD_NEXT, "utime");
}

static void
s5log(const char *fmt, ...)
{
	va_list ap;
	const char *path;

	if (logfd == -2) {
		path = getenv("S5SIM_LOG");
		logfd = -1;
		if (path != NULL && *path != '\0') {
			resolve();
			logfd = real_open(path, O_WRONLY | O_CREAT | O_APPEND,
					0644);
		}
	}
	if (logfd < 0)
		return;
	va_start(ap, fmt);
	(void) vdprintf(logfd, fmt, ap);
	va_end(ap);
}

/*
 * Is `path' inside $S5SIM_ROOT?  A relative path is judged against the
 * current directory but rewritten in its own relative form.
 */
static int
under_root(const char *path)
{
	const char *root;
	char cwdbuf[PATH_MAX];
	char abs[PATH_MAX * 2];
	size_t rootlen;
	const char *test;

	root = getenv("S5SIM_ROOT");
	if (root == NULL || *root == '\0' || path == NULL)
		return (0);
	rootlen = strlen(root);
	while (rootlen > 1 && root[rootlen - 1] == '/')
		rootlen--;

	if (path[0] == '/') {
		test = path;
	} else {
		if (getcwd(cwdbuf, sizeof (cwdbuf)) == NULL)
			return (0);
		if (strlen(cwdbuf) + 1 + strlen(path) + 1 > sizeof (abs))
			return (0);
		(void) sprintf(abs, "%s/%s", cwdbuf, path);
		test = abs;
	}
	if (strncmp(test, root, rootlen) != 0)
		return (0);
	return (test[rootlen] == '/' || test[rootlen] == '\0');
}

/*
 * Truncate every component of `path' to S5_NAME_MAX bytes into `buf'.
 * Returns buf, or path itself when the path is not in the simulated
 * filesystem (or would not fit, which the harness never does).
 */
static const char *
s5path(const char *path, char *buf, size_t bufsize)
{
	const char *p;
	size_t out = 0;
	size_t n;

	if (!under_root(path))
		return (path);

	p = path;
	while (*p != '\0') {
		if (*p == '/') {
			if (out + 1 >= bufsize)
				return (path);
			buf[out++] = *p++;
			continue;
		}
		n = 0;
		while (p[n] != '\0' && p[n] != '/')
			n++;
		if (n > S5_NAME_MAX)
			n = S5_NAME_MAX;
		if (out + n >= bufsize)
			return (path);
		(void) memcpy(buf + out, p, n);
		out += n;
		while (*p != '\0' && *p != '/')
			p++;
	}
	buf[out] = '\0';
	return (buf);
}

int
open(const char *path, int flags, ...)
{
	char buf[PATH_MAX];
	va_list ap;
	mode_t mode = 0;
	int rc;

	resolve();
	if (flags & O_CREAT) {
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}
	rc = real_open(s5path(path, buf, sizeof (buf)), flags, mode);
	s5log("open      %-40s -> %-24s rc=%d errno=%d\n", path,
		s5path(path, buf, sizeof (buf)), rc, rc < 0 ? errno : 0);
	return (rc);
}

int
open64(const char *path, int flags, ...)
{
	va_list ap;
	mode_t mode = 0;

	if (flags & O_CREAT) {
		va_start(ap, flags);
		mode = (mode_t)va_arg(ap, int);
		va_end(ap);
	}
	return (open(path, flags, mode));
}

int
access(const char *path, int amode)
{
	char buf[PATH_MAX];
	int rc;

	resolve();
	rc = real_access(s5path(path, buf, sizeof (buf)), amode);
	s5log("access    %-40s -> %-24s rc=%d\n", path,
		s5path(path, buf, sizeof (buf)), rc);
	return (rc);
}

int
rename(const char *from, const char *to)
{
	char fbuf[PATH_MAX];
	char tbuf[PATH_MAX];
	char fx[PATH_MAX];
	char tx[PATH_MAX];
	int rc;

	resolve();
	(void) strcpy(fx, s5path(from, fbuf, sizeof (fbuf)));
	(void) strcpy(tx, s5path(to, tbuf, sizeof (tbuf)));
	rc = real_rename(fx, tx);
	s5log("rename    %-40s -> %-24s rc=%d\n", fx, tx, rc);
	return (rc);
}

int
unlink(const char *path)
{
	char buf[PATH_MAX];

	resolve();
	return (real_unlink(s5path(path, buf, sizeof (buf))));
}

int
remove(const char *path)
{
	char buf[PATH_MAX];

	resolve();
	return (real_remove(s5path(path, buf, sizeof (buf))));
}

int
mkdir(const char *path, mode_t mode)
{
	char buf[PATH_MAX];

	resolve();
	return (real_mkdir(s5path(path, buf, sizeof (buf)), mode));
}

int
utime(const char *path, const struct utimbuf *times)
{
	char buf[PATH_MAX];

	resolve();
	return (real_utime(s5path(path, buf, sizeof (buf)), times));
}

/*
 * mkstemp() as the box has it: SVR4 mktemp() semantics (the six X's become
 * <pid><letter>, one letter per attempt) wrapped in O_CREAT|O_EXCL, and the
 * template EMPTIED when every attempt collides.  Mirrors ../../compat/
 * amixcompat.c; see the file header for why glibc's cannot be used here.
 */
int
mkstemp(char *template)
{
	char saved[PATH_MAX];
	size_t len;
	char letter;
	int fd;

	if (template == NULL) {
		errno = EINVAL;
		return (-1);
	}
	len = strlen(template);
	if (len < 6 || len >= sizeof (saved) ||
			strcmp(template + len - 6, "XXXXXX") != 0) {
		errno = EINVAL;
		return (-1);
	}
	(void) strcpy(saved, template);
	s5log("mkstemp   template=<%s> (basename %d chars)\n", template,
		(int)(strrchr(template, '/') != NULL ?
			len - (strrchr(template, '/') - template) - 1 : len));

	for (letter = 'a'; letter <= 'z'; letter++) {
		(void) sprintf(template + len - 6, "%05d%c",
			(int)(getpid() % 100000), letter);
		fd = open(template, O_CREAT | O_EXCL | O_RDWR, 0600);
		if (fd >= 0) {
			s5log("mkstemp   created=<%s>\n", template);
			return (fd);
		}
		if (errno != EEXIST) {
			s5log("mkstemp   FAILED errno=%d\n", errno);
			return (-1);
		}
		(void) strcpy(template, saved);
	}
	template[0] = '\0';		/* mktemp() empties it when it gives up */
	s5log("mkstemp   EXHAUSTED (every candidate truncated onto an "
		"existing dirent)\n");
	errno = EEXIST;
	return (-1);
}
