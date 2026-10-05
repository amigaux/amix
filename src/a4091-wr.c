/* SPDX-License-Identifier: MIT */
/*
 * a4091.c -- Commodore A4091 (Zorro III / NCR 53C710) SCSI host adapter for Amix.
 *
 * PHASE 2: real SCSI.  Detection (phase 1) proved the kernel can sptalloc-map the
 * Zorro III window (board @ phys 0x40000000, inside the 68030 TT GAP) and read the
 * 53C710 registers (CTEST8 high nibble = chip rev).  This phase drives the chip:
 * soft-reset + init, then a minimal SELECT + INQUIRY to a target via the 53C710
 * SCRIPTS engine, returning the 36-byte INQUIRY response (the first proof Amix can
 * talk to the drive *behind* the A4091).
 *
 * a4091queue() is reached via the GSIO raw-SCSI passthrough (/dev/scsi).  The caller
 * supplies cp->cdb (the CDB, e.g. INQUIRY 12 00 00 00 24 00), cp->unit (target id),
 * cp->addr (result buffer).  We run the transaction and fill cp->addr with the
 * INQUIRY data followed by diagnostics.
 *
 * 53C710 facts for the A4091 (cross-checked vs A4091/a4091-software siop.c):
 *   - register file at board+0x800000; READS at reg+0x00, WRITES at reg+0x40 (shadow).
 *   - 8/32-bit accesses only, never 16-bit.  big-endian byte lanes.
 *   - soft reset = ISTAT bit6 (0x40), NOT self-clearing.
 *   - SCID is a one-hot id bitmask (1<<7 = 0x80 for host id 7).
 *   - DMODE=0xE0 (burst8|FC2, A4091), DCNTL=0x00 (Zorro, CF=SCLK/2 @50MHz).
 *   - CTEST8 |= SM(0x01) bus-arbitration errata workaround (A4091-specific).
 * DMA model on the 68030 line, AS MEASURED IN EMULATION ONLY: kvtop()==identity
 * (kernel VA==PA via 68030 TT0), data cache off (Amiberry cpu_data_cache=false),
 * so a static array's address is the bus address the chip DMAs to -- no
 * translation, no cache flush (matches a2091.c).  That "no flush" holds for the
 * 030 build under emulation; it has never run on real hardware, and it is NOT the
 * 040/060 rule.
 *
 * 040/060 ARM (-DA4091_KVA, the driver line; the 030 build is byte-identical
 * without it): the board is found only through autocon() via the sd.c rows
 * (sdcardbase() returns the recorded base, no 0x40000000 fallback); both pages
 * are mapped with dev_kvmap(.., 0x1000, NCS, NOSLEEP) (sptalloc would give a
 * cacheable page there); a dead window or a NULL map is a clean "no board";
 * every transfer goes through the D42 prepare/complete seam (a4091_dmarec.h,
 * docs/D42-CALL-SHAPE.md); a misaligned FROM_DEVICE range of at most 1 KB is
 * bounced through a 16-aligned driver buffer (D42 "Bounce"); a4091_bytewrite_probe
 * (off by default) measures U77.
 *
 * Refs: reference/a4091-study.md (init recipe, SCRIPTS, DSA layout, done-detection),
 *       reference/a4091-software/siop.c + siop_script.ss (53C710 / ARCH_710).
 */
#include	"sys/types.h"
#include	"sys/immu.h"		/* PG_V, phystopfn, paddr_t */
#include	"sys/errno.h"
#include	"rico.h"
#include	"sd.h"
#ifdef	A4091_KVA
#include	"sys/inline.h"		/* _spl7()/splx(): the bprobe windows */
#include	"a4091_dmarec.h"	/* the D42 seam: record + prepare/complete */
#endif

#define	A4091_PROD	0x02020054	/* AutoConfig: Commodore(0x0202) product 0x54 */
#define	SIOP_OFF	0x00800000	/* 53C710 register block within the board window */
#define	WRSHADOW	0x40		/* A4091 write-shadow: writes go to reg+0x40 */

/* 53C710 register offsets (native, ARCH_710; read at +0, write at +WRSHADOW) */
#define	R_SIEN		0x00
#define	R_SCNTL1	0x02
#define	R_SCNTL0	0x03
#define	R_SCID		0x07
#define	R_SBCL		0x08
#define	R_SSTAT2	0x0C		/* ro; low bits = live SCSI phase (MSG/CD/IO) */
#define	R_SSTAT1	0x0D		/* ro: SCSI status reg 1 (FIFO flags/parity) */
#define	R_SSTAT0	0x0E
#define	R_DSTAT		0x0F
#define	R_DSA		0x10		/* 32-bit */
#define	R_CTEST1	0x16		/* ro: FIFO flags (FMT high nibble = DMA FIFO empty) */
#define	R_CTEST0	0x17
#define	R_CTEST7	0x18
#define	R_TEMP		0x1C		/* 32-bit */
#define	R_CTEST8	0x21		/* high nibble = chip rev; SM/CLF FIFO controls */
#define	R_ISTAT		0x22
#define	R_DFIFO		0x23		/* rw: DMA FIFO byte-offset counter (low 7 bits) */
#define	R_DBC		0x24		/* 32-bit DCMD:DBC; byte count = low 24 bits */
#define	R_DSP		0x2C		/* 32-bit; writing it starts SCRIPTS */
#define	R_DSPS		0x30		/* 32-bit; INT code lands here */
#define	R_SCRATCH	0x34		/* 32-bit scratch (for write self-test) */
#define	R_DCNTL		0x38
#define	R_DWT		0x39
#define	R_DIEN		0x3A
#define	R_DMODE		0x3B

/* register bits */
#define	ISTAT_ABRT	0x80
#define	ISTAT_RST	0x40
#define	ISTAT_SIP	0x02
#define	ISTAT_DIP	0x01
#define	DSTAT_SIR	0x04		/* SCRIPTS INT instruction */
#define	SSTAT0_M_A	0x80		/* phase mismatch (or ATN active) (siopreg.h:402) */
#define	SSTAT0_STO	0x20		/* selection timeout */
#define	SSTAT1_ORF	0x40		/* output reg (sodr) still full (siopreg.h:425) */
#define	SSTAT1_OLF	0x20		/* output latch (sodl) still full (siopreg.h:426) */
#define	CTEST1_FMT	0xf0		/* DMA FIFO "byte empty" flags; ==0xf0 -> empty (siopreg.h:483) */
#define	CTEST8_CLF	0x04		/* clear DMA + SCSI FIFOs (not self-clearing) (siopreg.h:595) */

