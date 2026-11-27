# build/Makefile: make dist and its partial targets (dist.sh), the
# host tests of the build framework, the selftests of the packaging harness
# (they need the cross toolchains: run them in the build container), and the
# check of the packages directories.
#
# MIT licence, see LICENSE at the top of the repository.

STEPS = dist tools kit kernel-k30 kernel-k46 modules drivers kspace userland apkg catalogs release media lock

.PHONY: $(STEPS) test selftests check-packages

# SYSTEM=<amix-system checkout>, LOCK=<lock of record>, VARIANT=shared
# (default) or static, the userland variant, and DIST_OUT=<directory>, the
# output tree in place of out/ (out/build, the packages, the caches), are
# passed on to dist.sh in the environment: two rolls at once each take a
# DIST_OUT of their own (make recipes/cde DIST_OUT=out/roll2).
# DIST_NETWORK=none runs the steps' containers with no network, every input
# from the caches.
export SYSTEM LOCK VARIANT DIST_OUT DIST_NETWORK

$(STEPS):
	sh dist.sh $@

recipes/% drivers/%:
	sh dist.sh $@

test:
	python3 -I pkg/tests/test-pkgmeta
	python3 -I pkg/tests/test-pkgbuild
	python3 -I pkg/tests/test-s5mark
	python3 -I pkg/tests/test-conffile
	python3 -I pkg/tests/test-dsnorm
	python3 -I pkg/tests/test-classes
	python3 -I pkg/tests/test-arnorm
	python3 -I pkg/tests/test-dlmsrc
	python3 -I pkg/tests/test-fetch
	python3 -I pkg/tests/test-kfsmod
	python3 -I pkg/tests/test-kmroot
	python3 -I pkg/tests/test-kdrv
	python3 -I pkg/tests/test-manpages
	python3 -I tests/test-dist
	python3 -I tests/test-nightly
	python3 -I tests/test-lock
	python3 -I tests/test-together
	sh hosttools/gencat/tests/run.sh

selftests:
	sh pkg/tests/run-selftests

check-packages:
	sh pkg/check-packages
