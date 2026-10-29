/*
 * b2test.c -- a stand-in boot2 for the b2link round-trip test: pointers in
 * initialised data, a function pointer, a string table, bss and COMMON.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
static const char msg[] = "hello from boot2";
static const char *const table[] = { msg, msg + 6, msg + 11 };
static int value = 5;
static int *pvalue = &value;
static long zeroed[64];
int common_counter;
static int (*fn)(void);

static int
three(void)
{
	return 3;
}

long
boot2_main(void *iob, void *hdr, unsigned long part, unsigned long choice, void *mem,
	   void *execbase)
{
	(void)iob; (void)hdr; (void)part; (void)choice; (void)mem; (void)execbase;
	fn = three;
	zeroed[1] = common_counter;
	return table[1][0] + *pvalue + fn() + zeroed[1];
}
