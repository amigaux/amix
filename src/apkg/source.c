/*
 * source.c - package SOURCE abstraction for apkg: HTTP, FILE, RAW.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * See source.h for the classification rules and the RAW self-describing
 * layout.  The three media differ only in READ COST, and src_stage is
 * driven by it:
 *   HTTP  download -> cache -> md5 -> hand pkgadd the cache file (eph=1)
 *   FILE  .pkg     md5-verify IN PLACE, hand pkgadd the medium  (eph=0)
 *   FILE  .pkg.Z   verify in place, zcat to cache               (eph=1)
 *   RAW   dd at the catalog's byte offset -> cache -> md5       (eph=1)
 * A compressed datastream is always decompressed to the cache (the
 * medium may be read-only), so a .Z can never be eph=0.
 *
 * The "verify everything before mutating anything" invariant lives in
 * the caller (cmd_install stages ALL entries, md5-verified, before the
 * first pkgadd); src_stage supplies the per-entry md5 verification.
 *
 * C89 throughout: no snprintf/strdup, block-top declarations.  The zcat
 * step is the one shell pipeline - catalog filenames are restricted to
 * [A-Za-z0-9._+-/] at parse time precisely so they are shell-inert.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "apkg.h"
#include "source.h"


/* ---------------- small helpers ---------------- */

/* case-insensitive prefix test (scheme names are case-insensitive) */
static int has_prefix(const char *s, const char *p)
{
    while (*p != '\0') {
        if (tolower((unsigned char)*s) != tolower((unsigned char)*p))
            return 0;
        s++;
        p++;
    }
    return 1;
}

/* basename of a (forward-slash) path */
static const char *base_of(const char *path)
{
    const char *slash;

    slash = strrchr(path, '/');
    return slash != NULL ? slash + 1 : path;
}

static int is_z(const char *p)
{
    unsigned l;

    l = (unsigned)strlen(p);
    return l >= 3 && strcmp(p + l - 2, ".Z") == 0;
}

/* allocated copy of a ".Z" path with the suffix removed */
static char *drop_z(const char *p)
{
    unsigned l;
    char *o;

    l = (unsigned)strlen(p);
    o = xmalloc(l - 1);
    memcpy(o, p, l - 2);
    o[l - 2] = '\0';
    return o;
}

/* binary copy src -> dst; 0 ok / -1 error */
static int copy_file(const char *src, const char *dst)
{
    FILE *in;
    FILE *out;
    char buf[8192];
    unsigned n;

    in = fopen(src, "rb");
    if (in == NULL)
        return -1;
    out = fopen(dst, "wb");
    if (out == NULL) {
        fclose(in);
        return -1;
    }
    while ((n = (unsigned)fread(buf, 1, sizeof(buf), in)) > 0) {
        if (fwrite(buf, 1, n, out) != n) {
            fclose(in);
            fclose(out);
            return -1;
        }
    }
    if (ferror(in)) {
        fclose(in);
        fclose(out);
        return -1;
    }
    fclose(in);
    if (fclose(out) != 0)
        return -1;
    return 0;
}

/* zcat srcz (must be a .Z file) into out; 0 ok / -1 error */
static int zcat_to(const char *srcz, const char *out)
{
    char *cmd;
    int rc;

    if (opt_dryrun) {
        printf("would run: zcat < %s > %s\n", srcz, out);
        return 0;
    }
    cmd = xmalloc((unsigned)(strlen(srcz) + strlen(out) + 32));
    sprintf(cmd, "zcat < \"%s\" > \"%s\"", srcz, out);
    note("running: %s", cmd);
    rc = system(cmd);
    free(cmd);
    if (rc != 0) {
        warnx2("zcat failed on %s", srcz);
        unlink(out);
        return -1;
    }
    return 0;
}

/* the entry's hash check alone: md5 for userland, sha256 for kernel
 * space (C2-2 §1; userland stays md5 + size).  1 = matches. */
static int hash_matches(const char *path, const struct pkgent *ent)
{
    char hex[65];

    if (ent->kspace)
        return sha256_file(path, hex) == 0 && strcmp(hex, ent->sha256) == 0;
    return md5_file(path, hex) == 0 && strcmp(hex, ent->md5) == 0;
}

/* size + hash check of `path` against the catalog entry: size + md5 for
 * a userland package, size + SHA-256 for a kernel-space one.  0 ok /
 * -1 fail (message printed, but the caller decides whether to unlink) */