#define	HOST_ID		7

extern caddr_t	sptalloc();
extern int	printf();
extern char	*sdcardbase();		/* sd.c: phys base recorded for a card */

/*
 * Per-card register mappings, indexed by the sd-layer card number (cp->card).
 * a4091map() maps each board's two sub-regions once and caches them here, then
 * points the current-card view (acfg/siop/board_phys) at the requested card --
 * so an A4091 and an A4092/A4770 can be driven at the same time.  The RD/WR
 * macros and the SCRIPTS launch all work through the current-card view.
 */
static volatile uchar	*acfg_tbl[SDCARDS];	/* board base page per card       */
static volatile uchar	*siop_tbl[SDCARDS];	/* 53C710 register block per card */
static long		phys_tbl[SDCARDS];	/* board phys base per card       */

static volatile uchar	*acfg;		/* current card: board base page (AutoConfig regs) */
static volatile uchar	*siop;		/* current card: 53C710 register block (read base)  */
static long		board_phys;	/* current card: board phys base                    */

/* register accessors -- reads at +0, writes at +WRSHADOW; 8/32-bit only */
#define	RD8(r)		(siop[(r)])
#define	WR8(r,v)	(siop[(r)+WRSHADOW] = (uchar)(v))
#define	RD32(r)		(*(volatile ulong *)(siop + (r)))
#define	WR32(r,v)	(*(volatile ulong *)(siop + (r) + WRSHADOW) = (ulong)(v))

/*
 * The minimal table-indirect INQUIRY SCRIPTS (based on reference/scripts/inq-wr.ss,
 * assembled by ncr53cxxx; now 23 instructions / 184 bytes).  DSPS result vectors:
 * ok=0xff00, err5(unexpected phase)=0xff05, seltimeout=0xff10.  Static array =>
 * lives in kernel .data => bus address == &inq_script[0] (TT0 identity).
 *
 * The phase-dispatch block at byte offset SCRIPT_DISPATCH (0x30, just after the
 * CMD MOVE) fans out on the LIVE bus phase.  It is ALSO the re-entry point the
 * DATA_IN short-read recovery re-launches (see a4091queue): re-dispatching there
 * on the live phase drains STATUS + MSG_IN to a clean INT 0xff00.
 *
 * NOTE: hand-patched relative to the generated reference/scripts/inq-wr.out to add
 * a "JUMP msgin, WHEN MSG_IN" dispatch case (a non-STATUS post-data phase must not
 * fall to err_phase on real HW).  reference/scripts/inq-wr.ss is now stale and
 * should be regenerated to match in a follow-up (out of scope here).  All relative
 * displacements below were recomputed for the +1-instruction (8-byte) insertion.
 */
#define	SCRIPT_DISPATCH	0x30		/* byte offset of the phase-dispatch block */

static ulong inq_script[] = {		/* READ+WRITE: DATA phase dispatches on live bus phase */
	0x47000000, 0x000000a8,		/* 0x00 SELECT ATN FROM ds_Device, REL(seltimeout) */
	0x86830000, 0x00000098,		/* 0x08 JUMP err_phase, WHEN NOT MSG_OUT           */
	0x1e000004, 0x00000004,		/* 0x10 MOVE FROM ds_MsgOut, WHEN MSG_OUT (IDENTIFY)*/
	0x82830000, 0x00000088,		/* 0x18 JUMP err_phase, WHEN NOT CMD               */
	0x60000008, 0x00000000,		/* 0x20 CLEAR ATN                                  */
	0x1a00000c, 0x0000000c,		/* 0x28 MOVE FROM ds_Cmd, WHEN CMD                 */
	0x808b0000, 0x00000020,		/* 0x30 datadisp: JUMP dataout, WHEN DATA_OUT (wr) */
	0x818b0000, 0x00000028,		/* 0x38 JUMP datain,  WHEN DATA_IN   (read)        */
	0x838b0000, 0x00000028,		/* 0x40 JUMP status_phase, WHEN STATUS (no data)   */
	0x878b0000, 0x00000030,		/* 0x48 JUMP msgin,   WHEN MSG_IN (non-STATUS drain)*/
	0x80880000, 0x00000050,		/* 0x50 JUMP err_phase               (unexpected)  */
	0x1800003c, 0x0000003c,		/* 0x58 dataout: MOVE FROM ds_Data1, WHEN DATA_OUT */
	0x80880000, 0x00000008,		/* 0x60 JUMP status_phase                          */
	0x1900003c, 0x0000003c,		/* 0x68 datain:  MOVE FROM ds_Data1, WHEN DATA_IN  */
	0x83830000, 0x00000030,		/* 0x70 status_phase: JUMP err_phase, WHEN NOT STATUS*/
	0x1b000014, 0x00000014,		/* 0x78 MOVE FROM ds_Status, WHEN STATUS           */
	0x87830000, 0x00000020,		/* 0x80 msgin: JUMP err_phase, WHEN NOT MSG_IN     */
	0x1f00001c, 0x0000001c,		/* 0x88 MOVE FROM ds_Msg, WHEN MSG_IN              */
	0x60000040, 0x00000000,		/* 0x90 CLEAR ACK                                  */
	0x48000000, 0x00000000,		/* 0x98 WAIT DISCONNECT                            */
	0x98080000, 0x0000ff00,		/* 0xa0 INT ok                                     */
	0x98080000, 0x0000ff05,		/* 0xa8 err_phase: INT err5                        */
	0x98080000, 0x0000ff10,		/* 0xb0 seltimeout: INT 0xff10                     */
};

/*
 * The data structure the SCRIPTS read via DSA (mirror of siop_ds, siopvar.h:56-76).
 * Each {len,ptr} pair is 8 bytes; scsi_addr is a lone selector word at offset 0.
 * All longwords big-endian, pointers are bus addresses (identity).
 */
