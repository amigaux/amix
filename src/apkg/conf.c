/*
 * conf.c - /etc/apkg.conf parsing and defaults for apkg.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Format: plain "key=value" lines, '#' starts a comment, blank lines
 * ignored, whitespace around key and value trimmed.  Unknown keys warn.
 *
 * Keys: repo, cachedir, pkgadd, pkgrm, admin, the fetch-path tunables --
 * timeout, connect_timeout, retries, retry_delay, progress, bufsize,
 * redirects, rcvbuf, sndbuf -- and the resolver's three: nameserver,
 * dns_timeout, dns_retries.  Nothing the fetch path does is a
 * compiled-in constant an operator cannot move; the defaults live in
 * apkg.h.
 *
 * `admin` names the admin(4) FILE handed to `pkgadd -a` / `pkgrm -a`.
 * conf_adminfile() below MATERIALISES it rather than trusting it to be
 * there -- see the comment on that function; that is a metal fix, not
 * belt-and-braces.
 *
 *   timeout          seconds of network SILENCE tolerated mid-transfer.
 *                    NOT a cap on how long a transfer may take: http.c
 *                    re-arms the timer on every chunk that arrives, so
 *                    a slow-but-flowing multi-megabyte fetch never
 *                    trips it however long it runs.
 *   connect_timeout  its own, much shorter budget for resolve+connect,
 *                    so a dead host fails in seconds rather than
 *                    inheriting the mid-transfer patience.
 *   retries          extra attempts after a NETWORK failure (a non-200
 *                    status is an answer, not a failure -- never retried).
 *   retry_delay      seconds before the first retry; doubles each time.
 *   progress         bytes between progress lines on stderr; 0 silences
 *                    them.  -v quarters the interval.
 *   bufsize          socket read buffer, clamped to [512, 262144].
 *   redirects        301/302 hops followed; 0 refuses to follow any.
 *   nameserver       an IPv4 nameserver for the stub resolver (dns.c),
 *                    optionally with ":port".  REPEATABLE: each line
 *                    appends, and they are tried in the order written.
 *                    The default list is EMPTY -- with no nameserver
 *                    line apkg resolves exactly as it always did, out
 *                    of the hosts file only.  A line with an empty
 *                    value CLEARS the list, so a later config can undo
 *                    an earlier one.  The hosts file is consulted
 *                    FIRST in any case: DNS is the fallback, never the
 *                    override.
 *   dns_timeout      seconds per DNS query ATTEMPT (not per name, not
 *                    per server).
 *   dns_retries      extra attempts per nameserver; every configured
 *                    server is asked in turn regardless.
 *   rcvbuf/sndbuf    SO_RCVBUF / SO_SNDBUF, REQUESTED before connect();
 *                    0 leaves the stack's own default.  SO_RCVBUF is
 *                    the only client-side lever on the TCP receive
 *                    window, but on the stock Amix stack its effect is
 *                    unverified -- sockmod may not propagate it to the
 *                    tcp module, whose hiwat is 4096 -- so the -v
 *                    readback is not proof.  See apkg.h.
 *
 * Numbers are parsed strictly (a trailing 'x' is an error, not a zero)
 * so that a typo is reported rather than silently meaning "0" for the
 * keys where 0 is a legal value.  A rejected value warns and leaves
 * the default in place -- a bad config file never disables a guard.
 *
 * Two roots, independent and composable:
 *
 *   APKG_ROOT (environment) - the CLIENT's own root.  Prefixes every
 *     COMPILED-IN default path (/etc/apkg.conf, everything under
 *     /var/apkg, and the pkgadd/pkgrm binaries with their /usr/sbin
 *     fallbacks) so the whole client can be pointed at a fake root for
 *     testing or offline image work.  Config-file values are literal.
 *
 *   -R <target> (conf_load's target_opt) - the INSTALL TARGET root.  It
 *     prefixes ONLY the "is it installed?" database (/var/sadm/pkg) and
 *     is passed through to `pkgadd -R`.  It deliberately does NOT move
 *     the engine binaries, the admin file, the config, or the cache:
 *     the engine runs FROM the miniroot/CD and installs INTO the target
 *     (prefixing the engine path would be the classic bootstrap bug).
 *
 * The two compose: <root><target>/var/sadm/pkg is the target DB, so a
 * host test can relocate the whole world under APKG_ROOT and still aim
 * -R inside it.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>

#include "apkg.h"

#define DEF_REPO      "http://pkg.amigaux.org"
#define DEF_CACHEDIR  "/var/apkg/cache"
#define DEF_PKGADD    "/usr/apkg/bin/pkgadd"
#define DEF_PKGADD_FB "/usr/sbin/pkgadd"
#define DEF_PKGRM     "/usr/apkg/bin/pkgrm"
#define DEF_PKGRM_FB  "/usr/sbin/pkgrm"
#define DEF_ADMIN     "/var/apkg/admin"
#define DEF_CONF      "/etc/apkg.conf"

/* Strict decimal parse: the WHOLE string must be an optionally signed
 * integer.  Returns 0 and stores the value, or -1 on anything else
 * (including an empty value).  atol() cannot be used here: it maps
 * both "0" and "banana" to 0, and 0 is a legal setting for several of
 * these keys. */
