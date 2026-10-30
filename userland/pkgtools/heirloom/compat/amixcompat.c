/*
 * amixcompat.c - small C89 shims for functions missing from the Amix
 * (Amiga Unix, SVR4.0 m68k) libc.  Companion to amixcompat.h; compiled
 * into libadm.a by the Amix cross build only (see COMPATOBJ in
 * mk.config.amix).
 *
 * Copyright (c) 2026 Jussi Alanärä
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>

#include "wchar.h"
#include "wctype.h"

/*
 * ASCII lower-case helper.  SVR4 tolower() is only defined for
 * characters that are actually upper case, so do it by hand.
 */
static int
lc(int c)
{
	if (c >= 'A' && c <= 'Z')
		return (c - 'A' + 'a');
	return (c);
}

int
strcasecmp(const char *s1, const char *s2)
{
	int c1, c2;

	for (;;) {
		c1 = lc((unsigned char)*s1++);
		c2 = lc((unsigned char)*s2++);
		if (c1 != c2)
			return (c1 - c2);
		if (c1 == 0)
			return (0);
	}
}

int
strncasecmp(const char *s1, const char *s2, size_t n)
{
	int c1, c2;

	while (n-- != 0) {
		c1 = lc((unsigned char)*s1++);
		c2 = lc((unsigned char)*s2++);
		if (c1 != c2)
			return (c1 - c2);
		if (c1 == 0)
			return (0);
	}
	return (0);
}

/*
 * mkstemp() built on SVR4 mktemp() + O_CREAT|O_EXCL.  mktemp()
 * overwrites the XXXXXX template, so keep a pristine copy and retry
 * a few times on EEXIST races.
 */
int
mkstemp(char *template)
{
	char	saved[1024];
	int	fd;
	int	tries;

	if (template == NULL || strlen(template) >= sizeof (saved)) {
		errno = EINVAL;
		return (-1);
	}
	(void) strcpy(saved, template);

	for (tries = 0; tries < 10; tries++) {
		if (mktemp(template) == NULL || template[0] == '\0') {
			errno = EEXIST;
			return (-1);
		}
		fd = open(template, O_CREAT | O_EXCL | O_RDWR, 0600);
		if (fd >= 0)
			return (fd);
		if (errno != EEXIST)
			return (-1);
		/* collision: restore template and try again */
		(void) strcpy(template, saved);
	}
	errno = EEXIST;
	return (-1);
}

/*
 * isblank() - C99; absent from the SVR4.0 ctype.  Needed by the
 * vendored fnmatch character-class table (compat/charclass.h).
 */
int
isblank(int c)
{
	return (c == ' ' || c == '\t');
}

/*
 * Minimal wide-character classification, sufficient for
 * libadm/puttext.c (message line folding).  Amix is effectively a
 * single-byte-locale system; treat 0..255 with the byte classifiers
 * and consider everything else printable, width 1.
 */
int
iswspace(wchar_t wc)
{
	if (wc >= 0 && wc < 256)
		return (isspace((int)wc));
	return (0);
}

int
iswprint(wchar_t wc)
{
	if (wc >= 0 && wc < 256)
		return (isprint((int)wc));
	return (1);
}

int
iswalpha(wchar_t wc)
{
	if (wc >= 0 && wc < 256)
		return (isalpha((int)wc));
	return (0);
}

int
wcwidth(wchar_t wc)
{
	if (wc == 0)
		return (0);
	if (wc < 32 || (wc >= 127 && wc < 160))
		return (-1);
	return (1);
}

/*
 * iswdigit() - see the other isw* fallbacks above.
 */
int
iswdigit(wchar_t wc)
{
	if (wc >= 0 && wc < 256)
		return (isdigit((int)wc));
	return (0);
}

/*
 * getpagesize() - BSD; SVR4 spells it sysconf(_SC_PAGESIZE).
 */
int
getpagesize(void)
{
	long	v;

	v = sysconf(_SC_PAGESIZE);
	/*
	 * Sanity: the value feeds buffer-size rounding in libpkg/vfpops.c;
	 * an unsupported sysconf index returning garbage must not produce
	 * insane allocation sizes.  Accept only a power of two in a
	 * plausible range.
	 */
	if (v < 512 || v > 65536 || (v & (v - 1)) != 0)
		v = 4096;
	return ((int)v);
}

