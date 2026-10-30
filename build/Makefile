# build/Makefile: host tests of the build framework, the selftests of the
# packaging harness (they need the cross toolchains: run them in the build
# container), and the check of the packages directory.
#
# MIT licence, see LICENSE at the top of the repository.

.PHONY: test selftests check-packages

test:
	python3 -I pkg/tests/test-pkgmeta
	python3 -I pkg/tests/test-pkgbuild
	python3 -I pkg/tests/test-s5mark
	python3 -I pkg/tests/test-conffile

selftests:
	sh pkg/tests/run-selftests

check-packages:
	sh pkg/check-packages
