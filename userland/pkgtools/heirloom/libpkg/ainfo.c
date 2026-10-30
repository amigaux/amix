/*
 * AMIX PORT: bounded, always-terminated ownership writers for struct ainfo.
 *
 * New file (not upstream).  Part of the vendored heirloom-pkgtools tree;
 * uses the CDDL-licensed struct ainfo from <pkgstrct.h> and the libpkg
 * logerr()/pkg_gt() primitives, so it inherits the surrounding tree's
 * license.  See heirloom/AMIX-PORT.md.
 *
 * The ainfo owner[] and group[] fields are fixed char[ATRSIZ+1] arrays.
 * The historical writers copied into them with strcpy() (verify.c) or a
 * NON-terminating strncpy(dst, src, ATRSIZ) (installf.c, mkpkgmap.c).  A
 * name longer than ATRSIZ (64) - which can legitimately arrive from a
 * TARGET root's /etc/group under `pkgadd -R` - either smashed the struct
 * (strcpy) or left the field unterminated (strncpy).  These setters
 * truncate at ATRSIZ, ALWAYS NUL-terminate, and emit a LOUD diagnostic
 * on truncation so a pathological name is never silently accepted.
 */

#include <stdio.h>
#include <string.h>
#include <pkgstrct.h>
#include <pkglib.h>
#include "pkglocale.h"

#define	ERR_ATTR_TRUNC	\
	"WARNING: %s name <%.*s...> exceeds %d bytes - truncated " \
	"(possible mis-ownership)"

/*
 * Bounded copy into an ATRSIZ+1 attribute buffer.  Public so mkpkgmap's
 * local owner[]/group[] buffers (also ATRSIZ+1) can share the one
 * truncation-and-diagnostic implementation.
 */
void
pkgattr_set(char *a_dst, const char *a_src, const char *a_what)
{
	size_t	n;

	if (a_dst == (char *)NULL) {
		return;
	}
	if (a_src == (const char *)NULL) {
		a_dst[0] = '\0';
		return;
	}
	n = strlen(a_src);
	if (n > (size_t)ATRSIZ) {
		logerr(pkg_gt(ERR_ATTR_TRUNC), a_what, ATRSIZ, a_src, ATRSIZ);
		n = (size_t)ATRSIZ;
	}
	(void) memcpy(a_dst, a_src, n);
	a_dst[n] = '\0';
}

void
ainfo_set_owner(struct ainfo *a_ainfo, const char *a_name)
{
	pkgattr_set(a_ainfo->owner, a_name, "owner");
}

void
ainfo_set_group(struct ainfo *a_ainfo, const char *a_name)
{
	pkgattr_set(a_ainfo->group, a_name, "group");
}
