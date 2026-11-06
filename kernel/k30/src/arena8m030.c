/*
 * arena8m030.c -- kseg's table for the 8 MiB kvseg (tools/arena8m030.py).
 *
 * kseg records each run's length in a table of bytes indexed by (va - syssegs) >> 17, one entry per 128 KiB of kvseg.
 * Stock's table has 32 entries, for 4 MiB, and is local to os/exp.  The tool retargets kseg's and unkseg's relocations
 * from it to this one; nothing else names either table.
 */
char ksegtbl64[64];
