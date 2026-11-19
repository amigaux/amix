/*
 * gencat - host build of the AMIX message catalogue generator.
 *
 * MIT licence, see LICENSE at the top of the repository.
 *
 * Writes the same bytes as the gencat(1) of AMIX 2.1c (SVR4.0, m68k)
 * on any host: every integer in the output is a 32-bit big-endian
 * value, whatever the byte order of the machine this runs on.
 *
 * Usage:  gencat [-l] [-m] catfile [msgfile ...]
 *         gencat --dump catfile
 *
 * Without -m two files are written: "catfile" (the set table) and
 * "catfile.m" (a string file in mkmsgs(1) format, which this program
 * writes itself instead of running mkmsgs).  With -m one file in the
 * older self-contained ("malloc") format is written.  An existing
 * catfile of either format is read first and the source merged over
 * it.  -l lists the messages read back from an existing catfile.
 * --dump is an extension: it decodes a catalogue of either format the
 * way catgets(3C) does and prints every message.
 *
 * File formats (all integers 32-bit big-endian; see FORMAT.md):
 *
 *   -m ("malloc") catalogue
 *     header, 20 bytes:
 *       magic          0xFF88FF89
 *       nsets          number of set headers
 *       mem            size of everything after the header
 *       off_msg_hdr    offset of the message headers (from end of header)
 *       off_msg        offset of the message text    (from end of header)
 *     nsets set headers, 12 bytes each, ascending set number:
 *       set number, number of messages, index of its first message header
 *     message headers, 12 bytes each, set by set, ascending number:
 *       message number, length (text plus NUL), offset into the text area
 *     text area: every message followed by a NUL, in header order.
 *
 *   default catfile (set table)
 *     count          highest set number N (0 if no sets)
 *     N entries, 8 bytes each, entry i for set i:
 *       first        index in catfile.m of message 1 of set i (0: no set)
 *       last         highest message number in set i (0: no set)
 *     A message m of set i is string (first + m - 1) of catfile.m.
 *
 *   catfile.m (mkmsgs format)
 *     count          number of strings K
 *     K offsets      offset of string k (k = 1..K) from start of file
 *     K strings      each NUL-terminated
 *     A message number that is not defined inside a set's range is the
 *     one-byte string "\001", which the readers treat as "no message".
 *
 * The source is parsed line by line in a fixed 1024-byte line buffer,
 * the way the target tool does it, so that odd input (a last line with
 * no newline, an over-long line) gives the same result.  Default-mode
 * text keeps \n and \\ as two-character escapes and goes through the
 * same second escape pass mkmsgs applies, so the two modes can differ
 * for text that produces a raw backslash or newline byte.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define SRC_LINE	0x400		/* fgets size for source lines */
#define TEXT_MAX	0x400		/* longest converted message */
#define SET_MAX		1024
#define MSG_MAX		32767
#define CAT_MAGIC	0xFF88FF89UL
#define DFLT_MSG	"\001"
#define NOT_FOUND	"Message not found!!\n"
#define MK_LINE		0x800		/* mkmsgs input line buffer */

struct msg {
	int32_t nr;
	int32_t len;		/* text length including the NUL */
	unsigned char *text;
	struct msg *next;
};

struct set {
	int32_t nr;
	struct msg *msgs;
	struct set *next;
};

static struct set *sets;
static int32_t curset = 1;
static int no_output;
static int list_flag;
static int malloc_format;
static long scratch_off;	/* running offset printed by -l */

/*
 * Line buffer.  Continuation lines are read at the offset where the
 * message text started, with the full line size, so the buffer has
 * room for that; the target tool would run past its buffer there.
 */
static unsigned char linebuf[2 * SRC_LINE + 8];
static unsigned char msgbuf[TEXT_MAX + 8];

static const char *progname = "gencat";

/*
 * Character classes of the target's default table, which classifies
 * the upper half as ISO 8859-1: 0xA0 is white space (and, like the
 * space, not a control character), 0x80-0x9F are control characters.
 */
static int c_space(int c)
{
	return c == ' ' || (c >= '\t' && c <= '\r') || c == 0xa0;
}
static int c_cntrl(int c)
{
	return (c >= 0 && c < 0x20) || (c >= 0x7f && c <= 0x9f);
}
static int c_digit(int c) { return c >= '0' && c <= '9'; }
static int c_xdigit(int c)
{
	return c_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}
static int c_lower(int c) { return (c >= 'A' && c <= 'Z') ? c + 32 : c; }

static void fatal(void)
{
	exit(1);
}

static void *xmalloc(size_t n)
{
	void *p = malloc(n ? n : 1);

	if (p == NULL) {
		fprintf(stderr, "%s: out of memory\n", progname);
		fatal();
	}
	return p;
}

