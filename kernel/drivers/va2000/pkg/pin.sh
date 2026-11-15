# pin.sh -- va2000-k30 (va200030) / va2000-k46 (va200046): /dev/va2000, the
# MNT VA2000 RTG graphics card's registers and framebuffer for programs, as a
# DEMAND-class kernel module (amix-dlm C3-5 sec 1, C3-6), by sha256.
# Sourced by build.sh through build/pkg/common/kdrv.sh.
#
# The objects are make dist's drivers step's: the fork at
# kernel/drivers/va2000/va2000.pin (Antti Sokero's va2000-amix, MIT) built
# with this checkout's kit into out/modules/<line>/va2000.  The licence,
# module/VERSION, the manual page and src/va2000.h are the fork's, in
# out/cache/forks/va2000/.
#
# Demand class (majors=c:68, unload=never, no depend=), kabi k30.1.2 /
# k46.1.2: it loads on the 1.1 kernels.  On k46 its fb_register (DDI
# k46.1.6) is a weak reference: the framebuffer gets the fast cache class on
# a kernel that offers it and keeps the default class otherwise.  Major c 68
# is va2000's in the amix-dlm registry; a kbootset whose registry lacks it
# (before 1.1.0.261115-46) refuses the boot set, and apkg on 1.1 has no key
# for a module's kbootset floor, so pkginfo's descriptions say so.  The node
# /dev/va2000 (c 68 0, 0666, as the fork's static install makes it) ships as
# a device entry in class va2000.  No parameters (modreg: comments only).
# Beside the module the package ships the driver's interface header for
# programs, /usr/include/va2000.h, the page va2000(7) and its whatis line.
# 1.1.0-1 (2026-11-15): the first package.  Module 1.1.0-1 (fork dbb5b4f),
# built in amix-toolchain:dist against the kit of amix 09b89ffb (kabi
# k30.1.5 / k46.1.6, gcc-cross-amix 33ebadc).

KM_NAME=va2000
KM_SHORT=va2000
KM_REPO=kernel/drivers/va2000
KM_VERSION=1.1.0-1
KM_VERSION_FILE=out/cache/forks/va2000/module/VERSION

KM_K30_SHA=2307fed3e4890e03345ce8fc7c16f25c4dd6ab4c6ce2ea1ef6266c76d2e042ff
KM_K46_SHA=402b5f7136e6ca3607a9e58575a6be06cab57e80e351123ac148fc30728e90ea

KM_KIT_COMMIT=09b89ffba4d40c771d43ef47bef967eed96b5c70

_va=out/cache/forks/va2000
KM_FILES_COMMON="\
/usr/include/va2000.h $_va/src/va2000.h 65fb8d77fe3ab6a4dd4968767f4276080419a0d5c740e1fda29ebe73f4955e79 0644
/opt/amix/man/7/va2000 $_va/module/man/va2000.7 78c614ea0b8346b79662f89cf39d165377e2881cd2f4dbe74f5bce4ae461aee0 0644
/opt/amix/man/whatis.d/@PKG@ kernel/drivers/va2000/pkg/va2000.whatis 997b62278929d9be63788ba6725be0ee92515f7856476cd044f279148662773f 0644"

KM_LICENCES="\
$_va/LICENSE 1126322e2cc8d165adc4c792eeb195717de2bcc7b39be1ce77959d78e87ef685"

KM_EXTRA_NOTE="va2000 is Antti Sokero's MNT VA2000 driver for Amiga UNIX (va2000-amix,
MIT, copyright (c) 2025-2026 Antti Sokero), built as a loadable module from
our fork of it, https://github.com/amigaux/va2000-amix, at the commit
kernel/drivers/va2000/va2000.pin of the amix repository names.  It is a
demand-class module: it loads at the first open of /dev/va2000 and stays
only when it finds a board.  It needs a kbootset whose registry has
character major 68 (kbootset 1.1.0.261115-46 or later).
/usr/include/va2000.h is the driver's interface for programs; the page is
va2000(7)."

KM_SOURCE_EPOCH=1794700800	# 2026-11-15 00:00 UTC
