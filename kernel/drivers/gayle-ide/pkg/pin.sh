# pin.sh -- gayle-k30 / gayle-k46: the A4000 Gayle IDE driver (a pseudo SCSI
# host adapter under sd) as a ROOT-class kernel module (amix-dlm C3-5 sec 1,
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
# polled), slave, debug, master, slaveunit; the package sets none (modreg:
# comments only, the module's defaults).
# 1.1.0-5 (2026-11-01): the module 1.1.0-3 (fork 24ed009), the same objects as
# the earlier 1.1.0-4, first rolled from amix.
# 1.1.0-6 (2026-11-01): the same module 1.1.0-3, built with the kit of toolchain
# pin gcc-2.7.2.3-33ebadc: the objects differ from 1.1.0-5 only in that tag.
# 1.1.0-7 (2026-11-02): the module 1.1.0-4 (fork d320430): the investigation
# symbols are built only with IDE_DIAG.

KM_NAME=gayle
KM_SHORT=gayle
KM_REPO=kernel/drivers/gayle-ide
KM_VERSION=1.1.0-4
KM_PKG_VERSION=1.1.0-7
KM_VERSION_FILE=out/cache/forks/gayle-ide/module/VERSION

KM_K30_SHA=afbf757f081f413c60382d2c3ddf7512f6e027627b96cd2201e3f55b651916fb
KM_K46_SHA=eb35c041eb3c49ce21a2c079a5c413b4a6d6809d7868a801d03f917e1bb25baa

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
out/cache/forks/gayle-ide/LICENSE b2a9d95bb7959880868ac8f29fcb7268c02a9401597ba1d153b0055bdc5c9340"

KM_EXTRA_NOTE="The module drives the IDE port with interrupts by default on both lines:
at boot it self-tests the interrupt with one READ VERIFY and falls back to
polled I/O if the test fails.  The line \`param intr=0\` in
/etc/conf/modreg.local.d/gayle selects polled I/O.  Only the A4000 Gayle is
driven (match mobo:gayle); the A1200/A600 rows are not in the module."

KM_SOURCE_EPOCH=1793577600	# 2026-11-02 00:00 UTC