static struct siop_ds {
	ulong	scsi_addr;		/* 0x00  (1<<(16+target)) | (sxfer<<8) */
	ulong	idlen;    uchar	*idbuf;		/* 0x04 ds_MsgOut (IDENTIFY) */
	ulong	cmdlen;   uchar	*cmdbuf;	/* 0x0c ds_Cmd     (CDB)     */
	ulong	stslen;   uchar	*stsbuf;	/* 0x14 ds_Status            */
	ulong	msglen;   uchar	*msgbuf;	/* 0x1c ds_Msg     (cmd-cmpl)*/
	ulong	msginlen; uchar	*msginbuf;	/* 0x24 ds_MsgIn             */
	ulong	extmsglen;uchar	*extmsgbuf;	/* 0x2c ds_ExtMsg            */
	ulong	synmsglen;uchar	*synmsgbuf;	/* 0x34 ds_SyncMsg           */
	ulong	data1len; uchar	*data1buf;	/* 0x3c ds_Data1  (INQUIRY)  */
	ulong	data2len; uchar	*data2buf;	/* 0x44 ds_Data2  (chain end)*/
} ds;

static uchar	ident_buf[4];
static uchar	cdb_buf[12];
static uchar	datain_buf[36];
static uchar	status_buf[4];
static uchar	msg_buf[8];

/* last-transaction diagnostics (data path goes straight to cp->addr now) */
ulong	a4091_dsps;
ulong	a4091_resid;		/* DATA_IN short-read FIFO/odd-byte residue (real HW; 0 in emu) */
uchar	a4091_rc, a4091_istat, a4091_dstat, a4091_stat;

/*
 * "A4091 slow" console threshold, in ISTAT polls (A4-21).  Under emulation the
 * DMA is instant (poll == 0), but on metal every command spins while the chip
 * works, so the old poll > 0 gate printed one line per I/O.  The default is 1/8
 * of the 8,000,000 poll bound: one Zorro III ISTAT read costs roughly 0.3-1 us,
 * so it fires only past ~0.3-1 s, far above a healthy command (a few ms, a few
 * thousand polls).  Patchable (.data / kmem); 0 restores the poll > 0 gate.
 * a4091_maxpoll is the high-water poll count, kmem-readable, to calibrate it.
 */
ulong	a4091_slow_poll = 1000000;
ulong	a4091_maxpoll;

#ifdef	A4091_KVA
/*
 * ---------------------------------------------------------------------------
 * 040/060 driver-line arm.  Nothing below exists in the 030 build.
 * ---------------------------------------------------------------------------
 *
 * Provided by the port's relink, not by stock AMIX:
 *   dev_kvmap(phys, nbytes, cm, flags) / dev_kvunmap(kva, nbytes)
 *                    -- src/devkvmap040.s; cm 0x40 = NCS, flags bit 0 = NOSLEEP.
 *   sdcardbase(card) -- the sd.c shim PO-04 adds: the base autocon() recorded.
 * Stock:
 *   bprobe(addr, v)  -- one byte through u_nofault: v < 0 reads, else writes
 *                       the low byte of v; 0 = no fault, 1 = bus error caught.
 */
extern char	*dev_kvmap();
extern void	dev_kvunmap();
extern int	bprobe();

#define	A4091_CM_NCS	0x40		/* noncacheable, serialised: control registers */
#define	A4091_NOSLEEP	1		/* runs from the boot-time sd bus scan */
#define	A4091_MAPLEN	0x1000		/* one page each: AutoConfig page, 53C710 page */

/*
 * Patchable knobs (.data; poke the kernel image before boot, or /dev/kmem).
 *   a4091_bytewrite_probe  nonzero: run the U77 byte-write probe at attach (and
 *                          once per card on the next I/O if poked at runtime).
 *                          OFF by default: a refused write that the line's
 *                          u_nofault pad does not catch is a panic.
 *   a4091_dma_off       nonzero: the D42 service sees off != 0 in the record,
 *                          counts, and does no cache op (DL-02's control arm).
 */
long	a4091_bytewrite_probe = 0;
long	a4091_dma_off = 0;

/*
 * The per-controller D42 record: owned by THIS object (D42 as amended), one per
 * sd card, filled in at attach.  Layout and field ownership: a4091_dmarec.h.
 */
struct dma_rec	a4091_dmarec[SDCARDS];

/*
 * Driver-side counters, kmem-readable, magic first ("A4K2"; "A4K1" had no bounce
 * fields).  Never panic:
 * every refusal on this arm lands here and in one console line.
 *   bw_mask[card]: 0x80000000 = probe ran; bits 0-3 write fault per SCRATCH lane,
 *                  bits 4-7 read fault, bits 8-11 read-back mismatch.
 */
struct a4091_kstat {
	ulong	magic;			/* 0x41344b32 "A4K2", static                */
	ulong	d42_linked;		/* 0 = local stubs, 1 = dma_* linked      */
	ulong	nobase;			/* sdcardbase() == 0: autocon found nothing  */
	ulong	mapfail;		/* dev_kvmap() returned NULL                 */
	ulong	deadwin;		/* first-touch read of the 53C710 faulted    */
	ulong	attached;		/* cards mapped and accepted                 */
	ulong	stub_prep;		/* stub prepare calls (no cache op!)         */
	ulong	stub_cmpl;		/* stub complete calls (no cache op!)        */
	ulong	bw_runs;		/* U77 probe runs                            */
	ulong	bw_ok;			/* lanes written + read back equal           */
	ulong	bw_wfault;		/* lanes whose byte WRITE faulted            */
	ulong	bw_rfault;		/* lanes whose byte READ faulted             */
	ulong	bw_mismatch;		/* lanes read back different                 */
	ulong	bw_refused;		/* attaches refused on a failed probe        */
	ulong	bw_mask[SDCARDS];	/* per card, see above                       */
	ulong	bounce_n;		/* FROM_DEVICE transfers bounced (misaligned) */
	ulong	bounce_toolong;		/* misaligned FROM_DEVICE > 1 KB: refused    */
};
struct a4091_kstat	a4091_kstat = {
	0x41344b32,
#ifdef	A4091_D42
	1,
#else
	0,
#endif
};

static uchar	a4091_nobrd[SDCARDS];	/* "no board" latched: stay quiet after */

/*
 * The bounce (docs/D42-CALL-SHAPE.md "Bounce").  A FROM_DEVICE range whose pa or
 * pa+len is off a 16-byte line shares an edge line with unrelated bytes; such a
 * range (GSIO's iobuf, dd's 16-byte sense) is DMA'd here instead and copied out
 * after dma_complete.  Static .bss in this object, never a stack buffer; its
 * address is its bus address by the same kernel-.data identity the DSA table
 * (&ds) already relies on.  One buffer serves every card: a4091queue runs one
 * command at a time to completion (polled, no sleep, shared ds/cdb_buf) and the
 * copy-out finishes before the sd callback can re-enter.
 */
