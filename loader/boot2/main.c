/*
 * main.c -- boot2 (docs/spec/10-boot-loader.md §3.2): find the generation,
 * load and check the kernel, build bootinfo, hand over.
 *
 * Stage 1 boots static kernels: a generation is a kernel and a manifest; a
 * manifest that needs the module arena or a RAM disk is refused with a
 * message (loader-min guards this as well).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "crc32.h"
#include "store.h"
#include "manifest.h"
#include "select.h"
#include "inflate.h"
#include "rel.h"
#include "bootinfo.h"
#include "input.h"
#include "menu.h"

#define BOUNCE	(16 * 2048UL)	/* chip-memory transfer buffer for every read */

/* the large working state lives in one allocation, not in bss, so the
 * loaded image plus bss stays inside boot1's 28 KiB area */
struct work {
	ax_u32 crctab[256];
	struct ax_inflate inf;
	struct ax_manifest man;
	ax_u8 cb[2][2048];
	ax_u8 cfgs[AXB_MAXBOARDS * AXB_CFGSIZE];
	ax_u8 mems[AXB_MAXMEM * AXB_MEMSIZE];
};
static struct work *w;
#define crctab	(w->crctab)
#define inf	(w->inf)
#define man	(w->man)

static ax_u8 *iob;		/* the strap's IOStdReq */
static ax_u32 part;		/* partition start in bytes */
static ax_u8 *bounce;		/* BOUNCE bytes of chip memory */
static ax_u32 curvol = 1;	/* the volume in the drive (floppy pairs) */
static struct ax_header hdr;
static struct ax_ctl ctl, newctl;
static int ctlcopy;		/* which control-block copy was read */
static ax_u32 cpu, attn;

/* the generation that loaded */
static const struct ax_gen *g;
static ax_u8 *mbuf, *kbuf;
static ax_u32 gen, vaddr;
static struct ax_bootdata bd;

static const char *const lmsg[] = { "",
	"L1 generation is for the other CPU line",
	"L2 manifest missing or damaged",
	"L3 member damaged",
	"L4 not enough memory",
	"L5 module arena overflow",
	"L6 relocation failed",
	"L7 no root module matched",
	"L8 trial generation did not reach multi-user",
	"L9 generation needs a newer loader",
	"L10 control block write failed",
	"L11 volume needed",
	"L12 path not found",
	"L13 read error" };

static void
fail(int code, ax_u32 gen)
{
	con_printf("amix-boot: %s (generation %u)\n", lmsg[code], gen);
}

static void motor_off(void);

/* device I/O through the chip bounce buffer: off is partition-relative,
 * 2048-aligned; len any; writes are whole 2048-byte blocks */
static int
io(int cmd, ax_u32 off, ax_u8 *buf, ax_u32 len)
{
	ax_u32 n, chunk;

	while (len) {
		chunk = len < BOUNCE ? len : BOUNCE;
		n = (chunk + 2047) & ~2047UL;
		if (cmd == CMD_WRITE)
			x_memcpy(bounce, buf, chunk);
		*(ax_u16 *)(iob + IO_COMMAND) = (ax_u16)cmd;
		*(ax_u32 *)(iob + IO_LENGTH) = n;
		*(ax_u32 *)(iob + IO_DATA) = (ax_u32)bounce;
		*(ax_u32 *)(iob + IO_OFFSET) = part + off;
		if (x_doio(iob) != 0)
			return -1;
		if (cmd == CMD_READ)
			x_memcpy(buf, bounce, chunk);
		off += n;
		buf += chunk;
		len -= chunk;
	}
	return 0;
}

/*
 * Multi-volume stores (the floppy pair, docs/spec/10-boot-loader.md §4.3):
 * an extent on another volume asks for that disk and waits until a store
 * header of the same set and the wanted volume can be read (L11).
 */
