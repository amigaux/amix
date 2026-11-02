# pin.sh -- z3660eth-k30 (zeth30) / z3660eth-k46 (zeth46): the Z3660
# ethernet driver as a kernel module (amix-dlm C3-5 sec 1), by sha256.
# Sourced by build.sh through build/pkg/common/kdrv.sh.
#
# The objects are make dist's drivers step's, out/modules/<line>/z3660eth,
# built in the build container from kernel/drivers/z3660eth/module.
# Boot class (match=zorro:144b:01,mobo:z3660-window, majors=c:51), no
# depend=.  The package ships the driver's link.d entry for ifup and the node
# /dev/zen0 (c 51 0, mode 0600) in the module's class, z3660eth.
#
# 1.0.0-10 (2026-11-01): the first roll from amix.  Module 1.0.0-5; the
# objects are 1.0.0-9's, byte for byte (af24613d / 86fe050b), and so are the
# link.d entry, the node and modreg; the package files (vendor amix, the
# descriptions, the licence paths, the epoch) are new, hence the revision.
# 1.0.0-11 (2026-11-01): the objects rebuilt on the kit of f5678ba, whose
# PIN is gcc-cross-amix 33ebadc (.moddata cc=gcc-2.7.2.3-33ebadc; module
# kernels from k30 -68 and k46 -56 refuse an 8949028 module).  Module
# 1.0.0-5, source unchanged; built in amix-toolchain:gca-33ebadc.  The
# package files are -10's but for the revision.
# 1.0.0-12 (2026-11-02): module 1.0.0-6, the fixed-window probe guarded by
# bprobe (a box without a Z3660 gets ENXIO, not a bus error, in _load), and
# the MAC probe checks MAC_HI's shape (no open-bus pattern passes).
# Built in amix-toolchain:dist at amix 8653b72 (gcc-cross-amix 33ebadc).

KM_NAME=z3660eth
KM_SHORT=zeth
KM_REPO=kernel/drivers/z3660eth
KM_VERSION=1.0.0-6
KM_PKG_VERSION=1.0.0-12

KM_K30_SHA=149582a65af09e81cd1eda4416f23cdff4e7749d90ccb13c527f99cd8f7032c4
KM_K46_SHA=46df59d84caee64123d7045c37123a401848ef51478d37a7f7607aea1cca710f
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
kernel/drivers/z3660eth/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
kernel/drivers/z3660eth/NOTICE f7c22823715ccb1c30e4d8ae35e18051275cd79ef545bbc7cac2e58eececbc46"

# the driver's link.d entry, vendor data for ifup, shipped verbatim
KM_FILES_COMMON="\
/etc/inet/link.d/z3660eth kernel/drivers/z3660eth/link.d/z3660eth 0d2586e039aecf82860436186bef761a057e05887477706df1674bfb21c143c7 0444"

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
