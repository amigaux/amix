/*
 * X11/VendorP.h -- X11R6.3's <X11/VendorP.h> with C linkage in C++, as
 * later X releases declare it; Motif's <Xm/VendorSP.h> declares
 * vendorShellClassRec inside extern "C", and C++ refuses the two linkages.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_X11_VENDORP_H
#define AMIX_COMPAT_X11_VENDORP_H
#ifdef __cplusplus
extern "C" {
#endif
#include_next <X11/VendorP.h>
#ifdef __cplusplus
}
#endif
#endif
