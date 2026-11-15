/*
 * conffile.c - the apkg side of config files that keep the
 * administrator's edits (conffile(5)).
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * The class action scripts (../conffile/i.conffile, r.conffile) do the
 * safe thing inside every pkgadd and pkgrm, under any installer: an
 * edited file is kept, the new default goes to <path>.new, and the file
 * is named in /var/sadm/conffiles/PENDING as "<pkginst> <path>".  The
 * engine's stdin is /dev/null (install.c, the fail-fast fix), so nothing can
 * be asked there.  apkg asks AFTER the transaction:
 *
 *   keep   your file stays; <path>.new is deleted (the same bytes stay
 *          in the baseline, /var/sadm/conffiles/<pkginst>/<path>)
 *   new    your file becomes <path>.old, <path>.new becomes <path>, and
 *          the contents DB is told: installf -c conffile <pkginst>
 *          <path> e, then installf -f <pkginst> (without -c the entry
 *          falls back to class none; host-tested in src/conffile/tests)
 *   diff   diff(1) of your file against <path>.new, then ask again
 *   later  nothing; the file stays pending for `apkg conffiles resolve`
 *
 * At a terminal with no flag apkg asks file by file (keep is the default
 * answer); -y / --conf-keep keep and --conf-new take every new default
 * without asking.  With no terminal and no flag nothing is decided: the
 * files are listed and stay pending.
 *
 * Paths in PENDING and under the baseline tree are relative to the
 * install root; on disk they sit under <APKG_ROOT><-R target>.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <dirent.h>
#include <unistd.h>

#include "apkg.h"

int opt_conf = CONF_ASK;

#define DIFF_CMD "/usr/bin/diff"

typedef void (*walkfn)(const struct conf *cf, const char *pkginst,
                       const char *rel, void *arg);
static void walk(const struct conf *cf, const char *pkginst,
                 const char *dir, const char *rel, walkfn fn, void *arg);

/* one PENDING line */
struct pend {
    char *pkginst;
    char *path;
};

static char *cf_rootpfx(const struct conf *cf)
{
    return cat2(cf->root, cf->target);
}

static char *pending_path(const struct conf *cf)
{
    return cat2(cf->cfdir, "/PENDING");
}

/* read PENDING; a missing file is an empty list */
static int pend_load(const struct conf *cf, struct pend **out, int *n)
{
    char *path;
    FILE *fp;
    char line[1024];
    char *sp;
    unsigned len;
    int cap;

    *out = NULL;
    *n = 0;
    cap = 0;
    path = pending_path(cf);
    fp = fopen(path, "r");
    free(path);
    if (fp == NULL)
        return 0;
    while (fgets(line, sizeof(line), fp) != NULL) {
        len = (unsigned)strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        sp = strchr(line, ' ');
        if (sp == NULL || sp == line || sp[1] != '/')
            continue;               /* not "<pkginst> /<path>": skip */
        *sp = '\0';
        if (*n == cap) {
            cap = cap ? cap * 2 : 8;
            *out = (struct pend *)xrealloc((char *)*out,
                                           (unsigned)(cap * sizeof(**out)));
        }
        (*out)[*n].pkginst = xstrdup(line);
        (*out)[*n].path = xstrdup(sp + 1);
        (*n)++;
    }
    fclose(fp);
    return 0;
}

static void pend_free(struct pend *p, int n)
{
    int i;

    for (i = 0; i < n; i++) {
        free(p[i].pkginst);
        free(p[i].path);
    }
    if (p != NULL)
        free((char *)p);
}

/* drop one line from PENDING (rewritten through a temporary + rename) */
static int pend_drop(const struct conf *cf, const char *pkginst,
                     const char *path)
{
    struct pend *p;
    char *pp;
    char *tmp;
    FILE *fp;
    int n;
    int i;
    int rc;

    if (opt_dryrun)
        return 0;
    if (pend_load(cf, &p, &n) != 0)
        return -1;
    pp = pending_path(cf);
    tmp = cat2(pp, ".tmp");
    rc = 0;
    fp = fopen(tmp, "w");
    if (fp == NULL) {
        warnx2("cannot write %s", tmp);
        rc = -1;
    } else {
        for (i = 0; i < n; i++)
            if (strcmp(p[i].pkginst, pkginst) != 0 ||
                strcmp(p[i].path, path) != 0)
                fprintf(fp, "%s %s\n", p[i].pkginst, p[i].path);
        if (fclose(fp) != 0 || rename(tmp, pp) != 0) {
            warnx2("cannot update %s", pp);
            rc = -1;
        }
    }
    free(tmp);
    free(pp);
    pend_free(p, n);
    return rc;
}

/* 1 when the two files have the same bytes */
static int same_file(const char *a, const char *b)
{
    FILE *fa;
    FILE *fb;
    int ca;
    int cb;

    fa = fopen(a, "r");
    if (fa == NULL)
        return 0;
    fb = fopen(b, "r");
    if (fb == NULL) {
        fclose(fa);
        return 0;
    }
    do {
        ca = getc(fa);
        cb = getc(fb);
    } while (ca == cb && ca != EOF);
    fclose(fa);
    fclose(fb);
    return ca == cb;
}