static int verify_file(const char *path, const struct pkgent *ent)
{
    char hex[65];
    long sz;

    sz = file_size(path);
    if (sz != ent->size) {
        warnx2("%s: size %ld does not match catalog size %ld",
               path, sz, ent->size);
        return -1;
    }
    if (ent->kspace) {
        if (ent->sha256[0] == '\0') {
            warnx2("%s: the catalog carries no sha256 for kernel-space "
                   "package %s", path, ent->name);
            return -1;
        }
        if (sha256_file(path, hex) != 0 || strcmp(hex, ent->sha256) != 0) {
            warnx2("%s: sha256 mismatch (got %s, catalog %s)",
                   path, hex, ent->sha256);
            return -1;
        }
        note("sha256 verified: %s", ent->filename);
        return 0;
    }
    if (md5_file(path, hex) != 0 || strcmp(hex, ent->md5) != 0) {
        warnx2("%s: md5 mismatch (got %s, catalog %s)",
               path, hex, ent->md5);
        return -1;
    }
    note("md5 verified: %s", ent->filename);
    return 0;
}

/* ---------------- RAW device reads ---------------- */

/* Copy `len` bytes from raw device `dev` starting at byte offset `off`
 * (512-aligned) into file `dst`.  Character raw-device reads come back
 * in 512-byte multiples, so the tail is over-read to the next boundary
 * and only the needed bytes are written.  0 ok / -1 error. */
static int raw_extract(const char *dev, long off, long len, const char *dst)
{
    int fd;
    FILE *out;
    char buf[65536];       /* multiple of 512 */
    long remaining;
    long toread;
    long got;
    int n;

    fd = open(dev, O_RDONLY);
    if (fd < 0) {
        warnx2("cannot open raw device %s", dev);
        return -1;
    }
    if (lseek(fd, (off_t)off, SEEK_SET) == (off_t)-1) {
        warnx2("cannot seek %s to offset %ld", dev, off);
        close(fd);
        return -1;
    }
    out = fopen(dst, "wb");
    if (out == NULL) {
        warnx2("cannot write %s", dst);
        close(fd);
        return -1;
    }
    remaining = len;
    while (remaining > 0) {
        if (remaining >= (long)sizeof(buf))
            toread = (long)sizeof(buf);
        else
            toread = (remaining + 511L) & ~511L;   /* up to 512 boundary */
        n = (int)read(fd, buf, (unsigned)toread);
        if (n <= 0) {
            warnx2("short raw read on %s (offset %ld, %ld left)",
                   dev, off, remaining);
            fclose(out);
            close(fd);
            return -1;
        }
        got = (long)n < remaining ? (long)n : remaining;
        if (fwrite(buf, 1, (unsigned)got, out) != (unsigned)got) {
            warnx2("write error on %s", dst);
            fclose(out);
            close(fd);
            return -1;
        }
        remaining -= got;
    }
    close(fd);
    if (fclose(out) != 0) {
        warnx2("write error closing %s", dst);
        return -1;
    }
    return 0;
}

/* Read the fixed metadata region [off, off+max) from the raw device and
 * write the prefix up to the first NUL byte (the region is text, NUL-
 * padded) to `dst`.  *absent is set when the region's first byte is NUL
 * (nothing staged there).  0 ok / -1 error. */
static int raw_fetch_text(const char *dev, long off, long max,
                          const char *dst, int *absent)
{
    int fd;
    FILE *out;
    char *buf;
    long total;
    long i;
    int n;

    *absent = 0;
    fd = open(dev, O_RDONLY);
    if (fd < 0) {
        warnx2("cannot open raw device %s", dev);
        return -1;
    }
    if (lseek(fd, (off_t)off, SEEK_SET) == (off_t)-1) {
        warnx2("cannot seek %s to offset %ld", dev, off);
        close(fd);
        return -1;
    }
    buf = xmalloc((unsigned)max);
    total = 0;
    while (total < max) {
        n = (int)read(fd, buf + total, (unsigned)(max - total));
        if (n <= 0)
            break;
        total += n;
    }
    close(fd);
    if (total <= 0) {
        free(buf);
        warnx2("raw read failed at offset %ld on %s", off, dev);
        return -1;
    }
    for (i = 0; i < total; i++) {
        if (buf[i] == '\0')
            break;
    }
    if (i == 0) {          /* empty region */
        *absent = 1;
        free(buf);
        return 0;
    }
    out = fopen(dst, "wb");
    if (out == NULL) {
        free(buf);
        warnx2("cannot write %s", dst);
        return -1;
    }
    if (fwrite(buf, 1, (unsigned)i, out) != (unsigned)i) {
        fclose(out);
        free(buf);
        warnx2("write error on %s", dst);
        return -1;
    }
    free(buf);
    if (fclose(out) != 0) {
        warnx2("write error closing %s", dst);
        return -1;
    }
    return 0;
}

