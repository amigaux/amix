# pin.sh -- xsurf-k30 (xsurf30) / xsurf-k46 (xsurf46): the X-Surf and
# X-Surf-100 ethernet driver as a kernel module (amix-dlm C3-5 sec 1), by
# sha256.  Sourced by build.sh through build/pkg/common/kdrv.sh.
#
# The objects are make dist's drivers step's, out/modules/<line>/xsurf,
# built in the build container from kernel/drivers/xsurf/module.  Boot class
# (match=zorro:1212:64,zorro:1212:17, majors=c:56), no depend=.  The package
# ships the driver's link.d entry for ifup, the nodes /dev/xsf0, /dev/xsf1
# and /dev/xsfctl (c 56 0, 1 and 15, mode 0600) in the module's class,
# xsurf, the status program /usr/sbin/xsf, which kdrv_prepare builds
# (tools.sh, GCC 14), and the pages xsurf(7) and xsf(1M) with their whatis
# lines.
#
# 1.0.0-1 (2026-11-14): the first package.  Module 1.0.0-1, kabi k30.1.2 /
# k46.1.2, built in amix-toolchain:dist against the kit of amix 1a3e7797
# (gcc-cross-amix 33ebadc).  Needs a kbootset whose registry has c 56 xsurf
# (1.1.0.261114-45 or later); no kbootset= key, no depend.
# 1.0.0-2 (2026-11-14): module 1.0.0-2, the status record's ack_retries
# counted and the console line's station address printed with leading zeros;
# tested in emulation on both lines (README, Tested).  Built in
# amix-toolchain:dist against the kit of amix 1a3e7797.
# 1.0.0-3 (2026-11-14): module 1.0.0-3, SIOCGIFFLAGS and SIOCSIFFLAGS
# acknowledged with IP's ifreq, so ifconfig shows xsf0's flags (was flags=0);
# tested in emulation on both lines (README, Tested).  Built in
# amix-toolchain:dist against the kit of amix 1a3e7797.
# 1.0.0-4 (2026-11-15): module 1.0.0-4: the link state (the X-Surf-100's
# DSR, the X-Surf's medium registers) in the load line, the status record
# (version 2) and a console line on each change; each kind of transmit
# failure said once; collisions in netstat; a board whose registers do not
# take writes refused at load and reported through the new /dev/xsfctl; no
# write to the AX88796B's register 0x17; after a reset the X-Surf-100 waits
# for D_RDY; register cycles byte, else word (parameter regs); a remote-DMA
# self-test at load, the windows, else the data port (parameter data).
# New: /usr/sbin/xsf, xsurf(7), xsf(1M).  Built in amix-toolchain:dist
# against the kit of amix 1a3e7797.

KM_NAME=xsurf
KM_SHORT=xsurf
KM_REPO=kernel/drivers/xsurf
KM_VERSION=1.0.0-4

KM_K30_SHA=e8e7cd7a84993a286685065ffbf4bf6f8081e66996158a08fa60fa10c0b5eb1a
KM_K46_SHA=b4e8316b9b2727af5cb670ef9eb04520126c02cd66aaa157fe903e3785b365df
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=1a3e77979df2f22d613d715742e975e98fb2d5de

KM_LICENCES="\
kernel/drivers/xsurf/LICENSE fbc902eab45736ecf5baf223cbc0db0b03e9a7f3232caa5fdf8ddce4bb27a735
kernel/drivers/xsurf/NOTICE 61cdaa4de14fcb16e351c24244c7637c5b78d45da69a71975aec086f5a3de218"

# the driver's link.d entry, vendor data for ifup, shipped verbatim; xsf
# as tools.sh builds it; the pages and their whatis fragment (@PKG@:
# xsurf30 or xsurf46)
_xs=out/build/xsurf-tools/out
KM_FILES_COMMON="\
/etc/inet/link.d/xsurf kernel/drivers/xsurf/link.d/xsurf b4b62296d468f10c4c847d41f6d54a92791d98be710600a91ad84578a1a3e0d3 0444
/usr/sbin/xsf $_xs/bin/xsf 38a3bd9938fe803667e9fc0c4eee8f08b5fa6a68bc659851449cbb5f9c8e8ca8 0755
/opt/amix/man/7/xsurf kernel/drivers/xsurf/man/xsurf.7 b8bb8d804450777b28ded0141ac191b1962864c10a6315d5c7d952c9a53de646 0644
/opt/amix/man/whatis.d/@PKG@ kernel/drivers/xsurf/pkg/xsurf.whatis cba113c6abf27b42e240d6c16158e79056255812bc7ea64183d5e55c070efffd 0644
/opt/amix/man/1m/xsf kernel/drivers/xsurf/man/xsf.1m 3143e44f07929eca6715239bb5922c07a2145c437989736c0a66b0727f394bb3 0644"

# xsf, in GCC 14's environment rather than the roll's (TOOLCHAIN=none)
kdrv_prepare() {
	env -i HOME="${HOME:-/tmp}" PATH="$PATH" G14="${G14:-}" GCA="${GCA:-}" \
		AMIX_SYSTEM="$AMIX_SYSTEM" AMIX_BUILD_ROOT="$AMIX_BUILD_ROOT" \
		sh "$AMIX_REPO_ROOT/kernel/drivers/xsurf/pkg/tools.sh"
}

KM_SOURCE_EPOCH=1794700800	# 2026-11-15 00:00 UTC