#define	A4091_BOUNCE_MAX	1024		/* GSIO's ceiling; sense is 16 */
/* +16: room to start on a 16-byte line AND to round the service length up to
 * whole lines (<= 15 + 1024 bytes used). */
static uchar	a4091_bounce[A4091_BOUNCE_MAX + 16];

#ifndef	A4091_D42
/*
 * STUBS until the collaborator's side of the seam exists (docs/D42-CALL-SHAPE.md).
 * They do NO cache maintenance and leave the record's service fields alone; they
 * only count, so the call sites are exercised and visible.  A kernel carrying
 * them is coherent only with the data cache off (every emulated cell today) and
 * says so once at attach.
 */
static int
dma_prepare( r, pa, len, dir)
struct dma_rec	*r;
ulong	pa, len;
int	dir;
{
	a4091_kstat.stub_prep++;
	return 1;			/* not PREPARED: nothing owns the segment */
}

static void
dma_complete( r, pa, len, dir)
struct dma_rec	*r;
ulong	pa, len;
int	dir;
{
	a4091_kstat.stub_cmpl++;
}
#endif	/* !A4091_D42 */

/*
 * The two call sites, by physical line.  sdcom.addr is physical by contract on
 * this line; the direction is the sd client's `reading` flag (dd.c/ct.c set it,
 * GSIO takes it from the caller).  A zero-length transfer (TEST UNIT READY) moves
 * no data: no call, one count.
 */
static void
a4091_dma_prepare( card, pa, len, dir)
int	card;
ulong	pa, len;
int	dir;
{
	struct dma_rec	*r;

	r = &a4091_dmarec[card];
	if (len == 0) {
		r->drv_zero++;
		return;
	}
	r->off = (ulong)a4091_dma_off;
	r->drv_prep++;
	(void)dma_prepare( r, pa, len, dir);
}

static void
a4091_dma_complete( card, pa, len, dir)
int	card;
ulong	pa, len;
int	dir;
{
	struct dma_rec	*r;

	r = &a4091_dmarec[card];
	if (len == 0)
		return;
	r->drv_cmpl++;
	dma_complete( r, pa, len, dir);
}

/*
 * One byte through bprobe's u_nofault pad.  u_nofault belongs to the u-area, and
 * interrupt code runs on the same u-area: an interrupt taking a legitimate fault
 * inside the window would land on OUR pad.  So the window is masked (IPL 7; a
 * handful of instructions).  1 = the access faulted.
 */
static int
a4091_probe8( a, v)
volatile uchar	*a;
int	v;
{
	int	s, f;

	s = _spl7();
	f = bprobe( (caddr_t)a, v);
	splx( s);
	return f;
}

/*
 * U77 -- can this board, through this bridge, take a single-byte WRITE at an odd
 * offset of a Zorro III register window?  ISSUE-65 (port) saw a byte write to a
 * Zorro III register window refused at an odd address and never settled board
 * firmware vs bridge; the 53C710 is byte-addressed and this driver writes odd
 * registers (SCNTL0 0x03, SCID 0x07, DWT 0x39, DMODE 0x3B, ...) on every I/O.
 * The probe writes each byte lane of SCRATCH (0x34-0x37: two even, two odd; no
 * side effect while SCRIPTS is idle) through the write shadow, reads it back
 * through the read side, every access through bprobe, and records the lanes.
 * Returns the number of failed lanes.
 */
static int
a4091_bwprobe( card, s)
int	card;
volatile uchar	*s;
{
	int	b, bad;
	uchar	v, r;
	ulong	m;
	volatile uchar	*rd;

	a4091_kstat.bw_runs++;
	bad = 0;
	m = 0x80000000;
	for (b = 0; b < 4; ++b) {
		rd = s + R_SCRATCH + b;
		v  = (uchar)(0xA5 ^ (b << 4) ^ b);	/* distinct per lane */
		if (a4091_probe8( rd + WRSHADOW, (int)v)) {
			a4091_kstat.bw_wfault++;
			m |= (ulong)1 << b;
			bad++;
			continue;
		}
		if (a4091_probe8( rd, -1)) {
			a4091_kstat.bw_rfault++;
			m |= (ulong)1 << (4 + b);
			bad++;
			continue;
		}
		r = *rd;
		if (r != v) {
			a4091_kstat.bw_mismatch++;
			m |= (ulong)1 << (8 + b);
			bad++;
			continue;
		}
		a4091_kstat.bw_ok++;
	}
	a4091_kstat.bw_mask[card] = m;
	printf("a4091: card %d: U77 byte-write probe: %d/4 lanes ok (mask 0x%x)\n",
	    card, 4 - bad, (int)m);
	return bad;
}

/*
 * First map of a card on the driver line.  0 = mapped and accepted, ENXIO = no
 * board (latched: later calls return ENXIO without a word).  Nothing here may
 * panic: the sd bus scan calls this for every card slot at boot.
 */
