#!/bin/sh
# hosttest.sh -- host test of the random module (random/README.md) and of its boot step
# randseed, without a box.  The shipped random/src/random.c is compiled by the host cc after
# mechanical substitutions: the three hardware addresses become test memory, and the K&R
# declarations stay.  Stub headers stand in for the kernel's sys/param.h, sys/uio.h,
# sys/cred.h, sys/conf.h, sys/ddi.h, sys/moddefs.h and sys/amixddi.h; the test provides
# lbolt, getminor and uiomove (a recorder that can fail, and can run a second reader while
# the first is "asleep" in it).  The test includes the substituted source, so it sees the
# generator's state.  Then randseed runs under sh with stand-in devices.
#
#   usage: sh random/test/hosttest.sh        (HOSTCC overrides cc)
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/inc/sys"

# the substitutions, each required to happen exactly once
sed -e 's|^#define RAND_VHPOSR.*|#define RAND_VHPOSR ((unsigned long)td_beam)|' \
    -e 's|^#define RAND_CIAA.*|#define RAND_CIAA ((unsigned long)td_ciaa)|' \
    -e 's|^#define RAND_CIAB.*|#define RAND_CIAB ((unsigned long)td_ciab)|' \
    "$top/random/src/random.c" > "$tmp/random.c"
for m in '#define RAND_VHPOSR ((unsigned long)td_beam)' '#define RAND_CIAA ((unsigned long)td_ciaa)' \
    '#define RAND_CIAB ((unsigned long)td_ciab)'; do
	[ "$(grep -cF "$m" "$tmp/random.c")" = 1 ] || { echo "hosttest: substitution failed: $m" >&2; exit 1; }
done

# the hardware it reads: only the timer bytes of each CIA (registers 4-7) and the beam
# counter; never a TOD high byte (0xa00/0xb00: reading latches the counter) or an ICR (0xd00:
# reading clears it)
regs=$(grep -o '[ab]\[0x[0-9a-f]*\]' "$top/random/src/random.c" | sort -u | tr '\n' ' ')
[ "$regs" = "a[0x400] a[0x500] a[0x600] a[0x700] b[0x400] b[0x500] b[0x600] b[0x700] " ] ||
	{ echo "hosttest: the CIA registers read are: $regs" >&2; exit 1; }
grep -q '^#define RAND_VHPOSR	0xdff006' "$top/random/src/random.c" &&
grep -q '^#define RAND_CIAA	0xbfe001' "$top/random/src/random.c" &&
grep -q '^#define RAND_CIAB	0xbfd000' "$top/random/src/random.c" ||
	{ echo "hosttest: the hardware addresses changed" >&2; exit 1; }
# the major: the source's, the keys' and the registry's line (c 48 random, dlm a8719fb)
grep -q '^#define RAND_MAJOR	48' "$top/random/src/random.c" &&
grep -q '^majors=c:48$' "$top/random/module/keys" &&
grep -q '^name=random$' "$top/random/module/keys" &&
grep -q '^unload=never$' "$top/random/module/keys" ||
	{ echo "hosttest: the major, the name or unload differ between random.c and keys" >&2; exit 1; }
echo "hosttest: source: CIA timer bytes and VHPOSR only; c 48 in random.c and keys; unload never"

cat > "$tmp/inc/sys/param.h" <<'H'
H
cat > "$tmp/inc/sys/uio.h" <<'H'
typedef enum uio_rw { UIO_READ, UIO_WRITE } uio_rw_t;
struct uio { char *td_base; int uio_resid; };
int uiomove(caddr_t, long, uio_rw_t, struct uio *);
H
cat > "$tmp/inc/sys/cred.h" <<'H'
struct cred { int cr_uid; };
H
cat > "$tmp/inc/sys/conf.h" <<'H'
struct bdevsw { int (*d_open)(); int (*d_close)(); int (*d_strategy)(); int (*d_print)(); };
struct cdevsw { int (*d_open)(); int (*d_close)(); int (*d_read)(); int (*d_write)();
	int (*d_ioctl)(); int (*d_mmap)(); };
