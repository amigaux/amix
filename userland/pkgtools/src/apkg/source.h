/*
 * source.h - package SOURCE abstraction for apkg.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * A "source" is where catalog + package bits come from.  Three kinds,
 * classified EXPLICITLY from the repo string (no heuristics):
 *
 *   http://host/path   -> SRC_HTTP  (the HTTP client in http.c)
 *   file:///cdrom      -> SRC_FILE  (scheme stripped)
 *   /cdrom             -> SRC_FILE  (leading '/': what an installer passes)
 *   raw:/dev/rdsk/...  -> SRC_RAW   (tape / raw slice, byte-offset addressed)
 *   anything else      -> hard error
 *
 * The layering keeps http.c an HTTP-only client (its http://-only URL
 * rejection is CORRECT once classification moved up here): adding file://
 * to the HTTP client would be a layering violation.
 *
 * Two operations:
 *   src_fetch  - pull a small named metadata file (catalog, catalog.md5)
 *                to a local path.  Return contract mirrors http_get so
 *                the update path treats every source uniformly.
 *   src_stage  - make one catalog entry's datastream ready for
 *                `pkgadd -d`, md5-verified.  *ephemeral tells the caller
 *                whether the staged path is scratch (safe/worth removing)
 *                or the source medium itself (never touch it).
 *
 * The RAW medium is self-describing: a fixed metadata region at the
 * front (catalog + catalog.md5, NUL-padded) followed by the package
 * datastreams at the byte offsets the catalog's offset column records.
 * These constants are shared with tools/repo/gen-catalog.py --raw, which
 * lays the image out; keep the two in lockstep.
 */

#ifndef APKG_SOURCE_H
#define APKG_SOURCE_H

#include "apkg.h"   /* struct conf, struct pkgent */

enum { SRC_HTTP, SRC_FILE, SRC_RAW };   /* RAW = tape / raw slice */

/* src_fetch return contract - the same integers http_get uses, so
 * cmd_update can share one dispatch. */
#define SRC_OK        0   /* fetched, body in dest                       */
#define SRC_ENET     -1   /* transport failure (network / read / dd)     */
#define SRC_ESTATUS  -2   /* addressable but absent (status in *status)  */

/* RAW self-describing layout (byte offsets into the raw slice).  Reads
 * of a raw character device are 512-aligned, so every constant is a
 * multiple of 512.  gen-catalog.py --raw MUST use the identical values. */
#define RAW_CAT_OFF    0L        /* catalog text, NUL-padded             */
#define RAW_CAT_MAX    32768L    /* ... reserved region size             */
#define RAW_MD5_OFF    32768L    /* catalog.md5 text, NUL-padded         */
#define RAW_MD5_MAX    512L      /* ... reserved region size             */
#define RAW_DATA_OFF   65536L    /* first package datastream begins here */

struct source {
    int kind;      /* SRC_HTTP | SRC_FILE | SRC_RAW                      */
    char *base;    /* HTTP: full URL, no trailing '/'.  FILE: directory
                    * path, scheme stripped, no trailing '/'.  RAW: the
                    * raw device path (e.g. /dev/rdsk/c5d0s0).           */
    struct httpopts http;  /* every fetch-path knob, from apkg.conf.
                    * src_open fills it with the built-in defaults; the
                    * caller overwrites it with http_opts_from_conf(). */
};

/* Classify repo and fill s.  Returns 0 on success, -1 on an
 * unclassifiable repo (message printed). */
extern int src_open(const char *repo, struct source *s);

/* Free anything src_open allocated. */
extern void src_close(struct source *s);

/* Fetch metadata file <rel> (e.g. "catalog") into dest, under s->http
 * (ignored by FILE/RAW).  Returns SRC_OK / SRC_ENET / SRC_ESTATUS,
 * with the 404-alike code in *status. */
extern int src_fetch(const struct source *s, const char *rel,
                     const char *dest, int *status);

/* Stage ent's datastream for `pkgadd -d`, md5-verified against the
 * catalog.  On success *out is an allocated path to the ready file and
 * *ephemeral is 1 when that path is scratch the caller may unlink, 0
 * when it is the source medium itself.  Returns an EX_* code. */
extern int src_stage(const struct source *s, const struct pkgent *ent,
                     const char *cachedir, char **out, int *ephemeral);

#endif /* APKG_SOURCE_H */