static int
a4091attach( card)
int	card;
{
	long	base;
	volatile uchar	*a, *s;
	struct dma_rec	*r;

	if (a4091_nobrd[card])
		return ENXIO;

	/* D49: autocon() via the sd.c row is the ONLY discovery; no fixed address */
	base = (long)sdcardbase( card);
	if (base == 0) {
		a4091_kstat.nobase++;
		a4091_nobrd[card] = 1;
		printf("a4091: card %d: no board (autocon recorded no base)\n", card);
		return ENXIO;
	}

	/* permanent NCS pages, like va2000_map_regs: never sptalloc on this line */
	a = (volatile uchar *)dev_kvmap( base, A4091_MAPLEN, A4091_CM_NCS, A4091_NOSLEEP);
	s = (volatile uchar *)dev_kvmap( base + SIOP_OFF, A4091_MAPLEN, A4091_CM_NCS, A4091_NOSLEEP);
	if (a == 0 || s == 0) {
		if (a) dev_kvunmap( (char *)a, A4091_MAPLEN);
		if (s) dev_kvunmap( (char *)s, A4091_MAPLEN);
		a4091_kstat.mapfail++;
		a4091_nobrd[card] = 1;
		printf("a4091: card %d: cannot map board at 0x%x: no board\n", card, (int)base);
		return ENXIO;
	}

	/* first touch of the window: ISTAT (no read side effect) through u_nofault;
	 * a dead window must degrade to "no board", not a kernel bus error (U62) */
	if (a4091_probe8( s + R_ISTAT, -1)) {
		dev_kvunmap( (char *)a, A4091_MAPLEN);
		dev_kvunmap( (char *)s, A4091_MAPLEN);
		a4091_kstat.deadwin++;
		a4091_nobrd[card] = 1;
		printf("a4091: card %d: bus error at 0x%x: no board\n", card, (int)(base + SIOP_OFF));
		return ENXIO;
	}

	/* U77, before anything else writes a byte to the chip */
	if (a4091_bytewrite_probe && a4091_bwprobe( card, s) != 0) {
		dev_kvunmap( (char *)a, A4091_MAPLEN);
		dev_kvunmap( (char *)s, A4091_MAPLEN);
		a4091_kstat.bw_refused++;
		a4091_nobrd[card] = 1;
		printf("a4091: card %d: byte writes refused: board not usable\n", card);
		return ENXIO;
	}

	/* the D42 record: identity fields now, before the first transfer */
	r = &a4091_dmarec[card];
	r->magic   = DMA_REC_MAGIC;
	r->version = DMA_REC_VERSION;
	r->ctlid   = A4091_PROD;	/* the driver family's id, not the board's */
	r->unit    = (ulong)card;
	r->off     = (ulong)a4091_dma_off;

	acfg_tbl[card] = a;
	siop_tbl[card] = s;
	phys_tbl[card] = base;
	a4091_kstat.attached++;
	printf("a4091: card %d: board at 0x%x, NCS pages, D42 seam %s\n", card, (int)base,
	    a4091_kstat.d42_linked ? "linked" : "STUB (no cache maintenance)");
	return 0;
}
#endif	/* A4091_KVA */

/*
 * Map one card's two safe sub-regions (AutoConfig page + 53C710 window) into
 * kernel VA and select it as the current card.  Each card is mapped once and
 * cached in the per-card tables; the base comes from sd.c (sdcardbase), which
 * recorded what autocon returned for that board -- so this is product-agnostic
 * (A4091 / A4092 / A4770 all map by whatever base the sd layer assigned).
 * 0 on success, errno else.
 */
static int
a4091map( card)
int	card;
{
	long	base;

	if (card < 0 || card >= SDCARDS)
		return ENXIO;

#ifdef	A4091_KVA
	if (siop_tbl[card] == 0) {		/* first request for this card: attach it */
		int	e;

		if (e = a4091attach( card))
			return e;
	} else if (a4091_bytewrite_probe && a4091_kstat.bw_mask[card] == 0)
		(void)a4091_bwprobe( card, siop_tbl[card]);	/* poked at runtime: record only */
#else
	if (siop_tbl[card] == 0) {		/* first request for this card: map it */
		base = (long)sdcardbase( card);
		if (base == 0)
			base = 0x40000000;	/* last-resort guard (A4091 phys base) */
		acfg_tbl[card] = (volatile uchar *)sptalloc( 1, PG_V, phystopfn( (paddr_t)base), 0);
		siop_tbl[card] = (volatile uchar *)sptalloc( 1, PG_V, phystopfn( (paddr_t)base + SIOP_OFF), 0);
		if (acfg_tbl[card] == 0 || siop_tbl[card] == 0) {
			acfg_tbl[card] = 0;
			siop_tbl[card] = 0;
			return ENOMEM;
		}
		phys_tbl[card] = base;
	}
#endif

	/* select this card as current for the RD/WR macros + SCRIPTS launch */
	acfg = acfg_tbl[card];
	siop = siop_tbl[card];
	board_phys = phys_tbl[card];
	return 0;
}

/*
 * 53C710 soft reset + minimal polled-mode init (subset of siopreset, siop.c:800-826).
 * No SCSI/DMA interrupts (we poll).  The SCSI bus reset is a4091_busreset(), once
 * per card (A4-22).
 */
static void
a4091init()
{
	WR8( R_ISTAT,  RD8(R_ISTAT) | ISTAT_ABRT);	/* abort any running script */
	WR8( R_ISTAT,  RD8(R_ISTAT) | ISTAT_RST);	/* soft reset...            */
	WR8( R_ISTAT,  RD8(R_ISTAT) & ~ISTAT_RST);	/* ...clear (not self)      */
	WR8( R_SIEN,   0x00);
	WR8( R_SCNTL0, 0xCC);				/* ARB_FULL|EPC|EPG         */
	WR8( R_SCNTL1, 0x20);				/* ESR enable sel/resel     */
	WR8( R_DCNTL,  0x00);				/* CF=SCLK/2 @50MHz, no EA   */
	WR8( R_DMODE,  0xE0);				/* burst8|FC2 (A4091)       */
	WR8( R_SIEN,   0x00);
	WR8( R_DIEN,   0x00);
	WR8( R_SCID,   1 << HOST_ID);			/* one-hot host id (0x80)   */
	WR8( R_DWT,    0x00);
	WR8( R_CTEST0, RD8(R_CTEST0) | 0x50);		/* BTD|EAN                  */
	WR8( R_CTEST7, RD8(R_CTEST7) | 0x80);		/* CDIS                     */
	WR8( R_CTEST8, RD8(R_CTEST8) | 0x01);		/* SM errata (A4091)        */
	{ uchar i = RD8(R_ISTAT);			/* clear stale latched ints */
	  if (i & ISTAT_SIP) (void)RD8(R_SSTAT0);
	  if (i & ISTAT_DIP) (void)RD8(R_DSTAT); }
}

/*
 * SCSI bus reset, once per card, before its first command (A4-22).  The board's
 * AmigaOS ROM may have negotiated synchronous transfer with a target (A4091/A4092
 * DIP SW6 Off); a target keeps that agreement until a bus reset, while this
 * driver always runs asynchronous (SXFER never written, no SDTR).  The soft reset
 * in a4091init() resets the chip only, not the bus.
 *
 * Timed by the beam counter, not a CPU loop: the high byte of VHPOSR (0xDFF006)
 * changes once per scanline (63.5 us NTSC, 64 us PAL) on every CPU, while the
 * stock drv_usecwait is a dbf loop sized for the 030.  RST is held for 2 line
 * changes (>= 1 full line, > the 25 us minimum), then 4000 line changes give
 * >= 254 ms (> the 250 ms reset-to-selection time).  Each wait is bounded in
 * reads so a stuck counter cannot hang the boot (a4091_busreset_to counts it).
 * The first command to each target afterwards gets CHECK CONDITION / UNIT
 * ATTENTION (6/29): dd senses and retries once (one "blk" console line), ct's
 * open starts with REQUEST SENSE, GSIO returns status 2 once to its caller.
 *   a4091_busreset     patchable; 0 skips the reset (the pre-A4-22 behaviour)
 *   a4091_busreset_n   resets done;  a4091_busreset_to  line waits that timed out
 *   a4091_rearm_n      resets re-armed by a stuck command (see a4091queue)
 */
