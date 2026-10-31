# build/Makefile: make dist and its partial targets (dist.sh, P-38 S1.5), the
# host tests of the build framework, the selftests of the packaging harness
# (they need the cross toolchains: run them in the build container), and the
# check of the packages directories.
#
# MIT licence, see LICENSE at the top of the repository.

STEPS = dist tools kit kernel-k30 kernel-k46 modules drivers kspace userland catalogs media lock

.PHONY: $(STEPS) test selftests check-packages

# SYSTEM=<amix-system checkout> and LOCK=<lock of record> are passed on to
# dist.sh in the environment.
export SYSTEM LOCK

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
	python3 -I tests/test-dist
	python3 -I tests/test-lock

selftests:
	sh pkg/tests/run-selftests

check-packages:
	sh pkg/check-packages
