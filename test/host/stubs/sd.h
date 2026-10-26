#ifndef _HOSTTEST_SD_H
#define _HOSTTEST_SD_H
/* struct sdcom with the field names, types and order of the kit's
 * stock/usr/sys/amiga/alien/sd.h; rico.h first (uchar, bool, uint). */
#define SDCARDS 2
#define SDUNITS 8

struct sdcom {
	volatile struct sdcom	*next;
	bool		reading,
			okay;
	uchar		status,
			cdb[12];
	caddr_t		addr;
	uint		nbyte,
			card,
			unit;
	void		(*intr)( );
};
#endif
