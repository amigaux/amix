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
# 1.0.0-4 (2026-11-01): the same module 1.0.0-1 and source, built with
# gcc-cross-amix 33ebadc: .moddata says cc=gcc-2.7.2.3-33ebadc, every other
# section equals 1.0.0-3's; for kernel-k30-m -68 and kernel-k46-m -56 or later.
# 1.0.0-5 (2026-11-02): module 1.0.0-2: a4091-wr.c's bus reset before the
# first command adds up the beam lines that passed, not the counter changes
# seen (on metal the same 254 ms; under an emulator that runs the CPU in
# bursts no longer most of a minute).
# 1.0.0-6 (2026-11-02): module 1.0.0-3: no U77 byte-write probe, no
# a4091_dma_off knob (the D42 record's off is 0 for good), no last-command
# globals; the k46 attach line reads "a4kt710: board 0 at 0xdd0000".
# 1.0.0-7 (2026-11-02): module 1.0.0-4: a Kickstart with a card.resource ROM
# tag (A1200, A600) is refused before any $DD access, even with declared=1;
# declared=1 now reads the Kickstart once for that tag.

KM_NAME=a4kt710
KM_SHORT=a4kt710
KM_REPO=kernel/drivers/a4091
KM_VERSION=1.0.0-4
KM_PKG_VERSION=1.0.0-7
KM_VERSION_FILE=kernel/drivers/a4091/module/a4kt710/VERSION

KM_K30_SHA=04ec15f0c083fec6bb8ad7221780745a0f958588ea92136d2623ff5aab9027b1
KM_K46_SHA=a5546a47e9b80b7426dda79be2f7acaa474e0f446ce803920f81a7ad9c658eee
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
kernel/drivers/a4091/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
kernel/drivers/a4091/NOTICE f37c3ca7dba3c5b572e961a2ce1bd67e13ecf2eed9f341221866dfafc8ca3f21"

KM_EXTRA_NOTE="The module drives the A4000T's onboard NCR 53C710 at 0xDD0000 and touches
nothing there unless the running Kickstart carries the A4000T's cold-start
NCR scsi.device ROM tag (amix-dlm C4-2 v6 sec 8.1), the chipset is AGA and
a read-only probe of the chip answers; otherwise it returns ENXIO, silent.
The parameter declared (default -1, the tag decides; 0 never; 1 without the
tag) overrides that tag: param declared=0 in /etc/conf/modreg.local.d/a4kt710
disables the controller.  A Kickstart with a card.resource ROM tag (every
A1200 and A600 one) is refused before any access, whatever declared says.  On the 68030 line (a4kt710-k30) the DMA goes
through the module core's 030 provider, a bounce pool below 0x08000000
(boot2 at amix-dlm 4003c9f or later); it is not supported with a Z3660 in
030 mode and is untested on metal.  On the
68040/68060 line (a4kt710-k46) the provider is the identity: an A4000T with
a Z3660 has booted with its root on the onboard bus through this module,
the DMA buffer in the Z3660's memory; a byte compare of that DMA is still
open (kernel/drivers/a4091/docs/A4000T-ONBOARD-710.md sec 10.6).  The
objects carry cc=gcc-2.7.2.3-33ebadc, so they load on kernel-k30-m -68 or
later (a4kt710-k30) and kernel-k46-m -56 or later (a4kt710-k46).  The
module is built from src/a4kt710.c and src/a4091-wr.c, part 1 of the NOTICE
below (MIT); none of the NOTICE's other parts is in the object."

KM_SOURCE_EPOCH=1793577600	# 2026-11-02 00:00 UTC
