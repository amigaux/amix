/*
 * main.c -- boot2 behind boot1 (docs/spec/10-boot-loader.md §3.2): the boot
 * store as the medium -- extents read through the strap's IOStdReq, into
 * their buffer or a bounce buffer as the partition's DosEnvec allows,
 * multi-volume floppy pairs, control-block writes, the RTH1 boot-node
 * walk -- and core.c for everything else.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "crc32.h"
#include "input.h"
#include "core.h"

#define BOUNCE	(16 * 2048UL)	/* the transfer buffer, and the longest transfer */

static ax_u8 *iob;		/* the strap's IOStdReq */
static ax_u32 part;		/* partition start in bytes */
static ax_u8 *bounce;		/* BOUNCE bytes where the device can transfer */
static ax_u32 mask;		/* the partition's de_Mask; 0 = none known */
static ax_u32 memtype;		/* its de_BufMemType | MEMF_PUBLIC */
static ax_u32 curvol = 1;	/* the volume in the drive (floppy pairs) */
static struct ax_header hdr;
static int ctlcopy;		/* which control-block copy was read */

static const char *
devname(void)
{
	return *(const char **)(*(ax_u8 **)(iob + IO_DEVICE) + LN_NAME);
}

/* the device can transfer n bytes at p: FFS's test of de_Mask (its low
 * bits the alignment, its value the highest address) */
static int
dmaok(const void *p, ax_u32 n)
{
	return ((ax_u32)p & ~mask) == 0 && (ax_u32)p + n - 1 <= mask;
}

/* device I/O: off is partition-relative, 2048-aligned; len any; writes are
 * whole 2048-byte blocks.  At most BOUNCE bytes a transfer, straight into
 * buf when the Mask allows it, else through the bounce buffer. */
static int
io(int cmd, ax_u32 off, ax_u8 *buf, ax_u32 len)
{
	ax_u32 n, chunk;
	ax_u8 *p;

	while (len) {
		chunk = len < BOUNCE ? len : BOUNCE;
		n = (chunk + 2047) & ~2047UL;
		p = n == chunk && dmaok(buf, n) ? buf : bounce;
		if (cmd == CMD_WRITE)
			x_memcpy(p, buf, chunk);	/* onto itself when p is buf */
		*(ax_u16 *)(iob + IO_COMMAND) = (ax_u16)cmd;
		*(ax_u32 *)(iob + IO_LENGTH) = n;
		*(ax_u32 *)(iob + IO_DATA) = (ax_u32)p;
		*(ax_u32 *)(iob + IO_OFFSET) = part + off;
		if (x_doio(iob) != 0)
			return -1;
		if (cmd == CMD_READ && p != buf)
			x_memcpy(buf, p, chunk);
		off += n;
		buf += chunk;
		len -= chunk;
	}
	return 0;
}

static void
motor_off(void)
{
	*(ax_u16 *)(iob + IO_COMMAND) = TD_MOTOR;
	*(ax_u32 *)(iob + IO_LENGTH) = 0;
	x_doio(iob);	/* devices without a motor answer with an error: ignored */
}

/* the device's disk-change counter, or -1 when it keeps none */
static long
changenum(void)
{
	*(ax_u16 *)(iob + IO_COMMAND) = TD_CHANGENUM;
	*(ax_u32 *)(iob + IO_LENGTH) = 0;
	if (x_doio(iob) != 0)
		return -1;
	return (long)*(ax_u32 *)(iob + IO_ACTUAL);
}

/*
 * Multi-volume stores (the floppy pair, docs/spec/10-boot-loader.md §4.3):
 * an extent on another volume asks for that disk and waits until a store
 * header of the same set and the wanted volume can be read (L11).
 * trackdisk keeps the last track it read across a disk change, so the disk
 * is read again when its change counter moved, a key asks, or every 4 s,
 * always after CMD_CLEAR; the motor stays off while waiting.  The 4 s read
 * is for a counter that never moves: Kickstart 3.2.1's trackdisk under
 * amiberry did not count the rig's swap, and the loop waited for ever
 * (E958/E959, 2026-10-27).  A device without a change counter is re-read
 * every half second.  Each verdict is said once (N25b/N26b, 2026-10-25).
 */
