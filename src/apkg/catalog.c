/*
 * catalog.c - apkg catalog (v1) parsing.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Format (docs/design.md section 2): the first line must be exactly
 * "#apkg-catalog 1".  After that, '#' comment lines and blank lines
 * are ignored; every other line is one package:
 *
 *   name|version|pkginst|filename|md5|size|deps|category|description[|offset]
 *
 * deps is a comma-separated list of package NAMES or the word "none".
 * The 10th field, offset, is OPTIONAL: a decimal byte offset the RAW
 * source addresses the package by (gen-catalog.py --raw emits it).  A
 * 9-field line - every HTTP/FILE catalog - leaves offset = -1, which the
 * RAW source treats as "no offset, refuse" (fail closed).  No field may
 * contain '|'.  Parsing is defensive: wrong field count, empty mandatory
 * fields, a non-hex md5, a non-numeric size/offset or an unsafe filename
 * reject the catalog (CAT_EFORMAT) with a line number on stderr, rather
 * than limping on with garbage.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "apkg.h"

#define NFIELDS_MIN 9    /* name..description                          */
#define NFIELDS_MAX 10   /* ... + optional offset (RAW source)         */
#define MAXLINE 2048

static int hex32(const char *s)
{
    int i;

    for (i = 0; i < 32; i++) {
        if (!isxdigit((unsigned char)s[i]))
            return 0;
    }
    return s[32] == '\0';
}

static int all_digits(const char *s)
{
    if (*s == '\0')
        return 0;
    while (*s != '\0') {
        if (!isdigit((unsigned char)*s))
            return 0;
        s++;
    }
    return 1;
}

/* SECURITY: the filename field reaches a URL (<repo>/pkgs/<filename>),
 * a shell pipeline (the zcat step) and filesystem paths (its basename
 * becomes the cache file), so the character set stays tight:
 * [A-Za-z0-9._+-] plus '/' as a separator for the categorized repo
 * subdirectories (stock/, base/, test/, ...).  Nothing that could
 * escape the pkgs/ tree or the cache is allowed: no leading '/', no
 * "." or ".." components, no empty components ("//"), no trailing
 * '/', no leading dot. */
static int safe_filename(const char *s)
{
    const char *comp;

    if (*s == '\0' || *s == '/' || *s == '.')
        return 0;
    comp = s;
    while (*s != '\0') {
        if (*s == '/') {
            /* component just ended: reject "", ".", ".." */
            if (s == comp ||
                (s - comp == 1 && comp[0] == '.') ||
                (s - comp == 2 && comp[0] == '.' && comp[1] == '.'))
                return 0;
            comp = s + 1;
        } else if (!isalnum((unsigned char)*s) && *s != '.' &&
                   *s != '_' && *s != '+' && *s != '-') {
            return 0;
        }
        s++;
    }
    /* final component: empty means trailing '/'; "."/".." traverse */
    if (s == comp ||
        (s - comp == 1 && comp[0] == '.') ||
        (s - comp == 2 && comp[0] == '.' && comp[1] == '.'))
        return 0;
    return 1;
}

/* plain names (name, pkginst, version, category): printable, no
 * whitespace, no '|' (already impossible), no '/' */
static int safe_word(const char *s)
{
    if (*s == '\0')
        return 0;
    while (*s != '\0') {
        if (!isprint((unsigned char)*s) ||
            isspace((unsigned char)*s) || *s == '/')
            return 0;
        s++;
    }
    return 1;
}

static void ent_free(struct pkgent *e)
{
    int i;

    free(e->name);
    free(e->version);
    free(e->pkginst);
    free(e->filename);
    free(e->md5);
    free(e->category);
    free(e->desc);
    for (i = 0; i < e->ndeps; i++)
        free(e->deps[i]);
    free((char *)e->deps);
    if (e->kspace) {
        free(e->role);
        free(e->kline);
        free(e->kabi);
        free(e->pin);
        free(e->sha256);
        free(e->loaderv);
        if (e->kpkginst != NULL)
            free(e->kpkginst);
        if (e->refused != NULL)
            free(e->refused);
    }
}

