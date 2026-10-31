# pin.sh -- monsw-k30 / monsw-k46: the monitor switch (/dev/monsw, the CIA-B
# lines that flip a monitor between the chipset display and a display card) as
# a kernel module, with its tool, boot step and pages (amix-dlm C3-5 sec 1,
# C3-6 sec 4), by sha256.  Sourced by build.sh.
#
# The objects are built by make dist's modules step (or `make -C
# kernel/modules/monsw/module`) into kernel/modules/monsw/build/<line>/mod.d/
# monsw; monswctl by kmod_prepare below (monsw/tool/Makefile, stripped).
#
# Demand class (majors=c:52), unload=never, param config:int:-1:-1:51, no
# depend=.  /dev/monsw (c 52 0) is a device entry in the module's class, monsw.
# No dependency on amix-base: the boot step logs through its rc.subr when it is
# there, else to the console.
# 1.0.0-5 (2026-10-31): the objects of kernel/modules at kabi 1.2 (the same
# code as 1.0.0-2's kabi 1.0 objects), monswctl, /etc/init.d/monsw, the pages.
# 1.0.0-6 (2026-10-31): monswctl opens /dev/monsw read-only for get and status,
# so any user's `monswctl status` works at the node's 0644; the pages say so.

KM_NAME=monsw
KM_SHORT=monsw
KM_REPO=kernel/modules/monsw
KM_VERSION=1.0.0-6

KM_K30_OBJ=kernel/modules/monsw/build/k30/mod.d/monsw
KM_K30_SHA=1f53a31b0d55778c4ae23536bbb30776d9ec2efabf0a86214b9e9525c69b522d
KM_K46_OBJ=kernel/modules/monsw/build/k46/mod.d/monsw
KM_K46_SHA=962709ca0d0b98cfb541504ef685e9046a55d8671cb90a3cae1a35d1ce2e5c84
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=7a68948b9dd41adb4f4d0aee1f4459aca2d0ef8a

KM_LICENCES="\
kernel/modules/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4"

# the boot step's rc2.d name is a copy, not a link: a kernel-space package is
# pure files
KM_FILES_COMMON="\
/usr/sbin/monswctl kernel/modules/monsw/build/tool/monswctl dd05a6ba5ca62f25f70e7f2679ee73c7c43a7a13fdcc5dca817e28c657f87355 0755
/etc/init.d/monsw kernel/modules/monsw/rc/monsw f050017fa2ef0dafe6c4daedc5837a5b887df8b1b384b48b997bbdf16925bcd7 0744
/etc/rc2.d/S20monsw kernel/modules/monsw/rc/monsw f050017fa2ef0dafe6c4daedc5837a5b887df8b1b384b48b997bbdf16925bcd7 0744
/opt/amix/man/7/monsw kernel/modules/monsw/man/monsw.7 f2b587b8a7dfdc65936ceffed7188f024ac274b42132df9eb3585db71948f3ed 0644
/opt/amix/man/1m/monswctl kernel/modules/monsw/man/monswctl.1m 2e4faec8a5b596cb69121cc38fa0d5742ed8ac43aec7b64664900a707c0aad45 0644"
KM_WHATIS=kernel/modules/monsw/pkg/monsw.whatis
KM_WHATIS_SHA=4d0289ad1e7c4c52c824210a55e6c8fbbaabd3a8f6bf588a6bdd25019f3a9c08

KM_SOURCE_EPOCH=1793404800	# 2026-10-31 00:00 UTC

# monswctl: make dist's modules step builds the objects only
kmod_prepare() {
	( . "$AMIX_CROSS_ENV" >/dev/null 2>&1; make -s -C "$KM_ROOT/kernel/modules/monsw/tool" )
}
