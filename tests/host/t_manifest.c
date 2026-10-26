/*
 * t_manifest.c -- GMF1 parser: the spec's example, every refusal path.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#include <stdio.h>
#include <string.h>
#include "t.h"
#include "crc32.h"
#include "manifest.h"

static ax_u32 tab[256];
static char buf[8192];
static struct ax_manifest m;

/* body + a correct end line; returns the length */
static ax_u32
seal(const char *body)
{
	ax_u32 n = strlen(body);

	memcpy(buf, body, n);
	sprintf(buf + n, "end crc32=%08x\n", (unsigned)ax_crc32(tab, (const ax_u8 *)body, n));
	return strlen(buf);
}

static int
parse(ax_u32 len, int *line)
{
	return ax_manifest_parse(tab, buf, len, &m, line);
}

static const char *example_lines[] = {
	"GMF1\n",
	"generation 41\n",
	"line k46\n",
	"kabi k46.1.0\n",
	"cpu 68040 68060\n",
	"loader-min 1\n",
	"created 2026-11-02T10:00:00Z\n",
	"rootfs ufs\n",
	"root sd id=144b0100 base=00000000 unit=6 slice=1\n",
	"swap sd id=144b0100 base=00000000 unit=6 slice=2\n",
	"boards 144b0100 02025400\n",
	"arena 0x001f2000 0x00080000\n",
	"ident 0x001f1fc0\n",
	"kernel unix 2101234 at=0x00012000 stored=1203317 z=deflate crc32=1a2b3c4d sha256=00ff\n",
	"module z3660scsi root 45678 at=0x00134000 stored=20000 z=deflate crc32=0badf00d match=zorro:144b:01\n",
	"module gayle-ide root 19876 at=0x0013a000 crc32=00000001 match=mobo:gayle\n",
	"module z3660eth boot 30212 path=/stand/gen/41/mod/z3660eth sha256=abcd\n",
	"param z3660eth.intr=6\n",
	"future-key whatever\n",
	0
};
static char example[2048];


