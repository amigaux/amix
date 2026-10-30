/*
 * host-diff.c - differential test of libacompat's snprintf against the host's.
 *
 * Copyright (c) 2026 Jussi Alanärä.  BSD-2-Clause; see LICENSE.
 *
 * ---------------------------------------------------------------------------
 * WHY A HOST TEST EXISTS FOR A CROSS-COMPILED LIBRARY
 *
 * The on-box smoke test can only check the cases somebody thought to write
 * down, and it costs a bench cycle to run.  This one runs in a second on the
 * build host and checks the same source against a reference implementation
 * that is already known-correct -- glibc's snprintf -- over thousands of
 * (format, value, buffer-size) combinations including every edge the hand-
 * written cases would miss: truncation exactly at the boundary, zero-length
 * buffers, precision 0 of the value 0, LLONG_MIN, width smaller than the body.
 *
 * The comparison is on BOTH the bytes written and the return value.  The return
 * value is not decoration: C99 says it is the length that WOULD have been
 * written, and callers size buffers with it.  A shim that gets the string right
 * and the count wrong turns the standard measure-then-allocate idiom into an
 * infinite loop, and no amount of eyeballing output catches that.
 *
 * ---------------------------------------------------------------------------
 * WHAT THIS TEST CANNOT PROVE
 *
 * It runs x86 code compiled by a modern gcc.  It proves the ALGORITHM; it does
 * not prove the m68k code generation, which is the other half of the risk on
 * this toolchain and is why the build script also disassembles the archive and
 * why the package is smoke-tested on a real box.  Neither test replaces the
 * other.
 *
 * Float conversions are deliberately NOT compared: libacompat delegates them to
 * the platform's own sprintf, so on the host this test would be comparing glibc
 * against glibc and proving nothing, while on Amix the digits are libc's by
 * construction.
 *
 * %p is excluded for a real difference rather than an accidental one: glibc
 * prints NULL as "(nil)"; libacompat prints "0x0", the SVR4/BSD spelling.  It
 * is checked explicitly below instead.
 *
 * Build:  cc -o host-diff host-diff.c ../src/snprintf.c -I../include \
 *            -DAMIX_NO_LIBC_NAMES -D_AMIX_HAVE_SSIZE_T
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#include "amixcompat.h"

static int failures;
static int checks;

/*
 * Compare one case.  `expect` and `expect_n` come from the host's snprintf;
 * `got`/`got_n` from libacompat's.  The buffers are poisoned before each call
 * so a shim that writes nothing is not mistaken for one that writes the right
 * thing.
 */
static void
report(const char *what, const char *expect, int expect_n,
    const char *got, int got_n, size_t bufsize)
{
	checks++;
	/*
	 * A size of 0 means NOTHING may be written -- not even the NUL.  So at
	 * size 0 the only thing there is to compare is the return value; the
	 * buffers still hold the poison pattern by design, and comparing them
	 * would be testing memset.  (Getting this wrong is how the first run of
	 * this harness produced 500 "failures" that were all the test's fault.)
	 */
	if (expect_n != got_n) {
		failures++;
		printf("FAIL %s (size=%lu): rc host=%d ours=%d\n",
		    what, (unsigned long)bufsize, expect_n, got_n);
		return;
	}
	if (bufsize == 0)
		return;
	if (strcmp(expect, got) == 0)
		return;
	failures++;
	printf("FAIL %s (size=%lu)\n", what, (unsigned long)bufsize);
	printf("     host: rc=%d  \"%s\"\n", expect_n, expect);
	printf("     ours: rc=%d  \"%s\"\n", got_n, got);
}

/*
 * The poison pattern proves a shim that writes nothing is not mistaken for one
 * that writes the right thing.  The last byte is always left as NUL so the
 * comparison functions cannot run off the end of an unterminated buffer.
 */
#define POISON 0xA5
#define POISON_FILL(b)	do { memset((b), POISON, sizeof(b)); \
			     (b)[sizeof(b) - 1] = '\0'; } while (0)

