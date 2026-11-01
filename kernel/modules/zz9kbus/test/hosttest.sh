#!/bin/sh
# hosttest.sh -- host test of the zz9kbus registry (include/zz9kbus.h), without a box.
# The shipped zz9kbus/src/zz9kbus.c is compiled by the host cc with stub headers for the
# kernel's sys/param.h and sys/moddefs.h; the test includes it, so it sees the table.
#
#   usage: sh zz9kbus/test/hosttest.sh        (HOSTCC overrides cc)
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "$tmp/inc/sys"
: > "$tmp/inc/sys/param.h"
cat > "$tmp/inc/sys/moddefs.h" <<'H'
#define MOD_MISC_WRAPPER(p, l, u, d) \
	int (*td_load)(char *) = l; int (*td_unload)(void) = u; char *td_desc = d
H
cp "$top/zz9kbus/src/zz9kbus.c" "$tmp/zz9kbus.c"

cat > "$tmp/t.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/types.h>
#define _KERNEL
#include "zz9kbus.c"

static int checks;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL %s:%d: ", __FILE__, __LINE__); \
	printf(__VA_ARGS__); printf("\n"); exit(1); } checks++; } while (0)

static unsigned rd(char *c, int o) { return 0; }
static void bell(char *c) { }
static int hp(char *c, unsigned long a, unsigned long l, unsigned long *p) { return -1; }

static void
mk(struct zz9kbus_board *b, unsigned long id)
{
	b->zb_version = ZZ9KBUS_VERSION;
	b->zb_unit = -1;
	b->zb_id = id;
	b->zb_boff = 0x400;
	b->zb_bsize = 0x20;
	b->zb_bread = (unsigned (*)())rd;
	b->zb_doorbell = (void (*)())bell;
	b->zb_heapphys = (int (*)())hp;
}

int
main(void)
{
	struct zz9kbus_board a, b, c, bad;

	mk(&a, ZZ9KBUS_ID_Z3660); mk(&b, ZZ9KBUS_ID_ZZ9000_Z3); mk(&c, ZZ9KBUS_ID_ZZ9000_Z2);
	CHECK(td_load("") == 0 && td_unload() == 0, "load/unload with no board");
	CHECK(strcmp(td_desc, "ZZ9000-family board registry") == 0, "desc");

	/* register: units in order, refusals */
	CHECK(zz9kbus_register((struct zz9kbus_board *)0) == EINVAL, "register(0)");
	bad = a; bad.zb_version = 2;
	CHECK(zz9kbus_register(&bad) == EINVAL, "a wrong version");
	bad = a; bad.zb_heapphys = 0;
	CHECK(zz9kbus_register(&bad) == EINVAL, "no zb_heapphys");
	bad = a; bad.zb_bsize = 0;
	CHECK(zz9kbus_register(&bad) == EINVAL, "no bootstrap size");
	CHECK(zz9kbus_register(&a) == 0 && a.zb_unit == 0, "first board: unit %d", a.zb_unit);
	CHECK(zz9kbus_register(&a) == EBUSY, "the same board twice");
	CHECK(zz9kbus_register(&b) == 0 && b.zb_unit == 1, "second board: unit %d", b.zb_unit);
	CHECK(zz9kbus_register(&c) == ENOSPC && c.zb_unit == -1, "third board");
	CHECK(td_unload() == EBUSY, "unload with boards registered");

	/* get / put: holds counted; units outside or empty give 0 */
	CHECK(zz9kbus_get(-1) == 0 && zz9kbus_get(ZZ9KBUS_NUNIT) == 0, "get out of range");
	CHECK(zz9kbus_get(0) == &a && a.zb_hold == 1, "get(0): hold %d", a.zb_hold);
	CHECK(zz9kbus_get(0) == &a && a.zb_hold == 2, "get(0) again: hold %d", a.zb_hold);

	/* unregister while held: EBUSY, the board stays; after the puts it goes */
	CHECK(zz9kbus_unregister(&a) == EBUSY && zz9kbus_tab[0] == &a, "unregister while held");
	zz9kbus_put(&a);
	CHECK(zz9kbus_unregister(&a) == EBUSY, "unregister with one hold left");
	zz9kbus_put(&a);
	CHECK(a.zb_hold == 0, "hold after two puts: %d", a.zb_hold);
	zz9kbus_put(&a);
	CHECK(a.zb_hold == 0, "a put without a get went below 0");
	zz9kbus_put((struct zz9kbus_board *)0);
	CHECK(zz9kbus_unregister(&a) == 0 && a.zb_unit == -1 && zz9kbus_get(0) == 0,
	    "unregister when free");
	CHECK(zz9kbus_unregister(&a) == EINVAL, "unregister twice");
	CHECK(zz9kbus_unregister(&c) == EINVAL, "unregister a board never in");

	/* the freed unit is reused, the other unit untouched */
	CHECK(zz9kbus_register(&c) == 0 && c.zb_unit == 0, "reuse of unit 0: %d", c.zb_unit);
	CHECK(zz9kbus_get(1) == &b, "unit 1 kept its board");
	zz9kbus_put(&b);
	CHECK(zz9kbus_unregister(&b) == 0 && zz9kbus_unregister(&c) == 0, "unregister both");
	CHECK(td_unload() == 0, "unload with the table empty");

	printf("hosttest: ok (%d checks)\n", checks);
	return 0;
}
C
${HOSTCC:-cc} -std=gnu89 -Wall -Wno-unused-function -I"$tmp/inc" -I"$top/include" -I"$tmp" \
	-include string.h -o "$tmp/t" "$tmp/t.c" 2> "$tmp/cc.log" || { cat "$tmp/cc.log" >&2; exit 1; }
[ ! -s "$tmp/cc.log" ] || { cat "$tmp/cc.log" >&2; echo "hosttest: compiler warnings" >&2; exit 1; }
"$tmp/t"
