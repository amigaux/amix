/*
 * conffile.c - the apkg side of config files that keep the
 * administrator's edits (P-36 section 1.2; conffile(5)).
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * The class action scripts (../conffile/i.conffile, r.conffile) do the
 * safe thing inside every pkgadd and pkgrm, under any installer: an
 * edited file is kept, the new default goes to <path>.new, and the file
 * is named in /var/sadm/conffiles/PENDING as "<pkginst> <path>".  The
 * engine's stdin is /dev/null (install.c, METAL-FIX.3), so nothing can
 * be asked there.  apkg asks AFTER the transaction:
 *
 *   keep   your file stays; <path>.new is deleted (the same bytes stay
 *          in the baseline, /var/sadm/conffiles/<pkginst>/<path>)
 *   new    your file becomes <path>.old, <path>.new becomes <path>, and
 *          the contents DB is told: installf -c conffile <pkginst>
 *          <path> e, then installf -f <pkginst> (without -c the entry
 *          falls back to class none; host-tested in P-36 W1)
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
typedef void (*walkfn)(const struct conf *cf, const char *pkginst,
                       const char *rel, void *arg);

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