static unsigned char *dupbytes(const unsigned char *s, size_t n)
{
	unsigned char *p = xmalloc(n);

	memcpy(p, s, n);
	return p;
}

static void put32(unsigned char *p, uint32_t v)
{
	p[0] = (unsigned char)(v >> 24);
	p[1] = (unsigned char)(v >> 16);
	p[2] = (unsigned char)(v >> 8);
	p[3] = (unsigned char)v;
}

static int32_t get32(const unsigned char *p)
{
	return (int32_t)(((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
	    ((uint32_t)p[2] << 8) | (uint32_t)p[3]);
}

/* growable byte buffer */
struct buf {
	unsigned char *p;
	size_t len, cap;
};

static void buf_add(struct buf *b, const void *s, size_t n)
{
	if (b->len + n > b->cap) {
		size_t cap = b->cap ? b->cap : 256;
		unsigned char *np;

		while (cap < b->len + n)
			cap *= 2;
		np = realloc(b->p, cap);
		if (np == NULL) {
			fprintf(stderr, "%s: out of memory\n", progname);
			fatal();
		}
		b->p = np;
		b->cap = cap;
	}
	if (n)
		memcpy(b->p + b->len, s, n);
	b->len += n;
}

static void buf_add32(struct buf *b, uint32_t v)
{
	unsigned char q[4];

	put32(q, v);
	buf_add(b, q, 4);
}

/* ---------------------------------------------------------------- */
/* the in-memory catalogue                                          */

static struct set *get_set(int32_t nr)
{
	struct set *s;

	for (s = sets; s != NULL; s = s->next)
		if (s->nr == nr)
			return s;
	return NULL;
}

/* list walk: stop at an equal number (found) or a greater one (insert) */
static void add_set(int32_t nr)
{
	struct set *s, *prev, *n;

	if (nr > SET_MAX || nr <= 0) {
		fprintf(stderr, "Invalid set number %d -- Ignored\n", (int)nr);
		return;
	}
	prev = sets;
	for (s = sets; s != NULL; s = s->next) {
		if (nr == s->nr)
			goto done;
		if (nr < s->nr)
			break;
		prev = s;
	}
	n = xmalloc(sizeof *n);
	n->nr = nr;
	n->msgs = NULL;
	n->next = s;
	if (s == prev)
		sets = n;
	else
		prev->next = n;
done:
	curset = nr;
}

static void free_msgs(struct msg *m)
{
	while (m != NULL) {
		struct msg *nx = m->next;

		free(m->text);
		free(m);
		m = nx;
	}
}

static void del_set(int32_t nr)
{
	struct set *s, *prev;

	if (nr > SET_MAX || nr <= 0) {
		fprintf(stderr, "Invalid set number %d -- Ignored\n", (int)nr);
		return;
	}
	prev = sets;
	for (s = sets; s != NULL; s = s->next) {
		if (nr == s->nr)
			break;
		if (nr < s->nr) {
			s = NULL;
			break;
		}
		prev = s;
	}
	if (s == NULL) {
		fprintf(stderr, "del_set : Set not found %d -- Ignored\n",
		    (int)nr);
		return;
	}
	free_msgs(s->msgs);
	if (s == prev)
		sets = s->next;
	else
		prev->next = s->next;
	free(s);
	if (nr == 1)
		add_set(1);	/* set 1 always exists */
	if (nr == curset)
		curset = 1;
}

static void del_msg(int32_t setnr, int32_t nr)
{
	struct set *s = get_set(setnr);
	struct msg *m, *prev;

	if (s == NULL) {
		fprintf(stderr, "Invalid set number %d -- Ignored\n",
		    (int)setnr);
		return;
	}
	if (nr > MSG_MAX || nr <= 0) {
		fprintf(stderr, "Invalid message number %d -- Ignored\n",
		    (int)nr);
		return;
	}
	prev = s->msgs;
	for (m = s->msgs; m != NULL; m = m->next) {
		if (nr == m->nr)
			break;
		if (nr < m->nr) {
			m = NULL;
			break;
		}
		prev = m;
	}
	if (m == NULL) {
		fprintf(stderr, "del_msg : msg not found %d -- Ignored\n",
		    (int)nr);
		return;
	}
	if (m == prev)
		s->msgs = m->next;
	else
		prev->next = m->next;
	free(m->text);
	free(m);
}

static void add_msg(int32_t setnr, int32_t nr, int32_t len,
    const unsigned char *text)
{
	struct set *s = get_set(setnr);
	struct msg *m, *prev, *n;

	if (s == NULL) {
		fprintf(stderr, "Invalid set number %d -- Ignored\n",
		    (int)setnr);
		return;
	}
	if (nr > MSG_MAX || nr <= 0) {
		fprintf(stderr, "Invalid message number %d -- Ignored\n",
		    (int)nr);
		return;
	}
	if (len > TEXT_MAX + 1 || len < 0) {
		fprintf(stderr, "Invalid message length %d -- Ignored\n",
		    (int)len);
		return;
	}
	prev = s->msgs;
	for (m = s->msgs; m != NULL; m = m->next) {
		if (nr == m->nr)
			break;
		if (nr < m->nr)
			break;
		prev = m;
	}
	if (m != NULL && m->nr == nr) {
		free(m->text);
		n = m;
	} else {
		n = xmalloc(sizeof *n);
		n->nr = nr;
		n->next = m;
		if (m == prev)
			s->msgs = n;
		else
			prev->next = n;
	}
	n->len = len;
	n->text = dupbytes(text, (size_t)len);
	scratch_off += len;
}

/* append at the end of the lists, in file order (read-back only) */
static struct set *append_set(int32_t nr)
{
	struct set *n = xmalloc(sizeof *n), **pp = &sets;

	n->nr = nr;
	n->msgs = NULL;
	n->next = NULL;
	while (*pp != NULL)
		pp = &(*pp)->next;
	*pp = n;
	return n;
}

static struct msg *append_msg(struct set *s, int32_t nr, int32_t len)
{
	struct msg *n = xmalloc(sizeof *n), **pp = &s->msgs;

	n->nr = nr;
	n->len = len;
	n->text = NULL;
	n->next = NULL;
	while (*pp != NULL)
		pp = &(*pp)->next;
	*pp = n;
	return n;
}

/* ---------------------------------------------------------------- */
/* source parsing                                                   */

/* skip spaces (not tabs); -1 at end of line */
static long skip_blanks(long i)
{
	while (linebuf[i] && c_space(linebuf[i]) && !c_cntrl(linebuf[i]))
		i++;
	if (linebuf[i] == '\0' || linebuf[i] == '\n')
		return -1;
	return i;
}

static int32_t c_atoi(const unsigned char *s)
{
	uint32_t v = 0;
	int neg = 0;

	while (c_space(*s))
		s++;
	if (*s == '-' || *s == '+')
		neg = *s++ == '-';
	while (c_digit(*s))
		v = v * 10 + (uint32_t)(*s++ - '0');
	return (int32_t)(neg ? 0u - v : v);
}

enum { S_LEAD, S_TEXT, S_ESC, S_NUM, S_ZERO, S_DIGITS, S_DONE };

/*
 * Convert the text of one message, starting at linebuf[start].
 * Returns the number of bytes put in msgbuf (a NUL follows), or -1.
 */
static int msg_conv(const char *fname, int32_t setnr, int32_t nr, FILE *fp,
    long start, int quote)
{
	unsigned char *line0 = linebuf + start;
	unsigned char *p = line0, *restart;
	unsigned char *out = msgbuf;
	unsigned char c = 0, acc = 0;
	int state = S_LEAD, quoted = 0, len = 0, base = 8;

#define PUT(ch) do {							\
		*out++ = (unsigned char)(ch);				\
		if (len + 1 > TEXT_MAX) {				\
			fprintf(stderr, "%s: set %d msg %d: "		\
			    "Invalid message length\n", fname,		\
			    (int)setnr, (int)nr);			\
			return -1;					\
		}							\
		len++;							\
	} while (0)

	if (quote == 0) {
		/* no quote character: one separator character is eaten */
		state = S_TEXT;
		if (c_space(*p))
			p++;
	}
	restart = p;

	while (state != S_DONE) {
		if (p >= linebuf + sizeof linebuf)
			goto overrun;
		c = *p++;
		switch (state) {
		case S_LEAD:	/* white space before an optional quote */
			if (c == '\n')
				state = S_DONE;
			else if (c == quote) {
				state = S_TEXT;
				quoted = 1;
			} else if (!c_space(c)) {
				state = S_TEXT;
				p = restart;
				quoted = 0;
			}
			break;
		case S_TEXT:
			if (c == '\n') {
				if (quoted) {
					fprintf(stderr, "%s: set %d msg %d: "
					    "Unmatched quote (%c)\n", fname,
					    (int)setnr, (int)nr, quote);
					return -1;
				}
				state = S_DONE;
			} else if (c == quote) {
				if (!quoted) {
					fprintf(stderr, "%s: set %d msg %d: "
					    "Unexpected quote (%c)\n", fname,
					    (int)setnr, (int)nr, quote);
					return -1;
				}
				state = S_DONE;
			} else if (c == '\\')
				state = S_ESC;
			else
				PUT(c);
			break;
		case S_ESC:
			if (c == quote && c != '\n') {
				PUT(c);
				state = S_TEXT;
				break;
			}
			state = S_TEXT;
			switch (c) {
			case '\\':
				/* default mode keeps \\ for the mkmsgs pass */
				if (!malloc_format)
					PUT('\\');
				PUT('\\');
				break;
			case 'n':
				if (malloc_format)
					PUT('\n');
				else {
					PUT('\\');
					PUT('n');
				}
				break;
			case 'r': PUT('\r'); break;
			case 'b': PUT('\b'); break;
			case 't': PUT('\t'); break;
			case 'v': PUT('\v'); break;
			case 'f': PUT('\f'); break;
			case '\'': PUT('\''); break;
			case '"': PUT('"'); break;
			case '\n':
				/* continuation: next line read in place */
				if (fgets((char *)line0, SRC_LINE, fp) == NULL)
					state = S_DONE;
				else
					p = line0;
				break;
			default:
				if (c_digit(c)) {
					state = S_NUM;
					p--;
				} else
					PUT(c);	/* unknown: backslash dropped */
				break;
			}
			break;
		case S_NUM:	/* first digit of a numeric escape */
			acc = 0;
			base = 8;
			if (!c_digit(c)) {
				state = S_TEXT;
				PUT(c);
			} else if (c == '0')
				state = S_ZERO;
			else {
				state = S_DIGITS;
				p--;
			}
			break;
		case S_ZERO:	/* "\0x" starts a hexadecimal escape */
			state = S_DIGITS;
			if (c == 'x' || c == 'X')
				base = 16;
			else
				p--;
			break;
		case S_DIGITS:	/* any number of digits, kept modulo 256 */
			if ((base == 8 && (c < '0' || c > '7')) ||
			    (base == 16 && !c_xdigit(c))) {
				p--;
				PUT(acc);
				state = S_TEXT;
				break;
			}
			acc = (unsigned char)(acc * base);
			c = (unsigned char)c_lower(c);
			acc = (unsigned char)(acc + (c > 0x60 ? c - 87 : c - 48));
			break;
		}
	}

	if (c == quote) {
		/* after a closing quote only white space may follow */
		for (;;) {
			if (p >= linebuf + sizeof linebuf)
				goto overrun;
			c = *p++;
			if (c == '\n')
				break;
			if (!c_space(c)) {
				fprintf(stderr, "%s: set %d msg %d: "
				    "Unexpected extra characters\n", fname,
				    (int)setnr, (int)nr);
				return -1;
			}
		}
	}
	*out = '\0';
	return len;
overrun:
	/* only reachable by running on past the end of a line */
	fprintf(stderr, "%s: set %d msg %d: line too long\n", fname,
	    (int)setnr, (int)nr);
	return -1;
#undef PUT
}

static void cat_msg_build(const char *fname, FILE *fp)
{
	int quote = 0;

	curset = 1;
	add_set(1);
	while (fgets((char *)linebuf, SRC_LINE, fp) != NULL) {
		long i = skip_blanks(0), j;
		uint32_t nr;
		int n;

		if (i < 0)
			continue;	/* empty line */
		if (linebuf[i] == '$') {
			const char *cmd = (const char *)linebuf + ++i;

			if (strncmp(cmd, "set", 3) == 0) {
				if ((j = skip_blanks(i + 3)) < 0)
					fprintf(stderr, "Incomplete set "
					    "command -- Ignored\n");
				else
					add_set(c_atoi(linebuf + j));
			} else if (strncmp(cmd, "delset", 6) == 0) {
				if ((j = skip_blanks(i + 6)) < 0)
					fprintf(stderr, "Incomplete delset "
					    "command -- Ignored\n");
				else
					del_set(c_atoi(linebuf + j));
			} else if (strncmp(cmd, "quote", 5) == 0) {
				j = skip_blanks(i + 5);
				quote = j < 0 ? 0 : linebuf[j];
			}
			/* anything else after $ is a comment */
			continue;
		}
		if (!c_digit(linebuf[i])) {
			fprintf(stderr, "Unexpected line -- Skipped\n");
			continue;
		}
		nr = 0;
		while (c_digit(linebuf[i]))
			nr = nr * 10 + (uint32_t)(linebuf[i++] - '0');
		if (linebuf[i] == '\n') {
			/* number alone: delete */
			del_msg(curset, (int32_t)nr);
			continue;
		}
		if (skip_blanks(i) < 0) {
			/* number and separator only: empty message */
			add_msg(curset, (int32_t)nr, 1,
			    (const unsigned char *)"");
			continue;
		}
		/* the text starts at the separator, not after the blanks:
		   msg_conv eats the one separator (no quote) or skips to the
		   quote, and unquoted text keeps the rest of the white space */
		n = msg_conv(fname, curset, (int32_t)nr, fp, i, quote);
		if (n < 0) {
			no_output = 1;
			continue;
		}
		add_msg(curset, (int32_t)nr, n + 1, msgbuf);
	}
}

/* ---------------------------------------------------------------- */
/* mkmsgs                                                           */

/*
 * Second escape pass (mkmsgs): \n \t \b \r \f \v \a \\ and one to
 * three octal digits; any other escaped character stands for itself.
 * The result ends at the first NUL it contains.
 */
static size_t mk_conv(unsigned char *dst, const unsigned char *src)
{
	unsigned char *d = dst;
	unsigned char c;

	while ((c = *src++) != '\0') {
		if (c != '\\') {
			*d++ = c;
			continue;
		}
		c = *src++;
		switch (c) {
		case 'n': *d++ = '\n'; break;
		case 't': *d++ = '\t'; break;
		case 'b': *d++ = '\b'; break;
		case 'r': *d++ = '\r'; break;
		case 'f': *d++ = '\f'; break;
		case 'v': *d++ = '\v'; break;
		case 'a': *d++ = 7; break;
		case '\\': *d++ = '\\'; break;
		case '\0':
			/* trailing backslash: the string ends here */
			*d = '\0';
			return (size_t)(d - dst);
		default:
			if (c >= '0' && c <= '7') {
				unsigned v = (unsigned)(c - '0');
				int k;

				for (k = 0; k < 2 && *src >= '0' &&
				    *src <= '7'; k++)
					v = (v << 3) | (unsigned)(*src++ - '0');
				*d++ = (unsigned char)v;
			} else
				*d++ = c;
			break;
		}
	}
	*d = '\0';
	return strlen((char *)dst);
}

/*
 * Build an mkmsgs-format file from newline-terminated input lines.
 * Returns 0, or -1 when mkmsgs would refuse the input.
 */
static int mkmsgs(const unsigned char *in, size_t inlen, struct buf *outb)
{
	struct buf strs = { NULL, 0, 0 };
	unsigned char line[MK_LINE + 8], conv[2 * MK_LINE + 8];
	size_t pos = 0, k, nlines = 0, off;
	size_t *lens = NULL, lcap = 0;

	while (pos < inlen) {
		size_t n = 0, cl;

		/* one fgets of at most MK_LINE - 1 bytes */
		while (n < MK_LINE - 1 && pos < inlen) {
			line[n++] = in[pos++];
			if (line[n - 1] == '\n')
				break;
		}
		line[n] = '\0';
		if (memchr(line, '\0', n) != NULL || line[n - 1] != '\n') {
			fprintf(stderr, "%s: mkmsgs pass: error on line %lu\n",
			    progname, (unsigned long)nlines);
			free(strs.p);
			free(lens);
			return -1;
		}
		line[n - 1] = '\0';
		cl = mk_conv(conv, line);
		buf_add(&strs, conv, cl + 1);
		if (nlines == lcap) {
			lcap = lcap ? 2 * lcap : 64;
			lens = realloc(lens, lcap * sizeof *lens);
			if (lens == NULL) {
				fprintf(stderr, "%s: out of memory\n", progname);
				fatal();
			}
		}
		lens[nlines++] = cl + 1;
	}
	buf_add32(outb, (uint32_t)nlines);
	off = 4 + 4 * nlines;
	for (k = 0; k < nlines; k++) {
		buf_add32(outb, (uint32_t)off);
		off += lens[k];
	}
	buf_add(outb, strs.p, strs.len);
	free(strs.p);
	free(lens);
	return 0;
}

/* ---------------------------------------------------------------- */
/* writing                                                          */

static int write_file(const char *name, const struct buf *b)
{
	FILE *f = fopen(name, "wb");

	if (f == NULL) {
		fprintf(stderr, "%s: cannot create %s\n", progname, name);
		return -1;
	}
	if (fwrite(b->p, 1, b->len, f) != b->len || fclose(f) != 0) {
		fprintf(stderr, "%s: write error on %s\n", progname, name);
		return -1;
	}
	return 0;
}

static int dump_malloc(const char *name)
{
	struct buf shdr = { NULL, 0, 0 }, mhdr = { NULL, 0, 0 };
	struct buf text = { NULL, 0, 0 }, out = { NULL, 0, 0 };
	struct set *s;
	struct msg *m;
	uint32_t nsets = 0, idx = 0;
	int rc;

	for (s = sets; s != NULL; s = s->next) {
		uint32_t count = 0, first = idx;

		nsets++;
		for (m = s->msgs; m != NULL; m = m->next) {
			count++;
			idx++;
			buf_add32(&mhdr, (uint32_t)m->nr);
			buf_add32(&mhdr, (uint32_t)m->len);
			buf_add32(&mhdr, (uint32_t)text.len);
			buf_add(&text, m->text, (size_t)m->len);
		}
		buf_add32(&shdr, (uint32_t)s->nr);
		buf_add32(&shdr, count);
		buf_add32(&shdr, first);
	}
	buf_add32(&out, (uint32_t)CAT_MAGIC);
	buf_add32(&out, nsets);
	buf_add32(&out, (uint32_t)(shdr.len + mhdr.len + text.len));
	buf_add32(&out, (uint32_t)shdr.len);
	buf_add32(&out, (uint32_t)(shdr.len + mhdr.len));
	buf_add(&out, shdr.p, shdr.len);
	buf_add(&out, mhdr.p, mhdr.len);
	buf_add(&out, text.p, text.len);
	rc = write_file(name, &out);
	free(shdr.p);
	free(mhdr.p);
	free(text.p);
	free(out.p);
	return rc;
}

static int dump_mkmsgs(const char *name)
{
	struct buf tab = { NULL, 0, 0 }, lines = { NULL, 0, 0 };
	struct buf mfile = { NULL, 0, 0 };
	struct set *s;
	struct msg *m;
	int32_t count = 0, index = 1;
	char *mname;
	int rc = -1;

	buf_add32(&tab, 0);	/* set count, filled in below */
	for (s = sets; s != NULL; s = s->next) {
		int32_t first = 0, last = 0;

		/* empty entries for set numbers not in use */
		for (count++; count != s->nr; count++) {
			buf_add32(&tab, 0);
			buf_add32(&tab, 0);
		}
		if (s->msgs != NULL)
			first = index;
		for (m = s->msgs; m != NULL; m = m->next) {
			int32_t k;

			/* placeholder lines for unused message numbers */
			for (k = last + 1; k < m->nr; k++, index++)
				buf_add(&lines, DFLT_MSG "\n", 2);
			last = m->nr;
			buf_add(&lines, m->text, (size_t)m->len - 1);
			buf_add(&lines, "\n", 1);
			index++;
		}
		buf_add32(&tab, (uint32_t)first);
		buf_add32(&tab, (uint32_t)last);
	}
	put32(tab.p, (uint32_t)count);
	if (write_file(name, &tab) != 0)
		goto out;
	if (mkmsgs(lines.p, lines.len, &mfile) != 0) {
		fprintf(stderr, "%s: %s.m not written\n", progname, name);
		goto out;
	}
	mname = xmalloc(strlen(name) + 3);
	strcpy(mname, name);
	strcat(mname, ".m");
	rc = write_file(mname, &mfile);
	free(mname);
out:
	free(tab.p);
	free(lines.p);
	free(mfile.p);
	return rc;
}

/* ---------------------------------------------------------------- */
/* reading an existing catalogue                                    */

static unsigned char *slurp(const char *name, size_t *len)
{
	FILE *f = fopen(name, "rb");
	struct buf b = { NULL, 0, 0 };
	unsigned char tmp[4096];
	size_t n;

	if (f == NULL)
		return NULL;
	while ((n = fread(tmp, 1, sizeof tmp, f)) > 0)
		buf_add(&b, tmp, n);
	fclose(f);
	buf_add(&b, "", 1);	/* guard NUL */
	*len = b.len - 1;
	return b.p;
}

/* a string of an mkmsgs file, as gettxt(3C) returns it */
static const char *mk_string(const unsigned char *mf, size_t mlen,
    int32_t idx)
{
	int32_t n, off;

	if (mf == NULL)
		return DFLT_MSG;	/* string file missing */
	if (mlen < 4)
		return NOT_FOUND;
	n = get32(mf);
	if (idx <= 0 || idx > n || (size_t)idx * 4 + 4 > mlen)
		return NOT_FOUND;
	off = get32(mf + 4 * idx);
	if (off < 0 || (size_t)off >= mlen)
		return NOT_FOUND;
	return (const char *)mf + off;	/* slurp() guarantees a final NUL */
}

/* escape newline and backslash again, for the mkmsgs pass */
static char *reescape(const char *s)
{
	char *d = xmalloc(2 * strlen(s) + 1), *p = d;

	for (; *s; s++) {
		if (*s == '\n') {
			*p++ = '\\';
			*p++ = 'n';
		} else if (*s == '\\') {
			*p++ = '\\';
			*p++ = '\\';
		} else
			*p++ = *s;
	}
	*p = '\0';
	return d;
}

static void read_malloc(FILE *f, const char *name)
{
	unsigned char h[20];
	int32_t nsets, i, k, *counts;
	struct set *s, *first = NULL;
	struct msg *m;

	rewind(f);
	if (fread(h, 20, 1, f) != 1) {
		fprintf(stderr, "%s : Cannot read header\n", name);
		fatal();
	}
	nsets = get32(h + 4);
	counts = xmalloc(sizeof *counts * (size_t)(nsets > 0 ? nsets : 1));
	for (i = 0; i < nsets; i++) {
		unsigned char sh[12];

		if (fread(sh, 12, 1, f) != 1) {
			fprintf(stderr, "Cannot read set headers\n");
			fatal();
		}
		s = append_set(get32(sh));
		if (first == NULL)
			first = s;
		counts[i] = get32(sh + 4);
	}
	for (s = first, i = 0; s != NULL; s = s->next, i++) {
		for (k = 0; k < counts[i]; k++) {
			unsigned char mh[12];

			if (fread(mh, 12, 1, f) != 1) {
				fprintf(stderr, "%s: Cannot read message "
				    "headers\n", name);
				fatal();
			}
			append_msg(s, get32(mh), get32(mh + 4));
		}
	}
	free(counts);
	/* the text follows the headers and is read in header order */
	for (s = sets; s != NULL; s = s->next) {
		for (m = s->msgs; m != NULL; m = m->next) {
			size_t n = m->len > 0 ? (size_t)m->len : 0;

			m->text = xmalloc(n + 1);
			if (fread(m->text, 1, n, f) != n) {
				fprintf(stderr, "%s: Cannot read messages\n",
				    name);
				fatal();
			}
			if (list_flag)
				printf("Set %d,Message %d,Offset %ld,"
				    "Length %d\n%.*s\n*\n", (int)s->nr,
				    (int)m->nr, scratch_off, (int)m->len,
				    (int)m->len, (char *)m->text);
			scratch_off += m->len;
		}
	}
}

static void read_mkmsgs(FILE *f, const char *name)
{
	unsigned char hb[8], *mf;
	size_t mlen = 0;
	int32_t nsets, setnr;
	char *mname;

	rewind(f);
	if (fread(hb, 1, 4, f) != 4) {
		fprintf(stderr, "%s: Cannot get number of sets\n", name);
		fatal();
	}
	nsets = get32(hb);
	mname = xmalloc(strlen(name) + 3);
	strcpy(mname, name);
	strcat(mname, ".m");
	mf = slurp(mname, &mlen);
	free(mname);
	for (setnr = 1; setnr <= nsets; setnr++) {
		int32_t first, last, nr, idx;
		struct set *s;

		if (fread(hb, 1, 8, f) != 8) {
			fprintf(stderr, "%s: Cannot get set information\n",
			    name);
			fatal();
		}
		first = get32(hb);
		last = get32(hb + 4);
		if (first == 0)
			continue;
		s = append_set(setnr);
		idx = first;
		for (nr = 1; nr <= last && idx != 0; nr++, idx++) {
			char *t = reescape(mk_string(mf, mlen, idx));
			struct msg *m;

			if (strcmp(t, DFLT_MSG) == 0) {
				free(t);
				continue;
			}
			m = append_msg(s, nr, (int32_t)strlen(t) + 1);
			m->text = (unsigned char *)t;
			if (list_flag)
				printf("Set %d,Message %d,Text %s\n*\n",
				    (int)setnr, (int)nr, t);
			scratch_off += m->len;
		}
	}
	free(mf);
}

static void cat_build(const char *name)
{
	FILE *f = fopen(name, "rb");
	unsigned char mb[4];

	if (f == NULL)
		return;		/* new catalogue */
	if (fread(mb, 4, 1, f) != 1) {
		fprintf(stderr, "%s : Cannot read catalog\n", name);
		fatal();
	}
	if ((uint32_t)get32(mb) == (uint32_t)CAT_MAGIC)
		read_malloc(f, name);
	else
		read_mkmsgs(f, name);
	fclose(f);
}

/* ---------------------------------------------------------------- */
/* --dump: decode like catgets(3C)                                  */

static void print_text(const unsigned char *s, size_t n)
{
	size_t i;

	for (i = 0; i < n; i++) {
		unsigned c = s[i];

		switch (c) {
		case '\n': fputs("\\n", stdout); break;
		case '\t': fputs("\\t", stdout); break;
		case '\v': fputs("\\v", stdout); break;
		case '\b': fputs("\\b", stdout); break;
		case '\r': fputs("\\r", stdout); break;
		case '\f': fputs("\\f", stdout); break;
		case '\\': fputs("\\\\", stdout); break;
		default:
			if (c < 0x20 || c >= 0x7f)
				printf("\\%03o", c);
			else
				putchar((int)c);
		}
	}
}

/* length of a C string held in at most max bytes */
static size_t cstrlen(const unsigned char *s, int32_t max)
{
	size_t n = 0;

	while ((int32_t)n < max && s[n] != '\0')
		n++;
	return n;
}

static int dump_catalogue(const char *name)
{
	size_t len = 0, mlen = 0;
	unsigned char *f = slurp(name, &len), *mf;
	char *mname;
	int32_t i, k;

	if (f == NULL) {
		fprintf(stderr, "%s: cannot open %s\n", progname, name);
		return 1;
	}
	if (len >= 20 && (uint32_t)get32(f) == (uint32_t)CAT_MAGIC) {
		int32_t nsets = get32(f + 4);
		const unsigned char *body = f + 20;
		int32_t omh = get32(f + 12), om = get32(f + 16);

		if (omh < 0 || om < omh || (size_t)om > len - 20 ||
		    nsets < 0 || (size_t)nsets * 12 > (size_t)omh) {
			fprintf(stderr, "%s: bad header\n", name);
			return 1;
		}
		printf("format malloc sets %d\n", (int)nsets);
		for (i = 0; i < nsets; i++) {
			const unsigned char *sh = body + 12 * i;
			int32_t snr = get32(sh), cnt = get32(sh + 4);
			int32_t fm = get32(sh + 8);

			for (k = 0; k < cnt; k++) {
				const unsigned char *mh, *t;
				int32_t mnr, ml, mp;

				if (fm < 0 || (size_t)omh + 12 *
				    ((size_t)fm + (size_t)k + 1) > (size_t)om) {
					fprintf(stderr, "%s: bad set header\n",
					    name);
					free(f);
					return 1;
				}
				mh = body + omh + 12 * (fm + k);
				mnr = get32(mh);
				ml = get32(mh + 4);
				mp = get32(mh + 8);
				if (mp < 0 || (size_t)om + (size_t)mp >
				    len - 20) {
					fprintf(stderr, "%s: bad message "
					    "header\n", name);
					free(f);
					return 1;
				}
				t = body + om + mp;
				if ((size_t)om + (size_t)mp + (size_t)(ml > 0 ?
				    ml : 0) > len - 20)
					ml = (int32_t)(len - 20 - (size_t)om -
					    (size_t)mp);
				printf("%d %d \"", (int)snr, (int)mnr);
				/* catgets returns a C string */
				print_text(t, cstrlen(t, ml));
				printf("\"\n");
			}
		}
		free(f);
		return 0;
	}
	mname = xmalloc(strlen(name) + 3);
	strcpy(mname, name);
	strcat(mname, ".m");
	mf = slurp(mname, &mlen);
	free(mname);
	if (len < 4 || mf == NULL) {
		fprintf(stderr, "%s: not a catalogue or %s.m missing\n",
		    progname, name);
		free(f);
		free(mf);
		return 1;
	}
	printf("format mkmsgs sets %d strings %d\n", (int)get32(f),
	    (int)get32(mf));
	for (i = 1; i <= get32(f) && (size_t)(4 + 8 * i) <= len; i++) {
		int32_t first = get32(f + 4 + 8 * (i - 1));
		int32_t last = get32(f + 8 + 8 * (i - 1));

		for (k = 1; k <= last; k++) {
			const char *t = mk_string(mf, mlen, first + k - 1);

			if (strcmp(t, DFLT_MSG) == 0 ||
			    strcmp(t, NOT_FOUND) == 0)
				continue;
			printf("%d %d \"", (int)i, (int)k);
			print_text((const unsigned char *)t, strlen(t));
			printf("\"\n");
		}
	}
	free(f);
	free(mf);
	return 0;
}

/* ---------------------------------------------------------------- */

static void usage(void)
{
	fprintf(stderr, "Usage: gencat [-lm] catfile [msgfile ...]\n"
	    "       gencat --dump catfile\n");
	exit(1);
}

int main(int argc, char **argv)
{
	const char *catname;
	int i, nfiles;

	if (argc == 3 && strcmp(argv[1], "--dump") == 0)
		return dump_catalogue(argv[2]);
	if (argc < 2)
		usage();
	/* options: only the letter after each '-' counts */
	for (i = 1; i < argc && argv[i][0] == '-'; i++) {
		switch (argv[i][1]) {
		case 'l': list_flag = 1; break;
		case 'm': malloc_format = 1; break;
		default: usage();
		}
	}
	if (i >= argc)
		usage();
	catname = argv[i++];
	nfiles = argc - i;

	cat_build(catname);
	if (nfiles == 0)
		cat_msg_build("stdin", stdin);
	for (; i < argc; i++) {
		FILE *fp = fopen(argv[i], "r");

		if (fp == NULL) {
			perror(argv[i]);
			continue;
		}
		if (nfiles > 1)
			printf("%s:\n", argv[i]);
		cat_msg_build(argv[i], fp);
		fclose(fp);
	}
	fflush(stdout);
	if (no_output) {
		fprintf(stderr, "%s not updated\n", catname);
		return 1;
	}
	if (malloc_format ? dump_malloc(catname) : dump_mkmsgs(catname))
		return 1;
	return 0;
}
