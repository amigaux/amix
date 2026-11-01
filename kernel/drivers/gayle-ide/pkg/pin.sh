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

KM_NAME=gayle
KM_SHORT=gayle
KM_REPO=kernel/drivers/gayle-ide
KM_VERSION=1.1.0-3
KM_PKG_VERSION=1.1.0-6
KM_VERSION_FILE=out/cache/forks/gayle-ide/module/VERSION

KM_K30_SHA=5833325d72f1fe4917a8cf3a0af835f5a9d0928bc8e2331d0f7c47dcff13d561
KM_K46_SHA=f0ad33a8dadef1dd5ff4e463aa448905a4ec7ad2ac8683e937be1360227927ce

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_LICENCES="\
out/cache/forks/gayle-ide/LICENSE b2a9d95bb7959880868ac8f29fcb7268c02a9401597ba1d153b0055bdc5c9340"

KM_EXTRA_NOTE="The module drives the IDE port with interrupts by default on both lines:
at boot it self-tests the interrupt with one READ VERIFY and falls back to
polled I/O if the test fails.  The line \`param intr=0\` in
/etc/conf/modreg.local.d/gayle selects polled I/O.  Only the A4000 Gayle is
driven (match mobo:gayle); the A1200/A600 rows are not in the module."

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
