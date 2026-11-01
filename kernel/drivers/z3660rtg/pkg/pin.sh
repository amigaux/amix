# pin.sh -- z3660rtg-k30 / z3660rtg-k46: the Z3660 RTG framebuffer driver as
# a DEMAND-class kernel module (amix-dlm C3-5 sec 1), by sha256, with what X
# on a Z3660 needs from the driver package.  Sourced by kdrv.sh.
#
# The objects are make dist's drivers step's: the fork at
# kernel/drivers/z3660rtg/z3660rtg.pin built with this checkout's kit into
# out/modules/<line>/z3660rtg, linked against the real monsw of each line.
# The licence, notice and module/VERSION are the fork's, in
# out/cache/forks/z3660rtg/.
#
# Demand class (majors=c:49), depend=monsw: kbootset composes it only beside
# the monsw module package of its line (gate 3).  Nodes /dev/zz9000 (c 49 0,
# 0660 root sys: the server and the monitor-switch tool run as root) and
# /dev/zz9000i (c 49 128, 0444: the board's sensors).  Parameters blit,
# fixed, kvfb and maxarea; the package sets none (modreg: comments only).
# Beside the module: /etc/display.d/z3660 (display.d(4)'s worked example),
# zz9k_monsw, rtg-kbdback, ztop with its manual page and whatis line, and
# the 1.1 launcher startx-rtg, which kdrv_prepare builds (tools.sh, GCC 14).
# xztop, which links X11R6.3, is the xztop userland package.
# 1.1.1-3 (2026-11-01): the module 1.1.1-1 (fork a9d39a1: startx-rtg runs
# the server at /opt/amix/X11R6/bin/Xzz9000), built with the
# gcc-2.7.2.3-33ebadc kit, first rolled from amix; xztop moved out.

KM_NAME=z3660rtg
KM_SHORT=zrtg
KM_REPO=kernel/drivers/z3660rtg
KM_VERSION=1.1.1-1
KM_PKG_VERSION=1.1.1-3
KM_VERSION_FILE=out/cache/forks/z3660rtg/module/VERSION

KM_K30_SHA=ab7af11c013c2df07619f0f2991f7236aa358c76819f7fce210cdbd7ad778d71
KM_K46_SHA=813898d9b37885c46777962838276a1e199526ed809ea53338f57e65f5bf2be8
# modcheck resolves depend=monsw against the monsw make dist builds
KM_K30_DEPS="out/modules/k30/monsw 4bc8f57089b80baec94fa64e0a65dfd6a3b27a2ab4a66c63db345e9e35233a20"
KM_K46_DEPS="out/modules/k46/monsw f9f6ed6b6a31a20d689f5cb8a30d53bf5804eae8b639ccf316b5feb1628f7623"

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
out/cache/forks/z3660rtg/LICENSE cf0e3ecd08ada3e67f95383c50ae8424547b6d56beed809f0ef7fc2fb10d0e6a
out/cache/forks/z3660rtg/NOTICE 4583f4897add7f88779ea561d8d13a8262b366024af14d56cf153e62d925cb0f"
KM_EXTRA_NOTE="Linked into the module: the stock Amix console font object
(usr/sys/amiga/console/sunfont.o, Commodore), under the 2026-09-23
distribution approval above.  The programs link only the box's libc
(rtg-kbdback also libscreen.so)."

# tools.sh's inputs: the stock libscreen rtg-kbdback links and its header
ZR_LIBSCREEN_SHA=47a02053802884a993e459d2a21b3ce19dc0ae21e9ec6f4e3cff053a52f194d2
ZR_SCREEN_H_SHA=6e6ac7cdbeb4dd53ec5a5d84cf9b7a1b6633a9aefc525694b4a1cac26d71415c

# what tools.sh writes, verified and shipped verbatim (@PKG@: zrtg30, zrtg46)
_zr=out/build/z3660rtg-tools/out
KM_FILES_COMMON="\
/opt/amix/bin/zz9k_monsw $_zr/bin/zz9k_monsw a6fab7e35cf058f8b651d3c7351701e942d6ddfaed7d03630c49b45391f0dee1 0755
/opt/amix/bin/rtg-kbdback $_zr/bin/rtg-kbdback e56a8bb7a7f8aaddb7b374111d1d01e3850095b820387038cb9bdf7451e560fb 0755
/opt/amix/bin/ztop $_zr/bin/ztop 99b99291f767f579bbfc74d828bb573afaa8d602d8ec8622e477776fa5e527e6 0755
/opt/amix/bin/startx-rtg $_zr/bin/startx-rtg 4c0173a3c001f68a9bbdaa122171e672da725a3fd4b99e3323918ee4aadf61a4 0755
/opt/amix/man/1/ztop $_zr/man/1/ztop a7bbd8208aa29ad79a74044fc1e9077567d8f89a80de23ebdf2b4aa2c5197876 0644
/opt/amix/man/whatis.d/@PKG@ $_zr/man/whatis c934a66f897f282fbab6a726d051a008528fc4b8936dcdb31efb99637d0cbf65 0644
/etc/display.d/z3660 $_zr/display.d/z3660 421064a1dec95831a55940d9624ee816b5d3e692dfa6580dd2fbc8ac50fd529a 0444"

# the tools, in GCC 14's environment rather than the roll's (TOOLCHAIN=none)
kdrv_prepare() {
	env -i HOME="${HOME:-/tmp}" PATH="$PATH" G14="${G14:-}" GCA="${GCA:-}" \
		AMIX_SYSTEM="$AMIX_SYSTEM" AMIX_BUILD_ROOT="$AMIX_BUILD_ROOT" \
		sh "$AMIX_REPO_ROOT/kernel/drivers/z3660rtg/pkg/tools.sh"
}

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
