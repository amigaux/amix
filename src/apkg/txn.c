/*
 * txn.c - apkg's transaction journal, /var/apkg/txn (40 §6, P-28 D63).
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * A transaction is journaled from the moment every package in it is
 * staged and verified (nothing is journaled that has not passed its
 * hash) until apkg has finished it.  The journal says, per package,
 * whether its pkgadd (and, for kernel space, its install record) or its
 * pkgrm is done, and where the staged datastream is; and for the whole
 * transaction whether the kbootset trigger is still owed.  `apkg recover`
 * reads it and finishes the work (install.c).  apkg's journal is its own:
 * kbootset keeps a separate one (C2-4, --journal), and the boot path's
 * atomicity comes from kbootset's generation commit, not from this file.
 *
 * Format: text, one record per line, fields separated by one space, the
 * file replaced whole (write <txn>.new, then rename) at every change:
 *
 *   apkg-txn 1
 *   verb <install|upgrade|remove>
 *   state <installing|installed|built>
 *   started <seconds since 1970>
 *   kspace <0|1>
 *   pkg <done> <ow> <kspace> <size> <name> <version> <pkginst> <hash>
 *       <staged> <role> <line> <kabi> <pin> <sha256> <source>
 *
 * Absent values are "-".  <hash> is the catalog's md5 (userland) or
 * sha256 (kernel space) of <staged>, or "-" when <staged> is not the
 * verified datastream itself (a .Z decompressed into the cache); <size>
 * is <staged>'s size when it was journaled.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "apkg.h"

#define TXN_MAGIC "apkg-txn 1"
#define TXN_FIELDS 15

static const char *dash(const char *s)
{
    return (s == NULL || s[0] == '\0') ? "-" : s;
}

static int has_space(const char *s)
{
    if (s == NULL)
        return 0;
    while (*s != '\0') {
        if (*s == ' ' || *s == '\t' || *s == '\n')
            return 1;
        s++;
    }
    return 0;
}

void txn_init(struct txn *t, const char *verb)
{
    memset((char *)t, 0, sizeof(*t));
    strncpy(t->verb, verb, sizeof(t->verb) - 1);
    strcpy(t->state, "installing");
    t->started = (long)time((time_t *)0);
}

void txn_add(struct txn *t, const struct pkgent *e, const char *pkginst,
             const char *staged, int ow, const char *source)
{
    struct txnpkg *p;
    unsigned l;
    int z;

    t->p = (struct txnpkg *)xrealloc((char *)t->p,
        (unsigned)((t->n + 1) * sizeof(struct txnpkg)));
    p = &t->p[t->n++];
    memset((char *)p, 0, sizeof(*p));
    p->ow = ow;
    p->kspace = e->kspace;
    if (e->kspace)
        t->kspace = 1;
    p->name = xstrdup(e->name);
    p->version = xstrdup(e->version);
    p->pkginst = xstrdup(dash(pkginst));
    p->staged = xstrdup(dash(staged));
    l = (unsigned)strlen(e->filename);
    z = l >= 2 && strcmp(e->filename + l - 2, ".Z") == 0;
    if (strcmp(p->staged, "-") == 0 || z)
        p->hash = xstrdup("-");
    else
        p->hash = xstrdup(dash(e->kspace ? e->sha256 : e->md5));
    p->size = strcmp(p->staged, "-") == 0 ? -1 : file_size(p->staged);
    p->role = xstrdup(dash(e->kspace ? e->role : NULL));
    p->kline = xstrdup(dash(e->kspace ? e->kline : NULL));
    p->kabi = xstrdup(dash(e->kspace ? e->kabi : NULL));
    p->pin = xstrdup(dash(e->kspace ? e->pin : NULL));
    p->sha256 = xstrdup(dash(e->kspace ? e->sha256 : NULL));
    p->source = xstrdup(dash(source));
}

void txn_free(struct txn *t)
{
    int i;
    struct txnpkg *p;

    for (i = 0; i < t->n; i++) {
        p = &t->p[i];
        free(p->name);
        free(p->version);
        free(p->pkginst);
        free(p->hash);
        free(p->staged);
        free(p->role);
        free(p->kline);
        free(p->kabi);
        free(p->pin);
        free(p->sha256);
        free(p->source);
    }
    if (t->p != NULL)
        free((char *)t->p);
    t->p = NULL;
    t->n = 0;
}

int txn_exists(const struct conf *cf)
{
    return file_exists(cf->txnfile);
}

/* A transaction left behind blocks the next one: two transactions must
 * never interleave on one target.  Under -n this only warns. */
int txn_refuse_if_pending(const struct conf *cf)
{
    if (!txn_exists(cf))
        return 0;
    if (opt_dryrun) {
        warnx2("an unfinished transaction is journaled in %s "
               "(apkg recover finishes it)", cf->txnfile);
        return 0;
    }
    warnx2("an unfinished transaction is journaled in %s", cf->txnfile);
    warnx2("run 'apkg recover' to finish it (or 'apkg -f recover' to "
           "discard the journal)");
    return -1;
}

