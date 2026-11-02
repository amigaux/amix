/* alloca.h for Amix: SVR4.0 has none; GCC's built-in does the work. */
#ifndef alloca
#define alloca(n) __builtin_alloca(n)
#endif