/* ---------------- the kernel-space block (#ext kpkg 1) ----------------
 *
 * amix-dlm docs/contracts/C2-2-kpkg.md §1, version 3 (2026-10-26):
 *
 *   #ext kpkg 1
 *   #kpkg <name> <version> role=<kernel|module> line=<k30|k46>
 *         kabi=<tag> pin=<compiler pin> size=<bytes> sha256=<64 hex>
 *         file=<datastream>                          (one line each)
 *   #kpkg <name> <version> role=loader line=any loader=<n> size=<bytes>
 *         sha256=<64 hex> file=<datastream>
 *
 * The keys are role-dependent (§1.1): an entry lacking a key its role
 * requires, or carrying one its role excludes (kabi=/pin= on a loader),
 * is refused.
 *   #ksig <key-id> <file>                            (optional; absent in 1.1)
 *   #end kpkg
 *
 * After the name and the version the attributes are key=value in any
 * order.  An unknown key is ignored; an unknown key starting with '!'
 * refuses the ENTRY.  Version 2 names two optional keys, both read here:
 * pkginst= (the SVR4 instance; otherwise taken from the datastream's
 * header) and offset= (the byte offset on a RAW medium, as the ordinary
 * 10th field).
 *
 * What refuses the WHOLE catalog (fail closed, like an unsafe filename):
 * an unterminated block, an ordinary entry line inside it, a second
 * block, a #kpkg line without a usable name and version, and a name
 * used twice.  What refuses only the ENTRY (kept, marked, never
 * installable): a missing or malformed required key, a '!' key, a
 * duplicate key.  A block of another version is skipped whole, so a
 * later format never breaks this client.
 */

/* a name that is also a safe record file name under /var/apkg/kpkg */
static int safe_kname(const char *s)
{
    if (*s == '\0' || *s == '.' || *s == '-')
        return 0;
    while (*s != '\0') {
        if (!isalnum((unsigned char)*s) && *s != '.' && *s != '_' &&
            *s != '+' && *s != '-')
            return 0;
        s++;
    }
    return 1;
}

static int hex64(const char *s)
{
    int i;

    for (i = 0; i < 64; i++) {
        if (!isxdigit((unsigned char)s[i]))
            return 0;
    }
    return s[64] == '\0';
}

/* record the first refusal reason only */
static void krefuse(struct pkgent *e, const char *why, const char *what)
{
    if (e->refused != NULL)
        return;
    e->refused = cat3(why, what != NULL ? " " : "", what != NULL ? what : "");
}

/* a key seen twice refuses the entry; returns 1 for the repeat */
static int kdup(int *seen, struct pkgent *e, const char *key)
{
    if (*seen) {
        krefuse(e, "duplicate key", key);
        return 1;
    }
    *seen = 1;
    return 0;
}

/* parse one "#kpkg ..." line (writable) into e.  Returns 0 (entry
 * parsed; e->refused may be set) or -1 (catalog format error). */
