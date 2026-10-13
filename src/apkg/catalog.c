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
    unsigned len;

    cat->ents = NULL;
    cat->n = 0;
    cat->cap = 0;

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

    lineno = 1;
    while (fgets(line, (int)sizeof(line), fp) != NULL) {
        lineno++;
        len = (unsigned)strlen(line);
        if (len == sizeof(line) - 1 && line[len - 1] != '\n') {
            warnx2("%s:%d: line too long", path, lineno);
            fclose(fp);
            catalog_free(cat);
            return CAT_EFORMAT;
        }
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (line[0] == '\0' || line[0] == '#')
            continue;
        if (parse_entry(line, &e, path, lineno) != 0) {
            fclose(fp);
            catalog_free(cat);
            return CAT_EFORMAT;
        }
        if (cat->n == cat->cap) {
            cat->cap = cat->cap == 0 ? 16 : cat->cap * 2;
            cat->ents = (struct pkgent *)xrealloc((char *)cat->ents,
                (unsigned)(cat->cap * sizeof(struct pkgent)));
        }
        cat->ents[cat->n] = e;
        cat->n++;
    }
    fclose(fp);
    return CAT_OK;
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
}
