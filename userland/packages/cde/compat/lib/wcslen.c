/*
 * wcslen.c -- wcslen(3) for CDE, which Amix's C library lacks; a member of its
 * own in libamixcompat-cde.a, so a program that links another one first
 * (dtksh: libast's) takes that one alone.
 * MIT licence, see LICENSE in userland/packages.
 */
#include <wchar.h>

size_t
wcslen(const wchar_t *s)
{
	const wchar_t *p = s;

	while (*p)
		p++;
	return (size_t)(p - s);
}
