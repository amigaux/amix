/*
 * core.c -- see core.h.
 *
 * Stage 1 boots static kernels: a generation is a kernel and a manifest; a
 * manifest that needs the module arena or a RAM disk is refused with a
 * message (loader-min guards this as well).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include "b2.h"
#include "crc32.h"
#include "select.h"
#include "inflate.h"
#include "rel.h"
#include "input.h"
#include "menu.h"
#include "core.h"

/* the large working state lives in one allocation, not in bss, so the
 * loaded boot2 image plus bss stays inside boot1's 28 KiB area */
struct work {
	ax_u32 crctab[256];
	struct ax_inflate inf;
	struct ax_manifest man;
	struct ax_ctl ctl, newctl;	/* the control block, and the one written */
	ax_u8 cfgs[AXB_MAXBOARDS * AXB_CFGSIZE];
	ax_u8 mems[AXB_MAXMEM * AXB_MEMSIZE];
};
static struct work *w;
#define crctab	(w->crctab)
#define inf	(w->inf)
#define man	(w->man)
#define ctl	(w->ctl)
#define newctl	(w->newctl)

ax_u32 *ax_crctab;
ax_u32 core_cpu;
static ax_u32 attn;
static const struct medium *med;

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

void
fail(int code, ax_u32 id)
{
	con_printf("amix-boot: %s (generation %u)\n", lmsg[code], id);
}

int
core_init(void)
{
	w = x_allocmem(sizeof(*w), MEMF_PUBLIC | MEMF_CLEAR);
	if (!w) {
		con_puts("amix-boot: L4 no memory\n");
		return -1;
	}
	ax_crc32_init(crctab);
	ax_crctab = crctab;
	core_cpu = (ax_u32)ax_super(ax_probe, 0);
	attn = *(ax_u16 *)((ax_u8 *)ax_execbase + EXEC_ATTNFLAGS);
	return 0;
}

/* the kernel's bind address (ax_bind_region over exec's memory list);
 * *size 0: no fast memory */
