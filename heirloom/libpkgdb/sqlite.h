/*
 * libpkgdb/sqlite.h - STUB declaration header for the Amix port.
 *
 * The vendored SQLite (libpkgdb/) was removed from this tree; the
 * empirical linker maps (research/heirloom/linksets/) prove that
 * libgendb/genericdb.o is never pulled into any built binary, so
 * genericdb.c only needs these declarations to COMPILE.  Nothing here
 * is ever called; if genericdb_open() were ever linked in, the link
 * would fail with unresolved sqlite_* symbols (by design).
 *
 * Covers exactly the SQLite 2.x names genericdb.c references.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT license (see compat/amixcompat.h).
 */

#ifndef AMIX_STUB_SQLITE_H
#define AMIX_STUB_SQLITE_H

typedef struct sqlite sqlite;

#define SQLITE_OK	0	/* successful result */

extern sqlite *sqlite_open(const char *, int, char **);
extern void sqlite_close(sqlite *);
extern int sqlite_get_table(sqlite *, const char *, char ***, int *,
    int *, char **);
extern void sqlite_free_table(char **);
extern void sqlite_freemem(void *);

#endif /* AMIX_STUB_SQLITE_H */
