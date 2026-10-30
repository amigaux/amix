# Changelog

## 2026-10-30 — the 68030 cross cut; drivers from kernel/drivers (bc6cc64 … 18d2dce)

The host cross build of the 68030 kernel moved in as new commits: build-cross-kernel.sh, kernel-patches.conf and
kpatch-lib, fstypes.conf and fstype-lib, dlm-core-link with the halt and marc_root shims (a missing shim FAILs step 7),
elf2brel, mksym030, kinfo-cdevsw, the kabi sidecar, relsim, bootchain-verify and the boot-chain contract v1; stock
bases come from the AMIX_SYSTEM input. Drivers come from kernel/drivers (--drivers/AMIX_DRIVERS only as an override);
docs/driver-contract.md documents kernel-patches.conf. The -22 reference cut rebuilds byte-identically from amix alone:
unix 3a02c257, unix.brel 4b4aefc1, kabi 19c04ef0, ufs 64c99884, s5 f7a74b73. make -C kernel/k30 test runs the self-tests.

## 2026-10-30 — moved in from amix-kerntools (public part)

jusii/amix-kerntools release-master 578ff79 (5 commits) moved in by subtree merge after a filter-repo rewrite: CLAUDE.md
dropped, AGENTS.md renamed docs/driver-contract.md, 578ff79 pruned as empty; 4 commits, old→new map in
docs/history-map.txt. privacy-check --all: 0 hits (was 3, class 2). The on-box build hub: amix-build, onbox-build, the
clean-kernel gate, relsim, checkunix; the k30 cross cut follows.
