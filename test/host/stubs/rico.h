#ifndef _HOSTTEST_RICO_H
#define _HOSTTEST_RICO_H
/* The alien short names a4091-wr.c and sd.h use: the real amiga/alien/rico.h's
 * definitions, trimmed to what the driver and struct sdcom need. */
#define uchar   unsigned char
#define ushort  unsigned short
#define uint    unsigned
#define ulong   unsigned long

#define bool    char
#define TRUE    (0 == 0)
#define FALSE   (!TRUE)
#endif
