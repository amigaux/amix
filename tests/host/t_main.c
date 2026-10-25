/*
 * t_main.c -- run every host unit test.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "t.h"

int t_fail, t_run;

int
main(void)
{
	test_crc32();
	test_store();
	test_manifest();
	test_inflate();
	test_select();
	test_rel();
	printf("%d checks, %d failed\n", t_run, t_fail);
	return t_fail != 0;
}
