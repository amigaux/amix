/*
 * X11/Xdmcp.h -- X11R6.3's <X11/Xdmcp.h> with prototypes.  R6.3 declares
 * part of libXdmcp K&R style and the Alloc and Realloc calls not at all;
 * the prototypes follow R6.3's own definitions (lib/Xdmcp), with each
 * CARD8 or CARD16 argument as the unsigned it is promoted to.
 * MIT licence, see LICENSE in userland/packages.
 */
#ifndef AMIX_COMPAT_X11_XDMCP_H
#define AMIX_COMPAT_X11_XDMCP_H
#define XdmcpWriteCARD8 amix_kr_XdmcpWriteCARD8
#define XdmcpWriteCARD16 amix_kr_XdmcpWriteCARD16
#define XdmcpWriteCARD32 amix_kr_XdmcpWriteCARD32
#define XdmcpWriteARRAY8 amix_kr_XdmcpWriteARRAY8
#define XdmcpWriteARRAY16 amix_kr_XdmcpWriteARRAY16
#define XdmcpWriteARRAY32 amix_kr_XdmcpWriteARRAY32
#define XdmcpWriteARRAYofARRAY8 amix_kr_XdmcpWriteARRAYofARRAY8
#define XdmcpWriteHeader amix_kr_XdmcpWriteHeader
#define XdmcpFlush amix_kr_XdmcpFlush
#define XdmcpReadCARD8 amix_kr_XdmcpReadCARD8
#define XdmcpReadCARD16 amix_kr_XdmcpReadCARD16
#define XdmcpReadCARD32 amix_kr_XdmcpReadCARD32
#define XdmcpReadARRAY8 amix_kr_XdmcpReadARRAY8
#define XdmcpReadARRAY16 amix_kr_XdmcpReadARRAY16
#define XdmcpReadARRAY32 amix_kr_XdmcpReadARRAY32
#define XdmcpReadARRAYofARRAY8 amix_kr_XdmcpReadARRAYofARRAY8
#define XdmcpReadHeader amix_kr_XdmcpReadHeader
#define XdmcpFill amix_kr_XdmcpFill
#define XdmcpReadRemaining amix_kr_XdmcpReadRemaining
#define XdmcpDisposeARRAY8 amix_kr_XdmcpDisposeARRAY8
#define XdmcpDisposeARRAY16 amix_kr_XdmcpDisposeARRAY16
#define XdmcpDisposeARRAY32 amix_kr_XdmcpDisposeARRAY32
#define XdmcpDisposeARRAYofARRAY8 amix_kr_XdmcpDisposeARRAYofARRAY8
#define XdmcpCopyARRAY8 amix_kr_XdmcpCopyARRAY8
#define XdmcpARRAY8Equal amix_kr_XdmcpARRAY8Equal
#define XdmcpGenerateKey amix_kr_XdmcpGenerateKey
#define XdmcpIncrementKey amix_kr_XdmcpIncrementKey
#define XdmcpDecrementKey amix_kr_XdmcpDecrementKey
#define XdmcpWrap amix_kr_XdmcpWrap
#define XdmcpUnwrap amix_kr_XdmcpUnwrap
#include_next <X11/Xdmcp.h>
#undef XdmcpWriteCARD8
#undef XdmcpWriteCARD16
#undef XdmcpWriteCARD32
#undef XdmcpWriteARRAY8
#undef XdmcpWriteARRAY16
#undef XdmcpWriteARRAY32
#undef XdmcpWriteARRAYofARRAY8
#undef XdmcpWriteHeader
#undef XdmcpFlush
#undef XdmcpReadCARD8
#undef XdmcpReadCARD16
#undef XdmcpReadCARD32
#undef XdmcpReadARRAY8
#undef XdmcpReadARRAY16
#undef XdmcpReadARRAY32
#undef XdmcpReadARRAYofARRAY8
#undef XdmcpReadHeader
#undef XdmcpFill
#undef XdmcpReadRemaining
#undef XdmcpDisposeARRAY8
#undef XdmcpDisposeARRAY16
#undef XdmcpDisposeARRAY32
#undef XdmcpDisposeARRAYofARRAY8
#undef XdmcpCopyARRAY8
#undef XdmcpARRAY8Equal
#undef XdmcpGenerateKey
#undef XdmcpIncrementKey
#undef XdmcpDecrementKey
#undef XdmcpWrap
#undef XdmcpUnwrap
#ifdef __cplusplus
extern "C" {
#endif
extern int XdmcpWriteCARD8(XdmcpBufferPtr, unsigned);
extern int XdmcpWriteCARD16(XdmcpBufferPtr, unsigned);
extern int XdmcpWriteCARD32(XdmcpBufferPtr, CARD32);
extern int XdmcpWriteARRAY8(XdmcpBufferPtr, ARRAY8Ptr);
extern int XdmcpWriteARRAY16(XdmcpBufferPtr, ARRAY16Ptr);
extern int XdmcpWriteARRAY32(XdmcpBufferPtr, ARRAY32Ptr);
extern int XdmcpWriteARRAYofARRAY8(XdmcpBufferPtr, ARRAYofARRAY8Ptr);
extern int XdmcpWriteHeader(XdmcpBufferPtr, XdmcpHeaderPtr);
extern int XdmcpFlush(int, XdmcpBufferPtr, XdmcpNetaddr, int);
extern int XdmcpReadCARD8(XdmcpBufferPtr, CARD8Ptr);
extern int XdmcpReadCARD16(XdmcpBufferPtr, CARD16Ptr);
extern int XdmcpReadCARD32(XdmcpBufferPtr, CARD32Ptr);
extern int XdmcpReadARRAY8(XdmcpBufferPtr, ARRAY8Ptr);
extern int XdmcpReadARRAY16(XdmcpBufferPtr, ARRAY16Ptr);
extern int XdmcpReadARRAY32(XdmcpBufferPtr, ARRAY32Ptr);
extern int XdmcpReadARRAYofARRAY8(XdmcpBufferPtr, ARRAYofARRAY8Ptr);
extern int XdmcpReadHeader(XdmcpBufferPtr, XdmcpHeaderPtr);
extern int XdmcpFill(int, XdmcpBufferPtr, XdmcpNetaddr, int *);
extern int XdmcpReadRemaining(XdmcpBufferPtr);
extern void XdmcpDisposeARRAY8(ARRAY8Ptr);
extern void XdmcpDisposeARRAY16(ARRAY16Ptr);
extern void XdmcpDisposeARRAY32(ARRAY32Ptr);
extern void XdmcpDisposeARRAYofARRAY8(ARRAYofARRAY8Ptr);
extern int XdmcpAllocARRAY8(ARRAY8Ptr, int);
extern int XdmcpAllocARRAY16(ARRAY16Ptr, int);
extern int XdmcpAllocARRAY32(ARRAY32Ptr, int);
extern int XdmcpAllocARRAYofARRAY8(ARRAYofARRAY8Ptr, int);
extern int XdmcpReallocARRAY8(ARRAY8Ptr, int);
extern int XdmcpReallocARRAY16(ARRAY16Ptr, int);
extern int XdmcpReallocARRAY32(ARRAY32Ptr, int);
extern int XdmcpReallocARRAYofARRAY8(ARRAYofARRAY8Ptr, int);
extern int XdmcpCopyARRAY8(ARRAY8Ptr, ARRAY8Ptr);
extern int XdmcpARRAY8Equal(ARRAY8Ptr, ARRAY8Ptr);
extern void XdmcpGenerateKey(XdmAuthKeyPtr);
extern void XdmcpIncrementKey(XdmAuthKeyPtr);
extern void XdmcpDecrementKey(XdmAuthKeyPtr);
extern void XdmcpWrap(unsigned char *, unsigned char *, unsigned char *, int);
extern void XdmcpUnwrap(unsigned char *, unsigned char *, unsigned char *, int);
#ifdef __cplusplus
}
#endif
#endif
