# Changelog

## 2026-10-30 — CI kit job (5b376ee)

CI fetches amix-system at system/amix-system.pin (62f7132) and checks it against MANIFEST.sha256 and SYMLINKS
(system/fetch-amix-system, system/check-amix-system), builds the toolchain container or loads it from the Actions
cache, then runs make kit, kit-test and both lines of every module in the container (container-kit.sh); kit digests
and module sha256 go to the step summary. Module bytes equal the main checkout's: monsw 1f53a31b/962709ca, ramdisk
5523d853/054467f6. container-build.sh uses check-amix-system. Not required for merges.
