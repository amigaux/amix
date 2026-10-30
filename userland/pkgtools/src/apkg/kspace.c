/*
 * kspace.c - kernel space in apkg 0.3: SHA-256 of files, the install
 * records under /var/apkg/kpkg, the pre-flight, and the kbootset trigger.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * The interfaces are agreed contracts of the kernel-modules campaign
 * (kernel/dlm; C2-2 version 5, C2-3 version 6, C2-4 version 2, 2026-10-26),
 * and this file implements apkg's side of them exactly:
 *
 *   C2-2 kernel-space catalog entries and the install record
 *        (docs/contracts/C2-2-kpkg.md).  The record /var/apkg/kpkg/<pkginst>
 *        is apkg's alone; kbootset only reads it (gate 1 compares every
 *        generation member with the `file` line naming it).  One kernel
 *        package per line (§2.1): kspace_replaces().
 *   C2-4 kbootset as a called program (docs/contracts/C2-4-kbootset-cli.md):
 *        five exit statuses, `build` and `commit` as two calls, -R and
 *        --journal.  apkg never writes a boot slice itself.
 *
 * Integrity in 1.1 is the per-package SHA-256 of the catalog; there is
 * no signature (D-3 §13).  The hook of 60 §4 stays: kspace_verify_hook()
 * runs before the block is used and the record carries `verified no`.
 *
 * C89, no snprintf/strdup, block-top declarations (the period toolchain
 * builds this for the box).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <fcntl.h>
#include <time.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "apkg.h"
#include "sha256.h"

#define RECLINE 2048

/* ---------------- SHA-256 of a file ---------------- */

int sha256_file(const char *path, char hexout[65])
{
    static const char hx[] = "0123456789abcdef";
    struct ax_sha256 s;
    unsigned char buf[8192];
    unsigned char d[32];
    FILE *fp;
    unsigned n;
    int i;

    fp = fopen(path, "rb");
    if (fp == NULL)
        return -1;
    ax_sha256_init(&s);
    while ((n = (unsigned)fread(buf, 1, sizeof(buf), fp)) > 0)
        ax_sha256_update(&s, buf, (ax_u32)n);
    if (ferror(fp)) {
        fclose(fp);
        return -1;
    }
    fclose(fp);
    ax_sha256_final(&s, d);
    for (i = 0; i < 32; i++) {
        hexout[2 * i] = hx[d[i] >> 4];
        hexout[2 * i + 1] = hx[d[i] & 15];
    }
    hexout[64] = '\0';
    return 0;
}

/* ---------------- the verification hook (60 §4) ---------------- */

void kspace_verify_hook(struct catalog *cat)
{
    /* 1.1: no signature exists (D-3 §13).  A #ksig line is recorded by
     * catalog_load and not acted on; the verdict is "unverified" and the
     * block passes.  The release that adds signing checks the catalog
     * bytes against the #ksig file HERE and, by policy, refuses. */
    cat->kverified = 0;
    if (cat->nk > 0)
        note("kernel-space block: %d entr%s, unverified (no signature "
             "check in this release)%s%s", cat->nk,
             cat->nk == 1 ? "y" : "ies",
             cat->ksig_key != NULL ? "; #ksig recorded, key " : "",
             cat->ksig_key != NULL ? cat->ksig_key : "");
}

/* ---------------- records ---------------- */

struct krec {
    char name[256];         /* the full name (the file is the pkginst) */
    char version[128];
    char role[16];
    char line[16];
    char kabi[128];
    char pin[256];
    char firstfile[1024];   /* path of the first `file` line */
};

/* The record FILE is named by the package's pkginst -- its pkginst=,
 * else its name -- not by the name (C2-2 v4 §2): an s5 root keeps 14
 * characters of a file name, so "kernel-k46-zacd" and
 * "kernel-k46-zacd.new" collapse into one name and the atomic rename is
 * lost; a pkginst is at most 9 characters and "<pkginst>.new" stays
 * distinct.  The full name is the record's `name` line.  Every function
 * here that takes a `key` takes that file name. */
static char *rec_path(const struct conf *cf, const char *key)
{
    return cat3(cf->kpkgdir, "/", key);
}

static int rec_skip(const char *fname)
{
    unsigned n;

    n = (unsigned)strlen(fname);
    return fname[0] == '.' ||
           (n > 4 && strcmp(fname + n - 4, ".new") == 0);
}

static void copyval(char *dst, unsigned cap, const char *v)
{
    unsigned n;

    n = (unsigned)strlen(v);
    while (n > 0 && (v[n - 1] == '\n' || v[n - 1] == '\r' ||
                     v[n - 1] == ' ' || v[n - 1] == '\t'))
        n--;
    if (n >= cap)
        n = cap - 1;
    memcpy(dst, v, n);
    dst[n] = '\0';
}

/* 0 = read, -1 = no record */
static int rec_read(const struct conf *cf, const char *key, struct krec *r)
{
    char *path;
    FILE *fp;
    char line[RECLINE];
    char *v;
    char *sp;

    memset((char *)r, 0, sizeof(*r));
    if (key[0] == '\0' || strchr(key, '/') != NULL)
        return -1;
    path = rec_path(cf, key);
    fp = fopen(path, "r");
    free(path);
    if (fp == NULL)
        return -1;
    while (fgets(line, (int)sizeof(line), fp) != NULL) {
        v = strchr(line, ' ');
        if (v == NULL)
            continue;
        *v++ = '\0';
        if (strcmp(line, "name") == 0)
            copyval(r->name, sizeof(r->name), v);
        else if (strcmp(line, "version") == 0)
            copyval(r->version, sizeof(r->version), v);
        else if (strcmp(line, "role") == 0)
            copyval(r->role, sizeof(r->role), v);
        else if (strcmp(line, "line") == 0)
            copyval(r->line, sizeof(r->line), v);
        else if (strcmp(line, "kabi") == 0)
            copyval(r->kabi, sizeof(r->kabi), v);
        else if (strcmp(line, "pin") == 0)
            copyval(r->pin, sizeof(r->pin), v);
        else if (strcmp(line, "file") == 0 && r->firstfile[0] == '\0') {
            sp = strchr(v, ' ');
            if (sp != NULL)
                *sp = '\0';
            copyval(r->firstfile, sizeof(r->firstfile), v);
        }
    }
    fclose(fp);
    return 0;
}