int txn_save(const struct conf *cf, const struct txn *t)
{
    char *dir;
    char *tmp;
    FILE *fp;
    const struct txnpkg *p;
    int i;

    if (opt_dryrun)
        return 0;
    for (i = 0; i < t->n; i++) {
        p = &t->p[i];
        if (has_space(p->staged) || has_space(p->source) ||
            has_space(p->pkginst)) {
            warnx2("cannot journal %s: a path holds a blank (%s)",
                   p->name, p->staged);
            return -1;
        }
    }
    dir = dirname_of(cf->txnfile);
    if (mkpath(dir) != 0) {
        warnx2("cannot create %s", dir);
        free(dir);
        return -1;
    }
    free(dir);
    tmp = cat2(cf->txnfile, ".new");
    fp = fopen(tmp, "w");
    if (fp == NULL) {
        warnx2("cannot write the journal %s", tmp);
        free(tmp);
        return -1;
    }
    fprintf(fp, "%s\n", TXN_MAGIC);
    fprintf(fp, "verb %s\n", t->verb);
    fprintf(fp, "state %s\n", t->state);
    fprintf(fp, "started %ld\n", t->started);
    fprintf(fp, "kspace %d\n", t->kspace);
    for (i = 0; i < t->n; i++) {
        p = &t->p[i];
        fprintf(fp, "pkg %d %d %d %ld %s %s %s %s %s %s %s %s %s %s %s\n",
                p->done, p->ow, p->kspace, p->size, p->name, p->version,
                p->pkginst, p->hash, p->staged, p->role, p->kline,
                p->kabi, p->pin, p->sha256, p->source);
    }
    if (fclose(fp) != 0 || rename(tmp, cf->txnfile) != 0) {
        warnx2("cannot write the journal %s", cf->txnfile);
        unlink(tmp);
        free(tmp);
        return -1;
    }
    free(tmp);
    return 0;
}

void txn_clear(const struct conf *cf)
{
    if (opt_dryrun)
        return;
    if (unlink(cf->txnfile) != 0 && file_exists(cf->txnfile))
        warnx2("cannot remove the journal %s", cf->txnfile);
}

/* split a writable line on single blanks; returns the field count */
static int split_blank(char *s, char **f, int max)
{
    int n;

    n = 0;
    while (*s != '\0' && n < max) {
        while (*s == ' ')
            s++;
        if (*s == '\0')
            break;
        f[n++] = s;
        while (*s != '\0' && *s != ' ')
            s++;
        if (*s != '\0')
            *s++ = '\0';
    }
    return n;
}

int txn_load(const struct conf *cf, struct txn *t)
{
    FILE *fp;
    char line[4096];
    char *f[TXN_FIELDS + 2];
    struct txnpkg *p;
    unsigned len;
    int nf;
    int lineno;

    memset((char *)t, 0, sizeof(*t));
    fp = fopen(cf->txnfile, "r");
    if (fp == NULL)
        return -1;
    lineno = 0;
    while (fgets(line, (int)sizeof(line), fp) != NULL) {
        lineno++;
        len = (unsigned)strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (lineno == 1) {
            if (strcmp(line, TXN_MAGIC) != 0)
                goto bad;
            continue;
        }
        nf = split_blank(line, f, TXN_FIELDS + 2);
        if (nf == 0)
            continue;
        if (strcmp(f[0], "verb") == 0 && nf == 2) {
            strncpy(t->verb, f[1], sizeof(t->verb) - 1);
        } else if (strcmp(f[0], "state") == 0 && nf == 2) {
            strncpy(t->state, f[1], sizeof(t->state) - 1);
        } else if (strcmp(f[0], "started") == 0 && nf == 2) {
            t->started = atol(f[1]);
        } else if (strcmp(f[0], "kspace") == 0 && nf == 2) {
            t->kspace = atoi(f[1]);
        } else if (strcmp(f[0], "pkg") == 0 && nf == TXN_FIELDS + 1) {
            t->p = (struct txnpkg *)xrealloc((char *)t->p,
                (unsigned)((t->n + 1) * sizeof(struct txnpkg)));
            p = &t->p[t->n++];
            p->done = atoi(f[1]);
            p->ow = atoi(f[2]);
            p->kspace = atoi(f[3]);
            p->size = atol(f[4]);
            p->name = xstrdup(f[5]);
            p->version = xstrdup(f[6]);
            p->pkginst = xstrdup(f[7]);
            p->hash = xstrdup(f[8]);
            p->staged = xstrdup(f[9]);
            p->role = xstrdup(f[10]);
            p->kline = xstrdup(f[11]);
            p->kabi = xstrdup(f[12]);
            p->pin = xstrdup(f[13]);
            p->sha256 = xstrdup(f[14]);
            p->source = xstrdup(f[15]);
        } else {
            goto bad;
        }
    }
    fclose(fp);
    if (t->verb[0] == '\0' || t->state[0] == '\0')
        goto bad2;
    return 0;
bad:
    fclose(fp);
bad2:
    warnx2("%s is not a journal this apkg can read", cf->txnfile);
    txn_free(t);
    return -2;
}
