/*
 * contents-fsck.c -- checker/repairer for the SVR4 /var/sadm/install/contents
 * database, as shipped on Amiga Unix (Amix) 2.1c.
 *
 * Part of amix-packagemanager.  Standalone: single C89 source file, libc only.
 *
 * Copyright (c) 2026 Jussi Alanärä
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, subject to the following condition:
 * the above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
 *
 * Grammar checked (new-style, path-first contents(4) records):
 *   f/v/e:  path ftype class mode owner group size cksum modtime pkg...
 *   d/x/p:  path ftype class mode owner group pkg...
 *   c/b:    path ftype class major minor mode owner group pkg...
 *   s/l:    path=target ftype class pkg...
 *   ?:      path ftype class pkg...            (unknown-type placeholder)
 * Lines starting with '#', ':' or whitespace (and blank lines) are
 * comments/directives and are preserved verbatim.
 * Numeric fields may be '?' (unknown) -- the factory Amix DB really does
 * contain e.g. "/dev/console c none ? ? 0620 root tty core".
 * A trailing pkg field may carry a Solaris status prefix (-+*~!%) and an
 * optional "\" edit flag or ":class" suffix -- tolerated.
 *
 * Tolerant re-join rule (replicates the validated heirloom srchcfile patch):
 * the pathname is extended token by token until the next token is a single
 * valid ftype character [?fvelspcbdx] followed by whitespace AND the
 * remaining fields validate per-ftype.  The leftmost split that fully
 * validates wins.  This recovers records whose pathname contains embedded
 * spaces (the Amix factory corruption: ".../MacFS/TrueType Fonts").
 *
 * Sort-order checking is by PATHNAME: pkgadd/amixpkg keep the contents DB
 * in sorted pathname order, and an s/l record's on-disk first token is
 * "path=linktarget", so the key is that token truncated at the first '='.
 * Comparing the whole token instead spuriously flags every s/l entry whose
 * path is a prefix of the next entry's -- see the comment at the sort site.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define PROG        "contents-fsck"
#define VERSION     "1.0"

#define LINEMAX     4096            /* max supported line length (content) */
#define WORKSZ      (LINEMAX + 8)
#define MAXTOK      2100            /* > LINEMAX/2, can't overflow */
#define PATHSZ      (LINEMAX + 8)
#define WHYSZ       256

#define FTYPES      "?fvelspcbdx"
#define STATUSCH    "-+*~!%"

#define EXIT_CLEAN  0
#define EXIT_DIRTY  1
#define EXIT_ERROR  2

/* ------------------------------------------------------------------ */
/* globals (static buffers: no malloc, friendly to a 68030)            */
/* ------------------------------------------------------------------ */

static char linebuf[WORKSZ];        /* original line, newline stripped   */
static char workbuf[WORKSZ];        /* tokenized (NUL-punched) copy      */
static char *tok[MAXTOK];           /* token pointers into workbuf       */
static char recpath[PATHSZ];        /* recovered pathname                */
static char prevkey[PATHSZ];        /* previous sort key                 */
static char whybuf[WHYSZ];          /* first-candidate failure reason    */

/* options */
static int opt_repair = 0;          /* -r */
static int opt_strip = 0;           /* -s (repair): drop spaced records  */
static int opt_backup = 0;          /* -b (repair): copy input to .bak   */
static const char *opt_output = NULL;   /* -o (repair): output path      */

/* counters */
static long n_lines = 0;
static long n_comments = 0;
static long n_records = 0;
static long n_ft[11];               /* per-ftype counts, FTYPES order    */

static long f_unparse = 0;          /* unparseable / malformed records   */
static long f_spaced = 0;           /* recovered via tolerant re-join    */
static long f_duppkg = 0;           /* duplicated identical pkg fields   */
static long f_sort = 0;             /* out-of-sorted-order pathnames     */
static long f_eqhaz = 0;            /* '=' in a non-s/l pathname         */
static long f_long = 0;             /* line longer than LINEMAX          */

static long r_dedup = 0;            /* repair: records deduped           */
static long r_wsnorm = 0;           /* repair: records re-spaced         */
static long r_dropped = 0;          /* repair: spaced records dropped    */

/* parse result of the current record */
static int rec_ftype;               /* ftype char                        */
static int rec_fstart;              /* token index of the ftype token    */
static int rec_pkgfrom;             /* token index of first pkg field    */
static int rec_ntok;                /* token count                       */
static int rec_spaced;              /* pathname was re-joined            */