H
cat > "$tmp/inc/sys/ddi.h" <<'H'
unsigned getminor(dev_t);
H
cat > "$tmp/inc/sys/moddefs.h" <<'H'
struct mod_drv_data {
	struct bdevsw drv_bdevsw; int drv_bmajor, drv_bcount;
	struct cdevsw drv_cdevsw; int drv_cmajor, drv_ccount;
};
#define MOD_DRV_WRAPPER(p, load, unload, halt, desc) \
	int (*td_load)(char *) = load; int (*td_unload)(void) = unload; char *td_desc = desc
H
cat > "$tmp/inc/sys/amixddi.h" <<'H'
#define phystokv(paddr) (paddr)
H

cat > "$tmp/test.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>

unsigned short td_beam[1];
unsigned char td_ciaa[0x1000], td_ciab[0x1000];
long lbolt;

unsigned getminor(dev_t d) { return (unsigned)d; }

#include "random.c"

static int checks, td_fail_at = -1, td_calls;
static unsigned td_ctr_at[4096];
static void (*td_nested)(void);

int
uiomove(caddr_t p, long n, uio_rw_t rw, struct uio *u)
{
	if (td_calls < 4096)
		td_ctr_at[td_calls] = rand_ctr;
	if (td_calls++ == td_fail_at)
		return EFAULT;
	if (td_nested) {
		void (*f)(void) = td_nested;
		td_nested = 0;
		f();
	}
	if (rw == UIO_READ)
		memcpy(u->td_base, p, n);
	else
		memcpy(p, u->td_base, n);
	u->td_base += n;
	u->uio_resid -= n;
	return 0;
}

#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); \
	printf(__VA_ARGS__); printf("\n"); exit(1); } checks++; } while (0)

static int
rd(int minor, unsigned char *p, int n)
{
	struct uio u;
	int e;

	u.td_base = (char *)p;
	u.uio_resid = n;
	e = random_drvdata[0].drv_cdevsw.d_read((dev_t)minor, &u, (struct cred *)0);
	return e == 0 && u.uio_resid != 0 ? -1 : e;	/* -1: success, but not all of it */
}

static int
wr(int minor, const void *p, int n)
{
	struct uio u;

	u.td_base = (char *)p;
	u.uio_resid = n;
	return random_drvdata[0].drv_cdevsw.d_write((dev_t)minor, &u, (struct cred *)0);
}

/* the state, saved and put back, so a read can be done twice from the same point */
struct st { r32 key[8], ctr, calls; long lb; };
static void save(struct st *s) { memcpy(s->key, rand_key, 32); s->ctr = rand_ctr; s->calls = rand_calls; s->lb = lbolt; }
static void restore(struct st *s) { memcpy(rand_key, s->key, 32); rand_ctr = s->ctr; rand_calls = s->calls; lbolt = s->lb; }

/* what rand_block gives, as bytes in host order (what a read copies out) */
static void
stream(r32 *key, r32 ctr0, int nblk, unsigned char *out)
{
	r32 b[16];
	int i;

	for (i = 0; i < nblk; i++) {
		rand_block(key, ctr0 + i, 0, 0, 0, b);
		memcpy(out + 64 * i, b, 64);
	}
}

static unsigned char outer[512], inner[256];
static void nested_read(void) { CHECK(rd(1, inner, 256) == 0, "the nested read failed"); }

