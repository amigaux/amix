/*
 * impl.c: the server procedures of amixtest.x, for toolchain/test-rpcgen.
 *
 * MIT licence, see LICENSE at the top of the repository.
 */
#include <string.h>
#include "amixtest.h"

result *
lookup_1_svc(item *it, struct svc_req *rq)
{
	static result res;

	(void)rq;
	if (it->name != NULL && strcmp(it->name, "text") == 0) {
		res.k = K_TEXT;
		res.result_u.text = it->name;
	} else {
		res.k = K_NUM;
		res.result_u.num = (int)it->count + (int)it->vals.vals_len + it->where.v;
	}
	return &res;
}

char **
echo_1_svc(char **s, struct svc_req *rq)
{
	(void)rq;
	return s;
}

void *
ping_1_svc(void *v, struct svc_req *rq)
{
	static char done;

	(void)v;
	(void)rq;
	return &done;
}
