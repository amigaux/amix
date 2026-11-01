/*
 * dbbench.c -- times and checks the primitives Dropbear 2026.94 can offer,
 * built from Dropbear's own objects (curve25519.c, mlkem768.c, sntrup761.c,
 * dh_groups.c) and its bundled libtomcrypt/libtommath.  No /dev/urandom:
 * randomness is a fixed ChaCha20 stream, reset per test, so every DIGEST
 * line must equal the same program's on the build host.
 *
 *   dbbench [secs]     secs: CPU seconds per timed item (default 3)
 *
 * Built by build.sh (beside it) from the tree build/pkg/pkgbuild.sh leaves.
 * The ECDSA timings are left out: Dropbear signs ECDSA with its own code,
 * whose cost is that of the ECDH lines (one scalar multiplication to sign,
 * two to verify).
 *
 * Lines:  KAT <name> ok|FAIL       known-answer / self test
 *         DIGEST <name> <sha256>   outputs of fixed inputs (compare with host)
 *         TIME <name> <ops> <ticks> <hz>        CPU time of <ops> operations
 *         BULK <name> <pktsize> <bytes> <ticks> <hz>
 *
 * MIT, this repository.
 */
#include <sys/types.h>
#include <sys/times.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "includes.h"
#include "dbutil.h"
#include "curve25519.h"
#include "mlkem768.h"
#include "sntrup761.h"
#include "dh_groups.h"
#include "rsakeys.h"	/* made by build.sh: throwaway keys */

static long hz;
static long secs = 3;
static int fails;

/* ---- the fixed random stream ------------------------------------------- */
static chacha_state rng;
static void
seed(int n)
{
	unsigned char k[32], iv[8];
	memset(k, 0, sizeof(k));
	memset(iv, 0, sizeof(iv));
	k[0] = (unsigned char)n;
	chacha_setup(&rng, k, 32, 20);
	chacha_ivctr64(&rng, iv, 8, 0);
}
void
genrandom(unsigned char *buf, unsigned int len)
{
	chacha_keystream(&rng, buf, len);
}
void
m_burn(void *data, unsigned int len)
{
	volatile unsigned char *p = data;
	while (len--)
		*p++ = 0;
}
void
dropbear_exit(const char *fmt, ...)
{
	printf("EXIT %s\n", fmt);
	exit(1);
}
void
dropbear_log(int prio, const char *fmt, ...)
{
	(void)prio;
	printf("LOG %s\n", fmt);
}
void *
m_malloc(size_t n)
{
	void *p = calloc(1, n ? n : 1);
	if (!p)
		dropbear_exit("m_malloc");
	return p;
}
void *
m_calloc(size_t a, size_t b)
{
	return m_malloc(a * b);
}
void
m_free_ltm(void *p, size_t n)
{
	(void)n;
	free(p);
}
void *
m_realloc_ltm(void *p, size_t o, size_t n)
{
	(void)o;
	return m_realloc(p, n);
}
/* sntrup761's optimisation blockers (common-algo.c in the program) */
volatile int16_t crypto_int16_optblocker = 0;
volatile int32_t crypto_int32_optblocker = 0;
volatile int64_t crypto_int64_optblocker = 0;
void *m_realloc(void *p, size_t n);
void *
m_realloc(void *p, size_t n)
{
	p = realloc(p, n);
	if (!p)
		dropbear_exit("m_realloc");
	return p;
}

/* a deterministic LTC prng over the same stream */
static int prng_start(prng_state *p) { (void)p; return CRYPT_OK; }
static int prng_add(const unsigned char *in, unsigned long l, prng_state *p) { (void)in; (void)l; (void)p; return CRYPT_OK; }
static int prng_ready(prng_state *p) { (void)p; return CRYPT_OK; }
static unsigned long prng_read(unsigned char *out, unsigned long l, prng_state *p) { (void)p; genrandom(out, l); return l; }
static int prng_done(prng_state *p) { (void)p; return CRYPT_OK; }
static int prng_export(unsigned char *o, unsigned long *l, prng_state *p) { (void)o; (void)l; (void)p; return CRYPT_OK; }
static int prng_import(const unsigned char *i, unsigned long l, prng_state *p) { (void)i; (void)l; (void)p; return CRYPT_OK; }
static int prng_test(void) { return CRYPT_OK; }
static const struct ltc_prng_descriptor fixed_desc = {
	"fixed", 0, prng_start, prng_add, prng_ready, prng_read, prng_done,
	prng_export, prng_import, prng_test
};
static int wprng;
static prng_state ps;

