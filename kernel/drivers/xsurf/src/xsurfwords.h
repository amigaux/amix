#ifndef _XSURFWORDS_H
#define _XSURFWORDS_H
/*
 * xsurfwords.h -- the words for a status record's link state and for why a
 * board was refused, shared by the driver's console lines (xs_core.c) and
 * xsf(1M), so that both say the same.  Plain C, no library calls; include
 * xsurfuser.h first.  XS_WORDS_REFUSED also defines xs_words_refused().
 */

static char *
xs_words_cat(char *p, const char *s)
{
    while ((*p = *s++) != 0)
	p++;
    return p;
}

/* the link in words, into buf (64 bytes at least); returns buf */
static char *
xs_words_link(unsigned int link, unsigned int speed, unsigned int duplex,
	      unsigned int medium, char *buf)
{
    char *p = buf;

    *p = 0;
    switch (link) {
    case XSURF_LINK_UP:
	p = xs_words_cat(p, speed == 100 ? "link up 100" : "link up 10");
	p = xs_words_cat(p, duplex == XSURF_DUPLEX_FULL ? " full" :
			 duplex == XSURF_DUPLEX_HALF ? " half" : "");
	break;
    case XSURF_LINK_DOWN:
	p = xs_words_cat(p, medium == XSURF_MEDIUM_COAX ?
			 "no link (10BASE-T link test failed; sending on coax)" :
			 medium == XSURF_MEDIUM_AUI ?
			 "no link (10BASE-T link test failed; sending on AUI)" : "no link");
	break;
    default:
	switch (medium) {
	case XSURF_MEDIUM_NOTREADY:
	    p = xs_words_cat(p, "link state unknown (chip not ready)");
	    break;
	case XSURF_MEDIUM_TP_NOTEST:
	    p = xs_words_cat(p, "link state not available (10BASE-T, link test off)");
	    break;
	case XSURF_MEDIUM_COAX:
	    p = xs_words_cat(p, "link state not available (set to coax, 10BASE2)");
	    break;
	case XSURF_MEDIUM_AUI:
	    p = xs_words_cat(p, "link state not available (set to AUI, 10BASE5)");
	    break;
	default:
	    p = xs_words_cat(p, "link state not available on this card");
	    break;
	}
    }
    return buf;
}

#ifdef XS_WORDS_REFUSED
/* why a board was refused at load, as its console line said it */
static const char *
xs_words_refused(unsigned int why)
{
    switch (why) {
    case XSURF_REFUSED_NONE:	return "in use";
    case XSURF_REFUSED_NOANSWER: return "no answer at its registers (a bus error)";
    case XSURF_REFUSED_NORESET:	return "the chip does not reset";
    case XSURF_REFUSED_NOWRITES: return "its registers do not take writes";
    case XSURF_REFUSED_NOMAC:	return "no usable station address";
    case XSURF_REFUSED_HIGH:	return "placed at or above 0x80000000, the board has shut itself up";
    case XSURF_REFUSED_SMALL:	return "AutoConfig size too small";
    case XSURF_REFUSED_NOMAP:	return "no kernel address space to map it";
    }
    return "refused for a reason this xsf does not know";
}
#endif

#endif /* _XSURFWORDS_H */
