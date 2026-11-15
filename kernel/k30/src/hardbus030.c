/*
 * hardbus030.c -- the user bus-error probe for a physical address at or above 1 GiB.
 *
 * THE BUG.  usrxmemflt sends a user access that bus-errored on a translation the MMU tables call valid to
 * hardbus(va, pte).  The stock hardbus forms pa = (*pte & ~0x7ff) | (va & 0x7ff) and runs bprobe(pa, -1): a byte
 * read of pa used as a KERNEL VIRTUAL address.  A fault there prints "Hardware Bus Error @ va, (pa physical)" and
 * returns 9, so the process gets SIGKILL (from a kernel copy, EFAULT); no fault returns 0 and the access is retried.
 * That is right only below 0x40000000, where the kernel maps physical memory one-to-one.  From 0x40000000 the
 * kernel's own space is page-mapped (the u-area, then syssegs, then segmap), so for a Zorro III board the probe
 * reads whatever kernel page has the same number and the verdict follows the offset into the board, not the board:
 * a program drawing through a user mapping of a Zorro III framebuffer was killed at random offsets.
 *
 * THE FIX.  usrxmemflt's one call of hardbus is retargeted to hardbus_z3 after the final link
 * (tools/hardbus-retarget.py; build-cross-kernel.sh, --no-hardbus-guard builds without it).  Below 0x40000000
 * hardbus_z3 calls the stock hardbus unchanged.  At or above it, it maps the faulting physical page into the kernel
 * for the probe (sptalloc of one page), reads it there with bprobe, and unmaps it with sptfree(va, 1, 1), whose
 * segkmem_mapout flushes the whole ATC, so a stale entry for the user page goes too.  A probe that faults is a dead
 * device page: the stock warning and 9, as before.  No map space for the probe: a warning and 9, the stock outcome.
 * Otherwise 0, the access is retried; a run of HBG_RETRIES retries by the same process at the same va and pc, each
 * within a second of the last, ends with a warning and 9, so a page that keeps faulting while it reads fine cannot
 * hold a process in a fault loop.
 *
 * The counters are for adb: hbg_magic "HBG!" first, then every call, the calls at or above 1 GiB, the retries
 * granted, the probes that faulted, the probes with no map, the runs that hit the cap, and the last such pa.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/psw.h>
#include <sys/pcb.h>
#include <sys/cmn_err.h>

#define HBG_VSECT1	0x40000000	/* the kernel's one-to-one map ends here */
#define HBG_RETRIES	16		/* retries in a run at one proc, va and pc */
#define HBG_SIGKILL	9		/* what usrxmemflt's callers turn into SIGKILL (from a kernel copy, EFAULT) */
/* the u-area by offset (sys/user.h is not for this compiler); build-cross-kernel.sh checks both against the stock
 * code: u_trap stores u.u_ar0 at u+0x864, usrxmemflt reads u.u_procp at u+0x730 */
#define U_PROCP		(*(caddr_t *)(u + 0x730))
#define U_AR0		(*(struct pcb **)(u + 0x864))

extern int hardbus();			/* the stock probe, kept for every pa below HBG_VSECT1 */
extern int bprobe();
extern caddr_t sptalloc();
extern void sptfree();
extern long lbolt;
extern char u[];

long hbg_magic = 0x48424721;		/* "HBG!" */
long hbg_calls = 0;			/* every call */
long hbg_high = 0;			/* pa at or above HBG_VSECT1 */
long hbg_retry = 0;			/* of those: the probe read the page, the access is retried */
long hbg_kill = 0;			/* of those: the probe faulted, SIGKILL */
long hbg_nomap = 0;			/* of those: no map space for the probe, SIGKILL */
long hbg_cap = 0;			/* of those: HBG_RETRIES retries in a run, SIGKILL */
long hbg_last_pa = 0;			/* the last pa at or above HBG_VSECT1 */

static caddr_t hbg_p = 0;		/* the current run: process, va, pc, length, lbolt of its last fault */
static unsigned long hbg_va = 0, hbg_pc = 0;
static long hbg_n = 0;
static long hbg_t = 0;

int
hardbus_z3(va, pte)
	unsigned long va;
	unsigned long *pte;
{
	unsigned long pa, pc;
	caddr_t kva;
	int dead;

	hbg_calls++;
	pa = (*pte & ~0x7ffUL) | (va & 0x7ffUL);
	if (pa < HBG_VSECT1)
		return hardbus(va, pte);
	hbg_high++;
	hbg_last_pa = pa;
	kva = sptalloc(1, 0, pa >> 11, 0);
	if (kva == 0) {
		hbg_nomap++;
		cmn_err(CE_WARN, "Hardware Bus Error @ %x, (%x physical), no map space to probe it", va, pa);
		return HBG_SIGKILL;
	}
	dead = bprobe(kva + (pa & 0x7ffUL), -1);
	sptfree(kva, 1, 1);
	if (dead) {
		hbg_kill++;
		cmn_err(CE_WARN, "Hardware Bus Error @ %x, (%x physical)", va, pa);
		return HBG_SIGKILL;
	}
	pc = ((unsigned long)U_AR0->pcMSW << 16) | U_AR0->pcLSW;
	if (U_PROCP == hbg_p && va == hbg_va && pc == hbg_pc && lbolt - hbg_t < HZ) {
		if (++hbg_n > HBG_RETRIES) {
			hbg_cap++;
			hbg_p = 0;
			cmn_err(CE_WARN, "Hardware Bus Error @ %x, (%x physical), %d retries", va, pa, HBG_RETRIES);
			return HBG_SIGKILL;
		}
	} else {
		hbg_p = U_PROCP;
		hbg_va = va;
		hbg_pc = pc;
		hbg_n = 1;
	}
	hbg_t = lbolt;
	hbg_retry++;
	return 0;
}