/* ---------------- public: open / close ---------------- */

int src_open(const char *repo, struct source *s)
{
    unsigned len;

    s->base = NULL;
    http_opts_default(&s->http);
    if (repo == NULL || repo[0] == '\0') {
        warnx2("empty repository/source");
        return -1;
    }
    if (has_prefix(repo, "http://")) {
#ifdef APKG_NO_HTTP
        /* AMIX PORT (static/install variant, 2026-07-22): the HTTP
         * backend (http.c) is compiled out of this build - no static
         * libnsl.a exists on Amix 2.1 and the install miniroot has no
         * network stack.  An http:// repo must FAIL CLOSED here: never
         * misclassify it as another backend, never fall through. */
        warnx2("http: not available in the static/install build "
               "(source '%s'); use file://, an absolute /path, or "
               "raw:<device>", repo);
        return -1;
#else
        s->kind = SRC_HTTP;
        s->base = xstrdup(repo);              /* keep the full URL */
#endif
    } else if (has_prefix(repo, "file://")) {
        s->kind = SRC_FILE;
        s->base = xstrdup(repo + 7);          /* strip the scheme */
    } else if (repo[0] == '/') {
        s->kind = SRC_FILE;                   /* what an installer passes */
        s->base = xstrdup(repo);
    } else if (has_prefix(repo, "raw:")) {
        s->kind = SRC_RAW;
        s->base = xstrdup(repo + 4);          /* the raw device path */
    } else {
        warnx2("unclassifiable source '%s' (expected http://, file://, "
               "an absolute /path, or raw:<device>)", repo);
        return -1;
    }
    /* one trailing slash off HTTP/FILE bases; never a RAW device */
    if (s->kind != SRC_RAW) {
        len = (unsigned)strlen(s->base);
        if (len > 1 && s->base[len - 1] == '/')
            s->base[len - 1] = '\0';
    }
    note("source: kind=%s base=%s",
         s->kind == SRC_HTTP ? "http" :
         s->kind == SRC_FILE ? "file" : "raw", s->base);
    return 0;
}

void src_close(struct source *s)
{
    if (s->base != NULL) {
        free(s->base);
        s->base = NULL;
    }
}

/* ---------------- public: fetch a metadata file ---------------- */

int src_fetch(const struct source *s, const char *rel, const char *dest,
              int *status)
{
    char *url;
    char *src;
    long off;
    long max;
    int rc;
    int absent;

    *status = 0;
    switch (s->kind) {
#ifndef APKG_NO_HTTP                   /* HTTP backend excluded in the
                                        * static/install variant; src_open
                                        * has already refused http:// so
                                        * SRC_HTTP is unreachable here. */
    case SRC_HTTP:
        url = cat3(s->base, "/", rel);
        rc = http_get(url, dest, &s->http, status);
        free(url);
        return rc;                 /* HTTP_* codes == SRC_* codes */
#endif

    case SRC_FILE:
        src = cat3(s->base, "/", rel);
        if (!file_exists(src)) {
            *status = 404;
            free(src);
            return SRC_ESTATUS;
        }
        rc = copy_file(src, dest);
        if (rc != 0)
            warnx2("cannot read %s", src);
        free(src);
        return rc == 0 ? SRC_OK : SRC_ENET;

    case SRC_RAW:
        if (strcmp(rel, "catalog") == 0) {
            off = RAW_CAT_OFF;
            max = RAW_CAT_MAX;
        } else if (strcmp(rel, "catalog.md5") == 0) {
            off = RAW_MD5_OFF;
            max = RAW_MD5_MAX;
        } else {
            *status = 404;         /* RAW carries only catalog[.md5] */
            return SRC_ESTATUS;
        }
        if (raw_fetch_text(s->base, off, max, dest, &absent) != 0)
            return SRC_ENET;
        if (absent) {
            *status = 404;
            return SRC_ESTATUS;
        }
        return SRC_OK;
    }
    return SRC_ENET;
}

/* ---------------- public: stage a package datastream ---------------- */

/* Finish staging from a verified datastream at `path`: a plain datastream
 * is handed through as-is (ephemeral = plain_eph); a .Z is decompressed
 * to the cache and is always ephemeral.  Returns an EX_* code. */