/* fork/exec with the terminal left attached; the child's exit status */
static int run_tty(char **argv)
{
    int pid;
    int st;

    fflush(stdout);
    pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        execv(argv[0], argv);
        fprintf(stderr, "apkg: cannot exec %s\n", argv[0]);
        _exit(127);
    }
    if (waitpid(pid, &st, 0) < 0 || !WIFEXITED(st))
        return -1;
    return WEXITSTATUS(st);
}

/* installf [-R target] -c conffile <pkginst> <path> e, then installf -f */
static int reregister(const struct conf *cf, const char *pkginst,
                      const char *path)
{
    char *pkgadd;
    char *dir;
    char *installf;
    char *argv[12];
    int a;
    int rc;

    pkgadd = conf_pkgcmd(cf, 0);
    if (pkgadd == NULL)
        return -1;
    dir = dirname_of(pkgadd);
    installf = cat2(dir, "/installf");
    free(dir);
    free(pkgadd);
    rc = 0;
    a = 0;
    argv[a++] = installf;
    if (cf->target[0] != '\0') {
        argv[a++] = (char *)"-R";
        argv[a++] = cf->target;
    }
    argv[a++] = (char *)"-c";
    argv[a++] = (char *)"conffile";
    argv[a++] = (char *)pkginst;
    argv[a++] = (char *)path;
    argv[a++] = (char *)"e";
    argv[a] = NULL;
    if (opt_verbose)
        note("running: %s ... %s %s e", installf, pkginst, path);
    if (run_tty(argv) != 0) {
        warnx2("%s failed for %s %s", installf, pkginst, path);
        rc = -1;
    } else {
        a = 0;
        argv[a++] = installf;
        if (cf->target[0] != '\0') {
            argv[a++] = (char *)"-R";
            argv[a++] = cf->target;
        }
        argv[a++] = (char *)"-f";
        argv[a++] = (char *)pkginst;
        argv[a] = NULL;
        if (run_tty(argv) != 0) {
            warnx2("%s -f failed for %s", installf, pkginst);
            rc = -1;
        }
    }
    free(installf);
    return rc;
}

/* act on one pending file: CONF_KEEP or CONF_NEW */
static int apply(const struct conf *cf, const struct pend *p, int how)
{
    char *pfx;
    char *disk;
    char *newf;
    char *oldf;
    int rc;

    pfx = cf_rootpfx(cf);
    disk = cat2(pfx, p->path);
    newf = cat2(disk, ".new");
    oldf = cat2(disk, ".old");
    free(pfx);
    rc = 0;
    if (!file_exists(newf)) {
        warnx2("%s: no %s.new any more; no longer pending", p->path,
               p->path);
        rc = pend_drop(cf, p->pkginst, p->path);
    } else if (how == CONF_KEEP) {
        if (opt_dryrun) {
            printf("would keep %s and remove %s.new\n", p->path, p->path);
        } else {
            (void)unlink(newf);
            rc = pend_drop(cf, p->pkginst, p->path);
            printf("%s: kept yours; removed %s.new\n", p->path, p->path);
        }
    } else if (opt_dryrun) {
        printf("would install %s.new as %s, keeping yours as %s.old\n",
               p->path, p->path, p->path);
    } else {
        if (file_exists(disk) && rename(disk, oldf) != 0) {
            warnx2("cannot rename %s to %s", disk, oldf);
            rc = -1;
        } else if (rename(newf, disk) != 0) {
            warnx2("cannot rename %s to %s", newf, disk);
            rc = -1;
        } else {
            printf("%s: installed the new default; yours is %s.old\n",
                   p->path, p->path);
            if (pend_drop(cf, p->pkginst, p->path) != 0)
                rc = -1;
            if (reregister(cf, p->pkginst, p->path) != 0)
                rc = -1;
        }
    }
    free(oldf);
    free(newf);
    free(disk);
    return rc;
}

/* the per-file question; returns CONF_KEEP, CONF_NEW or 0 (later) */
static int ask(const struct conf *cf, const struct pend *p)
{
    char line[64];
    char *pfx;
    char *disk;
    char *newf;
    char *argv[4];

    for (;;) {
        printf("%s (%s): your version is kept for now.\n"
               "  [k]eep yours, install the [n]ew default, show the "
               "[d]iff, or decide [l]ater? [k] ", p->path, p->pkginst);
        fflush(stdout);
        if (fgets(line, sizeof(line), stdin) == NULL) {
            printf("\n");
            return 0;               /* EOF: decide later */
        }
        switch (line[0]) {
        case '\n':
        case 'k':
        case 'K':
            return CONF_KEEP;
        case 'n':
        case 'N':
            return CONF_NEW;
        case 'l':
        case 'L':
            return 0;
        case 'd':
        case 'D':
            pfx = cf_rootpfx(cf);
            disk = cat2(pfx, p->path);
            newf = cat2(disk, ".new");
            free(pfx);
            argv[0] = (char *)DIFF_CMD;
            argv[1] = disk;
            argv[2] = newf;
            argv[3] = NULL;
            printf("--- %s (yours)\n+++ %s.new (the new default)\n",
                   p->path, p->path);
            (void)run_tty(argv);
            free(newf);
            free(disk);
            break;
        default:
            printf("please answer k, n, d or l\n");
            break;
        }
    }
}