static int
want_volume(ax_u32 vol)
{
	ax_u8 *blk;
	struct ax_header h;
	ax_u32 said = 0, verdict, t;
	long last, cn;
	int f, asked, lmb = 1;

	if (vol == curvol)
		return 0;
	if (vol == 0 || vol > hdr.nvolumes)
		return -1;
	blk = x_allocmem(2048, MEMF_PUBLIC);
	if (!blk)
		return -1;
	motor_off();
	con_say("L11 insert boot volume %u of %u\n", vol, (ax_u32)hdr.nvolumes);
	last = changenum();
	for (t = 1;; t++) {
		for (f = 0, asked = 0; f < 25 && !asked; f++) {	/* half a second */
			in_frame();
			asked = in_key() >= 0 || in_serial() >= 0 || (in_lmb() && !lmb);
			lmb = in_lmb();
		}
		cn = changenum();
		if (cn >= 0 && cn == last && !asked && (t & 7))
			continue;		/* the same disk, nobody asked, not 4 s yet */
		last = cn;
		*(ax_u16 *)(iob + IO_COMMAND) = CMD_CLEAR;
		*(ax_u32 *)(iob + IO_LENGTH) = 0;
		x_doio(iob);
		if (io(CMD_READ, 0, blk, 2048) != 0)
			verdict = 4;		/* no disk, or not readable yet */
		else if (ax_hdr_pick(ax_crctab, blk + AX_HDR_A_OFF, blk + AX_HDR_B_OFF, &h) < 0)
			verdict = 1;		/* not a boot store at all */
		else if (h.set_id != hdr.set_id)
			verdict = 2 | (h.set_id << 8);
		else if (h.volume != vol)
			verdict = 3 | ((ax_u32)h.volume << 8);
		else
			break;
		motor_off();
		if (verdict == said && !asked)
			continue;		/* said already */
		said = verdict;
		if ((verdict & 0xFF) == 3)
			con_say("volume %u, not %u\n", (ax_u32)h.volume, vol);
		else if (verdict != 4)
			con_say("not of this boot set\n");
	}
	x_freemem(blk, 2048);
	curvol = vol;
	return 0;
}

/* an extent that runs past the end of its volume continues at
 * AX_VOLN_DATA on the next one (§4.3) */
static int
st_read_stored(const struct ax_member *mb, ax_u8 *dst)
{
	ax_u32 vol = mb->vol, off = mb->at, left = mb->stored, n;

	if (!mb->has_at)
		return 12;		/* a CD member (file=) in a store */
	for (;;) {
		if (off >= hdr.store_size || want_volume(vol) != 0)
			return 11;
		n = hdr.store_size - off < left ? hdr.store_size - off : left;
		if (io(CMD_READ, off, dst, n) != 0)
			return 13;
		dst += n;
		left -= n;
		if (!left)
			return 0;
		vol++;
		off = AX_VOLN_DATA;
	}
}

static ax_u8 *
st_read_manifest(const struct ax_gen *g)
{
	ax_u8 *buf = x_allocmem(g->man_len, MEMF_PUBLIC);

	if (!buf)
		return 0;
	if (want_volume(g->volume ? g->volume : 1) != 0 ||
	    io(CMD_READ, g->man_off, buf, g->man_len) != 0) {
		x_freemem(buf, g->man_len);
		return 0;
	}
	return buf;
}

/* write the inactive control-block copy and read it back */
static int
st_write_ctl(const struct ax_ctl *c)
{
	ax_u8 *blk = x_allocmem(2 * 2048, MEMF_PUBLIC);
	ax_u32 off = hdr.ctl_off[ctlcopy ^ 1];
	int rc = -1;

	if (!blk)
		return -1;
	ax_ctl_write(ax_crctab, c, blk);
	if (io(CMD_WRITE, off, blk, 2048) == 0 && io(CMD_READ, off, blk + 2048, 2048) == 0) {
		ax_u32 i;
		for (i = 0; i < 2048 && blk[i] == blk[2048 + i]; i++)
			;
		if (i == 2048) {
			ctlcopy ^= 1;
			rc = 0;
		}
	}
	x_freemem(blk, 2 * 2048);
	return rc;
}

