/*
 * t.h -- a minimal unit-test harness for the host tests.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef T_H
#define T_H
#include <stdio.h>

extern int t_fail, t_run;
#define T_CHECK(cond) do { t_run++; if (!(cond)) { t_fail++; \
	fprintf(stderr, "%s:%d: FAIL: %s\n", __FILE__, __LINE__, #cond); } } while (0)
#define T_EQ(a, b) do { long _a = (long)(a), _b = (long)(b); t_run++; if (_a != _b) { t_fail++; \
	fprintf(stderr, "%s:%d: FAIL: %s == %s (%ld != %ld)\n", __FILE__, __LINE__, #a, #b, _a, _b); } } while (0)

void test_crc32(void);
void test_store(void);
void test_manifest(void);
void test_inflate(void);
void test_select(void);
#endif
