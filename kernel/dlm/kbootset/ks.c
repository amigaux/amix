/*
 * ks.c -- kbootset's core (see ks.h): the store's generations and the
 * state machine over them (docs/spec/40-generations-and-composer.md §3,
 * docs/spec/10-boot-loader.md §4.2 and §7).
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "crc32.h"
#include "sha256.h"
#include "inflate.h"
#include "ks.h"

#define MAXMAN	65536		/* a manifest is at most this long */

static int
fail(struct ks *k, int rc, int gate, const char *msg)
{
	k->gate = gate;
	sprintf(k->msg, "%.300s", msg);
	return rc;
}

/* write len bytes at off and read them back; KS_OK or KS_EIO */
static int
put(struct ks *k, ax_u32 off, const ax_u8 *buf, ax_u32 len)
{
	ax_u8 *back = malloc(len ? len : 1);
	int rc = KS_EIO;

	if (back && k->dev.write(k->dev.ctx, off, buf, len) == 0 &&
	    k->dev.read(k->dev.ctx, off, back, len) == 0 && memcmp(back, buf, len) == 0)
		rc = KS_OK;
	free(back);
	if (rc != KS_OK)
		sprintf(k->msg, "write or read-back failed at 0x%lx (%lu bytes)",
			(unsigned long)off, (unsigned long)len);
	return rc;
}

static int
get(struct ks *k, ax_u32 off, ax_u8 *buf, ax_u32 len)
{
	if (k->dev.read(k->dev.ctx, off, buf, len) != 0) {
		sprintf(k->msg, "read failed at 0x%lx", (unsigned long)off);
		return KS_EIO;
	}
	return KS_OK;
}

const struct ax_gen *
ks_find(const struct ks *k, ax_u32 id)
{
	int i;

	for (i = 0; i < k->ctl.ngen; i++)
		if (k->ctl.gen[i].id == id && id)
			return &k->ctl.gen[i];
	return 0;
}

/* the manifest of g into a malloc'd, NUL-padded buffer, checked; 0 on error */
static char *
manifest(struct ks *k, const struct ax_gen *g, struct ax_manifest *m)
{
	char *buf;
	int errline;

	if (g->man_len == 0 || g->man_len > MAXMAN || (buf = malloc(g->man_len + 1)) == 0)
		return 0;
	if (get(k, g->man_off, (ax_u8 *)buf, g->man_len) != KS_OK ||
	    ax_crc32(k->crctab, (ax_u8 *)buf, g->man_len) != g->man_crc ||
	    ax_manifest_parse(k->crctab, buf, g->man_len, m, &errline) != AXM_OK ||
	    m->generation != g->id) {
		free(buf);
		return 0;
	}
	return buf;
}

char *
ks_manifest(struct ks *k, ax_u32 id, struct ax_manifest *m)
{
	const struct ax_gen *g = ks_find(k, id);

	return g ? manifest(k, g, m) : 0;
}

ax_u32
ks_next_id(const struct ks *k)
{
	ax_u32 id = k->ctl.last_id;
	int i;

	for (i = 0; i < k->ctl.ngen; i++)
		if (k->ctl.gen[i].id > id)
			id = k->ctl.gen[i].id;
	return id + 1;
}

static void
use(struct ks *k, ax_u32 off, ax_u32 len)
{
	if (k->nused < KS_MAXEXT) {
		k->used[k->nused].off = off;
		k->used[k->nused].len = (len + AX_BLK - 1) / AX_BLK * AX_BLK;
		k->nused++;
	}
}

static void
use_member(struct ks *k, const struct ax_member *mb)
{
	if (mb->has_at)
		use(k, mb->at, mb->stored);
}

/* every extent the current control block references; a generation whose
 * manifest cannot be read makes the store unwritable (its extents are
 * unknown, so nothing may be allocated) */
static int
usemap(struct ks *k)
{
	static struct ax_manifest m;
	char *buf;
	int i, j;

	k->nused = 0;
	for (i = 0; i < k->ctl.ngen; i++) {
		const struct ax_gen *g = &k->ctl.gen[i];

		if (g->state == AXG_FREE)
			continue;
		if ((buf = manifest(k, g, &m)) == 0) {
			sprintf(k->msg, "generation %lu: manifest unreadable or damaged; "
				"run kbootset check", (unsigned long)g->id);
			return KS_ESTORE;
		}
		use(k, g->man_off, g->man_len);
		use_member(k, &m.kernel);
		for (j = 0; j < m.nmod; j++)
			use_member(k, &m.mod[j]);
		if (m.has_ramdisk)
			use_member(k, &m.ramdisk);
		free(buf);
	}
	return KS_OK;
}

/* first fit of len bytes in the data area, avoiding the used extents and
 * the n extents already planned; 0 = no room */
