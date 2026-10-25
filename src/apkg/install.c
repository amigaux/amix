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
 * verifies EVERY package (md5 + size; SHA-256 + size for kernel space)
 * before the first pkgadd, so a bad source cannot leave a half-installed
 * chain.  Kernel space, the journal and `apkg recover`: see the section
 * "kernel space and the journal" below.
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

/* ---------------- kernel space and the journal ----------------
 *
 * apkg 0.3 (amix-dlm contracts C2-2 and C2-4, spec 40 §6).  A
 * kernel-space package (an entry of the catalog's #ext kpkg block) is
 * installed by the same pkgadd as any other, with four differences:
 *
 *   - it is verified by SHA-256 + size, not md5 (source.c);
 *   - its installed state is apkg's own record /var/apkg/kpkg/<pkginst>
 *     (the entry's pkginst=, else its name; C2-2 v4),
 *     written after the pkgadd with the SHA-256 of every installed file
 *     (kspace.c); its pkginst comes from the datastream's header;
 *   - the transaction is pre-flighted (kabi, compiler pin, line) before
 *     anything is staged;
 *   - a transaction that changed kernel space ends with the kbootset
 *     trigger: `kbootset build`, then `kbootset commit`, two calls.
 *     apkg never writes a boot slice.  Atomicity for the boot path is
 *     kbootset's generation commit: a half-installed set never reaches
 *     the store.
 *
 * Every transaction (install, upgrade, remove) is journaled in
 * /var/apkg/txn once all its packages are staged and verified; the
 * journal is removed when apkg is done with it.  It stays behind only
 * when there is work `apkg recover` can finish: an interruption, a
 * failed pkgadd inside a kernel-space transaction, or a trigger that
 * could not run (EX_BOOTSET).  A gate refusal (EX_BOOTGATE) is an
 * answer, not an interruption: the journal goes, the message says what
 * to fix.  A userland-only transaction whose pkgadd FAILS clears its
 * journal too (exactly 0.2.x behaviour: re-run the install).
 */

static int ent_installed(const struct conf *cf, const struct pkgent *e,
                         char *ver, unsigned verlen)
{
    if (e->kspace)
        return kpkg_installed(cf, e->pkginst, ver, verlen);  /* C2-2 v4 */
    return installed_version(cf, e->pkginst, ver, verlen);
}

/* the record's `source` (C2-2 §2/§3): the catalog URL for HTTP, the
 * mount path or the raw device as apkg saw it for a medium */
static char *source_id(const struct source *s)
{
    if (s->kind == SRC_HTTP)
        return cat2(s->base, "/catalog");
    return xstrdup(s->base);
}

static int count_kspace(struct pkgent **todo, int nt)
{
    int i;
    int n;

    n = 0;
    for (i = 0; i < nt; i++)
        if (todo[i]->kspace)
            n++;
    return n;
}

static void announce_kspace(int nk)
{
    if (nk > 0)
        printf("kernel space: %d package%s in this transaction; a "
               "generation build (kbootset) and a power cycle follow\n",
               nk, nk == 1 ? "" : "s");
}

/* the pkginst a staged kernel-space datastream installs as, after the
 * pure-files check (40 §6); -1 when it cannot be read, contradicts the
 * catalog's pkginst= or carries anything but plain files (message
 * printed).  Runs on every staged package before the first pkgadd. */
static int kspace_inst(const struct pkgent *e, const char *staged,
                       char *out, unsigned cap)
{
    char why[256];

    if (ds_pkginst(staged, out, cap) != 0) {
        if (opt_dryrun) {
            strncpy(out, e->pkginst, cap - 1);
            out[cap - 1] = '\0';
            return 0;
        }
        warnx2("%s: %s is not a single-package datastream", e->name,
               staged);
        return -1;
    }
    if (e->kpkginst != NULL && strcmp(e->kpkginst, out) != 0) {
        warnx2("%s: the datastream installs %s, the catalog says %s",
               e->name, out, e->kpkginst);
        return -1;
    }
    if (ds_pure_files(staged, why, sizeof(why)) != 0) {
        warnx2("%s: not a pure-file kernel-space package: %s", e->name, why);
        return -1;
    }
    return 0;
}