static int finish_stage(const char *path, const char *cachedir,
                        const char *filename, int plain_eph,
                        char **out, int *ephemeral)
{
    char *cz;
    char *dz;

    if (!is_z(path)) {
        *out = xstrdup(path);
        *ephemeral = plain_eph;
        return EX_OK;
    }
    cz = cat3(cachedir, "/", base_of(filename));   /* cachedir/foo.pkg.Z */
    dz = drop_z(cz);                               /* cachedir/foo.pkg   */
    free(cz);
    if (zcat_to(path, dz) != 0) {
        free(dz);
        return EX_PKGCMD;
    }
    *out = dz;
    *ephemeral = 1;
    return EX_OK;
}

int src_stage(const struct source *s, const struct pkgent *ent,
              const char *cachedir, char **out, int *ephemeral)
{
    char *cache;
    char *src;
    char *url;
    int rc;
    int status;

    *out = NULL;
    *ephemeral = 0;
    if (mkpath(cachedir) != 0) {
        warnx2("cannot create cache dir %s", cachedir);
        return EX_USAGE;
    }
    cache = cat3(cachedir, "/", base_of(ent->filename));

    switch (s->kind) {
#ifndef APKG_NO_HTTP                   /* HTTP backend excluded in the
                                        * static/install variant (see
                                        * src_open / src_fetch). */
    case SRC_HTTP:
        /* a cached copy that already matches is by definition the bits
         * we want; reuse it */
        if (file_exists(cache) && file_size(cache) == ent->size &&
            hash_matches(cache, ent)) {
            note("using cached %s", cache);
        } else if (opt_dryrun) {
            printf("would download %s/pkgs/%s -> %s\n",
                   s->base, ent->filename, cache);
            rc = finish_stage(cache, cachedir, ent->filename, 1,
                              out, ephemeral);
            free(cache);
            return rc;
        } else {
            url = cat3(s->base, "/pkgs/", ent->filename);
            printf("downloading %s ...\n", ent->filename);
            rc = http_get(url, cache, &s->http, &status);
            free(url);
            if (rc == HTTP_ESTATUS) {
                warnx2("HTTP %d for %s/pkgs/%s",
                       status, s->base, ent->filename);
                free(cache);
                return EX_NET;
            }
            if (rc != HTTP_OK) {
                free(cache);
                return EX_NET;
            }
            if (verify_file(cache, ent) != 0) {
                unlink(cache);
                free(cache);
                return EX_VERIFY;
            }
        }
        rc = finish_stage(cache, cachedir, ent->filename, 1,
                          out, ephemeral);
        free(cache);
        return rc;
#endif  /* !APKG_NO_HTTP */

    case SRC_FILE:
        src = cat3(s->base, "/pkgs/", ent->filename);
        if (opt_dryrun) {
            printf("would stage %s (in place)\n", src);
            rc = finish_stage(src, cachedir, ent->filename, 0,
                              out, ephemeral);
            free(src);
            free(cache);
            return rc;
        }
        if (!file_exists(src)) {
            warnx2("not on media: %s", src);
            free(src);
            free(cache);
            return EX_NET;
        }
        if (verify_file(src, ent) != 0) {   /* verify IN PLACE */
            free(src);
            free(cache);
            return EX_VERIFY;
        }
        /* plain .pkg -> hand pkgadd the medium (eph=0); .pkg.Z ->
         * decompress to cache (eph=1) */
        rc = finish_stage(src, cachedir, ent->filename, 0,
                          out, ephemeral);
        free(src);
        free(cache);
        return rc;

    case SRC_RAW:
        if (ent->offset < 0) {
            warnx2("%s: no catalog offset column; RAW source refuses it "
                   "(fail closed)", ent->filename);
            free(cache);
            return EX_VERIFY;
        }
        if (opt_dryrun) {
            printf("would dd %s@%ld (%ld bytes) -> %s\n",
                   s->base, ent->offset, ent->size, cache);
            rc = finish_stage(cache, cachedir, ent->filename, 1,
                              out, ephemeral);
            free(cache);
            return rc;
        }
        printf("reading %s from %s@%ld ...\n",
               ent->filename, s->base, ent->offset);
        if (raw_extract(s->base, ent->offset, ent->size, cache) != 0) {
            free(cache);
            return EX_NET;
        }
        if (verify_file(cache, ent) != 0) {
            unlink(cache);
            free(cache);
            return EX_VERIFY;
        }
        rc = finish_stage(cache, cachedir, ent->filename, 1,
                          out, ephemeral);
        free(cache);
        return rc;
    }
    free(cache);
    return EX_USAGE;
}