static ax_u32
alloc(const struct ks *k, const struct ks_ext *plan, int n, ax_u32 len)
{
	ax_u32 off = AX_DATA_OFF, end;
	int i, moved;

	len = (len + AX_BLK - 1) / AX_BLK * AX_BLK;
	do {
		moved = 0;
		end = off + len;
		for (i = 0; i < k->nused + n; i++) {
			const struct ks_ext *e = i < k->nused ? &k->used[i] : &plan[i - k->nused];

			if (e->len && off < e->off + e->len && e->off < end) {
				off = e->off + e->len;
				moved = 1;
				break;
			}
		}
	} while (moved);
	return len <= k->hdr.store_size && off <= k->hdr.store_size - len ? off : 0;
}

ax_u32
ks_free(const struct ks *k)
{
	ax_u32 total = k->hdr.store_size - AX_DATA_OFF, used = 0;
	int i;

	for (i = 0; i < k->nused; i++)
		used += k->used[i].len;
	return used > total ? 0 : total - used;
}

static int
present(const struct ax_ctl *c, ax_u32 id)
{
	int i;

	for (i = 0; i < c->ngen; i++)
		if (c->gen[i].id == id)
			return 1;
	return 0;
}

/* the kept set (40 §1): the pristine generation, the default, the two
 * newest good generations and the trial; everything else is dropped */
static void
keep(struct ax_ctl *c)
{
	ax_u32 good1 = 0, good2 = 0;
	int i, n;

	for (i = 0; i < c->ngen; i++)
		if (c->gen[i].state == AXG_GOOD) {
			if (c->gen[i].id > good1) {
				good2 = good1;
				good1 = c->gen[i].id;
			} else if (c->gen[i].id > good2) {
				good2 = c->gen[i].id;
			}
		}
	for (i = n = 0; i < c->ngen; i++) {
		const struct ax_gen *g = &c->gen[i];

		if (g->state == AXG_PRISTINE || g->id == c->default_gen ||
		    (g->state == AXG_TRIAL && g->id == c->trial_gen) ||
		    (g->state == AXG_GOOD && (g->id == good1 || g->id == good2)))
			c->gen[n++] = *g;
	}
	for (i = n; i < c->ngen; i++)
		memset(&c->gen[i], 0, sizeof(c->gen[i]));
	c->ngen = (ax_u16)n;
	if (c->trial_gen && !present(c, c->trial_gen))
		c->trial_gen = 0;
	if (c->oneshot == AXO_GEN && !present(c, c->oneshot_gen))
		c->oneshot = AXO_NONE, c->oneshot_gen = 0;
}

/* write c as the inactive control-block copy, sequence + 1, and read it
 * back: the commit point of every change to the generations */
static int
write_ctl(struct ks *k, struct ax_ctl *c)
{
	ax_u8 blk[AX_BLK];
	int rc;

	c->seq = k->ctl.seq + 1;
	ax_ctl_write(k->crctab, c, blk);
	if ((rc = put(k, k->hdr.ctl_off[k->ctlcopy ^ 1], blk, AX_BLK)) != KS_OK)
		return rc;
	k->ctl = *c;
	k->ctlcopy ^= 1;
	return usemap(k);
}

/* write h as the inactive header copy, sequence + 1, and read it back */
static int
write_hdr(struct ks *k, struct ax_header *h)
{
	ax_u8 blk[AX_HDR_SIZE];
	int rc;

	h->seq = k->hdr.seq + 1;
	ax_hdr_write(k->crctab, h, blk);
	if ((rc = put(k, k->hdrcopy ? AX_HDR_A_OFF : AX_HDR_B_OFF, blk, AX_HDR_SIZE)) != KS_OK)
		return rc;
	k->hdr = *h;
	k->hdrcopy ^= 1;
	return KS_OK;
}

static int
writable(struct ks *k)
{
	if (k->hdr.flags & (AXF_READONLY | AXF_MULTIVOL))
		return fail(k, KS_EREFUSE, 0, "the store is read-only (a floppy pair or a CD)");
	return KS_OK;
}

/* one member: read, inflate, CRC-32 and SHA-256; 0 good, 1 a problem */
ax_u8 *
ks_member(struct ks *k, const struct ax_member *mb, ax_u32 *len)
{
	static struct ax_inflate st;
	ax_u8 *z, *p, sha[32];
	ax_u32 got = 0;
	char hx[65];
	int i;

	if (!mb->has_at || (z = malloc(mb->stored ? mb->stored : 1)) == 0)
		return 0;
	if ((p = mb->z == AXZ_DEFLATE ? malloc(mb->size ? mb->size : 1) : z) == 0 ||
	    get(k, mb->at, z, mb->stored) != KS_OK ||
	    (mb->z == AXZ_DEFLATE &&
	     (ax_inflate(&st, p, mb->size, &got, z, mb->stored) != AXI_OK || got != mb->size)) ||
	    ax_crc32(k->crctab, p, mb->size) != mb->crc)
		goto bad;
	if (mb->sha256) {
		ax_sha256(p, mb->size, sha);
		for (i = 0; i < 32; i++)
			sprintf(hx + 2 * i, "%02x", sha[i]);
		if (strncmp(hx, mb->sha256, 64))
			goto bad;
	}
	if (p != z)
		free(z);
	*len = mb->size;
	return p;
bad:
	if (p && p != z)
		free(p);
	free(z);
	return 0;
}

