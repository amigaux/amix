/*
 * coreseg030.c -- a core dump passes over the pages its process may not read (tools/segvnprot-retarget.py).
 *
 * Stock core_seg writes each run as_memory finds with one vn_rdwr from the process's addresses and stops at the first
 * error, and elfcore then gives up: a truncated file and no core flag in the status.  A PROT_NONE page now gives EFAULT,
 * where stock spun for ever in the kernel, so one guard page would end the dump.  Here a run is divided by as_getprot, and
 * a page with no permission at all is not written: it stays a hole, which reads back as zeros, and no blocks go on a large
 * PROT_NONE reservation.  A write-only page can be read (src/segvnprot030.s), so it is written.  A failed write would not do
 * instead, since ufs allocates before it copies and could leave old disk bytes in the file.  When a run ends denied its last
 * byte is written from the kernel, so that the file reaches the length elfcore's program header gives.  Any error on what is written ends the dump, as stock: an I/O failure, a full
 * disk and the core limit are not denied pages.
 *
 * elfcore's and the other callers' relocations name this function; the stock body stays, unused.  Same arguments and calls
 * as the stock body.  p_as is at +124 of struct proc.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/errno.h>

#define	CS_PAGE		2048L
#define	CS_P_AS		124
#define	CS_WRITE	1		/* enum uio_rw, as the stock body pushes it */
#define	CS_USER		0		/* enum uio_seg */
#define	CS_KERNEL	1
#define	CS_PROT		7		/* PROT_READ, PROT_WRITE, PROT_EXEC */

extern int as_memory(), as_getprot(), vn_rdwr();

long core_holes = 0;			/* runs of pages left as holes, since boot */

int
core_seg_holes(p, vp, offset, addr, size, rlimit, cr)
	caddr_t p, vp, addr, cr;
	long offset, rlimit;
	u_int size;
{
	static char zero;		/* never written: a shared source of one zero byte */
	caddr_t as = *(caddr_t *)(p + CS_P_AS), base = addr, eaddr = addr + size, a, end, next;
	u_int len;
	int err, prot, denied;

	while (base < eaddr) {
		len = eaddr - base;
		if (as_memory(as, &base, &len) != 0)
			break;
		end = base + len;
		denied = 0;
		for (a = base; a < end; a = next) {
			/* as_getprot steps by pages from what it is given, so give it the page's start */
			prot = as_getprot(as, (caddr_t)((u_int)a & ~(CS_PAGE - 1)), &next);
			if (next > end)
				next = end;
			denied = (prot & CS_PROT) == 0;
			if (denied) {
				core_holes++;
				continue;
			}
			err = vn_rdwr(CS_WRITE, vp, a, next - a, offset + (a - addr), CS_USER, 0, rlimit, cr, (int *)0);
			if (err)
				return err;
		}
		if (denied) {
			err = vn_rdwr(CS_WRITE, vp, &zero, 1, offset + (end - addr) - 1, CS_KERNEL, 0, rlimit, cr, (int *)0);
			if (err)
				return err;
		}
		base = end;
	}
	return 0;
}
