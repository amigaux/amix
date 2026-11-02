# pin.sh -- z3660scsi-k30 / z3660scsi-k46: the Z3660 SCSI driver (piscsi
# mailbox) as a root-class kernel module (amix-dlm C3-5 v4 sec 1, C4-2), by
# sha256.  Sourced by build.sh through kdrv.sh.
#
# The objects are built by make dist's drivers step in the build container
# (kernel/drivers/z3660scsi/module on the kit of each line) into
# out/modules/<line>/z3660scsi, kdrv's default KM_K30_OBJ / KM_K46_OBJ.
#
# Root class (match=zorro:144b:01,mobo:z3660-window, rank=z3660,
# unload=never, param=cache:int:-1:-1:60), no majors (sd owns the disk
# majors), no depend=, kabi k30.1.2 / k46.1.2: loaded by the core's root
# pass (marc_root) before the root is mounted; kbootset composes it as a
# root record.
# 1.0.0-2 (2026-10-27): the module arms its data cache from cputype at _load
# (always 0 on the k30 line), cache= overrides.
# 1.0.0-3 (2026-10-31): a package-only revision of the module's 1.0.0-2, the
# same object rolled without the pkginfo BASEDIR line (stock pkgadd refuses
# one).
# 1.0.0-4 (2026-11-01): a package-only revision, the same object and payload
# rolled in amix; the copyright file names kernel/drivers/z3660scsi.
# 1.0.0-5 (2026-11-01): the module's 1.0.0-2 rebuilt on the kit of
# gcc-cross-amix 33ebadc (toolchain.pin): the objects carry
# cc=gcc-2.7.2.3-33ebadc, which kernels built with that pin require.
# 1.0.0-6 (2026-11-02): the module's 1.0.0-3, the fixed window gated before
# its first write (no access over a boot memory region; a read-only bprobe).
# 1.0.0-7 (2026-11-02): the module's 1.0.0-4, an unmapped unit answers
# INQUIRY as no device (peripheral qualifier 3, type 0x1F).
# 1.0.0-8 (2026-11-02): the module's 1.0.0-5, the page-cross ring and the
# fault knob only with -DZ3660_DIAG; the empty units on one console line.

KM_NAME=z3660scsi
KM_SHORT=zscsi
KM_REPO=kernel/drivers/z3660scsi
KM_VERSION=1.0.0-5
KM_PKG_VERSION=1.0.0-8

KM_K30_SHA=365782774127d58d43b20ff8c96ecaa665efed326852a42c6be018ddf066b798
KM_K46_SHA=2e6f0e6befb42ac459328ed657ae30c2e266ea5c471a2d7cf0fdbb4c4f503d1c
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=94f1f0449b03ac4ec3c94833313639cd6d11e358

KM_LICENCES="\
kernel/drivers/z3660scsi/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
kernel/drivers/z3660scsi/NOTICE 54f12c73d44fbb45c3e6da53006b58463633711add15f9ba4ea162d91c459cc2"

KM_SOURCE_EPOCH=1793577600	# 2026-11-02 00:00 UTC