static int
check_member(struct ks *k, ax_u32 gen, const char *what, const struct ax_member *mb,
	     void (*say)(const char *))
{
	static struct ax_inflate st;
	ax_u8 *z = 0, *p = 0, sha[32];
	char line[400], hx[65];
	ax_u32 got = 0;
	int i, bad = 1;

	if (!mb->has_at)
		return 0;		/* boot/demand class: on the root filesystem */
	if ((z = malloc(mb->stored ? mb->stored : 1)) == 0 ||
	    (p = mb->z == AXZ_DEFLATE ? malloc(mb->size ? mb->size : 1) : z) == 0) {
		sprintf(line, "generation %lu %s %s: out of memory", (unsigned long)gen, what, mb->name);
		goto out;
	}
	if (get(k, mb->at, z, mb->stored) != KS_OK) {
		sprintf(line, "generation %lu %s %s: read error", (unsigned long)gen, what, mb->name);
		goto out;
	}
	if (mb->z == AXZ_DEFLATE &&
	    (ax_inflate(&st, p, mb->size, &got, z, mb->stored) != AXI_OK || got != mb->size)) {
		sprintf(line, "generation %lu %s %s: does not inflate", (unsigned long)gen, what, mb->name);
		goto out;
	}
	if (ax_crc32(k->crctab, p, mb->size) != mb->crc) {
		sprintf(line, "generation %lu %s %s: CRC-32 BAD", (unsigned long)gen, what, mb->name);
		goto out;
	}
	if (mb->sha256) {
		ax_sha256(p, mb->size, sha);
		for (i = 0; i < 32; i++)
			sprintf(hx + 2 * i, "%02x", sha[i]);
		if (strncmp(hx, mb->sha256, 64)) {
			sprintf(line, "generation %lu %s %s: SHA-256 BAD", (unsigned long)gen, what, mb->name);
			goto out;
		}
	}
	sprintf(line, "generation %lu %s %s: %lu bytes, %s ok", (unsigned long)gen, what, mb->name,
		(unsigned long)mb->size, mb->sha256 ? "CRC-32 and SHA-256" : "CRC-32 (no SHA-256 recorded)");
	bad = 0;
out:
	say(line);
	if (p != z)
		free(p);
	free(z);
	return bad;
}

int
ks_check(struct ks *k, void (*say)(const char *line))
{
	static struct ax_manifest m;
	char line[200], *buf;
	int i, j, bad = 0;

	for (i = 0; i < k->ctl.ngen; i++) {
		const struct ax_gen *g = &k->ctl.gen[i];

		if ((buf = manifest(k, g, &m)) == 0) {
			sprintf(line, "generation %lu: manifest unreadable or damaged", (unsigned long)g->id);
			say(line);
			bad++;
			continue;
		}
		bad += check_member(k, g->id, "kernel", &m.kernel, say);
		for (j = 0; j < m.nmod; j++)
			bad += check_member(k, g->id, "module", &m.mod[j], say);
		if (m.has_ramdisk)
			bad += check_member(k, g->id, "ramdisk", &m.ramdisk, say);
		free(buf);
	}
	return bad;
}

int
ks_open(struct ks *k)
{
	ax_u8 a[AX_BLK], b[AX_BLK];
	char line[200];
	unsigned long id;
	int rc;

	k->gate = 0;
	k->msg[0] = 0;
	ax_crc32_init(k->crctab);
	if (get(k, AX_HDR_A_OFF, a, AX_HDR_SIZE) || get(k, AX_HDR_B_OFF, b, AX_HDR_SIZE))
		return KS_EIO;
	if ((k->hdrcopy = ax_hdr_pick(k->crctab, a, b, &k->hdr)) < 0)
		return fail(k, KS_ESTORE, 0, "no valid store header: not a boot store");
	if (get(k, k->hdr.ctl_off[0], a, AX_BLK) || get(k, k->hdr.ctl_off[1], b, AX_BLK))
		return KS_EIO;
	if ((k->ctlcopy = ax_ctl_pick(k->crctab, a, b, &k->ctl)) < 0)
		return fail(k, KS_ESTORE, 0, "no valid control block");
	if ((rc = usemap(k)) != KS_OK)
		return rc;
	/* an interrupted commit: before its commit point its extents were
	 * never referenced, after it the commit is complete; either way the
	 * store is consistent and only the journal is left to clear */
	if (k->jrn.get && k->jrn.get(k->jrn.ctx, line, sizeof(line)) > 0) {
		if (!strncmp(line, "commit ", 7) && (id = strtoul(line + 7, 0, 10)) != 0)
			sprintf(k->msg, ks_find(k, (ax_u32)id) ?
				"the commit of generation %lu had completed when it was interrupted" :
				"the commit of generation %lu was interrupted before its commit point; "
				"nothing of it remains", id);
		else
			sprintf(k->msg, "an unknown journal record was cleared");
		if (k->jrn.clear(k->jrn.ctx) != 0)
			return fail(k, KS_EIO, 0, "cannot clear the journal");
	}
	return KS_OK;
}