/*
 * madvise() - advisory only; no equivalent on SVR4.0.  No-op.
 */
/*ARGSUSED*/
int
madvise(void *addr, size_t len, int advice)
{
	return (0);
}

/*
 * memalign() - the only user (libpkg/vfpops.c) wants page-aligned
 * buffers purely as a read()-performance hint and later free()s the
 * result, so a plain malloc() is a correct substitute.
 */
/*ARGSUSED*/
void *
memalign(size_t align, size_t size)
{
	return (malloc(size));
}

/*
 * pwrite() - emulated with lseek/write/lseek.  Not atomic with
 * respect to other users of the same descriptor; the pkg tools are
 * single-threaded, single-process writers.
 */
ssize_t
pwrite(int fd, const void *buf, size_t nbyte, long offset)
{
	long	old;
	ssize_t	w;
	int	e;

	old = lseek(fd, 0L, SEEK_CUR);
	if (old == -1L)
		return (-1);
	if (lseek(fd, offset, SEEK_SET) == -1L)
		return (-1);
	w = (ssize_t)write(fd, (char *)buf, (unsigned)nbyte);
	e = errno;
	(void) lseek(fd, old, SEEK_SET);
	errno = e;
	return (w);
}

/*
 * ftruncate() - SVR4.0 has no ftruncate(2); shrinking is done with
 * fcntl(F_FREESP) and growing with an explicit zero-byte write.
 */
int
ftruncate(int fd, long length)
{
	struct stat	st;
	struct flock	fl;
	long		old;

	if (fstat(fd, &st) != 0)
		return (-1);
	if ((long)st.st_size == length)
		return (0);
	if ((long)st.st_size > length) {
		fl.l_whence = 0;	/* SEEK_SET */
		fl.l_start = length;
		fl.l_len = 0L;		/* to end of file */
		return (fcntl(fd, F_FREESP, &fl));
	}
	/* grow: write one zero byte at length-1 */
	old = lseek(fd, 0L, SEEK_CUR);
	if (old == -1L)
		return (-1);
	if (lseek(fd, length - 1, SEEK_SET) == -1L)
		return (-1);
	if (write(fd, "", 1) != 1) {
		(void) lseek(fd, old, SEEK_SET);
		return (-1);
	}
	(void) lseek(fd, old, SEEK_SET);
	return (0);
}

/*
 * atoll() - C99; simple C89 replacement (decimal, optional sign,
 * leading whitespace - matches atoll semantics for valid input).
 */
long long
atoll(const char *str)
{
	long long	v = 0;
	int		neg = 0;

	while (*str == ' ' || *str == '\t' || *str == '\n')
		str++;
	if (*str == '-') {
		neg = 1;
		str++;
	} else if (*str == '+') {
		str++;
	}
	while (*str >= '0' && *str <= '9') {
		v = v * 10 + (*str - '0');
		str++;
	}
	return (neg ? -v : v);
}

/*
 * realpath() - not in SVR4.0 libc.  Classic chdir/getcwd technique:
 * resolves all directory components (including symlinks); a symlink
 * in the FINAL component is not chased (sufficient for the two users
 * in this tree, which canonicalize directory-ish device paths).
 */