void
test_manifest(void)
{
	int line;
	ax_u32 n;
	char body[4096];

	ax_crc32_init(tab);
	example[0] = 0;
	for (n = 0; example_lines[n]; n++)
		strcat(example, example_lines[n]);

	n = seal(example);
	T_EQ(parse(n, &line), AXM_OK);
	T_EQ(m.generation, 41);
	T_CHECK(m.line && strcmp(m.line, "k46") == 0);
	T_CHECK(m.cpu && strcmp(m.cpu, "68040 68060") == 0);
	T_CHECK(m.root && strcmp(m.root, "sd id=144b0100 base=00000000 unit=6 slice=1") == 0);
	T_CHECK(m.rootfs && strcmp(m.rootfs, "ufs") == 0);
	T_EQ(m.has_arena, 1);
	T_EQ(m.arena_off, 0x1f2000);
	T_EQ(m.arena_cap, 0x80000);
	T_EQ(m.has_ident, 1);
	T_EQ(m.ident_off, 0x1f1fc0);
	T_EQ(m.kernel.size, 2101234);
	T_EQ(m.kernel.stored, 1203317);
	T_EQ(m.kernel.z, AXZ_DEFLATE);
	T_EQ(m.kernel.crc, 0x1a2b3c4dUL);
	T_EQ(m.kernel.at, 0x12000);
	T_EQ(m.kernel.vol, 1);
	T_EQ(m.nmod, 3);
	T_EQ(m.mod[0].cls, AXC_ROOT);
	T_CHECK(m.mod[0].match && strcmp(m.mod[0].match, "zorro:144b:01") == 0);
	T_EQ(m.mod[1].stored, 19876);	/* uncompressed: stored = size */
	T_EQ(m.mod[2].cls, AXC_BOOT);
	T_CHECK(m.mod[2].path != 0);
	T_EQ(m.nparam, 1);
	T_CHECK(strcmp(m.param[0], "z3660eth.intr=6") == 0);

	/* a static stage-1 generation: kernel only, brel, uncompressed */
	n = seal("GMF1\ngeneration 1\nline k30\nkernel unix 1267397 at=0x10800 crc32=cafebabe\n");
	T_EQ(parse(n, &line), AXM_OK);
	T_EQ(m.has_arena, 0);
	T_EQ(m.has_ident, 0);
	T_EQ(m.nmod, 0);
	T_EQ(m.kernel.bss, 0);
	/* a brel kernel's bss (its format does not record it) */
	n = seal("GMF1\ngeneration 1\nline k46\nkernel unix 1459584 at=0x10800 crc32=cafebabe bss=283445\n");
	T_EQ(parse(n, &line), AXM_OK);
	T_EQ(m.kernel.bss, 283445);

	/* multi-volume extent */
	n = seal("GMF1\ngeneration 2\nline k30\nkernel unix 10 at=2:0x800 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_OK);
	T_EQ(m.kernel.vol, 2);
	T_EQ(m.kernel.at, 0x800);

	/* a CD manifest: members by file name in the line directory */
	n = seal("GMF1\ngeneration 7\nline k46\nroot sd id=c0de0100 unit=1 slice=1\n"
		 "kernel unix 1500000 file=UNIX stored=700000 z=deflate crc32=12345678\n");
	T_EQ(parse(n, &line), AXM_OK);
	T_CHECK(m.kernel.file && strcmp(m.kernel.file, "UNIX") == 0);
	T_EQ(m.kernel.has_at, 0);
	T_EQ(m.kernel.stored, 700000);
	/* both an extent and a file: refused */
	n = seal("GMF1\ngeneration 7\nline k46\nkernel unix 10 at=0x800 file=UNIX crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_EMISSING);

	/* refusals */
	n = seal(example);
	buf[30] ^= 1;			/* one changed byte */
	T_EQ(parse(n, &line), AXM_ECRC);

	n = seal("GMF2\ngeneration 1\nline k30\nkernel unix 1 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_EHEAD);

	strcpy(body, example);
	strcat(body, "!future-critical yes\n");
	n = seal(body);
	T_EQ(parse(n, &line), AXM_ECRIT);
	T_EQ(line, 20);			/* the 20th line */

	/* a known key may carry the critical mark */
	n = seal("GMF1\n!generation 3\nline k30\nkernel unix 1 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_OK);
	T_EQ(m.generation, 3);

	n = seal("GMF1\ngeneration 1\nline k30\n");
	T_EQ(parse(n, &line), AXM_EMISSING);		/* no kernel */

	n = seal("GMF1\ngeneration 1\nline k30\nkernel unix 1 at=0x900 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_EMISSING);		/* misaligned extent */

	n = seal("GMF1\ngeneration 1\nline k30\nkernel unix 1 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_EMISSING);		/* no extent */

	n = seal("GMF1\ngeneration 1\nline k30\nkernel unix 5 at=0 stored=4 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_ESYNTAX);		/* stored != size without compression */

	n = seal("GMF1\ngeneration 1\nline k30\nline k46\nkernel unix 1 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_EDUP);

	n = seal("GMF1\ngeneration 1\nline k30\nident 0x40\nident 0x40\nkernel unix 1 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_EDUP);

	n = seal("GMF1\ngeneration 1\nline k30\nident 0x40 0x80\nkernel unix 1 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_ESYNTAX);

	n = seal("GMF1\ngeneration 1\nline k30\nkernel unix 1 at=0 crc32=00000000\nmodule x root 9 path=/a\n");
	T_EQ(parse(n, &line), AXM_EMISSING);		/* root module without an extent */

	n = seal("GMF1\ngeneration 1\nline k30\nkernel unix 1 at=0 crc32=00000000\nmodule x boot 9 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_EMISSING);		/* boot module without a path */

	n = seal("GMF1\ngeneration 1\nline k30\nkernel unix 1 at=0 crc32=0000000g\n");
	T_EQ(parse(n, &line), AXM_ESYNTAX);

	n = seal("GMF1\ngeneration 0x\nline k30\nkernel unix 1 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_ESYNTAX);

	/* overlong line */
	memset(body, 'a', 300);
	memcpy(body, "GMF1\nx ", 7);
	body[300] = '\n';
	body[301] = 0;
	n = seal(body);
	T_EQ(parse(n, &line), AXM_ELONG);

	/* a control character */
	n = seal("GMF1\ngeneration 1\tx\nline k30\nkernel unix 1 at=0 crc32=00000000\n");
	T_EQ(parse(n, &line), AXM_ELONG);

	/* bytes after the end line, and no end line */
	n = seal(example);
	strcpy(buf + n, "extra\n");
	T_EQ(parse(n + 6, &line), AXM_EEND);
	strcpy(buf, "GMF1\ngeneration 1\n");
	T_EQ(parse(strlen(buf), &line), AXM_EEND);
	/* no final newline */
	n = seal(example);
	T_EQ(parse(n - 1, &line), AXM_EEND);

	/* too many modules */
	strcpy(body, "GMF1\ngeneration 1\nline k30\nkernel unix 1 at=0 crc32=00000000\n");
	for (n = 0; n < AXM_MAXMOD + 1; n++)
		sprintf(body + strlen(body), "module m%u demand 1 path=/x\n", (unsigned)n);
	n = seal(body);
	T_EQ(parse(n, &line), AXM_EMANY);
}
