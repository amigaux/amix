#!/bin/sh
# hosttest.sh -- host test of the monsw module's parameter parser and of the switch semantics
# it feeds (monsw/README.md), without a box.  The shipped monsw/src/monsw.c is compiled with
# -DMONSW_MODULE by the host cc after mechanical substitutions: the two IPL macros become
# counters, the CIA-B PRA/DDRA addresses two bytes of test memory, and the K&R printf
# declaration goes (the test's printf is a prototyped recorder).  Stub
# headers stand in for the kernel's sys/cred.h, sys/ddi.h, sys/conf.h and sys/moddefs.h;
# sys/monsw.h is kernel/modules/include/sys/monsw.h.
#
#   usage: sh monsw/test/hosttest.sh        (HOSTCC overrides cc)
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/inc/sys"

# the substitutions, each required to happen exactly once
sed -e 's|^#define MONSW_PRA .*|#define MONSW_PRA ((long)\&td_pra)|' \
    -e 's|^#define MONSW_DDRA .*|#define MONSW_DDRA ((long)\&td_ddra)|' \
    -e 's|^#define MONSW_SPLTTY(s) .*|#define MONSW_SPLTTY(s) ((s) = 0x2000, td_spl++)|' \
    -e 's|^#define MONSW_SPLX(s) .*|#define MONSW_SPLX(s) ((void)(s), td_spl--)|' \
    -e 's|^extern int printf();$|/* extern int printf(); -- hosttest */|' \
    "$top/monsw/src/monsw.c" > "$tmp/monsw.c"
for m in '#define MONSW_PRA ((long)&td_pra)' '#define MONSW_DDRA ((long)&td_ddra)' \
    '#define MONSW_SPLTTY(s) ((s)' '#define MONSW_SPLX(s) ((void)' '/* extern int printf(); -- hosttest */'; do
	[ "$(grep -cF "$m" "$tmp/monsw.c")" = 1 ] || { echo "hosttest: substitution failed: $m" >&2; exit 1; }
done

cat > "$tmp/inc/sys/cred.h" <<'H'
struct cred { int cr_uid; };
H
: > "$tmp/inc/sys/ddi.h"
cat > "$tmp/inc/sys/conf.h" <<'H'
#ifndef _SYS_CONF_H
#define _SYS_CONF_H
struct bdevsw { int (*d_open)(); int (*d_close)(); int (*d_strategy)(); int (*d_print)(); };
struct cdevsw { int (*d_open)(); int (*d_close)(); int (*d_read)(); int (*d_write)();
	int (*d_ioctl)(); int (*d_mmap)(); };
#endif
H
cat > "$tmp/inc/sys/moddefs.h" <<'H'
struct mod_drv_data {
	struct bdevsw drv_bdevsw; int drv_bmajor, drv_bcount;
	struct cdevsw drv_cdevsw; int drv_cmajor, drv_ccount;
};
struct td_wrapper { int (*load)(); int (*unload)(); void (*halt)(); char *desc; };
#define MOD_DRV_WRAPPER(p, l, u, h, d) struct td_wrapper p##_wrapper = { l, u, h, d }
H

cat > "$tmp/t.c" <<'C'
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>

static unsigned char td_pra, td_ddra;
static int td_spl, td_root = 1, td_nlines;
static char td_lines[4096];
static struct { int f[5]; } td_out;

int td_printf(const char *, ...);
int
td_printf(const char *fmt, ...)
{
	va_list ap;
	size_t n = strlen(td_lines);

	va_start(ap, fmt);
	vsnprintf(td_lines + n, sizeof td_lines - n, fmt, ap);
	va_end(ap);
	td_nlines++;
	return 0;
}
int copyout(void *src, void *dst, int n) { (void)dst; memcpy(&td_out, src, n); return 0; }
int drv_priv(void *crp) { (void)crp; return td_root ? 0 : EPERM; }

#define printf td_printf
#include "monsw.c"
#undef printf

static int fails, checks;

#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; \
	fprintf(stdout, "FAIL line %d: ", __LINE__); fprintf(stdout, __VA_ARGS__); \
	fputc('\n', stdout); } } while (0)

/* a fresh module: the initialisers of monsw.c, as a load gets them */
static void
fresh(unsigned char pra, unsigned char ddra)
{
	int h;

	monsw_config = -1; monsw_setval = -1; monsw_seed = -1; monsw_cfg = 0;
	monsw_src = MONSW_SRC_NONE; monsw_state = -1; monsw_isopen = 0; monsw_want = 0;
	monsw_said = 0;
	for (h = 0; h < MONSW_NCARD; h++)
		monsw_card[h] = 0;
	td_pra = pra; td_ddra = ddra; td_lines[0] = 0; td_nlines = 0; td_root = 1;
}