char *
realpath(const char *path, char *resolved)
{
	char	saved[1024];
	char	dir[1024];
	const char	*base;
	char	*sl;
	size_t	n;

	if (path == NULL || resolved == NULL || *path == '\0') {
		errno = EINVAL;
		return (NULL);
	}
	if (getcwd(saved, sizeof (saved)) == NULL)
		return (NULL);

	/* fast path: the whole path is a directory */
	if (chdir(path) == 0) {
		if (getcwd(resolved, 1024) == NULL) {
			(void) chdir(saved);
			return (NULL);
		}
		(void) chdir(saved);
		return (resolved);
	}

	/* split into directory + final component */
	if (strlen(path) >= sizeof (dir)) {
		errno = ENAMETOOLONG;
		return (NULL);
	}
	(void) strcpy(dir, path);
	sl = strrchr(dir, '/');
	if (sl == NULL) {
		base = path;
		(void) strcpy(dir, ".");
	} else {
		base = sl + 1;
		if (sl == dir)
			sl[1] = '\0';	/* "/name" -> "/" */
		else
			*sl = '\0';
	}
	if (chdir(dir) != 0)
		return (NULL);
	if (getcwd(resolved, 1024) == NULL) {
		(void) chdir(saved);
		return (NULL);
	}
	n = strlen(resolved);
	if (n + strlen(base) + 2 > 1024) {
		(void) chdir(saved);
		errno = ENAMETOOLONG;
		return (NULL);
	}
	if (n > 0 && resolved[n - 1] != '/') {
		resolved[n] = '/';
		resolved[n + 1] = '\0';
	}
	(void) strcat(resolved, base);
	(void) chdir(saved);
	return (resolved);
}

/*
 * fgetpwent()/fgetgrent() - declared by the SVR4.0 <pwd.h>/<grp.h>
 * but not present in libc.so.1 (verified with nm).  Minimal
 * colon-separated parsers over static buffers, exactly like the
 * historic implementations.  Used by libpkg/ncgrpw.c to read
 * /etc/passwd//etc/group inside an alternate install root.
 */
#include <pwd.h>
#include <grp.h>

#define	AMIX_PWLINE	512
#define	AMIX_GRLINE	1024
#define	AMIX_GRMEMB	64

static char *
amix_nextfield(char **cp)
{
	char	*s, *p;

	s = *cp;
	if (s == NULL)
		return ("");
	p = strchr(s, ':');
	if (p != NULL) {
		*p = '\0';
		*cp = p + 1;
	} else {
		*cp = NULL;
	}
	return (s);
}

struct passwd *
fgetpwent(FILE *fp)
{
	static struct passwd	pw;
	static char		line[AMIX_PWLINE];
	char	*cp, *p;

	for (;;) {
		if (fgets(line, sizeof (line), fp) == NULL)
			return (NULL);
		if ((p = strchr(line, '\n')) != NULL)
			*p = '\0';
		if (line[0] == '\0' || line[0] == '#')
			continue;
		break;
	}
	memset((void *)&pw, 0, sizeof (pw));
	cp = line;
	pw.pw_name = amix_nextfield(&cp);
	pw.pw_passwd = amix_nextfield(&cp);
	pw.pw_uid = (uid_t)atoi(amix_nextfield(&cp));
	pw.pw_gid = (gid_t)atoi(amix_nextfield(&cp));
	pw.pw_gecos = amix_nextfield(&cp);
	pw.pw_dir = amix_nextfield(&cp);
	pw.pw_shell = amix_nextfield(&cp);
	pw.pw_age = "";
	pw.pw_comment = "";
	return (&pw);
}

struct group *
fgetgrent(FILE *fp)
{
	static struct group	gr;
	static char		line[AMIX_GRLINE];
	static char		*memb[AMIX_GRMEMB + 1];
	char	*cp, *p, *m;
	int	i;

	for (;;) {
		if (fgets(line, sizeof (line), fp) == NULL)
			return (NULL);
		if ((p = strchr(line, '\n')) != NULL)
			*p = '\0';
		if (line[0] == '\0' || line[0] == '#')
			continue;
		break;
	}
	memset((void *)&gr, 0, sizeof (gr));
	cp = line;
	gr.gr_name = amix_nextfield(&cp);
	gr.gr_passwd = amix_nextfield(&cp);
	gr.gr_gid = (gid_t)atoi(amix_nextfield(&cp));
	m = amix_nextfield(&cp);
	i = 0;
	while (m != NULL && *m != '\0' && i < AMIX_GRMEMB) {
		memb[i++] = m;
		p = strchr(m, ',');
		if (p == NULL)
			break;
		*p = '\0';
		m = p + 1;
	}
	memb[i] = NULL;
	gr.gr_mem = memb;
	return (&gr);
}

