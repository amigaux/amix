/*
 * corechk.h -- reading back a core dump of vm30's core cases (an ELF core, big-endian, whatever the host): included by
 * vm30.c and by the host test t_corechk.c.
 *
 * MIT licence, see LICENSE in kernel/k30.
 */
#define CK_PG	2048

static unsigned long ck_be32(unsigned char *b) { return (unsigned long)b[0] << 24 | (unsigned long)b[1] << 16 | (unsigned long)b[2] << 8 | b[3]; }

/* program header i of a core: 0, or -1 when it cannot be read */
static int ck_phdr(int fd, unsigned long i, unsigned long *type, unsigned long *o, unsigned long *v, unsigned long *fsz)
{
	unsigned char e[52], ph[32];

	lseek(fd, (off_t)0, 0);
	if (read(fd, (char *)e, 52) != 52 || i >= ((unsigned long)e[44] << 8 | e[45]))
		return -1;
	lseek(fd, (off_t)(ck_be32(e + 28) + i * 32), 0);
	if (read(fd, (char *)ph, 32) != 32)
		return -1;
	*type = ck_be32(ph);
	*o = ck_be32(ph + 4);
	*v = ck_be32(ph + 8);
	*fsz = ck_be32(ph + 16);
	return 0;
}

/* the byte of a core at address a, or -1: no segment holds it, -2 past its end */
static int coreat(int fd, char *a)
{
	unsigned long i, type, o, v, fsz;
	unsigned char c;

	for (i = 0; ck_phdr(fd, i, &type, &o, &v, &fsz) == 0; i++) {
		if (type != 1 || (unsigned long)a < v || (unsigned long)a >= v + fsz)
			continue;
		lseek(fd, (off_t)(o + ((unsigned long)a - v)), 0);
		return read(fd, (char *)&c, 1) == 1 ? c : -2;
	}
	return -1;
}

/* the length a core's program headers give it: the end of its last PT_LOAD data */
static unsigned long coreend(int fd)
{
	unsigned long i, type, o, v, fsz, end = 0;

	for (i = 0; ck_phdr(fd, i, &type, &o, &v, &fsz) == 0; i++)
		if (type == 1 && fsz != 0 && o + fsz > end)
			end = o + fsz;
	return end;
}

/* a core of vm30's 16 pages at p, page i holding i + 1, with denied: pages 3 and 15 PROT_NONE.  0; 4: a page wrong
 * (a PROT_NONE page must read back 0, as a hole does: neither missing from the headers nor past the file's end);
 * 5: the file shorter than its headers say */
static int corecheck(int fd, long size, char *p, int denied)
{
	int i, v, bad = 0;

	if ((unsigned long)size < coreend(fd)) {
		printf("core: %ld bytes, its program headers say %lu\n", size, coreend(fd));
		return 5;
	}
	for (i = 0; i < 16; i++) {
		int none = denied && (i == 3 || i == 15);

		v = coreat(fd, p + i * CK_PG);
		if (none ? v != 0 : v != i + 1) {
			printf("core page %d: %d\n", i, v);
			bad++;
		}
	}
	return bad ? 4 : 0;
}
