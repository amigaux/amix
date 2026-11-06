# kernel/k30 host self-tests: no Amiga and no cross compiler needed. Cases that need an
# input from outside this repository (AMIX_SYSTEM, CDFS, a driver checkout) skip and say so.

.PHONY: test
test:
	python3 tools/arena8m-selftest.py
	sh tests/swapguard/run.sh
	sh tests/segvnprot/t_forkst.sh
	sh tests/segvnprot/t_corechk.sh
	python3 -I tests/amixrun/test.py tools/amixrun.py
	tools/kpatch-selftest.sh
	tools/fstype-selftest.sh
	python3 tools/elf2brel-selftest.py
	python3 tools/relsim.py --selftest
	python3 tools/mksym030.py --selftest
	python3 tools/kinfo-cdevsw.py --selftest
	python3 tools/kabi-sidecar030.py --selftest
	python3 tools/rwippc030.py --selftest
	python3 tools/growsdt030.py --selftest
	python3 tools/check-chain-stamp.py --selftest
	python3 tools/kernel-rootdev-stamp.py --selftest
	python3 tools/kernel-cputype-stamp.py --selftest
	python3 tools/kernel-sddevsize-inject.py --selftest
	python3 tools/kernel-support-probe-inject.py --selftest
	python3 tools/k0-gates.py --selftest
	sh tools/cuts-selftest.sh
