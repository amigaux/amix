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
# 1.0.0-7 (2026-10-31): the driver gives EBADF for RTG, NATIVE and SETCFG on a
# descriptor opened only for reading; objects bb900ef8 / 287ee3ad.
# 1.0.0-8 (2026-10-31): rc/monsw's header comment; objects and monswctl unchanged.
# 1.0.0-9 (2026-11-01): rebuilt on kit 3b53a8a (gcc-cross-amix 33ebadc); the
# code is unchanged, only .moddata cc= differs (gcc-2.7.2.3-33ebadc).  monswctl
# links values-Xa.o as the native cc does (_lib_version 1), 7228 bytes.

KM_NAME=monsw
KM_SHORT=monsw
KM_REPO=kernel/modules/monsw
KM_VERSION=1.0.0-9

KM_K30_OBJ=kernel/modules/monsw/build/k30/mod.d/monsw
KM_K30_SHA=4bc8f57089b80baec94fa64e0a65dfd6a3b27a2ab4a66c63db345e9e35233a20
KM_K46_OBJ=kernel/modules/monsw/build/k46/mod.d/monsw
KM_K46_SHA=f9f6ed6b6a31a20d689f5cb8a30d53bf5804eae8b639ccf316b5feb1628f7623
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=3b53a8aad7c2bca344bfff064ef0b573b06a520f	# PIN gcc-2.7.2.3-33ebadc

KM_LICENCES="\
kernel/modules/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4"

# the boot step's rc2.d name is a copy, not a link: a kernel-space package is
# pure files
KM_FILES_COMMON="\
/usr/sbin/monswctl kernel/modules/monsw/build/tool/monswctl b9e2aa21c0ccda1a975e7dfc871997c127a67ab1c7f08da626cb521a7e295ca6 0755
/etc/init.d/monsw kernel/modules/monsw/rc/monsw 8744a32609ab00f94dcb00ade98db4f06c8596088293ae560b687a8474102652 0744
/etc/rc2.d/S20monsw kernel/modules/monsw/rc/monsw 8744a32609ab00f94dcb00ade98db4f06c8596088293ae560b687a8474102652 0744
/opt/amix/man/7/monsw kernel/modules/monsw/man/monsw.7 1d18b042ef37647135cbb3cdff07caf3c3097c7a2faea63e37aae9a1e6d9a570 0644
/opt/amix/man/1m/monswctl kernel/modules/monsw/man/monswctl.1m 2e4faec8a5b596cb69121cc38fa0d5742ed8ac43aec7b64664900a707c0aad45 0644"
KM_WHATIS=kernel/modules/monsw/pkg/monsw.whatis
KM_WHATIS_SHA=4d0289ad1e7c4c52c824210a55e6c8fbbaabd3a8f6bf588a6bdd25019f3a9c08

KM_SOURCE_EPOCH=1793404800	# 2026-10-31 00:00 UTC

# monswctl: make dist's modules step builds the objects only
kmod_prepare() {
	( . "$AMIX_CROSS_ENV" >/dev/null 2>&1; make -s -C "$KM_ROOT/kernel/modules/monsw/tool" )
}
