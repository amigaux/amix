# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Jussi Alanärä <jussi@alanara.fi>
#
# userland/pkgtools/Makefile -- APKG and APKGENG through make dist (P-38 S4.2).
#
#   make dist [OUT=<dir>]   build the host engine, cross-build apkg,
#                           contents-fsck and the engine for Amix, and roll
#                           APKG-<ver>.pkg and APKGENG-<ver>.pkg into OUT
#                           (default <amix>/out/userland/pkgs), with
#                           tools/repo's deps/descs/names/cats.conf: the
#                           staging root's confs gen-catalog.py reads there
#                           (cats.conf declares the category vocabulary)
#   make repro-check        dist twice, from this checkout and from a
#                           `git archive` of HEAD at another path under
#                           another umask, and compare the bytes
#
# Each package rolls under its version's own epoch, pinned beside the
# version in tools/repo/build-packages.sh (EPOCH_APKG, EPOCH_ENG; P-38 D-b);
# the environment's SOURCE_DATE_EPOCH is never used.  The cross compiler is
# m68k-cbm-sysv4-gcc on PATH, as in the build container, or GCA naming
# gcc-cross-amix's build/ directory (its env.sh is sourced).

TOP := $(abspath ../..)
OUT ?= $(TOP)/out/userland/pkgs
STAGE ?= $(TOP)/out/build/pkgtools
GCA ?=
CROSS := $(if $(wildcard $(GCA)/env.sh),. $(GCA)/env.sh &&,)

.PHONY: dist engine-host cross repro-check

dist: engine-host cross
	rm -rf $(STAGE)
	bash tools/repo/build-packages.sh --apkg --eng $(STAGE)
	mkdir -p $(OUT)
	cp $(STAGE)/base/APKG-*.pkg $(STAGE)/base/APKGENG-*.pkg $(OUT)/
	cp tools/repo/deps.conf tools/repo/descs.conf tools/repo/names.conf \
		tools/repo/cats.conf $(OUT)/
	@cd $(OUT) && md5sum APKG-*.pkg APKGENG-*.pkg

engine-host:
	cd heirloom && ./build-host.sh

# the host engine first: both builds share heirloom's object directories,
# and each regenerates them
cross: engine-host
	@$(CROSS) command -v m68k-cbm-sysv4-gcc >/dev/null || { \
		echo "make dist: no m68k-cbm-sysv4-gcc: run in the build container or set GCA" >&2; exit 1; }
	$(CROSS) $(MAKE) -C src/apkg amix
	$(CROSS) $(MAKE) -C src/contents-fsck amix
	$(CROSS) cd heirloom && ./build-amix.sh

repro-check:
	GCA=$(GCA) bash tools/repo/dist-repro.sh