/* 1 when p belongs to one of the n pkginsts (n < 0: to every one) */
static int wanted(const struct pend *p, char **insts, int n)
{
    int i;

    if (n < 0)
        return 1;
    for (i = 0; i < n; i++)
        if (strcmp(insts[i], p->pkginst) == 0)
            return 1;
    return 0;
}

/* the baselines of one package, for pend_stale() */
struct blist {
    char **rel;
    char cls[64][32];
    int n;
};

static void blist_add(const struct conf *cf, const char *pkginst,
                      const char *rel, void *arg)
{
    struct blist *b;

    (void)cf;
    (void)pkginst;
    b = (struct blist *)arg;
    if (b->n == 64)
        return;
    b->rel[b->n] = xstrdup(rel);
    b->cls[b->n][0] = '\0';
    b->n++;
}

/* one pass over the contents database: the class each b->rel[] has under
 * pkginst now ("" when no line lists pkginst for it) */
static void blist_classes(const struct conf *cf, const char *pkginst,
                          struct blist *b);

/* drop one baseline and the directories it leaves empty */
static void drop_baseline(const struct conf *cf, const char *pkginst,
                          const char *rel)
{
    char *top;
    char *base;
    char *dir;
    char *up;

    top = cat3(cf->cfdir, "/", pkginst);
    base = cat2(top, rel);
    if (unlink(base) == 0) {
        dir = dirname_of(base);
        while (strcmp(dir, top) != 0 && rmdir(dir) == 0) {
            up = dirname_of(dir);
            free(dir);
            dir = up;
        }
        free(dir);
        (void)rmdir(top);
    }
    free(base);
    free(top);
}

/* After a transaction: a config file of one of its packages that the
 * package no longer ships as one (a version without the class, a
 * downgrade) loses its baseline, its PENDING line and the .new beside
 * it, so the report and `apkg conffiles` name only real config files. */
static void pend_stale(const struct conf *cf, char **insts, int n)
{
    struct blist b;
    char *dir;
    char *pfx;
    char *x;
    int i;
    int k;

    if (opt_dryrun)
        return;
    pfx = cf_rootpfx(cf);
    b.rel = (char **)xmalloc((unsigned)(64 * sizeof(char *)));
    for (i = 0; i < n; i++) {
        if (!conffile_state(cf, insts[i]))
            continue;
        b.n = 0;
        dir = cat3(cf->cfdir, "/", insts[i]);
        walk(cf, insts[i], dir, "", blist_add, (void *)&b);
        free(dir);
        blist_classes(cf, insts[i], &b);
        for (k = 0; k < b.n; k++) {
            if (strcmp(b.cls[k], "conffile") != 0) {
                (void)pend_drop(cf, insts[i], b.rel[k]);
                x = cat3(pfx, b.rel[k], ".new");
                (void)unlink(x);
                free(x);
                drop_baseline(cf, insts[i], b.rel[k]);
                note("%s is no longer a config file of %s", b.rel[k],
                     insts[i]);
            }
            free(b.rel[k]);
        }
    }
    free((char *)b.rel);
    free(pfx);
}

/* decide the pending files of insts[] (n < 0: all): ask at a terminal,
 * or apply opt_conf; with neither, leave them pending */
static int decide(const struct conf *cf, char **insts, int n, int interactive)
{
    struct pend *p;
    int np;
    int i;
    int how;
    int rc;

    if (pend_load(cf, &p, &np) != 0)
        return EX_USAGE;
    rc = EX_OK;
    for (i = 0; i < np; i++) {
        if (!wanted(&p[i], insts, n))
            continue;
        how = opt_conf;
        if (how == CONF_ASK)
            how = interactive ? ask(cf, &p[i]) : 0;
        if (how != 0 && apply(cf, &p[i], how) != 0)
            rc = EX_PKGCMD;
    }
    pend_free(p, np);
    return rc;
}

/* after install/upgrade: list the pending files of this transaction's
 * packages, then decide them (or leave them) */
int conffile_after(const struct conf *cf, char **insts, int n)
{
    struct pend *p;
    int np;
    int mine;
    int other;
    int i;
    int interactive;
    int rc;

    pend_stale(cf, insts, n);
    if (pend_load(cf, &p, &np) != 0 || np == 0) {
        pend_free(p, np);
        return EX_OK;
    }
    mine = 0;
    other = 0;
    for (i = 0; i < np; i++) {
        if (wanted(&p[i], insts, n))
            mine++;
        else
            other++;
    }
    if (mine > 0) {
        printf("config files kept with a new default beside them:\n");
        for (i = 0; i < np; i++)
            if (wanted(&p[i], insts, n))
                printf("  %s (%s): the new default is %s.new\n",
                       p[i].path, p[i].pkginst, p[i].path);
    }
    pend_free(p, np);
    rc = EX_OK;
    interactive = isatty(0);
    if (mine > 0) {
        if (opt_conf == CONF_ASK && !interactive)
            printf("decide with: apkg conffiles resolve "
                   "(or --conf-keep / --conf-new)\n");
        else
            rc = decide(cf, insts, n, interactive);
    }
    if (other > 0)
        printf("%d more config file%s pending from earlier: "
               "apkg conffiles\n", other, other == 1 ? "" : "s");
    return rc;
}

