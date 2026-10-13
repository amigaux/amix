/*
 * install.c - installed-state reading, dependency resolution, and the
 * install / upgrade / remove verbs.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Installed state (docs/stock-pkg-system.md section 2): a package
 * instance <pkginst> is installed iff <target>/var/sadm/pkg/<pkginst>/
 * pkginfo exists (cf->sadmpkg already carries the APKG_ROOT + -R target
 * prefix); its VERSION= line (absent on stock Amix packages until the
 * migration script has run) gives the installed version, displayed as
 * "(none)" when missing.
 *
 * Fetching + staging is delegated to the SOURCE layer (source.c): HTTP,
 * a mounted FILE tree (/cdrom), or a RAW slice.  cmd_install stages and
 * md5-verifies EVERY package before the first pkgadd, so a bad source
 * cannot leave a half-installed chain.
 *
 * NOTHING IS EVER REMOVED BEFORE ITS REPLACEMENT IS IN PLACE.  The
 * upgrade verb is a single pkgadd over the installed instance
 * (instance=overwrite), not pkgrm-then-pkgadd; see cmd_upgrade for the
 * metal failure that retired the old sequence.  The admin(4) file every
 * engine call needs is materialised by conf_adminfile() at the call
 * site rather than assumed to exist -- the APKG package owns it, so a
 * pkgrm can delete it out from under a later pkgadd.
 *
 * pkgadd/pkgrm are driven with fork/execv rather than system(): no shell
 * quoting surface for paths, exact argv logging, and the child's exit
 * status comes back unmangled.  When cf->target is set the argv grows an
 * explicit "-R <target>" (byte-identical to the plain form otherwise).
 *
 * The child's stdin is redirected to /dev/null (METAL-FIX.3): a batch /
 * installer run feeds the engine no stdin, yet the stock 1991 pkgadd will
 * PROMPT (conflict / "Do you want to continue") even under -n on some
 * error paths.  With an inherited, never-fed stdin such a prompt blocks
 * forever, wedging the waitpid() below so apkg never returns and the
 * failure is never propagated - observed on metal (M-RUN1, 2026-07-23): a
 * pkgadd "unable to open mount table" error left the console hung at "No
 * changes were made to the system." and the driver's fail-closed `die`
 * (which keys on apkg's rc) never fired.  /dev/null gives any such prompt
 * an immediate EOF, so pkgadd ABORTS non-zero and run_cmd reports it like
 * any other failure.  stdout/stderr are left attached so pkgadd's
 * diagnostics still reach the console/log.  This covers the shared install
 * loop (all of HTTP/FILE/RAW), upgrade, and remove alike.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "apkg.h"
#include "source.h"

/* ---------------- installed state ---------------- */

int installed_version(const struct conf *cf, const char *pkginst,
                      char *ver, unsigned verlen)
{
    char *path;
    FILE *fp;
    char line[512];
    char *val;
    unsigned len;

    ver[0] = '\0';
    path = cat3(cf->sadmpkg, "/", pkginst);
    {
        char *p2;

        p2 = cat2(path, "/pkginfo");
        free(path);
        path = p2;
    }
    fp = fopen(path, "r");
    free(path);
    if (fp == NULL)
        return 0;
    while (fgets(line, (int)sizeof(line), fp) != NULL) {
        if (strncmp(line, "VERSION=", 8) != 0)
            continue;
        val = line + 8;
        len = (unsigned)strlen(val);
        while (len > 0 && (val[len - 1] == '\n' || val[len - 1] == '\r'))
            val[--len] = '\0';
        /* strip one level of surrounding quotes */
        if (len >= 2 && (val[0] == '"' || val[0] == '\'') &&
            val[len - 1] == val[0]) {
            val[len - 1] = '\0';
            val++;
            len -= 2;
        }
        if (len >= verlen)
            len = verlen - 1;
        memcpy(ver, val, len);
        ver[len] = '\0';
        break;
    }
    fclose(fp);
    return 1;
}

/* version string for display: "(none)" for VERSION-less packages */
static const char *disp_ver(const char *v)
{
    return v[0] == '\0' ? "(none)" : v;
}

/* ---------------- running pkgadd / pkgrm ---------------- */

