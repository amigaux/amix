# package.sh -- Motif 2.3.8; assignments only.
NAME=motif
PKG=motif
VERSION=2.3.8
PKGREV=3   # -3: gcc14-cross-amix 276ef49 (every program exports environ, so the bytes move; the code is 2.3.8-2's), and the shared variant 2.3.8-3.s; -2: gcc14-cross-amix 9d13dcd (release-1.1): fold-mem-offsets off
SOURCE_EPOCH=1795046400   # 2026-11-19 00:00 UTC
SUMMARY="Motif 2.3.8 - the Motif toolkit (Xm, Mrm, Uil), mwm, uil and xmbind"
# the shared variant (VARIANT=shared, prototype.shared), the default: against
# X11R6.3's shared variant; the static one (VARIANT=static, prototype) stays
# buildable, its bytes unchanged
SHARED_PKGREV=3.s
SHARED_SUMMARY="Motif 2.3.8 with shared libraries - the Motif toolkit (Xm, Mrm, Uil), mwm, uil and xmbind"
SHARED_DESC="Motif 2.3.8, the Open Group's LGPL release, built from the upstream source against X11R6.3 under /opt/amix/X11R6: the libXm, libMrm and libUil libraries, shared (with the static archives), with their headers, the mwm window manager, the uil compiler, xmbind, the bindings and the manual pages. Xft, Xprint, PNG and JPEG are off (X11R6.3 has none of them); Motif's own XPM reader is in libXm."
DESC="Motif 2.3.8, the Open Group's LGPL release, built from the upstream source against X11R6.3 under /opt/amix/X11R6: the libXm, libMrm and libUil libraries with their headers, the mwm window manager, the uil compiler, xmbind, the bindings and the manual pages. Xft, Xprint, PNG and JPEG are off (X11R6.3 has none of them); Motif's own XPM reader is in libXm."
CATEGORY=x11
SET=extra
LICENSE="LGPL-2.0-or-later AND X11"
URL=https://downloads.sourceforge.net/project/motif/Motif%202.3.8%20Source%20Code/motif-2.3.8.tar.gz
SHA256=859b723666eeac7df018209d66045c9853b50b4218cecadb794e2359619ebce7
# the configuration an admin edits: an upgrade keeps an edited one and puts
# the new default beside it as .new
CONFFILES="/opt/amix/X11R6/lib/X11/system.mwmrc /opt/amix/X11R6/lib/X11/bindings/xmbind.alias"
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix/X11R6
DEPENDS="x11r6.3"
BUILD_DEPENDS="x11r6.3"
# libregex.so.1 for POSIX regcomp (Amix libc has none; libgen's regcmp is static-only)
# amixrt 1.0-5: libXm's select comes from it, and 1.0-2..1.0-4 set a wrong
# errno on a failing call, so an interrupted select was not EINTR; the shared
# X11R6.3 and libregex.so.1 (regex 3.8-1 was static only): a static x11r6.3 or
# regex already installed is lifted, not kept
SHARED_DEPENDS="x11r6.3>=6.3-15.s regex>=3.8-2 amixrt>=1.0-5"
SHARED_BUILD_DEPENDS="x11r6.3 regex"