/* ---------------- the baseline tree ---------------- */

/* call fn(cf, pkginst, rel) for each baseline file under dir; rel is
 * the path below <cfdir>/<pkginst> */

static void walk(const struct conf *cf, const char *pkginst,
                 const char *dir, const char *rel, walkfn fn, void *arg)
{
    DIR *d;
    struct dirent *de;
    struct stat st;
    char *sub;
    char *subrel;

    d = opendir(dir);
    if (d == NULL)
        return;
    while ((de = readdir(d)) != NULL) {
        if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
            continue;
        sub = cat3(dir, "/", de->d_name);
        subrel = cat3(rel, "/", de->d_name);
        if (stat(sub, &st) == 0) {
            if (S_ISDIR(st.st_mode))
                walk(cf, pkginst, sub, subrel, fn, arg);
            else if (S_ISREG(st.st_mode))
                fn(cf, pkginst, subrel, arg);
        }
        free(subrel);
        free(sub);
    }
    closedir(d);
}

/* 1 when <pkginst> has baselines: installed, or removed with its edited
 * config files kept (the "config-files" state) */
int conffile_state(const struct conf *cf, const char *pkginst)
{
    char *dir;
    DIR *d;
    struct dirent *de;
    int any;

    dir = cat3(cf->cfdir, "/", pkginst);
    d = opendir(dir);
    free(dir);
    if (d == NULL)
        return 0;
    any = 0;
    while (!any && (de = readdir(d)) != NULL)
        if (strcmp(de->d_name, ".") != 0 && strcmp(de->d_name, "..") != 0)
            any = 1;
    closedir(d);
    return any;
}

struct listarg {
    struct pend *p;
    int np;
    int shown;
};

static void list_one(const struct conf *cf, const char *pkginst,
                     const char *rel, void *arg)
{
    struct listarg *la;
    char *pfx;
    char *disk;
    char *base;
    char iver[128];
    const char *state;
    int i;

    la = (struct listarg *)arg;
    pfx = cf_rootpfx(cf);
    disk = cat2(pfx, rel);
    free(pfx);
    base = cat3(cf->cfdir, "/", pkginst);
    pfx = base;
    base = cat2(pfx, rel);
    free(pfx);

    state = NULL;
    for (i = 0; i < la->np; i++)
        if (strcmp(la->p[i].pkginst, pkginst) == 0 &&
            strcmp(la->p[i].path, rel) == 0)
            state = "pending: the new default is beside it as .new";
    if (state == NULL && file_exists(disk) && !same_file(disk, base))
        state = "edited";
    if (state != NULL) {
        printf("%-10s %-30s %s%s\n", pkginst, rel, state,
               installed_version(cf, pkginst, iver, sizeof(iver)) ? ""
               : " (package removed)");
        la->shown++;
    }
    free(base);
    free(disk);
}

static int list_files(const struct conf *cf, const char *only)
{
    struct listarg la;
    DIR *d;
    struct dirent *de;
    char *dir;

    if (pend_load(cf, &la.p, &la.np) != 0)
        return EX_USAGE;
    la.shown = 0;
    d = opendir(cf->cfdir);
    if (d != NULL) {
        while ((de = readdir(d)) != NULL) {
            if (de->d_name[0] == '.' || strcmp(de->d_name, "PENDING") == 0)
                continue;
            if (only != NULL && strcmp(only, de->d_name) != 0)
                continue;
            dir = cat3(cf->cfdir, "/", de->d_name);
            walk(cf, de->d_name, dir, "", list_one, (void *)&la);
            free(dir);
        }
        closedir(d);
    }
    if (la.shown == 0)
        printf("no pending or edited config files%s%s\n",
               only != NULL ? " for " : "", only != NULL ? only : "");
    pend_free(la.p, la.np);
    return EX_OK;
}

/* `apkg conffiles [list] [pkginst]` and `apkg conffiles resolve
 * [pkginst]`; pkginst already mapped from a catalog name by main.c */
int cmd_conffiles(const struct conf *cf, int resolve, const char *pkginst)
{
    char *one[1];

    if (!resolve)
        return list_files(cf, pkginst);
    if (opt_conf == CONF_ASK && !isatty(0)) {
        warnx2("conffiles resolve asks at a terminal; without one, give "
               "--conf-keep or --conf-new");
        return EX_USAGE;
    }
    if (pkginst == NULL)
        return decide(cf, NULL, -1, 1);
    one[0] = (char *)pkginst;
    return decide(cf, one, 1, 1);
}

/* ---------------- purge ---------------- */

static void purge_one(const struct conf *cf, const char *pkginst,
                      const char *rel, void *arg)
{
    char *pfx;
    char *disk;
    char *extra;
    int *rc;

    rc = (int *)arg;
    pfx = cf_rootpfx(cf);
    disk = cat2(pfx, rel);
    free(pfx);
    if (opt_dryrun) {
        printf("would remove %s (%s), its .new and .old\n", rel, pkginst);
    } else {
        if (file_exists(disk)) {
            if (unlink(disk) != 0) {
                warnx2("cannot remove %s", disk);
                *rc = EX_USAGE;
            } else {
                printf("removed %s\n", rel);
            }
        }
        extra = cat2(disk, ".new");
        (void)unlink(extra);
        free(extra);
        extra = cat2(disk, ".old");
        (void)unlink(extra);
        free(extra);
    }
    free(disk);
}