/* ------------------------------------------------------------------ */
/* small helpers (C89: no snprintf, no strdup)                         */
/* ------------------------------------------------------------------ */

static long total_findings(void)
{
    return f_unparse + f_spaced + f_duppkg + f_sort + f_eqhaz + f_long;
}

/* bounded string copy; always NUL-terminates; returns 0 if truncated */
static int scopy(char *dst, const char *src, unsigned long dstsz)
{
    unsigned long i;

    for (i = 0; src[i] != '\0'; i++) {
        if (i + 1 >= dstsz) {
            dst[i] = '\0';
            return 0;
        }
        dst[i] = src[i];
    }
    dst[i] = '\0';
    return 1;
}

static int tok_is_octal(const char *s)
{
    const char *p;

    if (s[0] == '?' && s[1] == '\0')
        return 1;                       /* unknown value, allowed */
    if (s[0] == '\0' || strlen(s) > 7)
        return 0;
    for (p = s; *p != '\0'; p++) {
        if (*p < '0' || *p > '7')
            return 0;
    }
    return 1;
}

static int tok_is_dec(const char *s)
{
    const char *p;

    if (s[0] == '?' && s[1] == '\0')
        return 1;                       /* unknown value, allowed */
    if (s[0] == '\0' || strlen(s) > 12)
        return 0;
    for (p = s; *p != '\0'; p++) {
        if (!isdigit((unsigned char)*p))
            return 0;
    }
    return 1;
}

static int tok_is_name(const char *s)
{
    unsigned long len;

    len = strlen(s);
    return (len >= 1 && len <= 32);
}

/* pkg field: optional status prefix, then a nonempty name; the name may
 * carry "\" (edit flag) and/or ":class" suffixes (Solaris extensions). */
static int tok_is_pkg(const char *s)
{
    if (s[0] != '\0' && strchr(STATUSCH, s[0]) != NULL)
        s++;
    if (s[0] == '\0' || s[0] == ':' || s[0] == '\\')
        return 0;
    return 1;
}

/* ------------------------------------------------------------------ */
/* per-ftype field validation                                          */
/*                                                                     */
/* t[] holds the tokens AFTER the ftype token (t[0] = class), n of     */
/* them; path is the candidate (re-joined) pathname.  On success       */
/* returns NULL and sets *pkgrel to the index (within t) of the first  */
/* pkg field.  On failure returns a static reason string.              */
/* ------------------------------------------------------------------ */

static const char *validate_rest(int ft, char **t, int n, int *pkgrel,
                                 const char *path)
{
    int pk;

    if (getenv("CFSCK_DEBUG") != NULL && n_lines <= 5)
        fprintf(stderr, "DBG vr ft=%c n=%d path=[%s] strchr=%s t0=[%s]\n",
                ft, n, path,
                (strchr(path, '=') != NULL) ? "hit" : "null",
                (n > 0) ? t[0] : "-");
    if (n < 1)
        return "missing class field";

    switch (ft) {
    case 'f':
    case 'v':
    case 'e':
        /* class mode owner group size cksum modtime pkg... */
        if (n < 8)
            return "too few fields (need class mode owner group size cksum modtime pkg)";
        if (!tok_is_octal(t[1]))
            return "mode is not octal";
        if (!tok_is_name(t[2]))
            return "malformed owner";
        if (!tok_is_name(t[3]))
            return "malformed group";
        if (!tok_is_dec(t[4]))
            return "size is not decimal";
        if (!tok_is_dec(t[5]))
            return "cksum is not decimal";
        if (!tok_is_dec(t[6]))
            return "modtime is not decimal";
        pk = 7;
        break;

    case 'd':
    case 'x':
    case 'p':
        /* class mode owner group pkg... */
        if (n < 5)
            return "too few fields (need class mode owner group pkg)";
        if (!tok_is_octal(t[1]))
            return "mode is not octal";
        if (!tok_is_name(t[2]))
            return "malformed owner";
        if (!tok_is_name(t[3]))
            return "malformed group";
        pk = 4;
        break;

    case 'c':
    case 'b':
        /* class major minor mode owner group pkg... */
        if (n < 7)
            return "too few fields (need class major minor mode owner group pkg)";
        if (!tok_is_dec(t[1]))
            return "major is not decimal";
        if (!tok_is_dec(t[2]))
            return "minor is not decimal";
        if (!tok_is_octal(t[3]))
            return "mode is not octal";
        if (!tok_is_name(t[4]))
            return "malformed owner";
        if (!tok_is_name(t[5]))
            return "malformed group";
        pk = 6;
        break;

    case 's':
    case 'l':
        /* class pkg...; pathname must carry "=target" */
        if (strchr(path, '=') == NULL)
            return "link entry has no '=target' in pathname";
        if (n < 2)
            return "too few fields (need class pkg)";
        pk = 1;
        break;

    case '?':
        /* class pkg... (unknown-type placeholder, per srchcfile) */
        if (n < 2)
            return "too few fields (need class pkg)";
        pk = 1;
        break;

    default:
        return "unknown ftype";
    }

    if (pk >= n)
        return "missing package field";
    *pkgrel = pk;
    for (; pk < n; pk++) {
        if (!tok_is_pkg(t[pk]))
            return "malformed package field";
    }
    return NULL;
}

