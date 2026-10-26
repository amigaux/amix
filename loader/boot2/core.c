/*
 * core.c -- see core.h.
 *
 * Loader version 2: a generation is a kernel and a manifest; a module
 * kernel's manifest names its identity record and its module arena
 * (C3-3, C3-4), and the loader checks the one and fills the other with
 * the arena directory, a copy of the manifest and the root-class modules
 * (C4-4 version 3).  A RAM disk is S4-11's: a manifest with one is
 * refused with a message (loader-min guards this as well).
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
static ax_u8 *mbuf, *mcopy, *kbuf;
static ax_u32 gen, vaddr;
static int k30;			/* the generation is for the k30 line */
static struct ax_bootdata bd;

/* the L codes' lines, packed: entry n follows the n-th NUL; each at most
 * 20 characters after its code, 10 section 9 gives the meaning */
static const char lmsg[] = "\0"
	"L1 wrong CPU line\0"
	"L2 manifest damaged\0"
	"L3 member damaged\0"
	"L4 no memory\0"
	"L5 arena overflow\0"
	"L6 relocation failed\0"
	"L7\0"				/* retired: the core matches (C4-4 v3) */
	"L8 trial not confirmed\0"
	"L9 loader too old\0"
	"L10 control write failed\0"
	"L11 volume needed\0"
	"L12 path not found\0"
	"L13 read error\0"
	"L14 identity mismatch";

const char l4_nomem[] = "L4 no memory\n";	/* core.c and main.c */

void
fail(int code, ax_u32 id)
{
	const char *p = lmsg;

	while (code)
		if (!*p++)
			code--;
	con_say("%s (generation %u)\n", p, id);
}