int
ks_create(struct ks *k, ax_u32 store_size, const ax_u8 *boot1, const ax_u8 *boot2,
	  ax_u32 boot2_len, ax_u32 loader_version, int force)
{
	ax_u8 blk[AX_BLK];
	struct ax_header h;
	struct ax_ctl c;
	ax_u32 off;
	int rc;

	ax_crc32_init(k->crctab);
	k->gate = 0;
	if (store_size % AX_BLK || store_size < AX_DATA_OFF + AX_BLK)
		return fail(k, KS_EREFUSE, 0, "a store is a multiple of 2048 bytes and larger than 64 KiB");
	if (boot2_len == 0 || boot2_len > AX_BOOT2_MAX)
		return fail(k, KS_EREFUSE, 0, "boot2 must be 1..28672 bytes");
	/* what is there: a store, or any bootblock (a 1.0 chain), is not
	 * replaced by accident */
	if (!force && get(k, 0, blk, AX_BLK) == KS_OK &&
	    (ax_hdr_pick(k->crctab, blk + AX_HDR_A_OFF, blk + AX_HDR_B_OFF, &h) >= 0 ||
	     !memcmp(blk, "DOS", 3)))
		return fail(k, KS_EREFUSE, 0, "the slice already holds a boot store or a bootblock: "
			    "create --force replaces it");
	/* the first 64 KiB zeroed: nothing of an earlier chain survives */
	memset(blk, 0, AX_BLK);
	for (off = 0; off < AX_DATA_OFF; off += AX_BLK)
		if ((rc = put(k, off, blk, AX_BLK)) != KS_OK)
			return rc;
	if (boot1 && (rc = put(k, AX_BOOT1_OFF, boot1, AX_BOOT1_MAX)) != KS_OK)
		return rc;
	if ((rc = put(k, AX_BOOT2_A_OFF, boot2, boot2_len)) != KS_OK)
		return rc;
	memset(&c, 0, sizeof(c));
	c.seq = 1;
	c.menu_ds = 20;
	c.console = AXC_SERIAL | AXC_SCREEN;
	c.serial_baud = 9600;
	ax_ctl_write(k->crctab, &c, blk);
	if ((rc = put(k, AX_CTL_A_OFF, blk, AX_BLK)) != KS_OK)
		return rc;
	memset(blk, 0, AX_BLK);			/* copy B: not valid */
	if ((rc = put(k, AX_CTL_B_OFF, blk, AX_BLK)) != KS_OK ||
	    (rc = put(k, AX_TALLY_OFF, blk, AX_BLK)) != KS_OK)
		return rc;
	memset(&h, 0, sizeof(h));
	h.seq = 1;
	h.store_size = store_size;
	h.flags = AXF_WRITABLE;
	h.volume = h.nvolumes = 1;
	h.set_id = ax_crc32(k->crctab, boot2, boot2_len) ^ store_size;
	h.boot2[0].off = AX_BOOT2_A_OFF;
	h.boot2[0].len = boot2_len;
	h.boot2[0].crc = ax_crc32(k->crctab, boot2, boot2_len);
	h.boot2[0].ver = loader_version;
	h.ctl_off[0] = AX_CTL_A_OFF;
	h.ctl_off[1] = AX_CTL_B_OFF;
	h.tally_off = AX_TALLY_OFF;
	h.medium = AXM_DISK;
	ax_hdr_write(k->crctab, &h, blk);
	if ((rc = put(k, AX_HDR_B_OFF, blk, AX_HDR_SIZE)) != KS_OK ||	/* B last: A is found first */
	    (rc = put(k, AX_HDR_A_OFF, blk, AX_HDR_SIZE)) != KS_OK)
		return rc;
	return ks_open(k);
}

/*
 * What boot2 puts in the arena for the manifest m (mlen bytes): the
 * directory of 32 + 48 bytes a root-class record, the manifest copy, then
 * every root-class module 16-aligned with its bss= tail -- the layout of
 * loader/boot2/core.c's arena_fill (C4-4 version 3 section 1)
 */
ax_u32
ks_arena_need(const struct ax_manifest *m, ax_u32 mlen)
{
	ax_u32 off, n = 0;
	int i;

	for (i = 0; i < m->nmod; i++)
		n += m->mod[i].cls == AXC_ROOT;
	off = 32 + 48 * n + mlen;
	for (i = 0; i < m->nmod; i++)
		if (m->mod[i].cls == AXC_ROOT) {
			off = (off + 15) & ~(ax_u32)15;
			off = (off + m->mod[i].size + 15) & ~(ax_u32)15;
			off += m->mod[i].bss;
		}
	return off;
}