static int parse_kpkg(char *line, struct pkgent *e, const char *path,
                      int lineno)
{
    char *tok[64];
    char *p;
    char *eq;
    char *key;
    char *val;
    int nt;
    int i;
    int seen_role, seen_line, seen_kabi, seen_pin, seen_size, seen_sha,
        seen_file, seen_pkginst, seen_offset, seen_loader;
    int loader;

    nt = 0;
    p = line;
    for (;;) {
        while (*p == ' ' || *p == '\t')
            p++;
        if (*p == '\0')
            break;
        if (nt == 64) {
            warnx2("%s:%d: too many fields on a #kpkg line", path, lineno);
            return -1;
        }
        tok[nt++] = p;
        while (*p != '\0' && *p != ' ' && *p != '\t')
            p++;
        if (*p != '\0')
            *p++ = '\0';
    }
    /* tok[0] is "#kpkg" */
    if (nt < 3 || !safe_kname(tok[1]) || !safe_word(tok[2]) ||
        strchr(tok[1], '=') != NULL || strchr(tok[2], '=') != NULL) {
        warnx2("%s:%d: #kpkg needs a name and a version", path, lineno);
        return -1;
    }
    memset((char *)e, 0, sizeof(*e));
    e->kspace = 1;
    e->offset = -1;
    e->name = xstrdup(tok[1]);
    e->version = xstrdup(tok[2]);
    seen_role = seen_line = seen_kabi = seen_pin = seen_size = seen_sha =
        seen_file = seen_pkginst = seen_offset = seen_loader = 0;
    for (i = 3; i < nt; i++) {
        eq = strchr(tok[i], '=');
        if (eq == NULL || eq == tok[i]) {
            krefuse(e, "malformed attribute", tok[i]);
            continue;
        }
        *eq = '\0';
        key = tok[i];
        val = eq + 1;
        if (strcmp(key, "role") == 0) {
            if (kdup(&seen_role, e, key))
                continue;
            if (strcmp(val, "kernel") != 0 && strcmp(val, "loader") != 0 &&
                strcmp(val, "module") != 0)
                krefuse(e, "unknown role", val);
            e->role = xstrdup(val);
        } else if (strcmp(key, "line") == 0) {
            if (kdup(&seen_line, e, key))
                continue;
            e->kline = xstrdup(val);       /* checked per role below */
        } else if (strcmp(key, "kabi") == 0) {
            if (kdup(&seen_kabi, e, key))
                continue;
            if (!safe_word(val))
                krefuse(e, "bad kabi", val);
            e->kabi = xstrdup(val);
        } else if (strcmp(key, "pin") == 0) {
            if (kdup(&seen_pin, e, key))
                continue;
            if (!safe_word(val))
                krefuse(e, "bad pin", val);
            e->pin = xstrdup(val);
        } else if (strcmp(key, "size") == 0) {
            if (kdup(&seen_size, e, key))
                continue;
            if (!all_digits(val) || strlen(val) > 10)
                krefuse(e, "bad size", val);
            else
                e->size = atol(val);
        } else if (strcmp(key, "sha256") == 0) {
            if (kdup(&seen_sha, e, key))
                continue;
            if (!hex64(val))
                krefuse(e, "sha256 is not 64 hex chars", NULL);
            e->sha256 = xstrdup(val);
        } else if (strcmp(key, "file") == 0) {
            if (kdup(&seen_file, e, key))
                continue;
            if (!safe_filename(val))
                krefuse(e, "unsafe file", val);
            else
                e->filename = xstrdup(val);
        } else if (strcmp(key, "loader") == 0) {
            if (kdup(&seen_loader, e, key))
                continue;
            if (!all_digits(val) || strlen(val) > 9)
                krefuse(e, "bad loader", val);
            e->loaderv = xstrdup(val);
        } else if (strcmp(key, "pkginst") == 0) {
            if (kdup(&seen_pkginst, e, key))
                continue;
            if (!safe_kname(val) || strlen(val) > 32)
                krefuse(e, "bad pkginst", val);
            else
                e->kpkginst = xstrdup(val);
        } else if (strcmp(key, "offset") == 0) {
            if (kdup(&seen_offset, e, key))
                continue;
            if (!all_digits(val) || strlen(val) > 10)
                krefuse(e, "bad offset", val);
            else
                e->offset = atol(val);
        } else if (key[0] == '!') {
            krefuse(e, "unknown mandatory key", key);
        }
        /* any other key: ignored (C2-2 §1) */
    }
    /* the keys each role requires and excludes (C2-2 v3 §1.1): kernel and
     * module carry line=k30|k46, kabi=, pin=; the loader carries
     * line=any and loader=<n>, and never kabi= or pin= */
    loader = e->role != NULL && strcmp(e->role, "loader") == 0;
    if (!seen_role)
        krefuse(e, "missing key", "role=");
    if (!seen_line)
        krefuse(e, "missing key", "line=");
    else if (loader && strcmp(e->kline, "any") != 0)
        krefuse(e, "a loader needs line=any, not", e->kline);
    else if (!loader && strcmp(e->kline, "k30") != 0 &&
             strcmp(e->kline, "k46") != 0)
        krefuse(e, "unknown line", e->kline);
    if (loader) {
        if (seen_kabi)
            krefuse(e, "a loader entry may not carry", "kabi= (C2-2 v3 §1.1)");
        if (seen_pin)
            krefuse(e, "a loader entry may not carry", "pin= (C2-2 v3 §1.1)");
        if (!seen_loader)
            krefuse(e, "missing key", "loader= (C2-2 v3 §1.1)");
    } else {
        if (!seen_kabi)
            krefuse(e, "missing key", "kabi= (C2-2 v3 §1.1)");
        if (!seen_pin)
            krefuse(e, "missing key", "pin= (C2-2 v3 §1.1)");
    }
    if (!seen_size)
        krefuse(e, "missing key", "size=");
    if (!seen_sha)
        krefuse(e, "missing key", "sha256=");
    if (!seen_file)
        krefuse(e, "missing key", "file=");

    /* the ordinary fields every verb prints, filled so no caller needs
     * to know an entry is kernel space just to display it */
    if (e->role == NULL)
        e->role = xstrdup("?");
    if (e->kline == NULL)
        e->kline = xstrdup("?");
    if (e->kabi == NULL)
        e->kabi = xstrdup(loader ? "-" : "?");
    if (e->pin == NULL)
        e->pin = xstrdup(loader ? "-" : "?");
    if (e->loaderv == NULL)
        e->loaderv = xstrdup("-");
    if (e->sha256 == NULL)
        e->sha256 = xstrdup("");
    for (i = 0; e->sha256[i] != '\0'; i++)
        e->sha256[i] = (char)tolower((unsigned char)e->sha256[i]);
    if (e->filename == NULL)
        e->filename = xstrdup("-");
    e->pkginst = xstrdup(e->kpkginst != NULL ? e->kpkginst : e->name);
    e->md5 = xstrdup("");
    e->category = xstrdup(e->role);
    e->desc = xmalloc((unsigned)(strlen(e->role) + strlen(e->kline) +
                                 strlen(e->kabi) + strlen(e->loaderv) + 40));
    if (loader)
        sprintf(e->desc, "kernel-space loader %s, line %s", e->loaderv,
                e->kline);
    else
        sprintf(e->desc, "kernel-space %s, line %s, kabi %s",
                e->role, e->kline, e->kabi);
    e->deps = NULL;
    e->ndeps = 0;
    if (e->refused != NULL)
        note("%s:%d: kernel-space entry %s refused: %s",
             path, lineno, e->name, e->refused);
    return 0;
}

