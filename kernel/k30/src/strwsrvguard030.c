/*
 * strwsrvguard030.c -- the stream head's write service, with the forward queue's write wait set again when it is
 * full once more.
 *
 * THE BUG.  A queue that drains below its low mark back-enables the queue behind it if QWANTW is set (QB_WANTW for
 * a band), clearing that flag; for a stream head that runs strwsrv with QBACK (QB_BACK) set.  strwsrv takes tq, the
 * next queue forward with a service procedure, and under splstr wakes the writers -- S_WRNORM / POLLWRNORM, per
 * band S_WRBAND / POLLWRBAND -- only if tq (the band) is no longer full.  If it filled again between the
 * back-enable and strwsrv, nothing is woken and nothing sets QWANTW (QB_WANTW) on it again, so its next drain
 * back-enables nobody.  A writer that sleeps in strwrite retries canput, which sets the flag itself; a non-blocking
 * writer waiting in poll sleeps until its poll timeout.  Seen on TCP loopback with 2048-byte socket buffers on both
 * ends and 8192-byte non-blocking writes: a stall in the first of ten repetitions.
 *
 * THE FIX.  The one relocation naming strwsrv, the stream head write qinit's qi_srvp (stwdata), is retargeted to
 * strwsrv_guarded after the final link (tools/strwsrvguard-retarget.py; build-cross-kernel.sh --strwsrv-guard).
 * At splstr, held from before the stock strwsrv to after the re-arm (strwsrv's own splx comes back to this
 * level), it calls strwsrv unchanged, takes tq as strwsrv does, and where q has QBACK and tq is QFULL sets QWANTW
 * on tq; along q's and tq's band lists side by side, where q's band has QB_BACK and tq's band QB_FULL, it sets
 * QB_WANTW on tq's band.  QBACK and QB_BACK are still set on return: queuerun clears them after the service
 * procedure.  A drain that comes later back-enables the stream head again; one that came between strwsrv's test
 * and the re-arm cannot, splstr being held.  The worst a re-arm does is one more back-enable.
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/stream.h>

#undef splstr			/* stream.h's spltty(): the kernel defines the DDI function splstr (sr 0x2400) */
extern int strwsrv();
extern int splstr(), splx();

long swq_magic = 0x53575121;	/* "SWQ!" */
long swq_calls = 0;		/* every strwsrv */
long swq_rearm = 0;		/* QWANTW set on a full tq */
long swq_brearm = 0;		/* QB_WANTW set on a full band of tq */
long swq_last = 0;		/* the last tq re-armed */

int
strwsrv_guarded(q)
	queue_t *q;
{
	queue_t *tq;
	qband_t *qbp, *tqbp;
	int s;

	s = splstr();
	swq_calls++;
	strwsrv(q);
	if ((tq = q->q_next) != 0) {
		while (tq->q_next != 0 && tq->q_qinfo->qi_srvp == 0)
			tq = tq->q_next;
		if ((q->q_flag & QBACK) && (tq->q_flag & QFULL)) {
			tq->q_flag |= QWANTW;
			swq_rearm++;
			swq_last = (long)tq;
		}
		for (qbp = q->q_bandp, tqbp = tq->q_bandp; qbp != 0 && tqbp != 0;
		    qbp = qbp->qb_next, tqbp = tqbp->qb_next)
			if ((qbp->qb_flag & QB_BACK) && (tqbp->qb_flag & QB_FULL)) {
				tqbp->qb_flag |= QB_WANTW;
				swq_brearm++;
				swq_last = (long)tq;
			}
	}
	splx(s);
	return 0;
}