/* one member record of the manifest */
static void
record(char *out, const struct ks_member *mb, ax_u32 at, ax_u32 stored, ax_u32 crc,
       const ax_u8 sha[32])
{
	static const char *const kind[] = { "", "kernel", "module", "ramdisk" };
	int i;

	sprintf(out, "%s %s%s %lu at=0x%lx", kind[mb->kind], mb->name,
		mb->kind == AXK_MODULE ? " root" : "", (unsigned long)mb->size, (unsigned long)at);
	if (stored != mb->size)
		sprintf(out + strlen(out), " stored=%lu z=deflate", (unsigned long)stored);
	sprintf(out + strlen(out), " crc32=%08lx sha256=", (unsigned long)crc);
	for (i = 0; i < 32; i++)
		sprintf(out + strlen(out), "%02x", sha[i]);
	if (mb->attrs && *mb->attrs)
		sprintf(out + strlen(out), " %s", mb->attrs);
	strcat(out, "\n");
}

int
ks_commit(struct ks *k, const struct ks_newgen *g, ax_u32 *idp)
{
	static struct ks_ext plan[AXM_MAXMOD + 4];
	static char man[MAXMAN + 1], copy[MAXMAN + 1];
	static struct ax_manifest chk;
	const ax_u8 *data[AXM_MAXMOD + 2];
	ax_u8 *zbuf[AXM_MAXMOD + 2], sha[32];
	ax_u32 stored[AXM_MAXMOD + 2], id, need = 0, mlen, crc;
	struct ax_ctl c;
	struct ax_gen *ng;
	char line[512], jl[64];
	int i, rc, errline, pristine = k->ctl.ngen == 0;

	k->gate = 0;
	k->msg[0] = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	if (g->n < 1 || g->n > AXM_MAXMOD + 2 || g->m[0].kind != AXK_KERNEL)
		return fail(k, KS_EREFUSE, 0, "a generation is one kernel and its members");
	if (k->ctl.ngen >= AX_MAXGEN)
		return fail(k, KS_EREFUSE, 0, "the control block is full; run kbootset collect");
	id = ks_next_id(k);
	if (g->id && g->id != id) {
		sprintf(line, "generation %lu was built, but the store's next id is %lu: "
			"run kbootset build again", (unsigned long)g->id, (unsigned long)id);
		return fail(k, KS_EREFUSE, 0, line);
	}

	/* everything is prepared in memory and placed before anything is
	 * written, so a refusal writes nothing */
	for (i = 0; i < g->n; i++) {
		zbuf[i] = 0;
		data[i] = g->m[i].data;
		stored[i] = g->m[i].size;
		if (g->m[i].deflate && k->deflate &&
		    (zbuf[i] = k->deflate(g->m[i].data, g->m[i].size, &stored[i])) != 0 &&
		    stored[i] < g->m[i].size) {
			data[i] = zbuf[i];
		} else {
			free(zbuf[i]);
			zbuf[i] = 0;
			stored[i] = g->m[i].size;
		}
	}
	mlen = (ax_u32)sprintf(man, "GMF1\ngeneration %lu\n%s", (unsigned long)id, g->head ? g->head : "");
	rc = KS_OK;
	for (i = 0; i < g->n && rc == KS_OK; i++) {
		plan[i].len = (stored[i] + AX_BLK - 1) / AX_BLK * AX_BLK;
		need += plan[i].len;
		if ((plan[i].off = alloc(k, plan, i, stored[i])) == 0) {
			rc = KS_EREFUSE;
			break;
		}
		ax_sha256(g->m[i].data, g->m[i].size, sha);
		record(line, &g->m[i], plan[i].off, stored[i],
		       ax_crc32(k->crctab, g->m[i].data, g->m[i].size), sha);
		if (strlen(line) > AXM_MAXLINE + 1 || mlen + strlen(line) + 300 > MAXMAN) {
			rc = fail(k, KS_EREFUSE, 0, "manifest record too long");
			break;
		}
		strcpy(man + mlen, line);
		mlen += (ax_u32)strlen(line);
	}
	if (rc == KS_OK) {
		if (g->tail) {
			if (mlen + strlen(g->tail) + 30 > MAXMAN)
				rc = fail(k, KS_EREFUSE, 0, "manifest too long");
			else
				mlen += (ax_u32)sprintf(man + mlen, "%s", g->tail);
		}
	}
	if (rc == KS_OK) {
		crc = ax_crc32(k->crctab, (ax_u8 *)man, mlen);
		mlen += (ax_u32)sprintf(man + mlen, "end crc32=%08lx\n", (unsigned long)crc);
		memcpy(copy, man, mlen);
		if (ax_manifest_parse(k->crctab, copy, mlen, &chk, &errline) != AXM_OK ||
		    chk.generation != id) {
			sprintf(line, "the new manifest is refused by the loader's parser at line %d", errline);
			rc = fail(k, KS_EREFUSE, 0, line);
		} else if (chk.has_arena && ks_arena_need(&chk, mlen) > chk.arena_cap) {
			/* boot2 places the directory, the manifest copy and every
			 * root-class module with its bss= tail (C3-4, C4-4 v3) */
			sprintf(line, "gate 4 (arena): the manifest copy and the root set need %lu bytes, "
				"the arena has %lu", (unsigned long)ks_arena_need(&chk, mlen),
				(unsigned long)chk.arena_cap);
			rc = fail(k, KS_EREFUSE, 4, line);
		}
	}
	if (rc == KS_OK) {
		plan[g->n].len = (mlen + AX_BLK - 1) / AX_BLK * AX_BLK;
		need += plan[g->n].len;
		if ((plan[g->n].off = alloc(k, plan, g->n, mlen)) == 0)
			rc = KS_EREFUSE;
	}
	if (rc == KS_EREFUSE && !k->msg[0]) {
		sprintf(line, "gate 5 (store space): generation %lu needs %lu bytes, %lu free",
			(unsigned long)id, (unsigned long)need, (unsigned long)ks_free(k));
		rc = fail(k, KS_EREFUSE, 5, line);
	}
	if (rc != KS_OK)
		goto out;

	/* 1. journal; 2-4. members and manifest, each read back */
	if (k->step)
		k->step(1, "journal");
	if (k->jrn.put) {
		sprintf(jl, "commit %lu", (unsigned long)id);
		if (k->jrn.put(k->jrn.ctx, jl) != 0) {
			rc = fail(k, KS_EIO, 0, "cannot write the journal");
			goto out;
		}
	}
	if (k->step)
		k->step(2, "members");
	for (i = 0; i < g->n && rc == KS_OK; i++)
		rc = put(k, plan[i].off, data[i], stored[i]);
	if (rc == KS_OK && k->step)
		k->step(4, "manifest");
	if (rc == KS_OK)
		rc = put(k, plan[g->n].off, (ax_u8 *)man, mlen);
	if (rc != KS_OK)
		goto out;

	/* 5. the control block: the commit point */
	c = k->ctl;
	for (i = 0; i < c.ngen; i++)		/* a newer trial replaces an older one */
		if (c.gen[i].state == AXG_TRIAL)
			c.gen[i].state = AXG_BAD;
	ng = &c.gen[c.ngen++];
	memset(ng, 0, sizeof(*ng));
	ng->id = id;
	ng->state = pristine ? AXG_PRISTINE : AXG_TRIAL;
	ng->volume = 1;
	ng->man_off = plan[g->n].off;
	ng->man_len = mlen;
	ng->man_crc = ax_crc32(k->crctab, (ax_u8 *)man, mlen);
	ng->created = g->created;
	if (pristine) {
		c.default_gen = id;
		c.trial_gen = 0;
	} else {
		c.trial_gen = id;
	}
	c.last_id = id;
	keep(&c);				/* 6. collect */
	if (k->step)
		k->step(5, "control block");
	if ((rc = write_ctl(k, &c)) != KS_OK)
		goto out;
	if (k->step)
		k->step(7, "journal cleared");

	/* 7. done */
	if (k->jrn.clear && k->jrn.clear(k->jrn.ctx) != 0) {
		rc = fail(k, KS_EIO, 0, "committed, but the journal could not be cleared");
		goto out;
	}
	*idp = id;
	sprintf(k->msg, pristine ? "generation %lu written as the pristine generation" :
		"generation %lu committed; power-cycle to boot it", (unsigned long)id);
out:
	for (i = 0; i < g->n; i++)
		free(zbuf[i]);
	return rc;
}

