/*
 * wchar.h for Amix: SVR4.0 has none.  libcommon's iblok.h wants wchar_t
 * (<stdlib.h> has it) and wint_t; tar reads no wide characters.
 */
#ifndef AMIX_WCHAR_H
#define AMIX_WCHAR_H
#include <stdlib.h>
typedef long wint_t;
#endif