/* Finish a journaled transaction after its package loop.  failed is the
 * loop's EX_* (EX_OK when every package is done).  Returns the
 * transaction's exit code. */
static int txn_finish(const struct conf *cf, struct txn *t, int failed)
{
    int rc;

    if (failed != EX_OK) {
        if (t->kspace && !opt_dryrun) {
            warnx2("the transaction is incomplete; the boot store is "
                   "untouched");
            warnx2("'apkg recover' retries the rest from the journal %s",
                   cf->txnfile);
        } else {
            txn_clear(cf);
        }
        return failed;
    }
    if (!t->kspace) {
        txn_clear(cf);
        return EX_OK;
    }
    if (strcmp(t->state, "built") != 0) {
        strcpy(t->state, "installed");
        if (txn_save(cf, t) != 0)
            return EX_USAGE;
    }
    rc = kspace_trigger(cf, t);
    if (rc == EX_BOOTSET)
        return rc;          /* journal kept: recover re-runs the trigger */
    txn_clear(cf);
    return rc;
}

/* pkgadd one staged package and, for kernel space, write its record */
static int install_one(const struct conf *cf, const char *pkgadd,
                       const char *file, const char *pkginst, int ow,
                       const struct txnpkg *p)
{
    int rc;

    if (run_pkgadd(cf, pkgadd, file, pkginst, ow) != 0)
        return EX_PKGCMD;
    if (!p->kspace)
        return EX_OK;
    rc = kpkg_write_record_fields(cf, p->reckey, p->name, p->version,
                                  p->role,
                                  p->kline, p->kabi, p->pin, p->loaderv,
                                  p->sha256, pkginst, p->source);
    return rc;
}

/* the shared phase 2 of install and upgrade: journal, pkgadd in order,
 * the trigger.  files[]/insts[] are the staged datastreams and the
 * pkginst each installs as. */