/* "#ext kpkg <n>" -> n, or -1 when the line is not that header */
static int kpkg_ext_version(const char *line)
{
    const char *p;

    if (strncmp(line, KPKG_EXT, sizeof(KPKG_EXT) - 1) != 0)
        return -1;
    p = line + sizeof(KPKG_EXT) - 1;
    if (*p != ' ' && *p != '\t')
        return -1;
    while (*p == ' ' || *p == '\t')
        p++;
    if (!isdigit((unsigned char)*p))
        return 0;      /* malformed version: treated as "not ours" */
    return atoi(p);
}

static int is_kend(const char *line)
{
    unsigned n;

    n = (unsigned)strlen(line);
    while (n > 0 && (line[n - 1] == ' ' || line[n - 1] == '\t'))
        n--;
    return n == sizeof(KPKG_END) - 1 &&
           strncmp(line, KPKG_END, sizeof(KPKG_END) - 1) == 0;
}

static int has_word_prefix(const char *line, const char *w)
{
    unsigned n;

    n = (unsigned)strlen(w);
    return strncmp(line, w, n) == 0 &&
           (line[n] == ' ' || line[n] == '\t');
}

static int parse_deps(const char *field, struct pkgent *e)
{
    char *copy;
    char *p;
    char *tok;
    int n;

    e->deps = NULL;
    e->ndeps = 0;
    if (strcmp(field, "none") == 0 || field[0] == '\0')
        return 0;
    copy = xstrdup(field);
    n = 0;
    p = copy;
    for (;;) {
        tok = p;
        p = strchr(p, ',');
        if (p != NULL)
            *p = '\0';
        if (tok[0] == '\0' || !safe_word(tok)) {
            free(copy);
            return -1;
        }
        e->deps = (char **)xrealloc((char *)e->deps,
                                    (unsigned)((n + 1) * sizeof(char *)));
        e->deps[n] = xstrdup(tok);
        n++;
        if (p == NULL)
            break;
        p++;
    }
    e->ndeps = n;
    free(copy);
    return 0;
}

/* split a writable line on '|' into up to NFIELDS_MAX fields; returns
 * the field count, or -1 when the line has more than NFIELDS_MAX */