int
core_init(void)
{
	w = x_allocmem(sizeof(*w), MEMF_PUBLIC | MEMF_CLEAR);
	if (!w) {
		con_say(l4_nomem);
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

/*
 * Where image offset off (len bytes) sits in the relocated file buffer.
 * The identity record and the arena are .data objects (C3-3): in the data
 * segment of an ET_REL kernel, in the single section of a brel.
 */
static ax_u8 *
img(ax_u32 off, ax_u32 len)
{
	ax_u32 a = vaddr + off;

	if (bd.dsize && a >= bd.dvaddr && a - bd.dvaddr + len <= bd.dsize)
		return kbuf + bd.doffset + (a - bd.dvaddr);
	if (!bd.dsize && a >= bd.tvaddr && a - bd.tvaddr + len <= bd.tsize)
		return kbuf + bd.toffset + (a - bd.tvaddr);
	return 0;
}

/*
 * A module kernel: its identity record must say what the manifest says
 * (C3-3), then the arena gets its directory, the manifest copy and every
 * root-class module of the generation, in safe mode only the safe set
 * (C3-4; C4-4 version 3): each file 16-aligned, decompressed and
 * CRC-checked by load_member, with its zeroed bss= tail behind it.
 * boot2 selects nothing: the core evaluates match= at marc_root.  No
 * parameter strings: the core reads them in the manifest copy.  0, or
 * the L code.
 */
/* boot2 places every root-class record, in safe mode the safe set (C4-4 v3) */
static int
placed(const struct ax_member *mb, int safe)
{
	return mb->cls == AXC_ROOT && (!safe || mb->safe);
}

static const char needs[] = "the %s needs %u bytes, it has %u\n";

static int
arena_fill(int safe)
{
	ax_u8 *id = img(man.ident_off, 64), *a = img(man.arena_off, man.arena_cap), *e, *b;
	ax_u32 sum = 0, i, n = 0, off, line = (ax_u32)(man.line[1] - '0') * 10 + (ax_u32)(man.line[2] - '0');
	struct ax_member *mb;

	if (!id || !a || !man.kabi)
		return 14;
	for (i = 0; i < 16; i++)
		sum += AX_GET32(id + 4 * i);
	for (i = 0; i < 24 && man.kabi[i] && id[12 + i] == (ax_u8)man.kabi[i]; i++)
		;
	if (AX_GET32(id) != 0x41584b31UL || AX_GET32(id + 4) != 0x00010040UL || sum ||
	    i == 24 || man.kabi[i] || id[12 + i] || AX_GET32(id + 36) != line ||
	    AX_GET32(id + 40) != man.arena_off || AX_GET32(id + 44) != man.arena_cap)
		return 14;
	for (i = 0; i < (ax_u32)man.nmod; i++)
		n += placed(&man.mod[i], safe);
	off = 32 + 48 * n;
	if (off + g->man_len > man.arena_cap) {
		con_say(needs, "arena", off + g->man_len, man.arena_cap);
		return 5;
	}
	x_memset(a, 0, off);
	x_memcpy(a + off, mcopy, g->man_len);
	AX_PUT32(a + 16, off);
	AX_PUT32(a + 20, g->man_len);
	off += g->man_len;
	for (n = 0, i = 0; i < (ax_u32)man.nmod; i++) {
		mb = &man.mod[i];
		if (!placed(mb, safe))
			continue;
		off = (off + 15) & ~15UL;
		if (off + ((mb->size + 15) & ~15UL) + mb->bss > man.arena_cap) {
			con_say(needs, "arena", off + mb->size + mb->bss, man.arena_cap);
			return 5;
		}
		con_say("module %s %u bytes\n", mb->name, mb->size);
		if ((b = load_member(mb, gen)) == 0)
			return -1;		/* load_member said which L code */
		x_memcpy(a + off, b, mb->size);
		x_freemem(b, mb->size);
		e = a + 32 + 48 * n++;
		for (sum = 0; sum < 15 && mb->name[sum]; sum++)
			e[sum] = (ax_u8)mb->name[sum];
		AX_PUT32(e + 16, off);
		AX_PUT32(e + 20, mb->size);
		AX_PUT32(e + 24, 1);
		AX_PUT32(e + 28, mb->crc);
		AX_PUT32(e + 32, 1 | (mb->safe ? 4 : 0));
		off = (off + mb->size + 15) & ~15UL;
		x_memset(a + off, 0, mb->bss);
		off += mb->bss;
	}
	AX_PUT32(a, 0x41584131UL);		/* AXA1 */
	AX_PUT32(a + 4, 0x00010020UL);
	AX_PUT32(a + 12, n);
	AX_PUT32(a + 24, off);
	AX_PUT32(a + 28, gen);
	for (sum = 0, i = 0; i < 8 + 12 * n; i++)
		sum += AX_GET32(a + 4 * i);
	AX_PUT32(a + 8, 0 - sum);
	return 0;
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
		/* the parser cuts its buffer up: the arena gets this copy */
		if (mbuf && (mcopy = x_allocmem(g->man_len, MEMF_PUBLIC)) != 0)
			x_memcpy(mcopy, mbuf, g->man_len);
		if (!mbuf || !mcopy || ax_crc32(crctab, mbuf, g->man_len) != g->man_crc ||
		    ax_manifest_parse(crctab, (char *)mbuf, g->man_len, &man, &errline) != AXM_OK ||
		    man.generation != gen) {
			fail(2, gen);
			goto next;
		}
		if (!line_ok(man.line)) {
			con_say("L1 generation %u is for line %s; this CPU is a 680%u\n",
				   gen, man.line, core_cpu);
			goto next;
		}
		if (man.loader_min > LOADER_VERSION || man.has_arena != man.has_ident ||
		    man.has_ramdisk) {
			fail(9, gen);
			goto next;
		}
		k30 = man.line[1] == '3';	/* line_ok: k30 or k46 */
		con_say("generation %u, kernel %s %u bytes\n", gen, man.kernel.name,
			   man.kernel.size);
		vaddr = bind_address(&room);
		if (k30 && room > AX_K30_MEMCAP)
			room = AX_K30_MEMCAP;	/* the k30 kernel's limit (10 section 3) */
		if (!room) {	/* never bind in chip memory: 0 is the vector table */
			con_say("no fast memory below 0x40000000 to run the kernel in\n");
			fail(4, gen);
			goto next;
		}
		kbuf = load_member(&man.kernel, gen);
		if (!kbuf)
			goto next;
		rc = ax_rel(kbuf, man.kernel.size, vaddr, 1, &bd, &rer);
		if (rc == AXR_OK) {
			bd.end = ax_kernel_end(&bd, man.kernel.bss, &i);
			if (i)
				con_say("no bss= for this brel: 512 KiB assumed\n");
		}
		if (rc == AXR_OK && bd.end - vaddr <= room) {
			if (!man.has_arena || (rc = arena_fill(sel->safe)) == 0)
				return k;
			if (rc > 0)
				fail(rc, gen);
		} else if (rc == AXR_OK) {
			con_say(needs, "kernel", bd.end - vaddr, room);
			fail(4, gen);
		} else
			con_say("L6 relocation failed: error %d, section %u record %u type %u\n",
				   rc, rer.rsect, rer.index, rer.type);
		x_freemem(kbuf, man.kernel.size);
		kbuf = 0;
next:
		if (mbuf)
			x_freemem(mbuf, g->man_len);
		if (mcopy)
			x_freemem(mcopy, g->man_len);
		mbuf = mcopy = 0;
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
		con_say("nothing loaded\n");
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
	if (k30)
		ax_memcap(w->mems, nmem, vaddr, AX_K30_MEMCAP);

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
		con_say("DEVELOPMENT LOAD: modules outside the manifest allowed this boot\n");
	if (sel.safe)
		con_say("safe mode\n");
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
		con_say("L4 no chip memory for the hand-off\n");
		return -1;
	}
	if (ax_bootinfo_build(bi, w->cfgs, ncfg, w->mems, nmem, keys, &bd, rth, axl) != 0) {
		con_say("more than 16 boards or memory regions\n");
		return -1;
	}
	con_say("RTH1 flags %x unit %u board %08x id %08x%s\n", f, u, b, id,
		   have_root ? ", root record from the manifest" : "");
	con_say("kernel bound at %08x, text %u rodata %u data %u, end %08x\n",
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
	con_say("starting the kernel\n");
	ax_super((void (*)(void))chipcode, ci);
	return -1;			/* not reached */
}