static void print_argv(const char *pfx, char **argv)
{
    int i;

    fprintf(stderr, "apkg: %s", pfx);
    for (i = 0; argv[i] != NULL; i++)
        fprintf(stderr, " %s", argv[i]);
    fprintf(stderr, "\n");
}

/* fork/execv; returns child exit status (0..255), or -1 on
 * fork/exec/wait failure.  The child's stdin is redirected to /dev/null
 * so a pkgadd that would prompt gets EOF and aborts rather than blocking
 * this waitpid() forever (see the file header / METAL-FIX.3). */
static int run_cmd(char **argv)
{
    int pid;
    int st;

    pid = fork();
    if (pid < 0) {
        warnx2("fork failed");
        return -1;
    }
    if (pid == 0) {
        int nullfd;

        /* EOF-on-read stdin: a never-fed prompt must abort, not hang */
        nullfd = open("/dev/null", O_RDONLY);
        if (nullfd >= 0) {
            (void)dup2(nullfd, 0);
            if (nullfd > 0)
                (void)close(nullfd);
        } else {
            (void)close(0);   /* fallback: read() then fails, still aborts */
        }
        execv(argv[0], argv);
        fprintf(stderr, "apkg: cannot exec %s\n", argv[0]);
        _exit(127);
    }
    if (waitpid(pid, &st, 0) < 0) {
        warnx2("waitpid failed");
        return -1;
    }
    if (!WIFEXITED(st)) {
        warnx2("%s terminated abnormally", argv[0]);
        return -1;
    }
    return WEXITSTATUS(st);
}

/* {pkgadd, ["-R" target,] "-n", "-a", admin, "-d", file, pkginst, NULL}
 *
 * The admin file is obtained from conf_adminfile(), which CREATES it if
 * it is not there -- never read cf->admin straight into the argv.  See
 * conf.c: the APKG package owns /var/apkg/admin, so a pkgrm can (and on
 * metal did) delete the very file the next pkgadd needs.
 *
 * overwrite != 0 asks for the instance=overwrite flavour, i.e. "replace
 * the installed instance of this package".  That is the upgrade verb's
 * whole mechanism, and it is also what makes -f meaningful when the
 * installed version differs from the catalog's. */
static int run_pkgadd(const struct conf *cf, const char *pkgadd,
                      const char *file, const char *pkginst, int overwrite)
{
    char *argv[11];
    char *admin;
    int a;
    int rc;

    admin = conf_adminfile(cf, overwrite);
    if (admin == NULL)
        return -1;
    a = 0;
    argv[a++] = (char *)pkgadd;
    if (cf->target[0] != '\0') {
        argv[a++] = (char *)"-R";
        argv[a++] = cf->target;
    }
    argv[a++] = (char *)"-n";
    argv[a++] = (char *)"-a";
    argv[a++] = admin;
    argv[a++] = (char *)"-d";
    argv[a++] = (char *)file;
    argv[a++] = (char *)pkginst;
    argv[a] = NULL;
    if (opt_dryrun) {
        print_argv("would run:", argv);
        free(admin);
        return 0;
    }
    if (opt_verbose)
        print_argv("running:", argv);
    rc = run_cmd(argv);
    free(admin);
    return rc;
}

/* {pkgrm, ["-R" target,] "-n", "-a", admin, pkginst, NULL} */
static int run_pkgrm(const struct conf *cf, const char *pkgrm,
                     const char *pkginst)
{
    char *argv[9];
    char *admin;
    int a;
    int rc;

    admin = conf_adminfile(cf, 0);
    if (admin == NULL)
        return -1;
    a = 0;
    argv[a++] = (char *)pkgrm;
    if (cf->target[0] != '\0') {
        argv[a++] = (char *)"-R";
        argv[a++] = cf->target;
    }
    argv[a++] = (char *)"-n";
    argv[a++] = (char *)"-a";
    argv[a++] = admin;
    argv[a++] = (char *)pkginst;
    argv[a] = NULL;
    if (opt_dryrun) {
        print_argv("would run:", argv);
        free(admin);
        return 0;
    }
    if (opt_verbose)
        print_argv("running:", argv);
    rc = run_cmd(argv);
    free(admin);
    return rc;
}

/* ---------------- dependency resolution ---------------- */

/* marks: 0 = unvisited, 1 = on the current DFS path, 2 = emitted */
#define M_WHITE 0
#define M_GREY  1
#define M_BLACK 2