/* rm -r of a baseline directory */
static int rm_tree(const char *dir)
{
    DIR *d;
    struct dirent *de;
    struct stat st;
    char *sub;
    int rc;

    rc = 0;
    d = opendir(dir);
    if (d != NULL) {
        while ((de = readdir(d)) != NULL) {
            if (strcmp(de->d_name, ".") == 0 ||
                strcmp(de->d_name, "..") == 0)
                continue;
            sub = cat3(dir, "/", de->d_name);
            if (stat(sub, &st) == 0 && S_ISDIR(st.st_mode))
                rc |= rm_tree(sub);
            else if (unlink(sub) != 0)
                rc = -1;
            free(sub);
        }
        closedir(d);
    }
    if (rmdir(dir) != 0)
        rc = -1;
    return rc;
}

/* after pkgrm (or for a package already removed): delete its kept
 * config files, their .new and .old, its PENDING lines and baselines */
int conffile_purge(const struct conf *cf, const char *pkginst)
{
    struct pend *p;
    char *dir;
    int np;
    int i;
    int rc;

    rc = EX_OK;
    dir = cat3(cf->cfdir, "/", pkginst);
    walk(cf, pkginst, dir, "", purge_one, (void *)&rc);
    if (pend_load(cf, &p, &np) == 0) {
        for (i = 0; i < np; i++)
            if (strcmp(p[i].pkginst, pkginst) == 0)
                (void)pend_drop(cf, p[i].pkginst, p[i].path);
        pend_free(p, np);
    }
    if (!opt_dryrun && file_exists(dir) && rm_tree(dir) != 0) {
        warnx2("cannot remove %s", dir);
        rc = EX_USAGE;
    }
    free(dir);
    return rc;
}

/* ---------------- after pkgrm ---------------- */

static void prune_one(const struct conf *cf, const char *pkginst,
                      const char *rel, void *arg)
{
    char *pfx;
    char *disk;
    char *base;
    char *dir;
    char *top;
    char *up;

    (void)arg;
    pfx = cf_rootpfx(cf);
    disk = cat2(pfx, rel);
    free(pfx);
    if (!file_exists(disk)) {
        top = cat3(cf->cfdir, "/", pkginst);
        base = cat2(top, rel);
        if (unlink(base) == 0) {
            note("dropped the baseline of %s: the file is gone", rel);
            dir = dirname_of(base);
            while (strcmp(dir, top) != 0 && rmdir(dir) == 0) {
                up = dirname_of(dir);
                free(dir);
                dir = up;
            }
            free(dir);
            (void)rmdir(top);
        }
        free(base);
        free(top);
    }
    free(disk);
}

/* r.conffile removes the baseline of every conffile it removes and keeps
 * the one of a file it keeps.  A baseline whose file is gone was stored
 * before an upgrade that never ran (conffile_prepare), for a file pkgrm
 * then removed as class none; it would leave the package in the
 * config-files state, so it goes. */
void conffile_prune(const struct conf *cf, const char *pkginst)
{
    char *dir;

    if (opt_dryrun)
        return;
    dir = cat3(cf->cfdir, "/", pkginst);
    walk(cf, pkginst, dir, "", prune_one, NULL);
    free(dir);
}

/* ---------------- a file that becomes a conffile ----------------
 *
 * An upgrade is one pkgadd over the installed instance (instance=
 * overwrite); no pkgrm runs first.  When the new version ships a path
 * as class conffile that the installed version shipped in another class
 * (a plain f none file), i.conffile finds no baseline for it.  It keeps
 * the file and writes <path>.new beside it, which is right for a file
 * the administrator edited, and wrong for one nobody touched: that one
 * should take the new default.  i.conffile cannot tell the two apart,
 * because the engine writes the new contents entry before the class
 * script runs, so the old size, sum and mtime are gone by then.
 *
 * So before the pkgadd apkg compares each such file with its installed
 * contents entry: size, the engine's checksum (libpkg verify.c) and
 * mtime (the engine sets it from the pkgmap).  All three equal: the
 * file is the old default, untouched, and apkg copies it to the
 * baseline <cfdir>/<pkginst>/<path>.  i.conffile then finds the file
 * equal to its baseline and installs the new default, silently.
 * Anything else is left to i.conffile, which keeps the file.  apkg
 * moves and changes no file of the administrator's, so a failed or cut
 * pkgadd leaves nothing to restore.  A path that already was a
 * conffile, one that is not a regular file, or one the contents DB
 * gives to no package of this name is not touched.  A package whose
 * pkgmap has no conffile entry costs one read of its pkgmap.
 */

#define PREP_MAX 512            /* conffile entries looked at per package */

struct prep {
    char *path;                 /* absolute, as the target root sees it */
    int found;                  /* a contents line of this pkginst */
    char type;
    char cls[32];
    long size;
    unsigned long sum;
    long mtime;
};