/* ------------------------------------------------------------------ */
/* record parsing with the tolerant re-join rule                       */
/*                                                                     */
/* Returns 1 on success (rec_* globals set), 0 on failure (*why set    */
/* to a diagnostic; if an ftype candidate was seen, the reason its     */
/* validation failed).                                                 */
/* ------------------------------------------------------------------ */

static int parse_record(int ntok, const char **why)
{
    int k;
    int sawcand = 0;

    *why = NULL;
    rec_ntok = ntok;

    if (ntok < 2) {
        *why = "too few fields for any record type";
        return 0;
    }

    for (k = 1; k < ntok; k++) {
        const char *ft = tok[k];
        const char *w;
        int pkgrel;
        int i;
        unsigned long len;

        if (ft[0] == '\0' || ft[1] != '\0' ||
            strchr(FTYPES, ft[0]) == NULL)
            continue;                   /* not an ftype token: extend path */

        /* candidate split: path = tok[0..k-1] re-joined with spaces */
        len = 0;
        for (i = 0; i < k; i++)
            len += strlen(tok[i]) + 1;
        if (len >= PATHSZ) {
            *why = "pathname too long";
            return 0;
        }
        recpath[0] = '\0';
        for (i = 0; i < k; i++) {
            if (i > 0)
                strcat(recpath, " ");
            strcat(recpath, tok[i]);
        }

        w = validate_rest(ft[0], &tok[k + 1], ntok - k - 1, &pkgrel,
                          recpath);
        if (w == NULL) {
            rec_ftype = ft[0];
            rec_fstart = k;
            rec_pkgfrom = k + 1 + pkgrel;
            rec_spaced = (k >= 2);
            return 1;
        }
        if (!sawcand) {
            sawcand = 1;
            sprintf(whybuf, "ftype '%c': %.200s", ft[0], w);
            *why = whybuf;
        }
    }

    if (*why == NULL)
        *why = "no valid ftype token found";
    return 0;
}

/* ------------------------------------------------------------------ */
/* line reader: fgets-based, lines up to LINEMAX bytes of content      */
/* ------------------------------------------------------------------ */

/* returns -1 at EOF, else content length.  *toolong set if the line
 * exceeds LINEMAX (buffer holds the first chunk; caller must drain).
 * *had_nl records whether the line ended with a newline. */
static int read_line(FILE *fp, int *toolong, int *had_nl)
{
    unsigned long len;
    int c;

    *toolong = 0;
    *had_nl = 0;
    if (fgets(linebuf, LINEMAX + 2, fp) == NULL)
        return -1;
    len = strlen(linebuf);
    if (len > 0 && linebuf[len - 1] == '\n') {
        *had_nl = 1;
        linebuf[--len] = '\0';
        return (int)len;
    }
    c = getc(fp);
    if (c == EOF)
        return (int)len;                /* final line without newline */
    ungetc(c, fp);
    *toolong = 1;
    return (int)len;
}

/* drain the remainder of an over-long line; copy it verbatim to out
 * (may be NULL); reports whether a newline terminated the line */
