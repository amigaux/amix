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
# 1.0.0-8 (2026-11-04): the same module 1.0.0-4, objects unchanged: the
# copyright note says what is known in plain words.
# 1.0.0-9 (2026-11-22): module 1.0.0-5: commands complete on the 53C710's
# interrupt (level 2) once a self-test after the root mount passes; param intr
# (1 default, 0 always polled); a watchdog falls back to polled.

KM_NAME=a4kt710
KM_SHORT=a4kt710
KM_REPO=kernel/drivers/a4091
KM_VERSION=1.0.0-5
KM_PKG_VERSION=1.0.0-9
KM_VERSION_FILE=kernel/drivers/a4091/module/a4kt710/VERSION

KM_K30_SHA=d53be43b228b800fc04f830a9911981efa8364dacbf2b0db727c7e66929b05b0
KM_K46_SHA=688b73f02904a789f7011c565d5d73cd37cc42a20968bdd5f56862bee1e4cfb4
KM_K30_DEPS=
KM_K46_DEPS=

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
kernel/drivers/a4091/LICENSE 20e6022dcc8109f79734098db83e2e3d22b72b342a628da822d4fbec44af74b4
kernel/drivers/a4091/NOTICE f37c3ca7dba3c5b572e961a2ce1bd67e13ecf2eed9f341221866dfafc8ca3f21"

KM_EXTRA_NOTE="The module drives the A4000T's onboard NCR 53C710 at 0xDD0000 and touches
nothing there unless the running Kickstart carries the A4000T's cold-start
NCR scsi.device ROM tag, the chipset is AGA and a read-only probe of the
chip answers; otherwise it returns ENXIO, silent.  The parameter declared
(default -1, the tag decides; 0 never; 1 without the tag) overrides that
tag: param declared=0 in /etc/conf/modreg.local.d/a4kt710 disables the
controller.  A Kickstart with a card.resource ROM tag (every A1200 and A600
one) is refused before any access, whatever declared says.  On the 68030
line (a4kt710-k30) the DMA goes through the module core's 030 provider, a
bounce pool below 0x08000000, which needs the boot loader of amix 1.1 or
later.  That form is not supported with a Z3660 in 030 mode, and it has run
only under emulation, never on a real machine.  On the 68040/68060 line
(a4kt710-k46) the chip's DMA goes straight to memory, with no bounce pool.
With module 1.0.0-1, an A4000T with a Z3660 booted with its root on the onboard
bus, the DMA buffer in the Z3660's memory, and raw reads of 16 MiB through
that bus matched the host's checksum of the disk.  Commands complete on the
53C710's interrupt (level 2) once a self-test after the root mount passes;
until then, with param intr=0, or after interrupts stop, the module polls.
The objects carry
cc=gcc-2.7.2.3-33ebadc, so they load on kernel-k30-m -68 or later
(a4kt710-k30) and kernel-k46-m -56 or later (a4kt710-k46).  The module is
built from src/a4kt710.c and src/a4091-wr.c, part 1 of the NOTICE below
(MIT); none of the NOTICE's other parts is in the object."

KM_SOURCE_EPOCH=1795305600	# 2026-11-22 00:00 UTC