/* the engine's checksum: the sum of the bytes, folded twice to 16 bits
 * (heirloom libpkg/verify.c compute_checksum) */
static int engine_sum(const char *path, unsigned long *out)
{
    FILE *fp;
    unsigned char buf[4096];
    unsigned long s;
    unsigned long t;
    unsigned n;
    unsigned i;

    fp = fopen(path, "r");
    if (fp == NULL)
        return -1;
    s = 0;
    while ((n = (unsigned)fread((char *)buf, 1, sizeof(buf), fp)) > 0)
        for (i = 0; i < n; i++)
            s += buf[i];
    if (ferror(fp)) {
        fclose(fp);
        return -1;
    }
    fclose(fp);
    s &= 0xffffffffUL;
    t = (s & 0xffffUL) + (s >> 16);
    *out = (t & 0xffffUL) + (t >> 16);
    return 0;
}

/* copy src to dst through dst.tmp + rename */
static int copy_file(const char *src, const char *dst)
{
    FILE *in;
    FILE *out;
    char buf[4096];
    char *tmp;
    unsigned n;
    int rc;

    in = fopen(src, "r");
    if (in == NULL)
        return -1;
    tmp = cat2(dst, ".tmp");
    out = fopen(tmp, "w");
    if (out == NULL) {
        fclose(in);
        free(tmp);
        return -1;
    }
    rc = 0;
    while ((n = (unsigned)fread(buf, 1, sizeof(buf), in)) > 0)
        if (fwrite(buf, 1, n, out) != n) {
            rc = -1;
            break;
        }
    if (ferror(in))
        rc = -1;
    fclose(in);
    if (fclose(out) != 0)
        rc = -1;
    if (rc == 0 && rename(tmp, dst) != 0)
        rc = -1;
    if (rc != 0)
        (void)unlink(tmp);
    free(tmp);
    return rc;
}

/* split s on blanks into at most max tokens; the count */
static int split_ws(char *s, char **tok, int max)
{
    int n;

    n = 0;
    for (;;) {
        while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')
            s++;
        if (*s == '\0' || n == max)
            break;
        tok[n++] = s;
        while (*s != '\0' && *s != ' ' && *s != '\t' && *s != '\r' &&
               *s != '\n')
            s++;
        if (*s != '\0')
            *s++ = '\0';
    }
    return n;
}

/* 1 when the contents package token (status prefix, \, :class) names
 * pkginst */
static int token_is(const char *tok, const char *pkginst)
{
    unsigned n;

    while (*tok != '\0' && !(*tok >= 'A' && *tok <= 'Z') &&
           !(*tok >= 'a' && *tok <= 'z') && !(*tok >= '0' && *tok <= '9'))
        tok++;
    n = (unsigned)strlen(pkginst);
    return strncmp(tok, pkginst, n) == 0 &&
           (tok[n] == '\0' || tok[n] == '\\' || tok[n] == ':');
}

/* the pkgmap's conffile objects of type f/e/v, absolute (BASEDIR before
 * a relative path); a path with a $PARAM is skipped (not seeded) */
static int prep_collect(const char *staged, struct prep *pv, int *np)
{
    char why[256];
    char *map;
    char *info;
    char *base;
    char *line;
    char *next;
    char *tok[4];
    int nt;
    int nrel;
    int i;

    *np = 0;
    if (ds_member(staged, "pkgmap", &map, why, sizeof(why)) != 0)
        return 0;                       /* no pkgmap: nothing to seed */
    nrel = 0;
    for (line = map; line != NULL && *line != '\0'; line = next) {
        next = strchr(line, '\n');
        if (next != NULL)
            *next++ = '\0';
        nt = split_ws(line, tok, 4);
        if (nt > 0 && tok[0][0] >= '0' && tok[0][0] <= '9') {
            tok[0] = tok[1];            /* part number */
            tok[1] = tok[2];
            tok[2] = tok[3];
            nt--;
        }
        if (nt < 3 || tok[0][1] != '\0' ||
            (tok[0][0] != 'f' && tok[0][0] != 'e' && tok[0][0] != 'v') ||
            strcmp(tok[1], "conffile") != 0 || strchr(tok[2], '$') != NULL)
            continue;
        if (*np == PREP_MAX)
            break;
        memset((char *)&pv[*np], 0, sizeof(pv[*np]));
        pv[*np].path = xstrdup(tok[2]);
        if (tok[2][0] != '/')
            nrel++;
        (*np)++;
    }
    free(map);
    if (nrel == 0)
        return 0;
    base = NULL;
    if (ds_member(staged, "pkginfo", &info, why, sizeof(why)) == 0) {
        base = pkginfo_get(info, "BASEDIR");
        free(info);
    }
    for (i = 0; i < *np; i++) {
        if (pv[i].path[0] == '/')
            continue;
        next = pv[i].path;
        if (base == NULL || base[0] == '\0' || strcmp(base, "/") == 0)
            pv[i].path = cat2("/", next);
        else
            pv[i].path = cat3(base, "/", next);
        free(next);
    }
    if (base != NULL)
        free(base);
    return 0;
}

/* one pass over the contents DB: the line of each collected path, when
 * it lists pkginst */
