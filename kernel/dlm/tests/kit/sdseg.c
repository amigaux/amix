/*
 * sdseg.c -- the layout of sys/sdseg.h (docs/contracts/C4-7-sd-segments.md
 * section 2, 3) against the stock struct sdcom, through a kit's headers
 * and the kernel's compiler.  Compiled, never linked or run: a wrong
 * offset is a negative array size, so the compile fails naming it.
 * SDCOM_SZ is the line's ABI_SDCOM_SZ from abi.txt (C3-3 section 4).
 *
 * K&R C.
 */

#include "sys/types.h"
#include "sys/errno.h"
#include "amiga/alien/rico.h"
#include "amiga/alien/sd.h"
#include "sys/sdseg.h"

#define	OFF(s, m)	((int)&((struct s *)0)->m)
#define	IS(name, cond)	typedef char name[(cond) ? 1 : -1]

IS(sdcom_size_is_abi, sizeof (struct sdcom) == SDCOM_SZ);
IS(sdcom_size_40, sizeof (struct sdcom) == 40);
IS(sdcom_addr_20, OFF(sdcom, addr) == 20);
IS(sdcom_intr_36, OFF(sdcom, intr) == 36);

IS(sdseg_pa_0, OFF(sdseg, ss_pa) == 0);
IS(sdseg_len_4, OFF(sdseg, ss_len) == 4);
IS(sdseg_size_8, sizeof (struct sdseg) == 8);

IS(sdcomx_com_0, OFF(sdcomx, sx_com) == 0);
IS(sdcomx_flags_after_sdcom, OFF(sdcomx, sx_flags) == sizeof (struct sdcom));
IS(sdcomx_flags_40, OFF(sdcomx, sx_flags) == 40);
IS(sdcomx_nseg_42, OFF(sdcomx, sx_nseg) == 42);
IS(sdcomx_seg_44, OFF(sdcomx, sx_seg) == 44);
IS(sdcomx_resid_48, OFF(sdcomx, sx_resid) == 48);
IS(sdcomx_size_52, sizeof (struct sdcomx) == 52);
IS(sdcomx_card_as_stock, OFF(sdcomx, sx_com.card) == OFF(sdcom, card));

IS(sdlim_ver_0, OFF(sdlim, sl_ver) == 0);
IS(sdlim_flags_2, OFF(sdlim, sl_flags) == 2);
IS(sdlim_maxbytes_4, OFF(sdlim, sl_maxbytes) == 4);
IS(sdlim_maxseg_8, OFF(sdlim, sl_maxseg) == 8);
IS(sdlim_align_10, OFF(sdlim, sl_align) == 10);
IS(sdlim_gran_12, OFF(sdlim, sl_gran) == 12);
IS(sdlim_pad_14, OFF(sdlim, sl_pad) == 14);
IS(sdlim_reach_16, OFF(sdlim, sl_reach) == 16);
IS(sdlim_queue_20, OFF(sdlim, sl_queue) == 20);
IS(sdlim_size_24, sizeof (struct sdlim) == 24);

/* a driver's use (C4-7 section 6): the weak reference and both entries */
static bool	myqueue(), myqueuex();
DDI_SD_LIMITS_DECL;
static struct sdlim	mylim = {
	SDLIM_VER, SDL_SEG, 65536, 16, 4, 4, 0, 0xFFFFFFFF, myqueuex
};

static bool
myqueue(c, cp)
	uint c;
	struct sdcom *cp;
{
	return (c == 0 && cp != 0);
}

static bool
myqueuex(c, cpx)
	uint c;
	struct sdcomx *cpx;
{
	return myqueue(c, &cpx->sx_com);
}

int
sdseg_load(c)
	uint c;
{
	return DDI_SD_LIMITS(myqueue, c, &mylim);
}