static int
want_volume(ax_u32 vol)
{
	ax_u8 *blk;
	struct ax_header h;
	int f, k;

	if (vol == curvol)
		return 0;
	if (vol == 0 || vol > hdr.nvolumes) {
		fail(11, vol);
		return -1;
	}
	blk = x_allocmem(2048, MEMF_PUBLIC);
	if (!blk)
		return -1;
	motor_off();
	con_printf("amix-boot: L11 insert boot volume %u of %u\n", vol, (ax_u32)hdr.nvolumes);
	for (;;) {
		for (f = 0; f < 25; f++) {	/* about half a second between tries */
			in_frame();
			k = in_key();
			if (k >= 0 || in_serial() >= 0 || in_lmb())
				break;
		}
		if (io(CMD_READ, 0, blk, 2048) != 0)
			continue;
		if (ax_hdr_pick(crctab, blk + AX_HDR_A_OFF, blk + AX_HDR_B_OFF, &h) < 0 ||
		    h.set_id != hdr.set_id) {
			con_puts("amix-boot: that disk is not part of this boot set\n");
			continue;
		}
		if (h.volume != vol) {
			con_printf("amix-boot: that is volume %u; insert volume %u\n", (ax_u32)h.volume, vol);
			continue;
		}
		break;
	}
	x_freemem(blk, 2048);
	curvol = vol;
	return 0;
}

static void
motor_off(void)
{
	*(ax_u16 *)(iob + IO_COMMAND) = TD_MOTOR;
	*(ax_u32 *)(iob + IO_LENGTH) = 0;
	x_doio(iob);	/* devices without a motor answer with an error: ignored */
}

/* the base of the largest non-chip memory region, rounded down to 256 bytes */
static ax_u32
bind_address(void)
{
	ax_u8 *mh = *(ax_u8 **)((ax_u8 *)ax_execbase + EXEC_MEMLIST);
	ax_u32 base = 0, max = 0, lower, size;

	for (; *(ax_u32 *)mh; mh = *(ax_u8 **)mh) {
		if (*(ax_u16 *)(mh + 14) & MEMF_CHIP)
			continue;
		lower = *(ax_u32 *)(mh + 20) & ~0xFFUL;
		size = *(ax_u32 *)(mh + 24) - lower;
		if (size > max)
			max = size, base = lower;
	}
	return base;
}

