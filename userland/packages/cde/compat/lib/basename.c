/*
 * basename.c -- basename(3G) for the shared variant's libraries.  Amix has it
 * only in the static, non-PIC libgen.a, which would put text relocations into
 * a shared library; this one is built position-independent with the rest of
 * compat and links ahead of -lgen there.  The static build links libgen's.
 * MIT licence, see LICENSE in userland/packages.
 */
#include <string.h>

char *basename(char *path)
{
	char *end, *p;

	if (path == 0 || *path == '\0')
		return ".";
	end = path + strlen(path) - 1;
	while (end > path && *end == '/')	/* trailing slashes go */
		*end-- = '\0';
	if (end == path && *end == '/')		/* "/" stays "/" */
		return path;
	p = strrchr(path, '/');
	return p ? p + 1 : path;
}