/* ---- reporting ------------------------------------------------------------ */
static long
ticks(void)
{
	struct tms t;
	times(&t);
	return (long)(t.tms_utime + t.tms_stime);
}
static void
kat(const char *name, int ok)
{
	printf("KAT %s %s\n", name, ok ? "ok" : "FAIL");
	if (!ok)
		fails++;
	fflush(stdout);
}
static hash_state dg;
static void dstart(void) { sha256_init(&dg); }
static void dadd(const unsigned char *p, unsigned long n) { sha256_process(&dg, p, n); }
static void
dend(const char *name)
{
	unsigned char h[32];
	int i;
	sha256_done(&dg, h);
	printf("DIGEST %s ", name);
	for (i = 0; i < 32; i++)
		printf("%02x", h[i]);
	printf("\n");
	fflush(stdout);
}
static int
unhex(const char *s, unsigned char *out)
{
	int n = 0;
	unsigned int b;
	while (s[0] && s[1]) {
		sscanf(s, "%2x", &b);
		out[n++] = (unsigned char)b;
		s += 2;
	}
	return n;
}

/* TIME: repeat body until secs of CPU (at least once, at most cap) */
#define TIMEIT(name, cap, body) do {					\
	long _n = 0, _t0 = ticks(), _t;					\
	do { body; _n++; _t = ticks() - _t0; }				\
	while (_t < secs * hz && _n < (cap));				\
	printf("TIME %s %ld %ld %ld\n", name, _n, _t, hz);		\
	fflush(stdout);							\
} while (0)

/* ---- X25519 and Ed25519 ---------------------------------------------- */
static void
t_curve25519(void)
{
	/* RFC 7748 5.2, first vector */
	unsigned char k[32], u[32], out[32], want[32];
	unsigned char a[32], b[32], pa[32], pb[32], sa[32], sb[32];
	unsigned char base[32] = { 9 };
	unhex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4", k);
	unhex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c", u);
	unhex("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552", want);
	dropbear_curve25519_scalarmult(out, k, u);
	kat("x25519-rfc7748", memcmp(out, want, 32) == 0);
	/* RFC 7748 6.1 Diffie-Hellman */
	unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", a);
	unhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb", b);
	dropbear_curve25519_scalarmult(pa, a, base);
	dropbear_curve25519_scalarmult(pb, b, base);
	dropbear_curve25519_scalarmult(sa, a, pb);
	dropbear_curve25519_scalarmult(sb, b, pa);
	unhex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", want);
	kat("x25519-dh-rfc7748", memcmp(sa, want, 32) == 0 && memcmp(sb, want, 32) == 0);
	TIMEIT("x25519", 100000, dropbear_curve25519_scalarmult(out, a, pb));
}

static void
t_ed25519(void)
{
	/* RFC 8032 7.1 TEST 2 (one-byte message) */
	unsigned char sk[64], pk[32], sig[64], want[64], wpk[32];
	unsigned char msg[1] = { 0x72 };
	unsigned char big[256];
	unsigned long slen;
	int i, ok;
	unhex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb", sk);
	unhex("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", wpk);
	unhex("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
	      "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00", want);
	/* Dropbear's secret key is the 32-byte seed, as in RFC 8032 */
	memcpy(pk, wpk, 32);
	dropbear_ed25519_sign(msg, 1, sig, &slen, sk, pk);
	kat("ed25519-sign-rfc8032", slen == 64 && memcmp(sig, want, 64) == 0);
	kat("ed25519-verify-rfc8032", dropbear_ed25519_verify(msg, 1, sig, 64, pk) == 0);
	sig[5] ^= 1;
	kat("ed25519-reject-bad", dropbear_ed25519_verify(msg, 1, sig, 64, pk) != 0);
	/* make_key from the fixed stream; the public key must match the host's */
	seed(2);
	dropbear_ed25519_make_key(pk, sk);
	for (i = 0; i < 256; i++)
		big[i] = (unsigned char)i;
	dropbear_ed25519_sign(big, sizeof(big), sig, &slen, sk, pk);
	ok = dropbear_ed25519_verify(big, sizeof(big), sig, slen, pk) == 0;
	kat("ed25519-roundtrip", ok);
	dstart(); dadd(pk, 32); dadd(sig, 64); dend("ed25519");
	TIMEIT("ed25519-keygen", 100000, dropbear_ed25519_make_key(pk, sk));
	TIMEIT("ed25519-sign", 100000, dropbear_ed25519_sign(big, sizeof(big), sig, &slen, sk, pk));
	TIMEIT("ed25519-verify", 100000, dropbear_ed25519_verify(big, sizeof(big), sig, slen, pk));
}

