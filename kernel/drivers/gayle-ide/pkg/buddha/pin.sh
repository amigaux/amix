# pin.sh -- buddha-k30 (buddha30) / buddha-k46 (buddha46): the Buddha and
# Catweasel Z-II IDE driver (a pseudo SCSI host adapter under sd) as a
# ROOT-class kernel module (amix-dlm C3-5 sec 1, C4-2 sec 8.2), by sha256.
# Sourced by kdrv.sh.
#
# The objects are make dist's drivers step's: the fork at
# kernel/drivers/gayle-ide/gayle-ide.pin built with this checkout's kit into
# out/modules/<line>/buddha (the fork's build/buddha/<line>/mod.d/buddha).
# The licence and module/buddha/VERSION are the fork's, in
# out/cache/forks/gayle-ide/.
#
# Root class (match=zorro:1212:2a,mobo:buddha, rank=ide, unload=never), no
# majors (sd owns the disk majors), no depend=: mobo:buddha is the stand-in
# the 1.1 kits' motherboard registry lists, since the 1.1 module core refuses
# the Buddha's own key zorro:1212:00.  Parameters intr (1 default: interrupts
# after a self-test; 0 polled), slave, debug; the package sets none.
#
# Until gayle-ide.pin names a fork commit that has the module (the fork's
# release-1.1, 6003b68 or later), the pinned source has no module/buddha:
# KM_ONLY_IF_FILE then keeps the recipe out of the roll, and gayle's packages
# roll as before.
#
# 1.1.0-4 (2026-11-14): the first package.  Module 1.1.0-4 (fork 6003b68),
# built with the kit of amix 1a3e7797, whose motherboard registry lists
# buddha.  Needs kbootset 1.1.0.261113-44 or later; no kbootset= key, no
# depend.

KM_NAME=buddha
KM_SHORT=buddha
KM_REPO=kernel/drivers/gayle-ide
KM_VERSION=1.1.0-4
KM_VERSION_FILE=out/cache/forks/gayle-ide/module/buddha/VERSION
KM_ONLY_IF_FILE=$KM_VERSION_FILE

KM_K30_SHA=8720ae0ae9e08b2ae5bc0cbee656bcb4af1f7b72611d6d4043701d55cca95a44
KM_K46_SHA=da22bb8e18a5e002a35cec9bdb67279adb14207a10585c4e38c81adf805b3df2

KM_KIT_COMMIT=1a3e77979df2f22d613d715742e975e98fb2d5de

KM_LICENCES="\
out/cache/forks/gayle-ide/LICENSE b2a9d95bb7959880868ac8f29fcb7268c02a9401597ba1d153b0055bdc5c9340"

KM_EXTRA_NOTE="The module drives every Buddha (two ports) and Catweasel Z-II (three
ports) it finds, with interrupts by default: at boot it self-tests the
interrupt and falls back to polled I/O if the test fails, and goes polled for
good if interrupts stop later.  The line \`param intr=0\` in
/etc/conf/modreg.local.d/buddha selects polled I/O.  The SCSI units are fixed
per port and drive: 6 and 5, 3 and 2, 1 and 0."

KM_SOURCE_EPOCH=1794614400	# 2026-11-14 00:00 UTC
