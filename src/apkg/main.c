/*
 * main.c - apkg: remote package client for Amiga Unix (Amix, SVR4 m68k).
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Verbs (docs/design.md section 2):
 *   update, list [installed|all], search <substr>, info <name>,
 *   download <name>, install <name>..., upgrade <name>,
 *   remove <name>, version
 * Options (before the verb): -n dry-run, -f force (applies to the
 *   packages NAMED on the command line, never to their dependencies),
 *   -v verbose, -c <conffile>.
 *
 * Option scanning is hand-rolled (design allows getopt or hand-rolled):
 * GNU getopt permutes argv while the SVR4 one does not, and identical
 * behaviour on host and target matters more than the three lines saved.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

#include "apkg.h"
#include "source.h"

int opt_dryrun = 0;
int opt_force = 0;
int opt_verbose = 0;

static void usage(void)
{
    fprintf(stderr,
        "usage: apkg [-n] [-f] [-v] [-c conffile] [-R root] <verb> [args]\n"
        "verbs:\n"
        "  update              fetch the repository catalog\n"
        "  list [installed|all]  list catalog packages\n"
        "  search <substr>     case-insensitive search of name/description\n"
        "  info <name>         show one catalog entry + installed state\n"
        "  download <name>     fetch a package into the cache and verify\n"
        "  install <name>...   resolve deps, download, pkgadd\n"
        "  upgrade <name>      pkgadd over the installed instance when the\n"
        "                      catalog is newer (no pkgrm; never uninstalls)\n"
        "  remove <name>       pkgrm wrapper\n"
        "  recover             finish (or with -f discard) an interrupted\n"
        "                      transaction from the journal /var/apkg/txn\n"
        "  version             print client version\n"
        "options: -n dry-run, -f force reinstall of the NAMED packages only,\n"
        "         -v verbose, -c conffile,\n"
        "         -R root install into an alternate target root (pkgadd -R)\n");
}

/* ---------------- update ---------------- */

/* read the first 32 hex chars (skipping leading whitespace) out of a
 * catalog.md5 file; accepts both bare digests and "md5sum" output */
static int read_md5_file(const char *path, char hex[33])
{
    FILE *fp;
    int c;
    int i;

    fp = fopen(path, "r");
    if (fp == NULL)
        return -1;
    do {
        c = getc(fp);
    } while (c == ' ' || c == '\t' || c == '\n' || c == '\r');
    i = 0;
    while (i < 32 && c != EOF &&
           ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') ||
            (c >= 'A' && c <= 'F'))) {
        hex[i++] = (char)((c >= 'A' && c <= 'F') ? c - 'A' + 'a' : c);
        c = getc(fp);
    }
    fclose(fp);
    hex[i] = '\0';
    return i == 32 ? 0 : -1;
}