/* ---- the KEMs ------------------------------------------------------------- */
static unsigned char kpk[2400], ksk[2400], kct[2400], k1[32], k2[32];

static void
t_mlkem(void)
{
	seed(3);
	crypto_kem_mlkem768_keypair(kpk, ksk);
	crypto_kem_mlkem768_enc(kct, k1, kpk);
	crypto_kem_mlkem768_dec(k2, kct, ksk);
	kat("mlkem768-roundtrip", memcmp(k1, k2, 32) == 0);
	kct[10] ^= 1;
	crypto_kem_mlkem768_dec(k2, kct, ksk);
	kat("mlkem768-implicit-reject", memcmp(k1, k2, 32) != 0);
	kct[10] ^= 1;
	dstart();
	dadd(kpk, crypto_kem_mlkem768_PUBLICKEYBYTES);
	dadd(ksk, crypto_kem_mlkem768_SECRETKEYBYTES);
	dadd(kct, crypto_kem_mlkem768_CIPHERTEXTBYTES);
	dadd(k1, 32);
	dend("mlkem768");
	TIMEIT("mlkem768-keygen", 100000, crypto_kem_mlkem768_keypair(kpk, ksk));
	TIMEIT("mlkem768-enc", 100000, crypto_kem_mlkem768_enc(kct, k1, kpk));
	TIMEIT("mlkem768-dec", 100000, crypto_kem_mlkem768_dec(k2, kct, ksk));
}

static void
t_sntrup(void)
{
	seed(4);
	crypto_kem_sntrup761_keypair(kpk, ksk);
	crypto_kem_sntrup761_enc(kct, k1, kpk);
	crypto_kem_sntrup761_dec(k2, kct, ksk);
	kat("sntrup761-roundtrip", memcmp(k1, k2, 32) == 0);
	dstart();
	dadd(kpk, crypto_kem_sntrup761_PUBLICKEYBYTES);
	dadd(ksk, crypto_kem_sntrup761_SECRETKEYBYTES);
	dadd(kct, crypto_kem_sntrup761_CIPHERTEXTBYTES);
	dadd(k1, 32);
	dend("sntrup761");
	TIMEIT("sntrup761-keygen", 1000, crypto_kem_sntrup761_keypair(kpk, ksk));
	TIMEIT("sntrup761-enc", 1000, crypto_kem_sntrup761_enc(kct, k1, kpk));
	TIMEIT("sntrup761-dec", 1000, crypto_kem_sntrup761_dec(k2, kct, ksk));
}

/* ---- diffie-hellman group14 (2048-bit), as kex-dh.c does it ------------- */
static void
t_dh14(void)
{
	mp_int p, g, q, x, y, z;
	unsigned char buf[256];
	mp_init_multi(&p, &g, &q, &x, &y, &z, NULL);
	mp_from_ubin(&p, dh_p_14, DH_P_14_LEN);
	mp_set(&g, 2);
	mp_sub_d(&p, 1, &q);
	mp_div_2(&q, &q);
	seed(5);
	genrandom(buf, sizeof(buf));
	buf[0] &= 0x7f;
	mp_from_ubin(&x, buf, sizeof(buf));
	mp_mod(&x, &q, &x);
	mp_exptmod(&g, &x, &p, &y);
	mp_to_ubin(&y, buf, sizeof(buf), NULL);
	dstart(); dadd(buf, mp_ubin_size(&y)); dend("dh14");
	TIMEIT("dh14-modexp", 100, mp_exptmod(&g, &x, &p, &y));
	mp_clear_multi(&p, &g, &q, &x, &y, &z, NULL);
}

/* ---- RSA (rsa-sha2-256) and ECDSA/ECDH nistp256 ---------------------- */
/* as rsa.c signs (one full exponentiation by d mod n, no CRT) and
 * verifies (by e) */
