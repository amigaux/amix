/*
 * vercmp.c - version comparison for apkg.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see LICENSE in this directory.
 *
 * Rule (docs/design.md section 2): split both versions into segments
 * on '.' and '-'.  Compare segment by segment: if both segments are
 * all-numeric they compare numerically, otherwise by strcmp.  A
 * missing segment counts as 0 ("1.2" == "1.2.0", "1.2" < "1.2.1").
 * An empty/absent version therefore sorts before any real one, which
 * is how VERSION-less stock packages are treated by upgrade.
 */

#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "apkg.h"

/* copy the next segment of *sp into buf (max buflen-1 chars), advance
 * *sp past the delimiter; returns 0 when the string was exhausted
 * before the call (buf then holds "0"). */
static int next_seg(const char **sp, char *buf, unsigned buflen)
{
    const char *s;
    unsigned i;

    s = *sp;
    if (*s == '\0') {
        buf[0] = '0';
        buf[1] = '\0';
        return 0;
    }
    i = 0;
    while (*s != '\0' && *s != '.' && *s != '-') {
        if (i < buflen - 1)
            buf[i++] = *s;
        s++;
    }
    buf[i] = '\0';
    if (*s == '.' || *s == '-')
        s++;
    *sp = s;
    return 1;
}

static int all_numeric(const char *s)
{
    if (*s == '\0')
        return 0;
    while (*s != '\0') {
        if (!isdigit((unsigned char)*s))
            return 0;
        s++;
    }
    return 1;
}

/* returns <0, 0, >0 like strcmp */
int apkg_vercmp(const char *a, const char *b)
{
    char sa[64];
    char sb[64];
    int more_a;
    int more_b;
    long na;
    long nb;
    int r;

    if (a == NULL)
        a = "";
    if (b == NULL)
        b = "";
    for (;;) {
        more_a = next_seg(&a, sa, sizeof(sa));
        more_b = next_seg(&b, sb, sizeof(sb));
        if (!more_a && !more_b)
            return 0;
        if (all_numeric(sa) && all_numeric(sb)) {
            na = atol(sa);
            nb = atol(sb);
            if (na != nb)
                return na < nb ? -1 : 1;
        } else {
            r = strcmp(sa, sb);
            if (r != 0)
                return r < 0 ? -1 : 1;
        }
    }
}
