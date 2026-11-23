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
# 1.0.0-10 (2026-11-02): module 1.0.0-7: no U77 byte-write probe, no
# a4091_dma_off knob (the D42 record's off is 0 for good), no last-command
# globals; the k46 attach line reads "a4091: board N at 0x...".
# 1.0.0-11 (2026-11-22): module 1.0.0-8: commands complete on the 53C710's
# interrupt (level 2) once a self-test after the root mount passes; param intr
# (1 default, 0 always polled); a watchdog falls back to polled.
# 1.0.0-12 (2026-11-22): module 1.0.0-9: declares the C4-7 limits after
# sd_register (one segment of up to 64 KiB through a4091queuex) on a kernel
# with the segment minor; param limits (1 default, 0 none).
# 1.0.0-13 (2026-11-23): module 1.0.0-10: param intr -1 (auto, the default) takes the
# interrupt only when the limits were accepted, else polls; on an A4000D the
# interrupt cost 2 KiB raw commands a quarter to a third of their speed.
# 1.0.0-14 (2026-11-23): module 1.0.0-11: param spin (0 default, off): on the
# interrupt path the queue reads the chip up to that many us after its launch
# and finishes a command that stopped there inline; param spinrd.  Auto turns
# the interrupt on only at the first command over 4 KiB (k46 -69 accepts the
# limits but still sends 4 KiB).
# 1.0.0-15 (2026-11-23): module 1.0.0-12: param sync (0 default): SDTR per
# target (100 ns, offset 8), asynchronous for good after a parity error or
# phase mismatch on a synchronous transfer or a parity error in the
# negotiation (the polled path reads the SSTAT0 latch).

KM_NAME=a4091
KM_SHORT=a4091
KM_REPO=kernel/drivers/a4091
KM_VERSION=1.0.0-12
KM_PKG_VERSION=1.0.0-15

KM_K30_SHA=81535b6f2a6f6a8020965da0baca4cfa4b85b2e44a54656828fe5f8476fd13d7
KM_K46_SHA=5888a6235421f6c7358a84d9c1ed1b67e2f28415e967d133c11158b73f60aaf4
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
kernel/drivers/a4091/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
kernel/drivers/a4091/NOTICE f37c3ca7dba3c5b572e961a2ce1bd67e13ecf2eed9f341221866dfafc8ca3f21"

KM_EXTRA_NOTE="On a kernel with the segment minor (k30.1.6, k46.1.7) the module declares
its limits after sd_register: the kernel may then send one segment of up
to 64 KiB a command; param limits=0 declares none.  Commands complete on
the 53C710's interrupt (level 2) when those limits were accepted (param
intr=-1, the default) and a self-test after the root mount passes; on a
kernel before that minor, with param intr=0 in
/etc/conf/modreg.local.d/a4091, or after interrupts stop, the module polls.
param intr=1 takes the interrupt whatever the command size.
On the 68030 line (a4091-k30) the module's DMA goes through the module
core's 030 DMA provider: a bounce pool in fast memory below 0x08000000,
which needs the boot loader of amix 1.1 or later.
Where no pool can be placed the provider gives no address, the module does
not arm the chip and the command fails.  The objects carry
cc=gcc-2.7.2.3-33ebadc, so they load on kernel-k30-m -68 or later (a4091-k30)
and kernel-k46-m -56 or later (a4091-k46), the kernels built with that
toolchain.  The module is built from src/a4091-wr.c, part 1 of the NOTICE
below (MIT); none of the NOTICE's other parts is in the object."

KM_SOURCE_EPOCH=1795305600	# 2026-11-22 00:00 UTC
