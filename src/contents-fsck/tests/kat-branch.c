/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi> */
/*
 * kat-branch.c -- known-answer test battery for the m68k cross pipeline
 * (gcc 2.7.2.3 -O -> asmfix.pl -> GNU as 2.8.1 -> static ld).
 *
 * Exercises every comparison operator (<, <=, ==, !=, >=, >) over signed
 * and unsigned ints, immediates, registers, memory and pointers, plus
 * switch-statement dispatch (the SGS .swbeg jump-table layout bug), each
 * with known answers.  Builds and runs on the host (C ground truth) and on
 * Amix (machine ground truth: run /tmp/kat-branch; exit code = number of
 * failures, 0 = all pass).
 *
 * MIT license, part of amix-packagemanager / contents-fsck.
 */

#include <stdio.h>

static int fails = 0;

static void ck(const char *name, int got, int want)
{
    if (got != want) {
        printf("FAIL %s: got %d want %d\n", name, got, want);
        fails++;
    } else {
        printf("PASS %s\n", name);
    }
}

/* ---- signed comparisons, register/register ---- */
static int slt(int a, int b) { return (a < b) ? 1 : 0; }
static int sle(int a, int b) { return (a <= b) ? 1 : 0; }
static int seq(int a, int b) { return (a == b) ? 1 : 0; }
static int sne(int a, int b) { return (a != b) ? 1 : 0; }
static int sge(int a, int b) { return (a >= b) ? 1 : 0; }
static int sgt(int a, int b) { return (a > b) ? 1 : 0; }

/* ---- signed comparisons vs immediate ---- */
static int lt8(int n)  { return (n < 8) ? 1 : 0; }
static int le8(int n)  { return (n <= 8) ? 1 : 0; }
static int gt4103(long n) { return (n > 4103L) ? 1 : 0; }
static int ltm3(int n) { return (n < -3) ? 1 : 0; }

/* ---- unsigned comparisons ---- */
static int ult(unsigned a, unsigned b) { return (a < b) ? 1 : 0; }
static int uge(unsigned a, unsigned b) { return (a >= b) ? 1 : 0; }
static int ugt2099(unsigned n) { return (n > 2099u) ? 1 : 0; }

/* ---- pointer and memory comparisons ---- */
static int pnull(const char *p) { return (p == (const char *)0) ? 1 : 0; }
static int pcmp(const char *p, const char *q) { return (p < q) ? 1 : 0; }
static int bderef(const char *p, const char *q)
{
    return (*p < *q) ? 1 : 0;
}
static long g_mem = 42;
static int memlt(int n) { return (n < g_mem) ? 1 : 0; }

/* ---- switch dispatch: mirrors contents-fsck validate_rest ---- */
static int sw_ftype(int ft, int n)
{
    switch (ft) {
    case '?':
        if (n < 2) return -1;
        return 1;
    case 'f': case 'v': case 'e':
        if (n < 8) return -2;
        return 2;
    case 'd': case 'x': case 'p':
        if (n < 5) return -3;
        return 3;
    case 'c': case 'b':
        if (n < 7) return -4;
        return 4;
    case 's': case 'l':
        if (n < 2) return -5;
        return 5;
    default:
        return 0;
    }
}

/* dense small switch */
static int sw_dense(int i)
{
    switch (i) {
    case 0: return 10;
    case 1: return 11;
    case 2: return 12;
    case 3: return 13;
    case 4: return 14;
    default: return -1;
    }
}

int main(void)
{
    static char lo = 'A', hi = 'z';
    char buf[2];

    buf[0] = 'a'; buf[1] = 'b';

    ck("slt(3,5)", slt(3, 5), 1);   ck("slt(5,3)", slt(5, 3), 0);
    ck("slt(4,4)", slt(4, 4), 0);   ck("slt(-2,1)", slt(-2, 1), 1);
    ck("sle(4,4)", sle(4, 4), 1);   ck("sle(5,4)", sle(5, 4), 0);
    ck("seq(7,7)", seq(7, 7), 1);   ck("seq(7,8)", seq(7, 8), 0);
    ck("sne(7,8)", sne(7, 8), 1);   ck("sne(7,7)", sne(7, 7), 0);
    ck("sge(4,4)", sge(4, 4), 1);   ck("sge(3,4)", sge(3, 4), 0);
    ck("sgt(5,4)", sgt(5, 4), 1);   ck("sgt(4,4)", sgt(4, 4), 0);

    ck("lt8(7)", lt8(7), 1);        ck("lt8(8)", lt8(8), 0);
    ck("le8(8)", le8(8), 1);        ck("le8(9)", le8(9), 0);
    ck("gt4103(4104)", gt4103(4104L), 1);
    ck("gt4103(4103)", gt4103(4103L), 0);
    ck("ltm3(-4)", ltm3(-4), 1);    ck("ltm3(-3)", ltm3(-3), 0);

    ck("ult(1,2)", ult(1, 2), 1);   ck("ult(2,1)", ult(2, 1), 0);
    ck("ult(0,0xffffffff)", ult(0u, 0xffffffffu), 1);
    ck("ult(0xffffffff,0)", ult(0xffffffffu, 0u), 0);
    ck("uge(2,2)", uge(2, 2), 1);   ck("uge(1,2)", uge(1, 2), 0);
    ck("ugt2099(2100)", ugt2099(2100u), 1);
    ck("ugt2099(2099)", ugt2099(2099u), 0);

    ck("pnull(NULL)", pnull((const char *)0), 1);
    ck("pnull(buf)", pnull(buf), 0);
    ck("pcmp(buf,buf+1)", pcmp(buf, buf + 1), 1);
    ck("pcmp(buf+1,buf)", pcmp(buf + 1, buf), 0);
    ck("bderef(a,b)", bderef(&buf[0], &buf[1]), 1);
    ck("bderef(b,a)", bderef(&buf[1], &buf[0]), 0);
    ck("bderef(lo,hi)", bderef(&lo, &hi), 1);
    ck("memlt(41)", memlt(41), 1);  ck("memlt(42)", memlt(42), 0);

    /* the exact shapes that failed on Amix before the .swbeg fix: */
    ck("sw('d',5)", sw_ftype('d', 5), 3);
    ck("sw('d',4)", sw_ftype('d', 4), -3);
    ck("sw('f',8)", sw_ftype('f', 8), 2);
    ck("sw('f',7)", sw_ftype('f', 7), -2);
    ck("sw('s',2)", sw_ftype('s', 2), 5);
    ck("sw('s',1)", sw_ftype('s', 1), -5);
    ck("sw('?',2)", sw_ftype('?', 2), 1);
    ck("sw('c',7)", sw_ftype('c', 7), 4);
    ck("sw('b',6)", sw_ftype('b', 6), -4);
    ck("sw('x',5)", sw_ftype('x', 5), 3);
    ck("sw('q',9)", sw_ftype('q', 9), 0);   /* default */
    ck("sw('z',9)", sw_ftype('z', 9), 0);   /* default, above range */
    ck("sw(' ',9)", sw_ftype(' ', 9), 0);   /* default, below range */
    ck("dense(0)", sw_dense(0), 10);
    ck("dense(4)", sw_dense(4), 14);
    ck("dense(5)", sw_dense(5), -1);
    ck("dense(-1)", sw_dense(-1), -1);

    printf("kat-branch: %d failures\n", fails);
    return fails;
}
