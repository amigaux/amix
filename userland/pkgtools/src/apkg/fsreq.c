/*
 * fsreq.c - the filesystem a package may install onto (APKG_FSTYPE).
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * docs/design.md section 2b is the interface.  In short: a package whose
 * pkginfo(4) carries
 *
 *     APKG_FSTYPE=ufs                    (or a list: ufs,nfs)
 *
 * installs only onto those filesystem types, named as statvfs(2)
 * f_basetype names them.  The packages set it when a file name is longer
 * than 14 bytes, which s5 cuts (P-35, Option C).  apkg checks, on the
 * staged and verified datastream and before any pkgadd of the
 * transaction:
 *
 *   - the directory of every pkgmap(4) object whose name is longer than
 *     14 bytes: the places that need long names.  With BASEDIR=/ and
 *     /opt/amix paths, a root on s5 with a ufs slice mounted on /opt
 *     passes, as it should;
 *   - or, when the package names no such object (or its pkgmap cannot
 *     be read), its install base <target><BASEDIR> (BASEDIR from the same
 *     pkginfo, "/" when absent);
 *
 * each by its nearest existing ancestor (a directory the package creates
 * lands on its parent's filesystem).  A filesystem not in the list
 * refuses the package, EX_DEPS, one line naming the package, the
 * directory and its filesystem.
 *
 * An unmarked package passes untouched, exactly as before.  So does a
 * file that is not a readable datastream (no pkginfo to read): pkgadd
 * judges those, as it always has.  The parameter is invisible to every
 * pkgadd (an unknown pkginfo parameter only reaches the install scripts'
 * environment), so the mark costs a UFS install nothing.
 *
 * C89, no snprintf/strdup, block-top declarations (the period toolchain
 * builds this for the box).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/statvfs.h>

#include "apkg.h"

#define S5_NAME_MAX 14        /* s5 cuts a directory entry at 14 bytes */
#define FSNAME_MAX  15        /* FSTYPSZ (16) less the NUL             */

/* the value of KEY in pkginfo(4) text: the first KEY=VALUE line, blanks
 * around KEY and VALUE and one pair of surrounding quotes removed (the
 * reading gen-catalog.py's parse_pkginfo() gives).  xmalloc'd, or NULL */
static char *pkginfo_get(const char *text, const char *key)
{
    const char *line;
    const char *end;
    const char *k;
    const char *v;
    char *out;
    unsigned klen;
    unsigned n;

    klen = (unsigned)strlen(key);
    for (line = text; *line != '\0'; line = *end != '\0' ? end + 1 : end) {
        end = strchr(line, '\n');
        if (end == NULL)
            end = line + strlen(line);
        k = line;
        while (k < end && (*k == ' ' || *k == '\t'))
            k++;
        if ((unsigned)(end - k) <= klen || strncmp(k, key, klen) != 0)
            continue;
        v = k + klen;
        while (v < end && (*v == ' ' || *v == '\t'))
            v++;
        if (v == end || *v != '=')
            continue;
        v++;
        while (v < end && (*v == ' ' || *v == '\t'))
            v++;
        n = (unsigned)(end - v);
        while (n > 0 && (v[n - 1] == '\r' || v[n - 1] == ' ' ||
                         v[n - 1] == '\t'))
            n--;
        if (n >= 2 && (v[0] == '"' || v[0] == '\'') && v[n - 1] == v[0]) {
            v++;
            n -= 2;
        }
        out = xmalloc(n + 1);
        memcpy(out, v, n);
        out[n] = '\0';
        return out;
    }
    return NULL;
}

/* "<type>[,<type>...]", each 1..15 of [a-z0-9]: 1 = well formed */
static int fstype_list_ok(const char *s)
{
    unsigned n;

    n = 0;
    for (;; s++) {
        if (*s == ',' || *s == '\0') {
            if (n == 0)
                return 0;
            if (*s == '\0')
                return 1;
            n = 0;
        } else if ((*s >= 'a' && *s <= 'z') || (*s >= '0' && *s <= '9')) {
            if (++n > FSNAME_MAX)
                return 0;
        } else {
            return 0;
        }
    }
}

static int in_list(const char *list, const char *type)
{
    unsigned n;

    n = (unsigned)strlen(type);
    while (*list != '\0') {
        if (strncmp(list, type, n) == 0 &&
            (list[n] == ',' || list[n] == '\0'))
            return 1;
        list = strchr(list, ',');
        if (list == NULL)
            break;
        list++;
    }
    return 0;
}