static void
cmp_ll(const char *fmt, long long v, size_t bufsize)
{
	char a[256], b[256];
	char label[128];
	int na, nb;

	POISON_FILL(a);
	POISON_FILL(b);
	na = snprintf(a, bufsize, fmt, v);
	nb = amix_snprintf(b, bufsize, fmt, v);
	sprintf(label, "%s <- %lld", fmt, v);
	report(label, a, na, b, nb, bufsize);
}

static void
cmp_ull(const char *fmt, unsigned long long v, size_t bufsize)
{
	char a[256], b[256];
	char label[128];
	int na, nb;

	POISON_FILL(a);
	POISON_FILL(b);
	na = snprintf(a, bufsize, fmt, v);
	nb = amix_snprintf(b, bufsize, fmt, v);
	sprintf(label, "%s <- %llu", fmt, v);
	report(label, a, na, b, nb, bufsize);
}

static void
cmp_int(const char *fmt, int v, size_t bufsize)
{
	char a[256], b[256];
	char label[128];
	int na, nb;

	POISON_FILL(a);
	POISON_FILL(b);
	na = snprintf(a, bufsize, fmt, v);
	nb = amix_snprintf(b, bufsize, fmt, v);
	sprintf(label, "%s <- %d", fmt, v);
	report(label, a, na, b, nb, bufsize);
}

static void
cmp_str(const char *fmt, const char *v, size_t bufsize)
{
	char a[256], b[256];
	char label[192];
	int na, nb;

	POISON_FILL(a);
	POISON_FILL(b);
	na = snprintf(a, bufsize, fmt, v);
	nb = amix_snprintf(b, bufsize, fmt, v);
	sprintf(label, "%s <- \"%s\"", fmt, v == NULL ? "(NULL)" : v);
	report(label, a, na, b, nb, bufsize);
}

static void
cmp_starint(const char *fmt, int w, int v, size_t bufsize)
{
	char a[256], b[256];
	char label[128];
	int na, nb;

	POISON_FILL(a);
	POISON_FILL(b);
	na = snprintf(a, bufsize, fmt, w, v);
	nb = amix_snprintf(b, bufsize, fmt, w, v);
	sprintf(label, "%s <- (*=%d, %d)", fmt, w, v);
	report(label, a, na, b, nb, bufsize);
}

