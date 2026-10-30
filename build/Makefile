# build/Makefile: host tests of the build framework, and the check of the
# packages directory.
#
# MIT licence, see LICENSE at the top of the repository.

.PHONY: test check-packages

test:
	python3 -I pkg/tests/test-pkgmeta
	python3 -I pkg/tests/test-pkgbuild

check-packages:
	sh pkg/check-packages