int
main(int argc, char **argv)
{
	static unsigned char a[70000], b[70000];
	struct st s0, s1;
	r32 k[8], t[16];
	int i, j, n, e, sizes[] = { 1, 3, 4, 16, 63, 64, 65, 255, 256, 257, 1000, 4096, 65536, 70000 };
	dev_t d;
	FILE *f;

	/* 1. the block function: RFC 8439 section 2.3.2 (key 00..1f, counter 1, nonce
	 *    000000090000004a00000000), the state after the 20 rounds plus the input */
	{
		static const r32 want[16] = {
			0xe4e7f110, 0x15593bd1, 0x1fdd0f50, 0xc47120a3,
			0xc7f4d1c7, 0x0368c033, 0x9aaa2204, 0x4e6cd4c3,
			0x466482d2, 0x09aa9f07, 0x05d7c214, 0xa2028bd9,
			0xd19c12b5, 0xb94e16de, 0xe883d0cb, 0x4e3c50a2 };
		for (i = 0; i < 8; i++)
			k[i] = (4*i) | (4*i+1) << 8 | (4*i+2) << 16 | (r32)(4*i+3) << 24;
		rand_block(k, 1, 0x09000000, 0x4a000000, 0, t);
		for (i = 0; i < 16; i++)
			CHECK(t[i] == want[i], "RFC 8439 2.3.2 word %d: %08x, want %08x", i, t[i], want[i]);
	}
	/* the stream for the Python cross-check: key 00..1f, counters 0..3, nonce 0 */
	if (argc > 1 && (f = fopen(argv[1], "wb")) != 0) {
		for (i = 0; i < 4; i++) {
			rand_block(k, i, 0, 0, 0, t);
			for (j = 0; j < 16; j++) {	/* RFC byte order: each word little-endian */
				fputc(t[j] & 0xff, f); fputc(t[j] >> 8 & 0xff, f);
				fputc(t[j] >> 16 & 0xff, f); fputc(t[j] >> 24, f);
			}
		}
		fclose(f);
	}

	/* 2. the row and the minors */
	CHECK(random_drvdata[0].drv_cmajor == 48 && random_drvdata[0].drv_ccount == 1, "row: major %d count %d",
	    random_drvdata[0].drv_cmajor, random_drvdata[0].drv_ccount);
	CHECK(random_drvdata[0].drv_bmajor == 0 && random_drvdata[0].drv_bdevsw.d_open == 0, "a block row");
	CHECK(random_drvdata[0].drv_cdevsw.d_ioctl == 0 && random_drvdata[0].drv_cdevsw.d_mmap == 0, "ioctl or mmap");
	CHECK(td_load("") == 0, "_load");
	for (i = 0; i < 8; i++)
		if (rand_key[i]) break;
	CHECK(i < 8, "_load left the key zero");
	for (n = 0; n < 4; n++) {
		d = (dev_t)n;
		e = random_drvdata[0].drv_cdevsw.d_open(&d, 0, 2, (struct cred *)0);
		CHECK(e == (n < 2 ? 0 : ENXIO), "open minor %d: %d", n, e);
		CHECK(random_drvdata[0].drv_cdevsw.d_close(d, 0, 2, (struct cred *)0) == 0, "close");
	}
	CHECK(rd(2, a, 16) == ENXIO && wr(2, a, 16) == ENXIO, "read or write of minor 2");

	/* 3. a read is ChaCha20 of the key the sample leaves, from counter 0; then the key is
	 *    replaced by a block of the private nonce (fast key erasure), and every 64 KiB within */
	for (i = 0; i < (int)(sizeof sizes / sizeof sizes[0]); i++) {
		n = sizes[i];
		save(&s0);
		memset(a, 0, sizeof a);
		CHECK(rd(i & 1, a, n) == 0, "read %d", n);
		save(&s1);
		restore(&s0);
		rand_stir((r32)n);
		memcpy(k, rand_key, 32);
		j = (n + 63) / 64;
		if (j > RAND_REKEY) {
			stream(k, 0, RAND_REKEY, b);
			rand_block(k, RAND_REKEY, RAND_NKEY, 0, 0, t);
			memcpy(k, t, 32);
			stream(k, 0, j - RAND_REKEY, b + 64 * RAND_REKEY);
			j -= RAND_REKEY;
		} else
			stream(k, 0, j, b);
		CHECK(memcmp(a, b, n) == 0, "read %d is not the stream of the stirred key", n);
		CHECK(a[n] == 0, "read %d wrote past its end", n);
		rand_block(k, j, RAND_NKEY, 0, 0, t);
		CHECK(memcmp(s1.key, t, 32) == 0 && s1.ctr == 0, "read %d: the key after it is not the erasure block", n);
		restore(&s1);
	}
	/* the erasure block is never output: the next counter's block under the output nonce differs */
	rand_block(s0.key, 0, 0, 0, 0, t);
	CHECK(memcmp(t, s1.key, 32) != 0, "the new key equals an output block");

	/* 4. nothing the same twice: frozen hardware and clock, still every read differs */
	memset(td_ciaa, 0x5a, sizeof td_ciaa); memset(td_ciab, 0xa5, sizeof td_ciab); td_beam[0] = 0x1234; lbolt = 1000;
	CHECK(rd(1, a, 64) == 0 && rd(1, b, 64) == 0 && memcmp(a, b, 64) != 0, "two reads gave the same bytes");

	/* 5. every sampled input counts: the same state with one input changed gives another read */
	save(&s0);
	CHECK(rd(1, a, 32) == 0, "read");
#define DIFFERS(what, change, undo) do { restore(&s0); change; CHECK(rd(1, b, 32) == 0, "read"); undo; \
	CHECK(memcmp(a, b, 32) != 0, "%s does not reach the output", what); } while (0)
	DIFFERS("lbolt", lbolt++, lbolt--);
	DIFFERS("VHPOSR", td_beam[0]++, td_beam[0]--);
	for (j = 4; j <= 7; j++) {
		DIFFERS("a CIA-A timer byte", td_ciaa[j << 8]++, td_ciaa[j << 8]--);
		DIFFERS("a CIA-B timer byte", td_ciab[j << 8]++, td_ciab[j << 8]--);
	}
	restore(&s0); CHECK(rd(1, b, 32) == 0 && memcmp(a, b, 32) == 0, "a read from the same state and input differs");
	restore(&s0); CHECK(rd(1, b, 33) == 0 && memcmp(a, b, 32) != 0, "the request size does not reach the output");
	restore(&s0); td_ciaa[0xa00]++; td_ciaa[0xd00]++; td_ciab[0xd00]++;
	CHECK(rd(1, b, 32) == 0 && memcmp(a, b, 32) == 0, "an unread register changed the output");

	/* 6. writes mix in: any written byte changes the next read; its length counts */
	{
		static const char *in[] = { "", "x", "y", "x\0", "seed material of more than one chunk, 40 B" };
		static const int len[] = { 0, 1, 1, 2, 42 };
		unsigned char got[5][32];

		for (i = 0; i < 5; i++) {
			restore(&s0);
			CHECK(wr(i & 1, in[i], len[i]) == 0, "write %d", i);
			CHECK(rd(1, got[i], 32) == 0, "read");
		}
		CHECK(memcmp(got[0], a, 32) == 0, "an empty write changed the state");
		for (i = 1; i < 5; i++)
			for (j = 0; j < i; j++)
				CHECK(memcmp(got[i], got[j], 32) != 0, "writes %d and %d give the same state", i, j);
	}

	/* 7. a failed copy: the error, and the key is still replaced */
	save(&s0);
	td_calls = 0; td_fail_at = 1;
	e = rd(1, a, 1000);
	td_fail_at = -1;
	CHECK(e == EFAULT, "a failed uiomove gave %d", e);
	CHECK(memcmp(rand_key, s0.key, 32) != 0 && rand_ctr == 0, "after a failed read the key stayed");
	td_calls = 0; e = wr(1, "abcdefgh", 8);
	CHECK(e == 0, "write");
	td_calls = 0; td_fail_at = 0; e = wr(1, "abcdefgh", 8); td_fail_at = -1;
	CHECK(e == EFAULT, "a failed write copy gave %d", e);

	/* 8. a second reader while the first sleeps in uiomove: the counter is advanced before
	 *    each copy, and no 64-byte block of either read is in the other */
	td_calls = 0;
	CHECK(rd(1, a, 64 * 9) == 0, "read");
	CHECK(td_calls == 3, "a 576-byte read made %d copies", td_calls);
	CHECK(td_ctr_at[0] == 4 && td_ctr_at[1] == 8 && td_ctr_at[2] == 9,
	    "the counter at the copies: %u %u %u, want 4 8 9", td_ctr_at[0], td_ctr_at[1], td_ctr_at[2]);
	td_calls = 0; td_nested = nested_read;
	CHECK(rd(1, outer, 512) == 0, "the outer read");
	for (i = 0; i < 8; i++)
		for (j = 0; j < 4; j++)
			CHECK(memcmp(outer + 64 * i, inner + 64 * j, 64) != 0, "outer block %d = inner block %d", i, j);

	/* 9. unload: the key goes */
	CHECK(td_unload() == 0, "_unload");
	for (i = 0; i < 8; i++)
		CHECK(rand_key[i] == 0, "_unload left key word %d", i);
	CHECK(strcmp(td_desc, "random numbers /dev/random, /dev/urandom") == 0, "desc");

	/* 10. the output, roughly: 1 MiB, its byte counts, its bits, no repeated 16 bytes */
	{
		static unsigned char big[1 << 20];
		static long cnt[256];
		double chi = 0, x;
		long bits = 0;

		td_load("");
		for (i = 0; i < (1 << 20); i += 4096) {
			lbolt++;
			CHECK(rd(1, big + i, 4096) == 0, "read");
		}
		for (i = 0; i < (1 << 20); i++) {
			cnt[big[i]]++;
			for (j = big[i]; j; j >>= 1)
				bits += j & 1;
		}
		for (i = 0; i < 256; i++) {
			x = cnt[i] - (1 << 20) / 256.0;
			chi += x * x / ((1 << 20) / 256.0);
		}
		CHECK(chi < 370, "chi-square %.1f on 255 degrees (p < 1e-6)", chi);	/* _load's address sample varies with ASLR */
		x = bits / (8.0 * (1 << 20));
		CHECK(x > 0.499 && x < 0.501, "%.4f of the bits set", x);
		printf("hosttest: 1 MiB: chi-square %.1f on 255 degrees, %.4f of the bits set\n", chi, x);
		f = fopen(argc > 2 ? argv[2] : "/dev/null", "wb");
		if (f) { fwrite(big, 1, sizeof big, f); fclose(f); }
	}
	printf("hosttest: module ok (%d checks)\n", checks);
	return 0;
}
C
${HOSTCC:-cc} -std=gnu89 -Wall -Wno-unused-parameter -Wno-unused-function -I"$tmp/inc" -I"$tmp" \
	-o "$tmp/test" "$tmp/test.c" 2> "$tmp/cc.log" || { cat "$tmp/cc.log" >&2; exit 1; }