static ax_u32
bind_address(ax_u32 *size)
{
	ax_u8 *mh = *(ax_u8 **)((ax_u8 *)ax_execbase + EXEC_MEMLIST);
	struct ax_memr r[AXB_MAXMEM];
	int n;

	for (n = 0; *(ax_u32 *)mh && n < AXB_MAXMEM; mh = *(ax_u8 **)mh, n++) {
		r[n].attr = *(ax_u16 *)(mh + 14);
		r[n].lower = *(ax_u32 *)(mh + 20);
		r[n].upper = *(ax_u32 *)(mh + 24);
	}
	return ax_bind_region(r, n, size);
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
load_member(const struct ax_member *mb, ax_u32 id)
{
	ax_u8 *buf, *z;
	ax_u32 got;
	int rc;

	buf = x_allocmem(mb->size ? mb->size : 1, MEMF_FAST);
	if (!buf)
		buf = x_allocmem(mb->size ? mb->size : 1, MEMF_PUBLIC);
	if (!buf) {
		fail(4, id);
		return 0;
	}
	if (mb->z == AXZ_DEFLATE) {
		z = x_allocmem(mb->stored ? mb->stored : 1, MEMF_PUBLIC);
		if (!z) {
			fail(4, id);
			x_freemem(buf, mb->size);
			return 0;
		}
		if ((rc = med->read_stored(mb, z)) != 0) {
			fail(rc, id);
			rc = -1;
		} else if (ax_inflate(&inf, buf, mb->size, &got, z, mb->stored) != AXI_OK ||
			   got != mb->size) {
			fail(3, id);
			rc = -1;
		}
		x_freemem(z, mb->stored);
		if (rc) {
			x_freemem(buf, mb->size);
			return 0;
		}
	} else if ((rc = med->read_stored(mb, buf)) != 0) {
		x_freemem(buf, mb->size);
		fail(rc, id);
		return 0;
	}
	if (ax_crc32(crctab, buf, mb->size) != mb->crc) {
		x_freemem(buf, mb->size);
		fail(3, id);
		return 0;
	}
	return buf;
}

static int
line_ok(const char *line)
{
	if (line[0] == 'k' && line[1] == '3' && line[2] == '0' && !line[3])
		return core_cpu == 30;
	if (line[0] == 'k' && line[1] == '4' && line[2] == '6' && !line[3])
		return core_cpu == 40 || core_cpu == 60;
	return 0;
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
	ax_u32 room;
	int k, i, errline, rc;

	for (k = 0; k < sel->n; k++) {
		gen = sel->order[k];
		g = gen_entry(gen);
		if (!g || g->man_len == 0 || g->man_len > 65536) {
			fail(2, gen);
			continue;
		}
		mbuf = med->read_manifest(g);
		if (!mbuf || ax_crc32(crctab, mbuf, g->man_len) != g->man_crc ||
		    ax_manifest_parse(crctab, (char *)mbuf, g->man_len, &man, &errline) != AXM_OK ||
		    man.generation != gen) {
			fail(2, gen);
			goto next;
		}
		if (!line_ok(man.line)) {
			con_printf("amix-boot: L1 generation %u is for line %s; this CPU is a 680%u\n",
				   gen, man.line, core_cpu);
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
		vaddr = bind_address(&room);
		if (!room) {	/* never bind in chip memory: 0 is the vector table */
			con_puts("amix-boot: no fast memory to run the kernel in\n");
			fail(4, gen);
			goto next;
		}
		kbuf = load_member(&man.kernel, gen);
		if (!kbuf)
			goto next;
		rc = ax_rel(kbuf, man.kernel.size, vaddr, 1, &bd, &rer);
		if (rc == AXR_OK && bd.end - vaddr <= room)
			return k;
		if (rc == AXR_OK) {
			con_printf("amix-boot: the kernel needs %u bytes, the largest fast memory "
				   "region has %u\n", bd.end - vaddr, room);
			fail(4, gen);
		} else
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
core_boot(const struct medium *m, const struct ax_ctl *c, void *replyport)
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

	med = m;
	ctl = *c;
	if (ctl.serial_baud)
		con_init(ctl.serial_baud);
	if (ctl.console & AXC_SCREEN)
		con_screen();
	in_init(replyport);
	ax_select(&ctl, m->readonly, &sel);
	if (sel.failed_trial)
		fail(8, sel.failed_trial);

	x_memset(keys, 0, sizeof(keys));
	win = ctl.menu_ds ? menu_window(ctl.menu_ds, keys) : MENU_NONE;
	if (win == MENU_PREVIOUS && (id = menu_previous(&ctl)) != 0) {
		override(&sel, id);
		menu = 1;
	} else if (win != MENU_NONE || sel.n == 0) {
		id = menu_run(&ctl, sel.n ? sel.order[0] : 0, core_cpu, &safe, &devload);
		if (!id)
			return -1;
		override(&sel, id);
		menu = 1;
	}
	sel.safe |= safe;
	sel.devload |= devload;
	if (sel.write && m->write_ctl) {
		ax_select_apply(&ctl, &sel, &newctl);
		if (m->write_ctl(&newctl) == 0) {
			ctl = newctl;
		} else {
			fail(10, sel.n ? sel.order[0] : 0);
			ax_select_writefail(&sel);
		}
	}

	/* the first generation that loads; when none does, the menu */
	while ((k = load_first(&sel)) < 0) {
		con_puts("amix-boot: nothing loaded\n");
		id = menu_run(&ctl, sel.n ? sel.order[0] : 0, core_cpu, &safe, &devload);
		if (!id)
			return -1;
		override(&sel, id);
		sel.safe |= safe;
		sel.devload |= devload;
		menu = 1;
	}
	if (m->quiesce)
		m->quiesce();

	/* bootinfo: boards, memory, keys, records */
	expbase = x_openlib("expansion.library", 0);
	ncfg = 0;
	for (cfg = 0; expbase && ncfg < AXB_MAXBOARDS &&
		      (cfg = x_findconfigdev(expbase, cfg, -1, -1)) != 0; ncfg++)
		x_memcpy(w->cfgs + ncfg * AXB_CFGSIZE, cfg, AXB_CFGSIZE);
	nmem = 0;
	for (mh = *(ax_u8 **)((ax_u8 *)ax_execbase + EXEC_MEMLIST); *(ax_u32 *)mh && nmem < AXB_MAXMEM;
	     mh = *(ax_u8 **)mh, nmem++)
		x_memcpy(w->mems + nmem * AXB_MEMSIZE, mh, AXB_MEMSIZE);

	x_memset(&lr, 0, sizeof(lr));
	f = u = b = id = 0;
	m->identify(&f, &u, &b, &id, &lr);
	if (man.root && ax_disksel_parse(man.root, &rootsel) == 0 && rootsel.kind == AXS_SD &&
	    ax_rto1_build(&rootsel, rto) == 0)
		have_root = 1;
	ax_rth1_build(f, u, b, id, have_root ? rto : 0, rth);

	lr.loader_version = LOADER_VERSION;
	lr.boot1_choice = m->choice;
	lr.cpu = core_cpu;
	lr.attnflags = attn;
	lr.gen_id = gen;
	lr.gen_state = menu ? AXL_MENU : sel.oneshot_used ? AXL_ONESHOT :
		       g->state == AXG_TRIAL ? AXL_TRIAL :
		       g->state == AXG_PRISTINE ? AXL_PRISTINE : AXL_GOOD;
	lr.flags = (sel.safe ? AXLF_SAFE : 0) | (sel.devload ? AXLF_DEVLOAD : 0) |
		   (k > 0 ? AXLF_FALLBACK : 0) | (m->readonly ? AXLF_READONLY : 0) |
		   (menu ? AXLF_MENU : 0);
	if (sel.devload)
		con_puts("amix-boot: DEVELOPMENT LOAD: modules outside the manifest allowed this boot\n");
	if (sel.safe)
		con_puts("amix-boot: safe mode\n");
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
	ci->cpu = core_cpu;
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