int
ks_mark_good(struct ks *k, ax_u32 booted, int primary_used)
{
	const struct ax_gen *g = ks_find(k, booted);
	struct ax_header h;
	struct ax_ctl c;
	int i, rc;

	k->gate = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	if (!g)
		return fail(k, KS_EREFUSE, 0, "the booted generation is not in the store");
	if (g->state == AXG_TRIAL && booted == k->ctl.trial_gen) {
		c = k->ctl;
		for (i = 0; i < c.ngen; i++)
			if (c.gen[i].id == booted) {
				c.gen[i].state = AXG_GOOD;
				c.gen[i].attempts = 0;
			}
		c.default_gen = booted;
		c.trial_gen = 0;
		keep(&c);
		if ((rc = write_ctl(k, &c)) != KS_OK)
			return rc;
		sprintf(k->msg, "generation %lu is good and the default", (unsigned long)booted);
	} else {
		sprintf(k->msg, "generation %lu is %s; nothing to mark", (unsigned long)booted,
			g->state == AXG_GOOD ? "good" : g->state == AXG_PRISTINE ? "pristine" :
			g->state == AXG_BAD ? "bad" : "not the trial");
	}
	if (k->hdr.flags & AXF_LDRTRIAL) {
		if (!primary_used) {
			sprintf(k->msg + strlen(k->msg), "; the new loader did not complete a boot "
				"(the previous one ran): run kbootset loader-install again to retry");
			return KS_OK;
		}
		h = k->hdr;
		h.flags &= ~AXF_LDRTRIAL;
		if ((rc = write_hdr(k, &h)) != KS_OK)
			return rc;
		strcat(k->msg, "; the new loader is accepted");
	}
	return KS_OK;
}

static char lastline[400];

/* line onto msg, cut at msg's end */
static void
append(struct ks *k, const char *line)
{
	size_t n = strlen(k->msg);

	while (*line && n + 1 < sizeof(k->msg))
		k->msg[n++] = *line++;
	k->msg[n] = 0;
}