int
main(void)
{
	static const char *int_fmts[] = {
		"%d", "%5d", "%-5d", "%05d", "%+d", "% d", "%.5d", "%.0d",
		"%8.5d", "%-8.5d", "%i", "%u", "%o", "%#o", "%x", "%X",
		"%#x", "%#X", "%08x", "%-8x", "%.4x", "%hd", "%hhd",
		"a%db", "%%%d%%"
	};
	static const long long ll_values[] = {
		0LL, 1LL, -1LL, 7LL, -7LL, 42LL, -42LL, 99999LL, -99999LL,
		2147483647LL, -2147483648LL, 4294967295LL, 4294967296LL,
		1234567890123456789LL, -1234567890123456789LL,
		9223372036854775807LL
	};
	static const unsigned long long ull_values[] = {
		0ULL, 1ULL, 255ULL, 65535ULL, 4294967295ULL, 4294967296ULL,
		18446744073709551615ULL, 12345678901234567890ULL,
		1000000000000ULL
	};
	static const size_t sizes[] = { 0, 1, 2, 3, 5, 8, 16, 200 };
	static const char *strs[] = { "", "a", "hello", "a rather longer string" };
	size_t si, fi, vi;
	char buf[64];
	int n;

	/* --- integer conversions, every width/flag against every value ---- */
	for (si = 0; si < sizeof(sizes) / sizeof(sizes[0]); si++) {
		for (fi = 0; fi < sizeof(int_fmts) / sizeof(int_fmts[0]); fi++) {
			for (vi = 0; vi < sizeof(ll_values) / sizeof(ll_values[0]); vi++) {
				long long v = ll_values[vi];
				/*
				 * The plain (non-ll) formats take an int, so
				 * only feed them values an int can hold --
				 * otherwise the varargs types differ between
				 * the two calls and the test is meaningless.
				 */
				if (v >= INT_MIN && v <= INT_MAX)
					cmp_int(int_fmts[fi], (int)v, sizes[si]);
			}
		}
	}

	/* --- the long long path, which is the whole reason for this shim --- */
	{
		static const char *ll_fmts[] = {
			"%lld", "%llu", "%llx", "%llX", "%llo", "%20lld",
			"%-20lld", "%020lld", "%+lld", "%.25lld", "%#llx",
			"%qd", "%jd"
		};
		for (si = 0; si < sizeof(sizes) / sizeof(sizes[0]); si++) {
			for (fi = 0; fi < sizeof(ll_fmts) / sizeof(ll_fmts[0]); fi++) {
				for (vi = 0; vi < sizeof(ll_values) / sizeof(ll_values[0]); vi++)
					cmp_ll(ll_fmts[fi], ll_values[vi], sizes[si]);
				for (vi = 0; vi < sizeof(ull_values) / sizeof(ull_values[0]); vi++) {
					const char *f = ll_fmts[fi];
					/* signed formats with huge unsigned values would differ legitimately */
					if (strchr(f, 'u') != NULL || strchr(f, 'x') != NULL ||
					    strchr(f, 'X') != NULL || strchr(f, 'o') != NULL)
						cmp_ull(f, ull_values[vi], sizes[si]);
				}
			}
		}
	}

	/* --- long, and the 32-bit-on-this-ABI z modifier ------------------- */
	{
		static const char *l_fmts[] = { "%ld", "%lu", "%lx", "%10ld", "%-10lu" };
		for (si = 0; si < sizeof(sizes) / sizeof(sizes[0]); si++)
			for (fi = 0; fi < sizeof(l_fmts) / sizeof(l_fmts[0]); fi++)
				for (vi = 0; vi < sizeof(ll_values) / sizeof(ll_values[0]); vi++) {
					long long v = ll_values[vi];
					if (v >= LONG_MIN && v <= LONG_MAX) {
						char a[256], b[256];
						char label[128];
						int na, nb;
						POISON_FILL(a);
						POISON_FILL(b);
						na = snprintf(a, sizes[si], l_fmts[fi], (long)v);
						nb = amix_snprintf(b, sizes[si], l_fmts[fi], (long)v);
						sprintf(label, "%s <- %ldL", l_fmts[fi], (long)v);
						report(label, a, na, b, nb, sizes[si]);
					}
				}
	}

	/* --- strings, precision, NULL -------------------------------------- */
	{
		static const char *s_fmts[] = {
			"%s", "%10s", "%-10s", "%.3s", "%10.3s", "%-10.3s",
			"[%s]", "%s%s"
		};
		for (si = 0; si < sizeof(sizes) / sizeof(sizes[0]); si++) {
			for (fi = 0; fi < sizeof(s_fmts) / sizeof(s_fmts[0]) - 1; fi++)
				for (vi = 0; vi < sizeof(strs) / sizeof(strs[0]); vi++)
					cmp_str(s_fmts[fi], strs[vi], sizes[si]);
			cmp_str("%s", NULL, sizes[si]);
			/*
			 * "%.3s" of NULL is NOT compared against the host: both
			 * behaviours are defensible and they differ.  Passing
			 * NULL to %s is undefined, and the two live traditions
			 * split on what to do when a precision truncates the
			 * substitute string -- glibc emits nothing at all when
			 * the precision is shorter than "(null)", BSD emits the
			 * truncation.  libacompat follows BSD, which is the
			 * lineage this target's userland comes from, so the
			 * expectation is asserted below rather than diffed.
			 */
		}
	}

	/* --- %c, and a * width/precision ----------------------------------- */
	for (si = 0; si < sizeof(sizes) / sizeof(sizes[0]); si++) {
		cmp_int("%c", 'A', sizes[si]);
		cmp_int("%5c", 'A', sizes[si]);
		cmp_int("%-5c", 'A', sizes[si]);
		cmp_starint("%*d", 8, 42, sizes[si]);
		cmp_starint("%*d", -8, 42, sizes[si]);
		cmp_starint("%.*d", 6, 42, sizes[si]);
		cmp_starint("%.*d", 0, 0, sizes[si]);
		{
			/*
			 * "%*.*d" takes THREE arguments, so it cannot go
			 * through cmp_starint -- feeding a three-conversion
			 * format two arguments is exactly the varargs
			 * desynchronisation this library exists to prevent, and
			 * writing it here by accident would make the test
			 * compare two different kinds of garbage.
			 */
			char a[256], b[256];
			int na, nb;
			POISON_FILL(a);
			POISON_FILL(b);
			na = snprintf(a, sizes[si], "%*.*d", 12, 6, 42);
			nb = amix_snprintf(b, sizes[si], "%*.*d", 12, 6, 42);
			report("%*.*d <- (12, 6, 42)", a, na, b, nb, sizes[si]);
		}
	}

	/* --- %p: an intentional divergence, so it is asserted, not compared - */
	checks++;
	n = amix_snprintf(buf, sizeof(buf), "%p", (void *)0);
	if (strcmp(buf, "0x0") != 0 || n != 3) {
		failures++;
		printf("FAIL %%p of NULL: rc=%d \"%s\" (expected rc=3 \"0x0\")\n", n, buf);
	}
	checks++;
	n = amix_snprintf(buf, sizeof(buf), "%p", (void *)0x1234abcd);
	if (strcmp(buf, "0x1234abcd") != 0 || n != 10) {
		failures++;
		printf("FAIL %%p: rc=%d \"%s\"\n", n, buf);
	}

	/* --- NULL %s with a precision: our documented BSD-side choice ------ */
	checks++;
	n = amix_snprintf(buf, sizeof(buf), "%.3s", (char *)0);
	if (strcmp(buf, "(nu") != 0 || n != 3) {
		failures++;
		printf("FAIL %%.3s of NULL: rc=%d \"%s\" (expected rc=3 \"(nu\")\n", n, buf);
	}
	checks++;
	n = amix_snprintf(buf, sizeof(buf), "%s", (char *)0);
	if (strcmp(buf, "(null)") != 0 || n != 6) {
		failures++;
		printf("FAIL %%s of NULL: rc=%d \"%s\" (expected rc=6 \"(null)\")\n", n, buf);
	}

	/* --- the truncation contract, stated explicitly -------------------- */
	{
		char small[4];
		memset(small, POISON, sizeof(small));
		checks++;
		n = amix_snprintf(small, 4, "%s", "abcdefgh");
		if (n != 8 || strcmp(small, "abc") != 0) {
			failures++;
			printf("FAIL truncation: rc=%d \"%s\" (expected rc=8 \"abc\")\n", n, small);
		}
		checks++;
		/*
		 * size 0 with a NULL buffer must be legal and must still return
		 * the would-be length: this is the measure-then-allocate idiom
		 * every modern caller uses.
		 */
		n = amix_snprintf((char *)0, 0, "%s-%d", "abc", 42);
		if (n != 6) {
			failures++;
			printf("FAIL NULL/0 measuring call: rc=%d (expected 6)\n", n);
		}
		checks++;
		/* size 1 writes only the NUL and must not touch small[1]. */
		memset(small, POISON, sizeof(small));
		n = amix_snprintf(small, 1, "xyz");
		if (n != 3 || small[0] != '\0' || small[1] != (char)POISON) {
			failures++;
			printf("FAIL size-1: rc=%d buf[0]=%d buf[1]=%d\n",
			    n, small[0], small[1]);
		}
	}

	printf("\nhost-diff: %d checks, %d failures\n", checks, failures);
	return (failures == 0 ? 0 : 1);
}