static int getnum(const char *s, long *out)
{
    long v;
    int neg;
    int digits;

    neg = 0;
    if (*s == '-' || *s == '+') {
        neg = (*s == '-');
        s++;
    }
    v = 0;
    digits = 0;
    while (*s != '\0') {
        if (!isdigit((unsigned char)*s))
            return -1;
        v = v * 10 + (long)(*s - '0');
        digits++;
        if (digits > 18)
            return -1;
        s++;
    }
    if (digits == 0)
        return -1;
    *out = neg ? -v : v;
    return 0;
}

static char *trim(char *s)
{
    char *end;

    while (*s != '\0' && isspace((unsigned char)*s))
        s++;
    end = s + strlen(s);
    while (end > s && isspace((unsigned char)end[-1]))
        end--;
    *end = '\0';
    return s;
}

/* Load configuration.  conffile_opt is the -c argument or NULL;
 * target_opt is the -R argument or NULL.
 * Returns 0 on success, -1 on error (message already printed). */
int conf_load(const char *conffile_opt, const char *target_opt,
              struct conf *cf)
{
    FILE *fp;
    char line[1024];
    char *p;
    char *key;
    char *val;
    char *cachedir_dir;
    char *rootpfx;
    const char *rootenv;
    unsigned tlen;
    long num;
    long clamped;
    int lineno;

    rootenv = getenv("APKG_ROOT");
    if (rootenv == NULL)
        rootenv = "";
    cf->root = xstrdup(rootenv);

    /* -R target: prefixes the target DB only; strip one trailing slash */
    cf->target = xstrdup(target_opt != NULL ? target_opt : "");
    tlen = (unsigned)strlen(cf->target);
    if (tlen > 1 && cf->target[tlen - 1] == '/')
        cf->target[tlen - 1] = '\0';

    cf->repo = xstrdup(DEF_REPO);
    cf->cachedir = cat2(cf->root, DEF_CACHEDIR);
    cf->pkgadd = cat2(cf->root, DEF_PKGADD);
    cf->pkgrm = cat2(cf->root, DEF_PKGRM);
    cf->admin = cat2(cf->root, DEF_ADMIN);
    cf->timeout = APKG_DEF_TIMEOUT;
    cf->conn_timeout = APKG_DEF_CONNTIMEO;
    cf->retries = APKG_DEF_RETRIES;
    cf->retry_delay = APKG_DEF_RETRYDELAY;
    cf->progress = APKG_DEF_PROGRESS;
    cf->bufsize = APKG_DEF_BUFSIZE;
    cf->redirects = APKG_DEF_REDIRECTS;
    cf->rcvbuf = APKG_DEF_RCVBUF;
    cf->sndbuf = APKG_DEF_SNDBUF;
    cf->nameservers = NULL;
    cf->nnameservers = 0;
    cf->dns_timeout = APKG_DEF_DNSTIMEO;
    cf->dns_retries = APKG_DEF_DNSRETRIES;
    cf->pkgadd_is_default = 1;
    cf->pkgrm_is_default = 1;

    if (conffile_opt != NULL)
        cf->conffile = xstrdup(conffile_opt);
    else
        cf->conffile = cat2(cf->root, DEF_CONF);

