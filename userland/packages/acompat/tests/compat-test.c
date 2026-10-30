/*
 * compat-test.c - the on-box acceptance test for libacompat.
 *
 * Copyright (c) 2026 Jussi Alanärä.  BSD-2-Clause; see LICENSE.
 *
 * Runs ON AMIX, links against the installed libacompat.a, and exercises every
 * symbol the library claims to provide.  It exists because the host
 * differential test (tests/host-diff.c) proves the ALGORITHM on x86 and cannot
 * prove anything about m68k code generation, the SVR4 libc underneath, or the
 * s5 filesystem -- and on this toolchain those are where the failures live.
 *
 * OUTPUT CONTRACT.  One "ok"/"FAIL" line per check, a summary, and an exit
 * status of 0 only if every check passed.  Machine-readable on purpose: the
 * bench transport is telnet, the console truncates canonical input at ~256
 * characters, and reading a wall of prose over that link is how a real failure
 * gets missed.
 *
 * ORDERING IS DELIBERATE.  The floating-point check runs LAST and announces
 * itself before it runs.  Stock Amix requires a 68881/68882, and on a part
 * without one ANY float conversion dies inside libc's _doprnt with SIGSYS --
 * "Bad System Call", exit 140, not SIGILL or SIGFPE.  Putting it last means a
 * box with no FPU still produces the results of every other check before it
 * dies, instead of taking the whole transcript with it.
 *
 * C89 as gcc 2.7.2.3 accepts it: no declarations after statements, no
 * loop-scoped indices, no // comments.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/time.h>

#include "amixcompat.h"
#include "strings.h"

static int passed;
static int failed;

static void
ck(const char *what, int ok)
{
	if (ok) {
		passed++;
		printf("ok   %s\n", what);
	} else {
		failed++;
		printf("FAIL %s\n", what);
	}
}

static void
ck_str(const char *what, const char *got, const char *want)
{
	if (strcmp(got, want) == 0) {
		passed++;
		printf("ok   %s\n", what);
	} else {
		failed++;
		printf("FAIL %s: got \"%s\" want \"%s\"\n", what, got, want);
	}
}

static void
ck_int(const char *what, long got, long want)
{
	if (got == want) {
		passed++;
		printf("ok   %s\n", what);
	} else {
		failed++;
		printf("FAIL %s: got %ld want %ld\n", what, got, want);
	}
}

int
main(argc, argv)
	int argc;
	char **argv;
{
	char buf[128];
	char tmpl[64];
	char rb[64];
	struct timeval t0;
	struct timeval t1;
	long elapsed;
	int n;
	int fd;
	const char *v;

	(void)argc;
	(void)argv;

	printf("== %s ==\n", amix_compat_version());

	/* ---------------------------------------------------------------- */
	printf("-- snprintf: the long long path --\n");

	/*
	 * THE check.  SVR4.0's own printf has no ll modifier at all, so this
	 * number cannot be printed by anything else on this machine.  If this
	 * line is right, the class of blocker that motivated the whole library
	 * (bzip2recover, coreutils, dropbear's libtom*) is closed.
	 */
	n = snprintf(buf, sizeof(buf), "%llu", 12345678901234567890ULL);
	ck_str("%llu of 12345678901234567890", buf, "12345678901234567890");
	ck_int("%llu return value", (long)n, 20L);

	n = snprintf(buf, sizeof(buf), "%lld", -1234567890123456789LL);
	ck_str("%lld negative", buf, "-1234567890123456789");

	n = snprintf(buf, sizeof(buf), "%llx", 18446744073709551615ULL);
	ck_str("%llx of UINT64_MAX", buf, "ffffffffffffffff");

	/*
	 * LLONG_MIN.  Negating it in the signed domain is undefined behaviour
	 * that a compiler is free to turn into anything; the implementation
	 * negates in the unsigned domain instead, and this is the check that
	 * proves it on the real code generator rather than on the host's.
	 */
	n = snprintf(buf, sizeof(buf), "%lld", (long long)(-9223372036854775807LL - 1LL));
	ck_str("%lld of LLONG_MIN", buf, "-9223372036854775808");

	printf("-- snprintf: bounds and return value --\n");

	n = snprintf(buf, 4, "%s", "abcdefgh");
	ck_str("truncation writes 3 chars + NUL", buf, "abc");
	ck_int("truncation returns the WOULD-BE length", (long)n, 8L);

	n = snprintf((char *)0, 0, "%s-%d", "abc", 42);
	ck_int("NULL/0 measuring call", (long)n, 6L);

	printf("-- snprintf: conversions --\n");
	(void)snprintf(buf, sizeof(buf), "%5d|%-5d|%05d|%+d|% d", 42, 42, 42, 42, 42);
	ck_str("width, left, zero, plus, space", buf, "   42|42   |00042|+42| 42");

	(void)snprintf(buf, sizeof(buf), "%x|%X|%#x|%o|%#o", 48879, 48879, 48879, 8, 8);
	ck_str("hex and octal", buf, "beef|BEEF|0xbeef|10|010");

	(void)snprintf(buf, sizeof(buf), "%.3s|%10.3s|%-10.3s|", "abcdefg", "abcdefg", "abcdefg");
	ck_str("string precision and padding", buf, "abc|       abc|abc       |");

	(void)snprintf(buf, sizeof(buf), "%*d|%.*d", 6, 7, 4, 7);
	ck_str("star width and precision", buf, "     7|0007");

	(void)snprintf(buf, sizeof(buf), "%c%%%s", 'A', "z");
	ck_str("char, literal percent, string", buf, "A%z");

	/* ---------------------------------------------------------------- */
	printf("-- strcasecmp / strncasecmp --\n");
	ck("strcasecmp equal ignoring case", strcasecmp("HeLLo", "hello") == 0);
	ck("strcasecmp orders a < b", strcasecmp("abc", "ABD") < 0);
	ck("strcasecmp orders b > a", strcasecmp("ABD", "abc") > 0);
	ck("strcasecmp distinguishes lengths", strcasecmp("abc", "abcd") != 0);
	ck("strncasecmp honours n", strncasecmp("abcXXX", "ABCyyy", 3) == 0);
	ck("strncasecmp n=0 always equal", strncasecmp("q", "z", 0) == 0);
	/*
	 * Non-alphabetic bytes must not be folded.  SVR4 tolower() is defined
	 * only for characters that ARE upper case, which is why the
	 * implementation folds by hand -- this check is what proves it did.
	 */
	ck("strcasecmp does not fold punctuation", strcasecmp("_", "?") != 0);

	/* ---------------------------------------------------------------- */
	printf("-- setenv / unsetenv --\n");
	ck_int("setenv new variable", (long)setenv("AMIXCOMPAT_T", "one", 1), 0L);
	v = getenv("AMIXCOMPAT_T");
	ck_str("getenv reads it back", v == NULL ? "(unset)" : v, "one");

	ck_int("setenv overwrite=0 does not replace",
	    (long)setenv("AMIXCOMPAT_T", "two", 0), 0L);
	v = getenv("AMIXCOMPAT_T");
	ck_str("value unchanged after overwrite=0", v == NULL ? "(unset)" : v, "one");

	ck_int("setenv overwrite=1 replaces", (long)setenv("AMIXCOMPAT_T", "two", 1), 0L);
	v = getenv("AMIXCOMPAT_T");
	ck_str("value changed after overwrite=1", v == NULL ? "(unset)" : v, "two");

	/*
	 * The reason unsetenv exists rather than putenv("NAME="): an empty
	 * variable still reads as PRESENT, and programs that test presence
	 * (configure scripts among them) then see the opposite of what was
	 * meant.  This check is specifically that getenv returns NULL, not "".
	 */
	ck_int("unsetenv", (long)unsetenv("AMIXCOMPAT_T"), 0L);
	ck("getenv is NULL after unsetenv, not empty", getenv("AMIXCOMPAT_T") == NULL);

	ck_int("setenv rejects a name containing '='",
	    (long)setenv("BAD=NAME", "x", 1), -1L);

	/*
	 * Repeated setenv of the same name must not leak: the shim frees the
	 * copy it previously installed.  Correctness is checked here (the value
	 * survives 50 rewrites); the absence of the leak is a design property
	 * argued in env.c, since this box has no usable heap instrumentation.
	 */
	{
		int i;
		int loop_ok;

		loop_ok = 1;
		for (i = 0; i < 50; i++) {
			(void)snprintf(buf, sizeof(buf), "v%d", i);
			if (setenv("AMIXCOMPAT_L", buf, 1) != 0)
				loop_ok = 0;
		}
		v = getenv("AMIXCOMPAT_L");
		if (v == NULL || strcmp(v, "v49") != 0)
			loop_ok = 0;
		ck("50 setenv rewrites keep the last value", loop_ok);
		(void)unsetenv("AMIXCOMPAT_L");
	}

	/* ---------------------------------------------------------------- */
	printf("-- mkstemp --\n");
	/*
	 * The basename is 8 characters plus XXXXXX = 14 bytes exactly, which is
	 * the largest name an s5 dirent holds without truncation.  Anything
	 * longer and every generated name would truncate onto the same dirent,
	 * so every O_EXCL create would return EEXIST forever -- the defect that
	 * once made pkgadd unable to overwrite long-named files on this exact
	 * filesystem.
	 */
	(void)strcpy(tmpl, "/tmp/actstXXXXXX");
	fd = mkstemp(tmpl);
	ck("mkstemp returns a descriptor", fd >= 0);
	if (fd >= 0) {
		ck("mkstemp filled in the template", strstr(tmpl, "XXXXXX") == NULL);
		n = (int)write(fd, "amix", 4);
		ck_int("write to the mkstemp fd", (long)n, 4L);
		(void)close(fd);
		fd = open(tmpl, O_RDONLY);
		ck("reopen the mkstemp file", fd >= 0);
		if (fd >= 0) {
			memset(rb, 0, sizeof(rb));
			n = (int)read(fd, rb, 4);
			(void)close(fd);
			ck_int("read back 4 bytes", (long)n, 4L);
			ck_str("read back the same bytes", rb, "amix");
		}
		(void)unlink(tmpl);
	}
	/*
	 * A template with a 14-byte basename cannot work on s5, and the shim
	 * says so immediately instead of spinning through sixteen identical
	 * EEXIST failures.
	 */
	(void)strcpy(tmpl, "/tmp/toolongnameXXXXXX");
	ck("mkstemp refuses an s5-untenable template", mkstemp(tmpl) < 0);

	(void)strcpy(tmpl, "/tmp/noXs");
	ck("mkstemp rejects a template with no XXXXXX", mkstemp(tmpl) < 0);

	/* ---------------------------------------------------------------- */
	printf("-- gettimeofday (via _abi_gettimeofday) --\n");
	/*
	 * libc.so.1 exports no `gettimeofday` at all; it exports
	 * `_abi_gettimeofday`, one-argument, and <rpc/types.h> hides that
	 * behind a #define.  If this call links and returns a plausible time,
	 * the alias works.
	 */
	memset((char *)&t0, 0, sizeof(t0));
	ck_int("gettimeofday returns 0", (long)gettimeofday(&t0, (void *)0), 0L);
	ck("tv_sec is non-zero", t0.tv_sec != 0);
	ck("tv_usec is in range", t0.tv_usec >= 0 && t0.tv_usec < 1000000);
	printf("     clock reads %ld.%06ld\n", (long)t0.tv_sec, (long)t0.tv_usec);
	/* NULL must be accepted and do nothing, per the shipped ABI function. */
	ck_int("gettimeofday(NULL) is not an error",
	    (long)gettimeofday((struct timeval *)0, (void *)0), 0L);

	/* ---------------------------------------------------------------- */
	printf("-- usleep --\n");
	(void)gettimeofday(&t0, (void *)0);
	ck_int("usleep(0) returns 0", (long)usleep(0U), 0L);
	ck_int("usleep(200000) returns 0", (long)usleep(200000U), 0L);
	(void)gettimeofday(&t1, (void *)0);
	elapsed = (long)(t1.tv_sec - t0.tv_sec) * 1000000L +
	    (long)(t1.tv_usec - t0.tv_usec);
	printf("     0.2 s request measured %ld us\n", elapsed);
	/*
	 * Bounds, not equality.  The kernel tick is HZ=60 (~16.7 ms) so the
	 * real granularity is far coarser than the interface suggests, and this
	 * is an emulated machine that can be descheduled by the host.  The
	 * check that matters is that it slept AT ALL: a usleep that returns
	 * immediately turns every backoff loop into a spin.
	 */
	ck("usleep actually slept (>= 100 ms)", elapsed >= 100000L);
	ck("usleep did not overshoot wildly (< 5 s)", elapsed < 5000000L);

	/* ---------------------------------------------------------------- */
	printf("-- floating point (LAST: needs a 68881/68882) --\n");
	printf("     If the next line does not appear and this process dies with\n");
	printf("     \"Bad System Call\", this part has no FPU: every float conversion\n");
	printf("     goes through libc's _doprnt, which carries FP instructions.\n");
	(void)snprintf(buf, sizeof(buf), "%.3f|%.2e|%g", 3.14159, 1234.5, 0.5);
	ck_str("float conversions delegate to libc", buf, "3.142|1.23e+03|0.5");
	(void)snprintf(buf, sizeof(buf), "%8.2f|%-8.2f|", -1.5, -1.5);
	ck_str("float width and sign placement", buf, "   -1.50|-1.50   |");

	/* ---------------------------------------------------------------- */
	printf("\n%d passed, %d failed\n", passed, failed);
	return (failed == 0 ? 0 : 1);
}
