#!/bin/sh
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# core-first-gate.sh (Gate 13) - refuse a `pkgadd -R` install of any
# non-`core` package into a target root that does not yet carry BOTH
# <root>/etc/passwd and <root>/etc/group.
#
# Why: libpkg clgrnam()/clpwnam() read <root>/etc/{group,passwd} under -R,
# but if those files are ABSENT they return NULL and the lookup silently
# falls back to the INSTALLING box's name service (getgrnam/getpwnam).
# On the bench that is correct BY COINCIDENCE (the box and the target
# share ids); from a miniroot whose ids differ it is silent mis-ownership.
# `core` is the one legitimate exception: it is the package that SHIPS
# /etc/passwd + /etc/group, so it must be installable into a bare root
# (the seed discipline pre-seeds them, but core itself establishes them).
#
# Portable Bourne sh - runs on the Amix box.
#
#   core-first-gate.sh <root> <pkg>
#
# Exit 0 = OK to install; non-zero = refused (fail-closed) or usage error.
root="$1"
pkg="$2"
[ -n "$root" ] && [ -n "$pkg" ] || {
	echo "usage: core-first-gate.sh <root> <pkg>" >&2; exit 2; }

if [ "$pkg" = core ]; then
	echo "core-first-gate: $pkg: OK (core establishes the name service)"
	exit 0
fi

miss=""
[ -f "$root/etc/passwd" ] || miss="$miss etc/passwd"
[ -f "$root/etc/group" ]  || miss="$miss etc/group"

if [ -n "$miss" ]; then
	echo "core-first-gate: REFUSING -R install of <$pkg> into <$root>:"
	echo "    target root lacks name service:$miss"
	echo "    install core first (or seed passwd+group) - fail-closed"
	exit 1
fi
echo "core-first-gate: $pkg: OK (target name service present)"
exit 0