#define	SCNTL1_ESR	0x20		/* enable selection/reselection */
#define	SCNTL1_RST	0x08		/* assert SCSI RST (siopreg.h:278) */
#define	SBCL_BSY	0x20		/* live SCSI BSY (siopreg.h:367) */
#define	VHPOSR		0xDFF006	/* custom: V7..V0 in the high byte */
#define	RST_HOLD_LINES	2
#define	RST_SETTLE_LINES 4000
#define	LINE_READ_BOUND	200000		/* reads per line change before giving up */

long	a4091_busreset = 1;
ulong	a4091_busreset_n;
ulong	a4091_busreset_to;
ulong	a4091_rearm_n;
static uchar	a4091_rstdone[SDCARDS];

static void
a4091_lines( n)
ulong	n;
{
	ulong	seen, reads;
	uchar	v, w;

	seen = 0;
	v = (uchar)(*(volatile ushort *)VHPOSR >> 8);
	while (seen < n) {
		reads = 0;
		w = v;
		while (w == v && reads < LINE_READ_BOUND) {
			w = (uchar)(*(volatile ushort *)VHPOSR >> 8);
			reads = reads + 1;
		}
		if (w == v) {
			a4091_busreset_to++;
			return;
		}
		v = w;
		seen = seen + 1;
	}
}

static void
a4091_busreset_card( card)
int	card;
{
	a4091_rstdone[card] = 1;
	if (!a4091_busreset)
		return;
	a4091init();
	WR8( R_SCNTL1, SCNTL1_ESR | SCNTL1_RST);
	a4091_lines( (ulong)RST_HOLD_LINES);
	WR8( R_SCNTL1, SCNTL1_ESR);
	a4091_lines( (ulong)RST_SETTLE_LINES);
	{ uchar i = RD8(R_ISTAT);			/* the RST raised SSTAT0 RST */
	  if (i & ISTAT_SIP) (void)RD8(R_SSTAT0);
	  if (i & ISTAT_DIP) (void)RD8(R_DSTAT); }
	a4091_busreset_n++;
}

/*
 * Generic SCSI queue entry.  Drives ANY CDB from the caller's sdcom (cp->cdb,
 * cp->nbyte, cp->addr) through the 53C710 SCRIPTS -- mirrors a3091queue.  CDB
 * length is derived from the opcode group code; data DMAs straight into cp->addr
 * (identity VA==PA).  READ path (DATA_IN) only; writes (DATA_OUT) need a SCRIPTS
 * branch (deferred).  Completion is now a BOUNDED ISTAT poll (a finite spin that
 * still exits for a silent/absent target -- this path is shared with the boot-time
 * SCSI bus scan, so it must not hang on an empty id).  The old "a poll loop breaks
 * the kernel boot" claim is retired: NOTES.md S18 traced the boot-breaker to an
 * intermittent (~70%) ld file-write corruption, independent of the poll loop and
 * mitigated by a build-until-stable clean gate.
 */
bool
a4091queue( c, cp)
int		c;
struct sdcom	*cp;
{
	ulong	dsps, poll;
	uchar	istat, dstat, sstat0;
	int	e, i, rc, target, cmdlen, recovered;
#ifdef	A4091_KVA
	int	dmadir, bounced;
	ulong	dpa, dlen;
#endif

	if (e = a4091map( cp->card)) {
		cp->status = 0xff; cp->okay = FALSE;
		(*cp->intr)( cp);
		return TRUE;
	}
	if (!a4091_rstdone[cp->card])
		a4091_busreset_card( (int)cp->card);

#ifdef	A4091_KVA
	/* The DMA target: the caller's buffer, or the bounce for a misaligned
	 * FROM_DEVICE range.  TO_DEVICE never bounces (no op at complete, no edge). */
	dmadir = cp->reading ? DMA_FROM_DEVICE : DMA_TO_DEVICE;
	dpa = (ulong)cp->addr;
	dlen = (ulong)cp->nbyte;
	bounced = 0;
	if (dmadir == DMA_FROM_DEVICE && cp->nbyte > 0
	    && ((dpa | (dpa + (ulong)cp->nbyte)) & 15) != 0) {
		if ((ulong)cp->nbyte > A4091_BOUNCE_MAX) {
			a4091_kstat.bounce_toolong++;
			printf("A4091 c%d: misaligned read of %d bytes refused (bounce max %d)\n",
			    (int)cp->card, (int)cp->nbyte, A4091_BOUNCE_MAX);
			cp->status = 0xff; cp->okay = FALSE;
			(*cp->intr)( cp);
			return TRUE;
		}
		dpa = ((ulong)a4091_bounce + 15) & ~(ulong)15;
		/* Service length rounded UP to whole lines: both edges then sit on
		 * our own aligned buffer, so edge_shared cannot count.  The SCSI
		 * length (ds.data1len) stays the caller's.  Clear it first: the
		 * prepare's cpushl writes the zeros back, so a command that moves
		 * fewer bytes than asked (TUR via GSIO) copies out zeros, never a
		 * previous command's bytes.  The exact count is not known here. */
		dlen = ((ulong)cp->nbyte + 15) & ~(ulong)15;
		{
			uchar	*bz;
			ulong	bi;

			bz = (uchar *)dpa;
			bi = 0;
			while (bi < dlen) {
				bz[bi] = 0;
				bi = bi + 1;
			}
		}
		bounced = 1;
		a4091_kstat.bounce_n++;
	}
#endif

	a4091init();

	target = (int)cp->unit;

	/* CDB length from SCSI group code (top 3 bits of opcode): 0->6, 5->12, else 10 */
	cmdlen = ((cp->cdb[0] >> 5) & 7) == 0 ? 6
	       : ((cp->cdb[0] >> 5) & 7) == 5 ? 12 : 10;