/* write the inactive control-block copy and read it back */
static int
ctl_write(const struct ax_ctl *c)
{
	ax_u8 *blk = x_allocmem(2 * 2048, MEMF_PUBLIC);
	ax_u32 off = hdr.ctl_off[ctlcopy ^ 1];
	int rc = -1;

	if (!blk)
		return -1;
	ax_ctl_write(crctab, c, blk);
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

static const struct ax_gen *
gen_entry(ax_u32 id)
{
	int i;

	for (i = 0; i < ctl.ngen; i++)
		if (ctl.gen[i].id == id)
			return &ctl.gen[i];
	return 0;
}

/* read member mb into a new MEMF_FAST buffer of mb->size bytes */
static ax_u8 *
load_member(const struct ax_member *mb, ax_u32 gen)
{
	ax_u8 *buf, *z;
	ax_u32 got;

	buf = x_allocmem(mb->size ? mb->size : 1, MEMF_FAST);
	if (!buf)
		buf = x_allocmem(mb->size ? mb->size : 1, MEMF_PUBLIC);
	if (!buf) {
		fail(4, gen);
		return 0;
	}
	if (want_volume(mb->vol) != 0) {
		x_freemem(buf, mb->size);
		return 0;
	}
	if (mb->z == AXZ_DEFLATE) {
		z = x_allocmem(mb->stored ? mb->stored : 1, MEMF_PUBLIC);
		if (!z) {
			fail(4, gen);
			x_freemem(buf, mb->size);
			return 0;
		}
		if (io(CMD_READ, mb->at, z, mb->stored) != 0 ||
		    ax_inflate(&inf, buf, mb->size, &got, z, mb->stored) != AXI_OK ||
		    got != mb->size) {
			x_freemem(z, mb->stored);
			x_freemem(buf, mb->size);
			fail(3, gen);
			return 0;
		}
		x_freemem(z, mb->stored);
	} else if (io(CMD_READ, mb->at, buf, mb->size) != 0) {
		x_freemem(buf, mb->size);
		fail(13, gen);
		return 0;
	}
	if (ax_crc32(crctab, buf, mb->size) != mb->crc) {
		x_freemem(buf, mb->size);
		fail(3, gen);
		return 0;
	}
	return buf;
}

static int
line_ok(const char *line)
{
	if (line[0] == 'k' && line[1] == '3' && line[2] == '0' && !line[3])
		return cpu == 30;
	if (line[0] == 'k' && line[1] == '4' && line[2] == '6' && !line[3])
		return cpu == 40 || cpu == 60;
	return 0;
}

/*
 * RTH1: find the BootNode the strap booted (device name, partition start,
 * unit), exactly as the RTH1 loaders do (amix-040-060-port/docs/contracts/
 * RTH1-ROOT-HINT.md): every pointer vetted with TypeOfMem, at most 64
 * nodes, under Forbid.  Fills flags/unit/base/id.
 */
static void
rth1_walk(void *expbase, ax_u32 *flags, ax_u32 *unit, ax_u32 *base, ax_u32 *id)
{
	ax_u8 *node, *dn, *fssm, *env, *bstr, *cfg, *match = 0, *cd = 0;
	const char *devname = *(const char **)(*(ax_u8 **)(iob + IO_DEVICE) + LN_NAME);
	ax_u8 req[IOSTD_SIZE];
	int budget = 64, matches = 0;
	ax_u32 start, n;
	const char *p;

	*flags = *unit = *base = *id = 0;
	x_forbid();
	for (node = *(ax_u8 **)((ax_u8 *)expbase + 74); *(ax_u32 *)node; node = *(ax_u8 **)node) {
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
		for (n = bstr[0], p = devname, bstr++; n && *bstr; n--, bstr++, p++)
			if (*bstr != (ax_u8)*p)
				break;
		if ((n && *bstr) || *p)
			continue;
		x_memset(req, 0, sizeof(req));
		if (x_opendevice(devname, *(ax_u32 *)fssm, req, *(ax_u32 *)(fssm + 12)) != 0)
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
	if (matches == 0)
		return;
	if (matches > 1) {
		*flags = RTH_AMBIG;
		return;
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
}

/* put id first; the rest of the default order follows.  An unstarted
 * trial keeps its recorded attempt only if it is still the one booted. */
static void
override(struct ax_sel *s, ax_u32 id)
{
	ax_u32 old[AX_MAXGEN + 1];
	int i, n = s->n;

	for (i = 0; i < n; i++)
		old[i] = s->order[i];
	if (s->trial_first && (n == 0 || old[0] != id))
		s->trial_first = 0;
	s->n = 0;
	s->order[s->n++] = id;
	for (i = 0; i < n; i++)
		if (old[i] != id)
			s->order[s->n++] = old[i];
	s->write = s->trial_first || s->oneshot_used || s->failed_trial;
}

/* load the first generation of the order that loads; its index, or -1 */
static int
load_first(const struct ax_sel *sel)
{
	struct ax_relerr rer;
	int k, i, errline, rc;

	for (k = 0; k < sel->n; k++) {
		gen = sel->order[k];
		g = gen_entry(gen);
		if (!g || g->man_len == 0 || g->man_len > 65536) {
			fail(2, gen);
			continue;
		}
		mbuf = x_allocmem(g->man_len, MEMF_PUBLIC);
		if (!mbuf || want_volume(g->volume ? g->volume : 1) != 0 ||
		    io(CMD_READ, g->man_off, mbuf, g->man_len) != 0 ||
		    ax_crc32(crctab, mbuf, g->man_len) != g->man_crc ||
		    ax_manifest_parse(crctab, (char *)mbuf, g->man_len, &man, &errline) != AXM_OK ||
		    man.generation != gen) {
			fail(2, gen);
			goto next;
		}
		if (!line_ok(man.line)) {
			con_printf("amix-boot: L1 generation %u is for line %s; this CPU is a 680%u\n",
				   gen, man.line, cpu);
			goto next;
		}
		for (i = 0; i < man.nmod && man.mod[i].cls != AXC_ROOT; i++)
			;
		if (man.loader_min > LOADER_VERSION || man.has_arena || man.has_ramdisk ||
		    i < man.nmod) {
			fail(9, gen);
			goto next;
		}
		con_printf("amix-boot: generation %u, kernel %s %u bytes\n", gen, man.kernel.name,
			   man.kernel.size);
		kbuf = load_member(&man.kernel, gen);
		if (!kbuf)
			goto next;
		vaddr = bind_address();
		rc = ax_rel(kbuf, man.kernel.size, vaddr, 1, &bd, &rer);
		if (rc == AXR_OK)
			return k;
		con_printf("amix-boot: L6 relocation failed: error %d, section %u record %u type %u\n",
			   rc, rer.rsect, rer.index, rer.type);
		x_freemem(kbuf, man.kernel.size);
		kbuf = 0;
next:
		if (mbuf)
			x_freemem(mbuf, g->man_len);
		mbuf = 0;
	}
	return -1;
}

struct ax_ci {
	ax_u32 sp, entry, d0, d1;
	ax_u32 tbuf, tvaddr, tsize, rbuf, rvaddr, rsize, dbuf, dvaddr, dsize;
	ax_u32 cpu, attn;
	ax_u32 coplist;		/* null copper list the hand-off installs */
};

/* copper words: FMODE, BPLCON3, BPLCON4 to their power-on values, no
 * bitplanes, black background, end -- the state the stock loader leaves
 * and the 1992 console assumes (N21, 2026-10-25) */
static const ax_u16 nullcop[] = {
	0x01fc, 0x0000, 0x0106, 0x0c00, 0x010c, 0x0011,
	0x0100, 0x0200, 0x0180, 0x0000, 0xffff, 0xfffe };

long
boot2_main(void *iobp, void *hdrp, ax_u32 partstart, ax_u32 choice, void *mem, void *execbase)
{
	struct ax_sel sel;
	struct ax_loaderrec lr;
	struct ax_disksel rootsel;
	ax_u8 *bi, *chipcode, *stack, *expbase, *cfg, *cop;
	ax_u8 rth[AX_RTH1_LEN], rto[AX_RTO1_LEN], axl[AX_AXL1_LEN], keys[16];
	struct ax_ci *ci;
	ax_u32 f, u, b, id, codesize;
	int i, k, ncfg, nmem, have_root = 0, win, menu = 0, safe = 0, devload = 0;
	ax_u8 *mh;

	(void)mem;
	ax_execbase = execbase;
	iob = iobp;
	part = partstart;
	con_init(9600);
	w = x_allocmem(sizeof(*w), MEMF_PUBLIC | MEMF_CLEAR);
	if (!w) {
		con_puts("amix-boot: L4 no memory\n");
		return -1;
	}
	ax_crc32_init(crctab);
	cpu = (ax_u32)ax_super(ax_probe, 0);
	attn = *(ax_u16 *)((ax_u8 *)execbase + EXEC_ATTNFLAGS);
	con_printf("\namix-boot %u: 680%u (AttnFlags %04x), boot1 choice %x\n",
		   LOADER_VERSION, cpu, attn, choice);
	if (choice & 0x100)
		con_puts("amix-boot: B2 primary boot2 damaged, secondary used\n");
	if (choice & 0x200)
		con_puts("amix-boot: B4 new loader already started once, previous loader used\n");

	bounce = x_allocmem(BOUNCE, MEMF_CHIP);
	if (!bounce) {
		con_puts("amix-boot: L4 no chip memory\n");
		return -1;
	}
	if (ax_hdr_parse(crctab, (ax_u8 *)hdrp, &hdr) != AX_OK) {
		con_puts("amix-boot: B1 store header lost\n");
		return -1;
	}
	curvol = hdr.volume;

	/* the control block, the console, the choice of generation */
	if (io(CMD_READ, hdr.ctl_off[0], w->cb[0], 2048) != 0)
		x_memset(w->cb[0], 0, 2048);
	if (io(CMD_READ, hdr.ctl_off[1], w->cb[1], 2048) != 0)
		x_memset(w->cb[1], 0, 2048);
	ctlcopy = ax_ctl_pick(crctab, w->cb[0], w->cb[1], &ctl);
	if (ctlcopy < 0) {
		con_puts("amix-boot: no valid control block\n");
		return -1;
	}
	if (ctl.serial_baud)
		con_init(ctl.serial_baud);
	if (ctl.console & AXC_SCREEN)
		con_screen();
	in_init(iob);
	ax_select(&ctl, (hdr.flags & AXF_READONLY) != 0, &sel);
	con_printf("amix-boot %u: 680%u, boot device unit %u at %u\n", LOADER_VERSION, cpu,
		   *(ax_u32 *)(iob + IO_UNIT), part);
	if (sel.failed_trial)
		fail(8, sel.failed_trial);

	x_memset(keys, 0, sizeof(keys));
	win = ctl.menu_ds ? menu_window(ctl.menu_ds, keys) : MENU_NONE;
	if (win == MENU_PREVIOUS && (id = menu_previous(&ctl)) != 0) {
		override(&sel, id);
		menu = 1;
	} else if (win != MENU_NONE || sel.n == 0) {
		id = menu_run(&ctl, sel.n ? sel.order[0] : 0, cpu, &safe, &devload);
		if (!id)
			return -1;
		override(&sel, id);
		menu = 1;
	}
	sel.safe |= safe;
	sel.devload |= devload;
	if (sel.write) {
		ax_select_apply(&ctl, &sel, &newctl);
		if (ctl_write(&newctl) == 0) {
			ctl = newctl;
		} else {
			fail(10, sel.n ? sel.order[0] : 0);
			ax_select_writefail(&sel);
		}
	}

	/* the first generation that loads; when none does, the menu */
	while ((k = load_first(&sel)) < 0) {
		con_puts("amix-boot: nothing loaded\n");
		id = menu_run(&ctl, sel.n ? sel.order[0] : 0, cpu, &safe, &devload);
		if (!id)
			return -1;
		override(&sel, id);
		sel.safe |= safe;
		sel.devload |= devload;
		menu = 1;
	}
	motor_off();

	/* bootinfo: boards, memory, keys, records */
	expbase = x_openlib("expansion.library", 0);
	ncfg = 0;
	for (cfg = 0; expbase && ncfg < AXB_MAXBOARDS &&
		      (cfg = x_findconfigdev(expbase, cfg, -1, -1)) != 0; ncfg++)
		x_memcpy(w->cfgs + ncfg * AXB_CFGSIZE, cfg, AXB_CFGSIZE);
	nmem = 0;
	for (mh = *(ax_u8 **)((ax_u8 *)execbase + EXEC_MEMLIST); *(ax_u32 *)mh && nmem < AXB_MAXMEM;
	     mh = *(ax_u8 **)mh, nmem++)
		x_memcpy(w->mems + nmem * AXB_MEMSIZE, mh, AXB_MEMSIZE);
	f = u = b = id = 0;
	if (expbase)
		rth1_walk(expbase, &f, &u, &b, &id);
	if (man.root && ax_disksel_parse(man.root, &rootsel) == 0 && rootsel.kind == AXS_SD &&
	    ax_rto1_build(&rootsel, rto) == 0)
		have_root = 1;
	ax_rth1_build(f, u, b, id, have_root ? rto : 0, rth);

	x_memset(&lr, 0, sizeof(lr));
	lr.loader_version = LOADER_VERSION;
	lr.boot1_choice = choice;
	lr.cpu = cpu;
	lr.attnflags = attn;
	lr.gen_id = gen;
	lr.gen_state = menu ? AXL_MENU : sel.oneshot_used ? AXL_ONESHOT :
		       g->state == AXG_TRIAL ? AXL_TRIAL :
		       g->state == AXG_PRISTINE ? AXL_PRISTINE : AXL_GOOD;
	lr.flags = (sel.safe ? AXLF_SAFE : 0) | (sel.devload ? AXLF_DEVLOAD : 0) |
		   (k > 0 ? AXLF_FALLBACK : 0) | ((hdr.flags & AXF_READONLY) ? AXLF_READONLY : 0) |
		   (menu ? AXLF_MENU : 0);
	if (sel.devload)
		con_puts("amix-boot: DEVELOPMENT LOAD: modules outside the manifest allowed this boot
");
	if (sel.safe)
		con_puts("amix-boot: safe mode
");
	lr.dev_unit = *(ax_u32 *)(iob + IO_UNIT);
	lr.dev_start = part;
	lr.dev_base = b;
	lr.dev_id = id;
	{
		const char *dn = *(const char **)(*(ax_u8 **)(iob + IO_DEVICE) + LN_NAME);
		ax_u32 len = 0;
		while (dn[len])
			len++;
		lr.dev_namecrc = ax_crc32(crctab, (const ax_u8 *)dn, len);
	}
	if (have_root)
		lr.root = rootsel;
	if (man.swap)
		ax_disksel_parse(man.swap, &lr.swap);
	if (man.rootfs)
		for (i = 0; i < 15 && man.rootfs[i]; i++)
			lr.rootfs[i] = man.rootfs[i];
	ax_axl1_build(&lr, axl);

	bi = x_allocmem(AXB_SIZE, MEMF_CHIP | MEMF_CLEAR);
	codesize = (ax_u32)ax_handoff_end - (ax_u32)ax_handoff;
	chipcode = x_allocmem(codesize, MEMF_CHIP);
	ci = x_allocmem(sizeof(*ci), MEMF_CHIP | MEMF_CLEAR);
	stack = x_allocmem(256, MEMF_CHIP);
	cop = x_allocmem(sizeof(nullcop), MEMF_CHIP);
	if (!bi || !chipcode || !ci || !stack || !cop) {
		con_puts("amix-boot: L4 no chip memory for the hand-off\n");
		return -1;
	}
	if (ax_bootinfo_build(bi, w->cfgs, ncfg, w->mems, nmem, keys, &bd, rth, axl) != 0) {
		con_puts("amix-boot: more than 16 boards or memory regions\n");
		return -1;
	}
	con_printf("amix-boot: RTH1 flags %x unit %u board %08x id %08x%s\n", f, u, b, id,
		   have_root ? ", root record from the manifest" : "");
	con_printf("amix-boot: kernel bound at %08x, text %u rodata %u data %u, end %08x\n",
		   vaddr, bd.tsize, bd.rsize, bd.dsize, bd.end);

	ci->sp = (ax_u32)stack + 252;
	ci->entry = bd.entry;
	ci->d0 = 3;			/* EXEC1 */
	ci->d1 = (ax_u32)bi;
	ci->tbuf = (ax_u32)kbuf + bd.toffset, ci->tvaddr = bd.tvaddr, ci->tsize = bd.tsize;
	ci->rbuf = (ax_u32)kbuf + bd.roffset, ci->rvaddr = bd.rvaddr, ci->rsize = bd.rsize;
	ci->dbuf = (ax_u32)kbuf + bd.doffset, ci->dvaddr = bd.dvaddr, ci->dsize = bd.dsize;
	ci->cpu = cpu;
	ci->attn = attn;
	x_memcpy(cop, nullcop, sizeof(nullcop));
	ci->coplist = (ax_u32)cop;
	x_memcpy(chipcode, (void *)ax_handoff, codesize);
	if (x_execversion() >= 37) {
		struct ax_regs r;
		REGS0(r);
		ax_call(ax_execbase, -636, &r);	/* CacheClearU: chipcode was just written */
	}
	con_puts("amix-boot: starting the kernel\n");
	ax_super((void (*)(void))chipcode, ci);
	return -1;			/* not reached */
}