    fp = fopen(cf->conffile, "r");
    if (fp == NULL) {
        if (conffile_opt != NULL) {
            warnx2("cannot open config file %s", cf->conffile);
            return -1;
        }
        /* no default config file: run on built-in defaults */
        note("no config file %s, using defaults", cf->conffile);
    } else {
        lineno = 0;
        while (fgets(line, (int)sizeof(line), fp) != NULL) {
            lineno++;
            p = strchr(line, '#');
            if (p != NULL)
                *p = '\0';
            p = trim(line);
            if (*p == '\0')
                continue;
            val = strchr(p, '=');
            if (val == NULL) {
                warnx2("%s:%d: not key=value, ignored",
                       cf->conffile, lineno);
                continue;
            }
            *val = '\0';
            val++;
            key = trim(p);
            val = trim(val);
            if (strcmp(key, "repo") == 0) {
                free(cf->repo);
                cf->repo = xstrdup(val);
            } else if (strcmp(key, "cachedir") == 0) {
                free(cf->cachedir);
                cf->cachedir = xstrdup(val);
            } else if (strcmp(key, "pkgadd") == 0) {
                free(cf->pkgadd);
                cf->pkgadd = xstrdup(val);
                cf->pkgadd_is_default = 0;
            } else if (strcmp(key, "pkgrm") == 0) {
                free(cf->pkgrm);
                cf->pkgrm = xstrdup(val);
                cf->pkgrm_is_default = 0;
            } else if (strcmp(key, "admin") == 0) {
                free(cf->admin);
                cf->admin = xstrdup(val);
            } else if (strcmp(key, "timeout") == 0) {
                if (getnum(val, &num) != 0 || num <= 0)
                    warnx2("%s:%d: bad timeout '%s', keeping %ld",
                           cf->conffile, lineno, val, cf->timeout);
                else
                    cf->timeout = num;
            } else if (strcmp(key, "connect_timeout") == 0) {
                if (getnum(val, &num) != 0 || num <= 0)
                    warnx2("%s:%d: bad connect_timeout '%s', keeping %ld",
                           cf->conffile, lineno, val, cf->conn_timeout);
                else
                    cf->conn_timeout = num;
            } else if (strcmp(key, "retries") == 0) {
                if (getnum(val, &num) != 0 || num < 0 || num > 100)
                    warnx2("%s:%d: bad retries '%s', keeping %d",
                           cf->conffile, lineno, val, cf->retries);
                else
                    cf->retries = (int)num;
            } else if (strcmp(key, "retry_delay") == 0) {
                if (getnum(val, &num) != 0 || num < 0)
                    warnx2("%s:%d: bad retry_delay '%s', keeping %ld",
                           cf->conffile, lineno, val, cf->retry_delay);
                else
                    cf->retry_delay = num;
            } else if (strcmp(key, "progress") == 0) {
                if (getnum(val, &num) != 0 || num < 0)
                    warnx2("%s:%d: bad progress '%s', keeping %ld",
                           cf->conffile, lineno, val, cf->progress);
                else
                    cf->progress = num;
            } else if (strcmp(key, "bufsize") == 0) {
                if (getnum(val, &num) != 0 || num <= 0) {
                    warnx2("%s:%d: bad bufsize '%s', keeping %ld",
                           cf->conffile, lineno, val, cf->bufsize);
                } else {
                    clamped = num;
                    if (clamped < APKG_MIN_BUFSIZE)
                        clamped = APKG_MIN_BUFSIZE;
                    if (clamped > APKG_MAX_BUFSIZE)
                        clamped = APKG_MAX_BUFSIZE;
                    if (clamped != num)
                        warnx2("%s:%d: bufsize %ld clamped to %ld",
                               cf->conffile, lineno, num, clamped);
                    cf->bufsize = clamped;
                }
            } else if (strcmp(key, "rcvbuf") == 0 ||
                       strcmp(key, "sndbuf") == 0) {
                if (getnum(val, &num) != 0 || num < 0 ||
                    num > APKG_MAX_SOCKBUF)
                    warnx2("%s:%d: bad %s '%s', keeping %ld",
                           cf->conffile, lineno, key, val,
                           key[0] == 'r' ? cf->rcvbuf : cf->sndbuf);
                else if (key[0] == 'r')
                    cf->rcvbuf = num;
                else
                    cf->sndbuf = num;
            } else if (strcmp(key, "nameserver") == 0) {
                /* REPEATABLE: each line appends.  An empty value clears
                 * the list -- the only way a later line can undo an
                 * earlier one, and the natural spelling of "this box
                 * uses the hosts file only". */
                if (*val == '\0') {
                    while (cf->nnameservers > 0)
                        free(cf->nameservers[--cf->nnameservers]);
                } else if (cf->nnameservers >= APKG_MAX_NAMESERVERS) {
                    warnx2("%s:%d: more than %d nameserver lines, "
                           "'%s' ignored", cf->conffile, lineno,
                           APKG_MAX_NAMESERVERS, val);
                } else {
                    cf->nameservers = (char **)xrealloc(
                        (char *)cf->nameservers,
                        (unsigned)((cf->nnameservers + 1) * sizeof(char *)));
                    cf->nameservers[cf->nnameservers] = xstrdup(val);
                    cf->nnameservers++;
                }
            } else if (strcmp(key, "dns_timeout") == 0) {
                if (getnum(val, &num) != 0 || num <= 0)
                    warnx2("%s:%d: bad dns_timeout '%s', keeping %ld",
                           cf->conffile, lineno, val, cf->dns_timeout);
                else
                    cf->dns_timeout = num;
            } else if (strcmp(key, "dns_retries") == 0) {
                if (getnum(val, &num) != 0 || num < 0 || num > 100)
                    warnx2("%s:%d: bad dns_retries '%s', keeping %d",
                           cf->conffile, lineno, val, cf->dns_retries);
                else
                    cf->dns_retries = (int)num;
            } else if (strcmp(key, "redirects") == 0) {
                if (getnum(val, &num) != 0 || num < 0 || num > 10)
                    warnx2("%s:%d: bad redirects '%s', keeping %d",
                           cf->conffile, lineno, val, cf->redirects);
                else
                    cf->redirects = (int)num;
            } else {
                warnx2("%s:%d: unknown key '%s', ignored",
                       cf->conffile, lineno, key);
            }
        }
        fclose(fp);
    }

