/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi> */
#include <stdio.h>
int mymod(int hv, int hsz) { return hv % hsz; }   /* variable divisor -> tdivs remainder form */
int mydiv(int hv, int hsz) { return hv / hsz; }
int main(void) {
    printf("351 %% 151 = %d  (expect 49)\n", mymod(351,151));
    printf("100 %% 7   = %d  (expect 2)\n",  mymod(100,7));
    printf("351 / 151 = %d  (expect 2)\n",   mydiv(351,151));
    return 0;
}
