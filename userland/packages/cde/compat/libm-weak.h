/*
 * libm-weak.h -- force-included into libDtHelp and libDtSearch in the shared
 * variant: their calls into Amix's libm become weak references.  Amix's libm
 * is static only and not position-independent, so a shared library cannot
 * link it without text relocations.  The program supplies these functions
 * instead: the shared variant links each program with them from the stock
 * libm and exports them (-Wl,-u and --export-dynamic-symbol, build.sh), and
 * the runtime linker binds the libraries' references to the program's copies.
 * A program that does not export them leaves the references 0: build.sh
 * refuses any program that NEEDs these libraries and does not (README, The
 * shared variant).
 * MIT licence, see LICENSE in userland/packages.
 */
#pragma weak sin
#pragma weak cos
#pragma weak tan
#pragma weak log
#pragma weak log10
#pragma weak sqrt