static void
grab(const char *line)
{
	strncpy(lastline, line, sizeof(lastline) - 1);
	lastline[sizeof(lastline) - 1] = 0;
}

int
ks_refused(struct ks *k, ax_u32 booted)
{
	static struct ax_manifest m;
	const struct ax_gen *d = ks_find(k, k->ctl.default_gen), *t = ks_find(k, k->ctl.trial_gen),
			    *b = ks_find(k, booted);
	char why[400], line[600], *buf;
	struct ax_ctl c;
	int i, rc;

	k->gate = 0;
	if (!d || !b || d->id == booted || d->state != AXG_GOOD ||
	    (b->state != AXG_GOOD && b->state != AXG_PRISTINE))
		return KS_OK;
	if (t && t->state == AXG_TRIAL && t->attempts)
		return KS_OK;		/* the trial was tried first: L8 takes it back */
	if ((rc = writable(k)) != KS_OK)
		return rc;
	why[0] = 0;
	if ((buf = manifest(k, d, &m)) == 0)
		sprintf(why, "generation %lu: manifest unreadable or damaged", (unsigned long)d->id);
	else {
		if (check_member(k, d->id, "kernel", &m.kernel, grab))
			strcpy(why, lastline);
		for (i = 0; !why[0] && i < m.nmod; i++)
			if (check_member(k, d->id, "module", &m.mod[i], grab))
				strcpy(why, lastline);
		if (!why[0] && m.has_ramdisk && check_member(k, d->id, "ramdisk", &m.ramdisk, grab))
			strcpy(why, lastline);
		free(buf);
	}
	if (!why[0]) {
		sprintf(line, "%sthe loader passed over the default, generation %lu, but its members "
			"verify: it stays the default (the loader's L line says why)",
			k->msg[0] ? "; " : "", (unsigned long)d->id);
		append(k, line);
		return KS_OK;
	}
	c = k->ctl;
	for (i = 0; i < c.ngen; i++)
		if (c.gen[i].id == d->id)
			c.gen[i].state = AXG_BAD;
	if (c.oneshot == AXO_GEN && c.oneshot_gen == d->id)
		c.oneshot = AXO_NONE, c.oneshot_gen = 0;
	c.default_gen = booted;
	keep(&c);
	sprintf(line, "%sthe loader refused the default and the store confirms it (%.120s): "
		"generation %lu marked bad, the default is generation %lu", k->msg[0] ? "; " : "",
		why, (unsigned long)d->id, (unsigned long)booted);
	if ((rc = write_ctl(k, &c)) != KS_OK)
		return rc;
	append(k, line);
	return KS_OK;
}

int
ks_retry(struct ks *k, ax_u32 booted)
{
	const struct ax_gen *g = ks_find(k, booted);
	struct ax_ctl c;
	int i, rc;

	k->gate = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	if (!g || g->state != AXG_TRIAL || booted != k->ctl.trial_gen || !g->attempts)
		return fail(k, KS_OK, 0, "the booted generation is not a trial on its attempt: nothing to give back");
	if ((g->flags & 3) >= KS_RETRIES)
		return fail(k, KS_OK, 0, "this trial's attempt was given back twice already: it stands");
	c = k->ctl;
	for (i = 0; i < c.ngen; i++)
		if (c.gen[i].id == booted) {
			c.gen[i].attempts = 0;
			c.gen[i].flags = (ax_u8)((c.gen[i].flags & ~3) | ((c.gen[i].flags & 3) + 1));
		}
	if ((rc = write_ctl(k, &c)) != KS_OK)
		return rc;
	sprintf(k->msg, "generation %lu gets its trial boot again (the fsck reboot did not count)",
		(unsigned long)booted);
	return KS_OK;
}

int
ks_rollback(struct ks *k, ax_u32 *to)
{
	ax_u32 best = 0;
	struct ax_ctl c;
	char m[120];
	int i, rc;

	k->gate = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	for (i = 0; i < k->ctl.ngen; i++) {
		const struct ax_gen *g = &k->ctl.gen[i];

		if ((g->state == AXG_GOOD || g->state == AXG_PRISTINE) &&
		    g->id < k->ctl.default_gen && g->id > best)
			best = g->id;
	}
	if (!best)
		return fail(k, KS_EREFUSE, 0, "no good or pristine generation older than the default");
	c = k->ctl;
	if (c.trial_gen)
		for (i = 0; i < c.ngen; i++)
			if (c.gen[i].id == c.trial_gen)
				c.gen[i].state = AXG_BAD;	/* cancelled; collected below */
	c.trial_gen = 0;
	sprintf(m, "the default is generation %lu (was %lu)", (unsigned long)best,
		(unsigned long)c.default_gen);
	c.default_gen = best;
	keep(&c);
	if ((rc = write_ctl(k, &c)) != KS_OK)
		return rc;
	*to = best;
	return fail(k, KS_OK, 0, m);
}