static int commit_txn(const struct conf *cf, const struct source *src,
                      const char *verb, struct pkgent **todo, int *ow,
                      char **files, char **insts, int nt,
                      const char *pkgadd)
{
    struct txn t;
    char *sid;
    char iver[128];
    int i;
    int rc;
    int upgrade;

    upgrade = strcmp(verb, "upgrade") == 0;
    sid = source_id(src);
    txn_init(&t, verb);
    for (i = 0; i < nt; i++)
        txn_add(&t, todo[i], insts[i], files[i], ow[i], sid);
    free(sid);
    if (txn_save(cf, &t) != 0) {
        txn_free(&t);
        return EX_USAGE;
    }

    rc = EX_OK;
    for (i = 0; i < nt; i++) {
        if (upgrade)
            (void)ent_installed(cf, todo[i], iver, sizeof(iver));
        if (install_one(cf, pkgadd, files[i], insts[i], ow[i],
                        &t.p[i]) != EX_OK) {
            if (upgrade)
                warnx2("pkgadd of %s %s failed; the installed %s is "
                       "untouched", todo[i]->name, todo[i]->version,
                       disp_ver(iver));
            else
                warnx2("pkgadd failed for %s, stopping", todo[i]->name);
            rc = EX_PKGCMD;
            break;
        }
        t.p[i].done = 1;
        (void)txn_save(cf, &t);
        if (!opt_dryrun) {
            if (upgrade)
                printf("upgraded %s to %s\n", todo[i]->name,
                       todo[i]->version);
            else
                printf("installed %s-%s\n", todo[i]->name,
                       todo[i]->version);
        }
    }
    rc = txn_finish(cf, &t, rc);
    txn_free(&t);
    return rc;
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
    if (ent->refused != NULL) {
        warnx2("%s: the catalog entry is refused: %s", name, ent->refused);
        return EX_VERIFY;
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

static void free_strv(char **v, int n)
{
    int i;

    for (i = 0; i < n; i++)
        free(v[i]);
    free((char *)v);
}

int cmd_install(const struct conf *cf, struct catalog *cat,
                char **names, int nnames)
{
    struct source src;
    struct pkgent **order;
    struct pkgent **todo;
    int *ow;               /* parallel to todo[]: pass instance=overwrite */
    char **files;
    char **insts;
    struct pkgent *ent;
    char *pkgadd;
    char *staged;
    char iver[128];
    char inst[64];
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
     *
     * Kernel-space packages follow the same rules; their installed
     * version is their record's.
     */
    todo = (struct pkgent **)xmalloc(
        (unsigned)((no > 0 ? no : 1) * sizeof(struct pkgent *)));
    ow = (int *)xmalloc((unsigned)((no > 0 ? no : 1) * sizeof(int)));
    nt = 0;
    for (i = 0; i < no; i++) {
        ent = order[i];
        named = is_named(names, nnames, ent);
        if (!ent_installed(cf, ent, iver, sizeof(iver))) {
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

    /* one transaction at a time on a target; then the kernel-space
     * pre-flight, before anything is fetched */
    rc = txn_refuse_if_pending(cf) != 0 ? EX_USAGE :
         kspace_preflight(cf, todo, nt);
    if (rc != EX_OK) {
        free((char *)todo);
        free((char *)ow);
        return rc;
    }
    announce_kspace(count_kspace(todo, nt));

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

    /* phase 1: stage + verify EVERYTHING before touching the system,
     * so a bad source cannot leave a half-installed chain */
    files = (char **)xmalloc((unsigned)(nt * sizeof(char *)));
    insts = (char **)xmalloc((unsigned)(nt * sizeof(char *)));
    for (i = 0; i < nt; i++) {
        rc = src_stage(&src, todo[i], cf->cachedir, &staged, &eph);
        if (rc == EX_OK && todo[i]->kspace &&
            kspace_inst(todo[i], staged, inst, sizeof(inst)) != 0) {
            free(staged);
            rc = EX_VERIFY;
        }
        if (rc != EX_OK) {
            free_strv(files, i);
            free_strv(insts, i);
            free((char *)todo);
            free((char *)ow);
            free(pkgadd);
            src_close(&src);
            return rc;
        }
        note("staged %s%s", staged, eph ? "" : " (in place)");
        files[i] = staged;
        insts[i] = xstrdup(todo[i]->kspace ? inst : todo[i]->pkginst);
    }

    /* phase 2: journal, pkgadd in dependency order (stop on the first
     * failure), then the trigger when kernel space changed */
    rc = commit_txn(cf, &src, "install", todo, ow, files, insts, nt,
                    pkgadd);

    free_strv(files, nt);
    free_strv(insts, nt);
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
    struct pkgent *todo[1];
    int ow[1];
    char *files[1];
    char *insts[1];
    char iver[128];
    char inst[64];
    char *pkgadd;
    char *staged;
    int eph;
    int rc;

    ent = catalog_find(cat, name);
    if (ent == NULL) {
        warnx2("package %s not in catalog", name);
        return EX_DEPS;
    }
    if (!ent_installed(cf, ent, iver, sizeof(iver))) {
        warnx2("%s is not installed; use 'apkg install %s'", name, name);
        return EX_USAGE;
    }
    if (apkg_vercmp(ent->version, iver) <= 0) {
        printf("%s is up to date (installed %s, catalog %s)\n",
               name, disp_ver(iver), ent->version);
        return EX_OK;
    }
    todo[0] = ent;
    ow[0] = 1;
    if (txn_refuse_if_pending(cf) != 0)
        return EX_USAGE;
    if ((rc = kspace_preflight(cf, todo, 1)) != EX_OK)
        return rc;
    printf("upgrading %s %s -> %s\n", name, disp_ver(iver), ent->version);
    announce_kspace(ent->kspace);

    pkgadd = conf_pkgcmd(cf, 0);
    if (pkgadd == NULL)
        return EX_USAGE;
    if (src_open(cf->repo, &src) != 0) {
        free(pkgadd);
        return EX_USAGE;
    }
    http_opts_from_conf(&src.http, cf);

    /* fetch + verify BEFORE anything touches the system: a bad
     * source must cost nothing but a failed exit */
    rc = src_stage(&src, ent, cf->cachedir, &staged, &eph);
    if (rc == EX_OK && ent->kspace &&
        kspace_inst(ent, staged, inst, sizeof(inst)) != 0) {
        free(staged);
        rc = EX_VERIFY;
    }
    if (rc != EX_OK) {
        warnx2("%s not fetched; the installed %s %s is untouched",
               name, name, disp_ver(iver));
        free(pkgadd);
        src_close(&src);
        return rc;
    }
    note("staged %s%s", staged, eph ? "" : " (in place)");
    files[0] = staged;
    insts[0] = ent->kspace ? inst : ent->pkginst;

    rc = commit_txn(cf, &src, "upgrade", todo, ow, files, insts, 1,
                    pkgadd);
    free(staged);
    free(pkgadd);
    src_close(&src);
    return rc;
}

/* remove one package: pkgrm, and for kernel space its record and the
 * trigger (a generation without the package is built and committed) */
int cmd_remove(const struct conf *cf, struct catalog *cat,
               const char *name)
{
    struct pkgent *ent;
    struct pkgent kent;
    struct txn t;
    const char *pkginst;
    char iver[128];
    char kinst[64];
    char key[256];
    char *pkgrm;
    int kspace;
    int rc;

    /* a kernel-space package is known by its record -- the file named by
     * its pkginst, found by name or pkginst (C2-2 v4 §2); its pkginst is
     * the one owning its recorded files in the contents database */
    pkginst = name;
    ent = NULL;
    if (cat != NULL)
        ent = catalog_find(cat, name);
    kspace = kpkg_find(cf, name, key, sizeof(key));
    if (!kspace && ent != NULL && ent->kspace)
        kspace = kpkg_find(cf, ent->pkginst, key, sizeof(key));
    if (kspace) {
        if (kpkg_owner(cf, key, kinst, sizeof(kinst)) == 0)
            pkginst = kinst;
        else if (ent != NULL)
            pkginst = ent->pkginst;
    } else if (ent != NULL) {
        /* map catalog name -> pkginst when we have a catalog; otherwise
         * (or when the name is unknown there) treat it as a pkginst */
        pkginst = ent->pkginst;
    }
    if (!installed_version(cf, pkginst, iver, sizeof(iver)) && !kspace) {
        warnx2("%s (pkginst %s) is not installed", name, pkginst);
        return EX_USAGE;
    }
    if (txn_refuse_if_pending(cf) != 0)
        return EX_USAGE;
    announce_kspace(kspace);
    pkgrm = conf_pkgcmd(cf, 1);
    if (pkgrm == NULL)
        return EX_USAGE;

    memset((char *)&kent, 0, sizeof(kent));
    kent.name = (char *)name;
    kent.version = (char *)"-";
    kent.filename = (char *)"-";
    kent.kspace = kspace;
    kent.md5 = (char *)"-";
    kent.pkginst = key;                 /* the record's file (txn_add) */
    txn_init(&t, "remove");
    txn_add(&t, &kent, pkginst, "-", 0, "-");
    if (txn_save(cf, &t) != 0) {
        txn_free(&t);
        free(pkgrm);
        return EX_USAGE;
    }

    rc = EX_OK;
    if (!installed_version(cf, pkginst, iver, sizeof(iver))) {
        warnx2("%s: the record names %s, which is not installed; "
               "removing the record", name, pkginst);
    } else if (run_pkgrm(cf, pkgrm, pkginst) != 0) {
        warnx2("pkgrm failed for %s", pkginst);
        rc = EX_PKGCMD;
    }
    if (rc == EX_OK && kspace && kpkg_remove_record(cf, key) != 0)
        rc = EX_USAGE;
    if (rc == EX_OK) {
        t.p[0].done = 1;
        (void)txn_save(cf, &t);
        if (!opt_dryrun)
            printf("removed %s\n", pkginst);
    }
    rc = txn_finish(cf, &t, rc);
    txn_free(&t);
    free(pkgrm);
    return rc;
}

/* ---------------- recover ---------------- */

/* the staged datastream still there and still the verified bytes? */
static int staged_ok(const struct txnpkg *p)
{
    char hex[65];

    if (!file_exists(p->staged)) {
        warnx2("%s: the staged datastream %s is gone", p->name, p->staged);
        return 0;
    }
    if (p->size >= 0 && file_size(p->staged) != p->size) {
        warnx2("%s: %s changed size since it was verified", p->name,
               p->staged);
        return 0;
    }
    if (strcmp(p->hash, "-") == 0)
        return 1;
    if (p->kspace) {
        if (sha256_file(p->staged, hex) != 0 || strcmp(hex, p->hash) != 0) {
            warnx2("%s: %s no longer matches its sha256", p->name,
                   p->staged);
            return 0;
        }
    } else if (md5_file(p->staged, hex) != 0 || strcmp(hex, p->hash) != 0) {
        warnx2("%s: %s no longer matches its md5", p->name, p->staged);
        return 0;
    }
    return 1;
}

int cmd_recover(const struct conf *cf)
{
    struct txn t;
    struct txnpkg *p;
    char iver[128];
    char *eng;
    int remove;
    int ndone;
    int i;
    int rc;

    if (!txn_exists(cf)) {
        printf("no unfinished transaction\n");
        return EX_OK;
    }
    rc = txn_load(cf, &t);
    if (rc != 0) {
        if (opt_force && !opt_dryrun) {
            warnx2("discarding the unreadable journal %s", cf->txnfile);
            txn_clear(cf);
            return EX_OK;
        }
        return EX_USAGE;
    }
    ndone = 0;
    for (i = 0; i < t.n; i++)
        ndone += t.p[i].done;
    printf("unfinished %s transaction (started %ld): %d of %d package%s "
           "done, state %s%s\n", t.verb, t.started, ndone, t.n,
           t.n == 1 ? "" : "s", t.state,
           t.kspace ? ", kernel space" : "");
    for (i = 0; i < t.n; i++)
        printf("  %s %s%s%s\n", t.p[i].done ? "done   " : "pending",
               t.p[i].name, strcmp(t.p[i].version, "-") != 0 ? "-" : "",
               strcmp(t.p[i].version, "-") != 0 ? t.p[i].version : "");
    if (opt_force) {
        printf("discarding the journal (-f); nothing else is changed\n");
        txn_clear(cf);
        txn_free(&t);
        return EX_OK;
    }

    remove = strcmp(t.verb, "remove") == 0;
    eng = conf_pkgcmd(cf, remove);
    if (eng == NULL) {
        txn_free(&t);
        return EX_USAGE;
    }
    rc = EX_OK;
    for (i = 0; i < t.n && rc == EX_OK; i++) {
        p = &t.p[i];
        if (p->done)
            continue;
        if (remove) {
            if (installed_version(cf, p->pkginst, iver, sizeof(iver)) &&
                run_pkgrm(cf, eng, p->pkginst) != 0) {
                warnx2("pkgrm failed for %s", p->pkginst);
                rc = EX_PKGCMD;
                break;
            }
            if (p->kspace && kpkg_remove_record(cf, p->reckey) != 0) {
                rc = EX_USAGE;
                break;
            }
        } else {
            if (!staged_ok(p)) {
                warnx2("cannot finish %s from the journal: 'apkg -f "
                       "recover' discards it, then install %s again",
                       p->name, p->name);
                rc = EX_VERIFY;
                break;
            }
            /* instance=overwrite: replaces whatever a cut pkgadd left */
            if (install_one(cf, eng, p->staged, p->pkginst, 1, p) !=
                EX_OK) {
                warnx2("pkgadd failed for %s", p->name);
                rc = EX_PKGCMD;
                break;
            }
        }
        p->done = 1;
        (void)txn_save(cf, &t);
        if (!opt_dryrun)
            printf("%s %s\n", remove ? "removed" : "installed", p->name);
    }
    free(eng);
    if (rc != EX_OK) {
        warnx2("the journal %s is kept", cf->txnfile);
        txn_free(&t);
        return rc;
    }
    if (t.kspace) {
        rc = kspace_trigger(cf, &t);
        if (rc != EX_BOOTSET)
            txn_clear(cf);
    } else {
        txn_clear(cf);
    }
    if (rc == EX_OK)
        printf("transaction finished\n");
    txn_free(&t);
    return rc;
}