static int resolve_visit(struct catalog *cat, struct pkgent *ent,
                         struct pkgent ***order, int *no)
{
    struct pkgent *dep;
    int i;
    int rc;

    if (ent->mark == M_BLACK)
        return 0;
    if (ent->mark == M_GREY) {
        warnx2("dependency cycle involving %s", ent->name);
        return -1;
    }
    ent->mark = M_GREY;
    for (i = 0; i < ent->ndeps; i++) {
        dep = catalog_find(cat, ent->deps[i]);
        if (dep == NULL) {
            warnx2("missing dependency: %s (needed by %s)",
                   ent->deps[i], ent->name);
            return -1;
        }
        rc = resolve_visit(cat, dep, order, no);
        if (rc != 0)
            return rc;
    }
    ent->mark = M_BLACK;
    *order = (struct pkgent **)xrealloc((char *)*order,
        (unsigned)((*no + 1) * sizeof(struct pkgent *)));
    (*order)[*no] = ent;
    (*no)++;
    return 0;
}

/* Was this catalog entry asked for by name on the command line, or did
 * it only arrive as somebody's dependency?  -f applies to the former. */
static int is_named(char **names, int nnames, const struct pkgent *ent)
{
    int i;

    for (i = 0; i < nnames; i++)
        if (strcmp(names[i], ent->name) == 0)
            return 1;
    return 0;
}

/* ---------------- verbs ---------------- */

int cmd_download(const struct conf *cf, struct catalog *cat,
                 const char *name)
{
    struct source src;
    struct pkgent *ent;
    char *staged;
    int eph;
    int rc;

    ent = catalog_find(cat, name);
    if (ent == NULL) {
        warnx2("package %s not in catalog", name);
        return EX_USAGE;
    }
    if (src_open(cf->repo, &src) != 0)
        return EX_USAGE;
    http_opts_from_conf(&src.http, cf);
    rc = src_stage(&src, ent, cf->cachedir, &staged, &eph);
    src_close(&src);
    if (rc != EX_OK)
        return rc;
    if (!opt_dryrun) {
        note("staged %s%s", staged, eph ? "" : " (in place)");
        printf("%s\n", staged);
    }
    free(staged);
    return EX_OK;
}