static int split_fields(char *line, char *fields[NFIELDS_MAX])
{
    int n;
    char *p;

    n = 0;
    p = line;
    fields[n++] = p;
    while ((p = strchr(p, '|')) != NULL) {
        *p = '\0';
        p++;
        if (n == NFIELDS_MAX)
            return -1;
        fields[n++] = p;
    }
    return n;
}

static int parse_entry(char *line, struct pkgent *e, const char *path,
                       int lineno)
{
    char *f[NFIELDS_MAX];
    int nf;
    int i;

    nf = split_fields(line, f);
    if (nf != NFIELDS_MIN && nf != NFIELDS_MAX) {
        warnx2("%s:%d: expected %d or %d '|'-separated fields",
               path, lineno, NFIELDS_MIN, NFIELDS_MAX);
        return -1;
    }
    for (i = 0; i < nf; i++) {
        /* trim spaces around every field except the description (f[8]) */
        if (i != 8) {
            while (*f[i] == ' ' || *f[i] == '\t')
                f[i]++;
        }
    }
    if (!safe_word(f[0]) || !safe_word(f[1]) || !safe_word(f[2])) {
        warnx2("%s:%d: bad name/version/pkginst field", path, lineno);
        return -1;
    }
    if (!safe_filename(f[3])) {
        warnx2("%s:%d: unsafe filename '%s'", path, lineno, f[3]);
        return -1;
    }
    if (!hex32(f[4])) {
        warnx2("%s:%d: md5 is not 32 hex chars", path, lineno);
        return -1;
    }
    if (!all_digits(f[5])) {
        warnx2("%s:%d: size is not numeric", path, lineno);
        return -1;
    }
    if (!safe_word(f[7])) {
        warnx2("%s:%d: bad category field", path, lineno);
        return -1;
    }
    if (nf == NFIELDS_MAX && !all_digits(f[9])) {
        warnx2("%s:%d: offset is not numeric", path, lineno);
        return -1;
    }

    memset((char *)e, 0, sizeof(*e));
    e->offset = -1;                     /* absent -> RAW refuses */
    if (parse_deps(f[6], e) != 0) {
        warnx2("%s:%d: bad deps field '%s'", path, lineno, f[6]);
        return -1;
    }
    e->name = xstrdup(f[0]);
    e->version = xstrdup(f[1]);
    e->pkginst = xstrdup(f[2]);
    e->filename = xstrdup(f[3]);
    e->md5 = xstrdup(f[4]);
    e->size = atol(f[5]);
    e->category = xstrdup(f[7]);
    e->desc = xstrdup(f[8]);
    if (nf == NFIELDS_MAX)
        e->offset = atol(f[9]);
    e->mark = 0;
    /* normalise md5 to lowercase for later comparison */
    for (i = 0; e->md5[i] != '\0'; i++)
        e->md5[i] = (char)tolower((unsigned char)e->md5[i]);
    return 0;
}

