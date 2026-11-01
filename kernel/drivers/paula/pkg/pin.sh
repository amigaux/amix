# pin.sh -- paula-k30 / paula-k46: /dev/paula, Paula's four audio channels
# driven register by register and replayed by CIA-A timer B, as a
# DEMAND-class kernel module (amix-dlm C3-5 sec 1, C3-6), by sha256.
# Sourced by kdrv.sh.
#
# The objects are make dist's drivers step's: the fork at
# kernel/drivers/paula/paula.pin (isoriano1968's paula-amix with our
# changes, MIT) built with this checkout's kit into out/modules/<line>/paula.
# The licence, module/VERSION and include/paula.h are the fork's, in
# out/cache/forks/paula/.
#
# Demand class (majors=c:54, unload=allowed, no depend=), kabi k30.1.3 /
# k46.1.3: it imports the names of DDI minor 3 (AllocMem, FreeMem,
# displaytype, and the patched audio driver's paula_busy and audio_nopen),
# so it needs a module kernel of kabi minor 3 or later.  Major c 54 is
# paula's in the amix-dlm registry.  The node /dev/paula (c 54 0, 0660 root
# audio) ships as a device entry in class paula; amix-base makes the group
# audio and is the package's depend.  While /dev/paula is open the patched
# audio driver refuses /dev/audio, and the other way round.  Parameters
# clock, maxarea and ring; the package sets none (modreg: comments only).
# Beside the module the package ships the driver's interface header for
# programs, /usr/include/paula.h.
# 1.1.0-2 (2026-11-01): the module 1.1.0-1 (fork a111e57), built with the
# gcc-2.7.2.3-33ebadc kit, first rolled from amix.

KM_NAME=paula
KM_SHORT=paula
KM_REPO=kernel/drivers/paula
KM_VERSION=1.1.0-1
KM_PKG_VERSION=1.1.0-2
KM_VERSION_FILE=out/cache/forks/paula/module/VERSION

KM_K30_SHA=5db201d7df21e9ec06b097416857afee88db9d6e9ae59a36fc1823603922d858
KM_K46_SHA=cb371bdef75b14064321dfc24b96ebdcb5a064a065fc470268947162cecd7781

KM_KIT_COMMIT=f5678baccb09dad7aa3cba4b193f4d371777aa9e

KM_FILES_COMMON="\
/usr/include/paula.h out/cache/forks/paula/include/paula.h 4874d7eb5896b358795204654d88d9e9d7d87da4087f9f791755e2e45bed5d99 0644"

KM_LICENCES="\
out/cache/forks/paula/LICENSE eb1fe549d8e6a1b8b8c06fad944d67433df01477c75ff420ce11ee3ef110867a"

KM_EXTRA_NOTE="paula is isoriano1968's /dev/paula driver for Amiga UNIX (paula-amix, MIT)
with our changes, built as a loadable module.  It is a demand-class module:
it loads at the first open of /dev/paula, which members of the group audio
may open (0660 root audio).  Its parameters clock, maxarea and ring are in
/etc/conf/modreg.d/paula.  While /dev/paula is open, /dev/audio refuses
its open, and while /dev/audio has a client, /dev/paula refuses its open
(the module kernel's audio driver carries the patch).  It needs a module
kernel of kabi minor 3 or later.  /usr/include/paula.h is the driver's
interface for programs."

KM_SOURCE_EPOCH=1793491200	# 2026-11-01 00:00 UTC