/*
 * basename() - SVR4.0 keeps this in libgen.a (under /usr/ccs/lib,
 * outside the wrapper's default library path); trivial to provide.
 * Historic SysV semantics, may modify nothing (returns pointer into
 * the argument or a static string).
 */
char *
basename(char *path)
{
	char	*p;

	if (path == NULL || *path == '\0')
		return (".");
	/* strip trailing slashes */
	p = path + strlen(path) - 1;
	while (p > path && *p == '/')
		*p-- = '\0';
	if ((p = strrchr(path, '/')) != NULL && p[1] != '\0')
		return (p + 1);
	if (p != NULL && p == path && p[1] == '\0')
		return ("/");
	return (path);
}

/*
 * strtok_r() - POSIX; not in SVR4.0 libc.
 */
char *
strtok_r(char *s, const char *delim, char **lasts)
{
	char	*tok, *end;

	if (s == NULL)
		s = *lasts;
	if (s == NULL)
		return (NULL);
	s += strspn(s, delim);
	if (*s == '\0') {
		*lasts = NULL;
		return (NULL);
	}
	tok = s;
	end = s + strcspn(s, delim);
	if (*end != '\0') {
		*end = '\0';
		*lasts = end + 1;
	} else {
		*lasts = NULL;
	}
	return (tok);
}

/*
 * strtoull() - C99; C89 replacement supporting bases 0, 8, 10, 16
 * (all this tree uses is base 10).  No errno/ERANGE handling.
 */
unsigned long long
strtoull(const char *str, char **endptr, int base)
{
	unsigned long long	v = 0;
	int	neg = 0;
	int	d;

	while (*str == ' ' || *str == '\t' || *str == '\n')
		str++;
	if (*str == '-') {
		neg = 1;
		str++;
	} else if (*str == '+') {
		str++;
	}
	if (base == 0) {
		if (str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
			base = 16;
			str += 2;
		} else if (str[0] == '0') {
			base = 8;
		} else {
			base = 10;
		}
	} else if (base == 16 &&
	    str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
		str += 2;
	}
	for (;;) {
		if (*str >= '0' && *str <= '9')
			d = *str - '0';
		else if (*str >= 'a' && *str <= 'f')
			d = *str - 'a' + 10;
		else if (*str >= 'A' && *str <= 'F')
			d = *str - 'A' + 10;
		else
			break;
		if (d >= base)
			break;
		v = v * (unsigned long long)base + (unsigned long long)d;
		str++;
	}
	if (endptr != NULL)
		*endptr = (char *)str;
	return (neg ? (unsigned long long)0 - v : v);
}

/*
 * gethostname() - BSD; SVR4 spells it uname(2) nodename.
 */
#include <sys/utsname.h>

int
gethostname(char *name, int namelen)
{
	struct utsname	un;
	size_t	n;

	if (uname(&un) < 0)
		return (-1);
	n = strlen(un.nodename);
	if (n >= (size_t)namelen)
		n = namelen - 1;
	(void) memcpy(name, un.nodename, n);
	name[n] = '\0';
	return (0);
}

/*
 * amix_raise_rlimits() - best-effort raise of the per-process memory
 * limits (soft -> hard).  The Amix default data limit (~8-16 MB) is
 * tight for the contents-file image plus package structures; if the
 * hard limit allows more, take it.  All failures are silently
 * ignored.  Called from libinst ocfile()/socfile() (the memory-heavy
 * DB paths shared by pkgadd/pkgrm/pkginstall/pkgremove/installf).
 */
#include <sys/resource.h>

