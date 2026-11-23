/*
 * fixdfdi.c -- __fixdfdi, double to long long, for the shared variant's
 * libraries.  GCC 14's libgcc.a is not position-independent: its __fixdfdi
 * reaches __fixunsdfdi by an absolute jsr, a text relocation in every shared
 * library that converts a double to a long long (libDtSvc, libDtMrm).  This
 * one is the same function, built position-independent with the rest of
 * compat, and links ahead of libgcc.a; __fixunsdfdi is still libgcc's.  It
 * goes away when the toolchain's libgcc is built position-independent.  The
 * static build links libgcc's.
 * MIT licence, see LICENSE in userland/packages.
 */
unsigned long long __fixunsdfdi(double);
long long __fixdfdi(double);

long long __fixdfdi(double a)
{
	/* no double-to-long-long conversion here: that would call this */
	if (a < 0)
		return -(long long)__fixunsdfdi(-a);
	return (long long)__fixunsdfdi(a);
}