static int drain_line(FILE *in, FILE *out)
{
    int c;

    while ((c = getc(in)) != EOF) {
        if (out != NULL)
            putc(c, out);
        if (c == '\n')
            return 1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* repair output helpers                                               */
/* ------------------------------------------------------------------ */

static void emit_verbatim(FILE *out, int had_nl)
{
    if (out == NULL)
        return;
    fputs(linebuf, out);
    if (had_nl)
        putc('\n', out);
}

/* emit the parsed record normalized: single spaces, pkg fields deduped */
static void emit_record(FILE *out)
{
    int i, j;

    if (out == NULL)
        return;
    fputs(recpath, out);
    putc(' ', out);
    putc(rec_ftype, out);
    for (i = rec_fstart + 1; i < rec_pkgfrom; i++) {
        putc(' ', out);
        fputs(tok[i], out);
    }
    for (i = rec_pkgfrom; i < rec_ntok; i++) {
        int dup = 0;

        for (j = rec_pkgfrom; j < i; j++) {
            if (strcmp(tok[i], tok[j]) == 0) {
                dup = 1;
                break;
            }
        }
        if (dup)
            continue;
        putc(' ', out);
        fputs(tok[i], out);
    }
    putc('\n', out);
}

/* did the original line differ from normalized single-space joining? */
static int line_was_misspaced(void)
{
    const char *p = linebuf;
    int i;

    for (i = 0; i < rec_ntok; i++) {
        unsigned long tl = strlen(tok[i]);

        if (i > 0) {
            if (*p != ' ')
                return 1;               /* tab or nothing */
            p++;
            if (*p == ' ' || *p == '\t')
                return 1;               /* run of whitespace */
        }
        if (strncmp(p, tok[i], tl) != 0)
            return 1;                   /* separator was a tab, etc. */
        p += tl;
    }
    return (*p != '\0');                /* trailing whitespace */
}

/* ------------------------------------------------------------------ */
/* file copy (for -b backup)                                           */
/* ------------------------------------------------------------------ */

static int copy_file(const char *src, const char *dst)
{
    FILE *in, *out;
    char buf[8192];
    unsigned long n;

    in = fopen(src, "rb");
    if (in == NULL)
        return -1;
    out = fopen(dst, "wb");
    if (out == NULL) {
        fclose(in);
        return -1;
    }
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) {
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

/* ------------------------------------------------------------------ */
/* the main scan                                                       */
/* ------------------------------------------------------------------ */

static int scan_file(const char *fname, FILE *in, FILE *out)
{
    int len, toolong, had_nl;
    int have_prev = 0;

    prevkey[0] = '\0';

    while ((len = read_line(in, &toolong, &had_nl)) >= 0) {
        n_lines++;

        if (toolong) {
            f_long++;
            printf("line %ld: [long-line] line exceeds %d bytes; "
                   "passed through verbatim\n", n_lines, LINEMAX);
            if (out != NULL)
                fputs(linebuf, out);
            had_nl = drain_line(in, out);
            continue;
        }

        /* comment / directive / blank lines: preserve verbatim */
        if (len == 0 || linebuf[0] == '#' || linebuf[0] == ':' ||
            isspace((unsigned char)linebuf[0])) {
            n_comments++;
            emit_verbatim(out, had_nl);
            continue;
        }

        /* a record line: must be new-style (absolute pathname first) */
        if (linebuf[0] != '/') {
            f_unparse++;
            printf("line %ld: [unparseable] record does not begin with "
                   "'/' (old-style entry?): %.120s%s\n",
                   n_lines, linebuf, (len > 120) ? "..." : "");
            emit_verbatim(out, had_nl);
            continue;
        }

        /* tokenize a working copy */
        {
            int ntok = 0;
            char *p;
            const char *why;

            memcpy(workbuf, linebuf, (unsigned long)len + 1);
            p = workbuf;
            while (*p != '\0') {
                while (*p == ' ' || *p == '\t')
                    p++;
                if (*p == '\0')
                    break;
                if (ntok >= MAXTOK)
                    break;              /* cannot happen: MAXTOK > len/2 */
                tok[ntok++] = p;
                while (*p != '\0' && *p != ' ' && *p != '\t')
                    p++;
                if (*p != '\0')
                    *p++ = '\0';
            }

            if (getenv("CFSCK_DEBUG") != NULL && n_lines <= 5)
                fprintf(stderr, "DBG line %ld len=%d ntok=%d tok0=%s\n",
                        n_lines, len, ntok, (ntok > 0) ? tok[0] : "-");
            if (!parse_record(ntok, &why)) {
                f_unparse++;
                printf("line %ld: [unparseable] %s: %.120s%s\n",
                       n_lines, why, linebuf,
                       (len > 120) ? "..." : "");
                emit_verbatim(out, had_nl);   /* never destroy data */
                continue;
            }

            n_records++;
            {
                const char *fp2 = strchr(FTYPES, rec_ftype);

                if (fp2 != NULL)
                    n_ft[fp2 - FTYPES]++;
            }

            /* finding: recovered spaced pathname */
            if (rec_spaced) {
                f_spaced++;
                printf("line %ld: [spaced-path] pathname contains "
                       "embedded space(s); recovered via tolerant "
                       "re-join as: \"%s\" (ftype %c, pkg %s)\n",
                       n_lines, recpath, rec_ftype, tok[rec_pkgfrom]);
            }

            /* finding: '=' inside a non-s/l pathname */
            if (rec_ftype != 's' && rec_ftype != 'l' &&
                strchr(recpath, '=') != NULL) {
                f_eqhaz++;
                printf("line %ld: [eq-hazard] '=' inside a non-%s "
                       "pathname \"%s\": stock tools will silently "
                       "mis-split it at the '='\n",
                       n_lines, "s/l", recpath);
            }

            /* finding: duplicated identical trailing pkg fields */
            {
                int i, j, dupline = 0;

                for (i = rec_pkgfrom + 1; i < rec_ntok; i++) {
                    for (j = rec_pkgfrom; j < i; j++) {
                        if (strcmp(tok[i], tok[j]) == 0) {
                            f_duppkg++;
                            dupline = 1;
                            printf("line %ld: [dup-pkg] duplicated "
                                   "trailing pkg field \"%s\"\n",
                                   n_lines, tok[i]);
                            break;
                        }
                    }
                }

                /*
                 * sort-order check by PATHNAME.  pkgadd/amixpkg keep the
                 * contents DB in sorted PATHNAME order; an s/l record's
                 * on-disk key is "path=linktarget", so the sort key is the
                 * path only (up to the first '=').  Comparing the whole
                 * token spuriously flags e.g. the symlink
                 * "/etc/cron=/usr/sbin/cron" against the following
                 * "/etc/cron.d" ('=' 0x3D sorts after '.' 0x2E even though
                 * the pathname /etc/cron correctly precedes /etc/cron.d).
                 */
                {
                    char sortkey[PATHSZ];
                    char *eqp;

                    scopy(sortkey, recpath, PATHSZ);
                    if ((rec_ftype == 's' || rec_ftype == 'l') &&
                        (eqp = strchr(sortkey, '=')) != NULL)
                        *eqp = '\0';
                    if (have_prev && strcmp(prevkey, sortkey) > 0) {
                        f_sort++;
                        printf("line %ld: [sort-order] \"%s\" sorts before "
                               "the preceding entry \"%s\"\n",
                               n_lines, sortkey, prevkey);
                    }
                    scopy(prevkey, sortkey, PATHSZ);
                    have_prev = 1;
                }

                /* repair-mode emission */
                if (out != NULL) {
                    if (rec_spaced && opt_strip) {
                        r_dropped++;
                        printf("line %ld: DROPPED spaced-pathname record "
                               "(-s)\n", n_lines);
                        printf(">>> on-disk file affected -- rename it "
                               "before using stock tools:\n");
                        printf(">>>     %s\n", recpath);
                    } else {
                        if (dupline)
                            r_dedup++;
                        if (line_was_misspaced())
                            r_wsnorm++;
                        emit_record(out);
                    }
                }
            }
        }
    }

    if (ferror(in)) {
        fprintf(stderr, PROG ": read error on %s\n", fname);
        return -1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* report                                                              */
/* ------------------------------------------------------------------ */

static void print_totals(const char *fname)
{
    int i;

    printf("----\n");
    printf("%s: %ld lines: %ld records, %ld comment/directive lines\n",
           fname, n_lines, n_records, n_comments);
    printf("records per ftype:");
    for (i = 0; FTYPES[i] != '\0'; i++) {
        if (n_ft[i] > 0)
            printf("  %c=%ld", FTYPES[i], n_ft[i]);
    }
    printf("\n");
    printf("findings: %ld total (unparseable %ld, spaced-path %ld, "
           "dup-pkg %ld, sort-order %ld, eq-hazard %ld, long-line %ld)\n",
           total_findings(), f_unparse, f_spaced, f_duppkg, f_sort,
           f_eqhaz, f_long);
}

/* ------------------------------------------------------------------ */
/* usage / main                                                        */
/* ------------------------------------------------------------------ */

static void usage(void)
{
    fprintf(stderr,
        "usage: " PROG " [-r [-s] [-b] [-o out]] <contents-file>\n"
        "  report mode (default): check the file, print findings, "
                "exit 0 clean / 1 findings\n"
        "  -r        repair: write <file>.fixed (input never modified)\n"
        "  -s        with -r: drop spaced-pathname records "
                "(default: keep them)\n"
        "  -b        with -r: copy input to <file>.bak first\n"
        "  -o <out>  with -r: write repaired file to <out> "
                "instead of <file>.fixed\n"
        "  -V        print version\n");
}

int main(int argc, char **argv)
{
    const char *fname = NULL;
    static char outpath[PATHSZ];
    static char tmppath[PATHSZ + 16];
    static char bakpath[PATHSZ + 16];
    FILE *in = NULL;
    FILE *out = NULL;
    int i;

    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '-' && argv[i][1] != '\0') {
            const char *a = argv[i];

            if (strcmp(a, "-r") == 0) {
                opt_repair = 1;
            } else if (strcmp(a, "-s") == 0) {
                opt_strip = 1;
            } else if (strcmp(a, "-b") == 0) {
                opt_backup = 1;
            } else if (strcmp(a, "-o") == 0) {
                if (i + 1 >= argc) {
                    fprintf(stderr, PROG ": -o requires an argument\n");
                    usage();
                    return EXIT_ERROR;
                }
                opt_output = argv[++i];
            } else if (strcmp(a, "-V") == 0) {
                printf(PROG " " VERSION "\n");
                return EXIT_CLEAN;
            } else {
                fprintf(stderr, PROG ": unknown option %s\n", a);
                usage();
                return EXIT_ERROR;
            }
        } else {
            if (fname != NULL) {
                fprintf(stderr, PROG ": exactly one input file expected\n");
                usage();
                return EXIT_ERROR;
            }
            fname = argv[i];
        }
    }

    if (fname == NULL) {
        usage();
        return EXIT_ERROR;
    }
    if ((opt_strip || opt_backup || opt_output != NULL) && !opt_repair) {
        fprintf(stderr, PROG ": -s/-b/-o only make sense with -r\n");
        usage();
        return EXIT_ERROR;
    }
    if (strlen(fname) + 16 >= PATHSZ) {
        fprintf(stderr, PROG ": input path too long\n");
        return EXIT_ERROR;
    }

    in = fopen(fname, "r");
    if (in == NULL) {
        fprintf(stderr, PROG ": cannot open %s\n", fname);
        return EXIT_ERROR;
    }

    if (opt_repair) {
        if (opt_output != NULL) {
            if (strlen(opt_output) + 16 >= PATHSZ) {
                fprintf(stderr, PROG ": output path too long\n");
                fclose(in);
                return EXIT_ERROR;
            }
            scopy(outpath, opt_output, PATHSZ);
        } else {
            sprintf(outpath, "%s.fixed", fname);
        }
        sprintf(tmppath, "%s.tmp", outpath);

        if (opt_backup) {
            sprintf(bakpath, "%s.bak", fname);
            if (copy_file(fname, bakpath) != 0) {
                fprintf(stderr, PROG ": cannot write backup %s\n", bakpath);
                fclose(in);
                return EXIT_ERROR;
            }
            printf("backup: wrote %s\n", bakpath);
        }

        out = fopen(tmppath, "w");
        if (out == NULL) {
            fprintf(stderr, PROG ": cannot create %s\n", tmppath);
            fclose(in);
            return EXIT_ERROR;
        }
    }

    printf(PROG ": %s %s\n", opt_repair ? "repairing" : "checking", fname);

    if (scan_file(fname, in, out) != 0) {
        fclose(in);
        if (out != NULL) {
            fclose(out);
            remove(tmppath);
        }
        return EXIT_ERROR;
    }
    fclose(in);

    if (out != NULL) {
        if (fclose(out) != 0) {
            fprintf(stderr, PROG ": write error on %s\n", tmppath);
            remove(tmppath);
            return EXIT_ERROR;
        }
        if (rename(tmppath, outpath) != 0) {
            fprintf(stderr, PROG ": cannot rename %s to %s\n",
                    tmppath, outpath);
            remove(tmppath);
            return EXIT_ERROR;
        }
        printf("repair: wrote %s (%ld records deduped, %ld records "
               "re-spaced, %ld spaced records %s)\n",
               outpath, r_dedup, r_wsnorm,
               opt_strip ? r_dropped : f_spaced,
               opt_strip ? "dropped" : "kept");
    }

    print_totals(fname);

    return (total_findings() > 0) ? EXIT_DIRTY : EXIT_CLEAN;
}
