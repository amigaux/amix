/*
 * vercmp-driver.c - apkg_vercmp for tests/run-tests.sh: prints -1, 0 or 1.
 *
 * Copyright (c) 2026 Jussi Alanärä.
 * MIT license - see ../LICENSE.
 */

#include <stdio.h>

extern int apkg_vercmp(const char *a, const char *b);

int main(int argc, char **argv)
{
    int r;

    if (argc != 3)
        return 2;
    r = apkg_vercmp(argv[1], argv[2]);
    printf("%d\n", r < 0 ? -1 : r > 0 ? 1 : 0);
    return 0;
}