static void
t_rsa(const char *name, const char *nh, const char *eh, const char *dh)
{
	mp_int n, e, d, m, s, v;
	unsigned char buf[512];
	char nm[64];
	mp_init_multi(&n, &e, &d, &m, &s, &v, NULL);
	mp_read_radix(&n, nh, 16);
	mp_read_radix(&e, eh, 16);
	mp_read_radix(&d, dh, 16);
	memset(buf, 0x5a, 200);
	mp_from_ubin(&m, buf, 200);
	mp_exptmod(&m, &d, &n, &s);
	mp_exptmod(&s, &e, &n, &v);
	snprintf(nm, sizeof(nm), "%s-sign-verify", name);
	kat(nm, mp_cmp(&m, &v) == MP_EQ);
	mp_to_ubin(&s, buf, sizeof(buf), NULL);
	dstart(); dadd(buf, mp_ubin_size(&s)); dend(name);
	snprintf(nm, sizeof(nm), "%s-sign", name);
	TIMEIT(nm, 1000, mp_exptmod(&m, &d, &n, &s));
	snprintf(nm, sizeof(nm), "%s-verify", name);
	TIMEIT(nm, 100000, mp_exptmod(&s, &e, &n, &v));
	mp_clear_multi(&n, &e, &d, &m, &s, &v, NULL);
}

static void
t_ecc(void)
{
	ecc_key a, b;
	unsigned char s1[66], s2[66];
	unsigned long l1 = sizeof(s1), l2 = sizeof(s2);
	const ltc_ecc_set_type *dp = NULL;
	int i;
	for (i = 0; ltc_ecc_sets[i].size; i++)
		if (ltc_ecc_sets[i].size == 32)
			dp = &ltc_ecc_sets[i];
	seed(6);
	ecc_make_key_ex(&ps, wprng, &a, dp);
	ecc_make_key_ex(&ps, wprng, &b, dp);
	ecc_shared_secret(&a, &b, s1, &l1);
	ecc_shared_secret(&b, &a, s2, &l2);
	kat("ecdh-p256-agree", l1 == l2 && memcmp(s1, s2, l1) == 0);
	dstart(); dadd(s1, l1); dend("ecdh-p256");
	TIMEIT("ecdh-p256-keygen", 1000, (ecc_free(&b), ecc_make_key_ex(&ps, wprng, &b, dp)));
	TIMEIT("ecdh-p256-shared", 1000, (l1 = sizeof(s1), ecc_shared_secret(&a, &b, s1, &l1)));
	ecc_free(&a);
	ecc_free(&b);
}

/* ---- bulk: one SSH packet's cipher and MAC ----------------------------- */
static unsigned char pkt[16384 + 64], out[16384 + 64];

static void
bulk(const char *name, int size, void (*one)(int))
{
	long n = 0, t0 = ticks(), t;
	do { one(size); n++; t = ticks() - t0; } while (t < secs * hz);
	printf("BULK %s %d %ld %ld %ld\n", name, size, n * (long)size, t, hz);
	fflush(stdout);
}

static chacha_state cc_main, cc_head;
static unsigned int seqno;
static void
chachapoly_one(int len)
{
	poly1305_state poly;
	unsigned char seqbuf[8], key[32];
	unsigned long taglen = 16;
	STORE64H((ulong64)seqno, seqbuf);
	seqno++;
	chacha_ivctr64(&cc_main, seqbuf, 8, 0);
	chacha_keystream(&cc_main, key, 32);
	poly1305_init(&poly, key, 32);
	chacha_ivctr64(&cc_head, seqbuf, 8, 0);
	chacha_crypt(&cc_head, pkt, 4, out);
	chacha_ivctr64(&cc_main, seqbuf, 8, 1);
	chacha_crypt(&cc_main, pkt + 4, len - 4, out + 4);
	poly1305_process(&poly, out, len);
	poly1305_done(&poly, out + len, &taglen);
}

static symmetric_CTR ctr;
static hmac_state hm;
static unsigned char mackey[64];
static int machash, mackeylen;
static void
ctr_hmac_one(int len)
{
	unsigned char seqbuf[4], tag[64];
	unsigned long tl = sizeof(tag);
	STORE32H(seqno, seqbuf);
	seqno++;
	hmac_init(&hm, machash, mackey, mackeylen);
	hmac_process(&hm, seqbuf, 4);
	hmac_process(&hm, pkt, len);
	hmac_done(&hm, tag, &tl);
	ctr_encrypt(pkt, out, len, &ctr);
}