	ident_buf[0] = 0x80;				/* IDENTIFY, no disconnect */
	for (i = 0; i < 12; ++i) cdb_buf[i] = cp->cdb[i];
	status_buf[0] = 0xff;
	for (i = 0; i < 8; ++i) msg_buf[i] = 0xff;

	/* DSA table -- command + data bound to the caller's sdcom */
	ds.scsi_addr = (ulong)0x10000 << target;
	ds.idlen = 1;        ds.idbuf     = ident_buf;
	ds.cmdlen = cmdlen;  ds.cmdbuf    = cdb_buf;
	ds.stslen = 1;       ds.stsbuf    = status_buf;
	ds.msglen = 1;       ds.msgbuf    = &msg_buf[0];
	ds.msginlen = 1;     ds.msginbuf  = &msg_buf[1];
	ds.extmsglen = 1;    ds.extmsgbuf = &msg_buf[2];
	ds.synmsglen = 1;    ds.synmsgbuf = &msg_buf[3];
#ifdef	A4091_KVA
	ds.data1len = cp->nbyte;  ds.data1buf = (uchar *)dpa;	/* caller buf or bounce */
#else
	ds.data1len = cp->nbyte;  ds.data1buf = (uchar *)cp->addr;	/* DMA -> caller buf */
#endif
	ds.data2len = 0;     ds.data2buf  = 0;

#ifdef	A4091_KVA
	/* D42 prepare: after the DSA table is final, before the DSP write arms the
	 * chip.  The recovery re-launch below moves no new segment: this covers it. */
	a4091_dma_prepare( (int)cp->card, dpa, dlen, dmadir);
#endif

	/* launch */
	recovered = 0;
	WR32( R_TEMP, 0);
	WR8 ( R_SBCL, 0);
	WR32( R_DSA, (ulong)&ds);
	WR32( R_DSP, (ulong)inq_script);

	/* bounded-poll completion -- spin on ISTAT until SIP|DIP or the bound.
	 * cc-safe while-form (bound in a local, poll = poll + 1; NOT for/++/helper):
	 * copied from a4091-pollfix.c:242, codegen rationale at a4091-pollfix.c:189.
	 * The bound still exits for a silent/absent target so the boot bus scan
	 * cannot hang on an empty SCSI id. */
	{
		ulong	limit;
		limit = 8000000;
		istat = 0;
		poll  = 0;
		while (poll < limit) {
			istat = RD8(R_ISTAT);
			if (istat & (ISTAT_SIP | ISTAT_DIP)) break;
			poll = poll + 1;
		}
	}
	sstat0 = (istat & ISTAT_SIP) ? RD8(R_SSTAT0) : 0;
	dstat  = (istat & ISTAT_DIP) ? RD8(R_DSTAT)  : 0;
	dsps   = RD32(R_DSPS);

	if (!(istat & (ISTAT_SIP | ISTAT_DIP)))         rc = -2;
	else if (sstat0 & SSTAT0_STO)                   rc = -1;
	else if ((dstat & DSTAT_SIR) && dsps == 0xff00) rc = 0;
	else                                            rc = -3;

	/*
	 * DATA_IN phase-mismatch / short-read recovery.
	 *
	 * A SCSI tape READ that short-reads at a filemark / archive-member boundary
	 * makes the target leave DATA_IN for STATUS (or MSG_IN) before our DATA_IN
	 * MOVE has moved the full requested count.  The 53C710 then raises a phase-
	 * mismatch interrupt (SSTAT0 M_A) and aborts SCRIPTS mid-MOVE -- which the
	 * ladder above (no INT ran, so no DSTAT_SIR/0xff00) classified rc=-3.  That is
	 * NOT an error: the bytes the target DID send are already DMA'd into cp->addr;
	 * we must land them, drain the bus, and return the real STATUS byte.
	 *
	 * Gate = M_A phase mismatch (SSTAT0 M_A) on a transaction that programmed a
	 * data transfer (cp->nbyte > 0), i.e. an active DATA_IN that ended short.  An
	 * exact-length DISK read never phase-mismatches: its MOVE's DBC reaches 0
	 * exactly as the target leaves DATA_IN, so the SCRIPTS falls through to STATUS
	 * with M_A CLEAR and rc already 0 -- the disk/mkfs path provably cannot enter
	 * this branch.  Disconnect/reselect is a separate, later real-HW step and is
	 * deliberately NOT handled here (the emulated A4091 never disconnects).
	 */
	if (rc == -3 && (sstat0 & SSTAT0_M_A) && cp->nbyte > 0) {
		ulong	resume;

		/*
		 * (a) REAL-HW ONLY -- NOT EXERCISED UNDER EMULATION.
		 * Account for and drain any DATA_IN bytes still parked in the 53C710
		 * DMA FIFO / odd-byte latches when the MOVE was cut short, so every
		 * received byte reaches memory before we complete.  Mirrors siop.c's
		 * phase-mismatch residue math (siop.c:1472 -- (dfifo-(dbc&0x7f))&0x7f,
		 * +1 per ORF/OLF) and its per-interrupt DMA-FIFO clear (siop.c:1273-1296).
		 * We deliberately do NOT compute siop.c's iob_curbuf/iob_curlen data-
		 * pointer continuation math: we COMPLETE the short transfer, we do not
		 * continue it, and sdcom has no residual field (the ct driver derives the
		 * residual from REQUEST SENSE when status==CHECK CONDITION).
		 * Under Amiberry the DMA is instantaneous: dfifo/ORF/OLF read 0, the
		 * residue is 0, and CTEST1 FMT is already 0xF0 -- so this whole block is
		 * a no-op in emulation.
		 */
		{
			uchar	dfifo, sstat1;
			int	adjust;
			ulong	g;

			dfifo  = RD8(R_DFIFO);
			sstat1 = RD8(R_SSTAT1);
			adjust = (dfifo - (int)(RD32(R_DBC) & 0x7f)) & 0x7f;
			if (sstat1 & SSTAT1_ORF) adjust = adjust + 1;
			if (sstat1 & SSTAT1_OLF) adjust = adjust + 1;
			a4091_resid = (ulong)adjust;		/* diagnostic only; 0 in emu */

			WR8( R_CTEST8, RD8(R_CTEST8) | CTEST8_CLF);	/* clear DMA+SCSI FIFO */
			g = 0;
			while (g < 100000) {			/* bounded: never hang */
				if ((RD8(R_CTEST1) & CTEST1_FMT) == CTEST1_FMT) break;
				g = g + 1;
			}
			WR8( R_CTEST8, RD8(R_CTEST8) & ~CTEST8_CLF);	/* CLF is not self-clr */
		}

		/*
		 * (b) Re-launch SCRIPTS at the phase-dispatch block (SCRIPT_DISPATCH) so
		 * it re-dispatches on the LIVE bus phase: STATUS for the short read (also
		 * MSG_IN, via the hand-added dispatch case) drains to a clean INT 0xff00.
		 * The SSTAT0 read above already cleared the SCSI (M_A) interrupt as the
		 * chip requires; DSA still points at ds, so no re-init.  Writing DSP
		 * starts SCRIPTS (DMODE MAN=0).
		 */
		WR32( R_DSP, (ulong)inq_script + SCRIPT_DISPATCH);

		/* (c) re-poll for the resumed completion (same bounded cc-safe form) */
		{
			ulong	limit;
			limit = 8000000;
			istat = 0;
			resume = 0;
			while (resume < limit) {
				istat = RD8(R_ISTAT);
				if (istat & (ISTAT_SIP | ISTAT_DIP)) break;
				resume = resume + 1;
			}
		}
		sstat0 = (istat & ISTAT_SIP) ? RD8(R_SSTAT0) : 0;
		dstat  = (istat & ISTAT_DIP) ? RD8(R_DSTAT)  : 0;
		dsps   = RD32(R_DSPS);

		if (!(istat & (ISTAT_SIP | ISTAT_DIP)))         rc = -2;
		else if (sstat0 & SSTAT0_STO)                   rc = -1;
		else if ((dstat & DSTAT_SIR) && dsps == 0xff00) rc = 0;
		else                                            rc = -3;

		poll = poll + resume;		/* keep the slow-path diagnostic live */
		recovered = 1;
	}

