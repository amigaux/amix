/*
 * b2.h -- boot2's internal interfaces: the AmigaOS calls it makes, the
 * console, and the routines in amiga.s.
 *
 * Copyright (c) 2026 Jussi Alanärä.  MIT licence, see LICENSE.
 */
#ifndef B2_H
#define B2_H

#include "axtypes.h"
#include "store.h"

#define LOADER_VERSION	AX_LOADER_VERSION

/* exec memory flags */
#define MEMF_PUBLIC	1UL
#define MEMF_CHIP	2UL
#define MEMF_FAST	4UL
#define MEMF_CLEAR	0x10000UL

/* struct offsets used (AmigaOS NDK, public structures) */
#define EXEC_VERSION	20	/* lib_Version (UWORD) */
#define EXEC_ATTNFLAGS	0x128	/* AttnFlags (UWORD) */
#define EXEC_MEMLIST	322	/* MemList.lh_Head */
#define IO_DEVICE	20
#define IO_UNIT		24
#define IO_COMMAND	28
#define IO_ERROR	31
#define IO_ACTUAL	32
#define IO_LENGTH	36
#define IO_DATA		40
#define IO_OFFSET	44
#define IOSTD_SIZE	48
#define LN_NAME		10
#define CMD_READ	2
#define CMD_WRITE	3
#define CMD_CLEAR	5	/* drop the device's track buffer */
#define TD_MOTOR	9
#define TD_CHANGENUM	13	/* io_Actual = the disk-change counter */

struct ax_regs { ax_u32 d0, d1, d2, d3, d4, d5, a0, a1, a2; };
#define REGS0(r) x_memset(&(r), 0, sizeof(r))

/* amiga.s */
long ax_call(void *base, long lvo, struct ax_regs *r);
long ax_super(void (*func)(void), void *arg);
void ax_probe(void);
void ax_handoff(void);
void ax_handoff_end(void);

/* sys.c: exec and expansion.library */
extern void *ax_execbase;
void *x_allocmem(ax_u32 size, ax_u32 flags);
void x_freemem(void *p, ax_u32 size);
void *x_allocabs(ax_u32 size, void *location);
int x_doio(void *iob);
void *x_openlib(const char *name, ax_u32 version);
void x_closelib(void *lib);
void x_forbid(void);
void x_permit(void);
ax_u32 x_typeofmem(const void *p);
int x_opendevice(const char *name, ax_u32 unit, void *ioreq, ax_u32 flags);
void x_closedevice(void *ioreq);
void *x_findconfigdev(void *expbase, void *old, long manuf, long prod);
ax_u16 x_execversion(void);
void x_memcpy(void *d, const void *s, ax_u32 n);
void x_memset(void *d, int c, ax_u32 n);

/* con.c: one line per step, to the serial port (and the screen when open) */
void con_init(ax_u32 baud);
void con_screen(void);
void con_puts(const char *s);
void con_printf(const char *fmt, ...);
void con_say(const char *fmt, ...);

#endif