static int cmd_update(const struct conf *cf)
{
    struct catalog cat;
    struct source src;
    char *tmp;
    char *md5tmp;
    char *catdir;
    char expect[33];
    char got[33];
    int rc;
    int status;
    int n;
    int nk;

    catdir = dirname_of(cf->catalog);
    if (mkpath(catdir) != 0) {
        warnx2("cannot create %s", catdir);
        free(catdir);
        return EX_USAGE;
    }
    free(catdir);

    if (src_open(cf->repo, &src) != 0)
        return EX_USAGE;
    http_opts_from_conf(&src.http, cf);

    if (opt_dryrun) {
        printf("would fetch %s/catalog -> %s\n", cf->repo, cf->catalog);
        src_close(&src);
        return EX_OK;
    }
    tmp = cat2(cf->catalog, ".new");
    rc = src_fetch(&src, "catalog", tmp, &status);
    if (rc == SRC_ESTATUS) {
        warnx2("catalog fetch from %s: status %d", cf->repo, status);
        src_close(&src);
        free(tmp);
        return EX_NET;
    }
    if (rc != SRC_OK) {
        src_close(&src);
        free(tmp);
        return EX_NET;
    }

    /* optional catalog.md5; an absent one (404-alike) means the source
     * does not carry one - skip verification, do not fail */
    md5tmp = cat2(cf->catalog, ".md5new");
    rc = src_fetch(&src, "catalog.md5", md5tmp, &status);
    if (rc == SRC_OK) {
        if (read_md5_file(md5tmp, expect) != 0) {
            warnx2("unparsable catalog.md5 from %s, ignoring it", cf->repo);
        } else if (md5_file(tmp, got) != 0 ||
                   strcmp(got, expect) != 0) {
            warnx2("catalog md5 mismatch (got %s, expected %s)",
                   got, expect);
            unlink(tmp);
            unlink(md5tmp);
            src_close(&src);
            free(md5tmp);
            free(tmp);
            return EX_VERIFY;
        } else {
            note("catalog md5 verified");
        }
        unlink(md5tmp);
    } else if (rc == SRC_ESTATUS && status == 404) {
        note("no catalog.md5 on the source, skipping verification");
    } else if (rc == SRC_ESTATUS) {
        warnx2("catalog.md5 fetch from %s: status %d", cf->repo, status);
        unlink(tmp);
        src_close(&src);
        free(md5tmp);
        free(tmp);
        return EX_NET;
    } else {
        unlink(tmp);
        src_close(&src);
        free(md5tmp);
        free(tmp);
        return EX_NET;
    }
    src_close(&src);
    free(md5tmp);

    /* header + format check before the new catalog goes live */
    rc = catalog_load(tmp, &cat);
    if (rc != CAT_OK) {
        if (rc == CAT_EBADHDR)
            warnx2("fetched catalog lacks the '%s' header, rejecting",
                   CATALOG_MAGIC);
        else
            warnx2("fetched catalog is malformed, rejecting");
        unlink(tmp);
        free(tmp);
        return EX_VERIFY;
    }
    n = cat.n - cat.nk;
    nk = cat.nk;
    catalog_free(&cat);

    if (rename(tmp, cf->catalog) != 0) {
        warnx2("cannot rename %s to %s", tmp, cf->catalog);
        unlink(tmp);
        free(tmp);
        return EX_USAGE;
    }
    free(tmp);
    if (nk > 0)
        printf("catalog updated: %d package%s, %d kernel-space "
               "(unverified: no signature check in this release)\n",
               n, n == 1 ? "" : "s", nk);
    else
        printf("catalog updated: %d package%s\n", n, n == 1 ? "" : "s");
    return EX_OK;
}

/* ---------------- list / search / info ---------------- */

/* installed state of any catalog entry: a kernel-space package is
 * installed when apkg holds its record (/var/apkg/kpkg/<name>) */
static int ent_installed_v(const struct conf *cf, const struct pkgent *e,
                           char *ver, unsigned verlen)
{
    if (e->kspace)
        return kpkg_installed(cf, e->name, ver, verlen);
    return installed_version(cf, e->pkginst, ver, verlen);
}

/* installed-marker column, e.g. "[installed 1.1]" or "-" */
static void inst_marker(const struct conf *cf, const struct pkgent *e,
                        char *buf, unsigned buflen)
{
    char iver[128];
    const char *v;

    if (!ent_installed_v(cf, e, iver, sizeof(iver))) {
        strcpy(buf, e->refused != NULL ? "[refused]" : "-");
        return;
    }
    v = iver[0] == '\0' ? "(none)" : iver;
    if (strlen(v) + 13 > buflen)         /* "[installed ]" + NUL */
        v = "?";
    sprintf(buf, "[installed %s]", v);   /* bounded: checked above */
}

static void list_line(const struct conf *cf, const struct pkgent *e)
{
    char marker[160];

    inst_marker(cf, e, marker, sizeof(marker));
    printf("%-14s %-10s %-20s %-10s %.40s\n",
           e->name, e->version, marker, e->category, e->desc);
}

static int cmd_list(const struct conf *cf, struct catalog *cat,
                    const char *which)
{
    char iver[128];
    int installed_only;
    int i;

    installed_only = 0;
    if (which != NULL) {
        if (strcmp(which, "installed") == 0)
            installed_only = 1;
        else if (strcmp(which, "all") != 0) {
            warnx2("list: expected 'installed' or 'all', not '%s'", which);
            return EX_USAGE;
        }
    }
    for (i = 0; i < cat->n; i++) {
        if (installed_only &&
            !ent_installed_v(cf, &cat->ents[i], iver, sizeof(iver)))
            continue;
        list_line(cf, &cat->ents[i]);
    }
    return EX_OK;
}