	/* stash diagnostics (data already DMA'd into cp->addr) */
	a4091_rc = (uchar)rc;  a4091_dsps = dsps;
	a4091_istat = istat;   a4091_dstat = dstat;  a4091_stat = status_buf[0];

	if (poll > a4091_maxpoll)
		a4091_maxpoll = poll;

	/*
	 * Slow/failing path ONLY (a successful command within a4091_slow_poll
	 * polls stays silent so per-block disk traffic can't flood the console).  Dump
	 * the terminal 53C710 state read fresh from the chip: for the rc=-2 tape
	 * hang (no SIP/DIP) the rc-ladder above skipped SSTAT0/DSTAT, so this is the
	 * only look at the real DSTAT/SSTAT0/phase.  SSTAT2 low bits = SCSI phase;
	 * DSP = terminal SCRIPTS pointer; DBC = residual DMA byte count; DSPS is the
	 * captured value that drove rc.
	 */
	if (poll > a4091_slow_poll || rc != 0 || recovered) {
		uchar	di, dd, d0, d1, d2;
		ulong	dp, db;
		di = RD8(R_ISTAT);
		dd = RD8(R_DSTAT);
		d0 = RD8(R_SSTAT0);
		d1 = RD8(R_SSTAT1);
		d2 = RD8(R_SSTAT2);
		dp = RD32(R_DSP);
		db = RD32(R_DBC) & 0x00ffffff;
		/*
		 * The Amix native K&R printf has no %l length modifier -- "%lx" renders a
		 * literal 'x', so the 32-bit dsp/dbc/dsps were unreadable.  Print each as
		 * two %x halves "hi:lo" (hi = bits 31..16, lo = bits 15..0; reconstruct as
		 * hi<<16 | lo, lo zero-padded to 4 hex digits).  rec=1 => short-read
		 * recovery ran; sts = the resumed STATUS byte (2 = CHECK CONDITION at a
		 * tape filemark).
		 */
		printf("A4091 slow: poll=%d rc=%d rec=%d istat=%x dstat=%x sstat0=%x sstat1=%x sstat2=%x dsp=%x:%x dbc=%x:%x dsps=%x:%x sts=%x\n",
		    (int)poll, rc, recovered, di, dd, d0, d1, d2,
		    (int)((dp >> 16) & 0xffff),   (int)(dp & 0xffff),
		    (int)((db >> 16) & 0xffff),   (int)(db & 0xffff),
		    (int)((dsps >> 16) & 0xffff), (int)(dsps & 0xffff),
		    status_buf[0]);
	}

	/*
	 * Stuck-bus guard.  A target with more data than nbyte (a 512-byte dd
	 * request to a 2048-byte CD unit) is still in its data phase holding BSY
	 * when the MOVE ends: err_phase gives rc -3, and every later SELECT on
	 * this card would run out the poll bound until a bus reset.  On rc -3 with
	 * BSY still up (any phase holds the bus the same way), or on the poll
	 * bound itself (rc -2), re-arm the once-per-card bus reset so the next
	 * command clears the bus first.  Read before the quiesce below.
	 */
	if (rc == -2 || (rc == -3 && (RD8(R_SBCL) & SBCL_BSY))) {
		a4091_rstdone[cp->card] = 0;
		a4091_rearm_n++;
	}

#ifdef	A4091_KVA
	/*
	 * D42 complete: the chip must have stopped touching the segment first.  On
	 * the poll bound (rc -2) SCRIPTS may still be running -- quiesce it (abort +
	 * soft reset, the same sequence the next I/O starts with) AFTER the
	 * diagnostics above have read the live state, then complete.  Always before
	 * the sd callback, which may re-enter this driver for the next request.
	 */
	if (rc == -2) {
		a4091init();
		a4091_dmarec[cp->card].drv_quiesce++;
	}
	a4091_dma_complete( (int)cp->card, dpa, dlen, dmadir);
	if (bounced) {			/* after complete, before the callback */
		uchar	*bs, *bd;
		ulong	bn;

		bs = (uchar *)dpa;
		bd = (uchar *)cp->addr;
		bn = 0;
		while (bn < (ulong)cp->nbyte) {
			bd[bn] = bs[bn];
			bn = bn + 1;
		}
	}
#endif

	cp->status = (rc == 0) ? status_buf[0] : 0xff;
	cp->okay   = (rc == 0) ? TRUE : FALSE;
	(*cp->intr)( cp);
	return TRUE;
}

void
a4091intr()
{
}
