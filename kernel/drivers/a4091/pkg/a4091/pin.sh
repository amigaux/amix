# pin.sh -- a4091-k30 / a4091-k46: the A4091/A4092/A4770 SCSI driver (NCR
# 53C710) as a root-class kernel module (amix-dlm C3-5 sec 1, C4-2, C4-5), by
# sha256.  Sourced by kdrv.sh (pkg/build.sh).
#
# The objects are built by make dist's drivers step in the build container
# (kernel/drivers/a4091/module, both lines) into out/modules/<line>/a4091.
#
# Root class (match=zorro:0202:54,zorro:c0de:01,zorro:c0de:02, rank=zorro,
# unload=never), no majors (sd owns the disk majors), no depend=, kabi
# k30.1.2 / k46.1.2 (DDI 1.2's DMA names): loaded by the core's root pass
# before the root is mounted; kbootset composes it as a root record.
# 1.0.0-1 to 1.0.0-6 (2026-10-27 to 2026-10-31) were rolled outside amix;
# 1.0.0-6 carried module 1.0.0-5.
# 1.0.0-7 (2026-11-01): the same module 1.0.0-5, its objects byte-identical
# to 1.0.0-6's, rolled from amix: the copyright file names kernel/drivers/a4091
# and the vendor is amix.
# 1.0.0-8 (2026-11-01): the same module 1.0.0-5 and source, built with
# gcc-cross-amix 33ebadc: .moddata says cc=gcc-2.7.2.3-33ebadc, every other
# section equals 1.0.0-7's; for kernel-k30-m -68 and kernel-k46-m -56 or later.
# 1.0.0-9 (2026-11-02): module 1.0.0-6: the bus reset before a card's first
# command adds up the beam lines that passed, not the counter changes seen
# (on metal the same 254 ms; under Amiberry at cpu_speed=max no longer
# 53-72 s); new global a4091_busreset_chg.

KM_NAME=a4091
KM_SHORT=a4091
KM_REPO=kernel/drivers/a4091
KM_VERSION=1.0.0-6
KM_PKG_VERSION=1.0.0-9

KM_K30_SHA=9ca1b96cd8083de56bdaea9c55f8c12ca36a5074d245ce15e3a837e6211b75f3
KM_K46_SHA=c2d518e4eb59b0dafb3e45f07e3e652f5c0353c68558cd58d797821946d2e277
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
kernel/drivers/a4091/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
kernel/drivers/a4091/NOTICE f37c3ca7dba3c5b572e961a2ce1bd67e13ecf2eed9f341221866dfafc8ca3f21"

KM_EXTRA_NOTE="On the 68030 line (a4091-k30) the module's DMA goes through the module
core's 030 DMA provider: a bounce pool in fast memory below 0x08000000,
which needs the amix boot loader's boot2 at amix-dlm 4003c9f or later.
Where no pool can be placed the provider gives no address, the module does
not arm the chip and the command fails.  The objects carry
cc=gcc-2.7.2.3-33ebadc, so they load on kernel-k30-m -68 or later (a4091-k30)
and kernel-k46-m -56 or later (a4091-k46), the kernels built with that
toolchain.  The module is built from src/a4091-wr.c, part 1 of the NOTICE
below (MIT); none of the NOTICE's other parts is in the object."

KM_SOURCE_EPOCH=1793577600	# 2026-11-02 00:00 UTC
