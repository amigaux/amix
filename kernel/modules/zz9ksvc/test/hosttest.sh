#!/bin/sh
# hosttest.sh -- host test of zz9ksvc (zz9ksvc/README.md), without a box.  The shipped
# zz9ksvc/src/zz9ksvc.c is compiled by the host cc with stub headers for the kernel's and
# stand-ins for the DDI names it calls (timeout and sleep drive a simulated clock), the
# shipped src/wire.c and zz9kbus/src/zz9kbus.c beside it, and test/fw.c as the board's
# runtime: a mailbox in host memory that answers like the firmware, with faults on demand.
# The stub headers are test/stub (zz9ksvc.c's) and test/stub-bus (zz9kbus.c's), the
# stand-ins and the client's calls test/td.h.
# The board is a stub zz9kbus board whose host-visible heap window the test chooses.  It
# runs once with the k30 page size (2 KiB) and once with the k46 one (4 KiB).
#
#   usage: sh zz9ksvc/test/hosttest.sh        (HOSTCC overrides cc)
set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT

cat > "$tmp/t.c" <<'C'
#include "td.h"

int
main(void)
{
	struct zzs_alloc za, zb, zc;
	struct zzs_info zi;
	struct zzs_wait zw;
	struct zzs_stats zt;
	dev_t a, b, c, cl[40];
	long id, id2, ids[8], ck;
	int e, i, h, nlive;
	unsigned long pg = TD_NBPP;

	/* 1. the descriptor checks (wire.c) */
	{
		struct zzw_ring r;
		static const int bad[] = { 1, 2, 3, 4, 5, 6, 7 };

		fw_init(8, 8, 0);
		CHECK(zzw_attach((char *)fw_mbox, FW_MBOXLEN, &r) == 0 && r.r_reqn == 8 &&
		    r.r_cmpoff == 128 + 8 * 64 && r.r_major == 2, "a good descriptor");
		CHECK(zzw_attach((char *)fw_mbox, 100, &r) == ENXIO, "a mapping shorter than the descriptor");
		CHECK(zzw_attach((char *)fw_mbox, 128 + 8 * 64, &r) == EIO, "rings past the mapping");
		CHECK(zzw_attach((char *)0, FW_MBOXLEN, &r) == ENXIO, "no mailbox");
		for (i = 0; i < (int)(sizeof bad / sizeof bad[0]); i++) {
			fw_init(8, 8, 0);
			fw_break(bad[i]);
			e = zzw_attach((char *)fw_mbox, FW_MBOXLEN, &r);
			CHECK(e == (bad[i] <= 3 ? ENXIO : EIO), "broken descriptor %d: %d", bad[i], e);
		}
	}

	/* 2. _load: no board, a board without the magic or a runtime, then a good one */
	CHECK(td_load("") == ENXIO, "_load with no board");
	fw_init(8, 8, 0);
	board_init();
	CHECK(zz9kbus_register(&board) == 0 && board.zb_unit == 0, "register the stub board");
	bread_magic = 0;
	CHECK(td_load("") == ENXIO && board.zb_hold == 0, "a board without the bootstrap magic");
	bread_magic = 1;
	board.zb_mbox = 0;
	CHECK(td_load("") == ENXIO && board.zb_hold == 0, "a board without a runtime");
	board.zb_mbox = (char *)fw_mbox;
	fw_break(1);
	CHECK(td_load("") == ENXIO && board.zb_hold == 0, "a descriptor without the magic");
	fw_init(8, 8, 0);
	CHECK(td_load("") == 0 && board.zb_hold == 1 && zzs_unit[0].u_ready, "_load with the board");
	CHECK(zz9kbus_unregister(&board) == EBUSY, "the board cannot go while zz9ksvc holds it");

	/* 3. opens: clones; unit 1 has no board; a clone minor cannot be opened by name */
	a = op_open(0, &e);
	CHECK(e == 0 && getminor(a) == ZZS_CLONE(0, 0) && getmajor(a) == ZZS_MAJOR, "open: clone %u", getminor(a));
	b = op_open(0, &e);
	CHECK(e == 0 && getminor(b) == ZZS_CLONE(0, 1), "second open: clone %u", getminor(b));
	op_open(1, &e);
	CHECK(e == ENXIO, "open of unit 1, no board: %d", e);
	{
		dev_t x = a;
		CHECK(zz9ksvc_drvdata[0].drv_cdevsw.d_open(&x, 3, 2, (struct cred *)0) == ENXIO,
		    "open of a clone minor");
	}
	td_kmem_fail = 1;
	op_open(0, &e);
	td_kmem_fail = 0;
	CHECK(e == ENOMEM, "open with no kernel memory: %d", e);
	CHECK(ioc(makedevice(ZZS_MAJOR, 0), ZZSIOC_INFO, &zi) == ENXIO, "ioctl on the node itself");

	/* 4. INFO */
	CHECK(ioc(a, ZZSIOC_INFO, &zi) == 0 && zi.zi_unit == 0 && zi.zi_id == (long)ZZ9KBUS_ID_Z3660 &&
	    zi.zi_abimajor == 2 && zi.zi_reqn == 8 && zi.zi_nhandle == 16 && zi.zi_maxout == 4 &&
	    zi.zi_quota == 8L * 1024 * 1024 && zi.zi_used == 0, "INFO");

	/* 5. ALLOC: the firmware is asked page-aligned, page-rounded; cookies; refusals */
	CHECK(op_alloc(a, 1000, 0, &za) == 0 && za.za_handle == 0 && za.za_length == (long)pg &&
	    za.za_cookie == ZZS_COOKIE(0, 0) && fw.last_align == pg && fw.nlive == 1, "ALLOC 1000: %ld %ld %lx",
	    za.za_handle, za.za_length, za.za_cookie);
	CHECK(op_alloc(a, 0, 0, &zb) == EINVAL && op_alloc(a, -5, 0, &zb) == EINVAL &&
	    op_alloc(a, ZZS_QUOTA + 1, 0, &zb) == EINVAL && op_alloc(a, 100, 8, &zb) == EINVAL,
	    "ALLOC refusals: length and flags");
	td_copy_fail = 1;
	CHECK(op_alloc(a, 100, 0, &zb) == EFAULT, "ALLOC with a bad argument");
	td_copy_fail = 0;
	CHECK(op_alloc(a, 100, ZZS_ALLOC_CARDONLY, &zb) == 0 && zb.za_handle == 1 && zb.za_cookie == -1,
	    "a card-only buffer has no cookie");
	CHECK(op_mmap(a, ZZS_COOKIE(1, 0)) == -1, "a card-only buffer does not map");
	/* quota: 8 MiB in all */
	CHECK(op_alloc(a, ZZS_QUOTA - 2 * pg, 0, &zc) == 0 && zc.za_handle == 2, "ALLOC to the quota");
	CHECK(op_alloc(a, pg, 0, &zc) == ENOSPC, "ALLOC past the quota");
	CHECK(ioc(a, ZZSIOC_FREE, (void *)2L) == 0, "FREE the big one");
	drain();
	CHECK(fw.nlive == 2, "the firmware got the FREE: %d live", fw.nlive);
	/* sixteen handles */
	for (h = 2; h < 16; h++)
		CHECK(op_alloc(a, 100, 0, &zc) == 0 && zc.za_handle == h, "ALLOC handle %d", h);
	CHECK(op_alloc(a, 100, 0, &zc) == ENOSPC, "a 17th buffer");
	for (h = 2; h < 16; h++)
		CHECK(ioc(a, ZZSIOC_FREE, (void *)(long)h) == 0, "FREE %d", h);
	CHECK(ioc(a, ZZSIOC_FREE, (void *)2L) == EINVAL && ioc(a, ZZSIOC_FREE, (void *)16L) == EINVAL &&
	    ioc(a, ZZSIOC_FREE, (void *)-1L) == EINVAL, "FREE of a free or impossible handle");
	drain();
	CHECK(fw.nlive == 2, "frees reached the firmware: %d live", fw.nlive);
	/* a buffer the firmware places outside the host-visible window is given back */
	nlive = fw.nlive;
	fw.alloc_outside = 1;
	CHECK(op_alloc(a, 100, 0, &zc) == EIO, "a buffer outside the window");
	fw.alloc_outside = 0;
	drain();
	CHECK(fw.nlive == nlive && ioc(a, ZZSIOC_INFO, &zi) == 0 && zi.zi_used == (long)(2 * pg),
	    "the outside buffer was freed: %d live, %ld used", fw.nlive, zi.zi_used);
	/* the firmware refuses */
	fw.alloc_status = 6;	/* NO_MEMORY */
	CHECK(op_alloc(a, 100, 0, &zc) == ENOMEM, "the firmware has no memory");
	fw.alloc_status = 0;
	/* the firmware does not answer: ETIMEDOUT; the late answer's buffer is given back */
	fw.hold = 1;
	nlive = fw.nlive;
	CHECK(op_alloc(a, 100, 0, &zc) == ETIMEDOUT, "ALLOC timed out");
	fw.hold = 0;
	drain();
	CHECK(fw.nlive == nlive && fw.bad_free == 0, "the late buffer was freed: %d live", fw.nlive);
	/* interrupted: EINTR, and the late buffer is given back too */
	td_signal = 1;
	CHECK(op_alloc(a, 100, 0, &zc) == EINTR, "ALLOC interrupted");
	drain();
	CHECK(fw.nlive == nlive, "the interrupted ALLOC's buffer was freed: %d live", fw.nlive);

	/* 6. mmap by cookie only */
	{
		long base = ZZS_COOKIE(0, 0);
		unsigned long phys = PHYS_BASE + 0;	/* handle 0 is the first buffer */
		int sh = TD_PSHIFT;

		CHECK(op_mmap(a, base) == (int)((phys) >> sh), "mmap handle 0, page 0");
		CHECK(op_mmap(a, base + pg - 2048) == (int)((phys + pg - 2048) >> sh),
		    "mmap at 2 KiB into the page: the same frame on k46");
		CHECK(op_mmap(a, base + pg) == -1, "mmap past the buffer");
		CHECK(op_mmap(a, -1L) == -1 && op_mmap(a, (long)0x80000000UL) == -1, "negative offsets");
		CHECK(op_mmap(a, 0) == -1, "offset 0: no handle");
		CHECK(op_mmap(a, ZZS_COOKIE(0, 1)) == -1, "a wrong generation");
		CHECK(op_mmap(a, (long)(17 << 23)) == -1 && op_mmap(a, ZZS_COOKIE(5, 0)) == -1,
		    "a handle out of range or free");
		CHECK(op_mmap(b, base) == -1, "another open's cookie maps nothing there");
		CHECK(op_mmap(makedevice(ZZS_MAJOR, 0), base) == -1, "the node itself maps nothing");
		/* an unmapped buffer freed and allocated again: the same handle, a new generation, the
		   old cookie dead */
		{
			dev_t x = op_open(0, &e);
			struct zzs_alloc zx;

			CHECK(e == 0 && op_alloc(x, 100, 0, &zx) == 0 && zx.za_handle == 0, "an unmapped buffer");
			nlive = fw.nlive;
			CHECK(ioc(x, ZZSIOC_FREE, (void *)0L) == 0, "FREE it");
			drain();
			CHECK(fw.nlive == nlive - 1, "an unmapped buffer goes back at once: %d live", fw.nlive);
			e = op_alloc(x, 100, 0, &zx);
			CHECK(e == 0 && zx.za_handle == 0 && zx.za_cookie == ZZS_COOKIE(0, 1),
			    "re-ALLOC handle 0: e %d handle %ld cookie %lx", e, zx.za_handle, zx.za_cookie);
			CHECK(op_mmap(x, ZZS_COOKIE(0, 0)) == -1 && op_mmap(x, zx.za_cookie) != -1,
			    "the old cookie is dead");
			CHECK(op_close(x) == 0, "close");
			drain();
		}
	}

	/* 6b. a mapped buffer, freed, is held until the close: the client may still have it
	   mapped, so its pages must not go to anyone else while the open lives */
	{
		dev_t x = op_open(0, &e), y = op_open(0, &e), w;
		struct zzs_alloc zx, zy;
		int px, py, nf, k;

		CHECK(op_alloc(x, 100, 0, &zx) == 0 && (px = op_mmap(x, zx.za_cookie)) != -1, "map a buffer");
		nf = fw.nfree;
		CHECK(ioc(x, ZZSIOC_FREE, (void *)zx.za_handle) == 0, "FREE it, the mapping kept");
		drain();
		CHECK(fw.nfree == nf && zzs_open_of(x)->o_buf[zx.za_handle].b_state == ZB_HELD,
		    "nothing went to the runtime; held");
		CHECK(op_mmap(x, zx.za_cookie) == -1 && op_mmap(x, ZZS_COOKIE(zx.za_handle, 1)) == -1,
		    "a held buffer maps nothing new");
		CHECK(ioc(x, ZZSIOC_FREE, (void *)zx.za_handle) == EINVAL, "a held buffer is freed once");
		CHECK(op_decompress(x, zx.za_handle, 0, 1, zx.za_handle, 0, 1, &id) == EBADF,
		    "a held buffer cannot be used");
		CHECK(ioc(x, ZZSIOC_INFO, &zi) == 0 && zi.zi_used == (long)pg, "its bytes still count");
		/* another client allocates: never the pages x may still have mapped */
		CHECK(op_alloc(y, 100, 0, &zy) == 0 && (py = op_mmap(y, zy.za_cookie)) != -1, "another client");
		CHECK(py != px, "the old mapping never sees the new buffer: frames %d, %d", px, py);
		CHECK(ioc(y, ZZSIOC_FREE, (void *)zy.za_handle) == 0, "free it (held: y mapped it)");
		/* x closes, which specfs does only after its last munmap: the held buffer goes back */
		CHECK(op_close(x) == 0, "close x");
		drain();
		CHECK(fw.nfree == nf + 1, "the held buffer went back at close: %d frees", fw.nfree - nf);
		w = op_open(0, &e);
		CHECK(op_alloc(w, 100, 0, &zx) == 0 && op_mmap(w, zx.za_cookie) == px,
		    "after the close its pages are handed out again");
		CHECK(op_close(w) == 0 && op_close(y) == 0, "close");
		drain();
		/* sixteen buffers mapped and freed: the handles stay taken until the close */
		w = op_open(0, &e);
		nlive = fw.nlive;
		for (k = 0; k < 16; k++)
			CHECK(op_alloc(w, 100, 0, &zx) == 0 && op_mmap(w, zx.za_cookie) != -1 &&
			    ioc(w, ZZSIOC_FREE, (void *)zx.za_handle) == 0, "map and free %d", k);
		CHECK(op_alloc(w, 100, 0, &zx) == ENOSPC, "no handle left while they are held");
		CHECK(op_close(w) == 0, "close");
		drain();
		CHECK(fw.nlive == nlive, "all sixteen went back at close: %d left", fw.nlive - nlive);
	}

	/* 7. SUBMIT: the policy, references, translation */
	CHECK(op_plain(a, fw_op_mem_copy(), &id) == EINVAL, "an opcode not allowed");
	td_root = 0;
	CHECK(op_plain(a, fw_op_module_status(), &id) == EPERM, "a root-only opcode as a user");
	td_root = 1;
	CHECK(op_plain(a, fw_op_module_status(), &id) == 0, "a root-only opcode as root");
	CHECK(op_wait(a, id, 0, &zw) == 0 && zw.zw_status == fw_status_ok(), "its reply");
	{
		struct zzs_submit zs;

		memset(&zs, 0, sizeof zs);
		zs.zs_opcode = fw_op_ping();
		zs.zs_len = 49;
		CHECK(ioc(a, ZZSIOC_SUBMIT, &zs) == EINVAL, "a payload over 48 bytes");
		zs.zs_len = -1;
		CHECK(ioc(a, ZZSIOC_SUBMIT, &zs) == EINVAL, "a negative payload length");
	}
	CHECK(op_alloc(a, 3 * pg, 0, &zc) == 0 && zc.za_handle == 2, "a second mappable buffer");
	ck = zc.za_cookie;
	CHECK(op_decompress(a, 9, 0, 1, 2, 0, 1, &id) == EBADF, "a handle out of range");
	CHECK(op_decompress(a, 3, 0, 1, 2, 0, 1, &id) == EBADF, "a free handle");
	CHECK(op_decompress(b, 0, 0, 1, 2, 0, 1, &id) == EBADF, "another open's handle");
	CHECK(op_decompress(a, 0, pg, 1, 2, 0, 1, &id) == EINVAL, "a range past the source");
	CHECK(op_decompress(a, 0, 1, pg, 2, 0, 1, &id) == EINVAL, "offset + length past the end");
	CHECK(op_decompress(a, 0, 8, 0xfffffffcUL, 2, 0, 1, &id) == EINVAL, "a length that wraps");
	CHECK(op_decompress(a, 0, 0, pg, 2, 0, 3 * pg + 1, &id) == EINVAL, "a destination too small");
	td_doorbells = 0;
	CHECK(op_decompress(a, 0, 0, pg, 2, 16, 3 * pg - 16, &id) == 0 && id != 0, "a good DECOMPRESS");
	CHECK(td_doorbells == 1, "one doorbell");
	CHECK(zzs_unit[0].u_open[0]->o_buf[0].b_busy == 1, "the source is busy");
	CHECK(ioc(a, ZZSIOC_FREE, (void *)0L) == EBUSY, "FREE of a buffer in use");
	CHECK(op_wait(b, id, 0, &zw) == EINVAL, "another open cannot wait for it");
	CHECK(op_wait(a, id + 77, 0, &zw) == EINVAL, "an unknown id");
	CHECK(op_wait(a, id, 0, &zw) == 0 && zw.zw_status == fw_status_ok() && zw.zw_len == 8 &&
	    zw.zw_payload[3] == (1234 & 0xff), "WAIT: status %ld len %ld", zw.zw_status, zw.zw_len);
	/* the firmware saw its own handles, never the client's numbers */
	{
		unsigned long fs = (unsigned long)fw.last_payload[0] << 24 | fw.last_payload[1] << 16 |
		    fw.last_payload[2] << 8 | fw.last_payload[3];
		unsigned long fd = (unsigned long)fw.last_payload[12] << 24 | fw.last_payload[13] << 16 |
		    fw.last_payload[14] << 8 | fw.last_payload[15];

		CHECK(fs == zzs_unit[0].u_open[0]->o_buf[0].b_fwh && fd == zzs_unit[0].u_open[0]->o_buf[2].b_fwh &&
		    fs >= 0x100, "the firmware got handles %lx %lx", fs, fd);
	}
	CHECK(zzs_unit[0].u_open[0]->o_buf[0].b_busy == 0 && fw.not_queued == 0, "released; entries queued");
	CHECK(op_wait(a, id, 0, &zw) == EINVAL, "a request is waited for once");
	/* EINTR leaves the request; it can be waited for again */
	fw.hold = 1;
	CHECK(op_decompress(a, 0, 0, 1, 2, 0, 1, &id) == 0, "submit");
	td_signal = 1;
	CHECK(op_wait(a, id, 0, &zw) == EINTR, "a signal ends the wait");
	fw.hold = 0;
	CHECK(op_wait(a, id, 0, &zw) == 0 && zw.zw_status == fw_status_ok(), "waited again");
	/* four in flight */
	fw.hold = 1;
	for (i = 0; i < 4; i++)
		CHECK(op_plain(a, fw_op_ping(), &ids[i]) == 0, "in flight %d", i);
	CHECK(op_plain(a, fw_op_ping(), &id) == EAGAIN, "a fifth in flight");
	CHECK(op_plain(b, fw_op_ping(), &id2) == 0, "another open has its own four");
	fw.hold = 0;
	for (i = 0; i < 4; i++)
		CHECK(op_wait(a, ids[i], 0, &zw) == 0, "wait %d", i);
	CHECK(op_wait(b, id2, 0, &zw) == 0, "wait in the other open");
	/* a full request ring */
	fw.hold = 1;
	c = op_open(0, &e);
	for (i = 0; i < 4; i++)
		CHECK(op_plain(a, fw_op_ping(), &ids[i]) == 0, "fill %d", i);
	for (i = 0; i < 3; i++)
		CHECK(op_plain(b, fw_op_ping(), &ids[4 + i]) == 0, "fill b %d", i);
	CHECK(op_plain(c, fw_op_ping(), &id) == EAGAIN, "the ring is full: 7 of 8 entries used");
	fw.hold = 0;
	for (i = 0; i < 4; i++)
		CHECK(op_wait(a, ids[i], 0, &zw) == 0, "drain a %d", i);
	for (i = 0; i < 3; i++)
		CHECK(op_wait(b, ids[4 + i], 0, &zw) == 0, "drain b %d", i);
	/* a stray completion is counted and ignored; nothing polls while idle, so it is seen
	   with the next request */
	fw_stray(999999);
	drain();
	zt = stats(a);
	CHECK(zt.zt_stray == 0, "seen while idle");
	CHECK(op_plain(a, fw_op_ping(), &id) == 0 && op_wait(a, id, 0, &zw) == 0, "the next request");
	zt = stats(a);
	CHECK(zt.zt_stray == 1, "stray completions: %ld", zt.zt_stray);

	/* 7b. a real DECOMPRESS through the kernel: the stand-in inflates as the firmware does */
	{
		static unsigned char orig[5000], comp[6000];
		unsigned long algs[3], k, n = 0;
		unsigned char *s, *t;

		algs[0] = fw_alg_raw(); algs[1] = fw_alg_zlib(); algs[2] = fw_alg_gzip();
		for (k = 0; k < sizeof orig; k++)
			orig[k] = (unsigned char)(k * 7 + k / 13);
		CHECK(op_alloc(b, 3 * 2048, 0, &zb) == 0 && op_alloc(b, 3 * 2048, 0, &zc) == 0, "two buffers");
		s = td_map(b, zb.za_cookie, zb.za_length);
		t = td_map(b, zc.za_cookie, zc.za_length);
		CHECK(s && t && s != t, "both map to the heap");
		for (k = 0; k < 3; k++) {
			n = fw_deflate(algs[k], orig, sizeof orig, comp, sizeof comp);
			CHECK(n > 0 && n <= (unsigned long)zb.za_length, "the test stream %lu: %lu bytes", algs[k], n);
			memcpy(s, comp, n);
			memset(t, 0, zc.za_length);
			CHECK(op_inflate(b, zb.za_handle, n, zc.za_handle, zc.za_length, algs[k], &id) == 0 &&
			    op_wait(b, id, 0, &zw) == 0 && zw.zw_status == fw_status_ok() && zw.zw_len == 48,
			    "inflate %lu: status %ld", algs[k], zw.zw_status);
			CHECK(zzw_get32(zw.zw_payload) == n && zzw_get32(zw.zw_payload + 4) == sizeof orig &&
			    zzw_get32(zw.zw_payload + 8) == fw_crc32(orig, sizeof orig) &&
			    memcmp(t, orig, sizeof orig) == 0, "inflate %lu: the bytes and the CRC", algs[k]);
		}
		/* too small a destination; a corrupt stream */
		CHECK(op_inflate(b, zb.za_handle, n, zc.za_handle, 100, algs[2], &id) == 0 &&
		    op_wait(b, id, 0, &zw) == 0 && zw.zw_status == 6, "no room: NO_MEMORY (%ld)", zw.zw_status);
		s[3] ^= 0xff;
		CHECK(op_inflate(b, zb.za_handle, n, zc.za_handle, zc.za_length, algs[2], &id) == 0 &&
		    op_wait(b, id, 0, &zw) == 0 && zw.zw_status == 4, "corrupt: BAD_REQUEST (%ld)", zw.zw_status);
		CHECK(ioc(b, ZZSIOC_FREE, (void *)zb.za_handle) == 0 &&
		    ioc(b, ZZSIOC_FREE, (void *)zc.za_handle) == 0, "free both");
		drain();
	}

	/* 8. timeout and quarantine: the runtime takes the DECOMPRESS and never answers it */
	fw.park_op = fw_op_decompress();
	CHECK(op_decompress(a, 0, 0, pg, 2, 0, 3 * pg, &id) == 0, "submit, held");
	CHECK(op_wait(a, id, 100, &zw) == ETIMEDOUT, "WAIT 100 ms times out");
	zt = stats(a);
	CHECK(zt.zt_quar == 2 && zt.zt_timedout >= 1, "two buffers quarantined: %ld", zt.zt_quar);
	CHECK(op_mmap(a, za.za_cookie) == -1, "a quarantined buffer does not map");
	CHECK(op_decompress(a, 0, 0, 1, 2, 0, 1, &id2) == EBADF, "a quarantined buffer cannot be used");
	CHECK(op_wait(a, id, 0, &zw) == EINVAL, "a timed-out request cannot be waited for");
	nlive = fw.nlive;
	CHECK(ioc(a, ZZSIOC_FREE, (void *)0L) == 0 && fw.nlive == nlive, "FREE of a quarantined buffer waits");
	e = op_alloc(a, 100, 0, &zb);
	CHECK(e == 0 && zb.za_handle == 3, "its slot is not reused: e %d got %ld", e, zb.za_handle);
	fw_unpark();
	drain();
	zt = stats(a);
	CHECK(zt.zt_quar == 0, "the late completion releases the quarantine");
	CHECK(fw.nlive == nlive + 1 && zzs_unit[0].u_open[0]->o_buf[0].b_state == ZB_HELD,
	    "the freed one, mapped before, is held, not given back (handle 3 came): %d live", fw.nlive);
	CHECK(zzs_unit[0].u_open[0]->o_buf[2].b_state == ZB_LIVE && op_mmap(a, ck) != -1,
	    "the other is usable again");
	CHECK(ioc(a, ZZSIOC_FREE, (void *)3L) == 0, "free the extra");

	/* 9. the quarantine cap: quarantined buffers plus the references of requests in flight
	   stay at or below ZZS_NQUAR; a request that could pass it is refused (white box: the
	   ring and request table run out before 32 references could be in flight here) */
	zzs_quar = ZZS_NQUAR - 3;
	fw.park_op = fw_op_decompress();
	CHECK(op_decompress(a, 2, 0, 1, 2, 0, 1, &id) == 0, "2 references with 29 quarantined");
	CHECK(zzs_reserve == 2, "reserved: %d", zzs_reserve);
	CHECK(op_decompress(a, 2, 0, 1, 2, 0, 1, &id2) == EAGAIN, "2 more would pass 32");
	CHECK(op_plain(a, fw_op_ping(), &ids[0]) == 0, "a request without references still goes");
	CHECK(op_wait(a, ids[0], 0, &zw) == 0, "it completes");
	fw_unpark();
	CHECK(op_wait(a, id, 0, &zw) == 0 && zzs_reserve == 0, "released: reserve %d", zzs_reserve);
	zzs_quar = 0;

	/* 10. close: idle buffers freed; buffers in use quarantined, the open kept until released */
	drain();
	cl[0] = op_open(0, &e);
	CHECK(e == 0 && op_alloc(cl[0], 100, 0, &zc) == 0, "alloc");
	CHECK(op_alloc(cl[0], 100, 0, &zc) == 0, "an idle buffer, freed at close");
	fw.park_op = fw_op_decompress();
	CHECK(op_decompress(cl[0], 0, 0, 1, 0, 0, 1, &id) == 0, "a request in flight at close");
	drain();
	{
		int slot = getminor(cl[0]) - ZZS_CLONE(0, 0);

		nlive = fw.nlive;
		CHECK(op_close(cl[0]) == 0, "close with a request in flight");
		CHECK(zzs_unit[0].u_open[slot] != 0 && zzs_unit[0].u_open[slot]->o_closed, "the open stays");
		CHECK(ioc(cl[0], ZZSIOC_INFO, &zi) == ENXIO && op_mmap(cl[0], ZZS_COOKIE(0, 0)) == -1,
		    "a closed open answers nothing");
		drain();
		CHECK(fw.nlive == nlive - 1, "the idle buffer was freed at close: %d live", fw.nlive);
		zt = stats(a);
		CHECK(zt.zt_quar == 1 && zt.zt_opens == 4, "quarantined at close: %ld, opens %ld",
		    zt.zt_quar, zt.zt_opens);
		fw_unpark();
		drain();
		CHECK(zzs_unit[0].u_open[slot] == 0 && fw.nlive == nlive - 2, "released and reaped; %d live", fw.nlive);
	}
	/* the callout is not armed when nothing is pending */
	drain();
	CHECK(zzs_tickid == 0 && callouts() == 0, "no polling when idle");
	zt = stats(a);
	i = zt.zt_polls;
	td_run(50);
	zt = stats(a);
	CHECK(zt.zt_polls == i, "an idle box costs no ticks");

	/* 11. STATS and RESET are root's; RESET forgets the runtime's state */
	td_root = 0;
	CHECK(ioc(a, ZZSIOC_STATS, &zt) == EPERM && ioc(a, ZZSIOC_RESET, 0) == EPERM, "STATS, RESET as a user");
	td_root = 1;
	fw.hold = 1;
	CHECK(op_decompress(a, 2, 0, 1, 2, 0, 1, &id) == 0, "a request in flight at reset");
	CHECK(ioc(a, ZZSIOC_RESET, 0) == 0, "RESET");
	CHECK(op_wait(a, id, 0, &zw) == EIO, "its waiter gets EIO");
	CHECK(zzs_unit[0].u_open[0]->o_buf[2].b_state == ZB_DEAD && op_mmap(a, ck) == -1,
	    "buffers are dead and do not map");
	CHECK(op_decompress(a, 2, 0, 1, 2, 0, 1, &id) == EBADF, "a dead buffer cannot be used");
	nlive = fw.nlive;
	CHECK(ioc(a, ZZSIOC_FREE, (void *)2L) == 0 && fw.nlive == nlive, "FREE of a dead buffer sends nothing");
	zt = stats(a);
	CHECK(zt.zt_quar == 0, "no quarantine after RESET");
	fw.hold = 0;
	drain();
	CHECK(op_plain(a, fw_op_ping(), &id) == 0 && op_wait(a, id, 0, &zw) == 0, "requests work after RESET");

	/* 11b. after a RESET the restarted runtime may place a new buffer over pages a live open
	   still has mapped: ALLOC refuses it, and gives it back, until that open closes */
	{
		dev_t x = op_open(0, &e), y = op_open(0, &e);
		struct zzs_alloc zx, zy;
		unsigned long arm;
		int px, nf;

		CHECK(op_alloc(x, 100, 0, &zx) == 0 && (px = op_mmap(x, zx.za_cookie)) != -1, "x maps a buffer");
		arm = FW_HEAP_ARM + ((unsigned long)px << TD_PSHIFT) - PHYS_BASE;
		fw_restart();
		CHECK(ioc(x, ZZSIOC_RESET, 0) == 0, "the runtime restarted: RESET");
		CHECK(zzs_open_of(x)->o_buf[zx.za_handle].b_state == ZB_DEAD, "x's buffer is dead");
		nf = fw.nfree;
		fw.alloc_at = arm;
		CHECK(op_alloc(y, 100, 0, &zy) == EAGAIN, "a new buffer over x's mapped pages is refused");
		drain();
		CHECK(fw.nfree == nf + 1 && fw.nlive == 0, "and given back to the runtime");
		CHECK(ioc(x, ZZSIOC_FREE, (void *)zx.za_handle) == 0 &&
		    zzs_open_of(x)->o_buf[zx.za_handle].b_state == ZB_HELD, "x frees it: held");
		fw.alloc_at = arm;
		CHECK(op_alloc(y, 100, 0, &zy) == EAGAIN, "still refused while x lives");
		drain();
		CHECK(op_close(x) == 0, "x closes");
		drain();
		CHECK(fw.nfree == nf + 2, "x's buffer, gone with the reset, sends no FREE: %d", fw.nfree - nf);
		fw.alloc_at = arm;
		CHECK(op_alloc(y, 100, 0, &zy) == 0 && op_mmap(y, zy.za_cookie) == px,
		    "after x's close the pages may go to y");
		CHECK(op_close(y) == 0, "close y");
		drain();
	}

	/* 12. unload: refused while opens remain; then the board is given back */
	CHECK(td_unload() == EBUSY, "unload with opens");
	CHECK(op_close(a) == 0 && op_close(b) == 0 && op_close(c) == 0, "close all");
	drain();
	CHECK(td_unload() == 0 && board.zb_hold == 0 && callouts() == 0, "unload; the board given back");
	CHECK(zz9kbus_unregister(&board) == 0, "now the board driver may go");
	CHECK(td_kmem_live == 0, "kernel memory all freed: %d", td_kmem_live);
	CHECK(strcmp(td_desc, "ZZ9000-family service channel /dev/zz9ksvcN") == 0, "desc");
	CHECK(zz9ksvc_drvdata[0].drv_cmajor == 55 && zz9ksvc_drvdata[0].drv_cdevsw.d_read == 0 &&
	    zz9ksvc_drvdata[0].drv_cdevsw.d_mmap != 0, "the cdevsw row");

	printf("hosttest: page %lu: ok (%d checks)\n", pg, checks);
	return 0;
}
C

