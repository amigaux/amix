# pin.sh -- a4kt710-k30 / a4kt710-k46: the A4000T's onboard NCR 53C710 as a
# root-class kernel module (amix-dlm C3-5 sec 1, C4-2 v6 sec 8 and 8.1,
# C4-5), by sha256.  Sourced by kdrv.sh (pkg/build.sh).
#
# The a4091 driver's second module target: src/a4kt710.c includes
# src/a4091-wr.c with A4091_A4KT (module/a4kt710/, docs/A4000T-ONBOARD-710.md
# sec 10), the release in module/a4kt710/VERSION.  make dist's drivers step
# builds it beside a4091 into out/modules/<line>/a4kt710.
#
# Root class (match=mobo:a4000t-710, rank=mobo, unload=never), no majors (sd
# owns the disk majors), no depend=, kabi k30.1.2 / k46.1.2 (DDI 1.2 DMA).
# param declared:int:-1:-1:1 (C4-2 v6 sec 8.1): -1 the running Kickstart's
# cold-start "NCR scsi.device" ROM tag decides, 0 never touch the window at
# 0xDD0000, 1 touch it without the tag.  The package sets none.
# 1.0.0-1 and 1.0.0-2 (2026-10-27, 2026-10-31) were rolled outside amix;
# 1.0.0-2 carried module 1.0.0-1.
# 1.0.0-3 (2026-11-01): the same module 1.0.0-1, its objects byte-identical
# to 1.0.0-2's, rolled from amix: the copyright file names kernel/drivers/a4091
# and the A4000T metal boots, and the vendor is amix.

KM_NAME=a4kt710
KM_SHORT=a4kt710
KM_REPO=kernel/drivers/a4091
KM_VERSION=1.0.0-1
KM_PKG_VERSION=1.0.0-3
KM_VERSION_FILE=kernel/drivers/a4091/module/a4kt710/VERSION

KM_K30_SHA=e65b4f7d31881dc0299a88af60ebe7ca4d28cf4d86a3fa772e6fa5d27d86ff85
KM_K46_SHA=95bebecb6a8854423bb5180e2b9992d32cc586b9dceaf76f338fa1c6ff96ce2f
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=6cc5dbafd168138530da0d8601a42322abbc4da9

KM_LICENCES="\
kernel/drivers/a4091/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
kernel/drivers/a4091/NOTICE f37c3ca7dba3c5b572e961a2ce1bd67e13ecf2eed9f341221866dfafc8ca3f21"

KM_EXTRA_NOTE="The module drives the A4000T's onboard NCR 53C710 at 0xDD0000 and touches
nothing there unless the running Kickstart carries the A4000T's cold-start
NCR scsi.device ROM tag (amix-dlm C4-2 v6 sec 8.1), the chipset is AGA and
a read-only probe of the chip answers; otherwise it returns ENXIO, silent.
The parameter declared (default -1, the tag decides; 0 never; 1 without the
tag) overrides it: param declared=0 in /etc/conf/modreg.local.d/a4kt710
disables the controller.  On the 68030 line (a4kt710-k30) the DMA goes
through the module core's 030 provider, a bounce pool below 0x08000000:
kernel-k30-m -14 or later, boot2 at amix-dlm 4003c9f or later; it is not
supported with a Z3660 in 030 mode and is untested on metal.  On the
68040/68060 line (a4kt710-k46) the provider is the identity: an A4000T with
a Z3660 has booted with its root on the onboard bus through this module,
the DMA buffer in the Z3660's memory; a byte compare of that DMA is still
open (kernel/drivers/a4091/docs/A4000T-ONBOARD-710.md sec 10.6).  The
module is built from src/a4kt710.c and src/a4091-wr.c, part 1 of the NOTICE
below (MIT); none of the NOTICE's other parts is in the object."

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