static int prep_contents(const struct conf *cf, const char *pkginst,
                         struct prep *pv, int np)
{
    FILE *fp;
    char *line;
    char *tok[256];
    unsigned len;
    int nt;
    int t;
    int i;
    int j;

    fp = fopen(cf->contents, "r");
    if (fp == NULL)
        return -1;
    line = xmalloc(8192);
    while (fgets(line, 8192, fp) != NULL) {
        len = (unsigned)strlen(line);
        if (len > 0 && line[len - 1] != '\n' && !feof(fp)) {
            int c;

            while ((c = getc(fp)) != EOF && c != '\n')
                ;               /* overlong line: not one of ours */
            continue;
        }
        if (line[0] != '/')
            continue;
        nt = split_ws(line, tok, 256);
        for (i = 0; i < np; i++)
            if (!pv[i].found && strcmp(tok[0], pv[i].path) == 0)
                break;
        if (i == np || nt < 3)
            continue;
        t = 1;
        if (tok[1][0] >= '0' && tok[1][0] <= '9')
            t = 2;              /* volume number */
        if (t + 8 >= nt || tok[t][1] != '\0' ||
            (tok[t][0] != 'f' && tok[t][0] != 'e' && tok[t][0] != 'v'))
            continue;
        for (j = t + 8; j < nt; j++)
            if (token_is(tok[j], pkginst))
                break;
        if (j == nt)
            continue;
        pv[i].found = 1;
        pv[i].type = tok[t][0];
        strncpy(pv[i].cls, tok[t + 1], sizeof(pv[i].cls) - 1);
        pv[i].size = atol(tok[t + 5]);
        pv[i].sum = (unsigned long)atol(tok[t + 6]);
        pv[i].mtime = atol(tok[t + 7]);
    }
    free(line);
    fclose(fp);
    return 0;
}

/* seed the baseline of each untouched file that pkgadd of staged will
 * turn into a conffile of pkginst; the number seeded */
int conffile_prepare(const struct conf *cf, const char *staged,
                     const char *pkginst)
{
    struct prep *pv;
    struct stat st;
    unsigned long sum;
    char *pfx;
    char *disk;
    char *base;
    char *dir;
    int np;
    int nseed;
    int i;

    pv = (struct prep *)xmalloc((unsigned)(PREP_MAX * sizeof(*pv)));
    (void)prep_collect(staged, pv, &np);
    nseed = 0;
    if (np > 0 && prep_contents(cf, pkginst, pv, np) == 0) {
        pfx = cf_rootpfx(cf);
        for (i = 0; i < np; i++) {
            if (!pv[i].found || strcmp(pv[i].cls, "conffile") == 0)
                continue;
            disk = cat2(pfx, pv[i].path);
            if (lstat(disk, &st) != 0 || !S_ISREG(st.st_mode) ||
                (long)st.st_size != pv[i].size ||
                (long)st.st_mtime != pv[i].mtime ||
                engine_sum(disk, &sum) != 0 || sum != pv[i].sum) {
                note("%s: differs from %s's installed entry; left to "
                     "i.conffile (kept if edited)", pv[i].path, pkginst);
                free(disk);
                continue;
            }
            base = cat3(cf->cfdir, "/", pkginst);
            dir = base;
            base = cat2(dir, pv[i].path);
            free(dir);
            if (opt_dryrun) {
                note("would store %s as the baseline of untouched %s",
                     base, pv[i].path);
            } else {
                dir = dirname_of(base);
                if (mkpath(dir) != 0 || copy_file(disk, base) != 0)
                    warnx2("cannot store the baseline %s; %s will be kept "
                           "with the new default beside it", base,
                           pv[i].path);
                else {
                    note("%s: untouched; the new default will replace it",
                         pv[i].path);
                    nseed++;
                }
                free(dir);
            }
            free(base);
            free(disk);
        }
        free(pfx);
    }
    for (i = 0; i < np; i++)
        free(pv[i].path);
    free((char *)pv);
    return nseed;
}

/* `apkg conffiles prepare`: seed for the packages of the journaled
 * transaction that are not installed yet.  APKG's postinstall runs it,
 * so an older apkg that upgrades APKG and other packages in one
 * transaction has them prepared by this one.  Quiet; always 0. */
int cmd_conffiles_prepare(const struct conf *cf)
{
    struct txn t;
    int i;

    if (!txn_exists(cf) || txn_load(cf, &t) != 0)
        return EX_OK;
    if (strcmp(t.verb, "remove") != 0)
        for (i = 0; i < t.n; i++)
            if (!t.p[i].done && !t.p[i].kspace &&
                strcmp(t.p[i].staged, "-") != 0 &&
                strcmp(t.p[i].pkginst, "-") != 0 &&
                file_exists(t.p[i].staged))
                (void)conffile_prepare(cf, t.p[i].staged, t.p[i].pkginst);
    txn_free(&t);
    return EX_OK;
}

/* ---------------- a conffile that becomes a plain file ---------------- */

static void blist_classes(const struct conf *cf, const char *pkginst,
                          struct blist *b)
{
    FILE *fp;
    char *line;
    char *tok[256];
    int nt;
    int t;
    int j;
    int k;

