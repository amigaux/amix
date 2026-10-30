#!/bin/sh
# Host test of z3660eth_param(), the module's _load parameter parser, on the
# strings the core passes (amix-dlm C3-5 v3 section 3: the manifest's param
# records as one "name=value ..." string, values in C3-1 section 3's forms,
# or 0 when there are none).  The function is cut out of src/z3660eth.c as
# it is, so the test runs the shipped text.  Usage: module/test-params.sh
set -e
top=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
awk '/^z3660eth_param\(params, name, dflt\)$/ { on = 1; print "static long" }
     on { print } on && /^}$/ { exit }' "$top/src/z3660eth.c" > "$tmp/param.c"
grep -q '^}$' "$tmp/param.c" || { echo "test-params: z3660eth_param not found"; exit 1; }
cat > "$tmp/t.c" <<'C'
#include <stdio.h>
#include "param.c"
static int fails;
static void
t(char *params, char *name, long dflt, long want)
{
	long v = z3660eth_param(params, name, dflt);

	if (v != want) {
		printf("FAIL %s in \"%s\": %ld, want %ld\n", name, params ? params : "(0)", v, want);
		fails++;
	}
}
int
main()
{
	/* the S3 manifest (param z3660eth.intr=0, param z3660eth.intrl2=1) */
	t("intr=0 intrl2=1", "intr", 0L, 0L);
	t("intr=0 intrl2=1", "intrl2", 1L, 1L);
	t("intr=6 intrl2=0", "intr", 0L, 6L);
	t("intr=6 intrl2=0", "intrl2", 1L, 0L);
	t("intrl2=0 intr=6", "intr", 0L, 6L);		/* a prefix of a longer name */
	t("intrl2=0 intr=6", "intrl2", 1L, 0L);
	t("intrl2=0", "intr", 0L, 0L);			/* intr absent: the default */
	t("intr=6", "intrl2", 1L, 1L);
	t((char *)0, "intr", 0L, 0L);			/* no params at all */
	t((char *)0, "intrl2", 1L, 1L);
	t("", "intrl2", 1L, 1L);
	t("intr=12", "intr", 0L, 12L);			/* range is _load's check */
	t("intr=-1", "intr", 0L, 0L);			/* not a non-negative number */
	t("intr=6x intrl2=0", "intr", 0L, 0L);
	t("intr= intrl2=0", "intr", 0L, 0L);
	t("intr=6 intrl2=0", "int", 7L, 7L);		/* no such name */
	t("other=3 intr=6", "intr", 0L, 6L);
	t("intr=6  intrl2=0", "intrl2", 1L, 0L);	/* two spaces */
	if (fails)
		return 1;
	printf("test-params: ok (18 cases)\n");
	return 0;
}
C
${HOSTCC:-cc} -w -o "$tmp/t" "$tmp/t.c" -I"$tmp"
"$tmp/t"
