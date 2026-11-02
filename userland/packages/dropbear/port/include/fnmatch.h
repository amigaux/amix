/*
 * fnmatch.h -- fnmatch(3) for Dropbear's scp on Amix, which has the shell
 * pattern matcher gmatch(3G) (libgen) and no fnmatch.  Flags are not
 * supported: scp passes none.  Defined in amix-compat.c.  MIT, this
 * repository.
 */
#ifndef AMIX_DROPBEAR_FNMATCH_H
#define AMIX_DROPBEAR_FNMATCH_H

#define FNM_NOMATCH 1

int fnmatch(const char *, const char *, int);

#endif