    if (b->n == 0)
        return;
    fp = fopen(cf->contents, "r");
    if (fp == NULL)
        return;
    line = xmalloc(8192);
    while (fgets(line, 8192, fp) != NULL) {
        if (line[0] != '/')
            continue;
        nt = split_ws(line, tok, 256);
        for (k = 0; k < b->n; k++)
            if (strcmp(tok[0], b->rel[k]) == 0)
                break;
        if (k == b->n)
            continue;
        t = 1;
        if (nt > 1 && tok[1][0] >= '0' && tok[1][0] <= '9')
            t = 2;
        if (t + 1 >= nt)
            continue;
        for (j = t + 2; j < nt; j++)
            if (token_is(tok[j], pkginst))
                break;
        if (j == nt)
            continue;
        strncpy(b->cls[k], tok[t + 1], sizeof(b->cls[k]) - 1);
        b->cls[k][sizeof(b->cls[k]) - 1] = '\0';
    }
    free(line);
    fclose(fp);
}

struct unconf {
    const struct conf *cf;
    const char *map;            /* the new pkgmap's text */
    const char *base;           /* its BASEDIR, or NULL */
};

/* the class the new pkgmap gives path: cls[] ("" when it ships none) */
static void map_class(const struct unconf *u, const char *path, char *cls,
                      unsigned cap)
{
    const char *line;
    const char *next;
    char buf[1024];
    char *tok[4];
    char *full;
    int nt;

    cls[0] = '\0';
    for (line = u->map; line != NULL && *line != '\0'; line = next) {
        next = strchr(line, '\n');
        nt = next != NULL ? (int)(next - line) : (int)strlen(line);
        if (next != NULL)
            next++;
        if (nt >= (int)sizeof(buf) || strstr(line, path + 1) == NULL)
            continue;
        memcpy(buf, line, (unsigned)nt);
        buf[nt] = '\0';
        nt = split_ws(buf, tok, 4);
        if (nt > 0 && tok[0][0] >= '0' && tok[0][0] <= '9') {
            tok[0] = tok[1];
            tok[1] = tok[2];
            tok[2] = tok[3];
            nt--;
        }
        if (nt < 3 || tok[0][1] != '\0' ||
            (tok[0][0] != 'f' && tok[0][0] != 'e' && tok[0][0] != 'v'))
            continue;
        if (tok[2][0] == '/')
            full = xstrdup(tok[2]);
        else if (u->base == NULL || u->base[0] == '\0' ||
                 strcmp(u->base, "/") == 0)
            full = cat2("/", tok[2]);
        else
            full = cat3(u->base, "/", tok[2]);
        if (strcmp(full, path) == 0) {
            strncpy(cls, tok[1], cap - 1);
            cls[cap - 1] = '\0';
            free(full);
            return;
        }
        free(full);
    }
}

/* one baseline: a config file of the installed version.  When the new
 * version ships the path in another class and the file differs from its
 * baseline (edited), the new pkgadd will lay the package's default over
 * it: the file is saved as <path>.old first, and that is said */
static void unconf_one(const struct conf *cf, const char *pkginst,
                       const char *rel, void *arg)
{
    struct unconf *u;
    char cls[32];
    char *pfx;
    char *disk;
    char *old;
    char *base;
    char *dir;

    u = (struct unconf *)arg;
    map_class(u, rel, cls, sizeof(cls));
    if (cls[0] == '\0' || strcmp(cls, "conffile") == 0)
        return;                 /* still a conffile, or not shipped */
    pfx = cf_rootpfx(cf);
    disk = cat2(pfx, rel);
    free(pfx);
    dir = cat3(cf->cfdir, "/", pkginst);
    base = cat2(dir, rel);
    free(dir);
    if (file_exists(disk) && !same_file(disk, base)) {
        old = cat2(disk, ".old");
        if (opt_dryrun) {
            printf("would save your %s as %s.old: this version of %s does "
                   "not keep edits to it\n", rel, rel, pkginst);
        } else if (copy_file(disk, old) == 0) {
            printf("%s: this version of %s does not keep edits to it; "
                   "yours is saved as %s.old\n", rel, pkginst, rel);
        } else {
            warnx2("cannot save %s as %s.old", rel, rel);
        }
        free(old);
    }
    free(base);
    free(disk);
}

int conffile_unconf(const struct conf *cf, const char *staged,
                    const char *pkginst)
{
    struct unconf u;
    char why[256];
    char *map;
    char *info;
    char *dir;
    char *b;

    if (!conffile_state(cf, pkginst))
        return 0;                       /* no baseline: nothing to save */
    if (ds_member(staged, "pkgmap", &map, why, sizeof(why)) != 0)
        return 0;
    b = NULL;
    if (ds_member(staged, "pkginfo", &info, why, sizeof(why)) == 0) {
        b = pkginfo_get(info, "BASEDIR");
        free(info);
    }
    u.cf = cf;
    u.map = map;
    u.base = b;
    dir = cat3(cf->cfdir, "/", pkginst);
    walk(cf, pkginst, dir, "", unconf_one, (void *)&u);
    free(dir);
    if (b != NULL)
        free(b);
    free(map);
    return 0;
}