static void copy_type(char *dst, unsigned cap, const char *src, unsigned n)
{
    if (n >= cap)
        n = cap - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

#ifndef FSTYPSZ
/* A host without statvfs f_basetype (Linux) cannot name an SVR4
 * filesystem type at all.  The host build is the test vehicle, so the
 * type comes from APKG_TEST_FSTYPE, "<dir>=<type>[,<dir>=<type>...]":
 * the longest <dir> that is p or one of its parents wins; anything else
 * is "unknown", which no package lists.  Never compiled for the box
 * (Amix's sys/statvfs.h defines FSTYPSZ). */
static void host_fstype(const char *p, char *type, unsigned cap)
{
    const char *e;
    const char *eq;
    const char *end;
    unsigned dlen;
    unsigned best;
    unsigned plen;

    copy_type(type, cap, "unknown", 7);
    e = getenv("APKG_TEST_FSTYPE");
    if (e == NULL)
        return;
    plen = (unsigned)strlen(p);
    best = 0;
    while (*e != '\0') {
        end = strchr(e, ',');
        if (end == NULL)
            end = e + strlen(e);
        eq = e;
        while (eq < end && *eq != '=')
            eq++;
        if (eq < end) {
            dlen = (unsigned)(eq - e);
            while (dlen > 1 && e[dlen - 1] == '/')
                dlen--;
            if (dlen > 0 && dlen <= plen && dlen >= best &&
                strncmp(p, e, dlen) == 0 &&
                (p[dlen] == '\0' || p[dlen] == '/' || e[dlen - 1] == '/')) {
                best = dlen;
                copy_type(type, cap, eq + 1, (unsigned)(end - eq - 1));
            }
        }
        e = *end != '\0' ? end + 1 : end;
    }
}
#endif

/* The filesystem type holding path, or -- when path does not exist yet
 * -- its nearest existing ancestor's: the filesystem a directory the
 * package creates will land on.  0 ok, -1 cannot tell. */
static int fs_type(const char *path, char *type, unsigned cap)
{
    struct statvfs sv;
    char *p;
    char *s;

    p = xstrdup(path);
    for (;;) {
        if (statvfs(p, &sv) == 0)
            break;
        if (errno != ENOENT && errno != ENOTDIR) {
            free(p);
            return -1;
        }
        s = strrchr(p, '/');
        if (s == NULL || (s == p && p[1] == '\0')) {
            free(p);
            return -1;
        }
        if (s == p)
            p[1] = '\0';
        else
            *s = '\0';
    }
#ifdef FSTYPSZ
    {
        unsigned n;

        n = 0;
        while (n < (unsigned)FSTYPSZ && sv.f_basetype[n] != '\0')
            n++;
        copy_type(type, cap, sv.f_basetype, n);
    }
#else
    host_fstype(p, type, cap);
#endif
    free(p);
    return 0;
}

/* one directory against the list; EX_OK or EX_DEPS (message printed) */
static int check_dir(const char *name, const char *want, const char *dir)
{
    char type[32];

    if (fs_type(dir, type, sizeof(type)) != 0) {
        warnx2("%s: refused: it installs only on %s, and the filesystem "
               "of %s cannot be read", name, want, dir);
        return EX_DEPS;
    }
    if (!in_list(want, type)) {
        warnx2("%s: refused: it installs only on %s, and %s is on %s%s",
               name, want, dir, type[0] != '\0' ? type : "(unnamed)",
               strcmp(type, "s5") == 0 ?
                   ", which cuts file names at 14 bytes" : "");
        return EX_DEPS;
    }
    note("%s: %s is on %s (%s=%s)", name, dir, type, APKG_FSTYPE_PARAM,
         want);
    return EX_OK;
}

/* <pfx><base>/<rel>, or <pfx><rel> for an absolute rel; one slash at
 * each join.  rel may be "" (the base itself). */
static char *join_path(const char *pfx, const char *base, const char *rel,
                       unsigned rlen)
{
    char *out;
    unsigned n;

    out = xmalloc((unsigned)(strlen(pfx) + strlen(base) + rlen + 3));
    strcpy(out, pfx);
    n = (unsigned)strlen(out);
    if (rlen == 0 || rel[0] != '/') {
        if (base[0] != '/' && (n == 0 || out[n - 1] != '/'))
            out[n++] = '/';
        strcpy(out + n, base);
        n = (unsigned)strlen(out);
        if (rlen > 0 && (n == 0 || out[n - 1] != '/'))
            out[n++] = '/';
    } else if (n > 0 && out[n - 1] == '/') {
        n--;
    }
    memcpy(out + n, rel, rlen);
    out[n + rlen] = '\0';
    /* no trailing slash (but keep "/") */
    n = (unsigned)strlen(out);
    while (n > 1 && out[n - 1] == '/')
        out[--n] = '\0';
    if (n == 0)
        strcpy(out, "/");
    return out;
}

/* every pkgmap(4) object named longer than 14 bytes: its directory.
 * Lines are "[part] <ftype> <class> <path>[=<target>] ..."; i lines (the
 * control files under /var/sadm) and ':' / '#' lines are not objects. */
static int check_pkgmap(const char *name, const char *want, const char *pfx,
                        const char *base, char *text, int *nchecked)
{
    char *line;
    char *next;
    char *tok[4];
    char *p;
    char *slash;
    char *dir;
    char *last;
    unsigned plen;
    int nt;
    int rc;

    last = NULL;
    rc = EX_OK;
    for (line = text; rc == EX_OK && line != NULL && *line != '\0';
         line = next) {
        next = strchr(line, '\n');
        if (next != NULL)
            *next++ = '\0';
        nt = 0;
        p = line;
        while (nt < 4) {
            while (*p == ' ' || *p == '\t' || *p == '\r')
                p++;
            if (*p == '\0')
                break;
            tok[nt++] = p;
            while (*p != '\0' && *p != ' ' && *p != '\t' && *p != '\r')
                p++;
            if (*p != '\0')
                *p++ = '\0';
        }
        if (nt == 0 || tok[0][0] == ':' || tok[0][0] == '#')
            continue;
        if (tok[0][0] >= '0' && tok[0][0] <= '9') {    /* part number */
            tok[0] = tok[1];
            tok[1] = tok[2];
            tok[2] = tok[3];
            nt--;
        }
        if (nt < 3 || tok[0][1] != '\0' || tok[0][0] == 'i')
            continue;
        p = strchr(tok[2], '=');               /* s and l: path=target */
        plen = p != NULL ? (unsigned)(p - tok[2]) : (unsigned)strlen(tok[2]);
        tok[2][plen] = '\0';
        slash = strrchr(tok[2], '/');
        if (strlen(slash != NULL ? slash + 1 : tok[2]) <= S5_NAME_MAX)
            continue;
        plen = slash != NULL ? (unsigned)(slash - tok[2]) : 0;
        if (plen == 0 && tok[2][0] == '/')
            plen = 1;                           /* "/name": the root */
        dir = join_path(pfx, base, tok[2], plen);
        if (last != NULL && strcmp(last, dir) == 0) {
            free(dir);
            continue;
        }
        rc = check_dir(name, want, dir);
        (*nchecked)++;
        if (last != NULL)
            free(last);
        last = dir;
    }
    if (last != NULL)
        free(last);
    return rc;
}

int fs_check(const struct conf *cf, const char *name, const char *staged)
{
    char why[256];
    char *info;
    char *map;
    char *want;
    char *base;
    char *pfx;
    char *dir;
    int nchecked;
    int rc;

    if (ds_member(staged, "pkginfo", &info, why, sizeof(why)) != 0) {
        note("%s: no pkginfo read from %s (%s); no %s check", name,
             staged, why, APKG_FSTYPE_PARAM);
        return EX_OK;
    }
    want = pkginfo_get(info, APKG_FSTYPE_PARAM);
    if (want == NULL) {
        free(info);
        return EX_OK;                           /* unmarked: as before */
    }
    base = pkginfo_get(info, "BASEDIR");
    free(info);
    if (base != NULL && base[0] == '\0') {
        free(base);
        base = NULL;
    }
    if (!fstype_list_ok(want)) {
        warnx2("%s: refused: %s=%s is not a list of filesystem types",
               name, APKG_FSTYPE_PARAM, want);
        free(want);
        if (base != NULL)
            free(base);
        return EX_VERIFY;
    }
    pfx = cat2(cf->root, cf->target);
    rc = EX_OK;
    nchecked = 0;
    if (ds_member(staged, "pkgmap", &map, why, sizeof(why)) == 0) {
        rc = check_pkgmap(name, want, pfx, base != NULL ? base : "/", map,
                          &nchecked);
        free(map);
    }
    if (rc == EX_OK && nchecked == 0) {     /* no long name: the base */
        dir = join_path(pfx, base != NULL ? base : "/", "", 0);
        rc = check_dir(name, want, dir);
        free(dir);
    }
    free(pfx);
    free(want);
    if (base != NULL)
        free(base);
    return rc;
}