int cmd_install(const struct conf *cf, struct catalog *cat,
                char **names, int nnames)
{
    struct source src;
    struct pkgent **order;
    struct pkgent **todo;
    int *ow;               /* parallel to todo[]: pass instance=overwrite */
    char **files;
    struct pkgent *ent;
    char *pkgadd;
    char *staged;
    char iver[128];
    int eph;
    int no, nt;
    int i;
    int cmp;
    int named;
    int rc;

    /* resolve the dependency closure, deps first */
    for (i = 0; i < cat->n; i++)
        cat->ents[i].mark = M_WHITE;
    order = NULL;
    no = 0;
    for (i = 0; i < nnames; i++) {
        ent = catalog_find(cat, names[i]);
        if (ent == NULL) {
            warnx2("package %s not in catalog", names[i]);
            if (order != NULL)
                free((char *)order);
            return EX_DEPS;
        }
        if (resolve_visit(cat, ent, &order, &no) != 0) {
            if (order != NULL)
                free((char *)order);
            return EX_DEPS;
        }
    }

    /* Decide what actually gets pkgadd'ed.  Three rules, all learned
     * the hard way on the metal (A4000D/68LC060, 2026-09-16):
     *
     *  - -f APPLIES TO THE NAMED PACKAGES ONLY.  It used to force a
     *    re-pkgadd of the whole dependency closure, so `apkg -f install
     *    apkg` re-installed the 2.3 MB APKGENG engine as well and took
     *    >4 minutes on a 68LC060 before it even reached the package the
     *    operator asked for.  A dependency is still installed when it is
     *    MISSING -- that is what makes the closure a closure -- but an
     *    already-satisfied one is left alone.
     *
     *  - AN INSTALLED PACKAGE WITH A NEWER CATALOG VERSION IS NOT A
     *    "skip".  Reporting "already installed" there is a lie of
     *    omission, and letting it fall through to pkgadd is worse: the
     *    default admin file says instance=quit, so pkgadd stops with
     *    "Unable to determine whether to overwrite an existing package
     *    instance".  Named -> refuse and point at the upgrade verb.
     *    Dependency -> say so and carry on; upgrading a dep behind the
     *    operator's back is not this verb's job.
     *
     *  - An installed version NEWER than the catalog's is reported, not
     *    silently reinstalled.
     */
    todo = (struct pkgent **)xmalloc(
        (unsigned)((no > 0 ? no : 1) * sizeof(struct pkgent *)));
    ow = (int *)xmalloc((unsigned)((no > 0 ? no : 1) * sizeof(int)));
    nt = 0;
    for (i = 0; i < no; i++) {
        ent = order[i];
        named = is_named(names, nnames, ent);
        if (!installed_version(cf, ent->pkginst, iver, sizeof(iver))) {
            todo[nt] = ent;
            ow[nt] = 0;
            nt++;
            continue;
        }
        cmp = apkg_vercmp(ent->version, iver);
        if (named && opt_force) {
            /* deliberate reinstall/replacement of what was asked for */
            todo[nt] = ent;
            ow[nt] = (cmp != 0);
            nt++;
            continue;
        }
        if (cmp == 0) {
            printf("%s-%s already installed, skipping (use -f to reinstall)\n",
                   ent->name, ent->version);
        } else if (cmp > 0) {
            if (named) {
                warnx2("%s %s is installed and the catalog has %s",
                       ent->name, disp_ver(iver), ent->version);
                warnx2("use 'apkg upgrade %s' to update it, "
                       "or -f to force a reinstall", ent->name);
                free((char *)order);
                free((char *)todo);
                free((char *)ow);
                return EX_USAGE;
            }
            printf("%s %s installed, catalog has %s "
                   "(dependency satisfied; 'apkg upgrade %s' to update it)\n",
                   ent->name, disp_ver(iver), ent->version, ent->name);
        } else {
            printf("%s %s installed is newer than the catalog's %s, "
                   "skipping\n", ent->name, disp_ver(iver), ent->version);
        }
    }
    if (order != NULL)
        free((char *)order);
    if (nt == 0) {
        printf("nothing to do\n");
        free((char *)todo);
        free((char *)ow);
        return EX_OK;
    }

    pkgadd = conf_pkgcmd(cf, 0);
    if (pkgadd == NULL) {
        free((char *)todo);
        free((char *)ow);
        return EX_USAGE;
    }
    if (src_open(cf->repo, &src) != 0) {
        free(pkgadd);
        free((char *)todo);
        free((char *)ow);
        return EX_USAGE;
    }
    http_opts_from_conf(&src.http, cf);

    /* phase 1: stage + md5-verify EVERYTHING before touching the system,
     * so a bad source cannot leave a half-installed chain */
    files = (char **)xmalloc((unsigned)(nt * sizeof(char *)));
    for (i = 0; i < nt; i++) {
        rc = src_stage(&src, todo[i], cf->cachedir, &staged, &eph);
        if (rc != EX_OK) {
            while (--i >= 0)
                free(files[i]);
            free((char *)files);
            free((char *)todo);
            free((char *)ow);
            free(pkgadd);
            src_close(&src);
            return rc;
        }
        note("staged %s%s", staged, eph ? "" : " (in place)");
        files[i] = staged;
    }

    /* phase 2: pkgadd in dependency order; stop on first failure */
    rc = EX_OK;
    for (i = 0; i < nt; i++) {
        if (run_pkgadd(cf, pkgadd, files[i], todo[i]->pkginst,
                       ow[i]) != 0) {
            warnx2("pkgadd failed for %s, stopping", todo[i]->name);
            rc = EX_PKGCMD;
            break;
        }
        if (!opt_dryrun)
            printf("installed %s-%s\n", todo[i]->name, todo[i]->version);
    }

    for (i = 0; i < nt; i++)
        free(files[i]);
    free((char *)files);
    free((char *)todo);
    free((char *)ow);
    free(pkgadd);
    src_close(&src);
    return rc;
}