static gcm_state gcm;
static void
gcm_one(int len)
{
	unsigned char iv[12], tag[16];
	unsigned long tl = 16;
	memset(iv, 0, sizeof(iv));
	STORE32H(seqno, iv + 8);
	seqno++;
	gcm_reset(&gcm);
	gcm_add_iv(&gcm, iv, 12);
	gcm_add_aad(&gcm, pkt, 4);
	gcm_process(&gcm, pkt + 4, len - 4, out + 4, GCM_ENCRYPT);
	gcm_done(&gcm, tag, &tl);
}

static void
t_bulk(void)
{
	unsigned char key[64], iv[16];
	int aes = find_cipher("aes"), i;
	int sizes[2] = { 16384, 64 };
	memset(key, 0x11, sizeof(key));
	memset(iv, 0x22, sizeof(iv));
	memset(pkt, 0x44, sizeof(pkt));
	/* a digest of each mode over fixed data, for the host comparison */
	chacha_setup(&cc_main, key, 32, 20);
	chacha_setup(&cc_head, key + 32, 32, 20);
	seqno = 7;
	chachapoly_one(1024);
	dstart(); dadd(out, 1024 + 16); dend("chachapoly-pkt");
	ctr_start(aes, iv, key, 16, 0, CTR_COUNTER_BIG_ENDIAN, &ctr);
	ctr_encrypt(pkt, out, 1024, &ctr);
	dstart(); dadd(out, 1024); dend("aes128-ctr");
	for (i = 0; i < 2; i++) {
		seqno = 0;
		bulk("chacha20-poly1305", sizes[i], chachapoly_one);
		ctr_start(aes, iv, key, 16, 0, CTR_COUNTER_BIG_ENDIAN, &ctr);
		machash = find_hash("sha256"); mackeylen = 32; memset(mackey, 0x55, 64);
		bulk("aes128-ctr+hmac-sha2-256", sizes[i], ctr_hmac_one);
		ctr_start(aes, iv, key, 32, 0, CTR_COUNTER_BIG_ENDIAN, &ctr);
		bulk("aes256-ctr+hmac-sha2-256", sizes[i], ctr_hmac_one);
		machash = find_hash("sha512"); mackeylen = 64;
		ctr_start(aes, iv, key, 16, 0, CTR_COUNTER_BIG_ENDIAN, &ctr);
		bulk("aes128-ctr+hmac-sha2-512", sizes[i], ctr_hmac_one);
		gcm_init(&gcm, aes, key, 16);
		bulk("aes128-gcm", sizes[i], gcm_one);
	}
}

int
main(int argc, char **argv)
{
	if (argc > 1)
		secs = atol(argv[1]);
	hz = sysconf(_SC_CLK_TCK);
	ltc_mp = ltm_desc;
	register_cipher(&aes_desc);
	register_hash(&sha256_desc);
	register_hash(&sha512_desc);
	wprng = register_prng(&fixed_desc);
	printf("dbbench dropbear-2026.94 small_code=%d hz=%ld secs=%ld\n", BENCH_SMALL, hz, secs);
	/* libtomcrypt's own self tests (built with LTC_TEST) */
	kat("ltc-chacha", chacha_test() == CRYPT_OK);
	kat("ltc-poly1305", poly1305_test() == CRYPT_OK);
	kat("ltc-aes", rijndael_test() == CRYPT_OK);
	{ int e = ctr_test(); if (e != CRYPT_OK) printf("ctr_test: %s\n", error_to_string(e)); kat("ltc-ctr", e == CRYPT_OK || e == CRYPT_NOP); }
	kat("ltc-sha256", sha256_test() == CRYPT_OK);
	kat("ltc-sha512", sha512_test() == CRYPT_OK);
	{	/* RFC 4231 test case 2 */
		unsigned char tag[32], want[32];
		unsigned long tl = 32;
		const char *d = "what do ya want for nothing?";
		unhex("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", want);
		hmac_memory(find_hash("sha256"), (const unsigned char *)"Jefe", 4,
		    (const unsigned char *)d, strlen(d), tag, &tl);
		kat("hmac-sha256-rfc4231", tl == 32 && memcmp(tag, want, 32) == 0);
	}
	t_curve25519();
	t_ed25519();
	t_mlkem();
	t_bulk();
	t_rsa("rsa2048", rsa2048_n, rsa2048_e, rsa2048_d);
	t_rsa("rsa3072", rsa3072_n, rsa3072_e, rsa3072_d);
	t_ecc();
	t_sntrup();
	t_dh14();
	printf("RESULT %s %d\n", fails ? "FAIL" : "PASS", fails);
	return fails != 0;
}