static int cmd_search(const struct conf *cf, struct catalog *cat,
                      const char *substr)
{
    int i;

    for (i = 0; i < cat->n; i++) {
        if (ci_strfind(cat->ents[i].name, substr) ||
            ci_strfind(cat->ents[i].desc, substr))
            list_line(cf, &cat->ents[i]);
    }
    return EX_OK;
}

static int cmd_info(const struct conf *cf, struct catalog *cat,
                    const char *name)
{
    struct pkgent *e;
    char iver[128];
    int i;

    e = catalog_find(cat, name);
    if (e == NULL) {
        warnx2("package %s not in catalog", name);
        return EX_USAGE;
    }
    printf("Name:        %s\n", e->name);
    printf("Version:     %s\n", e->version);
    printf("Pkginst:     %s%s\n", e->pkginst,
           e->kspace && e->kpkginst == NULL ? " (from the datastream)" : "");
    printf("Filename:    %s\n", e->filename);
    if (e->kspace) {
        printf("Kernel-space: %s, line %s\n", e->role, e->kline);
        if (strcmp(e->role, "loader") == 0) {
            printf("Loader:      %s\n", e->loaderv);
        } else {
            printf("Kabi:        %s\n", e->kabi);
            printf("Pin:         %s\n", e->pin);
        }
        printf("SHA256:      %s\n", e->sha256);
        printf("Signature:   unverified (no signature check in this "
               "release)\n");
        if (e->refused != NULL)
            printf("Refused:     %s\n", e->refused);
    } else {
        printf("MD5:         %s\n", e->md5);
    }
    printf("Size:        %ld\n", e->size);
    printf("Depends:     ");
    if (e->ndeps == 0) {
        printf("none\n");
    } else {
        for (i = 0; i < e->ndeps; i++)
            printf("%s%s", i > 0 ? ", " : "", e->deps[i]);
        printf("\n");
    }
    printf("Category:    %s\n", e->category);
    printf("Description: %s\n", e->desc);
    if (ent_installed_v(cf, e, iver, sizeof(iver)))
        printf("Installed:   yes, version %s\n",
               iver[0] == '\0' ? "(none)" : iver);
    else
        printf("Installed:   no\n");
    return EX_OK;
}

/* ---------------- catalog loading with user-facing errors -------- */

static int load_catalog_or_die(const struct conf *cf, struct catalog *cat,
                               int *exitcode)
{
    int rc;

    rc = catalog_load(cf->catalog, cat);
    if (rc == CAT_OK)
        return 0;
    if (rc == CAT_ENOENT) {
        warnx2("no catalog at %s - run 'apkg update' first", cf->catalog);
        *exitcode = EX_USAGE;
    } else if (rc == CAT_EBADHDR) {
        warnx2("%s lacks the '%s' header - refusing to use it",
               cf->catalog, CATALOG_MAGIC);
        *exitcode = EX_VERIFY;
    } else {
        warnx2("%s is malformed - run 'apkg update'", cf->catalog);
        *exitcode = EX_VERIFY;
    }
    return -1;
}

/* ---------------- entry point ---------------- */