void
amix_raise_rlimits(void)
{
	static int	done = 0;
	struct rlimit	rl;

	int	dbg;

	if (done)
		return;
	done = 1;
	dbg = (getenv("DS_DEBUG") != NULL);

#ifdef RLIMIT_DATA
	if (getrlimit(RLIMIT_DATA, &rl) == 0) {
		if (dbg)
			(void) fprintf(stderr,
			    "DS_DEBUG(rlimit): DATA cur=%ld max=%ld\n",
			    (long)rl.rlim_cur, (long)rl.rlim_max);
		if (rl.rlim_cur < rl.rlim_max) {
			rl.rlim_cur = rl.rlim_max;
			if (setrlimit(RLIMIT_DATA, &rl) == 0 && dbg)
				(void) fprintf(stderr,
				    "DS_DEBUG(rlimit): DATA raised to %ld\n",
				    (long)rl.rlim_cur);
		}
	}
#endif
#ifdef RLIMIT_VMEM
	if (getrlimit(RLIMIT_VMEM, &rl) == 0) {
		if (dbg)
			(void) fprintf(stderr,
			    "DS_DEBUG(rlimit): VMEM cur=%ld max=%ld\n",
			    (long)rl.rlim_cur, (long)rl.rlim_max);
		if (rl.rlim_cur < rl.rlim_max) {
			rl.rlim_cur = rl.rlim_max;
			if (setrlimit(RLIMIT_VMEM, &rl) == 0 && dbg)
				(void) fprintf(stderr,
				    "DS_DEBUG(rlimit): VMEM raised to %ld\n",
				    (long)rl.rlim_cur);
		}
	}
#endif
	if (dbg)
		(void) fflush(stderr);
}

/*
 * localtime_r() - POSIX; the pkg tools are single-threaded, so
 * copying the static localtime() result is fully equivalent.
 */
#include <time.h>

struct tm *
localtime_r(const time_t *timep, struct tm *result)
{
	struct tm	*p;

	p = localtime(timep);
	if (p == NULL)
		return (NULL);
	*result = *p;
	return (result);
}

/*
 * getpwnam()/getpwuid()/getgrnam()/getgrgid() - direct text-file
 * implementations that PREEMPT the Amix libc versions (an executable's
 * global definitions win over shared-library exports at static link
 * time for all objects in this build).
 *
 * WHY: the first getpwnam() call of a pkginstall run SIGSEGVs inside
 * the Amix libc passwd machinery (bench v15: averify's "owner check"
 * stage; the group path survives).  The libc internals allocate
 * through global function-pointer indirection (_libc_malloc & co) and
 * the passwd-side record handling dies in our process for reasons not
 * debuggable off-box.  Amix /etc/passwd and /etc/group are plain
 * text, so - like the mnttab sidestep - we parse them directly with
 * the fgetpwent()/fgetgrent() shims above (host-testable, no libc
 * passwd machinery at all).
 *
 * Semantics match libc: returns a pointer to static storage
 * (overwritten by the next call of the same family), NULL when not
 * found.
 */

static FILE *
amix_pw_open(void)
{
	return (fopen("/etc/passwd", "r"));
}

struct passwd *
getpwnam(const char *name)
{
	FILE	*fp;
	struct passwd	*pw;

	if (name == NULL || (fp = amix_pw_open()) == NULL)
		return (NULL);
	while ((pw = fgetpwent(fp)) != NULL) {
		if (strcmp(pw->pw_name, name) == 0)
			break;
	}
	(void) fclose(fp);
	return (pw);
}

struct passwd *
getpwuid(uid_t uid)
{
	FILE	*fp;
	struct passwd	*pw;

	if ((fp = amix_pw_open()) == NULL)
		return (NULL);
	while ((pw = fgetpwent(fp)) != NULL) {
		if (pw->pw_uid == uid)
			break;
	}
	(void) fclose(fp);
	return (pw);
}

struct group *
getgrnam(const char *name)
{
	FILE	*fp;
	struct group	*gr;

	if (name == NULL || (fp = fopen("/etc/group", "r")) == NULL)
		return (NULL);
	while ((gr = fgetgrent(fp)) != NULL) {
		if (strcmp(gr->gr_name, name) == 0)
			break;
	}
	(void) fclose(fp);
	return (gr);
}

struct group *
getgrgid(gid_t gid)
{
	FILE	*fp;
	struct group	*gr;

	if ((fp = fopen("/etc/group", "r")) == NULL)
		return (NULL);
	while ((gr = fgetgrent(fp)) != NULL) {
		if (gr->gr_gid == gid)
			break;
	}
	(void) fclose(fp);
	return (gr);
}
