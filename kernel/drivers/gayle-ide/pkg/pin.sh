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
# ROM decides; 1 A4000, 2 A1200, -1 never probe); the package sets none
# (modreg: comments only, the module's defaults).
# 1.1.0-5 (2026-11-01): the module 1.1.0-3 (fork 24ed009), the same objects as
# the earlier 1.1.0-4, first rolled from amix.
# 1.1.0-6 (2026-11-01): the same module 1.1.0-3, built with the kit of toolchain
# pin gcc-2.7.2.3-33ebadc: the objects differ from 1.1.0-5 only in that tag.
# 1.1.0-7 (2026-11-02): the module 1.1.0-4 (fork d320430): the investigation
# symbols are built only with IDE_DIAG.
# 1.1.0-8 (2026-11-02): the module 1.1.0-5 (fork 3b72994): the A1200 port
# too, chosen by the Kickstart ROM's card.resource resident; param board.

KM_NAME=gayle
KM_SHORT=gayle
KM_REPO=kernel/drivers/gayle-ide
KM_VERSION=1.1.0-5
KM_PKG_VERSION=1.1.0-8
KM_VERSION_FILE=out/cache/forks/gayle-ide/module/VERSION

KM_K30_SHA=3b7c03dadca22706ee7b4d13d748aa02d3854fe98aa35306bedd0c52c572e62b
KM_K46_SHA=33504a56f68d09b5616ffc970276ca7ecc4f1664323538b638bb2ff6f10ee1db

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
out/cache/forks/gayle-ide/LICENSE b2a9d95bb7959880868ac8f29fcb7268c02a9401597ba1d153b0055bdc5c9340"

KM_EXTRA_NOTE="The module drives the IDE port with interrupts by default on both lines:
at boot it self-tests the interrupt with one READ VERIFY and falls back to
polled I/O if the test fails.  The line \`param intr=0\` in
/etc/conf/modreg.local.d/gayle selects polled I/O.  The module drives the
Gayle IDE port of the A4000 and of the A1200: the Kickstart ROM's
card.resource resident picks the A1200, else the A4000; \`param board=1\`
(A4000) or \`param board=2\` (A1200) there picks one without reading the
ROM, and \`param board=-1\` never probes.  There is no A600 row."

KM_SOURCE_EPOCH=1793577600	# 2026-11-02 00:00 UTC