# the major, the name and the class agree between zz9ksvc.c and keys; the interface header
# carries no GPL text
grep -q '^#define ZZS_MAJOR	55' "$top/zz9ksvc/src/zz9ksvc.c" &&
grep -q '^majors=c:55$' "$top/zz9ksvc/module/keys" &&
grep -q '^name=zz9ksvc$' "$top/zz9ksvc/module/keys" &&
grep -q '^depend=zz9kbus$' "$top/zz9ksvc/module/keys" ||
	{ echo "hosttest: the major, name or depend differ between zz9ksvc.c and keys" >&2; exit 1; }
! grep -qi 'GPL\|General Public' "$top/include/sys/zz9kbus.h" ||
	{ echo "hosttest: include/sys/zz9kbus.h carries GPL text" >&2; exit 1; }
grep -q 'MIT licence' "$top/include/sys/zz9kbus.h" ||
	{ echo "hosttest: include/sys/zz9kbus.h has no MIT notice" >&2; exit 1; }
# only src/wire.c and test/fw.c include the SDK headers
inc=$(grep -l 'zz9k/abi.h' "$top"/zz9ksvc/src/*.c "$top"/zz9ksvc/src/*.h "$top"/zz9ksvc/test/*.c | xargs -n1 basename | sort | tr '\n' ' ')
[ "$inc" = "fw.c wire.c " ] || { echo "hosttest: SDK headers included by: $inc" >&2; exit 1; }
echo "hosttest: source: c 55 in zz9ksvc.c and keys; zz9kbus.h MIT; SDK headers only in wire.c"

for p in 2048:11 4096:12; do
	nbpp=${p%:*} shift=${p#*:}
	cc="${HOSTCC:-cc} -std=gnu89 -w -DTD_NBPP=$nbpp -DTD_PSHIFT=$shift"
	$cc -c -I"$top/zz9ksvc/sdk" -I"$top/zz9ksvc/src" -o "$tmp/wire.o" "$top/zz9ksvc/src/wire.c"
	$cc -c -I"$top/zz9ksvc/sdk" -I"$top/zz9ksvc/test" -o "$tmp/fw.o" "$top/zz9ksvc/test/fw.c"
	$cc -c -D_KERNEL -I"$top/zz9ksvc/test/stub-bus" -I"$top/include" -o "$tmp/bus.o" "$top/zz9kbus/src/zz9kbus.c"
	$cc -I"$top/zz9ksvc/test/stub" -I"$top/include" -I"$top/zz9ksvc/include" -I"$top/zz9ksvc/src" \
	    -I"$top/zz9ksvc/test" -o "$tmp/t" "$tmp/t.c" "$tmp/wire.o" "$tmp/fw.o" "$tmp/bus.o" -lz \
	    2> "$tmp/cc.log" || { cat "$tmp/cc.log" >&2; exit 1; }
	(cd "$top/zz9ksvc/src" && "$tmp/t")
done
