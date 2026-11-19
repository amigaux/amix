/*
 * cmain.c: a client of amixtest.x, for toolchain/test-rpcgen.
 *     client <host>     exits 0 when LOOKUP and ECHO answer as impl.c does
 *
 * MIT licence, see LICENSE at the top of the repository.
 */
#include <stdio.h>
#include <string.h>
#include "amixtest.h"

int
main(int argc, char **argv)
{
	CLIENT *cl;
	item it;
	int v[3] = { 1, 2, 3 };
	result *r;
	char *s = "hello", **e;

	if (argc < 2) {
		fprintf(stderr, "usage: %s host\n", argv[0]);
		return 2;
	}
	cl = clnt_create(argv[1], AMIXTEST_PROG, AMIXTEST_VERS, "netpath");
	if (cl == NULL) {
		clnt_pcreateerror(argv[1]);
		return 1;
	}
	memset(&it, 0, sizeof it);
	it.name = "x";
	it.count = 4;
	it.weight = 1.5;
	it.vals.vals_len = 3;
	it.vals.vals_val = v;
	it.where.v = 10;
	r = lookup_1(&it, cl);
	if (r == NULL || r->k != K_NUM || r->result_u.num != 17) {
		fprintf(stderr, "LOOKUP: wrong answer\n");
		return 1;
	}
	e = echo_1(&s, cl);
	if (e == NULL || strcmp(*e, "hello") != 0) {
		fprintf(stderr, "ECHO: wrong answer\n");
		return 1;
	}
	printf("amixtest: ok\n");
	clnt_destroy(cl);
	return 0;
}