    /* strip one trailing slash off the repo URL */
    if (cf->repo[0] != '\0' && cf->repo[strlen(cf->repo) - 1] == '/')
        cf->repo[strlen(cf->repo) - 1] = '\0';

    /* derived paths */
    cachedir_dir = dirname_of(cf->cachedir);
    cf->catalog = cat2(cachedir_dir, "/catalog");
    free(cachedir_dir);
    /* the installed-state DB lives under BOTH roots: APKG_ROOT (client)
     * then -R (target).  Both empty -> plain /var/sadm/pkg. */
    rootpfx = cat2(cf->root, cf->target);
    cf->sadmpkg = cat2(rootpfx, "/var/sadm/pkg");
    free(rootpfx);

    note("config: repo=%s cachedir=%s catalog=%s target=%s",
         cf->repo, cf->cachedir, cf->catalog,
         cf->target[0] != '\0' ? cf->target : "(none)");
    /* one grep-able line carrying every fetch-path knob in force */
    note("fetch: timeout=%lds connect_timeout=%lds retries=%d "
         "retry_delay=%lds progress=%ld bufsize=%ld redirects=%d "
         "rcvbuf=%ld sndbuf=%ld",
         cf->timeout, cf->conn_timeout, cf->retries, cf->retry_delay,
         cf->progress, cf->bufsize, cf->redirects,
         cf->rcvbuf, cf->sndbuf);
    conf_note_dns(cf);
    return 0;
}

/* The resolver's own grep-able line, beside the fetch one.  It names the
 * servers in the order they will be tried, because "which nameserver
 * answered" is the first question when a box cannot reach the repo, and
 * prints "(none)" rather than an empty field so that hosts-file-only --
 * the default, and what every box did before dns.c existed -- is stated
 * rather than left to be inferred from a blank. */