/*
 * RTH1: find the BootNode the strap booted (device name, partition start,
 * unit), exactly as the RTH1 loaders do (amix-040-060-port/docs/contracts/
 * RTH1-ROOT-HINT.md): every pointer vetted with TypeOfMem, at most 64
 * nodes, under Forbid.  Also fills the loader record's boot-device fields,
 * and takes the node's de_BufMemType and de_Mask for io().
 */
static void
st_identify(ax_u32 *flags, ax_u32 *unit, ax_u32 *base, ax_u32 *id, struct ax_loaderrec *lr)
{
	ax_u8 *node, *dn, *fssm, *env, *bstr, *cfg, *match = 0, *cd = 0, *expbase;
	const char *name = devname();
	ax_u8 req[IOSTD_SIZE];
	int budget = 64, matches = 0;
	ax_u32 start, n;
	const char *p;

	*flags = *unit = *base = *id = 0;
	expbase = x_openlib("expansion.library", 0);
	if (!expbase)
		goto record;
	x_forbid();
	for (node = *(ax_u8 **)(expbase + 74); *(ax_u32 *)node; node = *(ax_u8 **)node) {
		if (--budget == 0) {
			matches = 2;	/* no tail: a cycle; AMBIG */
			break;
		}
		dn = *(ax_u8 **)(node + 16);
		if (!dn || !x_typeofmem(dn))
			continue;
		fssm = (ax_u8 *)(*(ax_u32 *)(dn + 28) << 2);
		if (!fssm || !x_typeofmem(fssm))
			continue;
		env = (ax_u8 *)(*(ax_u32 *)(fssm + 8) << 2);
		if (!env || !x_typeofmem(env))
			continue;
		start = *(ax_u32 *)(env + 36) * *(ax_u32 *)(env + 12) *
			*(ax_u32 *)(env + 20) * *(ax_u32 *)(env + 4) * 4;
		if (start != part)
			continue;
		bstr = (ax_u8 *)(*(ax_u32 *)(fssm + 4) << 2);
		if (!bstr || !x_typeofmem(bstr))
			continue;
		/* BSTR vs C string; a NUL counted into the BSTR ends it */
		for (n = bstr[0], p = name, bstr++; n && *bstr; n--, bstr++, p++)
			if (*bstr != (ax_u8)*p)
				break;
		if ((n && *bstr) || *p)
			continue;
		x_memset(req, 0, sizeof(req));
		if (x_opendevice(name, *(ax_u32 *)fssm, req, *(ax_u32 *)(fssm + 12)) != 0)
			continue;
		n = *(ax_u32 *)(req + IO_UNIT);
		x_closedevice(req);
		if (n != *(ax_u32 *)(iob + IO_UNIT))
			continue;
		matches++;
		match = fssm;
		cd = *(ax_u8 **)(node + LN_NAME);	/* the ConfigDev, if it is one */
	}
	x_permit();
	if (matches == 1) {
		env = (ax_u8 *)(*(ax_u32 *)(match + 8) << 2);
		if (*(ax_u32 *)env >= 14) {	/* de_TableSize reaches de_Mask */
			memtype = *(ax_u32 *)(env + 48) | MEMF_PUBLIC;
			mask = *(ax_u32 *)(env + 56);
		}
		*unit = *(ax_u32 *)match;
		*flags = RTH_BOOT | RTH_BMOBO;
		for (cfg = 0; (cfg = x_findconfigdev(expbase, cfg, -1, -1)) != 0;) {
			if (cfg != cd)
				continue;
			*flags = RTH_BOOT | RTH_BCDEV;
			*base = *(ax_u32 *)(cfg + 32);
			*id = ((ax_u32)*(ax_u16 *)(cfg + 20) << 16) | ((ax_u32)cfg[17] << 8);
			if (*id == 0x144B0300UL) {	/* the Z3660 boot vehicle: name its card by id */
				*base = 0;
				*id = 0x144B0100UL;
			}
			break;
		}
	} else if (matches > 1) {
		*flags = RTH_AMBIG;
	}
record:
	lr->dev_unit = (*flags & RTH_BOOT) ? *unit : 0xFFFFFFFFUL; /* io_Unit is a pointer */
	lr->dev_start = part;
	lr->dev_base = *base;
	lr->dev_id = *id;
	for (n = 0; name[n]; n++)
		;
	lr->dev_namecrc = ax_crc32(ax_crctab, (const ax_u8 *)name, n);
}