int kpkg_installed(const struct conf *cf, const char *key,
                   char *ver, unsigned verlen)
{
    struct krec r;
    unsigned n;

    ver[0] = '\0';
    if (rec_read(cf, key, &r) != 0)
        return 0;
    n = (unsigned)strlen(r.version);
    if (n >= verlen)
        n = verlen - 1;
    memcpy(ver, r.version, n);
    ver[n] = '\0';
    return 1;
}

/* the record of a package given by its name or its pkginst: the file
 * <arg> when there is one, else the record whose `name` line is <arg>;
 * the file name into key.  1 = found, 0 = none */
int kpkg_find(const struct conf *cf, const char *arg, char *key,
              unsigned cap)
{
    struct krec r;
    DIR *d;
    struct dirent *de;
    int found;

    key[0] = '\0';
    found = 0;
    if (!rec_skip(arg) && rec_read(cf, arg, &r) == 0) {
        strncpy(key, arg, cap - 1);
        key[cap - 1] = '\0';
        return 1;
    }
    d = opendir(cf->kpkgdir);
    if (d == NULL)
        return 0;
    while ((de = readdir(d)) != NULL) {
        if (rec_skip(de->d_name) || rec_read(cf, de->d_name, &r) != 0)
            continue;
        if (strcmp(r.name, arg) == 0) {
            strncpy(key, de->d_name, cap - 1);
            key[cap - 1] = '\0';
            found = 1;
            break;
        }
    }
    closedir(d);
    return found;
}

int kpkg_remove_record(const struct conf *cf, const char *key)
{
    char *path;
    int rc;

    path = rec_path(cf, key);
    if (opt_dryrun) {
        printf("would remove the record %s\n", path);
        free(path);
        return 0;
    }
    rc = unlink(path);
    if (rc != 0 && file_exists(path)) {
        warnx2("cannot remove the record %s", path);
        free(path);
        return -1;
    }
    free(path);
    return 0;
}

/* ---------------- the datastream header ----------------
 *
 * A datastream begins
 *     # PaCkAgE DaTaStReAm
 *     <pkginst> <parts> <maxsize> [...]      (one line per package)
 *     # end of header
 * A kernel-space package is exactly one instance.
 */
int ds_pkginst(const char *path, char *out, unsigned outlen)
{
    FILE *fp;
    char line[512];
    char *p;
    unsigned n;
    int npkg;

    out[0] = '\0';
    fp = fopen(path, "rb");
    if (fp == NULL)
        return -1;
    if (fgets(line, (int)sizeof(line), fp) == NULL ||
        strncmp(line, "# PaCkAgE DaTaStReAm", 20) != 0) {
        fclose(fp);
        return -1;
    }
    npkg = 0;
    while (fgets(line, (int)sizeof(line), fp) != NULL) {
        if (strncmp(line, "# end of header", 15) == 0)
            break;
        p = line;
        n = 0;
        while (p[n] != '\0' && p[n] != ' ' && p[n] != '\t' &&
               p[n] != '\n')
            n++;
        if (n == 0)
            continue;
        npkg++;
        if (npkg == 1) {
            if (n >= outlen)
                n = outlen - 1;
            memcpy(out, p, n);
            out[n] = '\0';
        }
    }
    fclose(fp);
    return npkg == 1 ? 0 : -1;
}

/* ---------------- pure files (40 §6) ----------------
 *
 * "Kernel-space packages carry files only (class none, no scripts) and
 * never write a boot slice."  apkg checks it on the staged datastream,
 * before anything is installed, from the package's own pkgmap(4) (the
 * first cpio archive, newc or odc):
 *   f  allowed in class none only -- the payload;
 *   d  allowed in class none only -- the directories holding it (pkgadd
 *      needs them named to give them owner and mode);
 *   i  pkginfo, depend and copyright only -- no install or class-action
 *      scripts;
 *   c  in a module package only (C3-5 v4 section 1.2: the driver's
 *      device nodes ship as pkgmap entries, no script), class none, under
 *      /dev/, all of "c none <path> <major> <minor> <mode> <owner>
 *      <group>" with decimal major and minor and an octal mode; pkgadd
 *      makes the node (heirloom pkginstall/instvol.c -> libpkg/verify.c
 *      averify() mknod) and records it in the contents database;
 *   b  the same, a block driver's nodes (C3-5 v8 section 1.2), under
 *      /dev/dsk/ only (the ramdisk: /dev/dsk/ram0 b 20 0);
 *   anything else (e, v, l, s, p, x; c or b in a kernel or loader
 *      package) refuses the package.
 * At least one f is required.
 */

static unsigned long hexval(const char *p, int n)
{
    unsigned long v;
    int i;
    int c;

    v = 0;
    for (i = 0; i < n; i++) {
        c = p[i];
        if (c >= '0' && c <= '9')
            c -= '0';
        else if (c >= 'a' && c <= 'f')
            c = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
            c = c - 'A' + 10;
        else
            return (unsigned long)-1;
        v = v * 16 + (unsigned long)c;
    }
    return v;
}

static unsigned long octval(const char *p, int n)
{
    unsigned long v;
    int i;

    v = 0;
    for (i = 0; i < n; i++) {
        if (p[i] < '0' || p[i] > '7')
            return (unsigned long)-1;
        v = v * 8 + (unsigned long)(p[i] - '0');
    }
    return v;
}

static void setwhy(char *why, unsigned cap, const char *a, const char *b)
{
    unsigned n;

    n = 0;
    while (*a != '\0' && n + 1 < cap)
        why[n++] = *a++;
    while (b != NULL && *b != '\0' && n + 1 < cap)
        why[n++] = *b++;
    why[n] = '\0';
}

static int all_in(const char *s, const char *set)
{
    if (*s == '\0')
        return 0;
    for (; *s != '\0'; s++)
        if (strchr(set, *s) == NULL)
            return 0;
    return 1;
}

/* one module's c or b entry (tok[0..nt-1]); 0 = acceptable, -1 = not
 * (why).  c: under /dev/; b: under /dev/dsk/ (C3-5 v8 section 1.2) */