void conf_note_dns(const struct conf *cf)
{
    char *list;
    unsigned len;
    int i;

    if (!opt_verbose)
        return;
    if (cf->nnameservers <= 0) {
        note("dns: nameserver=(none, hosts file only) dns_timeout=%lds "
             "dns_retries=%d", cf->dns_timeout, cf->dns_retries);
        return;
    }
    len = 1;
    for (i = 0; i < cf->nnameservers; i++)
        len += (unsigned)strlen(cf->nameservers[i]) + 1;
    list = xmalloc(len);
    list[0] = '\0';
    for (i = 0; i < cf->nnameservers; i++) {
        if (i > 0)
            strcat(list, ",");
        strcat(list, cf->nameservers[i]);
    }
    note("dns: nameserver=%s dns_timeout=%lds dns_retries=%d",
         list, cf->dns_timeout, cf->dns_retries);
    free(list);
}

/* Fetch-path options, gathered in one place so they travel together
 * from the config file to the socket.  They live HERE, not in http.c:
 * the install-miniroot variant builds with -DAPKG_NO_HTTP and drops
 * http.c entirely, but source.c still has to fill a struct httpopts. */

void http_opts_default(struct httpopts *o)
{
    o->timeout = APKG_DEF_TIMEOUT;
    o->conn_timeout = APKG_DEF_CONNTIMEO;
    o->retries = APKG_DEF_RETRIES;
    o->retry_delay = APKG_DEF_RETRYDELAY;
    o->progress = APKG_DEF_PROGRESS;
    o->bufsize = APKG_DEF_BUFSIZE;
    o->redirects = APKG_DEF_REDIRECTS;
    o->rcvbuf = APKG_DEF_RCVBUF;
    o->sndbuf = APKG_DEF_SNDBUF;
    o->dns.servers = NULL;
    o->dns.nservers = 0;
    o->dns.timeout = APKG_DEF_DNSTIMEO;
    o->dns.retries = APKG_DEF_DNSRETRIES;
}

void http_opts_from_conf(struct httpopts *o, const struct conf *cf)
{
    o->timeout = cf->timeout;
    o->conn_timeout = cf->conn_timeout;
    o->retries = cf->retries;
    o->retry_delay = cf->retry_delay;
    o->progress = cf->progress;
    o->bufsize = cf->bufsize;
    o->redirects = cf->redirects;
    o->rcvbuf = cf->rcvbuf;
    o->sndbuf = cf->sndbuf;
    /* the array itself stays owned by the struct conf: struct httpopts is
     * copied by value all over the fetch path and must not own memory */
    o->dns.servers = cf->nameservers;
    o->dns.nservers = cf->nnameservers;
    o->dns.timeout = cf->dns_timeout;
    o->dns.retries = cf->dns_retries;
}

/* ---------------- the admin(4) file handed to -a ----------------
 *
 * WHY THIS IS GENERATED RATHER THAN ASSUMED (metal, A4000D/68LC060,
 * 2026-09-16 -- the defect that bricked apkg on the A4000D):
 *
 * The APKG package ships /var/apkg/admin as an `e` (editable) class
 * entry, so the admin file is PACKAGE-OWNED.  `pkgrm APKG` therefore
 * DELETES it -- reproduced host-side with the heirloom engine: after
 * `pkgrm -R <root> APKG` both /var/apkg/admin and the /var/apkg
 * directory were gone.  apkg's old upgrade verb ran `pkgrm APKG` and
 * then `pkgadd -a /var/apkg/admin ...`, so the pkgadd died with
 *
 *     pkgadd: ERROR: unable to open admin file </var/apkg/admin>
 *
 * and the box was left with apkg REMOVED and not reinstalled.  The
 * first read of that message ("admin= is an admin-DB
 * directory, not a file") was a reasonable guess but not the cause:
 * the path is a perfectly good admin file, it had simply just been
 * deleted by the pkgrm two seconds earlier.
 *
 * So the rule is: the admin file is re-materialised immediately
 * before EVERY engine invocation and never merely assumed to exist.
 * An admin file an operator has edited is left exactly as it is (we
 * only create what is missing).
 *
 * The `overwrite` flavour is a second, derived file -- <admin>.overwrite
 * -- carrying instance=overwrite so pkgadd will replace an installed
 * instance of a DIFFERENT version instead of stopping with "Unable to
 * determine whether to overwrite an existing package instance"
 * (pkginstall/getinst.c:97 quits on instance=quit; :153 reuses the
 * installed pkginst on instance=overwrite).  It is DERIVED from the
 * operator's own admin file -- every other key they set is carried
 * across verbatim, only the instance= line is replaced -- so turning
 * on instance=overwrite for an upgrade never silently discards a
 * space=quit or a setuid=quit the operator asked for.
 *
 * Returns an allocated path, or NULL (message printed) when the file
 * cannot be created.  Under -n nothing is written; the path that WOULD
 * be used is returned so the printed plan is the real argv.
 */