int catalog_load(const char *path, struct catalog *cat)
{
    FILE *fp;
    char line[MAXLINE];
    struct pkgent e;
    int lineno;
    int block;
    int seen_block;
    unsigned len;

    cat->ents = NULL;
    cat->n = 0;
    cat->cap = 0;
    cat->nk = 0;
    cat->ksig_key = NULL;
    cat->ksig_file = NULL;
    cat->kverified = 0;

    fp = fopen(path, "r");
    if (fp == NULL)
        return CAT_ENOENT;

    /* header line */
    if (fgets(line, (int)sizeof(line), fp) == NULL) {
        fclose(fp);
        return CAT_EBADHDR;
    }
    len = (unsigned)strlen(line);
    while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r' ||
                       line[len - 1] == ' ' || line[len - 1] == '\t'))
        line[--len] = '\0';
    if (strcmp(line, CATALOG_MAGIC) != 0) {
        fclose(fp);
        return CAT_EBADHDR;
    }

    /* block: 0 = outside, 1 = inside a kpkg 1 block, 2 = inside a
     * kpkg block of another version (skipped whole) */
    block = 0;
    seen_block = 0;
    lineno = 1;
    while (fgets(line, (int)sizeof(line), fp) != NULL) {
        lineno++;
        len = (unsigned)strlen(line);
        /* the same bound a 0.2.x client applies to EVERY line, comment
         * or not: a block line this long would brick the old client, so
         * this one refuses it too (C2-2 §1: every line under 2048 B) */
        if (len == sizeof(line) - 1 && line[len - 1] != '\n') {
            warnx2("%s:%d: line too long", path, lineno);
            goto bad;
        }
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (block != 0) {
            if (line[0] == '\0')
                continue;
            if (line[0] != '#') {
                warnx2("%s:%d: ordinary entry inside the kernel-space "
                       "block", path, lineno);
                goto bad;
            }
            if (is_kend(line)) {
                block = 0;
                continue;
            }
            if (block == 2)
                continue;
            if (kpkg_ext_version(line) >= 0) {
                warnx2("%s:%d: kernel-space block opened twice", path,
                       lineno);
                goto bad;
            }
            if (has_word_prefix(line, "#kpkg")) {
                if (parse_kpkg(line, &e, path, lineno) != 0)
                    goto bad;
                if (catalog_find(cat, e.name) != NULL) {
                    warnx2("%s:%d: package name %s used twice", path,
                           lineno, e.name);
                    ent_free(&e);
                    goto bad;
                }
                cat->nk++;
                goto add;
            }
            if (has_word_prefix(line, "#ksig")) {
                char *k, *f, *q;

                k = line + 5;
                while (*k == ' ' || *k == '\t')
                    k++;
                q = k;
                while (*q != '\0' && *q != ' ' && *q != '\t')
                    q++;
                f = q;
                while (*f == ' ' || *f == '\t')
                    f++;
                if (*q != '\0')
                    *q = '\0';
                if (*k != '\0' && *f != '\0' && cat->ksig_key == NULL) {
                    q = f;
                    while (*q != '\0' && *q != ' ' && *q != '\t')
                        q++;
                    *q = '\0';
                    cat->ksig_key = xstrdup(k);
                    cat->ksig_file = xstrdup(f);
                }
                continue;
            }
            continue;       /* any other comment inside the block */
        }
        if (line[0] == '#') {
            int v;

            v = kpkg_ext_version(line);
            if (v >= 0) {
                if (seen_block) {
                    warnx2("%s:%d: kernel-space block opened twice", path,
                           lineno);
                    goto bad;
                }
                seen_block = 1;
                if (v == KPKG_VERSION) {
                    block = 1;
                } else {
                    note("%s:%d: kernel-space block version %d is not "
                         "this client's (%d); skipped", path, lineno, v,
                         KPKG_VERSION);
                    block = 2;
                }
            }
            continue;
        }
        if (line[0] == '\0')
            continue;
        if (parse_entry(line, &e, path, lineno) != 0)
            goto bad;
    add:
        if (cat->n == cat->cap) {
            cat->cap = cat->cap == 0 ? 16 : cat->cap * 2;
            cat->ents = (struct pkgent *)xrealloc((char *)cat->ents,
                (unsigned)(cat->cap * sizeof(struct pkgent)));
        }
        cat->ents[cat->n] = e;
        cat->n++;
    }
    fclose(fp);
    if (block != 0) {
        warnx2("%s: kernel-space block has no '%s' line", path, KPKG_END);
        catalog_free(cat);
        return CAT_EFORMAT;
    }
    kspace_verify_hook(cat);
    return CAT_OK;
bad:
    fclose(fp);
    catalog_free(cat);
    return CAT_EFORMAT;
}

struct pkgent *catalog_find(struct catalog *cat, const char *name)
{
    int i;

    for (i = 0; i < cat->n; i++) {
        if (strcmp(cat->ents[i].name, name) == 0)
            return &cat->ents[i];
    }
    return NULL;
}

void catalog_free(struct catalog *cat)
{
    int i;

    for (i = 0; i < cat->n; i++)
        ent_free(&cat->ents[i]);
    free((char *)cat->ents);
    cat->ents = NULL;
    cat->n = 0;
    cat->cap = 0;
    cat->nk = 0;
    if (cat->ksig_key != NULL)
        free(cat->ksig_key);
    if (cat->ksig_file != NULL)
        free(cat->ksig_file);
    cat->ksig_key = NULL;
    cat->ksig_file = NULL;
}