static int
ioc(int req, int a)
{
	return monswioctl(0, req, a, 0, (struct cred *)0, (int *)0);
}

static int
getcfg(void)
{
	memset(&td_out, 0xff, sizeof td_out);
	return monswioctl(0, MONSWIOC_GETCFG, 0, 0, (struct cred *)0, (int *)0);
}

/* the parser alone: what _load gives monsw_config, and whether it said anything */
static void
p(char *params, int want, int said)
{
	td_lines[0] = 0; td_nlines = 0;
	int v = monsw_cfgparam(params);
	CHECK(v == want, "monsw_cfgparam(\"%s\") = %d, want %d", params ? params : "(0)", v, want);
	CHECK(td_nlines == said, "monsw_cfgparam(\"%s\") printed %d lines, want %d: %s",
	    params ? params : "(0)", td_nlines, said, td_lines);
}

int
main(void)
{
	int h, h2, v;

	/* 1. the parser: C3-1's int form, decimal with an optional '-' */
	p((char *)0, -1, 0);			/* no parameters at all */
	p("", -1, 0);
	p("config=-1", -1, 0);			/* the default kbootset writes */
	p("config=0", 0, 0);
	p("config=34", 34, 0);			/* the owner's boxes */
	p("config=51", 51, 0);
	p("config=-7", -1, 0);			/* any negative = unset */
	p("config=4", 4, 0);			/* not a bit sum: monswinit reports it */
	p("config=99999", 99999, 0);		/* out of range: forced, reported later */
	p("config=123456", 123456, 0);		/* a long decimal is still a decimal */
	p("config=12345678901234", 100000, 0);	/* saturates: no overflow into a valid sum */
	p("x=1 config=2", 2, 0);
	p("config=2 x=1", 2, 0);
	p("  config=3  ", 3, 0);
	p("configx=3", -1, 0);			/* other names */
	p("xconfig=3", -1, 0);
	p("config", -1, 0);
	p("conf=3", -1, 0);
	p("config=", -1, 1);			/* there but not a number: unset, said */
	p("config=3a", -1, 1);
	p("config=-", -1, 1);
	p("config=0x22", -1, 1);
	p("config=--3", -1, 1);
	p("config= 3", -1, 1);

	/* 2. _load with no value: nothing forced, nothing said, no line touched */
	fresh(0xff, 0xc0);
	CHECK(monsw_wrapper.load((char *)0) == 0, "load(0) failed");
	CHECK(monsw_config == -1 && monsw_cfg == 0 && monsw_src == MONSW_SRC_NONE,
	    "load(0): config %d cfg %d src %d", monsw_config, monsw_cfg, monsw_src);
	CHECK(td_nlines == 0, "load(0) printed: %s", td_lines);
	CHECK(td_pra == 0xff && td_ddra == 0xc0, "load(0) touched the port");
	CHECK(getcfg() == 0 && td_out.f[0] == 0 && td_out.f[1] == MONSW_SRC_NONE &&
	    td_out.f[2] == -1 && td_out.f[3] == 0 && td_out.f[4] == 0, "GETCFG after load(0)");

	/* 3. config=34 forces SEL, low = RTG; SETCFG answers EBUSY; the line waits for monsw_set */
	fresh(0xff, 0xc0);
	monsw_wrapper.load("config=34");
	CHECK(monsw_cfg == 34 && monsw_src == MONSW_SRC_PATCH, "load(34): cfg %d src %d",
	    monsw_cfg, monsw_src);
	CHECK(strcmp(td_lines, "monsw: switch value 34 (patched)\n") == 0, "load(34) said: %s", td_lines);
	CHECK(td_pra == 0xff && td_ddra == 0xc0, "load(34) touched the port");
	CHECK(ioc(MONSWIOC_SETCFG, 1) == EBUSY, "SETCFG while forced is not EBUSY");
	monsw_set(1);
	CHECK(td_pra == 0xfb && td_ddra == 0xc4, "RTG with 34: pra %02x ddra %02x", td_pra, td_ddra);
	monsw_set(0);
	CHECK(td_pra == 0xff && td_ddra == 0xc4, "native with 34: pra %02x ddra %02x", td_pra, td_ddra);
	CHECK(td_spl == 0, "IPL raise/restore unbalanced: %d", td_spl);

	/* 4. config=17: CTS, low = RTG */
	fresh(0x00, 0x00);
	monsw_wrapper.load("config=17");
	monsw_set(1);
	CHECK(td_pra == 0x00 && td_ddra == 0x10, "RTG with 17: pra %02x ddra %02x", td_pra, td_ddra);
	monsw_set(0);
	CHECK(td_pra == 0x10 && td_ddra == 0x10, "native with 17: pra %02x ddra %02x", td_pra, td_ddra);

	/* 5. an invalid sum: reported once, taken as 0 (no line touched), SETCFG still EBUSY */
	fresh(0x5a, 0x00);
	monsw_wrapper.load("config=4");
	CHECK(monsw_cfg == 0 && monsw_src == MONSW_SRC_PATCH && monsw_config == 4,
	    "load(4): cfg %d src %d config %d", monsw_cfg, monsw_src, monsw_config);
	CHECK(strcmp(td_lines, "monsw: value 0x4 is not a 1/2/16/32 bit sum; taken as 0\n"
	    "monsw: switch value 0 (patched)\n") == 0, "load(4) said: %s", td_lines);
	CHECK(ioc(MONSWIOC_SETCFG, 2) == EBUSY, "SETCFG after an invalid forced value is not EBUSY");
	td_lines[0] = 0; td_nlines = 0;
	h = monsw_register("card", 34);		/* the seed is ignored: forced wins */
	CHECK(h == 0 && monsw_cfg == 0, "register under a forced value: h %d cfg %d", h, monsw_cfg);
	CHECK(strstr(td_lines, "not a 1/2/16/32") == 0, "invalid value reported twice: %s", td_lines);
	monsw_set(1);
	CHECK(td_pra == 0x5a && td_ddra == 0x00, "value 0 touched the port");

	/* 6. not a number: said once by _load with its text, left unset; SETCFG stays open */
	fresh(0, 0);
	monsw_wrapper.load("x=1 config=0x22 y=2");
	CHECK(monsw_config == -1 && monsw_cfg == 0 && monsw_src == MONSW_SRC_NONE,
	    "load(0x22): config %d cfg %d src %d", monsw_config, monsw_cfg, monsw_src);
	CHECK(strcmp(td_lines, "monsw: config '0x22' is not a number; unset\n") == 0,
	    "load(0x22) said: %s", td_lines);
	CHECK(ioc(MONSWIOC_SETCFG, 34) == 0 && monsw_cfg == 34 && monsw_src == MONSW_SRC_SET,
	    "SETCFG after a non-number: cfg %d src %d", monsw_cfg, monsw_src);
	h = monsw_register("z3660", 1);
	CHECK(monsw_cfg == 34 && ioc(MONSWIOC_SETCFG, -1) == 0 && monsw_cfg == 1 &&
	    monsw_src == MONSW_SRC_SEED, "seed after a non-number: cfg %d src %d", monsw_cfg,
	    monsw_src);
	fresh(0, 0);
	monsw_wrapper.load("config=abcdefghijklmnopqrstuvwxyz");
	CHECK(strcmp(td_lines, "monsw: config 'abcdefghijklmno' is not a number; unset\n") == 0,
	    "a long non-number said: %s", td_lines);

	/* 6b. a long decimal is an invalid bit sum: forced, reported once, taken as 0 */
	fresh(0, 0);
	monsw_wrapper.load("config=123456");
	CHECK(monsw_config == 123456 && monsw_cfg == 0 && monsw_src == MONSW_SRC_PATCH &&
	    ioc(MONSWIOC_SETCFG, 2) == EBUSY, "load(123456): config %d cfg %d src %d",
	    monsw_config, monsw_cfg, monsw_src);
	CHECK(strcmp(td_lines, "monsw: value 0x1e240 is not a 1/2/16/32 bit sum; taken as 0\n"
	    "monsw: switch value 0 (patched)\n") == 0, "load(123456) said: %s", td_lines);

	/* 7. unset: seed from the first card, SETCFG over it, -1 back to the seed; root only */
	fresh(0xff, 0x00);
	monsw_wrapper.load("config=-1");
	h = monsw_register("z3660", 34);
	CHECK(monsw_cfg == 34 && monsw_src == MONSW_SRC_SEED, "seed: cfg %d src %d", monsw_cfg, monsw_src);
	h2 = monsw_register("other", 1);
	CHECK(h2 == 1 && monsw_cfg == 34, "a second seed was taken: cfg %d", monsw_cfg);
	td_root = 0;
	CHECK(ioc(MONSWIOC_SETCFG, 1) == EPERM, "SETCFG by a user is not EPERM");
	td_root = 1;
	CHECK(ioc(MONSWIOC_SETCFG, 4) == EINVAL, "SETCFG 4 is not EINVAL");
	CHECK(ioc(MONSWIOC_SETCFG, 64) == EINVAL, "SETCFG 64 is not EINVAL");
	CHECK(ioc(MONSWIOC_SETCFG, -2) == EINVAL, "SETCFG -2 is not EINVAL");
	CHECK(ioc(MONSWIOC_SETCFG, 1) == 0 && monsw_cfg == 1 && monsw_src == MONSW_SRC_SET,
	    "SETCFG 1: cfg %d src %d", monsw_cfg, monsw_src);
	CHECK(ioc(MONSWIOC_SETCFG, -1) == 0 && monsw_cfg == 34 && monsw_src == MONSW_SRC_SEED,
	    "SETCFG -1: cfg %d src %d", monsw_cfg, monsw_src);
	CHECK(getcfg() == 0 && td_out.f[0] == 34 && td_out.f[1] == MONSW_SRC_SEED &&
	    td_out.f[4] == 2, "GETCFG: %d %d %d %d %d", td_out.f[0], td_out.f[1], td_out.f[2],
	    td_out.f[3], td_out.f[4]);

	/* 8. a value change in RTG state returns the old lines to native first */
	fresh(0x00, 0x00);
	monsw_wrapper.load((char *)0);
	ioc(MONSWIOC_SETCFG, 1);		/* CTS, high = RTG */
	monsw_set(1);
	CHECK(td_pra == 0x10 && td_ddra == 0x10, "RTG with 1: pra %02x ddra %02x", td_pra, td_ddra);
	ioc(MONSWIOC_SETCFG, 2);		/* SEL, high = RTG */
	CHECK(td_pra == 0x04 && td_ddra == 0x14, "1 -> 2 in RTG: pra %02x ddra %02x", td_pra, td_ddra);

	/* 9. the last close: native if its holder asked for RTG; a GETCFG holder leaves it */
	fresh(0x00, 0x00);
	monsw_wrapper.load("config=2");
	monswopen((dev_t *)0, 0, 0, (struct cred *)0);
	ioc(MONSWIOC_RTG, 0);
	CHECK(monsw_state == 1 && td_pra == 0x04, "RTG ioctl: state %d pra %02x", monsw_state, td_pra);
	monswclose(0, 0, 0, (struct cred *)0);
	CHECK(monsw_state == 0 && td_pra == 0x00, "last close after RTG: state %d pra %02x",
	    monsw_state, td_pra);
	monsw_set(1);				/* a card driver's RTG */
	monswopen((dev_t *)0, 0, 0, (struct cred *)0);
	getcfg();
	monswclose(0, 0, 0, (struct cred *)0);
	CHECK(monsw_state == 1, "a GETCFG holder's close took the screen");
	h = monsw_register("rtg", -1);
	monsw_lastclose(h);			/* the card's own last close, no holder */
	CHECK(monsw_state == 0, "monsw_lastclose did not go native");

	/* 10. _unload: EBUSY while a card holds a handle; else native, and config unset */
	monsw_set(1);
	CHECK(monsw_wrapper.unload() == EBUSY, "unload with a card registered is not EBUSY");
	monsw_unregister(h);
	CHECK(monsw_wrapper.unload() == 0 && monsw_state == 0 && td_pra == 0x00 &&
	    monsw_config == -1, "unload: state %d pra %02x config %d", monsw_state, td_pra,
	    monsw_config);

	/* 11. the driver row and the wrapper */
	CHECK(monsw_drvdata[0].drv_cmajor == 52 && monsw_drvdata[0].drv_ccount == 1 &&
	    monsw_drvdata[0].drv_bcount == 0, "drvdata majors");
	CHECK(monsw_drvdata[0].drv_cdevsw.d_open == monswopen &&
	    monsw_drvdata[0].drv_cdevsw.d_close == monswclose &&
	    monsw_drvdata[0].drv_cdevsw.d_read == 0 && monsw_drvdata[0].drv_cdevsw.d_write == 0 &&
	    monsw_drvdata[0].drv_cdevsw.d_ioctl == monswioctl, "drvdata cdevsw row");
	CHECK(monsw_wrapper.halt == 0, "_halt is not the wrapper's 0");
	CHECK(td_spl == 0, "IPL raise/restore unbalanced: %d", td_spl);

	(void)v; (void)h2;
	if (fails) {
		fprintf(stdout, "hosttest: %d of %d checks failed\n", fails, checks);
		return 1;
	}
	fprintf(stdout, "hosttest: ok (%d checks)\n", checks);
	return 0;
}
C
${HOSTCC:-cc} -std=gnu89 -w -DMONSW_MODULE -I"$tmp/inc" -I"$top/include" -I"$tmp" \
	-o "$tmp/t" "$tmp/t.c"
"$tmp/t"
