/*
 * mkstemp.c -- mkstemp(3) for CDE, which Amix's C library lacks; a member of its
 * own in libamixcompat-cde.a, so a program that links another one first
 * (dtksh: libast's) takes that one alone.
 * MIT licence, see LICENSE in userland/packages.
 */
#include <sys/types.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/*
 * mkstemp: replace the trailing XXXXXX of tmpl with letters and digits and
 * create the file, O_EXCL, mode 0600; another name on EEXIST.  Returns the
 * open descriptor, or -1 with errno set (EINVAL for a template without
 * six trailing X's).
 */
int
mkstemp(char *tmpl)
{
	static const char set[] =
		"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
	static unsigned long seq;
	size_t len = strlen(tmpl);
	char *x;
	unsigned long v;
	int tries, i, fd;

	if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX") != 0) {
		errno = EINVAL;
		return -1;
	}
	x = tmpl + len - 6;
	for (tries = 0; tries < 10000; tries++) {
		v = ((unsigned long)getpid() << 16) ^ (unsigned long)time(NULL)
		    ^ (++seq * 2654435761UL);
		for (i = 0; i < 6; i++) {
			x[i] = set[v % 62];
			v /= 62;
		}
		fd = open(tmpl, O_RDWR | O_CREAT | O_EXCL, 0600);
		if (fd >= 0 || errno != EEXIST)
			return fd;
	}
	errno = EEXIST;
	return -1;
}
