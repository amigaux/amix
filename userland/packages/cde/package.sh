# package.sh -- CDE 2.5.3, the Common Desktop Environment; assignments only.
NAME=cde
PKG=cde
VERSION=2.5.3
PKGREV=1
SOURCE_EPOCH=1795046400   # 2026-11-19 00:00 UTC
SUMMARY="CDE 2.5.3 - the Common Desktop Environment"
DESC="The Common Desktop Environment 2.5.3 (cdesktopenv), built from the upstream source against X11R6.3 and Motif 2.3.8, under /opt/amix/dt with /usr/dt a link to it: the login manager dtlogin, the session manager dtsession, the window manager dtwm with the front panel, dtterm, dtfile, dtpad, dtcalc, dtcm, dtmail, the help viewer, ToolTalk, the action and data-type databases, the message catalogues, the manual pages and the help volumes. Configuration under /etc/dt. dtinfo, dtdocbook, dtksh and dtappbuilder are not built (README.md)."
CATEGORY=x11
SET=extra
LICENSE="LGPL-2.0-or-later AND CC-BY-SA-3.0 AND X11 AND IJG AND Spencer-94 AND MIT"
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