/* the built-in body, minus the instance= line that is appended last;
 * byte-identical to the admin file the APKG package ships */
static const char admin_body[] =
    "mail=\n"
    "partial=nocheck\n"
    "runlevel=nocheck\n"
    "idepend=nocheck\n"
    "rdepend=nocheck\n"
    "space=quit\n"
    "setuid=nocheck\n"
    "conflict=nocheck\n"
    "action=nocheck\n"
    "basedir=default\n";

/* true when the line is an "instance = ..." assignment */
static int is_instance_line(const char *line)
{
    const char *p;

    p = line;
    while (*p == ' ' || *p == '\t')
        p++;
    if (strncmp(p, "instance", 8) != 0)
        return 0;
    p += 8;
    while (*p == ' ' || *p == '\t')
        p++;
    return *p == '=';
}

char *conf_adminfile(const struct conf *cf, int overwrite)
{
    char *path;
    char *dir;
    FILE *in;
    FILE *out;
    char line[1024];
    unsigned n;
    int copied;
    int lastnl;

    if (!overwrite) {
        path = xstrdup(cf->admin);
        /* an existing (possibly operator-edited) admin file is used
         * as-is; we only ever create a MISSING one */
        if (file_exists(path))
            return path;
        if (opt_dryrun) {
            note("admin file %s missing; would create it", path);
            return path;
        }
        warnx2("admin file %s missing, creating a default one", path);
    } else {
        path = cat2(cf->admin, ".overwrite");
        if (opt_dryrun)
            return path;
    }

    dir = dirname_of(path);
    if (mkpath(dir) != 0) {
        warnx2("cannot create directory %s for the admin file", dir);
        free(dir);
        free(path);
        return NULL;
    }
    free(dir);

    out = fopen(path, "w");
    if (out == NULL) {
        warnx2("cannot create admin file %s", path);
        free(path);
        return NULL;
    }

    copied = 0;
    lastnl = 1;
    if (overwrite) {
        in = fopen(cf->admin, "r");
        if (in != NULL) {
            while (fgets(line, (int)sizeof(line), in) != NULL) {
                if (is_instance_line(line))
                    continue;
                fputs(line, out);
                n = (unsigned)strlen(line);
                lastnl = (n > 0 && line[n - 1] == '\n');
                copied = 1;
            }
            fclose(in);
        }
    }
    if (!copied) {
        fputs(admin_body, out);
        lastnl = 1;
    }
    if (!lastnl)
        fputc('\n', out);
    fprintf(out, "instance=%s\n", overwrite ? "overwrite" : "quit");

    if (fclose(out) != 0) {
        warnx2("error writing admin file %s", path);
        free(path);
        return NULL;
    }
    note("admin file %s (instance=%s)", path,
         overwrite ? "overwrite" : "quit");
    return path;
}

/* Resolve the pkgadd/pkgrm binary to run.  When the configured path
 * is the built-in default and is not executable, fall back to the
 * stock /usr/sbin one.  Returns an allocated path, or NULL (message
 * printed) when nothing usable exists. */
char *conf_pkgcmd(const struct conf *cf, int is_rm)
{
    const char *want;
    char *fb;
    int is_default;

    want = is_rm ? cf->pkgrm : cf->pkgadd;
    is_default = is_rm ? cf->pkgrm_is_default : cf->pkgadd_is_default;

    if (access(want, X_OK) == 0)
        return xstrdup(want);
    if (is_default) {
        fb = cat2(cf->root, is_rm ? DEF_PKGRM_FB : DEF_PKGADD_FB);
        if (access(fb, X_OK) == 0) {
            note("%s missing, falling back to %s", want, fb);
            return fb;
        }
        warnx2("neither %s nor %s is executable", want, fb);
        free(fb);
        return NULL;
    }
    warnx2("%s (from %s) is not executable", want, cf->conffile);
    return NULL;
}