[ ! -s "$tmp/cc.log" ] || { cat "$tmp/cc.log" >&2; echo "hosttest: compiler warnings" >&2; exit 1; }
"$tmp/test" "$tmp/stream" "$tmp/big"

# the stream against an independent ChaCha20 when the host has one (Python's cryptography)
if python3 -c 'import cryptography' 2>/dev/null; then
	python3 - "$tmp/stream" <<'P'
import sys
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
key = bytes(range(32))
nonce = (0).to_bytes(4, "little") + bytes(12)      # counter 0, nonce 0
ks = Cipher(algorithms.ChaCha20(key, nonce), mode=None).encryptor().update(bytes(256))
got = open(sys.argv[1], "rb").read()
if got != ks:
    sys.exit("hosttest: FAIL: the block stream differs from cryptography's ChaCha20")
print("hosttest: 4 blocks equal to Python cryptography's ChaCha20")
P
else
	echo "hosttest: SKIP: no Python cryptography for the independent ChaCha20 check"
fi
# no repeated 16-byte block in the 1 MiB
r=$(od -An -v -tx1 -w16 "$tmp/big" | sort | uniq -d | wc -l)
[ "$r" = 0 ] || { echo "hosttest: FAIL: $r repeated 16-byte blocks in 1 MiB" >&2; exit 1; }
echo "hosttest: 1 MiB: no repeated 16-byte block"

sh "$top/random/test/rctest.sh"
