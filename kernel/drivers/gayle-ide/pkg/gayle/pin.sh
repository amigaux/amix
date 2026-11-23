# pin.sh -- gayle-k30 / gayle-k46: the Gayle IDE driver of the A4000 and the
# A1200 (a pseudo SCSI host adapter under sd) as a ROOT-class kernel module (amix-dlm C3-5 sec 1,
# C4-2), by sha256.  Sourced by kdrv.sh.
#
# The objects are make dist's drivers step's: the fork at
# kernel/drivers/gayle-ide/gayle-ide.pin built with this checkout's kit into
# out/modules/<line>/gayle.  The licence and module/VERSION are the fork's, in
# out/cache/forks/gayle-ide/.
#
# Root class (match=mobo:gayle, rank=ide, unload=never), no majors (sd owns
# the disk majors), no depend=, kabi k30.1.2 / k46.1.2: loaded by the core's
# root pass before the root is mounted; kbootset composes it as a root
# record.  Parameters intr (1 default: interrupts after a self-test; 0
# polled), slave, debug, master, slaveunit, board (0 default: the Kickstart
# ROM decides; 1 A4000, 2 A1200, -1 never probe), limits (1 default: the C4-7
# limits on a kernel with the segment minor; 0 none); the package sets none
# (modreg: comments only, the module's defaults).
# 1.1.0-5 (2026-11-01): the module 1.1.0-3 (fork 24ed009), the same objects as
# the earlier 1.1.0-4, first rolled from amix.
# 1.1.0-6 (2026-11-01): the same module 1.1.0-3, built with the kit of toolchain
# pin gcc-2.7.2.3-33ebadc: the objects differ from 1.1.0-5 only in that tag.
# 1.1.0-7 (2026-11-02): the module 1.1.0-4 (fork d320430): the investigation
# symbols are built only with IDE_DIAG.
# 1.1.0-8 (2026-11-02): the module 1.1.0-5 (fork 3b72994): the A1200 port
# too, chosen by the Kickstart ROM's card.resource resident; param board.
# 1.1.0-9 (2026-11-04): the same module and objects; the copyright file's licence
# headings name the component, without the build path.
# 1.1.0-10 (2026-11-23): the module 1.1.0-6 (fork cff38a0): declares the C4-7
# limits after sd_register (one segment of up to 64 KiB a command, through
# idequeuex) on a kernel with the segment minor, param limits (1 default, 0
# none); whole sectors through an unrolled DATA loop.  Built and checked with
# the kit of amix 17cc5692 (k30.1.6 / k46.1.7); sd_limits is weak, so the
# module still needs only kabi k30.1.2 / k46.1.2.

KM_NAME=gayle
KM_SHORT=gayle
KM_REPO=kernel/drivers/gayle-ide
KM_VERSION=1.1.0-6
KM_PKG_VERSION=1.1.0-10
KM_VERSION_FILE=out/cache/forks/gayle-ide/module/VERSION

KM_K30_SHA=1574420dcec58da59509b45630fba57085561558f6d6778a89368a3b8755cc4d
KM_K46_SHA=abb85d4b3222232bf0677b2ea7d9d62db6df767603a39945fa120341f0dd2490

KM_KIT_COMMIT=17cc569212927c9bfd6a01ec71f5e6a2f759ff7e

KM_LICENCES="\
out/cache/forks/gayle-ide/LICENSE b2a9d95bb7959880868ac8f29fcb7268c02a9401597ba1d153b0055bdc5c9340"

KM_EXTRA_NOTE="The module drives the IDE port with interrupts by default on both lines:
at boot it self-tests the interrupt with one READ VERIFY and falls back to
polled I/O if the test fails.  The line \`param intr=0\` in
/etc/conf/modreg.local.d/gayle selects polled I/O.  The module drives the
Gayle IDE port of the A4000 and of the A1200: the Kickstart ROM's
card.resource resident picks the A1200, else the A4000; \`param board=1\`
(A4000) or \`param board=2\` (A1200) there picks one without reading the
ROM, and \`param board=-1\` never probes.  There is no A600 row.
On a kernel with the segment minor (k30.1.6, k46.1.7) the module declares
its limits, one segment of up to 64 KiB a command; \`param limits=0\`
declares none, and an older kernel answers the declaration with ENOSYS."

KM_SOURCE_EPOCH=1795392000	# 2026-11-23 00:00 UTC