static struct medium store = {
	0, st_read_stored, st_read_manifest, st_write_ctl, motor_off, st_identify, 0
};

long
boot2_main(void *iobp, void *hdrp, ax_u32 partstart, ax_u32 choice, void *mem, void *execbase,
	   ax_u32 infast)
{
	ax_u8 *cb;	/* both control-block copies, allocated: bss is boot1's space */
	struct ax_ctl ctl;	/* core_boot keeps its own copy */
	struct ax_loaderrec lr;	/* st_identify's outputs, unused here */
	ax_u32 f;
	ax_u8 *p;

	(void)mem;
	ax_execbase = execbase;
	iob = iobp;
	part = partstart;
	con_init(9600);
	if (core_init() != 0)
		return -1;
	con_printf("\namix-boot %u: 680%u (AttnFlags %04x), boot1 choice %x\n",
		   LOADER_VERSION, core_cpu, *(ax_u16 *)((ax_u8 *)execbase + EXEC_ATTNFLAGS), choice);
	if (choice & 0x100)
		con_say("B2 primary boot2 damaged, secondary used\n");
	if (choice & 0x200)
		con_say("B4 new loader already started once, previous loader used\n");
	if (!infast)
		con_say("no fast memory: the loader runs from chip memory\n");

	/* the bounce buffer as FFS takes its buffers (spec 10 §3.2): of
	 * de_BufMemType, or chip when the Mask does not reach it or no boot
	 * node gave one */
	st_identify(&f, &f, &f, &f, &lr);
	p = x_allocmem(BOUNCE, memtype);
	if (p && !dmaok(p, BOUNCE)) {
		x_freemem(p, BOUNCE);
		p = 0;
	}
	if (!p && !(p = x_allocmem(BOUNCE, MEMF_CHIP))) {
		con_say(l4_nomem);
		return -1;
	}
	bounce = p;
	if (ax_hdr_parse(ax_crctab, (ax_u8 *)hdrp, &hdr) != AX_OK) {
		con_say("B1 store header lost\n");
		return -1;
	}
	curvol = hdr.volume;
	cb = x_allocmem(2 * 2048, MEMF_PUBLIC);
	if (!cb) {
		con_say(l4_nomem);
		return -1;
	}
	if (io(CMD_READ, hdr.ctl_off[0], cb, 2048) != 0)
		x_memset(cb, 0, 2048);
	if (io(CMD_READ, hdr.ctl_off[1], cb + 2048, 2048) != 0)
		x_memset(cb + 2048, 0, 2048);
	ctlcopy = ax_ctl_pick(ax_crctab, cb, cb + 2048, &ctl);
	x_freemem(cb, 2 * 2048);
	if (ctlcopy < 0) {
		con_say("no valid control block\n");
		return -1;
	}
	con_printf("amix-boot %u: 680%u, boot device %s, partition at %u, buffer %x\n",
		   LOADER_VERSION, core_cpu, devname(), part, (ax_u32)p);
	store.readonly = (hdr.flags & AXF_READONLY) != 0;
	store.choice = choice;
	return core_boot(&store, &ctl, *(void **)(iob + 14));	/* the strap's reply port */
}
