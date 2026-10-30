#include <sys/types.h>
#include <sys/inline.h>
int  guard_hdr(void){ int s = spl6(); /* critical section */ splx(s); return 0; }
void leave_hdr(int s){ splx(s); }
void leave_gnu(int s){ __asm__ __volatile__("movew %0,%%sr" : : "d"(s)); }
