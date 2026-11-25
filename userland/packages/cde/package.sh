# package.sh -- CDE 2.5.3, the Common Desktop Environment; assignments only.
NAME=cde
PKG=cde
VERSION=2.5.3
PKGREV=4   # -4: dtksh, the desktop Korn shell (its ksh93 cross-built from feature-probe answers recorded on Amix), so dterror, dtlp and dthelpgen run; -3: dtterm's pty gets its terminal modules (ptem, ldterm); gcc14-cross-amix 276ef49; the shared variant 2.5.3-3.s; -2: App Builder (dtbuilder, dtcodegen) and ttsnoop; manual pages for every program; dtdbcache started with no arguments; reproducible dates; ttsnoop shows its messages (libtt without %C, the SVR4 tail)
SOURCE_EPOCH=1795392000   # 2026-11-23 00:00 UTC
SUMMARY="CDE 2.5.3 - the Common Desktop Environment"
# the shared variant (VARIANT=shared, prototype.shared), the default: CDE's
# libraries shared, against the shared variants of X11R6.3 and Motif; the
# static one (VARIANT=static, prototype) stays buildable, its bytes unchanged
SHARED_PKGREV=4.s
SHARED_SUMMARY="CDE 2.5.3 with shared libraries - the Common Desktop Environment"
SHARED_DESC="The Common Desktop Environment 2.5.3 (cdesktopenv), built from the upstream source against X11R6.3 and Motif 2.3.8, with CDE's libraries shared (libDtSvc, libDtWidget, libDtHelp, libDtPrint, libDtTerm, libDtMrm, libDtSearch, libDtXinerama, libcsa, libtt) and the programs linked against them and the shared X11R6.3, Motif, libjpeg and regex, under /opt/amix/dt with /usr/dt a link to it: the login manager dtlogin, the session manager dtsession, the window manager dtwm with the front panel, dtterm, dtfile, dtpad, dtcalc, dtcm, dtmail, the help viewer, the desktop Korn shell dtksh, the App Builder dtbuilder with its code generator dtcodegen, ToolTalk with the message viewer ttsnoop, the action and data-type databases, the message catalogues, the manual pages and the help volumes. Configuration under /etc/dt. dtinfo and dtdocbook are not built (README.md)."
DESC="The Common Desktop Environment 2.5.3 (cdesktopenv), built from the upstream source against X11R6.3 and Motif 2.3.8, under /opt/amix/dt with /usr/dt a link to it: the login manager dtlogin, the session manager dtsession, the window manager dtwm with the front panel, dtterm, dtfile, dtpad, dtcalc, dtcm, dtmail, the help viewer, the desktop Korn shell dtksh, the App Builder dtbuilder with its code generator dtcodegen, ToolTalk with the message viewer ttsnoop, the action and data-type databases, the message catalogues, the manual pages and the help volumes. Configuration under /etc/dt. dtinfo and dtdocbook are not built (README.md)."
CATEGORY=x11
SET=extra
LICENSE="LGPL-2.0-or-later AND CC-BY-SA-3.0 AND X11 AND IJG AND Spencer-94 AND MIT AND EPL-2.0"
URL=https://downloads.sourceforge.net/project/cdesktopenv/src/cde-2.5.3.tar.gz
SHA256=2b58c08ebf0a6bb9d4a32191cd25e204f5d8cba81bccaa36fc72f5c4aa979854
STYLE=hooks
TOOLCHAIN=gcc14
PREFIX=/opt/amix/dt
# /usr/dt, where CDE compiles in its files: a link to PREFIX; and dtterm's
# terminfo entry, where curses programs on the box look for it
SYSTEM_PATHS="/usr/dt /usr/share/lib/terminfo/d/dtterm"
DEPENDS="amix-base x11r6.3"
BUILD_DEPENDS="x11r6.3 motif libjpeg regex"
# the shared variant: the C++ runtime for libtt (cxxrt), and amixrt 1.0-5,
# the first with the functions libtt, libDtTerm, libcsa, libDtSvc and
# libDtMrm take from it (syslog, getutxline, sysinfo and seven more); the shared
# X11R6.3 and Motif and libregex.so.1, so a static one already installed is lifted
SHARED_DEPENDS="amix-base x11r6.3>=6.3-15.s motif>=2.3.8-3.s libjpeg regex>=3.8-2 amixrt>=1.0-5 cxxrt"
SHARED_BUILD_DEPENDS="x11r6.3 motif libjpeg regex"
