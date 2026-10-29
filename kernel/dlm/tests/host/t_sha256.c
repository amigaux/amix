/*
 * t_sha256.c -- SHA-256 against the FIPS 180-4 example vectors, and
 * incremental updates of every split against the one-shot digest.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>
#include "t.h"
#include "sha256.h"

static const char *
hex(const ax_u8 d[32])
{
	static char s[65];
	int i;

	for (i = 0; i < 32; i++)
		sprintf(s + 2 * i, "%02x", d[i]);
	return s;
}

void
test_sha256(void)
{
	static ax_u8 big[1000000];
	const char *m2 = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
	ax_u8 d[32], e[32];
	struct ax_sha256 s;
	ax_u32 i;

	ax_sha256((const ax_u8 *)"abc", 3, d);
	T_CHECK(!strcmp(hex(d), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
	ax_sha256((const ax_u8 *)"", 0, d);
	T_CHECK(!strcmp(hex(d), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
	ax_sha256((const ax_u8 *)m2, 56, d);
	T_CHECK(!strcmp(hex(d), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"));
	memset(big, 'a', sizeof(big));
	ax_sha256(big, sizeof(big), d);
	T_CHECK(!strcmp(hex(d), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"));
	/* every split of a 200-byte message, through the buffered path */
	for (i = 0; i < 200; i++)
		big[i] = (ax_u8)(i * 7 + 3);
	ax_sha256(big, 200, d);
	for (i = 0; i <= 200; i++) {
		ax_sha256_init(&s);
		ax_sha256_update(&s, big, i);
		ax_sha256_update(&s, big + i, 200 - i);
		ax_sha256_final(&s, e);
		T_CHECK(!memcmp(d, e, 32));
	}
}