static int cdev_ok(char **tok, int nt, char *why, unsigned cap)
{
    if (nt < 4) {
        setwhy(why, cap, "unreadable pkgmap line ", tok[0]);
        return -1;
    }
    if (strcmp(tok[2], "none") != 0) {
        setwhy(why, cap, "an object in class ", tok[2]);
        return -1;
    }
    if (tok[1][0] == 'b') {
        if (strncmp(tok[3], "/dev/dsk/", 9) != 0 || tok[3][9] == '\0') {
            setwhy(why, cap, "a block device node outside /dev/dsk/: ",
                   tok[3]);
            return -1;
        }
    } else if (strncmp(tok[3], "/dev/", 5) != 0 || tok[3][5] == '\0') {
        setwhy(why, cap, "a device node outside /dev/: ", tok[3]);
        return -1;
    }
    if (nt != 9 || !all_in(tok[4], "0123456789") ||
        !all_in(tok[5], "0123456789") || !all_in(tok[6], "01234567")) {
        setwhy(why, cap, "a device entry not of the form "
               "<major> <minor> <mode> <owner> <group>: ", tok[3]);
        return -1;
    }
    return 0;
}

/* the pkgmap rule above; module: c and b entries allowed.  0 = pure, -1 = not
 * (why set) */
static int pkgmap_pure(char *text, int module, char *why, unsigned cap)
{
    char *line;
    char *next;
    char *tok[10];
    char *p;
    int nt;
    int nf;

    nf = 0;
    for (line = text; line != NULL && *line != '\0'; line = next) {
        next = strchr(line, '\n');
        if (next != NULL)
            *next++ = '\0';
        nt = 0;
        p = line;
        while (nt < 10) {
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
        if (nt < 3 || tok[1][1] != '\0') {
            setwhy(why, cap, "unreadable pkgmap line ", tok[0]);
            return -1;
        }
        switch (tok[1][0]) {
        case 'i':
            if (strcmp(tok[2], "pkginfo") != 0 &&
                strcmp(tok[2], "depend") != 0 &&
                strcmp(tok[2], "copyright") != 0) {
                setwhy(why, cap, "it carries an install script: ", tok[2]);
                return -1;
            }
            break;
        case 'f':
        case 'd':
            if (strcmp(tok[2], "none") != 0) {
                setwhy(why, cap, "an object in class ", tok[2]);
                return -1;
            }
            if (nt < 4) {
                setwhy(why, cap, "unreadable pkgmap line ", tok[0]);
                return -1;
            }
            if (tok[1][0] == 'f')
                nf++;
            break;
        case 'c':
        case 'b':
            if (module) {
                if (cdev_ok(tok, nt, why, cap) != 0)
                    return -1;
                break;
            }
            /* FALLTHROUGH - no device nodes in a kernel or loader */
        default:
            setwhy(why, cap, "an object of type ", tok[1]);
            if (nt >= 4) {
                unsigned n;

                n = (unsigned)strlen(why);
                setwhy(why + n, cap - n, " at ", tok[3]);
            }
            return -1;
        }
    }
    if (nf == 0) {
        setwhy(why, cap, "it installs no file", NULL);
        return -1;
    }
    return 0;
}

/* The member <pkginst>/<member> (or a bare <member>) of the datastream's
 * first cpio archive (newc or odc), read whole into a NUL-terminated
 * buffer *text (xmalloc'd; the caller frees it).  0 = read, -1 = not
 * (why[] says: not a datastream, no such member, truncated, ...). */
int ds_member(const char *path, const char *member, char **text,
              char *why, unsigned cap)
{
    FILE *fp;
    char hdr[8193];
    char name[256];
    char *buf;
    unsigned long off;
    unsigned long fsz;
    unsigned long nsz;
    unsigned long dataoff;
    unsigned mlen;
    unsigned n;
    unsigned i;
    int odc;
    int rc;

    why[0] = '\0';
    *text = NULL;
    mlen = (unsigned)strlen(member);
    fp = fopen(path, "rb");
    if (fp == NULL) {
        setwhy(why, cap, "cannot read the datastream", NULL);
        return -1;
    }
    n = (unsigned)fread(hdr, 1, sizeof(hdr) - 1, fp);
    hdr[n] = '\0';
    if (n < 21 || strncmp(hdr, "# PaCkAgE DaTaStReAm\n", 21) != 0) {
        fclose(fp);
        setwhy(why, cap, "not a datastream", NULL);
        return -1;
    }
    off = 0;
    for (i = 0; i + 16 <= n; i++) {
        if (memcmp(hdr + i, "# end of header\n", 16) == 0) {
            off = (i + 16 + 511UL) & ~511UL;
            break;
        }
    }
    if (off == 0) {
        fclose(fp);
        setwhy(why, cap, "datastream header has no end", NULL);
        return -1;
    }
    rc = -1;
    setwhy(why, cap, "no ", member);
    n = (unsigned)strlen(why);
    setwhy(why + n, cap - n, " in the first archive", NULL);
    for (;;) {
        if (fseek(fp, (long)off, SEEK_SET) != 0 ||
            fread(hdr, 1, 110, fp) < 76) {
            setwhy(why, cap, "truncated cpio archive", NULL);
            break;
        }
        if (strncmp(hdr, "070701", 6) == 0 ||
            strncmp(hdr, "070702", 6) == 0) {
            odc = 0;
            fsz = hexval(hdr + 54, 8);
            nsz = hexval(hdr + 94, 8);
        } else if (strncmp(hdr, "070707", 6) == 0) {
            odc = 1;
            nsz = octval(hdr + 59, 6);
            fsz = octval(hdr + 65, 11);
        } else {
            setwhy(why, cap, "not a cpio archive after the header", NULL);
            break;
        }
        if (nsz == (unsigned long)-1 || fsz == (unsigned long)-1 ||
            nsz == 0 || nsz > sizeof(name)) {
            setwhy(why, cap, "bad cpio header", NULL);
            break;
        }
        if (fseek(fp, (long)(off + (odc ? 76 : 110)), SEEK_SET) != 0 ||
            fread(name, 1, (unsigned)nsz, fp) != (unsigned)nsz) {
            setwhy(why, cap, "truncated cpio name", NULL);
            break;
        }
        name[nsz - 1] = '\0';
        dataoff = off + (odc ? 76 : 110) + nsz;
        if (!odc)
            dataoff = (dataoff + 3) & ~3UL;
        if (strcmp(name, "TRAILER!!!") == 0)
            break;
        n = (unsigned)strlen(name);
        if ((n == mlen && strcmp(name, member) == 0) ||
            (n > mlen + 1 && strcmp(name + n - mlen, member) == 0 &&
             strchr(name, '/') == name + n - mlen - 1)) {
            if (fsz > 1048576UL) {
                setwhy(why, cap, member, " too large");
                break;
            }
            buf = xmalloc((unsigned)fsz + 1);
            if (fseek(fp, (long)dataoff, SEEK_SET) != 0 ||
                fread(buf, 1, (unsigned)fsz, fp) != (unsigned)fsz) {
                free(buf);
                setwhy(why, cap, "truncated ", member);
                break;
            }
            buf[fsz] = '\0';
            *text = buf;
            why[0] = '\0';
            rc = 0;
            break;
        }
        off = dataoff + fsz;
        if (!odc)
            off = (off + 3) & ~3UL;
    }
    fclose(fp);
    return rc;
}

int ds_pure_files(const char *path, int module, char *why, unsigned cap)
{
    char *text;
    int rc;

    if (ds_member(path, "pkgmap", &text, why, cap) != 0)
        return -1;
    rc = pkgmap_pure(text, module, why, cap);
    free(text);
    return rc;
}

/* ---------------- the contents database ----------------
 *
 * SVR4 contents lines (heirloom libpkg/putcfile.c):
 *   path[=target] [volno] type class ...  then the packages, each as
 *   [status]pkginst[\][:class]
 * f/e/v: path type class mode owner group size cksum modtime pkgs...
 * The paths are as the target root sees them (pkgadd -R strips the root).
 */

/* the bare pkginst of one package token */
static void pkg_token(const char *tok, char *out, unsigned cap)
{
    unsigned n;

    while (*tok != '\0' && !isalnum((unsigned char)*tok))
        tok++;                      /* status: + - * ! % @ ~ ... */
    n = 0;
    while (tok[n] != '\0' && tok[n] != '\\' && tok[n] != ':')
        n++;
    if (n >= cap)
        n = cap - 1;
    memcpy(out, tok, n);
    out[n] = '\0';
}

typedef int (*cont_cb)(void *ctx, const char *path, int type,
                       char **pkgs, int npkgs);

/* walk the target's contents DB; cb returns nonzero to stop.  0 ok /
 * -1 unreadable */
static int contents_walk(const struct conf *cf, cont_cb cb, void *ctx)
{
    FILE *fp;
    char *line;
    char *tok[256];
    char *p;
    int nt;
    int t;
    int first;
    unsigned len;

    fp = fopen(cf->contents, "r");
    if (fp == NULL)
        return -1;
    line = xmalloc(8192);
    while (fgets(line, 8192, fp) != NULL) {
        len = (unsigned)strlen(line);
        if (len > 0 && line[len - 1] != '\n' && !feof(fp)) {
            int c;

            while ((c = getc(fp)) != EOF && c != '\n')
                ;            /* overlong line: no package of ours */
            continue;
        }
        if (line[0] == '#' || line[0] == '\n')
            continue;
        nt = 0;
        p = line;
        for (;;) {
            while (*p == ' ' || *p == '\t' || *p == '\n')
                p++;
            if (*p == '\0' || nt == 256)
                break;
            tok[nt++] = p;
            while (*p != '\0' && *p != ' ' && *p != '\t' && *p != '\n')
                p++;
            if (*p != '\0')
                *p++ = '\0';
        }
        if (nt < 3)
            continue;
        t = 1;
        if (isdigit((unsigned char)tok[1][0]))
            t = 2;                   /* volume number */
        if (t >= nt || tok[t][1] != '\0')
            continue;
        switch (tok[t][0]) {
        case 'f': case 'e': case 'v':
            first = t + 8;
            break;
        case 'c': case 'b':     /* class major minor mode owner group */
            first = t + 7;
            break;
        case 'd': case 'x': case 'p':
            first = t + 5;
            break;
        default:                     /* l, s */
            first = t + 2;
            break;
        }
        if (first >= nt)
            continue;
        if (cb(ctx, tok[0], tok[t][0], tok + first, nt - first) != 0)
            break;
    }
    free(line);
    fclose(fp);
    return 0;
}

static int owns(char **pkgs, int npkgs, const char *pkginst)
{
    char b[64];
    int i;

    for (i = 0; i < npkgs; i++) {
        pkg_token(pkgs[i], b, sizeof(b));
        if (strcmp(b, pkginst) == 0)
            return 1;
    }
    return 0;
}

struct files_ctx {
    const char *pkginst;
    char **paths;
    int n;
};

static int collect_files(void *vctx, const char *path, int type,
                         char **pkgs, int npkgs)
{
    struct files_ctx *c;

    c = (struct files_ctx *)vctx;
    /* plain files only: a kernel-space package is pure files (40 §6),
     * which ds_pure_files() checked before the pkgadd.  A module's device
     * node (C3-5 v4 §1.2) has no bytes to hash, so it gets no `file` line
     * (C2-2 §2: a file's size and SHA-256; kbootset gate 1 compares
     * generation members, which are files): pkgadd records the node in
     * the contents database and pkgrm removes it from there */
    if (type == 'f' && owns(pkgs, npkgs, c->pkginst)) {
        c->paths = (char **)xrealloc((char *)c->paths,
            (unsigned)((c->n + 1) * sizeof(char *)));
        c->paths[c->n++] = xstrdup(path);
    }
    return 0;
}

struct owner_ctx {
    const char *path;
    char *out;
    unsigned cap;
    int found;
};

static int find_owner(void *vctx, const char *path, int type,
                      char **pkgs, int npkgs)
{
    struct owner_ctx *c;

    (void)type;
    c = (struct owner_ctx *)vctx;
    if (strcmp(path, c->path) != 0 || npkgs < 1)
        return 0;
    pkg_token(pkgs[0], c->out, c->cap);
    c->found = 1;
    return 1;
}

int kpkg_owner(const struct conf *cf, const char *key,
               char *pkginst, unsigned len)
{
    struct krec r;
    struct owner_ctx c;

    pkginst[0] = '\0';
    if (rec_read(cf, key, &r) != 0 || r.firstfile[0] == '\0')
        return -1;
    c.path = r.firstfile;
    c.out = pkginst;
    c.cap = len;
    c.found = 0;
    if (contents_walk(cf, find_owner, &c) != 0 || !c.found)
        return -1;
    return 0;
}

/* ---------------- writing a record (C2-2 v4 §2) ---------------- */

int kpkg_write_record_fields(const struct conf *cf,
    const char *key, const char *name, const char *version, const char *role,
    const char *line, const char *kabi, const char *pin,
    const char *loaderv, const char *sha256, const char *pkginst,
    const char *source)
{
    struct files_ctx c;
    char *path;
    char *tmp;
    char *full;
    char hex[65];
    FILE *fp;
    long sz;
    int i;
    int rc;

    path = rec_path(cf, key);
    if (opt_dryrun) {
        printf("would write the record %s\n", path);
        free(path);
        return EX_OK;
    }
    c.pkginst = pkginst;
    c.paths = NULL;
    c.n = 0;
    if (contents_walk(cf, collect_files, &c) != 0) {
        warnx2("cannot read the contents database %s", cf->contents);
        free(path);
        return EX_PKGCMD;
    }
    if (c.n == 0) {
        warnx2("the contents database lists no file of %s (%s); "
               "no record written", pkginst, name);
        free(path);
        return EX_PKGCMD;
    }
    if (mkpath(cf->kpkgdir) != 0) {
        warnx2("cannot create %s", cf->kpkgdir);
        rc = EX_USAGE;
        goto out;
    }
    tmp = cat2(path, ".new");
    fp = fopen(tmp, "w");
    if (fp == NULL) {
        warnx2("cannot write %s", tmp);
        free(tmp);
        rc = EX_USAGE;
        goto out;
    }
    fprintf(fp, "name %s\n", name);
    fprintf(fp, "version %s\n", version);
    fprintf(fp, "role %s\n", role);
    fprintf(fp, "line %s\n", line);
    /* C2-2 v4 §2: kabi and pin for a kernel or module, loader for the
     * loader -- never both */
    if (strcmp(role, "loader") == 0) {
        fprintf(fp, "loader %s\n", loaderv);
    } else {
        fprintf(fp, "kabi %s\n", kabi);
        fprintf(fp, "pin %s\n", pin);
    }
    fprintf(fp, "sha256 %s\n", sha256);
    fprintf(fp, "source %s\n", source);
    fprintf(fp, "installed %ld\n", (long)time((time_t *)0));
    fprintf(fp, "verified no\n");
    rc = EX_OK;
    for (i = 0; i < c.n; i++) {
        full = cat3(cf->root, cf->target, c.paths[i]);
        sz = file_size(full);
        if (sz < 0 || sha256_file(full, hex) != 0) {
            warnx2("cannot read installed file %s", full);
            free(full);
            rc = EX_PKGCMD;
            break;
        }
        free(full);
        fprintf(fp, "file %s %ld %s\n", c.paths[i], sz, hex);
    }
    if (fclose(fp) != 0 && rc == EX_OK) {
        warnx2("error writing %s", tmp);
        rc = EX_USAGE;
    }
    if (rc == EX_OK && rename(tmp, path) != 0) {
        warnx2("cannot rename %s to %s", tmp, path);
        rc = EX_USAGE;
    }
    if (rc != EX_OK)
        unlink(tmp);
    else
        note("record %s: %d file%s", path, c.n, c.n == 1 ? "" : "s");
    free(tmp);
out:
    for (i = 0; i < c.n; i++)
        free(c.paths[i]);
    if (c.paths != NULL)
        free((char *)c.paths);
    free(path);
    return rc;
}

int kpkg_write_record(const struct conf *cf, const struct pkgent *e,
                      const char *pkginst, const char *source)
{
    return kpkg_write_record_fields(cf, e->pkginst, e->name, e->version,
                                    e->role,
                                    e->kline, e->kabi, e->pin, e->loaderv,
                                    e->sha256, pkginst, source);
}

/* ---------------- pre-flight (40 §6, 20 §3) ---------------- */

/* "<fam>.<major>.<minor>" -> 0, or -1 when the tag is not of that form
 * (a stage-2 static kernel says "static", a loader may say anything) */
static int kabi_parse(const char *tag, char *fam, unsigned famcap,
                      long *maj, long *min)
{
    const char *d1;
    const char *d2;
    const char *p;
    unsigned n;

    d1 = strchr(tag, '.');
    if (d1 == NULL)
        return -1;
    d2 = strchr(d1 + 1, '.');
    if (d2 == NULL || strchr(d2 + 1, '.') != NULL)
        return -1;
    for (p = d1 + 1; p < d2; p++)
        if (!isdigit((unsigned char)*p))
            return -1;
    for (p = d2 + 1; *p != '\0'; p++)
        if (!isdigit((unsigned char)*p))
            return -1;
    if (d2 == d1 + 1 || d2[1] == '\0')
        return -1;
    n = (unsigned)(d1 - tag);
    if (n == 0 || n >= famcap)
        return -1;
    memcpy(fam, tag, n);
    fam[n] = '\0';
    *maj = atol(d1 + 1);
    *min = atol(d2 + 1);
    return 0;
}

/* one module against one kernel; 0 fits, -1 refused (message printed) */
static int module_fits(const char *mname, const char *mline,
                       const char *mkabi, const char *mpin,
                       const char *kname, const char *kkabi,
                       const char *kpin)
{
    char mf[32], kf[32];
    long mmaj, mmin, kmaj, kmin;

    if (kabi_parse(kkabi, kf, sizeof(kf), &kmaj, &kmin) != 0 || kmaj == 0) {
        warnx2("%s: the kernel %s (kabi %s) is static and takes no "
               "modules", mname, kname, kkabi);
        return -1;
    }
    if (kabi_parse(mkabi, mf, sizeof(mf), &mmaj, &mmin) != 0) {
        warnx2("%s: kabi '%s' is not <family>.<major>.<minor>", mname,
               mkabi);
        return -1;
    }
    if (strcmp(mf, mline) != 0 || strcmp(mf, kf) != 0 || mmaj != kmaj) {
        warnx2("%s: kabi %s does not match the kernel %s (kabi %s)",
               mname, mkabi, kname, kkabi);
        return -1;
    }
    if (mmin > kmin) {
        warnx2("%s: kabi %s needs a newer kernel than %s (kabi %s)",
               mname, mkabi, kname, kkabi);
        return -1;
    }
    if (strcmp(mpin, kpin) != 0) {
        warnx2("%s: compiler pin %s differs from the kernel %s's (%s)",
               mname, mpin, kname, kpin);
        return -1;
    }
    return 0;
}

static int in_todo(struct pkgent **todo, int nt, const char *name)
{
    int i;

    for (i = 0; i < nt; i++)
        if (strcmp(todo[i]->name, name) == 0)
            return 1;
    return 0;
}

/* the installed kernel record of a line: name into kname, 0 / -1 */
static int installed_kernel(const struct conf *cf, const char *line,
                            char *kname, unsigned cap, struct krec *kr)
{
    DIR *d;
    struct dirent *de;
    unsigned n;
    int found;

    found = 0;
    d = opendir(cf->kpkgdir);
    if (d == NULL)
        return -1;
    while ((de = readdir(d)) != NULL) {
        if (rec_skip(de->d_name) || rec_read(cf, de->d_name, kr) != 0)
            continue;
        if (strcmp(kr->role, "kernel") == 0 && strcmp(kr->line, line) == 0) {
            /* the full name from the record (the file is the pkginst) */
            n = (unsigned)strlen(kr->name[0] != '\0' ? kr->name :
                                 de->d_name);
            if (n >= cap)
                n = cap - 1;
            memcpy(kname, kr->name[0] != '\0' ? kr->name : de->d_name, n);
            kname[n] = '\0';
            found = 1;
            break;
        }
    }
    closedir(d);
    return found ? 0 : -1;
}

int kspace_preflight(const struct conf *cf, struct pkgent **todo, int nt)
{
    struct pkgent *k;
    struct krec kr;
    struct krec mr;
    char fam[32];
    char kname[256];
    long maj, min;
    DIR *d;
    struct dirent *de;
    const char *mname;
    int i, j;
    int bad;

    bad = 0;
    for (i = 0; i < nt; i++) {
        if (!todo[i]->kspace)
            continue;
        if (todo[i]->refused != NULL) {
            warnx2("%s: the catalog entry is refused: %s", todo[i]->name,
                   todo[i]->refused);
            return EX_VERIFY;
        }
        /* the loader has no kabi and serves both lines (C2-2 v3 §1.1) */
        if (strcmp(todo[i]->role, "loader") == 0)
            continue;
        /* a tag naming a family must name the entry's own line */
        if (kabi_parse(todo[i]->kabi, fam, sizeof(fam), &maj, &min) == 0 &&
            strcmp(fam, todo[i]->kline) != 0) {
            warnx2("%s: kabi %s is not of its line %s", todo[i]->name,
                   todo[i]->kabi, todo[i]->kline);
            bad = 1;
        }
    }
    if (bad)
        return EX_DEPS;

    /* every module against the kernel of its line: the one in this
     * transaction, else the installed one */
    for (i = 0; i < nt; i++) {
        if (!todo[i]->kspace || strcmp(todo[i]->role, "module") != 0)
            continue;
        k = NULL;
        for (j = 0; j < nt; j++)
            if (todo[j]->kspace && strcmp(todo[j]->role, "kernel") == 0 &&
                strcmp(todo[j]->kline, todo[i]->kline) == 0)
                k = todo[j];
        if (k != NULL) {
            if (module_fits(todo[i]->name, todo[i]->kline, todo[i]->kabi,
                            todo[i]->pin, k->name, k->kabi, k->pin) != 0)
                bad = 1;
        } else if (installed_kernel(cf, todo[i]->kline, kname,
                                    sizeof(kname), &kr) == 0) {
            if (module_fits(todo[i]->name, todo[i]->kline, todo[i]->kabi,
                            todo[i]->pin, kname, kr.kabi, kr.pin) != 0)
                bad = 1;
        } else {
            warnx2("%s: no kernel of line %s is installed or in this "
                   "transaction", todo[i]->name, todo[i]->kline);
            bad = 1;
        }
    }

    /* a new kernel against the installed modules of its line that this
     * transaction does not replace: they must follow it (-f does not
     * override; a kernel without its modules may not boot) */
    for (i = 0; i < nt; i++) {
        if (!todo[i]->kspace || strcmp(todo[i]->role, "kernel") != 0)
            continue;
        d = opendir(cf->kpkgdir);
        if (d == NULL)
            continue;
        while ((de = readdir(d)) != NULL) {
            if (rec_skip(de->d_name) ||
                rec_read(cf, de->d_name, &mr) != 0 ||
                strcmp(mr.role, "module") != 0 ||
                strcmp(mr.line, todo[i]->kline) != 0)
                continue;
            mname = mr.name[0] != '\0' ? mr.name : de->d_name;
            if (in_todo(todo, nt, mname))
                continue;
            /* C2-2 v5 §2.1: going back to a static kernel needs the
             * module packages removed first */
            if (kabi_parse(todo[i]->kabi, fam, sizeof(fam), &maj, &min) != 0
                || maj == 0) {
                warnx2("%s: built for kabi %s, the new kernel %s is static: "
                       "remove the module packages first", mname, mr.kabi,
                       todo[i]->name);
                bad = 1;
                continue;
            }
            if (module_fits(mname, mr.line, mr.kabi, mr.pin,
                            todo[i]->name, todo[i]->kabi,
                            todo[i]->pin) != 0) {
                warnx2("the installed module %s must be upgraded or "
                       "removed with the kernel %s", mname,
                       todo[i]->name);
                bad = 1;
            }
        }
        closedir(d);
    }
    return bad ? EX_DEPS : EX_OK;
}

/* ---------------- one kernel package per line (C2-2 v5 §2.1) ----------
 *
 * Every kernel package of a line installs the same paths
 * (/stand/<line>/unix, kabi, on k30 unix.sym): a static family's and the
 * module kernel's alike.  Two kernel records of one line would name one
 * path twice, which kbootset's gate 1 refuses.  So a transaction that
 * installs a role=kernel package replaces the kernel package recorded
 * under another pkginst on the same line: install.c removes it (pkgrm,
 * then its record) before the new pkgadd, because a pkgadd over another
 * package's file is a conflict, in the same journal.  The same pkginst is
 * an upgrade, as before.
 */

/* the kernel records of a line, file names sorted; returns the count */
static int kernel_records(const struct conf *cf, const char *line,
                          char ***keys)
{
    DIR *d;
    struct dirent *de;
    struct krec r;
    char **v;
    char *t;
    int n;
    int i, j;

    v = NULL;
    n = 0;
    d = opendir(cf->kpkgdir);
    if (d != NULL) {
        while ((de = readdir(d)) != NULL) {
            if (rec_skip(de->d_name) || rec_read(cf, de->d_name, &r) != 0 ||
                strcmp(r.role, "kernel") != 0 || strcmp(r.line, line) != 0)
                continue;
            v = (char **)xrealloc((char *)v,
                                  (unsigned)((n + 1) * sizeof(char *)));
            v[n++] = xstrdup(de->d_name);
        }
        closedir(d);
    }
    for (i = 1; i < n; i++)
        for (j = i; j > 0 && strcmp(v[j - 1], v[j]) > 0; j--) {
            t = v[j];
            v[j] = v[j - 1];
            v[j - 1] = t;
        }
    *keys = v;
    return n;
}

static void free_keys(char **v, int n)
{
    int i;

    for (i = 0; i < n; i++)
        free(v[i]);
    if (v != NULL)
        free((char *)v);
}

static void copystr(char *dst, unsigned cap, const char *src)
{
    unsigned n;

    n = (unsigned)strlen(src);
    if (n >= cap)
        n = cap - 1;
    memcpy(dst, src, n);
    dst[n] = '\0';
}

int kspace_replaces(const struct conf *cf, struct pkgent **todo, int nt,
                    struct kreplace **rep, int *nrep)
{
    struct pkgent *k;
    struct kreplace *x;
    struct krec r;
    char **keys;
    char *list;
    char *t;
    int nk;
    int i, j;

    *rep = NULL;
    *nrep = 0;
    /* the transaction itself carries one kernel per line */
    for (i = 0; i < nt; i++) {
        if (!todo[i]->kspace || strcmp(todo[i]->role, "kernel") != 0)
            continue;
        for (j = i + 1; j < nt; j++)
            if (todo[j]->kspace && strcmp(todo[j]->role, "kernel") == 0 &&
                strcmp(todo[j]->kline, todo[i]->kline) == 0) {
                warnx2("two kernel packages for line %s in this transaction "
                       "(%s, %s): install one", todo[i]->kline,
                       todo[i]->name, todo[j]->name);
                return EX_DEPS;
            }
    }
    /* every line the transaction installs a kernel or a module for */
    for (i = 0; i < nt; i++) {
        if (!todo[i]->kspace || strcmp(todo[i]->role, "loader") == 0)
            continue;
        for (j = 0; j < i; j++)
            if (todo[j]->kspace && strcmp(todo[j]->role, "loader") != 0 &&
                strcmp(todo[j]->kline, todo[i]->kline) == 0)
                break;
        if (j < i)
            continue;                         /* line already seen */
        nk = kernel_records(cf, todo[i]->kline, &keys);
        if (nk >= 2) {
            /* a box damaged by hand: which kernel is installed is unknown */
            list = xstrdup(keys[0]);
            for (j = 1; j < nk; j++) {
                t = cat3(list, ", ", keys[j]);
                free(list);
                list = t;
            }
            if (nk == 2)
                warnx2("two kernel records for line %s (%s): remove one",
                       todo[i]->kline, list);
            else
                warnx2("%d kernel records for line %s (%s): remove all but "
                       "one", nk, todo[i]->kline, list);
            free(list);
            free_keys(keys, nk);
            if (*rep != NULL)
                free((char *)*rep);
            *rep = NULL;
            *nrep = 0;
            return EX_DEPS;
        }
        k = NULL;
        for (j = 0; j < nt; j++)
            if (todo[j]->kspace && strcmp(todo[j]->role, "kernel") == 0 &&
                strcmp(todo[j]->kline, todo[i]->kline) == 0)
                k = todo[j];
        /* the record of the new kernel's own pkginst is an upgrade */
        if (nk == 1 && k != NULL && strcmp(keys[0], k->pkginst) != 0 &&
            rec_read(cf, keys[0], &r) == 0) {
            *rep = (struct kreplace *)xrealloc((char *)*rep,
                (unsigned)((*nrep + 1) * sizeof(struct kreplace)));
            x = &(*rep)[(*nrep)++];
            copystr(x->key, sizeof(x->key), keys[0]);
            copystr(x->name, sizeof(x->name),
                    r.name[0] != '\0' ? r.name : keys[0]);
            copystr(x->line, sizeof(x->line), todo[i]->kline);
            if (kpkg_owner(cf, keys[0], x->pkginst, sizeof(x->pkginst)) != 0)
                copystr(x->pkginst, sizeof(x->pkginst), keys[0]);
            printf("%s replaces %s (%s): one kernel package per line\n",
                   k->name, x->name, x->pkginst);
        }
        free_keys(keys, nk);
    }
    return EX_OK;
}

/* ---------------- the kbootset trigger (C2-4) ---------------- */

/* bootset= from <target>/etc/default/bootset (40 §2.2): 1 = auto (also
 * when the file or the key is absent: the default), 0 = manual.  An
 * unknown value is taken as manual -- never write a boot store on a
 * setting we cannot read. */
static int bootset_auto(const struct conf *cf)
{
    FILE *fp;
    char line[256];
    char *p;
    char *v;
    int mode;

    fp = fopen(cf->bootsetconf, "r");
    if (fp == NULL)
        return 1;
    mode = 1;
    while (fgets(line, (int)sizeof(line), fp) != NULL) {
        p = line;
        while (*p == ' ' || *p == '\t')
            p++;
        if (strncmp(p, "bootset", 7) != 0)
            continue;
        v = p + 7;
        while (*v == ' ' || *v == '\t')
            v++;
        if (*v != '=')
            continue;
        v++;
        while (*v == ' ' || *v == '\t' || *v == '"')
            v++;
        if (strncmp(v, "auto", 4) == 0)
            mode = 1;
        else if (strncmp(v, "manual", 6) == 0)
            mode = 0;
        else {
            warnx2("%s: unknown bootset value, taken as manual",
                   cf->bootsetconf);
            mode = 0;
        }
    }
    fclose(fp);
    return mode;
}

/* the argv of one kbootset call: kbootset [-R t] --journal J <cmd>;
 * returns the index of <cmd> */
static int kb_argv(const struct conf *cf, const char *cmd, char **argv,
                    char **journal)
{
    int a;

    if (cf->kbootset_journal[0] != '\0')
        *journal = xstrdup(cf->kbootset_journal);
    else
        *journal = cat2(cf->target, "/var/kbootset/journal");
    a = 0;
    argv[a++] = cf->kbootset;
    if (cf->target[0] != '\0') {
        argv[a++] = (char *)"-R";
        argv[a++] = cf->target;
    }
    argv[a++] = (char *)"--journal";
    argv[a++] = *journal;
    argv[a] = (char *)cmd;
    argv[a + 1] = NULL;
    return a;
}

static void print_cmdline(const char *pfx, char **argv)
{
    int i;

    printf("%s", pfx);
    for (i = 0; argv[i] != NULL; i++)
        printf(" %s", argv[i]);
    printf("\n");
}

/* pass one line of kbootset's stdout through; keep a "kbootset: " one */
static void kb_line(const char *line, char *last, unsigned lastcap)
{
    unsigned n;

    fputs(line, stdout);
    fflush(stdout);
    if (strncmp(line, "kbootset: ", 10) != 0)
        return;
    n = (unsigned)strlen(line + 10);
    while (n > 0 && (line[10 + n - 1] == '\n' || line[10 + n - 1] == '\r'))
        n--;
    if (n >= lastcap)
        n = lastcap - 1;
    memcpy(last, line + 10, n);
    last[n] = '\0';
}

/* run one kbootset call; its stdout is passed through line by line and
 * the last "kbootset: " line kept in last[].  Returns the exit status
 * (0..255), or -1 when it could not run or died on a signal. */
static int kb_run(char **argv, char *last, unsigned lastcap)
{
    int pfd[2];
    int pid;
    int st;
    int nullfd;
    char buf[512];
    char line[1024];
    unsigned used;
    int r;
    int j;

    last[0] = '\0';
    fflush(stdout);
    fflush(stderr);
    if (pipe(pfd) != 0) {
        warnx2("pipe failed");
        return -1;
    }
    pid = fork();
    if (pid < 0) {
        warnx2("fork failed");
        close(pfd[0]);
        close(pfd[1]);
        return -1;
    }
    if (pid == 0) {
        close(pfd[0]);
        nullfd = open("/dev/null", O_RDONLY);
        if (nullfd >= 0) {
            (void)dup2(nullfd, 0);
            if (nullfd > 0)
                (void)close(nullfd);
        }
        if (pfd[1] != 1) {
            (void)dup2(pfd[1], 1);
            (void)close(pfd[1]);
        }
        execv(argv[0], argv);
        fprintf(stderr, "apkg: cannot exec %s\n", argv[0]);
        _exit(127);
    }
    close(pfd[1]);
    /* read(2), not fdopen: the Amix <stdio.h> declares fdopen only for
     * non-ANSI compilations */
    used = 0;
    for (;;) {
        r = (int)read(pfd[0], buf, sizeof(buf));
        if (r <= 0)
            break;
        for (j = 0; j < r; j++) {
            if (used < sizeof(line) - 1)
                line[used++] = buf[j];
            if (buf[j] == '\n' || used == sizeof(line) - 1) {
                line[used] = '\0';
                kb_line(line, last, lastcap);
                used = 0;
            }
        }
    }
    if (used > 0) {
        line[used] = '\0';
        kb_line(line, last, lastcap);
    }
    close(pfd[0]);
    if (waitpid(pid, &st, 0) < 0) {
        warnx2("waitpid failed");
        return -1;
    }
    if (!WIFEXITED(st)) {
        warnx2("%s terminated abnormally", argv[0]);
        return -1;
    }
    if (WEXITSTATUS(st) == 127)
        return -1;
    return WEXITSTATUS(st);
}

/* one call, its status mapped to apkg's own (C2-4 §1) */
static int kb_call(const struct conf *cf, const char *cmd, char *last,
                   unsigned lastcap)
{
    char *argv[8];
    char *journal;
    int st;

    kb_argv(cf, cmd, argv, &journal);
    if (opt_verbose)
        print_cmdline("apkg: running:", argv);
    st = kb_run(argv, last, lastcap);
    free(journal);
    switch (st) {
    case 0:
        return EX_OK;
    case 1:
        warnx2("kbootset %s failed: an I/O error, a read-back mismatch "
               "or a damaged boot store (status 1)", cmd);
        warnx2("'kbootset status' shows the store; 'apkg recover' runs "
               "the build and commit again");
        return EX_BOOTSET;
    case 2:
        warnx2("kbootset rejected the call '%s' (status 2, usage): is "
               "%s the kbootset of contract C2-4 version 2?", cmd,
               cf->kbootset);
        return EX_BOOTSET;
    case 3:
        warnx2("kbootset %s refused by a rule (status 3)%s%s", cmd,
               last[0] != '\0' ? ": " : "", last);
        warnx2("the committed generation is unchanged");
        return EX_BOOTGATE;
    case 4:
        warnx2("kbootset %s refused at a gate (status 4)%s%s", cmd,
               last[0] != '\0' ? ": " : "", last);
        warnx2("the committed generation is unchanged");
        return EX_BOOTGATE;
    default:
        if (st < 0)
            warnx2("kbootset %s could not run (%s)", cmd, cf->kbootset);
        else
            warnx2("kbootset %s: unexpected status %d", cmd, st);
        warnx2("the packages are installed; 'apkg recover' runs the "
               "build and commit again");
        return EX_BOOTSET;
    }
}

int kspace_trigger(const struct conf *cf, struct txn *t)
{
    char *argv[8];
    char *journal;
    char last[1024];
    int ci;
    int rc;

    if (!bootset_auto(cf)) {
        ci = kb_argv(cf, "build", argv, &journal);
        print_cmdline("apkg: bootset=manual; compose the next generation "
                      "with:", argv);
        argv[ci] = (char *)"commit";
        print_cmdline("apkg: and then:", argv);
        free(journal);
        return EX_OK;
    }
    if (opt_dryrun) {
        ci = kb_argv(cf, "build", argv, &journal);
        print_cmdline("would run:", argv);
        argv[ci] = (char *)"commit";
        print_cmdline("would run:", argv);
        free(journal);
        return EX_OK;
    }
    if (access(cf->kbootset, X_OK) != 0) {
        warnx2("kbootset not found at %s; the next generation is not "
               "built", cf->kbootset);
        warnx2("the packages are installed; 'apkg recover' runs the "
               "build and commit once kbootset is there");
        return EX_BOOTSET;
    }
    rc = kb_call(cf, "build", last, sizeof(last));
    if (rc != EX_OK)
        return rc;
    /* between the two calls the built generation can be inspected
     * (C2-4 §5); the journal says the build is done */
    if (t != NULL) {
        strcpy(t->state, "built");
        (void)txn_save(cf, t);
    }
    rc = kb_call(cf, "commit", last, sizeof(last));
    if (rc != EX_OK) {
        warnx2("the generation was built but not committed: the next "
               "boot is unchanged");
        return rc;
    }
    printf("apkg: %s\n", last[0] != '\0' ? last :
           "kbootset commit done; power-cycle to boot it");
    return EX_OK;
}
