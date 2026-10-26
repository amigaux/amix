#ifndef _HOSTTEST_SYS_INLINE_H
#define _HOSTTEST_SYS_INLINE_H
/* The k46 arm's bprobe window: _spl7()/splx() as mock functions (no SR here). */
extern int _spl7();
extern int splx();
#endif