int main(int argc, char **argv)
{
    struct conf cf;
    struct catalog cat;
    const char *conffile;
    const char *root_opt;
    const char *verb;
    const char *p;
    int i;
    int rc;
    int ec;

    conffile = NULL;
    root_opt = NULL;
    i = 1;
    while (i < argc && argv[i][0] == '-' && argv[i][1] != '\0') {
        for (p = argv[i] + 1; *p != '\0'; p++) {
            switch (*p) {
            case 'n':
                opt_dryrun = 1;
                break;
            case 'f':
                opt_force = 1;
                break;
            case 'v':
                opt_verbose = 1;
                break;
            case 'c':
                if (p[1] != '\0') {
                    conffile = p + 1;
                    p += strlen(p) - 1;
                } else if (i + 1 < argc) {
                    i++;
                    conffile = argv[i];
                } else {
                    warnx2("-c needs a file argument");
                    usage();
                    return EX_USAGE;
                }
                break;
            case 'R':
                if (p[1] != '\0') {
                    root_opt = p + 1;
                    p += strlen(p) - 1;
                } else if (i + 1 < argc) {
                    i++;
                    root_opt = argv[i];
                } else {
                    warnx2("-R needs a root argument");
                    usage();
                    return EX_USAGE;
                }
                break;
            default:
                warnx2("unknown option -%c", *p);
                usage();
                return EX_USAGE;
            }
        }
        i++;
    }
    if (i >= argc) {
        usage();
        return EX_USAGE;
    }
    verb = argv[i];
    i++;

    if (strcmp(verb, "version") == 0) {
        printf("apkg %s\n", APKG_VERSION);
        return EX_OK;
    }

    signal(SIGPIPE, SIG_IGN);

    if (conf_load(conffile, root_opt, &cf) != 0)
        return EX_USAGE;

    if (strcmp(verb, "update") == 0) {
        if (i != argc) {
            usage();
            return EX_USAGE;
        }
        return cmd_update(&cf);
    }

    if (strcmp(verb, "list") == 0) {
        if (argc - i > 1) {
            usage();
            return EX_USAGE;
        }
        if (load_catalog_or_die(&cf, &cat, &ec) != 0)
            return ec;
        rc = cmd_list(&cf, &cat, i < argc ? argv[i] : NULL);
        catalog_free(&cat);
        return rc;
    }

    if (strcmp(verb, "search") == 0) {
        if (argc - i != 1) {
            usage();
            return EX_USAGE;
        }
        if (load_catalog_or_die(&cf, &cat, &ec) != 0)
            return ec;
        rc = cmd_search(&cf, &cat, argv[i]);
        catalog_free(&cat);
        return rc;
    }

    if (strcmp(verb, "info") == 0) {
        if (argc - i != 1) {
            usage();
            return EX_USAGE;
        }
        if (load_catalog_or_die(&cf, &cat, &ec) != 0)
            return ec;
        rc = cmd_info(&cf, &cat, argv[i]);
        catalog_free(&cat);
        return rc;
    }

    if (strcmp(verb, "download") == 0) {
        if (argc - i != 1) {
            usage();
            return EX_USAGE;
        }
        if (load_catalog_or_die(&cf, &cat, &ec) != 0)
            return ec;
        rc = cmd_download(&cf, &cat, argv[i]);
        catalog_free(&cat);
        return rc;
    }

    if (strcmp(verb, "install") == 0) {
        if (argc - i < 1) {
            usage();
            return EX_USAGE;
        }
        if (load_catalog_or_die(&cf, &cat, &ec) != 0)
            return ec;
        rc = cmd_install(&cf, &cat, argv + i, argc - i);
        catalog_free(&cat);
        return rc;
    }

    if (strcmp(verb, "upgrade") == 0) {
        if (argc - i != 1) {
            usage();
            return EX_USAGE;
        }
        if (load_catalog_or_die(&cf, &cat, &ec) != 0)
            return ec;
        rc = cmd_upgrade(&cf, &cat, argv[i]);
        catalog_free(&cat);
        return rc;
    }

    if (strcmp(verb, "remove") == 0) {
        if (argc - i != 1) {
            usage();
            return EX_USAGE;
        }
        /* the catalog is optional for remove: it only maps a friendly
         * name to a pkginst */
        if (catalog_load(cf.catalog, &cat) == CAT_OK) {
            rc = cmd_remove(&cf, &cat, argv[i]);
            catalog_free(&cat);
        } else {
            rc = cmd_remove(&cf, NULL, argv[i]);
        }
        return rc;
    }

    if (strcmp(verb, "recover") == 0) {
        if (i != argc) {
            usage();
            return EX_USAGE;
        }
        return cmd_recover(&cf);
    }

    warnx2("unknown verb '%s'", verb);
    usage();
    return EX_USAGE;
}