/* upgrade: ONE pkgadd, over the installed instance.  No pkgrm.
 *
 * It used to be pkgrm-then-pkgadd, and on the metal (2026-09-16,
 * real A4000D/68LC060) `apkg upgrade apkg` BRICKED apkg
 * with exactly that sequence: the pkgrm succeeded (the running apkg
 * kept executing on its old inode) and took /var/apkg/admin with it,
 * because the APKG package OWNS that file; the follow-on pkgadd then
 * died with "unable to open admin file </var/apkg/admin>", leaving the
 * box with no apkg at all and no way to fetch one.
 *
 * Two independent changes remove that class of failure:
 *
 *   1. conf_adminfile() materialises the admin file immediately before
 *      every engine call, so no engine step can ever be starved of it.
 *   2. There is no pkgrm here any more.  pkgadd with instance=overwrite
 *      replaces the installed instance in one step, which is what the
 *      SVR4 engine is for (pkginstall/getinst.c:153).  Nothing is
 *      removed before the replacement exists, so EVERY failure path --
 *      fetch, md5, staging, pkgadd itself -- leaves the currently
 *      installed package in place and working.
 *
 * That also answers the "can pkgadd replace the RUNNING apkg binary?"
 * question the way SVR4 always could: the old inode stays alive for the
 * running process while the directory entry is replaced.
 */
int cmd_upgrade(const struct conf *cf, struct catalog *cat,
                const char *name)
{
    struct source src;
    struct pkgent *ent;
    char iver[128];
    char *pkgadd;
    char *staged;
    int eph;
    int rc;

    ent = catalog_find(cat, name);
    if (ent == NULL) {
        warnx2("package %s not in catalog", name);
        return EX_DEPS;
    }
    if (!installed_version(cf, ent->pkginst, iver, sizeof(iver))) {
        warnx2("%s is not installed; use 'apkg install %s'", name, name);
        return EX_USAGE;
    }
    if (apkg_vercmp(ent->version, iver) <= 0) {
        printf("%s is up to date (installed %s, catalog %s)\n",
               name, disp_ver(iver), ent->version);
        return EX_OK;
    }
    printf("upgrading %s %s -> %s\n", name, disp_ver(iver), ent->version);

    pkgadd = conf_pkgcmd(cf, 0);
    if (pkgadd == NULL)
        return EX_USAGE;
    if (src_open(cf->repo, &src) != 0) {
        free(pkgadd);
        return EX_USAGE;
    }
    http_opts_from_conf(&src.http, cf);

    /* fetch + md5-verify BEFORE anything touches the system: a bad
     * source must cost nothing but a failed exit */
    rc = src_stage(&src, ent, cf->cachedir, &staged, &eph);
    if (rc != EX_OK) {
        warnx2("%s not fetched; the installed %s %s is untouched",
               name, name, disp_ver(iver));
        free(pkgadd);
        src_close(&src);
        return rc;
    }
    note("staged %s%s", staged, eph ? "" : " (in place)");

    rc = EX_OK;
    if (run_pkgadd(cf, pkgadd, staged, ent->pkginst, 1) != 0) {
        warnx2("pkgadd of %s %s failed; the installed %s is untouched",
               name, ent->version, disp_ver(iver));
        rc = EX_PKGCMD;
    } else if (!opt_dryrun) {
        printf("upgraded %s to %s\n", name, ent->version);
    }
    free(staged);
    free(pkgadd);
    src_close(&src);
    return rc;
}

int cmd_remove(const struct conf *cf, struct catalog *cat,
               const char *name)
{
    struct pkgent *ent;
    const char *pkginst;
    char iver[128];
    char *pkgrm;
    int rc;

    /* map catalog name -> pkginst when we have a catalog; otherwise
     * (or when the name is unknown there) treat it as a pkginst */
    pkginst = name;
    if (cat != NULL) {
        ent = catalog_find(cat, name);
        if (ent != NULL)
            pkginst = ent->pkginst;
    }
    if (!installed_version(cf, pkginst, iver, sizeof(iver))) {
        warnx2("%s (pkginst %s) is not installed", name, pkginst);
        return EX_USAGE;
    }
    pkgrm = conf_pkgcmd(cf, 1);
    if (pkgrm == NULL)
        return EX_USAGE;
    rc = EX_OK;
    if (run_pkgrm(cf, pkgrm, pkginst) != 0) {
        warnx2("pkgrm failed for %s", pkginst);
        rc = EX_PKGCMD;
    } else if (!opt_dryrun) {
        printf("removed %s\n", pkginst);
    }
    free(pkgrm);
    return rc;
}