int
ks_next(struct ks *k, int req, ax_u32 gen)
{
	const struct ax_gen *g;
	struct ax_ctl c;
	int rc;

	k->gate = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	if (req == AXO_GEN && (!(g = ks_find(k, gen)) || g->state == AXG_BAD))
		return fail(k, KS_EREFUSE, 0, "no such bootable generation");
	if (req < AXO_NONE || req > AXO_DEVLOAD)
		return fail(k, KS_EREFUSE, 0, "unknown request");
	c = k->ctl;
	c.oneshot = (ax_u8)req;
	c.oneshot_gen = req == AXO_GEN ? gen : 0;
	if ((rc = write_ctl(k, &c)) != KS_OK)
		return rc;
	return fail(k, KS_OK, 0, req == AXO_NONE ? "no request for the next boot" :
		    "the next boot only is changed");
}

int
ks_mark_bad(struct ks *k, ax_u32 id)
{
	const struct ax_gen *g = ks_find(k, id);
	struct ax_ctl c;
	int i, rc;

	k->gate = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	if (!g)
		return fail(k, KS_EREFUSE, 0, "no such generation");
	if (g->state == AXG_PRISTINE)
		return fail(k, KS_EREFUSE, 0, "the pristine generation is never marked bad");
	if (id == k->ctl.default_gen)
		return fail(k, KS_EREFUSE, 0, "that is the default generation; roll back first");
	c = k->ctl;
	for (i = 0; i < c.ngen; i++)
		if (c.gen[i].id == id)
			c.gen[i].state = AXG_BAD;
	if (c.trial_gen == id)
		c.trial_gen = 0;
	if (c.oneshot == AXO_GEN && c.oneshot_gen == id)
		c.oneshot = AXO_NONE, c.oneshot_gen = 0;
	keep(&c);
	if ((rc = write_ctl(k, &c)) != KS_OK)
		return rc;
	return fail(k, KS_OK, 0, "marked bad and collected");
}

int
ks_collect(struct ks *k)
{
	struct ax_ctl c;
	int rc, before = k->ctl.ngen;

	k->gate = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	c = k->ctl;
	keep(&c);
	if (c.ngen == before)
		return fail(k, KS_OK, 0, "nothing to collect");
	if ((rc = write_ctl(k, &c)) != KS_OK)
		return rc;
	sprintf(k->msg, "%d generation(s) collected", before - c.ngen);
	return KS_OK;
}

int
ks_loader_install(struct ks *k, const ax_u8 *boot2, ax_u32 len, ax_u32 version,
		  const ax_u8 *boot1)
{
	struct ax_header h;
	ax_u8 *cur;
	ax_u32 clen = k->hdr.boot2[0].len;
	int rc;

	k->gate = 0;
	if ((rc = writable(k)) != KS_OK)
		return rc;
	if (len == 0 || len > AX_BOOT2_MAX)
		return fail(k, KS_EREFUSE, 0, "boot2 must be 1..28672 bytes");
	if (boot1 && (memcmp(boot1, "DOS\0", 4) != 0))
		return fail(k, KS_EREFUSE, 0, "boot1 is not a framed bootblock");
	/* 1. the current primary becomes the secondary: written and recorded
	 * before the primary area is touched, so both copies are good */
	if (clen == 0 || clen > AX_BOOT2_MAX || (cur = malloc(clen)) == 0)
		return fail(k, KS_ESTORE, 0, "the installed loader is not recorded");
	if ((rc = get(k, k->hdr.boot2[0].off, cur, clen)) != KS_OK) {
		free(cur);
		return rc;
	}
	if (ax_crc32(k->crctab, cur, clen) != k->hdr.boot2[0].crc) {
		free(cur);
		return fail(k, KS_EREFUSE, 0, "the installed primary loader is damaged; "
			    "not replacing the copy the box can still boot");
	}
	rc = put(k, AX_BOOT2_B_OFF, cur, clen);
	free(cur);
	if (rc != KS_OK)
		return rc;
	h = k->hdr;
	h.boot2[1] = h.boot2[0];
	h.boot2[1].off = AX_BOOT2_B_OFF;
	if ((rc = write_hdr(k, &h)) != KS_OK)
		return rc;
	/* 2. the new primary; until the header names it, its CRC does not
	 * match and boot1 takes the secondary (B2) */
	if ((rc = put(k, AX_BOOT2_A_OFF, boot2, len)) != KS_OK)
		return rc;
	h = k->hdr;
	h.boot2[0].off = AX_BOOT2_A_OFF;
	h.boot2[0].len = len;
	h.boot2[0].crc = ax_crc32(k->crctab, boot2, len);
	h.boot2[0].ver = version;
	h.flags |= AXF_LDRTRIAL;
	if ((rc = write_hdr(k, &h)) != KS_OK)
		return rc;
	/* 3. boot1, only when asked: there is no second copy of it */
	if (boot1 && (rc = put(k, AX_BOOT1_OFF, boot1, AX_BOOT1_MAX)) != KS_OK)
		return rc;
	sprintf(k->msg, "loader version %lu installed on trial%s; power-cycle to boot it",
		(unsigned long)version, boot1 ? " (boot1 replaced)" : "");
	return KS_OK;
}
